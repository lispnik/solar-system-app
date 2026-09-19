;;;; events.lisp -- eclipses, transits, oppositions and conjunctions.
;;;;
;;;; Found, not tabulated: everything here is searched for in the same
;;;; ephemeris the app draws, so any date in its range has its events.
;;;;
;;;; Eclipses start from the new and full moons -- the times the Moon's
;;;; longitude, seen from the Earth, equals the Sun's or is opposite it,
;;;; found by Newton's method from the mean lunation -- and are decided by
;;;; the geometry of the shadows at the moment of greatest eclipse. For the
;;;; Sun: the shadow cone of the Moon, and how near its axis passes to the
;;;; Earth's centre; for the Moon: the Earth's shadow, enlarged by the usual
;;;; two per cent for the atmosphere, and how deep the Moon goes into it.
;;;; Transits, oppositions and conjunctions are the moments one geocentric
;;;; longitude passes another, bracketed by stepping two days at a time and
;;;; then bisected.
;;;;
;;;; Standish's "Earth" is the Earth-Moon barycentre, 4,670 km from the
;;;; Earth's centre -- three quarters of an Earth radius, which is the whole
;;;; difference between a total eclipse and none -- so the Earth itself is
;;;; put back where the Moon says it is.
;;;;
;;;; Times are Julian Dates in TT; EVENT-UTC gives UTC.

(in-package #:solar-system.core)

(defconstant +pi+ (float pi 1d0) "pi, as a double: ECL's PI is a long float.")
(defparameter +earth-moon-mass-ratio+ 81.30056d0)
(defparameter +sun-radius-km+ 696000d0)
(defparameter +earth-radius-km+ 6378.14d0)
(defparameter +moon-radius-km+ 1737.4d0)
(defparameter +shadow-enlargement+ 1.02d0
  "The Earth's shadow is larger than its geometry by about 2 per cent: the
atmosphere (Chauvenet's rule).")

(defstruct (event (:constructor make-event (jd kind title)))
  (jd 0d0 :type double-float)                ; TT
  (kind nil :type keyword)                   ; :solar-eclipse :lunar-eclipse :transit
                                             ; :opposition :conjunction
  (title "" :type string))

;;; ------------------------------------------------------------------
;;; seen from the Earth

(defun jd-tc (jd) (centuries-since-j2000 jd))

(defun earth-position (tc)
  "Values x, y, z in AU: the Earth's centre, heliocentric."
  (multiple-value-bind (bx by bz) (heliocentric-position (find-planet "Earth") tc)
    (multiple-value-bind (mx my mz) (lunar-position tc)
      (let ((f (/ 1d0 (1+ +earth-moon-mass-ratio+))))
        (values (- bx (* f mx)) (- by (* f my)) (- bz (* f mz)))))))

(defun geocentric (body tc)
  "Values x, y, z in AU: BODY -- the Sun, a planet, or :MOON -- from the
Earth's centre."
  (cond ((eq body :moon) (lunar-position tc))
        (t (multiple-value-bind (ex ey ez) (earth-position tc)
             (if (eq body +sun+)
                 (values (- ex) (- ey) (- ez))
                 (multiple-value-bind (x y z) (heliocentric-position body tc)
                   (values (- x ex) (- y ey) (- z ez))))))))

(defun ecliptic-longitude (x y)
  (mod (/ (* 180d0 (atan y x)) +pi+) 360d0))

(defun wrap-180 (degrees)
  (- (mod (+ degrees 180d0) 360d0) 180d0))

(defun separation (ax ay az bx by bz)
  "Degrees between two directions."
  (let ((cosine (/ (+ (* ax bx) (* ay by) (* az bz))
                   (sqrt (* (+ (* ax ax) (* ay ay) (* az az)) (+ (* bx bx) (* by by) (* bz bz)))))))
    (/ (* 180d0 (acos (max -1d0 (min 1d0 cosine)))) +pi+)))

(defun geocentric-longitude (body jd)
  (multiple-value-bind (x y) (geocentric body (jd-tc jd))
    (ecliptic-longitude x y)))

(defun body-separation (a b jd)
  (let ((tc (jd-tc jd)))
    (multiple-value-call #'separation (geocentric a tc) (geocentric b tc))))

;;; ------------------------------------------------------------------
;;; searching

(defun bisect (function low high &optional (iterations 30))
  "A root of FUNCTION between LOW and HIGH, where it changes sign."
  (let ((f-low (funcall function low)))
    (loop repeat iterations
          do (let* ((middle (* 0.5d0 (+ low high)))
                    (f-middle (funcall function middle)))
               (if (eq (minusp f-middle) (minusp f-low))
                   (setf low middle f-low f-middle)
                   (setf high middle))))
    (* 0.5d0 (+ low high))))

(defun minimize (function low high &optional (iterations 40))
  "Values the time between LOW and HIGH where FUNCTION is least, and that
least value: a golden-section search."
  (let* ((ratio (/ (- (sqrt 5d0) 1d0) 2d0))
         (c (- high (* ratio (- high low))))
         (d (+ low (* ratio (- high low))))
         (fc (funcall function c))
         (fd (funcall function d)))
    (loop repeat iterations
          do (if (< fc fd)
                 (setf high d d c fd fc c (- high (* ratio (- high low))) fc (funcall function c))
                 (setf low c c d fc fd d (+ low (* ratio (- high low))) fd (funcall function d))))
    (let ((best (* 0.5d0 (+ low high))))
      (values best (funcall function best)))))

;;; ------------------------------------------------------------------
;;; new and full moons

(defparameter +synodic-month+ 29.530588861d0)
(defparameter +new-moon-epoch+ 2451550.09766d0 "Meeus's first new moon of 2000, JDE.")

(defun syzygy (jd target)
  "The moment near JD when the Moon's geocentric longitude is TARGET degrees
from the Sun's: 0 new, 180 full. Newton, with the mean relative motion."
  (loop repeat 8
        do (let ((error (wrap-180 (- (geocentric-longitude :moon jd)
                                     (geocentric-longitude +sun+ jd)
                                     target))))
             (decf jd (/ error 12.190749d0))))
  jd)

;;; ------------------------------------------------------------------
;;; eclipses

(defun solar-shadow (jd)
  "Values the distance in km from the Earth's centre to the axis of the
Moon's shadow, the distance along that axis from the Moon, and the Moon-Sun
distance, at JD."
  (let ((tc (jd-tc jd)) (km +km-per-au+))
    (multiple-value-bind (sx sy sz) (geocentric +sun+ tc)
      (multiple-value-bind (mx my mz) (lunar-position tc)
        (let* ((sx (* km sx)) (sy (* km sy)) (sz (* km sz))
               (mx (* km mx)) (my (* km my)) (mz (* km mz))
               (ax (- mx sx)) (ay (- my sy)) (az (- mz sz))
               (length (sqrt (+ (* ax ax) (* ay ay) (* az az))))
               (ux (/ ax length)) (uy (/ ay length)) (uz (/ az length))
               (along (- (+ (* mx ux) (* my uy) (* mz uz))))
               (px (+ mx (* along ux))) (py (+ my (* along uy))) (pz (+ mz (* along uz))))
          (values (sqrt (+ (* px px) (* py py) (* pz pz))) along length))))))

(defun solar-eclipse (new-moon)
  "An EVENT if there is a solar eclipse near NEW-MOON, else NIL."
  (multiple-value-bind (jd miss)
      (minimize (lambda (jd) (values (solar-shadow jd))) (- new-moon 0.3d0) (+ new-moon 0.3d0))
    (multiple-value-bind (again along moon-sun) (solar-shadow jd)
      (declare (ignore again))                ; MISS, from the search
      (let* ((penumbra (+ +moon-radius-km+ (* along (/ (+ +sun-radius-km+ +moon-radius-km+) moon-sun))))
             ;; The umbra where the axis meets the surface, on the Moon's side.
             (surface (- along (sqrt (max 0d0 (- (expt +earth-radius-km+ 2) (expt miss 2))))))
             (umbra (- +moon-radius-km+ (* surface (/ (- +sun-radius-km+ +moon-radius-km+) moon-sun)))))
        (cond ((> miss (+ +earth-radius-km+ penumbra)) nil)
              ((< miss (+ +earth-radius-km+ (abs umbra)))
               (make-event jd :solar-eclipse
                           (if (plusp umbra) "Total solar eclipse" "Annular solar eclipse")))
              (t (make-event jd :solar-eclipse "Partial solar eclipse")))))))

(defun lunar-shadow (jd)
  "Values the Moon's distance in km from the axis of the Earth's shadow,
its distance along it, and the Earth-Sun distance, at JD."
  (let ((tc (jd-tc jd)) (km +km-per-au+))
    (multiple-value-bind (sx sy sz) (geocentric +sun+ tc)
      (multiple-value-bind (mx my mz) (lunar-position tc)
        (let* ((length (* km (sqrt (+ (* sx sx) (* sy sy) (* sz sz)))))
               (ux (/ (* km (- sx)) length)) (uy (/ (* km (- sy)) length)) (uz (/ (* km (- sz)) length))
               (mx (* km mx)) (my (* km my)) (mz (* km mz))
               (along (+ (* mx ux) (* my uy) (* mz uz)))
               (px (- mx (* along ux))) (py (- my (* along uy))) (pz (- mz (* along uz))))
          (values (sqrt (+ (* px px) (* py py) (* pz pz))) along length))))))

(defun lunar-eclipse (full-moon)
  "An EVENT if there is a lunar eclipse near FULL-MOON, else NIL."
  (multiple-value-bind (jd)
      (minimize (lambda (jd) (values (lunar-shadow jd))) (- full-moon 0.3d0) (+ full-moon 0.3d0))
    (multiple-value-bind (miss along earth-sun) (lunar-shadow jd)
      (let ((umbra (* +shadow-enlargement+
                      (- +earth-radius-km+ (* along (/ (- +sun-radius-km+ +earth-radius-km+) earth-sun)))))
            (penumbra (* +shadow-enlargement+
                         (+ +earth-radius-km+ (* along (/ (+ +sun-radius-km+ +earth-radius-km+) earth-sun))))))
        (cond ((< (+ miss +moon-radius-km+) umbra) (make-event jd :lunar-eclipse "Total lunar eclipse"))
              ((< (- miss +moon-radius-km+) umbra) (make-event jd :lunar-eclipse "Partial lunar eclipse"))
              ((< (- miss +moon-radius-km+) penumbra)
               (make-event jd :lunar-eclipse "Penumbral lunar eclipse"))
              (t nil))))))

(defun eclipses-between (from to)
  "The eclipses whose greatest moment is in [FROM, TO)."
  (let ((first-k (floor (- from +new-moon-epoch+) +synodic-month+))
        (events '()))
    (loop for k from (1- first-k)
          for mean = (+ +new-moon-epoch+ (* k +synodic-month+))
          while (< mean (+ to +synodic-month+))
          do (dolist (phase '(0d0 180d0))
               (let ((jd (syzygy (+ mean (if (zerop phase) 0d0 (/ +synodic-month+ 2))) phase)))
                 ;; Only near a node can there be one: the Moon within a
                 ;; couple of degrees of the ecliptic.
                 (when (< (abs (multiple-value-bind (x y z) (lunar-position (jd-tc jd))
                                 (/ (* 180d0 (atan z (sqrt (+ (* x x) (* y y))))) +pi+)))
                          1.7d0)
                   (let ((event (if (zerop phase) (solar-eclipse jd) (lunar-eclipse jd))))
                     (when (and event (<= from (event-jd event)) (< (event-jd event) to))
                       (push event events)))))))
    (nreverse events)))

;;; ------------------------------------------------------------------
;;; transits, oppositions, conjunctions

(defparameter +step-days+ 2d0)

(defun crossings (function from to)
  "Times in [FROM, TO) where FUNCTION, an angle in (-180, 180], passes
through zero going either way -- not where it wraps round at 180."
  (let ((times '())
        (previous (funcall function from)))
    (loop for jd from (+ from +step-days+) below (+ to +step-days+) by +step-days+
          for value = (funcall function jd)
          do (when (and (not (eq (minusp value) (minusp previous)))
                        (< (abs value) 45d0) (< (abs previous) 45d0))
               (let ((root (bisect function (- jd +step-days+) jd)))
                 (when (and (<= from root) (< root to)) (push root times))))
             (setf previous value))
    (nreverse times)))

(defun transits-between (from to)
  (loop for name in '("Mercury" "Venus")
        for planet = (find-planet name)
        nconc (loop for jd in (crossings (lambda (jd) (wrap-180 (- (geocentric-longitude planet jd)
                                                                   (geocentric-longitude +sun+ jd))))
                                         from to)
                    for tc = (jd-tc jd)
                    ;; Inferior: nearer than the Sun.
                    when (< (multiple-value-call #'distance (geocentric planet tc))
                            (multiple-value-call #'distance (geocentric +sun+ tc)))
                      nconc (multiple-value-bind (best least)
                                (minimize (lambda (jd) (body-separation planet +sun+ jd))
                                          (- jd 0.5d0) (+ jd 0.5d0))
                              (let ((sun-radius (/ (* 180d0 (atan +sun-radius-km+
                                                                  (* +km-per-au+ (multiple-value-call
                                                                                     #'distance
                                                                                   (geocentric +sun+ (jd-tc best))))))
                                                   +pi+)))
                                (when (< least sun-radius)
                                  (list (make-event best :transit (format nil "Transit of ~a" name)))))))))

(defun distance (x y z) (sqrt (+ (* x x) (* y y) (* z z))))

(defun oppositions-between (from to)
  (loop for name in '("Mars" "Jupiter" "Saturn" "Uranus" "Neptune")
        for planet = (find-planet name)
        nconc (loop for jd in (crossings (lambda (jd) (wrap-180 (- (geocentric-longitude planet jd)
                                                                   (geocentric-longitude +sun+ jd)
                                                                   180d0)))
                                         from to)
                    collect (make-event jd :opposition (format nil "~a at opposition" name)))))

(defparameter +close-conjunction+ 0.5d0 "Degrees: closer than this is an event.")
(defparameter +glare+ 12d0 "Degrees from the Sun within which a conjunction is lost in its light.")

(defun conjunctions-between (from to)
  (let ((names '("Mercury" "Venus" "Mars" "Jupiter" "Saturn")))
    (loop for (a-name . rest) on names
          for a = (find-planet a-name)
          nconc (loop for b-name in rest
                      for b = (find-planet b-name)
                      nconc (loop for jd in (crossings (lambda (jd) (wrap-180 (- (geocentric-longitude a jd)
                                                                                 (geocentric-longitude b jd))))
                                                       from to)
                                  nconc (multiple-value-bind (best least)
                                            (minimize (lambda (jd) (body-separation a b jd))
                                                      (- jd 2d0) (+ jd 2d0))
                                          (when (and (< least +close-conjunction+)
                                                     (> (body-separation a +sun+ best) +glare+))
                                            (list (make-event best :conjunction
                                                              (format nil "~a–~a conjunction, ~,1f°"
                                                                      a-name b-name least))))))))))

;;; ------------------------------------------------------------------
;;; all of them

(defparameter +chunk-days+ 30d0 "The grid events are searched in.")

(defun events-in-chunk (start)
  "Every event in [START, START + +CHUNK-DAYS+), in order."
  (let ((end (+ start +chunk-days+)))
    (sort (append (eclipses-between start end)
                  (transits-between start end)
                  (oppositions-between start end)
                  (conjunctions-between start end))
          #'< :key #'event-jd)))

(defun chunk-start (jd)
  (* +chunk-days+ (ffloor jd +chunk-days+)))

(defun find-events (from to)
  "Every event between FROM and TO, JD (TT), in order."
  (loop for start from (chunk-start from) below to by +chunk-days+
        nconc (remove-if-not (lambda (event) (<= from (event-jd event) to))
                             (events-in-chunk start))))

(defun event-utc (event)
  "The event's moment as a JD in UTC, for the clock."
  (- (event-jd event) (/ *delta-t* 86400d0)))

;;; ------------------------------------------------------------------
;;; where to stand

(defun eclipse-surface-point (jd)
  "Values the planetocentric east longitude and latitude, degrees, of the
point of greatest eclipse at JD (TT): where the axis of the Moon's shadow
meets the Earth's surface on the Moon's side -- or, where it misses, the
point nearest it."
  (let ((tc (jd-tc jd)) (km +km-per-au+))
    (multiple-value-bind (sx sy sz) (geocentric +sun+ tc)
      (multiple-value-bind (mx my mz) (lunar-position tc)
        (let* ((sx (* km sx)) (sy (* km sy)) (sz (* km sz))
               (mx (* km mx)) (my (* km my)) (mz (* km mz))
               (ax (- mx sx)) (ay (- my sy)) (az (- mz sz))
               (length (sqrt (+ (* ax ax) (* ay ay) (* az az))))
               (ux (/ ax length)) (uy (/ ay length)) (uz (/ az length))
               (along (- (+ (* mx ux) (* my uy) (* mz uz))))
               (px (+ mx (* along ux))) (py (+ my (* along uy))) (pz (+ mz (* along uz)))
               (miss (sqrt (+ (* px px) (* py py) (* pz pz))))
               (back (if (< miss +earth-radius-km+)
                         (sqrt (- (expt +earth-radius-km+ 2) (* miss miss)))
                         0d0)))
          ;; Back along the axis, towards the Moon, to the surface.
          (body-longitude-latitude (find-planet "Earth") tc
                                   (- px (* back ux)) (- py (* back uy)) (- pz (* back uz))))))))
