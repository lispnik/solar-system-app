;;;; fake-phone.lisp -- holding the phone up to the sky, in the simulator.
;;;;
;;;; The simulator has no motion sensors, so pointing at the sky there
;;;; cannot be tried by hand. It does have Core Location and interface
;;;; rotation, and *FAKE-ATTITUDE* stands in for Core Motion. So: build with
;;;; SOLAR_REPL=1, give the simulator a place and the app permission,
;;;;
;;;;     xcrun simctl privacy <device> grant location com.burnsidemk.solarsystem
;;;;     xcrun simctl location <device> set 41.8781,-87.6298
;;;;
;;;; send this file over slynk, press the location button (or call
;;;; START-POINTING), and then, for instance,
;;;;
;;;;     (orient 3)                  ; landscape right: home button on the right
;;;;     (hold-towards "Sun" 3)      ; the phone's back to the Sun, held that way
;;;;
;;;; and take a screenshot. What is drawn is the real path: the location from
;;;; Core Location, the turn from the window scene, the attitude through
;;;; DEVICE-CAMERA-ROTATION -- only the quaternion is made up.
;;;;
;;;; Load into the SOLAR-SYSTEM package.

(defun orient (orientation)
  "Turn the interface: 1 portrait, 3 landscape right, 4 landscape left."
  (ios-app-runtime:on-main
   (lambda ()
     (let* ((scene (objc:invoke (ui:key-window) "windowScene"))
            (mask (ash 1 orientation))
            (prefs (objc:invoke (objc:invoke "UIWindowSceneGeometryPreferencesIOS" "alloc")
                                "initWithInterfaceOrientations:" mask)))
       (objc:invoke (objc:invoke (ui:key-window) "rootViewController")
                    "setNeedsUpdateOfSupportedInterfaceOrientations")
       (objc:invoke scene "requestGeometryUpdateWithPreferences:errorHandler:" prefs nil))))
  :turned)

(defun hold-towards (name &optional (orientation 1))
  "Point the fake phone at the body NAME, held ORIENTATION."
  (ios-app-runtime:on-main
   (lambda ()
     (let* ((tc (centuries-since-j2000 (utc-to-tt (sim-jd))))
            (lon (car *observer*)) (lat (cdr *observer*)))
       (multiple-value-bind (x y z) (centre-of (find-body name) tc)
         (multiple-value-bind (ex ey ez) (earth-position tc)
           (multiple-value-bind (ox oy oz) (observer-position lon lat tc)
             (multiple-value-bind (alt az)
                 (altitude-azimuth lon lat tc (- x ex ox) (- y ey oy) (- z ez oz))
               (setf *fake-attitude* (multiple-value-list (pose-attitude az alt orientation)))
               (format t "~&SOLAR: ~a at ~,1f up, ~,1f az~%" name alt az)))))))) 
  :held)
