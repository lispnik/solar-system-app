;;;; ephemeris.lisp -- where the planets are, at any instant.
;;;;
;;;; E. M. Standish, "Keplerian Elements for Approximate Positions of the
;;;; Major Planets" (JPL; https://ssd.jpl.nasa.gov/planets/approx_pos.html):
;;;; six elements and their rates per Julian century, with respect to the
;;;; mean ecliptic and equinox of J2000. Table 1 is fitted over 1800 -- 2050
;;;; and is used there; tables 2a and 2b are fitted over 3000 BC -- 3000 AD
;;;; and are used outside it. Checked against Horizons, table 1 is within
;;;; 0.15 degree for every planet over 1900 -- 2026 (Saturn the worst), where
;;;; table 2 is 0.3 degree out for Saturn at J2000.
;;;;
;;;; Kepler's equation is solved afresh for every body on every frame;
;;;; nothing is integrated, so any date is as cheap as the next.
;;;;
;;;; Positions are heliocentric ecliptic J2000, in AU: x towards the vernal
;;;; equinox, z towards the north ecliptic pole. Looking down from +z, the
;;;; planets go round anticlockwise.

(in-package #:solar-system.core)

(defconstant +degrees+ (/ (float pi 1d0) 180d0))

;;; A body's elements are two tables of twelve numbers: the six elements at
;;; J2000, in the order a (AU), e, I, L (mean longitude), long. perihelion,
;;; long. node (degrees), then their six rates per Julian century.

(defstruct (body (:constructor make-body))
  (name "" :type string)
  (table-1 nil)         ; 1800 -- 2050: the closer fit, used inside it
  (table-2 nil)         ; 3000 BC -- 3000 AD: used outside
  ;; Table 2b, Jupiter to Neptune only, and only with table 2:
  ;; M += b T^2 + c cos(f T) + s sin(f T), all in degrees.
  (extra nil)
  ;; Dwarf planets: osculating elements sampled every ten years
  ;; (dwarf-elements.lisp), each #(jd a e i node peri-arg mean-anomaly n).
  (samples nil)
  ;; Moons: the body they go round, and how (satellites.lisp).
  (parent nil)
  (moon nil)
  ;; Comets: their conic's elements (comets.lisp).
  (comet nil)
  ;; Not the ephemeris: for drawing, and for the barycentre.
  (radius-km 0d0 :type double-float)
  (mass-ratio 0d0 :type double-float)     ; Sun's mass / the planet system's
  (colour #(1.0 1.0 1.0) :type simple-vector))

(defun table (&rest numbers)
  (coerce numbers '(simple-array double-float (12))))

(defparameter *planets*
  (list
   ;;                   a            e            I             L               long.peri.     long.node.
   (make-body
    :name "Mercury" :radius-km 2439.7d0 :mass-ratio 6023600d0 :colour #(0.66 0.63 0.60)
    :table-1 (table 0.38709927d0 0.20563593d0 7.00497902d0 252.25032350d0 77.45779628d0 48.33076593d0
                    0.00000037d0 0.00001906d0 -0.00594749d0 149472.67411175d0 0.16047689d0 -0.12534081d0)
    :table-2 (table 0.38709843d0 0.20563661d0 7.00559432d0 252.25166724d0 77.45771895d0 48.33961819d0
                    0.00000000d0 0.00002123d0 -0.00590158d0 149472.67486623d0 0.15940013d0 -0.12214182d0))
   (make-body
    :name "Venus" :radius-km 6051.8d0 :mass-ratio 408523.71d0 :colour #(0.93 0.83 0.60)
    :table-1 (table 0.72333566d0 0.00677672d0 3.39467605d0 181.97909950d0 131.60246718d0 76.67984255d0
                    0.00000390d0 -0.00004107d0 -0.00078890d0 58517.81538729d0 0.00268329d0 -0.27769418d0)
    :table-2 (table 0.72332102d0 0.00676399d0 3.39777545d0 181.97970850d0 131.76755713d0 76.67261496d0
                    -0.00000026d0 -0.00005107d0 0.00043494d0 58517.81560260d0 0.05679648d0 -0.27274174d0))
   ;; The Earth-Moon barycentre: the Earth itself is within 5000 km of it.
   (make-body
    :name "Earth" :radius-km 6371.0d0 :mass-ratio 328900.56d0 :colour #(0.30 0.56 0.98)
    :table-1 (table 1.00000261d0 0.01671123d0 -0.00001531d0 100.46457166d0 102.93768193d0 0.0d0
                    0.00000562d0 -0.00004392d0 -0.01294668d0 35999.37244981d0 0.32327364d0 0.0d0)
    :table-2 (table 1.00000018d0 0.01673163d0 -0.00054346d0 100.46691572d0 102.93005885d0 -5.11260389d0
                    -0.00000003d0 -0.00003661d0 -0.01337178d0 35999.37306329d0 0.31795260d0 -0.24123856d0))
   (make-body
    :name "Mars" :radius-km 3389.5d0 :mass-ratio 3098708d0 :colour #(0.88 0.42 0.26)
    :table-1 (table 1.52371034d0 0.09339410d0 1.84969142d0 -4.55343205d0 -23.94362959d0 49.55953891d0
                    0.00001847d0 0.00007882d0 -0.00813131d0 19140.30268499d0 0.44441088d0 -0.29257343d0)
    :table-2 (table 1.52371243d0 0.09336511d0 1.85181869d0 -4.56813164d0 -23.91744784d0 49.71320984d0
                    0.00000097d0 0.00009149d0 -0.00724757d0 19140.29934243d0 0.45223625d0 -0.26852431d0))
   (make-body
    :name "Jupiter" :radius-km 69911d0 :mass-ratio 1047.3486d0 :colour #(0.86 0.73 0.56)
    :table-1 (table 5.20288700d0 0.04838624d0 1.30439695d0 34.39644051d0 14.72847983d0 100.47390909d0
                    -0.00011607d0 -0.00013253d0 -0.00183714d0 3034.74612775d0 0.21252668d0 0.20469106d0)
    :table-2 (table 5.20248019d0 0.04853590d0 1.29861416d0 34.33479152d0 14.27495244d0 100.29282654d0
                    -0.00002864d0 0.00018026d0 -0.00322699d0 3034.90371757d0 0.18199196d0 0.13024619d0)
    :extra '(-0.00012452d0 0.06064060d0 -0.35635438d0 38.35125000d0))
   (make-body
    :name "Saturn" :radius-km 58232d0 :mass-ratio 3497.898d0 :colour #(0.91 0.83 0.62)
    :table-1 (table 9.53667594d0 0.05386179d0 2.48599187d0 49.95424423d0 92.59887831d0 113.66242448d0
                    -0.00125060d0 -0.00050991d0 0.00193609d0 1222.49362201d0 -0.41897216d0 -0.28867794d0)
    :table-2 (table 9.54149883d0 0.05550825d0 2.49424102d0 50.07571329d0 92.86136063d0 113.63998702d0
                    -0.00003065d0 -0.00032044d0 0.00451969d0 1222.11494724d0 0.54179478d0 -0.25015002d0)
    :extra '(0.00025899d0 -0.13434469d0 0.87320147d0 38.35125000d0))
   (make-body
    :name "Uranus" :radius-km 25362d0 :mass-ratio 22902.98d0 :colour #(0.62 0.86 0.90)
    :table-1 (table 19.18916464d0 0.04725744d0 0.77263783d0 313.23810451d0 170.95427630d0 74.01692503d0
                    -0.00196176d0 -0.00004397d0 -0.00242939d0 428.48202785d0 0.40805281d0 0.04240589d0)
    :table-2 (table 19.18797948d0 0.04685740d0 0.77298127d0 314.20276625d0 172.43404441d0 73.96250215d0
                    -0.00020455d0 -0.00001550d0 -0.00180155d0 428.49512595d0 0.09266985d0 0.05739699d0)
    :extra '(0.00058331d0 -0.97731848d0 0.17689245d0 7.67025000d0))
   (make-body
    :name "Neptune" :radius-km 24622d0 :mass-ratio 19412.24d0 :colour #(0.38 0.52 0.98)
    :table-1 (table 30.06992276d0 0.00859048d0 1.77004347d0 -55.12002969d0 44.96476227d0 131.78422574d0
                    0.00026291d0 0.00005105d0 0.00035372d0 218.45945325d0 -0.32241464d0 -0.00508664d0)
    :table-2 (table 30.06952752d0 0.00895439d0 1.77005520d0 304.22289287d0 46.68158724d0 131.78635853d0
                    0.00006447d0 0.00000818d0 0.00022400d0 218.46515314d0 0.01009938d0 -0.00606302d0)
    :extra '(-0.00041348d0 0.68346318d0 -0.10162547d0 7.67025000d0)))
  "The eight planets, Mercury outwards.")

(defparameter +sun+
  (make-body :name "Sun" :radius-km 695700d0 :mass-ratio 1d0 :colour #(1.0 0.84 0.42)))

(defun find-planet (name)
  (find name *planets* :key #'body-name :test #'string-equal))

;;; ------------------------------------------------------------------
;;; Kepler

(declaim (inline solve-kepler normalize-degrees to-ecliptic))
(defun solve-kepler (m e)
  "The eccentric anomaly E, in radians, with E - e sin E = M. Newton from
E0 = M + e sin M, which converges in a handful of steps for every planet
here: the largest e is Mercury's, 0.21."
  (declare (type double-float m e) (optimize (speed 3) (safety 0)))
  (let ((ea (+ m (* e (sin m)))))
    (declare (type double-float ea))
    (loop repeat 30
          for delta of-type double-float = (/ (- ea (* e (sin ea)) m)
                                              (- 1d0 (* e (cos ea))))
          do (decf ea delta)
          until (< (abs delta) 1d-12))
    ea))

(defun normalize-degrees (x)
  "X into [-180, 180)."
  (declare (type double-float x))
  (- (mod (+ x 180d0) 360d0) 180d0))

(defun table-1-p (tc)
  "Is TC, in centuries from J2000, inside 1800 -- 2050, where table 1 holds?"
  (<= -2d0 tc 0.5d0))

(defun elements (body tc)
  "Values a, e, and in radians I, the argument of perihelion, the node, and
the mean anomaly, at TC centuries of TT from J2000."
  (declare (type body body) (type double-float tc) (optimize (speed 3) (safety 0)))
  (when (body-samples body)
    (return-from elements (sample-elements (nearest-sample body tc) (tc-to-jd tc))))
  (let* ((modern (table-1-p tc))
         (table (if modern (body-table-1 body) (body-table-2 body))))
    (declare (type (simple-array double-float (12)) table))
    (flet ((at (k) (+ (aref table k) (* (aref table (+ k 6)) tc))))
      (declare (inline at))
      (let* ((a (at 0)) (e (at 1)) (i (at 2)) (l (at 3)) (peri (at 4)) (node (at 5))
             (m (- l peri)))
        (declare (type double-float a e i l peri node m))
        (when (and (not modern) (body-extra body))
          (destructuring-bind (b c s f) (body-extra body)
            (let ((f-tc (* f tc +degrees+)))
              (incf m (+ (* b tc tc) (* c (cos f-tc)) (* s (sin f-tc)))))))
        (values a e
                (* i +degrees+)
                (* (- peri node) +degrees+)
                (* node +degrees+)
                (* (normalize-degrees m) +degrees+))))))

(defun to-ecliptic (xp yp argp node incl)
  "A point (XP, YP) in the orbital plane, perihelion along +x, rotated into
the J2000 ecliptic: by the argument of perihelion, the inclination and the
node. Values x, y, z."
  (declare (type double-float xp yp argp node incl) (optimize (speed 3) (safety 0)))
  (let ((cw (cos argp)) (sw (sin argp))
        (cn (cos node)) (sn (sin node))
        (ci (cos incl)) (si (sin incl)))
    (values (+ (* (- (* cw cn) (* sw sn ci)) xp)
               (* (- (+ (* sw cn) (* cw sn ci))) yp))
            (+ (* (+ (* cw sn) (* sw cn ci)) xp)
               (* (- (* cw cn ci) (* sw sn)) yp))
            (+ (* sw si xp)
               (* cw si yp)))))

(defun heliocentric-position (body tc)
  "Values x, y, z in AU: BODY's heliocentric ecliptic J2000 position at TC
centuries of TT from J2000."
  (when (body-samples body)
    (return-from heliocentric-position (sampled-position body tc)))
  (when (body-comet body)
    (return-from heliocentric-position (comet-position body tc)))
  (multiple-value-bind (a e incl argp node m) (elements body tc)
    (let ((ea (solve-kepler m e)))
      (to-ecliptic (* a (- (cos ea) e))
                   (* a (sqrt (- 1d0 (* e e))) (sin ea))
                   argp node incl))))

(defun aphelion (body tc)
  (multiple-value-bind (a e) (elements body tc)
    (* a (+ 1d0 e))))

(defun orbit-points (body tc count)
  "COUNT+1 points round BODY's orbit at TC, closed, as a vector of x y z
triples in AU. Stepped evenly in eccentric anomaly, which puts more of them
near perihelion, where the curve bends most."
  (let ((points (make-array (* 3 (1+ count)) :element-type 'double-float)))
    (multiple-value-bind (a e incl argp node) (elements body tc)
      (let ((minor (* a (sqrt (- 1d0 (* e e))))))
        (dotimes (k (1+ count) points)
          (let ((ea (/ (* 2d0 (float pi 1d0) k) count)))
            (multiple-value-bind (x y z) (to-ecliptic (* a (- (cos ea) e)) (* minor (sin ea))
                                                      argp node incl)
              (setf (aref points (* 3 k)) x
                    (aref points (+ 1 (* 3 k))) y
                    (aref points (+ 2 (* 3 k))) z))))))))

;;; ------------------------------------------------------------------
;;; the Sun, relative to the barycentre

(defun sun-barycentric-offset (tc)
  "Values x, y, z: the Sun's position relative to the solar system's centre
of mass, in AU. Jupiter moves it by about its own radius; all eight together
by up to two of them."
  (let ((sx 0d0) (sy 0d0) (sz 0d0) (total 1d0))
    (dolist (planet *planets*)
      (let ((mu (/ 1d0 (body-mass-ratio planet))))
        (multiple-value-bind (x y z) (heliocentric-position planet tc)
          (incf sx (* mu x)) (incf sy (* mu y)) (incf sz (* mu z))
          (incf total mu))))
    (values (- (/ sx total)) (- (/ sy total)) (- (/ sz total)))))

(defparameter *frame* :heliocentric
  "Where the origin is: :HELIOCENTRIC, the Sun, or :BARYCENTRIC, the centre
of mass, about which the Sun itself wobbles.")

(defun body-positions (tc &optional (into (make-array 27 :element-type 'double-float)))
  "The Sun then the eight planets, x y z each, into a vector of 27 doubles,
in *FRAME*."
  (multiple-value-bind (ox oy oz)
      (if (eq *frame* :barycentric) (sun-barycentric-offset tc) (values 0d0 0d0 0d0))
    (setf (aref into 0) ox (aref into 1) oy (aref into 2) oz)
    (loop for planet in *planets*
          for k from 3 by 3
          do (multiple-value-bind (x y z) (heliocentric-position planet tc)
               (setf (aref into k) (+ x ox)
                     (aref into (+ k 1)) (+ y oy)
                     (aref into (+ k 2)) (+ z oz))))
    into))
