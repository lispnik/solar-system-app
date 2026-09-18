;;;; dwarfs.lisp -- Pluto, Ceres, Eris, Haumea and Makemake.
;;;;
;;;; No mean elements fitted over centuries exist for these the way
;;;; Standish's do for the planets, and one osculating set drifts: Neptune
;;;; drags Pluto round, Jupiter Ceres. So the orbit is sampled instead --
;;;; Horizons' osculating elements every ten years, 1600 to 2500, in
;;;; dwarf-elements.lisp -- and a position is the two-body motion from the
;;;; samples either side, blended by how far between them it is. Inside the
;;;; span that follows Horizons to a small fraction of a degree; outside it
;;;; the nearest end is simply carried on, and slowly goes wrong.

(in-package #:solar-system.core)

(defun tc-to-jd (tc)
  (+ +j2000+ (* tc 36525d0)))

(defun nearest-sample (body tc)
  (let* ((samples (body-samples body))
         (jd (tc-to-jd tc)))
    (reduce (lambda (a b) (if (< (abs (- (aref a 0) jd)) (abs (- (aref b 0) jd))) a b))
            samples)))

(defun sample-elements (sample jd)
  "The values ELEMENTS answers, from one osculating SAMPLE carried by
two-body motion to JD."
  (let ((m (+ (aref sample 6) (* (aref sample 7) (- jd (aref sample 0))))))
    (values (aref sample 1) (aref sample 2)
            (* (aref sample 3) +degrees+)
            (* (aref sample 5) +degrees+)
            (* (aref sample 4) +degrees+)
            (* (normalize-degrees m) +degrees+))))

(defun sample-position (sample jd)
  (declare (type simple-vector sample) (type double-float jd) (optimize (speed 3) (safety 0)))
  (multiple-value-bind (a e incl argp node m) (sample-elements sample jd)
    (let ((ea (solve-kepler m e)))
      (to-ecliptic (* a (- (cos ea) e))
                   (* a (sqrt (- 1d0 (* e e))) (sin ea))
                   argp node incl))))

(defun sampled-position (body tc)
  "Between two samples, the positions from each, weighted by nearness;
outside the span, the position from the end sample."
  (let* ((samples (body-samples body))
         (jd (tc-to-jd tc))
         (after (position-if (lambda (sample) (> (aref sample 0) jd)) samples)))
    (if (or (null after) (zerop after))
        (sample-position (aref samples (if after 0 (1- (length samples)))) jd)
        (let* ((before (aref samples (1- after)))
               (next (aref samples after))
               (f (/ (- jd (aref before 0)) (- (aref next 0) (aref before 0)))))
          (multiple-value-bind (x0 y0 z0) (sample-position before jd)
            (multiple-value-bind (x1 y1 z1) (sample-position next jd)
              (values (+ x0 (* f (- x1 x0)))
                      (+ y0 (* f (- y1 y0)))
                      (+ z0 (* f (- z1 z0))))))))))

(defparameter *dwarfs*
  (flet ((dwarf (name radius colour)
           (make-body :name name :radius-km radius :colour colour
                      :samples (coerce (rest (assoc name *dwarf-elements* :test #'string=))
                                       'simple-vector))))
    (list (dwarf "Ceres" 469.7d0 #(0.62 0.61 0.58))
          (dwarf "Pluto" 1188.3d0 #(0.86 0.76 0.64))
          (dwarf "Haumea" 816d0 #(0.84 0.85 0.88))
          (dwarf "Makemake" 715d0 #(0.86 0.66 0.50))
          (dwarf "Eris" 1163d0 #(0.90 0.90 0.93))))
  "Pluto and the dwarf planets, by distance.")

(defun heliocentric-bodies ()
  "Everything that goes round the Sun: planets then dwarf planets."
  (append *planets* *dwarfs*))
