;;;; comets.lisp -- a few famous comets, on their conic sections.
;;;;
;;;; Each is its osculating orbit at the perihelion it is known for, from
;;;; JPL Horizons (heliocentric, J2000 ecliptic): perihelion distance,
;;;; eccentricity, the time of perihelion, and the three angles. Two-body
;;;; motion from there is within a fraction of a degree of JPL's own
;;;; integration around that perihelion; far from it the planets' pulls,
;;;; and a comet's own jets, carry it off -- Halley's by a day at its 1986
;;;; perihelion, Hale-Bopp's by a whole orbit since Jupiter shortened it in
;;;; 1996, which is why the Small-Body Database's current elements are not
;;;; used here. Tsuchinshan-ATLAS is on
;;;; a hyperbola -- it came in from the Oort cloud and is leaving for good
;;;; -- so both conics are solved: Kepler's equation for the ellipse, from
;;;; a start that converges even at an eccentricity of 0.9992, and its
;;;; hyperbolic twin for the rest.

(in-package #:solar-system.core)

(defparameter +gauss+ 0.01720209895d0 "The Gaussian gravitational constant: radians a day at 1 AU.")

(defparameter *comet-elements*
  '(
    ("Halley" "1P/Halley" :q 5.871034488173393d-01 :e 9.672792271749998d-01 :tp 2.446470958961021d+06 :i 1.622422242700916d+02 :node 5.885993640671803d+01 :peri 1.118655480539208d+02)
    ("Encke" "2P/Encke" :q 3.395969560645750d-01 :e 8.469329982889625d-01 :tp 2.460240028291585d+06 :i 1.133650116708519d+01 :node 3.340187379482513d+02 :peri 1.872883069018290d+02)
    ("67P" "67P/Churyumov-Gerasimenko" :q 1.243258769756816d+00 :e 6.408747907061310d-01 :tp 2.457247586205268d+06 :i 7.040323352160453d+00 :node 5.013583024028684d+01 :peri 1.279601466792033d+01)
    ("Swift–Tuttle" "109P/Swift-Tuttle" :q 9.582167670401709d-01 :e 9.635910649295544d-01 :tp 2.448968824034196d+06 :i 1.134266314158627d+02 :node 1.394443402151469d+02 :peri 1.530014736204635d+02)
    ("Tempel–Tuttle" "55P/Tempel-Tuttle" :q 9.765853273340058d-01 :e 9.054980820101726d-01 :tp 2.450872596580421d+06 :i 1.624861455451949d+02 :node 2.352586254835554d+02 :peri 1.724969626256871d+02)
    ("Pons–Brooks" "12P/Pons-Brooks" :q 7.807881362192004d-01 :e 9.546113351997921d-01 :tp 2.460421624387140d+06 :i 7.419156117469920d+01 :node 2.558558149738149d+02 :peri 1.989887360232310d+02)
    ("Hale–Bopp" "C/1995 O1 (Hale-Bopp)" :q 9.141695085103265d-01 :e 9.951309034576423d-01 :tp 2.450539633095211d+06 :i 8.943017647394187d+01 :node 2.824705967367881d+02 :peri 1.305872456639791d+02)
    ("NEOWISE" "C/2020 F3 (NEOWISE)" :q 2.946512465205845d-01 :e 9.991781210696874d-01 :tp 2.459034178897501d+06 :i 1.289375034709085d+02 :node 6.101042915531990d+01 :peri 3.727865401815103d+01)
    ("Tsuchinshan–ATLAS" "C/2023 A3 (Tsuchinshan-ATLAS)" :q 3.914229237812405d-01 :e 1.000021225178465d+00 :tp 2.460581242029713d+06 :i 1.391105448520271d+02 :node 2.155945973664768d+01 :peri 3.084909842654490d+02))
  "Short name, full name, and the elements: q in AU, tp JD (TDB), angles in degrees.")

(defparameter *comets*
  (loop for (name full . elements) in *comet-elements*
        collect (make-body :name name :radius-km 5d0 :colour #(0.72 0.88 0.98)
                           :comet (list* :full-name full elements)))
  "The comets, as bodies.")

(defun solve-kepler-robust (m e)
  "E with E - e sin E = M, for any e below 1: Newton from Danby's start,
kept inside the bracket [M - e, M + e] where the root must lie."
  (let* ((m (- m (* 2 +pi+ (ffloor (+ m +pi+) (* 2 +pi+)))))    ; into [-pi, pi)
         (low (- m e)) (high (+ m e))
         (ea (+ m (* 0.85d0 e (if (minusp (sin m)) -1 1)))))
    (loop repeat 100
          do (let ((f (- ea (* e (sin ea)) m)))
               (when (< (abs f) 1d-14) (return))
               (if (plusp f) (setf high (min high ea)) (setf low (max low ea)))
               (let ((next (- ea (/ f (- 1 (* e (cos ea)))))))
                 (setf ea (if (<= low next high) next (* 0.5d0 (+ low high)))))))
    ea))

(defun solve-kepler-hyperbolic (m e)
  "H with e sinh H - H = M."
  (let ((h (* (if (minusp m) -1 1) (log (+ 1.8d0 (/ (* 2 (abs m)) e))))))
    (loop repeat 60
          do (let ((f (- (* e (sinh h)) h m)))
               (decf h (/ f (- (* e (cosh h)) 1)))
               (when (< (abs f) 1d-14) (return))))
    h))

(defun comet-plane-position (body jd)
  "Values x, y in the comet's orbital plane, perihelion along +x, AU."
  (destructuring-bind (&key q e tp &allow-other-keys) (body-comet body)
    (let* ((a (/ q (abs (- 1 e))))
           (n (/ +gauss+ (expt a 1.5d0)))
           (m (* n (- jd tp))))
      (if (< e 1)
          (let ((ea (solve-kepler-robust m e)))
            (values (* a (- (cos ea) e)) (* a (sqrt (- 1 (* e e))) (sin ea))))
          (let ((h (solve-kepler-hyperbolic m e)))
            (values (* a (- e (cosh h))) (* a (sqrt (- (* e e) 1)) (sinh h))))))))

(defun comet-angles (body)
  (destructuring-bind (&key i node peri &allow-other-keys) (body-comet body)
    (values (* (- peri 0d0) +degrees+) (* node +degrees+) (* i +degrees+))))

(defun comet-position (body tc)
  "Values x, y, z: the comet's heliocentric ecliptic J2000 position, AU."
  (multiple-value-bind (xp yp) (comet-plane-position body (tc-to-jd tc))
    (multiple-value-bind (argp node incl) (comet-angles body)
      (to-ecliptic xp yp argp node incl))))

(defparameter +comet-orbit-reach+ 60d0
  "AU: how far out a comet's orbit is drawn -- Hale-Bopp's goes to 350.")

(defun comet-orbit-points (body count)
  "COUNT+1 points along the comet's orbit, x y z triples in AU: all of it
if it turns back within +COMET-ORBIT-REACH+, else the arc inside it,
sampled evenly in true anomaly."
  (destructuring-bind (&key q e &allow-other-keys) (body-comet body)
    (let* ((points (make-array (* 3 (1+ count)) :element-type 'double-float))
           (p (* q (+ 1 e)))                        ; semi-latus rectum
           (aphelion (if (< e 1) (/ q (- 1 e) (/ 1 (+ 1 e))) nil))
           (limit (if (and aphelion (< aphelion +comet-orbit-reach+))
                      +pi+
                      (acos (max -1d0 (min 1d0 (/ (- (/ p +comet-orbit-reach+) 1) e)))))))
      (multiple-value-bind (argp node incl) (comet-angles body)
        (dotimes (k (1+ count) points)
          (let* ((nu (- (* 2 limit (/ k count)) limit))
                 (r (/ p (+ 1 (* e (cos nu))))))
            (multiple-value-bind (x y z) (to-ecliptic (* r (cos nu)) (* r (sin nu)) argp node incl)
              (setf (aref points (* 3 k)) x
                    (aref points (+ 1 (* 3 k))) y
                    (aref points (+ 2 (* 3 k))) z))))))))

(defun comet-tail (body tc)
  "Values the length in AU of the comet's tail at TC, and how bright it is,
0 to 1. Only inside about three AU does a comet's ice boil enough for a
tail; its length grows roughly as the inverse square of its distance from
the Sun, to a tenth or two of an AU near perihelion -- NEOWISE's, 0.15 AU
at 0.6 from the Sun, was about fifteen degrees long from the Earth. A
sketch of the physics, not a model of it."
  (let ((r (multiple-value-call #'distance (comet-position body tc))))
    (if (> r 3d0)
        (values 0d0 0d0)
        (values (min 0.3d0 (/ 0.06d0 (* r r)))
                (min 1d0 (/ 0.6d0 (* r r)))))))
