;;;; pointer.lisp -- hold the phone up to the sky.
;;;;
;;;; In the view from the Earth, the location button stands you where the
;;;; phone is and turns the view with it: Core Location says where on the
;;;; Earth that is, Core Motion which way the phone faces -- its attitude
;;;; in a frame of true north, west and up, as a quaternion -- and
;;;; observer.lisp makes the camera that looks out of the back of the phone.
;;;; A horizon is drawn, and the points of the compass along it.
;;;;
;;;; Where there are no motion sensors -- the simulator -- the location is
;;;; still used, and the view still turns by hand.

(in-package #:solar-system)

(defvar *location-manager* nil)
(defvar *location-listener* nil)
(defvar *motion-manager* nil)
(defvar *fake-attitude* nil
  "(qx qy qz qw), north-west-up, to use instead of Core Motion's attitude:
for the simulator, which has no motion sensors. POSE-ATTITUDE makes one:
  (setf *fake-attitude* (multiple-value-list (pose-attitude 180 50 3)))")
(defvar *here* nil "(east-longitude . latitude), degrees, from Core Location.")
(defvar *pointer-status* nil "A line for the clock while the phone is being asked.")
(defvar *compass-labels* '() "(azimuth . label) along the horizon.")
(defparameter +horizon-slot+ 20 "The spare line the horizon is drawn in.")

(objc:define-objc-class location-listener () ()
  (:objc-class-name "SolarLocationListener")
  (:objc-protocols "CLLocationManagerDelegate"))

(objc:define-objc-method ("locationManager:didUpdateLocations:" :void)
    ((self location-listener) (manager objc:objc-object-pointer) (locations objc:objc-object-pointer))
  (declare (ignore manager))
  (let ((coordinate (objc:invoke (objc:invoke locations "lastObject") "coordinate")))
    ;; CLLocationCoordinate2D, by value, as a vector: latitude, longitude.
    (setf *here* (cons (float (aref coordinate 1) 1d0) (float (aref coordinate 0) 1d0)))
    (when *pointing*
      (setf *observer* *here*)
      (when (motion-available-p) (setf *pointer-status* nil)))))

(objc:define-objc-method ("locationManager:didFailWithError:" :void)
    ((self location-listener) (manager objc:objc-object-pointer) (error objc:objc-object-pointer))
  (declare (ignore manager))
  (setf *pointer-status*
        (format nil "no location: ~a" (objc:ns-string-to-string (objc:invoke error "localizedDescription")))))

(defun motion-available-p ()
  (and *motion-manager* (objc:invoke-bool *motion-manager* "isDeviceMotionAvailable")))

(defun start-pointing ()
  (unless *sky-mode* (enter-sky))
  (setf *pointing* t *focus* nil
        *pointer-status* "asking where you are…")
  (unless *location-manager*
    (setf *location-listener* (ui:keep (make-instance 'location-listener))
          *location-manager* (ui:keep (objc:alloc-init-object "CLLocationManager")))
    (objc:invoke *location-manager* "setDelegate:" (objc:objc-object-pointer *location-listener*)))
  (objc:invoke *location-manager* "requestWhenInUseAuthorization")
  (objc:invoke *location-manager* "startUpdatingLocation")
  (when *here* (setf *observer* *here*))
  (unless *motion-manager*
    (setf *motion-manager* (ui:keep (objc:alloc-init-object "CMMotionManager"))))
  (if (motion-available-p)
      (let ((frames (objc:invoke "CMMotionManager" "availableAttitudeReferenceFrames")))
        (objc:invoke *motion-manager* "setDeviceMotionUpdateInterval:" (/ 1d0 60))
        ;; X to true north and Z up, if the compass and location allow it;
        ;; magnetic north, a few degrees out, if not.
        (objc:invoke *motion-manager* "startDeviceMotionUpdatesUsingReferenceFrame:"
                     (if (logtest frames 8) 8 4)))
      (unless *fake-attitude*
        (setf *pointer-status* "no motion sensors here: drag to look")))
  (when (and *here* (or *fake-attitude* (motion-available-p))) (setf *pointer-status* nil))
  (show-pointer-button))

(defun stop-pointing ()
  (setf *pointing* nil *observer* nil *pointer-status* nil)
  (when *location-manager* (objc:invoke *location-manager* "stopUpdatingLocation"))
  (when (motion-available-p) (objc:invoke *motion-manager* "stopDeviceMotionUpdates"))
  (store-line (spare-slot +horizon-slot+) 0 0 0 0 0 0 0)
  (show-pointer-button))

(defun toggle-pointing ()
  (if *pointing* (stop-pointing) (start-pointing)))

(defun show-pointer-button ()
  (when *pointer-button*
    (set-button-image *pointer-button*
                      (if *pointing* "location.north.circle.fill" "location.north.circle"))))

(defun interface-orientation ()
  "The window scene's UIInterfaceOrientation: 1 portrait, 2 upside down,
3 landscape right, 4 landscape left."
  (objc:invoke (objc:invoke (ui:key-window) "windowScene") "interfaceOrientation"))

(defun screen-turn ()
  "Radians the interface is turned from portrait."
  (interface-turn (interface-orientation)))

(defvar *pointing-sideways* nil
  "Whether the phone was last seen held sideways, pointed at the sky.")

(defun update-panel-for-pointing ()
  "Held sideways, the panel covers the middle of the screen -- where what
the phone is pointed at is drawn. Hide it on the way into pointing
sideways and show it on the way out; in between, a tap still shows it."
  (let ((sideways (and *pointing* (member (interface-orientation) '(3 4)) t)))
    (unless (eq sideways *pointing-sideways*)
      (setf *pointing-sideways* sideways)
      (objc:invoke *panel* "setHidden:" sideways)
      (objc:invoke *clock-label* "setHidden:" nil))))

(defun attitude ()
  "The phone's attitude as a list (qx qy qz qw), or NIL if it cannot say:
the fake one when there is one, else Core Motion's."
  (cond (*fake-attitude*)
        ((motion-available-p)
         (let ((motion (objc:invoke *motion-manager* "deviceMotion")))
           (unless (nothing-p motion)
             (let ((q (objc:invoke (objc:invoke motion "attitude") "quaternion")))
               (loop for i below 4 collect (float (aref q i) 1d0))))))))

(defun point-camera (tc)
  "Turn the camera the way the phone faces, once a frame, if it can say."
  (when (and *pointing* *observer*)
    (let ((q (attitude)))
      (when q
        (replace (solar-system.core::camera-rotation *camera*)
                 (device-camera-rotation (first q) (second q) (third q) (fourth q)
                                         (car *observer*) (cdr *observer*) tc
                                         (screen-turn)))))))

(defun update-horizon (tc)
  "The horizon, a circle round the observer at the sky's distance, and the
compass points along it -- while pointing."
  (let ((slot (spare-slot +horizon-slot+)))
    (if (not (and *pointing* *observer*))
        (store-line slot 0 0 0 0 0 0 0)
        (let ((contents (objc:invoke *orbit-buffer* "contents"))
              (target (solar-system.core::camera-target *camera*)))
          (multiple-value-bind (nx ny nz wx wy wz) (horizon-axes (car *observer*) (cdr *observer*) tc)
            (dotimes (i (1+ +segments+))
              (let* ((az (/ (* 2 pi i) +segments+))
                     (n (* +sky-circle-radius+ (cos az))) (w (- (* +sky-circle-radius+ (sin az)))))
                (store-floats contents (* 4 (+ (* slot (1+ +segments+)) i))
                              (+ (* n nx) (* w wx)) (+ (* n ny) (* w wy)) (+ (* n nz) (* w wz)) 1))))
          (store-line slot 0.45 0.85 0.55 0.6 (aref target 0) (aref target 1) (aref target 2) 0 1.3)))))

(defun make-compass-labels ()
  (setf *compass-labels*
        (loop for (azimuth name) in '((0 "N") (45 "NE") (90 "E") (135 "SE")
                                      (180 "S") (225 "SW") (270 "W") (315 "NW"))
              collect (let ((label (objc:alloc-init-object "UILabel")))
                        (objc:invoke label "setText:" name)
                        (objc:invoke label "setFont:" (ui:bold-font (if (= 1 (length name)) 14 11)))
                        (objc:invoke label "setTextColor:" (ui:color 0.55 0.95 0.65 0.9))
                        (objc:invoke label "sizeToFit")
                        (objc:invoke label "setHidden:" t)
                        (objc:invoke *label-container* "addSubview:" label)
                        (cons azimuth label)))))

(defun update-compass-labels ()
  "Each compass point where the horizon crosses it on the screen."
  (when *compass-labels*
    (if (not (and *pointing* *observer*))
        (dolist (entry *compass-labels*) (objc:invoke (cdr entry) "setHidden:" t))
        (let ((tc (centuries-since-j2000 (utc-to-tt (sim-jd))))
              (target (solar-system.core::camera-target *camera*)))
          (multiple-value-bind (width height scale aspect projection) (screen-metrics *view*)
            (multiple-value-bind (nx ny nz wx wy wz) (horizon-axes (car *observer*) (cdr *observer*) tc)
              (loop for (azimuth . label) in *compass-labels*
                    for a = (* azimuth (/ pi 180))
                    for n = (* +sky-circle-radius+ (cos a))
                    for w = (- (* +sky-circle-radius+ (sin a)))
                    do (multiple-value-bind (sx sy)
                           (to-points (+ (aref target 0) (* n nx) (* w wx))
                                      (+ (aref target 1) (* n ny) (* w wy))
                                      (+ (aref target 2) (* n nz) (* w wz))
                                      width height scale aspect projection)
                         (let ((shown (and sx (< 0 sx (/ width scale)) (< 0 sy (/ height scale)))))
                           (objc:invoke label "setHidden:" (not shown))
                           (when shown
                             (objc:invoke label "setCenter:" (vector sx (- sy 10d0)))))))))))))
