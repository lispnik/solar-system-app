;;;; orbits.lisp -- the lines: the orbits, the moons' orbits, the comets' orbits and tails.
;;;;
;;;; Each is +SEGMENTS+ points in its slot of the one line buffer, and a
;;;; colour, a centre and a style in *ORBIT-INFO*.

(in-package #:solar-system)

(defun ensure-orbits (tc k)
  "Rewrite the heliocentric orbits if the compression or the elements --
which drift, slowly -- have changed since they were drawn. A year of
simulated time moves them by less than a pixel. The camera does not enter
into it."
  (let ((key *orbit-key*))
    (unless (and key
                 (= *radius-exponent* (first key))
                 (< (abs (- tc (second key))) 0.01d0))
      (let ((contents (objc:invoke *orbit-buffer* "contents")))
        (loop for body in (heliocentric-bodies)
              for slot from 0
              do (store-orbit contents slot (orbit-points body tc +segments+) (x y z)
                   (compress x y z k)))
        (loop for comet in *comets*
              for index from 0
              do (store-orbit contents (comet-orbit-slot index) (comet-orbit-points comet +segments+) (x y z)
                   (compress x y z k))))
      (setf *orbit-key* (list *radius-exponent* tc)
            *scales* (moon-system-scales tc k)))))

(defun ensure-moon-orbits (tc)
  "Rewrite the moons' orbits, relative to their planets, when a day of
simulated time has passed -- the Moon's node turns a fifth of a degree in
three -- but not more often than every thirty frames, which at a year a
second is twice a second."
  (let ((key *moon-orbit-key*))
    (unless (and key
                 (eq *scales* (first key))
                 (or (< (abs (- tc (second key))) (/ 1d0 36525))
                     (< (- *frame-count* (third key)) 30)))
      (let ((contents (objc:invoke *orbit-buffer* "contents"))
            (first-slot (length (heliocentric-bodies))))
        (loop for moon in *moons*
              for slot from first-slot
              do (destructuring-bind (radius . outermost) (rest (assoc (body-parent moon) *scales*))
                   (store-orbit contents slot (moon-orbit-points moon tc +segments+) (x y z)
                     (moon-display-offset x y z radius outermost)))))
      (setf *moon-orbit-key* (list *scales* tc *frame-count*)))))

(defun fill-orbit-info (systems sun)
  "Each orbit's colour, opacity and centre: the Sun's family round the Sun,
the planets brighter than the dwarfs; each moon round its planet, as bright
as its system is visible. From the Earth, no orbits, but the ecliptic and
the equator across the sky."
  (when *sky-mode*
    (dotimes (slot (length (orbiters))) (store-line slot 0 0 0 0 0 0 0))
    (store-line (spare-slot 0) 0.85 0.75 0.45 0.35 0 0 0)
    (store-line (spare-slot 1) 0.45 0.60 0.95 0.25 0 0 0)
    (return-from fill-orbit-info))
  (store-line (spare-slot 0) 0 0 0 0 0 0 0)
  (store-line (spare-slot 1) 0 0 0 0 0 0 0)
  (destructuring-bind (sx sy sz) sun
    (loop for body in (heliocentric-bodies)
          for slot from 0
          for colour = (body-colour body)
          do (store-line slot (aref colour 0) (aref colour 1) (aref colour 2)
                         (if (member body *planets*) 0.45 0.3)
                         sx sy sz)))
  (loop for moon in *moons*
        for slot from (length (heliocentric-bodies))
        for colour = (body-colour (body-parent moon))
        do (destructuring-bind (px py pz alpha &rest rest) (rest (assoc (body-parent moon) systems))
             (declare (ignore rest))
             (store-line slot (aref colour 0) (aref colour 1) (aref colour 2) (* 0.35d0 alpha)
                         px py pz))))

(defun update-comet-lines (tc k sun)
  "Each comet's orbit, round the Sun, from outside; and its tail, away from
the Sun, from anywhere -- a line from the tip, clear, to the head."
  (let ((contents (objc:invoke *orbit-buffer* "contents")))
    (loop for comet in *comets*
          for index from 0
          for orbit = (comet-orbit-slot index)
          for tail = (comet-tail-slot index)
          do (destructuring-bind (sx sy sz) sun
               (if (and *small-bodies-on* (not *sky-mode*))
                   (store-line orbit 0.55 0.75 0.90 0.14 sx sy sz)
                   (store-line orbit 0 0 0 0 0 0 0))
               (multiple-value-bind (length brightness) (comet-tail comet tc)
                 (if (or (not *small-bodies-on*) (<= brightness 0.02d0))
                     (store-line tail 0 0 0 0 0 0 0)
                     (multiple-value-bind (x y z) (heliocentric-position comet tc)
                       (multiple-value-bind (ex ey ez) (if *sky-mode* (earth-position tc) (values 0d0 0d0 0d0))
                         (let* ((r (sqrt (+ (* x x) (* y y) (* z z))))
                                (ux (/ x r)) (uy (/ y r)) (uz (/ z r))
                                (base (* tail 4 (1+ +segments+))))
                           (dotimes (i (1+ +segments+))
                             (let* ((along (* length (- 1 (/ i +segments+))))
                                    (px (+ x (* along ux))) (py (+ y (* along uy))) (pz (+ z (* along uz))))
                               (multiple-value-bind (qx qy qz)
                                   (if *sky-mode*
                                       (values (- px ex) (- py ey) (- pz ez))
                                       (compress px py pz k))
                                 (store-floats contents (+ base (* 4 i)) qx qy qz 1))))
                           (if *sky-mode*
                               (store-line tail 0.78 0.90 1.0 (* 0.9d0 brightness) 0 0 0 1 2.5)
                               (store-line tail 0.78 0.90 1.0 (* 0.9d0 brightness) sx sy sz 1 2.5)))))))))))
