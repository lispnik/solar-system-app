;;;; view.lisp -- following a body, and between the screen and the scene.

(in-package #:solar-system)

(defun follow-focus (placed)
  "Keep the camera on the focused body, wherever it has moved: its target
there, from outside; looking at it, from the Earth."
  (let ((entry (and *focus* (find *focus* placed :key #'second))))
    (when entry
      (destructuring-bind (depth body x y z &rest rest) entry
        (declare (ignore depth body rest))
        (cond
          ;; Held up to the sky, the phone turns the view, not the body.
          (*pointing* nil)
          (*sky-mode*
            (let ((from (solar-system.core::camera-target *camera*)))
              (look-along *camera* (- x (aref from 0)) (- y (aref from 1)) (- z (aref from 2)))))
          (t
            (let ((target (solar-system.core::camera-target *camera*)))
              (setf (aref target 0) x (aref target 1) y (aref target 2) z))))))))

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
  (when *sky-mode*
    (return-from focus-on (sky-focus-on body)))
  (setf *focus* body)
  (let ((scale (and body (rest (assoc body *scales*)))))
    ;; One without moons: near enough that its disc is a good size.
    (when (and body (null scale))
      (setf (camera-zoom *camera*) (max (camera-zoom *camera*) 60d0)))
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
