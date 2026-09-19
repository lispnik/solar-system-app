;;;; moons.lisp -- the major moons, relative to their planets.
;;;;
;;;; Twenty moons from elements fitted to JPL Horizons (moon-elements.lisp):
;;;; in each moon's reference plane -- its Laplace plane, or its planet's
;;;; equator -- the node and the longitude of periapsis turn at steady
;;;; rates, the mean longitude runs as a quadratic, and for the three moons
;;;; held in resonance a libration swings it: Mimas by 43 degrees over 70
;;;; years, with Tethys, and Miranda by a degree and a half. A position is
;;;; Kepler in that plane, turned into the equator of J2000 and then into
;;;; the ecliptic. Over 1850 -- 2150 every moon is within a degree of
;;;; Horizons but Mimas (4.6) and Triton (2.8); outside it they drift.
;;;;
;;;; JPL's published table of mean elements was tried first and is not
;;;; this: its periods are rounded and not sidereal, and it serves near its
;;;; epoch, not over centuries.
;;;;
;;;; The Earth's Moon is too perturbed for any such model -- the Sun moves
;;;; it by degrees -- so it is computed from the main terms of ELP-2000 as
;;;; Meeus gives them (Astronomical Algorithms, ch. 47), within 0.01 degree
;;;; of Horizons.

(in-package #:solar-system.core)

(defconstant +km-per-au+ 149597870.7d0)
(defconstant +obliquity-j2000+ (* 23.4392911d0 +degrees+))
(defconstant +cos-obliquity+ (cos +obliquity-j2000+))
(defconstant +sin-obliquity+ (sin +obliquity-j2000+))

(deftype moon-vector () '(simple-array double-float (20)))

(defun moon-vector (&key pole a e i node peri l libration error)
  "A moon's elements as twenty doubles, so that a frame reads them without
parsing or consing: a (km) e i, the node's two coefficients, the
periapsis's two, the longitude's three, the libration's period, sine and
cosine (period 0 for none), the pole's cos RA, sin RA, cos Dec, sin Dec, and
the fit's error (0 for none)."
  (destructuring-bind (ra dec) pole
    (destructuring-bind (period sine cosine) (or libration '(0d0 0d0 0d0))
      (flet ((c (list n) (float (or (nth n list) 0d0) 1d0)))
        (coerce (list a e i (c node 0) (c node 1) (c peri 0) (c peri 1)
                      (c l 0) (c l 1) (c l 2) period sine cosine
                      (cos (* ra +degrees+)) (sin (* ra +degrees+))
                      (cos (* dec +degrees+)) (sin (* dec +degrees+))
                      (or error 0d0) 0d0 0d0)
                'moon-vector)))))

(defun moon-a (moon) (aref (the moon-vector (body-moon moon)) 0))
(defun moon-fit-error (moon)
  "The largest error in direction the fit saw, degrees; NIL for the Moon."
  (let ((error (aref (the moon-vector (body-moon moon)) 17)))
    (and (plusp error) error)))

(defparameter *moons*
  (cons
   ;; The Moon's mean elements (Meeus), in the ecliptic -- whose pole is at
   ;; RA 270, Dec 90 - obliquity -- draw its orbit; ELP places it.
   (make-body :name "Moon" :radius-km 1737.4d0 :colour #(0.80 0.80 0.78)
              :parent (find "Earth" *planets* :key #'body-name :test #'string=)
              :moon (moon-vector :pole (list 270d0 (- 90d0 23.4392911d0))
                                 :a 384400d0 :e 0.0549d0 :i 5.145d0
                                 :node (list 125.0445479d0 (/ -1934.1362891d0 36525))
                                 :peri (list 83.3532465d0 (/ 4069.0137287d0 36525))
                                 :l (list 218.3164477d0 (/ 481267.88123421d0 36525))))
   (loop for (name parent radius colour . elements) in *moon-elements*
         collect (make-body :name name :radius-km radius :colour colour
                            :parent (find parent (heliocentric-bodies) :key #'body-name
                                                                       :test #'string=)
                            :moon (apply #'moon-vector elements))))
  "The major moons, each with its parent.")

(defun find-body (name)
  (find name (append (list +sun+) (heliocentric-bodies) *moons* (symbol-value '*comets*))
        :key #'body-name :test #'string-equal))

(defun moons-of (body)
  (remove body *moons* :key #'body-parent :test-not #'eq))

;;; ------------------------------------------------------------------
;;; fitted elements

(defun moon-elements (moon tc)
  "Values a (AU), e, and in radians i, the argument of periapsis, the node
and the mean anomaly, in the moon's reference plane at TC."
  (declare (type double-float tc) (optimize (speed 3) (safety 0)))
  (let* ((v (body-moon moon))
         (days (* tc 36525d0))
         (ascending (+ (aref v 3) (* (aref v 4) days)))
         (periapsis (+ (aref v 5) (* (aref v 6) days)))
         (period (aref v 10))
         (longitude (+ (aref v 7) (* days (+ (aref v 8) (* days (aref v 9)))))))
    (declare (type moon-vector v)
             (type double-float days ascending periapsis period longitude))
    (when (plusp period)
      (let ((phase (/ (* 2d0 (float pi 1d0) days) period)))
        (declare (type double-float phase))
        (incf longitude (+ (* (aref v 11) (sin phase)) (* (aref v 12) (cos phase))))))
    (values (/ (aref v 0) +km-per-au+) (aref v 1) (* (aref v 2) +degrees+)
            (* (- periapsis ascending) +degrees+)
            (* ascending +degrees+)
            (* (normalize-degrees (- longitude periapsis)) +degrees+))))

(defun reference-to-ecliptic (moon x y z)
  "A vector in MOON's reference plane -- x to the plane's ascending node on
the ICRF equator, z its pole -- in the J2000 ecliptic."
  (declare (type double-float x y z) (optimize (speed 3) (safety 0)))
  (let* ((v (body-moon moon))
         (ca (aref v 13)) (sa (aref v 14)) (cd (aref v 15)) (sd (aref v 16))
         ;; node n = (-sa, ca, 0); y = p x n = (-sd ca, -sd sa, cd); p.
         (qx (+ (* x (- sa)) (* y (- (* sd ca))) (* z cd ca)))
         (qy (+ (* x ca) (* y (- (* sd sa))) (* z cd sa)))
         (qz (+ (* y cd) (* z sd))))
    (declare (type moon-vector v) (type double-float ca sa cd sd qx qy qz))
    (values qx
            (+ (* qy +cos-obliquity+) (* qz +sin-obliquity+))
            (- (* qz +cos-obliquity+) (* qy +sin-obliquity+)))))

(defun fitted-offset (moon tc)
  (multiple-value-bind (a e incl argp node m) (moon-elements moon tc)
    (let ((ea (solve-kepler m e)))
      (multiple-value-bind (x y z) (to-ecliptic (* a (- (cos ea) e))
                                                (* a (sqrt (- 1d0 (* e e))) (sin ea))
                                                argp node incl)
        (reference-to-ecliptic moon x y z)))))

(defun moon-orbit-points (moon tc count)
  "COUNT+1 points round MOON's orbit at TC, relative to its planet, as
x y z triples in AU."
  (let ((points (make-array (* 3 (1+ count)) :element-type 'double-float)))
    (multiple-value-bind (a e incl argp node) (moon-elements moon tc)
      (let ((minor (* a (sqrt (- 1d0 (* e e))))))
        (dotimes (k (1+ count) points)
          (let ((ea (/ (* 2d0 (float pi 1d0) k) count)))
            (multiple-value-bind (x y z) (to-ecliptic (* a (- (cos ea) e)) (* minor (sin ea))
                                                      argp node incl)
              (multiple-value-bind (x y z) (reference-to-ecliptic moon x y z)
                (setf (aref points (* 3 k)) x
                      (aref points (+ 1 (* 3 k))) y
                      (aref points (+ 2 (* 3 k))) z)))))))))

;;; ------------------------------------------------------------------
;;; the Moon: Meeus ch. 47

;;; D M M' F, then the sine coefficient of longitude and the cosine
;;; coefficient of distance: degrees and km, times 10^6 and 10^3.
(defparameter +lunar-longitude-distance+
  '((0 0 1 0 6288774 -20905355) (2 0 -1 0 1274027 -3699111) (2 0 0 0 658314 -2955968)
    (0 0 2 0 213618 -569925) (0 1 0 0 -185116 48888) (0 0 0 2 -114332 -3149)
    (2 0 -2 0 58793 246158) (2 -1 -1 0 57066 -152138) (2 0 1 0 53322 -170733)
    (2 -1 0 0 45758 -204586) (0 1 -1 0 -40923 -129620) (1 0 0 0 -34720 108743)
    (0 1 1 0 -30383 104755) (2 0 0 -2 15327 10321) (0 0 1 2 -12528 0)
    (0 0 1 -2 10980 79661) (4 0 -1 0 10675 -34782) (0 0 3 0 10034 -23210)
    (4 0 -2 0 8548 -21636) (2 1 -1 0 -7888 24208) (2 1 0 0 -6766 30824)
    (1 0 -1 0 -5163 -8379) (1 1 0 0 4987 -16675) (2 -1 1 0 4036 -12831)
    (2 0 2 0 3994 -10445) (4 0 0 0 3861 -11650) (2 0 -3 0 3665 14403)
    (0 1 -2 0 -2689 -7003) (2 0 -1 2 -2602 0) (2 -1 -2 0 2390 10056)
    (1 0 1 0 -2348 6322) (2 -2 0 0 2236 -9884) (0 1 2 0 -2120 5751)
    (0 2 0 0 -2069 0) (2 -2 -1 0 2048 -4950) (2 0 1 -2 -1773 4130)
    (2 0 0 2 -1595 0) (4 -1 -1 0 1215 -3958) (0 0 2 2 -1110 0)
    (3 0 -1 0 -892 3258) (2 1 1 0 -810 2616) (4 -1 -2 0 759 -1897)
    (0 2 -1 0 -713 -2117) (2 2 -1 0 -700 2354) (2 1 -2 0 691 0)
    (2 -1 0 -2 596 0) (4 0 1 0 549 -1423) (0 0 4 0 537 -1117)
    (4 -1 0 0 520 -1571) (1 0 -2 0 -487 -1739) (2 1 0 -2 -399 0)
    (0 0 2 -2 -381 -4421) (1 1 1 0 351 0) (3 0 -2 0 -340 0)
    (4 0 -3 0 330 0) (2 -1 2 0 327 0) (0 2 1 0 -323 1165)
    (1 1 -1 0 299 0) (2 0 3 0 294 0) (2 0 -1 -2 0 8752)))

;;; D M M' F, then the sine coefficient of latitude, degrees times 10^6.
(defparameter +lunar-latitude+
  '((0 0 0 1 5128122) (0 0 1 1 280602) (0 0 1 -1 277693) (2 0 0 -1 173237)
    (2 0 -1 1 55413) (2 0 -1 -1 46271) (2 0 0 1 32573) (0 0 2 1 17198)
    (2 0 1 -1 9266) (0 0 2 -1 8822) (2 -1 0 -1 8216) (2 0 -2 -1 4324)
    (2 0 1 1 4200) (2 1 0 -1 -3359) (2 -1 -1 1 2463) (2 -1 0 1 2211)
    (2 -1 -1 -1 2065) (0 1 -1 -1 -1870) (4 0 -1 -1 1828) (0 1 0 1 -1794)
    (0 0 0 3 -1749) (0 1 -1 1 -1565) (1 0 0 1 -1491) (0 1 1 1 -1475)
    (0 1 1 -1 -1410) (0 1 0 -1 -1344) (1 0 0 -1 -1335) (0 0 3 1 1107)
    (4 0 0 -1 1021) (4 0 -1 1 833)))

(defun flatten-terms (terms width)
  "TERMS as one (simple-array double-float) of WIDTH numbers a term."
  (let ((flat (make-array (* width (length terms)) :element-type 'double-float)))
    (loop for term in terms
          for base from 0 by width
          do (loop for x in term for i from base do (setf (aref flat i) (float x 1d0))))
    flat))

(defparameter +lunar-ld+ (flatten-terms +lunar-longitude-distance+ 6))
(defparameter +lunar-b+ (flatten-terms +lunar-latitude+ 5))

(defun lunar-position (tc)
  "Values x, y, z in AU: the Moon from the Earth's centre, in the J2000
ecliptic, at TC centuries of TT from J2000."
  (flet ((poly (&rest coefficients)
           (let ((sum 0d0) (power 1d0))
             (dolist (c coefficients sum)
               (incf sum (* c power))
               (setf power (* power tc))))))
    (let* ((lp (poly 218.3164477d0 481267.88123421d0 -0.0015786d0 (/ 1d0 538841) (/ -1d0 65194000)))
           (d (poly 297.8501921d0 445267.1114034d0 -0.0018819d0 (/ 1d0 545868) (/ -1d0 113065000)))
           (m (poly 357.5291092d0 35999.0502909d0 -0.0001536d0 (/ 1d0 24490000)))
           (mp (poly 134.9633964d0 477198.8675055d0 0.0087414d0 (/ 1d0 69699) (/ -1d0 14712000)))
           (f (poly 93.2720950d0 483202.0175233d0 -0.0036539d0 (/ -1d0 3526000) (/ 1d0 863310000)))
           (a1 (poly 119.75d0 131.849d0))
           (a2 (poly 53.09d0 479264.290d0))
           (a3 (poly 313.45d0 481266.484d0))
           (e (poly 1d0 -0.002516d0 -0.0000074d0))
           (sl 0d0) (sr 0d0) (sb 0d0))
      (declare (type double-float lp d m mp f a1 a2 a3 e sl sr sb)
               (optimize (speed 3) (safety 0)))
      (let ((d (* d +degrees+)) (m (* m +degrees+)) (mp (* mp +degrees+)) (f (* f +degrees+))
            (ld +lunar-ld+) (lb +lunar-b+))
        (declare (type double-float d m mp f)
                 (type (simple-array double-float (*)) ld lb))
        (flet ((eccentricity (cm)
                 (declare (type double-float cm))
                 (cond ((zerop cm) 1d0) ((= (abs cm) 1d0) e) (t (* e e)))))
          (declare (inline eccentricity))
          (loop for i of-type fixnum from 0 below (length ld) by 6
                do (let* ((cm (aref ld (+ i 1)))
                          (angle (+ (* (aref ld i) d) (* cm m) (* (aref ld (+ i 2)) mp)
                                    (* (aref ld (+ i 3)) f)))
                          (scale (eccentricity cm)))
                     (declare (type double-float cm angle scale))
                     (incf sl (* scale (aref ld (+ i 4)) (sin angle)))
                     (incf sr (* scale (aref ld (+ i 5)) (cos angle)))))
          (loop for i of-type fixnum from 0 below (length lb) by 5
                do (let* ((cm (aref lb (+ i 1)))
                          (angle (+ (* (aref lb i) d) (* cm m) (* (aref lb (+ i 2)) mp)
                                    (* (aref lb (+ i 3)) f))))
                     (declare (type double-float cm angle))
                     (incf sb (* (eccentricity cm) (aref lb (+ i 4)) (sin angle)))))))
      (flet ((sin-deg (x) (sin (* x +degrees+))))
        (incf sl (+ (* 3958 (sin-deg a1)) (* 1962 (sin-deg (- lp f))) (* 318 (sin-deg a2))))
        (incf sb (+ (* -2235 (sin-deg lp)) (* 382 (sin-deg a3)) (* 175 (sin-deg (- a1 f)))
                    (* 175 (sin-deg (+ a1 f))) (* 127 (sin-deg (- lp mp))) (* -115 (sin-deg (+ lp mp)))))
        ;; Longitude of date, to J2000 by the general precession in longitude.
        (let* ((longitude (* +degrees+ (- (+ lp (/ sl 1d6))
                                          (/ (+ (* 5029.0966d0 tc) (* 1.11113d0 tc tc)) 3600d0))))
               (latitude (* +degrees+ (/ sb 1d6)))
               (r (/ (+ 385000.56d0 (/ sr 1d3)) +km-per-au+)))
          (values (* r (cos latitude) (cos longitude))
                  (* r (cos latitude) (sin longitude))
                  (* r (sin latitude))))))))

(defun moon-offset (moon tc)
  "Values x, y, z in AU: MOON relative to its planet, J2000 ecliptic."
  (if (string= (body-name moon) "Moon")
      (lunar-position tc)
      (fitted-offset moon tc)))
