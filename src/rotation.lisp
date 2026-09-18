;;;; rotation.lisp -- which way each body faces.
;;;;
;;;; The IAU Working Group on Cartographic Coordinates and Rotational
;;;; Elements gives, for each body, the direction of its north pole in the
;;;; ICRF -- right ascension and declination, drifting slowly -- and the
;;;; angle W of its prime meridian, measured along its equator from where
;;;; that equator crosses the ICRF equator, growing by a steady rate a day.
;;;; From those, three axes fixed in the body: to longitude 0, to longitude
;;;; 90 east, and to the north pole, here in the J2000 ecliptic like
;;;; everything else. Venus, Uranus and Pluto turn backwards: their W falls.
;;;;
;;;; Periodic terms are left out -- the Moon's physical librations, Mars's
;;;; and Mercury's small wobbles -- which moves nothing on the screen.

(in-package #:solar-system.core)

(defparameter *rotation-elements*
  ;; name  (ra0 ra-per-century) (dec0 dec-per-century) (w0 w-per-day)
  '(("Sun"     (286.13d0 0d0)           (63.87d0 0d0)            (84.176d0 14.1844000d0))
    ("Mercury" (281.0103d0 -0.0328d0)   (61.4155d0 -0.0049d0)    (329.5988d0 6.1385108d0))
    ("Venus"   (272.76d0 0d0)           (67.16d0 0d0)            (160.20d0 -1.4813688d0))
    ("Earth"   (0d0 -0.641d0)           (90d0 -0.557d0)          (190.147d0 360.9856235d0))
    ("Moon"    (269.9949d0 0.0031d0)    (66.5392d0 0.0130d0)     (38.3213d0 13.17635815d0))
    ("Mars"    (317.68143d0 -0.1061d0)  (52.88650d0 -0.0609d0)   (176.630d0 350.89198226d0))
    ("Jupiter" (268.056595d0 -0.006499d0) (64.495303d0 0.002413d0) (284.95d0 870.5360000d0))
    ("Saturn"  (40.589d0 -0.036d0)      (83.537d0 -0.004d0)      (38.90d0 810.7939024d0))
    ("Uranus"  (257.311d0 0d0)          (-15.175d0 0d0)          (203.81d0 -501.1600928d0))
    ("Neptune" (299.36d0 0d0)           (43.46d0 0d0)            (249.978d0 541.1397757d0))
    ("Pluto"   (132.993d0 0d0)          (-6.163d0 0d0)           (302.695d0 56.3625225d0)))
  "IAU 2009 (Mars) and 2015 rotational elements, without periodic terms.
Neptune's pole and meridian also swing with N, added in POLE-AND-MERIDIAN.")

(defun pole-and-meridian (body tc)
  "Values RA and Dec of BODY's north pole and its W, in degrees, at TC; NIL
for a body with no rotation given."
  (let ((entry (rest (assoc (body-name body) *rotation-elements* :test #'string=))))
    (when entry
      (destructuring-bind ((ra0 ra1) (dec0 dec1) (w0 w1)) entry
        (let ((ra (+ ra0 (* ra1 tc)))
              (dec (+ dec0 (* dec1 tc)))
              (w (+ w0 (* w1 tc 36525d0))))
          (when (string= (body-name body) "Neptune")
            (let ((n (* +degrees+ (+ 357.85d0 (* 52.316d0 tc)))))
              (incf ra (* 0.70d0 (sin n)))
              (decf dec (* 0.51d0 (cos n)))
              (decf w (* 0.48d0 (sin n)))))
          (values ra dec (mod w 360d0)))))))

(defun icrf-to-ecliptic (x y z)
  (let ((c (cos +obliquity-j2000+)) (s (sin +obliquity-j2000+)))
    (values x (+ (* y c) (* z s)) (- (* z c) (* y s)))))

(defun body-axes (body tc)
  "Nine values: BODY's axes in the J2000 ecliptic at TC -- towards its
prime meridian on the equator, towards 90 degrees east, and its north
pole -- or NIL if it has no rotation given."
  (multiple-value-bind (ra dec w) (pole-and-meridian body tc)
    (when ra
      (let* ((a (* ra +degrees+)) (d (* dec +degrees+)) (w (* w +degrees+))
             ;; In the ICRF: the pole, and the node of the equator on the
             ;; ICRF equator, from which W is counted.
             (px (* (cos d) (cos a))) (py (* (cos d) (sin a))) (pz (sin d))
             (qx (- (sin a))) (qy (cos a)) (qz 0d0)
             ;; p x q, 90 degrees along the equator from the node.
             (rx (- (* py qz) (* pz qy))) (ry (- (* pz qx) (* px qz))) (rz (- (* px qy) (* py qx)))
             (xx (+ (* (cos w) qx) (* (sin w) rx)))
             (xy (+ (* (cos w) qy) (* (sin w) ry)))
             (xz (+ (* (cos w) qz) (* (sin w) rz)))
             ;; East: p x prime meridian.
             (yx (- (* py xz) (* pz xy))) (yy (- (* pz xx) (* px xz))) (yz (- (* px xy) (* py xx))))
        (multiple-value-call #'values
          (icrf-to-ecliptic xx xy xz)
          (icrf-to-ecliptic yx yy yz)
          (icrf-to-ecliptic px py pz))))))

(defun body-longitude-latitude (body tc x y z)
  "Values the planetocentric east longitude and latitude, degrees, of the
direction X Y Z (J2000 ecliptic) seen from BODY's centre."
  (multiple-value-bind (ax ay az bx by bz cx cy cz) (body-axes body tc)
    (let ((u (+ (* x ax) (* y ay) (* z az)))
          (v (+ (* x bx) (* y by) (* z bz)))
          (w (+ (* x cx) (* y cy) (* z cz))))
      (values (/ (* 180d0 (atan v u)) +pi+)
              (/ (* 180d0 (atan w (sqrt (+ (* u u) (* v v))))) +pi+)))))

(defun obliquity-of (body tc)
  "Degrees between BODY's north pole and the pole of its orbit."
  (multiple-value-bind (a e incl argp node) (elements body tc)
    (declare (ignore a e argp))
    (multiple-value-bind (ax ay az bx by bz px py pz) (body-axes body tc)
      (declare (ignore ax ay az bx by bz))
      (separation px py pz
                  (* (sin incl) (sin node)) (- (* (sin incl) (cos node))) (cos incl)))))
