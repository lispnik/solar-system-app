;;;; sky.lisp -- the view from the Earth.
;;;;
;;;; The camera at the Earth's centre, looking out, and everything where it
;;;; truly is: no compression, positions in AU from the Earth. Only
;;;; directions reach the screen, so the sky is right; the depth buffer
;;;; sees true distances, so the Moon passes in front of the Sun; the Sun's
;;;; true position lights everything, so Venus has its phases. Each body is
;;;; drawn at its true angular size, or as a dot where that is too small --
;;;; which is to say, until the view is narrowed on it: Jupiter becomes a
;;;; disc at a fifth of a degree, with its moons strung out beside it.
;;;;
;;;; Across the sky, the ecliptic and the celestial equator. The trails
;;;; become each planet's path across the sky over the past year, which is
;;;; where Mars's retrograde loop shows.
;;;;
;;;; From the Earth's centre a solar eclipse can miss: the Moon is near
;;;; enough that where you stand moves it by a degree. So a solar eclipse
;;;; puts the observer where it is greatest -- on the surface, under the
;;;; axis of the Moon's shadow -- and keeps them there as the Earth turns.

(in-package #:solar-system)

(defvar *sky-button* nil)
(defvar *observer* nil "(east-longitude . latitude), degrees, on the Earth's surface; NIL for its centre.")
(defvar *outside-camera* nil "The camera from outside, kept while in the sky.")
(defparameter +sky-circle-radius+ 100d0 "AU: beyond everything, so behind everything.")
(defparameter +trail-sky-radius+ 90d0)

;;; ------------------------------------------------------------------
;;; placing

(defun place-observer (tc)
  "Put the camera where *OBSERVER* stands at TC: turned with the Earth."
  (let ((target (solar-system.core::camera-target *camera*)))
    (if (null *observer*)
        (fill target 0d0)
        (multiple-value-bind (ax ay az bx by bz cx cy cz) (body-axes (find-planet "Earth") tc)
          (destructuring-bind (lon . lat) *observer*
            (let* ((r (/ solar-system.core::+earth-radius-km+ +km-per-au+))
                   (lon (* lon (/ pi 180))) (lat (* lat (/ pi 180)))
                   (u (* r (cos lat) (cos lon))) (v (* r (cos lat) (sin lon))) (w (* r (sin lat))))
              (setf (aref target 0) (float (+ (* u ax) (* v bx) (* w cx)) 1d0)
                    (aref target 1) (float (+ (* u ay) (* v by) (* w cy)) 1d0)
                    (aref target 2) (float (+ (* u az) (* v bz) (* w cz)) 1d0))))))))

(defun describe-observer ()
  (when (and *sky-mode* *observer*)
    (destructuring-bind (lon . lat) *observer*
      (format nil "seen from ~,1f°~:[N~;S~] ~,1f°~:[E~;W~]"
              (abs lat) (minusp lat) (abs lon) (minusp lon)))))

(defun place-bodies-from-earth (tc aspect height pixels-per-point)
  "As PLACE-BODIES, from the Earth: (depth body x y z radius alpha), the
ringed planets as systems, and the Sun."
  (place-observer tc)
  (let ((placed '()) (systems '())
        (sun (multiple-value-list (geocentric +sun+ tc))))
    (labels ((depth (x y z) (nth-value 2 (view-position *camera* aspect x y z)))
             (true-radius (body depth)
               (* (/ (body-radius-km body) +km-per-au+) (pixels-per-unit height depth)))
             (dot (body)
               (* (if (member body (list +sun+ (find-body "Moon"))) 1d0 0.55d0)
                  (disc-radius body pixels-per-point)))
             (place (body x y z &optional (alpha 1d0))
               (let ((depth (depth x y z)))
                 (push (list depth body x y z (max (dot body) (true-radius body depth)) alpha)
                       placed)
                 depth)))
      (destructuring-bind (sx sy sz) sun
        (place +sun+ sx sy sz))
      (multiple-value-bind (mx my mz) (lunar-position tc)
        (place (find-body "Moon") mx my mz))
      (dolist (body (heliocentric-bodies))
        (unless (string= (body-name body) "Earth")
          (multiple-value-bind (x y z) (geocentric body tc)
            (let* ((depth (place body x y z))
                   (per-unit (pixels-per-unit height depth))
                   (planet-radius (max (dot body) (true-radius body depth))))
              ;; Its moons, at their true places, once they stand clear of it.
              (dolist (moon (moons-of body))
                (multiple-value-bind (dx dy dz) (moon-offset moon tc)
                  (let ((apart (* per-unit (sqrt (+ (* dx dx) (* dy dy) (* dz dz))))))
                    (place moon (+ x dx) (+ y dy) (+ z dz)
                           (smoothstep (+ planet-radius 2d0) (+ planet-radius 8d0) apart)))))
              ;; Rings, once they are a few pixels across.
              (let ((ring (find (body-name body) +rings+ :key #'first :test #'string=)))
                (when ring
                  (let ((outer (* per-unit (/ (fourth ring) +km-per-au+))))
                    (push (list body x y z (smoothstep 2d0 8d0 outer) outer) systems)))))))))
    (values placed systems sun)))

;;; ------------------------------------------------------------------
;;; looking

(defun sky-focus-on (body)
  "Look at BODY and follow it, narrowed so that it -- or, for a planet with
moons, its moons -- fill a good part of the view."
  (setf *focus* body)
  (when body
    (let* ((tc (centuries-since-j2000 (utc-to-tt (sim-jd))))
           (distance (multiple-value-call #'solar-system.core::distance
                       (if (string= (body-name body) "Moon")
                           (lunar-position tc)
                           (geocentric body tc))))
           (moons (and (not (eq body +sun+)) (moons-of body)))
           (reach (if moons
                      (* 1.3d0 (/ (reduce #'max moons :key #'solar-system.core::moon-a) +km-per-au+))
                      (* 4.2d0 (/ (body-radius-km body) +km-per-au+))))
           (field (* 2 (atan (/ reach distance)))))
      (setf (camera-zoom *camera*)
            (max 1d0 (min 2000d0 (/ *centre-field-of-view* field)))))))

(defun look-at-midnight ()
  "Face away from the Sun, along the ecliptic: the midnight sky, where the
outer planets come to opposition."
  (multiple-value-bind (x y z) (geocentric +sun+ (centuries-since-j2000 (utc-to-tt (sim-jd))))
    (look-along *camera* (- x) (- y) (- z))
    (setf (camera-zoom *camera*) 0.75d0)))

;;; ------------------------------------------------------------------
;;; the sky's circles and the trails

(defun store-sky-circles ()
  "The ecliptic and the celestial equator, into the first two spare lines."
  (let ((contents (objc:invoke *orbit-buffer* "contents"))
        (c (cos solar-system.core::+obliquity-j2000+))
        (s (sin solar-system.core::+obliquity-j2000+)))
    (loop for slot in (list (spare-slot 0) (spare-slot 1))
          for equator in '(nil t)
          do (dotimes (i (1+ +segments+))
               (let* ((angle (/ (* 2 pi i) +segments+))
                      (x (cos angle)) (y (sin angle)))
                 (multiple-value-bind (ex ey ez)
                     (if equator (values x (* y c) (- (* y s))) (values x y 0d0))
                   (store-floats contents (* 4 (+ (* slot (1+ +segments+)) i))
                                 (* +sky-circle-radius+ ex) (* +sky-circle-radius+ ey)
                                 (* +sky-circle-radius+ ez) 1)))))))

(defun sky-trail-position (body jd)
  "Where BODY is on the sky at JD, as a point far out along its direction."
  (multiple-value-bind (x y z) (geocentric body (centuries-since-j2000 jd))
    (let ((r (sqrt (+ (* x x) (* y y) (* z z)))))
      (values (* +trail-sky-radius+ (/ x r)) (* +trail-sky-radius+ (/ y r))
              (* +trail-sky-radius+ (/ z r))))))

(defun use-sky-trails (on)
  (if on
      (setf *trail-position* #'sky-trail-position
            *trail-length* (lambda (body) (declare (ignore body)) 365.25d0)
            *trail-scene* (lambda (x y z k) (declare (ignore k)) (values x y z)))
      (setf *trail-position* #'heliocentric-trail-position
            *trail-length* #'trail-days
            *trail-scene* (lambda (x y z k) (compress x y z k))))
  (setf *trails* '()))

;;; ------------------------------------------------------------------
;;; in and out

(defun enter-sky (&key keep-camera)
  "To the Earth's centre. KEEP-CAMERA: the camera already says where to look
-- restored from a saved state."
  (setf *sky-mode* t)
  (unless keep-camera
    (setf *outside-camera* (copy-structure *camera*)
          (solar-system.core::camera-rotation *outside-camera*)
          (copy-seq (solar-system.core::camera-rotation *camera*))
          (solar-system.core::camera-target *outside-camera*)
          (copy-seq (solar-system.core::camera-target *camera*))))
  (setf (camera-mode *camera*) :centre)
  (fill (solar-system.core::camera-target *camera*) 0d0)
  (use-sky-trails t)
  (when *orbit-buffer* (store-sky-circles))
  (unless keep-camera
    (let ((followed *focus*))
      (if (and followed (not (string= (body-name followed) "Earth")))
          (sky-focus-on followed)
          (progn (setf *focus* nil) (look-at-midnight)))))
  (show-sky-button))

(defun leave-sky ()
  (setf *sky-mode* nil *observer* nil)
  (if *outside-camera*
      (setf *camera* *outside-camera* *outside-camera* nil)
      (progn (setf (camera-mode *camera*) :orbit) (reset-camera *camera*)))
  (setf (camera-mode *camera*) :orbit)
  (use-sky-trails nil)
  (let ((followed *focus*))
    (setf *focus* nil)
    (when followed (focus-on followed)))
  (show-sky-button))

(defun toggle-sky ()
  (if *sky-mode* (leave-sky) (enter-sky)))

(defun show-sky-button ()
  (when *sky-button*
    (set-button-image *sky-button* (if *sky-mode* "globe.americas.fill" "globe.americas"))))

(defun reset-sky-view ()
  (setf *focus* nil *observer* nil)
  (look-at-midnight))
