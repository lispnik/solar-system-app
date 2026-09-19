;;;; scale.lisp -- between the compressed view and true distances.
;;;;
;;;; The ruler button eases *RADIUS-EXPONENT* from its compressed 0.4 to 1,
;;;; where every distance from the Sun is to scale, and back. Everything
;;;; follows from the exponent: the orbits are redrawn as it changes, the
;;;; moons' systems re-measured. Discs stay the size they are -- at true
;;;; scale a planet would be far smaller than a pixel.

(in-package #:solar-system)

(defparameter +compressed-exponent+ 0.4d0)
(defparameter +scale-seconds+ 1.5d0)

(defvar *true-scale* nil "Where the toggle is headed: true distances or not.")
(defvar *scale-animation* nil "(from to start), while the exponent is moving.")

(defun toggle-scale ()
  ;; From the Earth everything is at true distance already.
  (when *sky-mode* (return-from toggle-scale))
  (setf *true-scale* (not *true-scale*)
        *scale-animation* (list *radius-exponent*
                                (if *true-scale* 1d0 +compressed-exponent+)
                                (get-internal-real-time)))
  (set-button-image *scale-button* (if *true-scale* "ruler.fill" "ruler")))

(defun step-scale ()
  "Move the exponent along, eased in and out; called once a frame."
  (when *scale-animation*
    (destructuring-bind (from to start) *scale-animation*
      (let* ((elapsed (/ (- (get-internal-real-time) start)
                         (float internal-time-units-per-second 1d0)))
             (u (min 1d0 (/ elapsed +scale-seconds+)))
             (eased (* u u (- 3 (* 2 u)))))
        (setf *radius-exponent* (+ from (* eased (- to from))))
        (when (>= u 1d0)
          (setf *radius-exponent* to
                *scale-animation* nil))))))

(defun describe-scale ()
  (cond (*scale-animation* "changing scale")
        (*true-scale* "true distances")
        (t nil)))

(defun sync-toggle-buttons ()
  "Show on the toggle buttons what the settings are, restored or not."
  (set-button-image *scale-button* (if *true-scale* "ruler.fill" "ruler"))
  (set-button-image *labels-button* (if *labels-on* "tag.fill" "tag"))
  (set-button-image *trails-button* (if *trails-on* "scribble.variable" "scribble"))
  (show-sky-button))
