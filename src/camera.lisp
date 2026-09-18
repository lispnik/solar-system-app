;;;; camera.lisp -- a camera that orbits, rolls, zooms and pans.
;;;;
;;;; The scene is the compressed solar system of projection.lisp, in which
;;;; the outermost aphelion is at distance 1. The camera looks at TARGET from
;;;; DISTANCE along its own +z, and its orientation is a rotation matrix
;;;; taking world coordinates to view coordinates: x right, y up, z towards
;;;; the viewer. The identity is the view from the north ecliptic pole, the
;;;; vernal equinox to the right.
;;;;
;;;; Gestures turn the scene about the SCREEN's axes, not the world's, which
;;;; is what makes a drag feel like turning a ball in your hand: each turn is
;;;; applied on the left, in view space, and the matrix is re-orthonormalised
;;;; so that a thousand small turns stay a rotation.

(in-package #:solar-system.core)

(defparameter *field-of-view* (* 30 +degrees+) "Vertical, in radians.")

(defstruct (camera (:constructor %make-camera))
  (rotation (identity-3) :type (simple-array double-float (9)))  ; row-major
  (target (make-array 3 :element-type 'double-float :initial-element 0d0)
   :type (simple-array double-float (3)))
  (zoom 1d0 :type double-float))            ; 1 fits the scene; larger is closer

(defun identity-3 ()
  (let ((m (make-array 9 :element-type 'double-float :initial-element 0d0)))
    (setf (aref m 0) 1d0 (aref m 4) 1d0 (aref m 8) 1d0)
    m))

(defun make-camera () (%make-camera))

(defun reset-camera (camera)
  (setf (camera-rotation camera) (identity-3)
        (camera-target camera) (make-array 3 :element-type 'double-float :initial-element 0d0)
        (camera-zoom camera) 1d0)
  camera)

(defun multiply-3 (a b)
  "A B, both row-major 3x3."
  (let ((m (make-array 9 :element-type 'double-float)))
    (dotimes (r 3 m)
      (dotimes (c 3)
        (setf (aref m (+ (* 3 r) c))
              (loop for k below 3 sum (* (aref a (+ (* 3 r) k)) (aref b (+ (* 3 k) c)))))))))

(defun axis-rotation (axis angle)
  "Rotation by ANGLE radians about view axis 0 (x), 1 (y) or 2 (z)."
  (let ((m (identity-3))
        (c (cos angle)) (s (sin angle)))
    (destructuring-bind (i j) (ecase axis (0 '(1 2)) (1 '(2 0)) (2 '(0 1)))
      (setf (aref m (+ (* 3 i) i)) c
            (aref m (+ (* 3 i) j)) (- s)
            (aref m (+ (* 3 j) i)) s
            (aref m (+ (* 3 j) j)) c))
    m))

(defun orthonormalize (m)
  "Gram-Schmidt on the rows of M, in place."
  (flet ((row (r) (list (aref m (* 3 r)) (aref m (+ 1 (* 3 r))) (aref m (+ 2 (* 3 r)))))
         (set-row (r v) (loop for x in v for c from 0 do (setf (aref m (+ c (* 3 r))) x)))
         (dot (a b) (reduce #'+ (mapcar #'* a b)))
         (unit (v) (let ((n (sqrt (reduce #'+ (mapcar #'* v v))))) (mapcar (lambda (x) (/ x n)) v))))
    (let* ((x (unit (row 0)))
           (y (unit (mapcar (lambda (b a) (- b (* (dot (row 1) x) a))) (row 1) x)))
           (z (list (- (* (second x) (third y)) (* (third x) (second y)))
                    (- (* (third x) (first y)) (* (first x) (third y)))
                    (- (* (first x) (second y)) (* (second x) (first y))))))
      (set-row 0 x) (set-row 1 y) (set-row 2 z)
      m)))

(defun turn-camera (camera axis angle)
  "Turn the scene by ANGLE about the screen's AXIS (0 x, 1 y, 2 z)."
  (setf (camera-rotation camera)
        (orthonormalize (multiply-3 (axis-rotation axis angle) (camera-rotation camera))))
  camera)

(defun fit-distance (aspect)
  "How far from the target the camera must be for the unit disc to fit,
with a margin, in a view of ASPECT (width / height)."
  (let* ((half-y (tan (/ *field-of-view* 2)))
         (half (min half-y (* aspect half-y))))
    (/ 1.08d0 half)))

(defun camera-distance (camera aspect)
  (/ (fit-distance aspect) (camera-zoom camera)))

(defun zoom-camera (camera factor)
  (setf (camera-zoom camera) (max 0.3d0 (min 400d0 (* (camera-zoom camera) factor))))
  camera)

(defun pan-camera (camera dx dy height-pixels aspect)
  "Move the scene by DX, DY pixels (y up) in a view HEIGHT-PIXELS tall: the
target moves the other way, in the plane facing the camera."
  (let* ((world-per-pixel (/ (* 2 (camera-distance camera aspect) (tan (/ *field-of-view* 2)))
                             height-pixels))
         (r (camera-rotation camera))
         (target (camera-target camera)))
    ;; View-space displacement (-dx, -dy, 0), back to world through R's transpose.
    (dotimes (c 3)
      (decf (aref target c) (* world-per-pixel (+ (* dx (aref r c)) (* dy (aref r (+ 3 c))))))))
  camera)

(defun view-position (camera aspect x y z)
  "Values x, y, z of the world point in view space."
  (let* ((r (camera-rotation camera))
         (target (camera-target camera))
         (px (- x (aref target 0))) (py (- y (aref target 1))) (pz (- z (aref target 2))))
    (flet ((row (i) (+ (* (aref r (* 3 i)) px) (* (aref r (+ 1 (* 3 i))) py) (* (aref r (+ 2 (* 3 i))) pz))))
      (values (row 0) (row 1) (- (row 2) (camera-distance camera aspect))))))

(defun view-matrix (camera aspect)
  "The world-to-view matrix, 16 doubles, column-major as Metal's float4x4."
  (let* ((r (camera-rotation camera))
         (target (camera-target camera))
         (m (make-array 16 :element-type 'double-float :initial-element 0d0)))
    (dotimes (row 3)
      (dotimes (col 3)
        (setf (aref m (+ (* 4 col) row)) (aref r (+ (* 3 row) col))))
      (setf (aref m (+ 12 row))
            (- (loop for k below 3 sum (* (aref r (+ (* 3 row) k)) (aref target k))))))
    (decf (aref m 14) (camera-distance camera aspect))
    (setf (aref m 15) 1d0)
    m))

(defun projection-matrix (camera aspect)
  "Perspective, Metal's clip space (z from 0 to 1), column-major."
  (let* ((distance (camera-distance camera aspect))
         (near (* 0.01d0 distance))
         (far (+ distance 4d0))
         (f (/ 1d0 (tan (/ *field-of-view* 2))))
         (m (make-array 16 :element-type 'double-float :initial-element 0d0)))
    (setf (aref m 0) (/ f aspect)
          (aref m 5) f
          (aref m 10) (/ far (- near far))
          (aref m 11) -1d0
          (aref m 14) (/ (* near far) (- near far)))
    m))
