;;;; persist.lisp -- the app as it was left.
;;;;
;;;; One property list, printed, in NSUserDefaults: the speed, direction and
;;;; whether it was playing; the scrubber's span; the toggles; the camera
;;;; and what it followed; and the date. Read back before the interface is
;;;; built, so the controls come up showing it. Left running at real time,
;;;; the app comes back to now -- that is what real time means; left
;;;; anywhere else, it comes back to the date on the clock.
;;;;
;;;; Written when it has changed, checked every two seconds: cheaper than
;;;; watching for the app going to the background, and a crash loses two
;;;; seconds at most.

(in-package #:solar-system)

(defparameter +state-key+ "SolarSystemState")
(defparameter +state-version+ 1)

(defvar *toggles* '(*labels-on* *true-scale* *trails-on*)
  "Boolean settings saved as they are. Features add theirs.")
(defvar *saved-state* nil "The text last written, to write only on a change.")

(defun defaults ()
  (objc:invoke "NSUserDefaults" "standardUserDefaults"))

(defun real-time-p ()
  (and *playing* (eql *speed-index* 0) (plusp *direction*)))

(defun current-state ()
  (let ((camera *camera*))
    (list :version +state-version+
          :speed-index *speed-index* :custom-rate *custom-rate*
          :direction *direction* :playing *playing* :span-index *span-index*
          :real-time (real-time-p) :jd (sim-jd)
          :toggles (mapcar (lambda (symbol) (cons (symbol-name symbol) (symbol-value symbol)))
                           *toggles*)
          :rotation (coerce (solar-system.core::camera-rotation camera) 'list)
          :target (coerce (solar-system.core::camera-target camera) 'list)
          :zoom (camera-zoom camera)
          :focus (and *focus* (body-name *focus*)))))

(defun save-state ()
  "Write the state if it has changed since last written."
  (let ((text (let ((*print-readably* nil) (*read-default-float-format* 'double-float))
                ;; The date to the second is enough, and keeps a running
                ;; clock from counting as a change every time.
                (prin1-to-string (let ((state (current-state)))
                                   (setf (getf state :jd) (/ (round (* 86400 (getf state :jd))) 86400d0))
                                   state)))))
    (unless (equal text *saved-state*)
      (objc:invoke (defaults) "setObject:forKey:" text +state-key+)
      (setf *saved-state* text))))

(defun read-state ()
  (let ((stored (objc:invoke (defaults) "stringForKey:" +state-key+)))
    (unless (nothing-p stored)
      (ignore-errors
       (let ((*read-eval* nil) (*read-default-float-format* 'double-float)
             (*package* (find-package '#:solar-system)))
         (let ((state (read-from-string (if (stringp stored) stored (objc:ns-string-to-string stored)))))
           (and (listp state) (eql (getf state :version) +state-version+) state)))))))

(defun restore-state ()
  "Put back what READ-STATE finds, if anything; T if it did."
  (let ((state (read-state)))
    (when state
      (setf *speed-index* (getf state :speed-index)
            *custom-rate* (getf state :custom-rate)
            *direction* (or (getf state :direction) 1)
            *playing* (getf state :playing)
            *span-index* (or (getf state :span-index) 1))
      (unless (or *speed-index* *custom-rate*) (setf *speed-index* 0))
      (loop for (name . value) in (getf state :toggles)
            for symbol = (find name *toggles* :key #'symbol-name :test #'string=)
            when symbol do (setf (symbol-value symbol) value))
      (when *true-scale* (setf *radius-exponent* 1d0))
      (let ((rotation (getf state :rotation)) (target (getf state :target)))
        (when (and (= 9 (length rotation)) (= 3 (length target)))
          (replace (solar-system.core::camera-rotation *camera*) (mapcar (lambda (x) (float x 1d0)) rotation))
          (replace (solar-system.core::camera-target *camera*) (mapcar (lambda (x) (float x 1d0)) target))
          (setf (camera-zoom *camera*) (float (or (getf state :zoom) 1d0) 1d0))))
      (setf *focus* (and (getf state :focus) (find-body (getf state :focus))))
      (if (getf state :real-time)
          (real-time)
          (set-sim-date (float (getf state :jd) 1d0)))
      (apply-rate)
      (setf *saved-state* nil)
      t)))
