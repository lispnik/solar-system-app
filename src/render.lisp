;;;; render.lisp -- Metal, from Lisp: the Sun, the planets, the dwarf planets
;;;; and the major moons, and their orbits.
;;;;
;;;; An MTKView whose delegate is a Lisp class. Every frame, drawInMTKView:
;;;; asks the clock what time it is, places thirty-four bodies, compresses
;;;; them into the scene, and encodes two instanced draws: the orbits as
;;;; thick antialiased lines, a quad per segment, each orbit relative to a
;;;; centre -- the Sun, or a moon's planet; then a disc per body, lit from
;;;; the Sun, farthest first. The shaders are a string compiled at run time,
;;;; as in the compute example.
;;;;
;;;; The orbits and bodies are in scene coordinates (projection.lisp); the
;;;; camera (camera.lisp) arrives as a view and a projection matrix, so a
;;;; gesture changes two matrices and nothing on the GPU is rebuilt. Lines
;;;; and discs are sized in pixels after projection, so they stay crisp at
;;;; any zoom.

(in-package #:solar-system)

(defparameter +segments+ 256 "Line segments per orbit.")

(defparameter +shaders+ "
#include <metal_stdlib>
using namespace metal;

#define SEGMENTS ~d

struct Uniforms { float4x4 view; float4x4 proj; float2 viewport; float line_width; float pad; float4 sun; };
struct Disc { float4 position; float4 colour; float4 extra; };  // position.w: radius in pixels; extra.x: glow

struct DiscVarying {
  float4 position [[position]];
  float2 local;
  float radius;
  float glow;
  float4 colour;
  float3 light;
};

// Behind the camera: a point off screen, so the quad has no area.
constant float4 nowhere = float4(2.0, 2.0, 0.5, 1.0);

vertex DiscVarying disc_vertex(uint vid [[vertex_id]], uint iid [[instance_id]],
                               constant Disc *discs [[buffer(0)]],
                               constant Uniforms &u [[buffer(1)]])
{
  Disc d = discs[iid];
  DiscVarying out;
  out.radius = d.position.w;
  out.glow = d.extra.x;
  out.colour = d.colour;
  float4 eye = u.view * float4(d.position.xyz, 1.0);
  float4 clip = u.proj * eye;
  float extent = out.radius * (1.0 + 5.0 * out.glow) + 1.5;
  float2 corner = float2((vid & 1) ? 1.0 : -1.0, (vid & 2) ? 1.0 : -1.0);
  out.local = corner * extent;
  float3 toward = (u.view * float4(u.sun.xyz, 1.0)).xyz - eye.xyz;
  out.light = length(toward) > 0.0 ? normalize(toward) : float3(0.0);
  if (clip.w <= 0.0 || d.colour.a <= 0.0) {
    out.position = nowhere;
    return out;
  }
  // A billboard: offset in pixels after projection. No depth buffer --
  // the discs come farthest first -- so z is simply kept inside the volume.
  float2 offset = out.local / (0.5 * u.viewport);
  out.position = float4(clip.xy + offset * clip.w, 0.5 * clip.w, clip.w);
  return out;
}

// Premultiplied alpha out, so a glow can add light with an alpha of zero.
fragment float4 disc_fragment(DiscVarying in [[stage_in]])
{
  float d = length(in.local);
  float cover = 1.0 - smoothstep(in.radius - 0.75, in.radius + 0.75, d);
  float3 rgb = in.colour.rgb;
  if (in.glow == 0.0) {
    // A sphere facing the camera, lit from wherever the Sun is: from above
    // the planets are half lit, from behind them a crescent.
    float2 n2 = in.local / in.radius;
    float3 n = float3(n2, sqrt(saturate(1.0 - dot(n2, n2))));
    rgb *= 0.12 + 0.88 * saturate(dot(n, in.light));
  }
  float4 colour = float4(rgb * cover, cover);
  if (in.glow > 0.0) {
    float halo = in.glow * exp(-2.5 * max(d - in.radius, 0.0) / in.radius) * (1.0 - cover);
    colour.rgb += in.colour.rgb * halo;
  }
  return colour * in.colour.a;
}

struct OrbitInfo { float4 colour; float4 centre; };  // centre: what the points are relative to

struct OrbitVarying {
  float4 position [[position]];
  float4 colour;
  float across;
  float half_width;
};

// One instance per segment: a quad from point k to point k+1, projected,
// then widened across its on-screen direction by half the line width and a
// pixel for the ramp.
vertex OrbitVarying orbit_vertex(uint vid [[vertex_id]], uint iid [[instance_id]],
                                 device const float4 *points [[buffer(0)]],
                                 constant Uniforms &u [[buffer(1)]],
                                 constant OrbitInfo *orbits [[buffer(2)]])
{
  uint orbit = iid / SEGMENTS;
  uint k = iid % SEGMENTS;
  float3 centre = orbits[orbit].centre.xyz;
  float4 c0 = u.proj * (u.view * float4(centre + points[orbit * (SEGMENTS + 1) + k].xyz, 1.0));
  float4 c1 = u.proj * (u.view * float4(centre + points[orbit * (SEGMENTS + 1) + k + 1].xyz, 1.0));
  OrbitVarying out;
  out.colour = orbits[orbit].colour;
  out.half_width = 0.5 * u.line_width;
  out.across = 0.0;
  if (c0.w <= 0.0 || c1.w <= 0.0 || out.colour.a <= 0.0) {
    out.position = nowhere;
    return out;
  }
  float2 half_viewport = 0.5 * u.viewport;
  float2 s0 = c0.xy / c0.w * half_viewport;
  float2 s1 = c1.xy / c1.w * half_viewport;
  float2 along = s1 - s0;
  float2 dir = length(along) > 0.0 ? normalize(along) : float2(1.0, 0.0);
  float2 normal = float2(-dir.y, dir.x);
  float side = ((vid & 1) ? 1.0 : -1.0) * (out.half_width + 1.0);
  float4 c = (vid & 2) ? c1 : c0;
  float2 p = ((vid & 2) ? s1 : s0) + normal * side;
  out.position = float4(p / half_viewport * c.w, 0.5 * c.w, c.w);
  out.across = side;
  return out;
}

fragment float4 orbit_fragment(OrbitVarying in [[stage_in]])
{
  float a = in.colour.a * (1.0 - smoothstep(in.half_width - 0.5, in.half_width + 0.5, abs(in.across)));
  return float4(in.colour.rgb * a, a);
}
")

;;; ------------------------------------------------------------------
;;; state

(defvar *device* nil)
(defvar *queue* nil)
(defvar *orbit-pipeline* nil)
(defvar *disc-pipeline* nil)
(defvar *view* nil "The MTKView.")

;;; What goes round what. Orbits are drawn in this order: the Sun's family,
;;; then the moons, each moon's orbit relative to its planet.
(defun orbiters () (append (heliocentric-bodies) *moons*))

(defvar *orbit-buffer* nil
  "An MTLBuffer of float4, (+SEGMENTS+ + 1) per orbiter: the heliocentric
orbits in the scene, the moons' relative to their planets.")
(defvar *orbit-key* nil "(exponent tc) the heliocentric orbits were drawn for.")
(defvar *moon-orbit-key* nil "(scales tc frame) the moons' orbits were drawn for.")
(defvar *scales* nil "MOON-SYSTEM-SCALES, kept with the heliocentric orbits.")

;;; Small per-frame data goes through setVertexBytes: from these, allocated
;;; once. Metal copies them at encode time, so one block each is enough.
(defvar *uniforms* nil)     ; 40 floats: view, projection, viewport w h, line width, pad, sun xyzw
(defvar *discs* nil)        ; 12 floats a body: x y z radius, r g b a, glow 0 0 0
(defvar *orbit-info* nil)   ; 8 floats an orbit: r g b a, centre x y z, 0

(defvar *camera* (make-camera))
(defvar *focus* nil "The body the camera follows, if any.")
(defvar *last-placed* nil "PLACE-BODIES' answer for the last frame drawn.")
(defvar *frame-count* 0)
(defparameter +uniform-bytes+ 160)
(defparameter +disc-floats+ 12)
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

;;; ------------------------------------------------------------------
;;; setup

(defun make-pipeline (library vertex fragment pixel-format sample-count)
  "A render pipeline from two functions in LIBRARY, blending premultiplied
alpha into PIXEL-FORMAT."
  (let ((descriptor (objc:alloc-init-object "MTLRenderPipelineDescriptor")))
    (objc:invoke descriptor "setVertexFunction:" (objc:invoke library "newFunctionWithName:" vertex))
    (objc:invoke descriptor "setFragmentFunction:" (objc:invoke library "newFunctionWithName:" fragment))
    (objc:invoke descriptor "setRasterSampleCount:" sample-count)
    (let ((attachment (objc:invoke (objc:invoke descriptor "colorAttachments")
                                   "objectAtIndexedSubscript:" 0)))
      (objc:invoke attachment "setPixelFormat:" pixel-format)
      (objc:invoke attachment "setBlendingEnabled:" t)
      ;; MTLBlendFactorOne and MTLBlendFactorOneMinusSourceAlpha.
      (objc:invoke attachment "setSourceRGBBlendFactor:" 1)
      (objc:invoke attachment "setSourceAlphaBlendFactor:" 1)
      (objc:invoke attachment "setDestinationRGBBlendFactor:" 5)
      (objc:invoke attachment "setDestinationAlphaBlendFactor:" 5))
    (objc:invoke-with-error *device* "newRenderPipelineStateWithDescriptor:error:" descriptor)))

(defun ensure-metal (view)
  "The device, the compiled shaders, both pipelines and the buffers: once."
  (unless *disc-pipeline*
    (let* ((library (objc:invoke-with-error *device* "newLibraryWithSource:options:error:"
                                            (format nil +shaders+ +segments+) nil))
           (pixel-format (objc:invoke view "colorPixelFormat"))
           (samples (objc:invoke view "sampleCount"))
           (orbits (length (orbiters))))
      (setf *queue* (objc:invoke *device* "newCommandQueue")
            *orbit-pipeline* (make-pipeline library "orbit_vertex" "orbit_fragment" pixel-format samples)
            *disc-pipeline* (make-pipeline library "disc_vertex" "disc_fragment" pixel-format samples)
            *orbit-buffer* (objc:invoke *device* "newBufferWithLength:options:"
                                        (* 16 orbits (1+ +segments+)) 0)
            *uniforms* (cffi:foreign-alloc :float :count (/ +uniform-bytes+ 4))
            *discs* (cffi:foreign-alloc :float :count (* +disc-floats+ (1+ orbits)))
            *orbit-info* (cffi:foreign-alloc :float :count (* 8 orbits)))
      (format t "SOLAR: Metal ready on ~a, ~dx MSAA; ~d orbits~%"
              (objc:ns-string-to-string (objc:invoke *device* "name")) samples orbits)
      (finish-output))))

;;; ------------------------------------------------------------------
;;; orbits

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

(defun ensure-orbits (tc k)
  "Rewrite the heliocentric orbits if the compression or the elements --
which drift, slowly -- have changed since they were drawn. A year of
simulated time moves them by less than a pixel. The camera does not enter
into it."
  (let ((key *orbit-key*))
    (unless (and key
                 (= *radius-exponent* (first key))
                 (< (abs (- tc (second key))) 0.01d0))
      (let ((contents (objc:invoke *orbit-buffer* "contents")))
        (loop for body in (heliocentric-bodies)
              for slot from 0
              do (store-orbit contents slot (orbit-points body tc +segments+) (x y z)
                   (compress x y z k))))
      (setf *orbit-key* (list *radius-exponent* tc)
            *scales* (moon-system-scales tc k)))))

(defun ensure-moon-orbits (tc)
  "Rewrite the moons' orbits, relative to their planets, when a day of
simulated time has passed -- the Moon's node turns a fifth of a degree in
three -- but not more often than every thirty frames, which at a year a
second is twice a second."
  (let ((key *moon-orbit-key*))
    (unless (and key
                 (eq *scales* (first key))
                 (or (< (abs (- tc (second key))) (/ 1d0 36525))
                     (< (- *frame-count* (third key)) 30)))
      (let ((contents (objc:invoke *orbit-buffer* "contents"))
            (first-slot (length (heliocentric-bodies))))
        (loop for moon in *moons*
              for slot from first-slot
              do (destructuring-bind (radius . outermost) (rest (assoc (body-parent moon) *scales*))
                   (store-orbit contents slot (moon-orbit-points moon tc +segments+) (x y z)
                     (moon-display-offset x y z radius outermost)))))
      (setf *moon-orbit-key* (list *scales* tc *frame-count*)))))

;;; ------------------------------------------------------------------
;;; bodies

(defun pixels-per-unit (height depth)
  "Pixels per scene unit at view DEPTH (negative, in front of the camera),
in a drawable HEIGHT pixels tall."
  (/ (* 0.5d0 height) (tan (/ *field-of-view* 2)) (max 1d-9 (- depth))))

(defun place-bodies (tc k aspect height pixels-per-point)
  "Every body's scene position, depth, disc radius and opacity, as a list
of (depth body x y z radius alpha), and the moon systems' opacities, as an
alist. Moons fade in as their system grows on the screen beyond four times
their planet's disc, and are gone below two and a half."
  (let* ((enlarge (max 1d0 (min 3d0 (sqrt (camera-zoom *camera*)))))
         (sun (multiple-value-list
               (if (eq *frame* :barycentric)
                   (multiple-value-bind (x y z) (sun-barycentric-offset tc) (compress x y z k))
                   (values 0d0 0d0 0d0))))
         (placed '())
         (systems '()))
    (flet ((place (body x y z &optional (alpha 1d0))
             (let ((depth (nth-value 2 (view-position *camera* aspect x y z))))
               (push (list depth body x y z (* enlarge (disc-radius body pixels-per-point)) alpha)
                     placed)
               depth)))
      (destructuring-bind (sx sy sz) sun
        (place +sun+ sx sy sz)
        (dolist (body (heliocentric-bodies))
          (multiple-value-bind (x y z) (multiple-value-call #'compress
                                         (heliocentric-position body tc) k)
            (let* ((px (+ x sx)) (py (+ y sy)) (pz (+ z sz))
                   (depth (place body px py pz))
                   (scale (rest (assoc body *scales*))))
              (when scale
                (destructuring-bind (radius . outermost) scale
                  (let* ((on-screen (* radius (pixels-per-unit height depth)))
                         (disc (* enlarge (disc-radius body pixels-per-point)))
                         (alpha (smoothstep (* 2.5d0 disc) (* 4d0 disc) on-screen)))
                    (push (list body px py pz alpha) systems)
                    (dolist (moon (moons-of body))
                      (multiple-value-bind (dx dy dz)
                          (multiple-value-call #'moon-display-offset
                            (moon-offset moon tc) radius outermost)
                        (place moon (+ px dx) (+ py dy) (+ pz dz) alpha)))))))))))
    (values placed systems sun)))

(defun fill-discs (placed)
  "The bodies into *DISCS*, farthest from the camera first, so that nearer
ones draw over them."
  (loop for (nil body x y z radius alpha) in (sort (copy-list placed) #'< :key #'first)
        for slot from 0
        for colour = (body-colour body)
        do (store-floats *discs* (* +disc-floats+ slot)
                         x y z radius
                         (aref colour 0) (aref colour 1) (aref colour 2) alpha
                         (if (eq body +sun+) 1 0) 0 0 0))
  (length placed))

(defun fill-orbit-info (systems sun)
  "Each orbit's colour, opacity and centre: the Sun's family round the Sun,
the planets brighter than the dwarfs; each moon round its planet, as bright
as its system is visible."
  (destructuring-bind (sx sy sz) sun
    (loop for body in (heliocentric-bodies)
          for slot from 0
          for colour = (body-colour body)
          do (store-floats *orbit-info* (* 8 slot)
                           (aref colour 0) (aref colour 1) (aref colour 2)
                           (if (member body *planets*) 0.45 0.3)
                           sx sy sz 0)))
  (loop for moon in *moons*
        for slot from (length (heliocentric-bodies))
        for colour = (body-colour (body-parent moon))
        do (destructuring-bind (px py pz alpha) (rest (assoc (body-parent moon) systems))
             (store-floats *orbit-info* (* 8 slot)
                           (aref colour 0) (aref colour 1) (aref colour 2) (* 0.35d0 alpha)
                           px py pz 0))))

(defun follow-focus (placed)
  "Keep the camera's target on the focused body, wherever it has moved."
  (let ((entry (and *focus* (find *focus* placed :key #'second))))
    (when entry
      (destructuring-bind (depth body x y z &rest rest) entry
        (declare (ignore depth body rest))
        (let ((target (solar-system.core::camera-target *camera*)))
          (setf (aref target 0) x (aref target 1) y (aref target 2) z))))))

(defun screen-metrics (view)
  "Values width and height in pixels, pixels per point, aspect, and the
projection matrix: what TO-POINTS needs, read once."
  (let* ((size (objc:invoke view "drawableSize"))
         (width (float (aref size 0) 1d0))
         (height (float (aref size 1) 1d0))
         (aspect (/ width height)))
    (values width height (float (objc:invoke view "contentScaleFactor") 1d0) aspect
            (projection-matrix *camera* aspect))))

(defun to-points (x y z width height scale aspect projection)
  "Values the screen position in points, y down, of scene point X Y Z; NIL
if it is behind the camera."
  (multiple-value-bind (vx vy vz) (view-position *camera* aspect x y z)
    (when (minusp vz)
      (values (/ (* 0.5d0 width (1+ (/ (* (aref projection 0) vx) (- vz)))) scale)
              (/ (* 0.5d0 height (- 1 (/ (* (aref projection 5) vy) (- vz)))) scale)))))

(defun body-at (view px py &optional (reach 24d0))
  "The visible body drawn nearest the point PX, PY (points, y down) of VIEW,
within REACH points of its disc, or NIL."
  (multiple-value-bind (width height scale aspect projection) (screen-metrics view)
    (let ((best nil) (best-distance nil))
      (loop for (nil body x y z radius alpha) in *last-placed*
            when (> alpha 0.5d0)
              do (multiple-value-bind (sx sy) (to-points x y z width height scale aspect projection)
                   (when sx
                     (let ((distance (- (sqrt (+ (expt (- sx px) 2) (expt (- sy py) 2)))
                                        (/ radius scale))))
                       (when (and (< distance reach) (or (null best) (< distance best-distance)))
                         (setf best body best-distance distance))))))
      best)))

(defun focus-on (body)
  "Follow BODY; for a planet with moons, come close enough to see them."
  (setf *focus* body)
  (let ((scale (and body (rest (assoc body *scales*)))))
    (when scale
      ;; The system's radius at about a third of the shorter side: at the
      ;; target, pixels per unit are h/2 / tan(fov/2) / distance.
      (let* ((size (objc:invoke *view* "drawableSize"))
             (width (float (aref size 0) 1d0))
             (height (float (aref size 1) 1d0))
             (aspect (/ width height))
             (wanted (* 0.3d0 (min width height)))
             (distance (/ (* 0.5d0 height (first scale)) (tan (/ *field-of-view* 2)) wanted)))
        (setf (camera-zoom *camera*)
              (max 0.3d0 (min 400d0 (/ (fit-distance aspect) distance))))))))

(defun store-matrix (pointer offset matrix)
  (dotimes (i 16)
    (setf (cffi:mem-aref pointer :float (+ offset i)) (float (aref matrix i) 1.0))))

(defun draw-frame (view)
  (objc:with-autorelease-pool ()
    (ensure-metal view)
    (let* ((size (objc:invoke view "drawableSize"))
           (width (float (aref size 0) 1d0))
           (height (float (aref size 1) 1d0)))
      (when (or (zerop width) (zerop height))
        (return-from draw-frame))
      (incf *frame-count*)
      (let* ((aspect (/ width height))
             (pixels-per-point (float (objc:invoke view "contentScaleFactor") 1d0))
             (jd (sim-jd))
             (tc (centuries-since-j2000 (utc-to-tt jd)))
             (k (compression tc))
             (orbits (length (orbiters)))
             (discs 0))
        (ensure-orbits tc k)
        (ensure-moon-orbits tc)
        (multiple-value-bind (placed systems sun)
            (place-bodies tc k aspect height pixels-per-point)
          (setf *last-placed* placed)
          (follow-focus placed)
          (setf discs (fill-discs placed))
          (fill-orbit-info systems sun)
          (store-matrix *uniforms* 0 (view-matrix *camera* aspect))
          (store-matrix *uniforms* 16 (projection-matrix *camera* aspect))
          (destructuring-bind (sx sy sz) sun
            (store-floats *uniforms* 32 width height (* 1.5d0 pixels-per-point) 0 sx sy sz 1)))
        (let ((pass (objc:invoke view "currentRenderPassDescriptor")))
          (unless (nothing-p pass)
            (let* ((commands (objc:invoke *queue* "commandBuffer"))
                   (encoder (objc:invoke commands "renderCommandEncoderWithDescriptor:" pass)))
              ;; Orbits: a quad (triangle strip of 4) per segment.
              (objc:invoke encoder "setRenderPipelineState:" *orbit-pipeline*)
              (objc:invoke encoder "setVertexBuffer:offset:atIndex:" *orbit-buffer* 0 0)
              (objc:invoke encoder "setVertexBytes:length:atIndex:" *uniforms* +uniform-bytes+ 1)
              (objc:invoke encoder "setVertexBytes:length:atIndex:" *orbit-info* (* 32 orbits) 2)
              (objc:invoke encoder "drawPrimitives:vertexStart:vertexCount:instanceCount:"
                           4 0 4 (* orbits +segments+))
              ;; Bodies: a quad per disc, farthest first.
              (objc:invoke encoder "setRenderPipelineState:" *disc-pipeline*)
              (objc:invoke encoder "setVertexBytes:length:atIndex:" *discs*
                           (* 4 +disc-floats+ discs) 0)
              (objc:invoke encoder "setVertexBytes:length:atIndex:" *uniforms* +uniform-bytes+ 1)
              (objc:invoke encoder "drawPrimitives:vertexStart:vertexCount:instanceCount:"
                           4 0 4 discs)
              (objc:invoke encoder "endEncoding")
              (objc:invoke commands "presentDrawable:" (objc:invoke view "currentDrawable"))
              (objc:invoke commands "commit"))))
        (after-frame jd)))))

;;; ------------------------------------------------------------------
;;; the delegate

;;; Not declared as conforming to MTKViewDelegate: that protocol is not in
;;; the runtime until something compiled refers to it, and MTKView never
;;; asks -- it sends the two messages to whatever its delegate is.
(objc:define-objc-class solar-renderer () ()
  (:objc-class-name "SolarRenderer"))

(defvar *frames* 0)
(defvar *frames-since* nil "Internal real time the count was last reported.")
(defvar *draw-time* 0 "Internal time units spent in DRAW-FRAME since the report.")
(defvar *draw-worst* 0)

(defun count-frame (spent)
  "Every ten seconds, say how many frames a second were drawn, and how long
the Lisp side of a frame took on average and at worst."
  (let ((now (get-internal-real-time)))
    (incf *frames*)
    (incf *draw-time* spent)
    (setf *draw-worst* (max *draw-worst* spent))
    (cond ((null *frames-since*) (setf *frames-since* now *frames* 0 *draw-time* 0 *draw-worst* 0))
          ((>= (- now *frames-since*) (* 10 internal-time-units-per-second))
           (let ((ms (/ 1000d0 internal-time-units-per-second)))
             (format t "~&SOLAR: ~,1f frames/s, drawing ~,1f ms a frame, ~,1f at worst~%"
                     (/ *frames* (/ (- now *frames-since*) internal-time-units-per-second))
                     (* ms (/ *draw-time* (max 1 *frames*))) (* ms *draw-worst*)))
           (finish-output)
           (setf *frames-since* now *frames* 0 *draw-time* 0 *draw-worst* 0)))))

(objc:define-objc-method ("drawInMTKView:" :void)
    ((self solar-renderer) (view objc:objc-object-pointer))
  ;; A Lisp error here would recur sixty times a second. Stop drawing and
  ;; say why; fix it over the REPL and (RESUME).
  (unless *failure*
    (handler-case (let ((start (get-internal-real-time)))
                    (draw-frame view)
                    (count-frame (- (get-internal-real-time) start)))
      (error (condition)
        (setf *failure* condition)
        (objc:invoke view "setPaused:" t)
        (format t "~&SOLAR: drawing stopped: ~a~%" condition)
        (finish-output)))))

(objc:define-objc-method ("mtkView:drawableSizeWillChange:" :void)
    ((self solar-renderer) (view objc:objc-object-pointer) (size cocoa:ns-size))
  (declare (ignore view))
  ;; DRAW-FRAME reads the size itself; this only says so.
  (format t "~&SOLAR: drawable now ~dx~d~%" (round (aref size 0)) (round (aref size 1)))
  (finish-output))

(defun resume ()
  "Draw again after a failure."
  (setf *failure* nil)
  (when *view*
    (objc:invoke *view* "setPaused:" nil))
  t)

(defun make-metal-view ()
  "An MTKView on the default device, its delegate a SOLAR-RENDERER."
  (setf *device* (si:call-cfun (cffi:foreign-symbol-pointer "MTLCreateSystemDefaultDevice")
                               :pointer-void '() '()))
  (when (nothing-p *device*)
    (error "No Metal device."))
  (let ((view (objc:invoke (objc:invoke "MTKView" "alloc") "initWithFrame:device:"
                           #(0d0 0d0 100d0 100d0) *device*)))
    (objc:invoke view "setTranslatesAutoresizingMaskIntoConstraints:" nil)
    (objc:invoke view "setSampleCount:" 4)
    (objc:invoke view "setPreferredFramesPerSecond:" 60)
    (objc:invoke view "setDelegate:" (ui:keep (make-instance 'solar-renderer)))
    (setf *view* view)))
