;;;; controls.lisp -- hands on the camera, and on time.
;;;;
;;;; Gestures on the Metal view move the camera:
;;;;   one-finger drag   turn the scene about the screen's x and y axes
;;;;   two-finger twist  turn it about the axis out of the screen
;;;;   pinch             zoom
;;;;   two-finger drag   pan
;;;;   tap a body        follow it; a planet with moons, close enough to see them
;;;;   double tap        back to the view from the north pole, following nothing
;;;;   tap elsewhere     hide or show the controls
;;;;
;;;; A panel at the bottom works time the way a movie player does: play and
;;;; pause, a scrubber over a window of time around the present date, the
;;;; window's width, the direction, the speed, and Now. The window follows
;;;; the date when it runs off either end, as a timeline that scrolls.

(in-package #:solar-system)

;;; ------------------------------------------------------------------
;;; the state of time

(defparameter +speeds+
  '(("1×" . 1d0) ("1h" . 3600d0) ("1d" . 86400d0) ("1w" . 604800d0)
    ("1mo" . 2629800d0) ("1y" . 31557600d0))
  "Simulated time per second of real time: the segmented control's choices.")

(defparameter +spans+
  '(("±1 y" . 365.25d0) ("±10 y" . 3652.5d0) ("±100 y" . 36525d0) ("±1000 y" . 365250d0))
  "Half-widths of the scrubber's window, in days.")

(defparameter +earliest-jd+ (jd-from-calendar -2999 1 1)
  "Where table 2's fit ends, 3000 BC; the clock stops here.")
(defparameter +latest-jd+ (jd-from-calendar 3000 1 1))

(defvar *playing* t)
(defvar *direction* 1)
(defvar *speed-index* 0 "Into +SPEEDS+, or NIL for *CUSTOM-RATE*.")
(defvar *custom-rate* nil "A rate from the launch arguments, not one of +SPEEDS+.")
(defvar *span-index* 1)
(defvar *window-centre* nil "JD at the middle of the scrubber.")
(defvar *scrubbing* nil)

(defvar *slider* nil)
(defvar *play-button* nil)
(defvar *direction-button* nil)
(defvar *speed-control* nil)
(defvar *span-button* nil)
(defvar *window-start-label* nil)
(defvar *window-end-label* nil)
(defvar *panel* nil)
(defvar *labels-button* nil)
(defvar *scale-button* nil)
(defvar *clock-label* nil "The date and rate, top left.")

(defun rate ()
  (if *speed-index* (cdr (nth *speed-index* +speeds+)) *custom-rate*))

(defun span-days ()
  (cdr (nth *span-index* +spans+)))

(defun apply-rate ()
  "Set the clock's rate from the controls: stopped while paused or while a
finger is on the scrubber."
  (set-time-scale (if (and *playing* (not *scrubbing*)) (* *direction* (rate)) 0d0)))

(defun describe-state ()
  (cond (*scrubbing* "scrubbing")
        ((not *playing*) "paused")
        (t (describe-rate *time-scale*))))

;;; ------------------------------------------------------------------
;;; the panel's parts

(defun symbol-image (name)
  (objc:invoke "UIImage" "systemImageNamed:" name))

(defun set-button-image (button name)
  (objc:invoke button "setImage:forState:" (symbol-image name) 0))

(defun on-event (control mask function)
  "Call FUNCTION with CONTROL on any of the UIControlEvents in MASK."
  (objc:invoke control "addTarget:action:forControlEvents:"
               (ui:action-target function) "fire:" mask)
  control)

(defconstant +touch-down+ 1)
(defconstant +touch-up+ (logior 64 128 256))   ; inside, outside, cancelled
(defconstant +value-changed+ 4096)

(defun date-part (jd)
  (subseq (format-jd jd) 0 (position #\Space (format-jd jd))))

(defun show-window ()
  "The slider's range and the dates at its ends, for the current window."
  (let ((span (span-days)))
    (objc:invoke *slider* "setMinimumValue:" (float (- span) 1.0))
    (objc:invoke *slider* "setMaximumValue:" (float span 1.0))
    (objc:invoke *window-start-label* "setText:"
                 (date-part (max +earliest-jd+ (- *window-centre* span))))
    (objc:invoke *window-end-label* "setText:"
                 (date-part (min +latest-jd+ (+ *window-centre* span))))))

(defun centre-window (jd)
  (setf *window-centre* jd)
  (show-window))

(defun show-playing ()
  (set-button-image *play-button* (if *playing* "pause.fill" "play.fill"))
  (set-button-image *direction-button* (if (plusp *direction*) "chevron.forward.2" "chevron.backward.2")))

(defun toggle-playing ()
  (setf *playing* (not *playing*))
  (apply-rate)
  (show-playing))

(defun after-frame (jd)
  "Called by DRAW-FRAME with the date it drew: stop at the ends of the
ephemeris, follow the date with the scrubber's window, move the thumb, and
move the labels."
  (update-labels)
  (step-scale)
  (when *slider*
    (when (or (< jd +earliest-jd+) (> jd +latest-jd+))
      (setf *playing* nil)
      (set-sim-date (max +earliest-jd+ (min +latest-jd+ jd)))
      (apply-rate)
      (show-playing)
      (setf jd (sim-jd)))
    (unless *scrubbing*
      (when (> (abs (- jd *window-centre*)) (span-days))
        (centre-window jd))
      (objc:invoke *slider* "setValue:animated:" (float (- jd *window-centre*) 1.0) nil))))

(defun now ()
  "Back to the present, in real time, playing forwards."
  (setf *playing* t *direction* 1 *speed-index* 0 *custom-rate* nil)
  (real-time)
  (apply-rate)
  (objc:invoke *speed-control* "setSelectedSegmentIndex:" 0)
  (show-playing)
  (centre-window (sim-jd)))

(defun make-slider ()
  (let ((slider (ui:new "UISlider")))
    (objc:invoke slider "setMinimumTrackTintColor:" (ui:color 0.95 0.75 0.35))
    (on-event slider +touch-down+
              (lambda (sender) (declare (ignore sender))
                (setf *scrubbing* t)
                (apply-rate)))
    (on-event slider +value-changed+
              (lambda (sender)
                (set-sim-date (max +earliest-jd+
                                   (min +latest-jd+
                                        (+ *window-centre* (objc:invoke sender "value")))))))
    (on-event slider +touch-up+
              (lambda (sender) (declare (ignore sender))
                (setf *scrubbing* nil)
                (apply-rate)))
    slider))

(defun small-label (text)
  (let ((label (ui:new "UILabel")))
    (objc:invoke label "setText:" text)
    (objc:invoke label "setFont:" (ui:mono-font 10))
    (objc:invoke label "setTextColor:" (ui:color 0.7 0.72 0.8))
    label))

(defun icon-button (image function)
  (let ((button (ui:system-button "")))
    (set-button-image button image)
    (objc:invoke button "setContentHuggingPriority:forAxis:" 751.0 0)
    (ui:fix button "widthAnchor" 36)
    (ui:on-tap button (lambda (sender) (declare (ignore sender)) (funcall function)))))

(defun row (&rest views)
  (let ((stack (ui:new "UIStackView")))
    (objc:invoke stack "setAxis:" 0)
    (objc:invoke stack "setSpacing:" 10d0)
    (objc:invoke stack "setAlignment:" 3)           ; centre
    (dolist (view views) (objc:invoke stack "addArrangedSubview:" view))
    stack))

(defun spacer ()
  "A view that takes up whatever room its row has left."
  (let ((view (ui:new "UIView")))
    (objc:invoke view "setContentHuggingPriority:forAxis:" 1.0 0)
    view))

(defun events-row ()
  "The events: the one before, the one in view, the one after."
  (row (icon-button "chevron.left" #'previous-event)
       (make-event-button)
       (icon-button "chevron.right" #'next-event)))

(defun tools-row ()
  "The toggles, spread along the row."
  (let ((row (apply #'row (toggle-buttons))))
    (objc:invoke row "setDistribution:" 3)       ; equal spacing
    row))

(defun toggle-buttons ()
  (list *labels-button* *trails-button* *scale-button*))

(defun make-panel ()
  "The playback controls, on a dark blur."
  (let* ((panel (objc:invoke (objc:invoke "UIVisualEffectView" "alloc") "initWithEffect:"
                             (objc:invoke "UIBlurEffect" "effectWithStyle:" 2)))   ; dark
         (column (ui:new "UIStackView")))
    (objc:invoke panel "setTranslatesAutoresizingMaskIntoConstraints:" nil)
    (objc:invoke panel "setOverrideUserInterfaceStyle:" 2)                      ; dark controls
    (objc:invoke (objc:invoke panel "layer") "setCornerRadius:" 16d0)
    (objc:invoke panel "setClipsToBounds:" t)
    (objc:invoke panel "setTintColor:" (ui:color 0.95 0.95 1.0))
    (setf *play-button* (icon-button "pause.fill" #'toggle-playing)
          *direction-button* (icon-button "chevron.forward.2"
                                          (lambda ()
                                            (setf *direction* (- *direction*))
                                            (apply-rate)
                                            (show-playing)))
          *slider* (make-slider)
          *span-button* (ui:system-button (car (nth *span-index* +spans+)))
          *speed-control* (objc:invoke (objc:invoke "UISegmentedControl" "alloc") "initWithItems:"
                                       (map 'vector #'car +speeds+))
          *window-start-label* (small-label "")
          *window-end-label* (small-label ""))
    (objc:invoke *span-button* "setContentHuggingPriority:forAxis:" 751.0 0)
    (objc:invoke (objc:invoke *span-button* "titleLabel") "setFont:" (ui:mono-font 12))
    (ui:on-tap *span-button*
               (lambda (sender)
                 (setf *span-index* (mod (1+ *span-index*) (length +spans+)))
                 (objc:invoke sender "setTitle:forState:" (car (nth *span-index* +spans+)) 0)
                 (centre-window (sim-jd))))
    (objc:invoke *speed-control* "setTranslatesAutoresizingMaskIntoConstraints:" nil)
    (objc:invoke *speed-control* "setSelectedSegmentIndex:" (or *speed-index* -1))
    (on-event *speed-control* +value-changed+
              (lambda (sender)
                (setf *speed-index* (objc:invoke sender "selectedSegmentIndex")
                      *custom-rate* nil)
                (apply-rate)))
    (let ((now-button (ui:system-button "Now"))
          (dates (row *window-start-label* *window-end-label*)))
      (objc:invoke now-button "setContentHuggingPriority:forAxis:" 751.0 0)
      (ui:on-tap now-button (lambda (sender) (declare (ignore sender)) (now)))
      (objc:invoke dates "setDistribution:" 3)       ; equal spacing: one each end
      (objc:invoke column "setAxis:" 1)
      (objc:invoke column "setSpacing:" 6d0)
      (setf *labels-button* (icon-button "tag.fill" #'toggle-labels)
            *trails-button* (icon-button "scribble.variable" #'toggle-trails)
            *scale-button* (icon-button "ruler" #'toggle-scale))
      (dolist (view (list (row *play-button* *slider* *span-button*)
                          dates
                          (row *direction-button* *speed-control* now-button)
                          (events-row)
                          (tools-row)))
        (objc:invoke column "addArrangedSubview:" view)))
    (objc:invoke (objc:invoke panel "contentView") "addSubview:" column)
    (let ((content (objc:invoke panel "contentView")))
      (ui:pin column "topAnchor" content "topAnchor" 10)
      (ui:pin column "bottomAnchor" content "bottomAnchor" -12)
      (ui:pin column "leadingAnchor" content "leadingAnchor" 14)
      (ui:pin column "trailingAnchor" content "trailingAnchor" -14))
    (setf *panel* panel)
    (centre-window (sim-jd))
    (show-playing)
    (make-tick-layers)
    panel))

;;; ------------------------------------------------------------------
;;; gestures

;;; Pinch, twist and two-finger drag are one motion of the hand; UIKit
;;; recognises only one gesture at a time unless a delegate says otherwise.
(objc:define-objc-class gesture-friend () ()
  (:objc-class-name "SolarGestureFriend"))

(objc:define-objc-method ("gestureRecognizer:shouldRecognizeSimultaneouslyWithGestureRecognizer:"
                          objc:objc-bool)
    ((self gesture-friend) (one objc:objc-object-pointer) (other objc:objc-object-pointer))
  (declare (ignore one other))
  t)

(defvar *gesture-friend* nil)

(defparameter *turn-per-point* 0.008d0 "Radians of turn per point of drag.")

(defun add-gesture (view class-name function &rest settings)
  "A CLASS-NAME recognizer on VIEW calling FUNCTION with itself. SETTINGS
are selector and argument, alternately, sent to it first."
  (let ((recognizer (objc:invoke (objc:invoke class-name "alloc") "initWithTarget:action:"
                                 (ui:action-target function) "fire:")))
    (loop for (selector argument) on settings by #'cddr
          do (objc:invoke recognizer selector argument))
    (objc:invoke view "addGestureRecognizer:" recognizer)
    recognizer))

(defun drawable-metrics (view)
  "Values height in pixels, aspect, and pixels per point."
  (let ((size (objc:invoke view "drawableSize")))
    (values (float (aref size 1) 1d0)
            (/ (float (aref size 0) 1d0) (float (aref size 1) 1d0))
            (float (objc:invoke view "contentScaleFactor") 1d0))))

(defun translation (recognizer view)
  "The recognizer's translation since the last call, in points, y down."
  (let ((moved (objc:invoke recognizer "translationInView:" view)))
    (objc:invoke recognizer "setTranslation:inView:" #(0d0 0d0) view)
    (values (float (aref moved 0) 1d0) (float (aref moved 1) 1d0))))

(defun add-gestures (view)
  (setf *gesture-friend* (ui:keep (make-instance 'gesture-friend)))
  (add-gesture view "UIPanGestureRecognizer"
               (lambda (recognizer)
                 (multiple-value-bind (dx dy) (translation recognizer view)
                   (turn-camera *camera* 1 (* *turn-per-point* dx))
                   (turn-camera *camera* 0 (* *turn-per-point* dy))))
               "setMaximumNumberOfTouches:" 1)
  (add-gesture view "UIPanGestureRecognizer"
               (lambda (recognizer)
                 (multiple-value-bind (dx dy) (translation recognizer view)
                   (multiple-value-bind (height aspect scale) (drawable-metrics view)
                     ;; Panning away from what is followed stops following it.
                     (setf *focus* nil)
                     (pan-camera *camera* (* dx scale) (- (* dy scale)) height aspect))))
               "setMinimumNumberOfTouches:" 2
               "setDelegate:" *gesture-friend*)
  (add-gesture view "UIPinchGestureRecognizer"
               (lambda (recognizer)
                 (zoom-camera *camera* (float (objc:invoke recognizer "scale") 1d0))
                 (objc:invoke recognizer "setScale:" 1d0))
               "setDelegate:" *gesture-friend*)
  (add-gesture view "UIRotationGestureRecognizer"
               (lambda (recognizer)
                 ;; UIKit's angle is clockwise on the screen; the camera's
                 ;; z turn is anticlockwise, y being up.
                 (turn-camera *camera* 2 (- (float (objc:invoke recognizer "rotation") 1d0)))
                 (objc:invoke recognizer "setRotation:" 0d0))
               "setDelegate:" *gesture-friend*)
  (let ((double (add-gesture view "UITapGestureRecognizer"
                             (lambda (recognizer) (declare (ignore recognizer))
                               (setf *focus* nil)
                               (reset-camera *camera*))
                             "setNumberOfTapsRequired:" 2)))
    (let ((single (add-gesture view "UITapGestureRecognizer"
                               (lambda (recognizer)
                                 (let* ((point (objc:invoke recognizer "locationInView:" view))
                                        (body (body-at view (float (aref point 0) 1d0)
                                                       (float (aref point 1) 1d0))))
                                   (if body
                                       (focus-on body)
                                       (let ((hide (not (objc:invoke-bool *panel* "isHidden"))))
                                         (objc:invoke *panel* "setHidden:" hide)
                                         (objc:invoke *clock-label* "setHidden:" hide))))))))
      (objc:invoke single "requireGestureRecognizerToFail:" double))))
