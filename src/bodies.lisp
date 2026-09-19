;;;; bodies.lisp -- where each body is drawn, how large, and its rings.

(in-package #:solar-system)

(defun pixels-per-unit (height depth)
  "Pixels per scene unit at view DEPTH (negative, in front of the camera),
in a drawable HEIGHT pixels tall."
  (/ (* 0.5d0 height) (tan (/ (camera-field-of-view *camera*) 2)) (max 1d-12 (- depth))))

(defun place-bodies (tc k aspect height pixels-per-point)
  "Every body's scene position, depth, disc radius and opacity, as a list
of (depth body x y z radius alpha), and the moon systems -- (body x y z
alpha on-screen-radius) -- as an alist. Moons fade in as their system
grows on the screen beyond four times their planet's disc, and are gone
below two and a half. Within a system that is showing, the planet and its
moons are drawn to the system's own scale -- the square root of their
radius over the outermost moon's distance, as the moons' distances are --
so that the planet grows as the camera comes close, its moons stay
outside it, and Saturn's rings inside Mimas."
  (let* ((zoom-enlarge (sqrt (camera-zoom *camera*)))
         (sun (multiple-value-list
               (if (eq *frame* :barycentric)
                   (multiple-value-bind (x y z) (sun-barycentric-offset tc) (compress x y z k))
                   (values 0d0 0d0 0d0))))
         (placed '())
         (systems '()))
    (labels ((base (body)
               ;; Followed and without moons to set a scale: let it grow.
               (* (max 1d0 (min (if (and (eq body *focus*) (null (assoc body *scales*))) 12d0 3d0)
                                zoom-enlarge))
                  (disc-radius body pixels-per-point)))
             (place (body x y z radius &optional (alpha 1d0))
               (let ((depth (nth-value 2 (view-position *camera* aspect x y z))))
                 (push (list depth body x y z radius alpha) placed)
                 depth)))
      (destructuring-bind (sx sy sz) sun
        (place +sun+ sx sy sz (base +sun+))
        (dolist (body (heliocentric-bodies))
          (multiple-value-bind (x y z) (multiple-value-call #'compress
                                         (heliocentric-position body tc) k)
            (let* ((px (+ x sx)) (py (+ y sy)) (pz (+ z sz))
                   (depth (nth-value 2 (view-position *camera* aspect px py pz)))
                   (scale (rest (assoc body *scales*))))
              (if (null scale)
                  (place body px py pz (base body))
                  (destructuring-bind (radius . outermost) scale
                    (let* ((on-screen (* radius (pixels-per-unit height depth)))
                           (outermost-km (* outermost +km-per-au+))
                           (disc (base body))
                           (alpha (smoothstep (* 2.5d0 disc) (* 4d0 disc) on-screen)))
                      ;; As the system shows, from the ordinary disc to
                      ;; the system's own scale -- not the larger of the
                      ;; two, or a followed planet's enlarged disc would
                      ;; swallow its rings and inner moons.
                      (flet ((to-scale (km) (* on-screen (sqrt (/ km outermost-km))))
                             (blend (ordinary scaled) (+ ordinary (* alpha (- scaled ordinary)))))
                        (place body px py pz (blend disc (to-scale (body-radius-km body))))
                        (push (list body px py pz alpha on-screen) systems)
                        (dolist (moon (moons-of body))
                          (multiple-value-bind (dx dy dz)
                              (multiple-value-call #'moon-display-offset
                                (moon-offset moon tc) radius outermost)
                            (place moon (+ px dx) (+ py dy) (+ pz dz)
                                   (max (* 1.3d0 pixels-per-point)
                                        (blend (base moon) (to-scale (body-radius-km moon))))
                                   alpha))))))))))
        (when *small-bodies-on*
          (dolist (comet *comets*)
            (multiple-value-bind (x y z) (multiple-value-call #'compress
                                           (heliocentric-position comet tc) k)
              (place comet (+ x sx) (+ y sy) (+ z sz) (base comet))))))
      (values placed systems sun))))

(defun view-axes (body tc)
  "Nine values: BODY's axes turned into view space, or NIL."
  (multiple-value-bind (ax ay az bx by bz cx cy cz) (body-axes body tc)
    (when ax
      (let ((r (solar-system.core::camera-rotation *camera*)))
        (flet ((turn (x y z)
                 (values (+ (* (aref r 0) x) (* (aref r 1) y) (* (aref r 2) z))
                         (+ (* (aref r 3) x) (* (aref r 4) y) (* (aref r 5) z))
                         (+ (* (aref r 6) x) (* (aref r 7) y) (* (aref r 8) z)))))
          (multiple-value-call #'values (turn ax ay az) (turn bx by bz) (turn cx cy cz)))))))

(defun fill-discs (placed tc ringed)
  "The bodies into this frame's disc buffer, farthest from the camera
first, so that nearer ones blend over them at their edges. RINGED: the
planets whose rings are drawn; Saturn's shadow it."
  (setf *disc-buffer* (svref *disc-buffers* (mod *frame-count* 3))
        *discs* (objc:invoke *disc-buffer* "contents"))
  (loop for (nil body x y z radius alpha) in (subseq (sort (copy-list placed) #'< :key #'first)
                                                     0 (min +max-discs+ (length placed)))
        for slot from 0
        for base = (* +disc-floats+ slot)
        for colour = (body-colour body)
        for index = (if (> alpha 0d0) (texture-index body) -1)
        do (store-floats *discs* base
                         x y z radius
                         (aref colour 0) (aref colour 1) (aref colour 2) alpha
                         (if (eq body +sun+) 1 0) index
                         (if (and (member body ringed) (string= (body-name body) "Saturn")) 1 0)
                         (if (and *sky-mode* (string= (body-name body) "Moon")) 1 0))
           (multiple-value-bind (ax ay az bx by bz cx cy cz)
               (if (>= index 0) (view-axes body tc) (values 1d0 0d0 0d0 0d0 1d0 0d0 0d0 0d0 1d0))
             (store-floats *discs* (+ base 12) ax ay az 0 bx by bz 0 cx cy cz 0)))
  (min +max-discs+ (length placed)))

(defun fill-rings (systems tc)
  "Each ringed planet's rings into its block of *RING-DATA*: at its moon
system's scale, seen from outside; at true scale from the Earth. Their
opacity is the system's. The planets whose rings are to be drawn."
  (loop for (name style inner outer) in +rings+
        for planet = (find-planet name)
        for block = (rest (assoc planet *ring-data*))
        for system = (rest (assoc planet systems))
        for scale = (rest (assoc planet *scales*))
        when (and block system (or scale *sky-mode*) (> (fourth system) 0.01d0)
                  (or (= style 1) *ring-map*))
          collect (destructuring-bind (px py pz alpha on-screen) system
                    (declare (ignore on-screen))
                    (multiple-value-bind (to-scale map-x map-y linear)
                        (if *sky-mode*
                            (values (lambda (km) (/ km +km-per-au+)) 1d0 +km-per-au+ 1)
                            (destructuring-bind (radius . outermost) scale
                              (let ((outermost-km (* outermost +km-per-au+)))
                                (values (lambda (km) (* radius (sqrt (/ km outermost-km))))
                                        radius outermost-km 0))))
                      (multiple-value-bind (ax ay az bx by bz) (body-axes planet tc)
                        (store-floats block 0
                                      px py pz 1  ax ay az 0  bx by bz 0
                                      (funcall to-scale inner) (funcall to-scale outer)
                                      (funcall to-scale (body-radius-km planet)) alpha
                                      map-x map-y inner outer
                                      style linear 0 0)
                        planet)))))
