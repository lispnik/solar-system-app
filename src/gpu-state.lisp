;;;; gpu-state.lisp -- what the renderer keeps between frames.
;;;;
;;;; The renderer is several files; this one is loaded first, because the
;;;; others share what is here: the Metal objects once made, the buffers,
;;;; the layout of the one buffer of lines, and the macros that write floats
;;;; into memory the GPU reads. The whole of it, file by file:
;;;;
;;;;   shaders.lisp   the Metal Shading Language, one string, compiled at run time
;;;;   metal.lisp     the device, the pipelines, the maps, the buffers: once
;;;;   belt.lisp      the asteroid belt, placed by the GPU
;;;;   bodies.lisp    where each disc goes and how big, and the rings
;;;;   orbits.lisp    the orbits, the moons' orbits and the comets' lines
;;;;   view.lisp      following, and from the screen to the scene and back
;;;;   frame.lisp     one frame, encoded; the MTKView and its delegate
;;;;
;;;; An MTKView whose delegate is a Lisp class. Every frame, drawInMTKView:
;;;; asks the clock what time it is, places the bodies, compresses them into
;;;; the scene, and encodes instanced draws: a disc per body, a sphere to the
;;;; depth buffer and, where there is a map, textured and turned by the
;;;; body's own axes (rotation.lisp); rings, flat in their planets'
;;;; equators; the asteroid belt, a point each; and the lines -- orbits,
;;;; trails, tails -- as thick antialiased quads, each relative to a centre.
;;;; The orbits and bodies are in scene coordinates (projection.lisp); the
;;;; camera (camera.lisp) arrives as a view and a projection matrix, so a
;;;; gesture changes two matrices and nothing on the GPU is rebuilt. Lines
;;;; and discs are sized in pixels after projection, so they stay crisp at
;;;; any zoom.

(in-package #:solar-system)

(defparameter +segments+ 256 "Line segments per orbit.")

;;; state

(defvar *device* nil)
(defvar *queue* nil)
(defvar *orbit-pipeline* nil)
(defvar *disc-pipeline* nil)
(defvar *view* nil "The MTKView.")

;;; The lines drawn, each +SEGMENTS+ long, in slots of the one buffer: the
;;; Sun's family's orbits, the moons' (relative to their planets), a trail
;;; for each of the Sun's family, and spare slots for what comes after.
(defparameter +spare-lines+ 24 "Two sky circles, and each comet's orbit and tail.")

(defun orbiters () (append (heliocentric-bodies) *moons*))
(defun line-count () (+ (length (orbiters)) (length (heliocentric-bodies)) +spare-lines+))
(defun trail-slot (index) (+ (length (orbiters)) index))
(defun spare-slot (index) (+ (length (orbiters)) (length (heliocentric-bodies)) index))

(defvar *orbit-buffer* nil
  "An MTLBuffer of float4, (+SEGMENTS+ + 1) per orbiter: the heliocentric
orbits in the scene, the moons' relative to their planets.")
(defvar *orbit-key* nil "(exponent tc) the heliocentric orbits were drawn for.")
(defvar *moon-orbit-key* nil "(scales tc frame) the moons' orbits were drawn for.")
(defvar *scales* nil "MOON-SYSTEM-SCALES, kept with the heliocentric orbits.")

;;; Small per-frame data goes through setVertexBytes: from these, allocated
;;; once. Metal copies them at encode time, so one block each is enough.
(defvar *uniforms* nil)     ; 40 floats: view, projection, viewport w h, line width, pad, sun xyzw
(defvar *discs* nil)        ; 24 floats a body (struct Disc), this frame's buffer's contents
(defvar *disc-buffers* nil "Three MTLBuffers of discs, a frame each in turn, so
the CPU never writes one the GPU may still be reading.")
(defvar *disc-buffer* nil "This frame's.")
(defparameter +max-discs+ 64)
(defvar *orbit-info* nil)   ; 12 floats a line: r g b a, centre x y z 0, style x y 0 0

(defvar *camera* (make-camera))
(defvar *sky-mode* nil "Seen from the Earth's centre (sky.lisp), or from outside.")
(defvar *small-bodies-on* t "The comets and the asteroid belt.")
(defvar *pointing* nil "Stood where the phone is, the view turned with it (pointer.lisp).")
(defvar *pointer-button* nil)
(defvar *belt-pipeline* nil)
(defvar *belt-buffer* nil "The asteroids' elements, eight floats each, from asteroids.bin.")
(defvar *belt-count* 0)
(defvar *belt-data* nil "16 floats: struct Belt.")

(defun comet-orbit-slot (index) (spare-slot (+ 2 index)))
(defun comet-tail-slot (index) (spare-slot (+ 2 (length *comets*) index)))
(defvar *focus* nil "The body the camera follows, if any.")
(defvar *last-placed* nil "PLACE-BODIES' answer for the last frame drawn.")
(defvar *frame-count* 0)
(defparameter +uniform-bytes+ 160)
(defparameter +disc-floats+ 24)
(defvar *ring-pipeline* nil)
(defvar *ring-data* '() "Ringed planet -> its 24 floats (struct Ring), allocated once.")
(defvar *depth-writing* nil "Depth test and write: the bodies and the rings.")
(defvar *depth-testing* nil "Depth test only: the orbits, which bodies hide.")
(defvar *maps* (make-array 10 :initial-element nil) "The planet maps, by texture index.")
(defvar *ring-map* nil)

(defparameter +maps+
  '(("Sun" . "sun") ("Mercury" . "mercury") ("Venus" . "venus") ("Earth" . "earth")
    ("Moon" . "moon") ("Mars" . "mars") ("Jupiter" . "jupiter") ("Saturn" . "saturn")
    ("Uranus" . "uranus") ("Neptune" . "neptune"))
  "Body and map, in texture order: Solar System Scope's, CC BY 4.0.")

(defparameter +rings+
  '(("Saturn" 0 74500d0 140220d0)       ; the map's edges: the C ring's inside to the F ring
    ("Uranus" 1 41700d0 51300d0))       ; just inside ring 6 to just outside epsilon
  "Ringed planets: name, style (0 map, 1 radii in the shader), inner and outer km.")
(defvar *failure* nil "The condition that stopped drawing, if one has.")

(defun nothing-p (object)
  "Is OBJECT nil, whichever way the bridge said so?"
  (or (null object)
      (and (cffi:pointerp object) (cffi:null-pointer-p object))))

(defmacro store-floats (pointer offset &rest values)
  "Write VALUES as single floats from OFFSET on: open-coded, so that the
thousands of writes a frame can make cons no argument lists."
  (let ((p (gensym)) (o (gensym)))
    `(let ((,p ,pointer) (,o ,offset))
       (declare (type fixnum ,o))
       ,@(loop for value in values
               for i from 0
               collect `(setf (cffi:mem-aref ,p :float (+ ,o ,i)) (float ,value 1.0))))))

(defun smoothstep (from to x)
  (let ((u (max 0d0 (min 1d0 (/ (- x from) (- to from))))))
    (* u u (- 3 (* 2 u)))))

(defmacro store-orbit (contents slot points (x y z) &body transform)
  "The COUNT+1 points of one orbit, x y z triples, into SLOT of the orbit
buffer, each through TRANSFORM, a form of X Y Z answering three values."
  (let ((base (gensym)) (i (gensym)) (v (gensym)))
    `(let ((,base (* ,slot 4 (1+ +segments+)))
           (,v ,points))
       (declare (type (simple-array double-float (*)) ,v) (type fixnum ,base))
       (dotimes (,i (1+ +segments+))
         (let ((,x (aref ,v (* 3 ,i))) (,y (aref ,v (+ 1 (* 3 ,i)))) (,z (aref ,v (+ 2 (* 3 ,i)))))
           (multiple-value-bind (,x ,y ,z) (progn ,@transform)
             (store-floats ,contents (+ ,base (* 4 ,i)) ,x ,y ,z 1)))))))

(defun store-line (slot r g b a cx cy cz &optional (fade 0) (width 0))
  (store-floats *orbit-info* (* 12 slot) r g b a cx cy cz 0 fade width 0 0))

(defun store-matrix (pointer offset matrix)
  (dotimes (i 16)
    (setf (cffi:mem-aref pointer :float (+ offset i)) (float (aref matrix i) 1.0))))
