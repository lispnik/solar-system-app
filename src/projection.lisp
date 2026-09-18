;;;; projection.lisp -- from AU to the scene the camera looks at.
;;;;
;;;; Neptune is 78 times as far out as Mercury, so at a true scale the inner
;;;; system is a smudge in the middle. The direction of every body from the
;;;; Sun is kept exactly; only its distance is compressed, through a power
;;;; law, so that every orbit fits and stays in order, and scaled so that
;;;; the outermost aphelion -- Eris's -- is at 1. *RADIUS-EXPONENT* 1 is the
;;;; true scale. The camera (camera.lisp) then looks at that scene from
;;;; anywhere.
;;;;
;;;; Moons are a scale of their own. Callisto is 0.013 AU from Jupiter, and
;;;; compressed with everything else it would be inside Jupiter's disc. So
;;;; each planet's moons are magnified about it: the outermost to a fraction
;;;; of the way to the neighbouring orbits, the rest by the square root of
;;;; their distance, their directions kept. They are there to be zoomed in
;;;; on; from afar they sit inside the planet's disc, and the renderer fades
;;;; them out.

(in-package #:solar-system.core)

(defparameter *radius-exponent* 0.4d0
  "Scene distance goes as (AU distance)^this. 1 is linear.")

(defvar *compression-cache* nil "(exponent tc k): the last COMPRESSION.")

(defun compression (tc)
  "The factor K in r' = K r^*RADIUS-EXPONENT* that puts the outermost
aphelion at TC at distance 1. Kept from call to call while TC moves less
than a year, since the aphelia hardly do."
  (let ((cache *compression-cache*))
    (if (and cache (= (first cache) *radius-exponent*) (< (abs (- tc (second cache))) 0.01d0))
        (third cache)
        (let* ((outer (reduce #'max (heliocentric-bodies) :key (lambda (body) (aphelion body tc))))
               (k (/ 1d0 (expt outer *radius-exponent*))))
          (setf *compression-cache* (list *radius-exponent* tc k))
          k))))

(declaim (inline compress))
(defun compress (x y z k)
  "Values x, y, z: the point in AU, in the scene. The direction is exact;
the distance is compressed."
  (declare (type double-float x y z k) (optimize (speed 3) (safety 0)))
  (let ((r (sqrt (+ (* x x) (* y y) (* z z)))))
    (if (zerop r)
        (values 0d0 0d0 0d0)
        (let ((f (/ (* k (expt r *radius-exponent*)) r)))
          (values (* f x) (* f y) (* f z))))))

(defparameter *moon-reach* 0.35d0
  "How far towards the nearest neighbouring orbit a planet's outermost moon
is drawn, as a fraction of the gap.")

(defun moon-system-scales (tc k)
  "For each body with moons, (body scene-radius . outermost-au): how far out
in the scene its outermost moon is drawn, and how far out it really is."
  (let* ((bodies (sort (copy-list (heliocentric-bodies)) #'<
                       :key (lambda (body) (values (elements body tc)))))
         (radii (mapcar (lambda (body) (* k (expt (values (elements body tc)) *radius-exponent*)))
                        bodies)))
    (loop for body in bodies
          for (previous here next) on (cons nil radii)
          for moons = (moons-of body)
          when moons
            collect (list* body
                           (* *moon-reach*
                              (min (if previous (- here previous) here)
                                   (if next (- next here) here)))
                           (/ (reduce #'max moons :key #'moon-a)
                              +km-per-au+)))))

(defun moon-display-offset (dx dy dz scene-radius outermost)
  "Values x, y, z: a moon's offset from its planet (AU) as drawn, the
direction kept, the distance DISTANCE mapped to SCENE-RADIUS times the square
root of its fraction of OUTERMOST."
  (let ((r (sqrt (+ (* dx dx) (* dy dy) (* dz dz)))))
    (if (zerop r)
        (values 0d0 0d0 0d0)
        (let ((f (/ (* scene-radius (sqrt (/ r outermost))) r)))
          (values (* f dx) (* f dy) (* f dz))))))

(defun disc-radius (body pixels-per-point)
  "BODY's disc radius in pixels. Not to scale -- nothing could be, beside
these distances -- but ordered: the logarithm of the true radius, clamped so
Mercury is still visible and Jupiter does not swallow Mars's orbit."
  (let ((points (cond ((eq body +sun+) 11d0)
                      ((body-parent body)
                       (max 1.3d0 (min 3d0 (* 1.4d0 (log (1+ (/ (body-radius-km body) 1000d0)))))))
                      (t (max 2.5d0 (min 8d0 (* 1.6d0 (log (1+ (/ (body-radius-km body) 1000d0))))))))))
    (* points pixels-per-point)))
