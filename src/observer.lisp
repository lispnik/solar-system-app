;;;; observer.lisp -- standing on the Earth, and what a body is like from there.
;;;;
;;;; The horizon where someone stands: north, west and up, as the phone's
;;;; motion sensors have them (Core Motion's "X to true north, Z vertical"
;;;; frame, whose Y is therefore west), turned with the Earth by its IAU
;;;; rotation. Altitude and azimuth follow from it, and so does the camera
;;;; of a phone held up to the sky: its attitude is a quaternion taking the
;;;; phone's own axes into that frame, and in portrait the phone's axes are
;;;; the screen's -- x right, y up, z out of the glass towards the eye, so
;;;; the camera looks out of the back.
;;;;
;;;; And the facts a card shows about a body: how far, how fast, how lit.

(in-package #:solar-system.core)

(defun observer-position (lon lat tc)
  "Values x, y, z in AU: a point on the Earth's surface at east longitude
LON and latitude LAT (degrees, planetocentric), from the Earth's centre."
  (multiple-value-bind (ax ay az bx by bz cx cy cz) (body-axes (find-planet "Earth") tc)
    (let* ((r (/ +earth-radius-km+ +km-per-au+))
           (lon (* lon +degrees+)) (lat (* lat +degrees+))
           (u (* r (cos lat) (cos lon))) (v (* r (cos lat) (sin lon))) (w (* r (sin lat))))
      (values (+ (* u ax) (* v bx) (* w cx))
              (+ (* u ay) (* v by) (* w cy))
              (+ (* u az) (* v bz) (* w cz))))))

(defun horizon-axes (lon lat tc)
  "Nine values: north, west and up at LON, LAT (degrees) at TC, as unit
vectors in the J2000 ecliptic."
  (multiple-value-bind (ax ay az bx by bz px py pz) (body-axes (find-planet "Earth") tc)
    (let* ((lo (* lon +degrees+)) (la (* lat +degrees+))
           (ux (+ (* (cos la) (cos lo) ax) (* (cos la) (sin lo) bx) (* (sin la) px)))
           (uy (+ (* (cos la) (cos lo) ay) (* (cos la) (sin lo) by) (* (sin la) py)))
           (uz (+ (* (cos la) (cos lo) az) (* (cos la) (sin lo) bz) (* (sin la) pz)))
           ;; North: the pole, less its part along up.
           (along (+ (* px ux) (* py uy) (* pz uz)))
           (nx (- px (* along ux))) (ny (- py (* along uy))) (nz (- pz (* along uz)))
           (n (sqrt (+ (* nx nx) (* ny ny) (* nz nz))))
           (nx (/ nx n)) (ny (/ ny n)) (nz (/ nz n)))
      ;; West = up x north.
      (values nx ny nz
              (- (* uy nz) (* uz ny)) (- (* uz nx) (* ux nz)) (- (* ux ny) (* uy nx))
              ux uy uz))))

(defun altitude-azimuth (lon lat tc x y z)
  "Values altitude and azimuth, degrees -- azimuth from north through east
-- of the direction X Y Z (ecliptic) seen from LON, LAT."
  (multiple-value-bind (nx ny nz wx wy wz ux uy uz) (horizon-axes lon lat tc)
    (let ((north (+ (* x nx) (* y ny) (* z nz)))
          (west (+ (* x wx) (* y wy) (* z wz)))
          (up (+ (* x ux) (* y uy) (* z uz))))
      (values (/ (* 180 (atan up (sqrt (+ (* north north) (* west west))))) +pi+)
              (mod (/ (* 180 (atan (- west) north)) +pi+) 360d0)))))

(defun quaternion-columns (qx qy qz qw)
  "The rotation a unit quaternion stands for, as its three columns -- the
images of x, y and z -- nine values."
  (values (- 1 (* 2 (+ (* qy qy) (* qz qz)))) (* 2 (+ (* qx qy) (* qz qw))) (* 2 (- (* qx qz) (* qy qw)))
          (* 2 (- (* qx qy) (* qz qw))) (- 1 (* 2 (+ (* qx qx) (* qz qz)))) (* 2 (+ (* qy qz) (* qx qw)))
          (* 2 (+ (* qx qz) (* qy qw))) (* 2 (- (* qy qz) (* qx qw))) (- 1 (* 2 (+ (* qx qx) (* qy qy))))))

(defun device-camera-rotation (qx qy qz qw lon lat tc &optional (screen-turn 0d0))
  "The camera rotation, row-major world -> view, of a phone whose attitude
is the quaternion QX QY QZ QW in the north-west-up frame at LON, LAT, the
interface turned SCREEN-TURN radians from portrait. The quaternion takes
the phone's axes into that frame: its columns are the phone's x, y and z
in north-west-up; those, in the ecliptic, are the view's axes."
  (multiple-value-bind (nx ny nz wx wy wz ux uy uz) (horizon-axes lon lat tc)
    (multiple-value-bind (xn xw xu yn yw yu zn zw zu) (quaternion-columns qx qy qz qw)
      (flet ((world (n w u) (list (+ (* n nx) (* w wx) (* u ux))
                                  (+ (* n ny) (* w wy) (* u uy))
                                  (+ (* n nz) (* w wz) (* u uz)))))
        (let* ((dx (world xn xw xu)) (dy (world yn yw yu)) (dz (world zn zw zu))
               (c (cos screen-turn)) (s (sin screen-turn))
               ;; The screen turned against the phone: its x and y are the
               ;; phone's turned by the interface's rotation.
               (vx (mapcar (lambda (a b) (+ (* c a) (* s b))) dx dy))
               (vy (mapcar (lambda (a b) (- (* c b) (* s a))) dx dy)))
          (coerce (append vx vy dz) '(simple-array double-float (9))))))))

;;; UIInterfaceOrientation, as the window scene reports it, and how far the
;;; interface is turned from portrait. Landscape right (3) has the home
;;; button on the right: the phone's top to the left, its x straight up.
(defun interface-turn (orientation)
  "Radians the interface is turned from portrait, for a UIInterfaceOrientation:
portrait 1, upside down 2, landscape right 3, landscape left 4."
  (case orientation
    ;; Landscape right is the phone turned a quarter anticlockwise, so the
    ;; interface is a quarter clockwise from the phone's own axes: minus.
    (2 +pi+) (3 (- (/ +pi+ 2))) (4 (/ +pi+ 2)) (t 0d0)))

(defun matrix-quaternion (m)
  "The unit quaternion of the rotation whose columns are M's -- M row-major
nine -- values qx qy qz qw. For tests: the attitude a phone would report."
  (let* ((m00 (aref m 0)) (m01 (aref m 1)) (m02 (aref m 2))
         (m10 (aref m 3)) (m11 (aref m 4)) (m12 (aref m 5))
         (m20 (aref m 6)) (m21 (aref m 7)) (m22 (aref m 8))
         (trace (+ m00 m11 m22)))
    (if (> trace 0)
        (let ((s (* 2 (sqrt (1+ trace)))))
          (values (/ (- m21 m12) s) (/ (- m02 m20) s) (/ (- m10 m01) s) (/ s 4)))
        (cond ((and (> m00 m11) (> m00 m22))
               (let ((s (* 2 (sqrt (+ 1 m00 (- m11) (- m22))))))
                 (values (/ s 4) (/ (+ m01 m10) s) (/ (+ m02 m20) s) (/ (- m21 m12) s))))
              ((> m11 m22)
               (let ((s (* 2 (sqrt (+ 1 m11 (- m00) (- m22))))))
                 (values (/ (+ m01 m10) s) (/ s 4) (/ (+ m12 m21) s) (/ (- m02 m20) s))))
              (t
               (let ((s (* 2 (sqrt (+ 1 m22 (- m00) (- m11))))))
                 (values (/ (+ m02 m20) s) (/ (+ m12 m21) s) (/ s 4) (/ (- m10 m01) s))))))))

;;; ------------------------------------------------------------------
;;; facts

(defun centre-of (body tc)
  "Values BODY's heliocentric position, AU -- the Moon's and every moon's
through their planets."
  (cond ((eq body +sun+) (values 0d0 0d0 0d0))
        ((string= (body-name body) "Earth") (earth-position tc))
        ((string= (body-name body) "Moon")
         (multiple-value-bind (ex ey ez) (earth-position tc)
           (multiple-value-bind (mx my mz) (lunar-position tc)
             (values (+ ex mx) (+ ey my) (+ ez mz)))))
        ((body-parent body)
         (multiple-value-bind (px py pz) (heliocentric-position (body-parent body) tc)
           (multiple-value-bind (dx dy dz) (moon-offset body tc)
             (values (+ px dx) (+ py dy) (+ pz dz)))))
        (t (heliocentric-position body tc))))

(defun body-kind (body)
  (cond ((eq body +sun+) "star")
        ((body-comet body) "comet")
        ((body-parent body) (format nil "moon of ~a" (body-name (body-parent body))))
        ((member body *dwarfs*) "dwarf planet")
        (t "planet")))

(defun body-facts (body tc)
  "A plist of what a card shows about BODY at TC: :kind; :sun and :earth,
distances in AU; :light, seconds from it to the Earth; :parent-distance,
km, for a moon; :speed, km/s, round the Sun or a moon's planet; :phase, the
fraction lit seen from the Earth; :elongation, degrees from the Sun;
:size, apparent diameter in arcseconds."
  (let* ((dt 0.02d0)
         (step (/ dt 36525)))
    (multiple-value-bind (x y z) (centre-of body tc)
      (multiple-value-bind (ex ey ez) (earth-position tc)
        (let* ((gx (- x ex)) (gy (- y ey)) (gz (- z ez))
               (earth (distance gx gy gz))
               (sun (distance x y z))
               (parent (body-parent body))
               (relative (lambda (tc) (if parent
                                          (if (string= (body-name body) "Moon")
                                              (lunar-position tc)
                                              (moon-offset body tc))
                                          (centre-of body tc))))
               (speed (multiple-value-bind (x0 y0 z0) (funcall relative (- tc step))
                        (multiple-value-bind (x1 y1 z1) (funcall relative (+ tc step))
                          (/ (* +km-per-au+ (distance (- x1 x0) (- y1 y0) (- z1 z0)))
                             (* 2 dt 86400)))))
               (facts (list :kind (body-kind body)
                            :sun (unless (eq body +sun+) sun)
                            :earth (unless (string= (body-name body) "Earth") earth)
                            :light (* earth (/ +km-per-au+ 299792.458d0))
                            :speed (unless (eq body +sun+) speed)
                            :radius (body-radius-km body)
                            :size (and (plusp earth)
                                       (* 2 206264.806d0 (/ (/ (body-radius-km body) +km-per-au+) earth))))))
          (when parent
            (setf (getf facts :parent-distance)
                  (* +km-per-au+ (multiple-value-call #'distance (funcall relative tc)))))
          (unless (or (eq body +sun+) (string= (body-name body) "Earth"))
            ;; Phase: the angle at the body between the Sun and the Earth.
            (let ((angle (separation (- x) (- y) (- z) (- gx) (- gy) (- gz))))
              (setf (getf facts :phase) (/ (+ 1 (cos (* angle +degrees+))) 2)
                    (getf facts :elongation) (separation (- ex) (- ey) (- ez) gx gy gz))))
          facts)))))
