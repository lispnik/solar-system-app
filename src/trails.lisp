;;;; trails.lisp -- where each body has just been.
;;;;
;;;; A fading line behind each of the Sun's family over the last eighth of
;;;; its orbit: Mercury's eleven days, Neptune's twenty years. It is drawn
;;;; from the ephemeris, not remembered, so a jump or a scrub leaves no
;;;; false history behind it -- but not recomputed every frame either:
;;;; each trail is kept on a fixed grid of times, a 256th of its length
;;;; apart, and as the clock moves only the grid points it passes are
;;;; worked out; the head is the body where it is now.
;;;;
;;;; What a trail follows is *TRAIL-POSITION*'s business: the heliocentric
;;;; position in the ordinary view; the view from Earth changes it.

(in-package #:solar-system)

(defvar *trails-on* t)
(defvar *trails-button* nil)

(defstruct trail
  body
  (step 1d0 :type double-float)     ; days between grid points
  (grid nil)                        ; grid index of the newest grid point
  (points (make-array (* 3 (1+ +segments+)) :element-type 'double-float))
  (exponent nil))                   ; the compression it was written at

(defvar *trails* '())

(defun trail-days (body)
  "An eighth of BODY's orbit, in days, from its semimajor axis."
  (/ (* 365.25d0 (expt (solar-system.core::elements body 0d0) 1.5d0)) 8))

(defun heliocentric-trail-position (body jd)
  (heliocentric-position body (centuries-since-j2000 jd)))

(defvar *trail-position* #'heliocentric-trail-position
  "A function of a body and a JD (TT) answering the x y z its trail passes.")
(defvar *trail-length* #'trail-days "A function of a body answering its trail's length in days.")

(defun reset-trails ()
  (setf *trails* (loop for body in (heliocentric-bodies)
                       collect (make-trail :body body
                                           :step (/ (funcall *trail-length* body) +segments+)))))

(defun advance-trail (trail jd)
  "Bring the grid points up to JD, computing only those it has not got.
T if any changed."
  (let* ((step (trail-step trail))
         (newest (floor jd step))
         (old (trail-grid trail))
         (points (trail-points trail))
         (count +segments+))                       ; grid points; the head is one more
    (flet ((fill-point (i grid-index)
             (multiple-value-bind (x y z)
                 (funcall *trail-position* (trail-body trail) (* grid-index step))
               (setf (aref points (* 3 i)) x
                     (aref points (+ 1 (* 3 i))) y
                     (aref points (+ 2 (* 3 i))) z))))
      (cond ((eql newest old) nil)
            ((or (null old) (>= (abs (- newest old)) count))
             (dotimes (i count) (fill-point i (+ (- newest count -1) i)))
             (setf (trail-grid trail) newest)
             t)
            ((> newest old)
             (let ((n (- newest old)))
               (replace points points :start1 0 :start2 (* 3 n) :end2 (* 3 count))
               (loop for i from (- count n) below count
                     do (fill-point i (+ (- newest count -1) i))))
             (setf (trail-grid trail) newest)
             t)
            (t
             (let ((n (- old newest)))
               (replace points points :start1 (* 3 n) :start2 0 :end2 (* 3 (- count n)))
               (dotimes (i n) (fill-point i (+ (- newest count -1) i))))
             (setf (trail-grid trail) newest)
             t)))))

(defun update-trails (tc k sun)
  "Keep every trail's line up to date in the orbit buffer: grid points as
the clock passes them, the head every frame."
  (let ((contents (objc:invoke *orbit-buffer* "contents"))
        (jd (+ solar-system.core:+j2000+ (* tc 36525d0))))
    (when (and *trails-on* (null *trails*)) (reset-trails))
    (loop for trail in *trails*
          for index from 0
          for slot = (trail-slot index)
          for body = (trail-body trail)
          for colour = (body-colour body)
          do (if (not *trails-on*)
                 (store-line slot 0 0 0 0 0 0 0)
                 (let* ((changed (advance-trail trail jd))
                        (points (trail-points trail))
                        (base (* slot 4 (1+ +segments+))))
                   ;; The head: where the body is now.
                   (multiple-value-bind (x y z) (funcall *trail-position* body jd)
                     (setf (aref points (* 3 +segments+)) x
                           (aref points (+ 1 (* 3 +segments+))) y
                           (aref points (+ 2 (* 3 +segments+))) z))
                   (flet ((write-point (i)
                            (multiple-value-bind (x y z)
                                (trail-scene (aref points (* 3 i)) (aref points (+ 1 (* 3 i)))
                                             (aref points (+ 2 (* 3 i))) k)
                              (store-floats contents (+ base (* 4 i)) x y z 1))))
                     (if (or changed (not (eql (trail-exponent trail) *radius-exponent*)))
                         (progn (dotimes (i (1+ +segments+)) (write-point i))
                                (setf (trail-exponent trail) *radius-exponent*))
                         (write-point +segments+)))
                   (destructuring-bind (sx sy sz) sun
                     (store-line slot (aref colour 0) (aref colour 1) (aref colour 2) 0.85
                                 sx sy sz 1 1.6)))))))

(defvar *trail-scene* (lambda (x y z k) (compress x y z k))
  "Where a trail point goes in the scene: compressed like everything else,
or as the view from Earth wants it.")

(defun trail-scene (x y z k) (funcall *trail-scene* x y z k))

(defun toggle-trails ()
  (setf *trails-on* (not *trails-on*))
  (set-button-image *trails-button* (if *trails-on* "scribble.variable" "scribble")))
