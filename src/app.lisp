;;;; app.lisp -- the screen: a Metal view edge to edge, a clock over it, and
;;;; the playback panel along the bottom.

(in-package #:solar-system)

(defun ns-date-jd ()
  "The wall clock as a JD (UTC), from NSDate: sub-millisecond, where
GET-UNIVERSAL-TIME is whole seconds."
  (jd-from-2001-seconds (objc:invoke "NSDate" "timeIntervalSinceReferenceDate")))

(defun describe-rate (scale)
  "\"real time\", \"1 day/s\", \"-3.2 yr/s\"..."
  (if (= scale 1d0)
      "real time"
      (let ((magnitude (abs scale)))
        (multiple-value-bind (value unit)
            (cond ((< magnitude 60) (values magnitude "x"))
                  ((< magnitude 3600) (values (/ magnitude 60) "min/s"))
                  ((< magnitude 86400) (values (/ magnitude 3600) "h/s"))
                  ((< magnitude 31557600) (values (/ magnitude 86400) "days/s"))
                  (t (values (/ magnitude 31557600) "yr/s")))
          (format nil "~:[~;-~]~,1f ~a" (minusp scale) value unit)))))

(defun update-clock ()
  (objc:invoke *clock-label* "setText:"
               (format nil "~a~%~a~@[~%following ~a~]~@[~%drawing stopped: ~a~]"
                       (format-jd (sim-jd)) (describe-state)
                       (and *focus* (body-name *focus*)) *failure*)))

(defun launch-time-scale ()
  "-SolarTimeScale N on the launch command line, which NSUserDefaults reads
into its argument domain -- so a simulator launch can start the clock fast:
  xcrun simctl launch booted org.asdf-ios-app.solar-system -SolarTimeScale 86400"
  (let ((scale (objc:invoke (objc:invoke "NSUserDefaults" "standardUserDefaults")
                            "doubleForKey:" "SolarTimeScale")))
    (and (numberp scale) (/= scale 0) scale)))

(defun start ()
  (objc:ensure-objc-initialized)
  (setf *wall-clock* #'ns-date-jd)
  (real-time)
  (let ((scale (launch-time-scale)))
    (when scale
      (setf *speed-index* nil *custom-rate* scale)
      (apply-rate)))
  (let* ((root (ui:root-view))
         (safe (objc:invoke (ui:root-controller) "safeAreaLayoutGuide"))
         (view (make-metal-view)))
    (objc:invoke root "setBackgroundColor:" (ui:color 0 0 0))
    (objc:invoke root "addSubview:" view)
    (dolist (edge '("topAnchor" "bottomAnchor" "leadingAnchor" "trailingAnchor"))
      (ui:pin view edge root edge))
    (add-gestures view)
    (let ((panel (make-panel)))
      (objc:invoke root "addSubview:" panel)
      (ui:pin panel "leadingAnchor" safe "leadingAnchor" 12)
      (ui:pin panel "trailingAnchor" safe "trailingAnchor" -12)
      (ui:pin panel "bottomAnchor" safe "bottomAnchor" -8))
    (setf *clock-label* (ui:new "UILabel"))
    (objc:invoke *clock-label* "setFont:" (ui:mono-font 12))
    (objc:invoke *clock-label* "setTextColor:" (ui:color 0.75 0.78 0.85))
    (objc:invoke *clock-label* "setNumberOfLines:" 0)
    (objc:invoke root "addSubview:" *clock-label*)
    (ui:pin *clock-label* "topAnchor" safe "topAnchor" 8)
    (ui:pin *clock-label* "leadingAnchor" safe "leadingAnchor" 16)
    (update-clock)
    (ui:after-every 0.25d0 (lambda (timer) (declare (ignore timer)) (update-clock)))
    (format t "SOLAR: started at ~a, ~a~%" (format-jd (sim-jd)) (describe-rate *time-scale*))
    (finish-output)
    (values)))
