;;;; timeline.lisp -- events on the timeline, like chapters in a video.
;;;;
;;;; A thread of its own searches for events (events.lisp) outward from the
;;;; date on the clock, thirty days at a time, over the scrubber's window and
;;;; a margin; it never touches the frame. What it has found is published as
;;;; a sorted vector, which the interface reads: ticks along the scrubber,
;;;; one colour a kind, and a row with the next event's name between two
;;;; buttons that jump to the one before and the one after. A jump pauses on
;;;; the event, and for an eclipse follows the Earth, where the Moon lines up.

(in-package #:solar-system)

;;; ------------------------------------------------------------------
;;; the search, on its own thread

(defvar *found* (make-hash-table :test 'equal)
  "Every event found, keyed by kind, title and its hour: chunks overlap by
nothing, but a search restarted elsewhere may find one again. The searcher
alone writes it.")
(defvar *events* #() "What has been found so far, in order: the searcher
replaces the whole vector, the interface only reads it.")
(defvar *events-version* 0 "Bumped each time *EVENTS* is replaced.")
(defvar *search-target* nil "(from . to), JD TT: what the interface wants covered.")
(defvar *covered* nil "(from . to), JD TT, chunk-aligned: what has been searched.")
(defvar *searcher* nil)

(defun publish-events ()
  (let ((events (sort (loop for event being the hash-values of *found* collect event)
                      #'< :key #'event-jd)))
    (setf *events* (coerce events 'simple-vector))
    (incf *events-version*)))

(defun search-next-chunk ()
  "Search one more chunk towards the target, on whichever side of what is
covered is nearer the clock; NIL when the target is covered."
  (let ((target *search-target*))
    (when target
      (destructuring-bind (from . to) target
        (let ((covered *covered*)
              (now (utc-to-tt (sim-jd))))
          ;; Somewhere else entirely: start again around the clock.
          (when (or (null covered) (< (cdr covered) from) (> (car covered) to))
            (let ((start (chunk-start (max from (min to now)))))
              (setf covered (cons start start) *covered* covered)))
          (let ((need-before (< from (car covered)))
                (need-after (> to (cdr covered))))
            (when (or need-before need-after)
              (let ((start (if (and need-before
                                    (or (not need-after)
                                        (< (- now (car covered)) (- (cdr covered) now))))
                               (- (car covered) +chunk-days+)
                               (cdr covered))))
                (dolist (event (events-in-chunk start))
                  (setf (gethash (list (event-kind event) (event-title event)
                                       (round (* 24 (event-jd event))))
                                 *found*)
                        event))
                (setf *covered* (cons (min (car covered) start)
                                      (max (cdr covered) (+ start +chunk-days+))))
                t))))))))

(defun searcher-loop ()
  (handler-case
      (let ((since-published 0))
        (loop
          (if (search-next-chunk)
              (when (>= (incf since-published) 6)
                (publish-events)
                (setf since-published 0))
              (progn
                (when (plusp since-published)
                  (publish-events)
                  (setf since-published 0))
                (sleep 0.25)))))
    (error (condition)
      (format t "~&SOLAR: the event search stopped: ~a~%" condition)
      (finish-output))))

(defun start-searcher ()
  (unless *searcher*
    (setf *searcher* (mp:process-run-function "event search" #'searcher-loop))))

(defun want-events-around (centre-utc half-width-days)
  "Ask the searcher for the window, and a sixth again each side."
  (let ((centre (utc-to-tt centre-utc))
        (reach (* half-width-days 7/6)))
    (setf *search-target* (cons (- centre reach) (+ centre reach)))))

;;; ------------------------------------------------------------------
;;; finding among what has been found

(defun event-after (jd-utc)
  "The first event after JD-UTC (by a minute), or NIL."
  (let ((events *events*) (jd (+ (utc-to-tt jd-utc) (/ 1d0 1440))))
    (find-if (lambda (event) (> (event-jd event) jd)) events)))

(defun event-before (jd-utc)
  (let ((events *events*) (jd (- (utc-to-tt jd-utc) (/ 1d0 1440))))
    (find-if (lambda (event) (< (event-jd event) jd)) events :from-end t)))

(defun event-at (jd-utc)
  "An event within an hour of JD-UTC: the one the clock is on."
  (let ((jd (utc-to-tt jd-utc)))
    (find-if (lambda (event) (< (abs (- (event-jd event) jd)) (/ 1d0 24))) *events*)))

;;; ------------------------------------------------------------------
;;; the interface

(defparameter +event-colours+
  '((:solar-eclipse 1.0 0.80 0.30) (:lunar-eclipse 0.95 0.38 0.30)
    (:transit 0.95 0.95 0.95) (:opposition 0.45 0.65 1.0) (:conjunction 0.45 0.90 0.55)))

(defvar *tick-layers* '() "(kind . CAShapeLayer) on the scrubber.")
(defvar *ticks-drawn-for* nil "(version centre span width) the ticks show.")
(defvar *event-button* nil)
(defvar *shown-event* nil)

(defun make-tick-layers ()
  "One shape layer a kind, over the top of the scrubber, touch-transparent
as layers are."
  (setf *tick-layers*
        (loop for (kind r g b) in +event-colours+
              collect (let ((layer (objc:alloc-init-object "CAShapeLayer")))
                        (objc:invoke layer "setStrokeColor:"
                                     (objc:invoke (ui:color r g b 0.95) "CGColor"))
                        (objc:invoke layer "setLineWidth:" 1.5d0)
                        (objc:invoke (objc:invoke *slider* "layer") "addSublayer:" layer)
                        (cons kind layer)))))

(defun thumb-x (value bounds track)
  "Where the thumb's centre is for VALUE, in the slider's own points."
  (let ((rect (objc:invoke *slider* "thumbRectForBounds:trackRect:value:"
                           bounds track (float value 1.0))))
    (+ (aref rect 0) (* 0.5d0 (aref rect 2)))))

(defun draw-ticks ()
  "A short line above the track for every event in the window, one column
of pixels at most a kind."
  (let* ((bounds (objc:invoke *slider* "bounds"))
         (track (objc:invoke *slider* "trackRectForBounds:" bounds))
         (span (span-days))
         (x0 (thumb-x (- span) bounds track))
         (x1 (thumb-x span bounds track))
         (top (- (aref track 1) 7d0)))
    (loop for (kind . layer) in *tick-layers*
          do (let ((path (objc:invoke "UIBezierPath" "bezierPath"))
                   (columns (make-hash-table)))
               (loop for event across *events*
                     for days = (- (event-utc event) *window-centre*)
                     when (and (eq (event-kind event) kind) (<= (abs days) span))
                       do (let ((x (+ x0 (* (- x1 x0) (/ (+ days span) (* 2 span))))))
                            (unless (gethash (round x) columns)
                              (setf (gethash (round x) columns) t)
                              (objc:invoke path "moveToPoint:" (vector x top))
                              (objc:invoke path "addLineToPoint:" (vector x (+ top 5d0))))))
               (objc:invoke layer "setPath:" (objc:invoke path "CGPath"))))))

(defun event-date (event)
  (subseq (format-jd (event-utc event)) 0 16))

(defun show-event-name ()
  "The event the clock is on, or else the next one, in the row's button."
  (let* ((now (sim-jd))
         (event (or (event-at now) (event-after now))))
    (unless (eq event *shown-event*)
      (setf *shown-event* event)
      (objc:invoke *event-button* "setTitle:forState:"
                   (if event
                       (format nil "~a~%~a UTC" (event-title event) (event-date event))
                       (if (plusp (length *events*)) "no more events in view" "searching for events…"))
                   0))))

(defun update-timeline ()
  "Four times a second: ask for the window, redraw the ticks if what is
found or the window has changed, and name the event in view."
  (when *slider*
    (want-events-around *window-centre* (span-days))
    (let ((key (list *events-version* *window-centre* (span-days)
                     (aref (objc:invoke *slider* "bounds") 2))))
      (unless (equal key *ticks-drawn-for*)
        (setf *ticks-drawn-for* key)
        (draw-ticks)))
    (show-event-name)))

(defun jump-to-event (event)
  "Stop on EVENT; for an eclipse, follow the Earth."
  (when event
    (setf *playing* nil)
    (set-sim-date (event-utc event))
    (apply-rate)
    (show-playing)
    (when (> (abs (- (event-utc event) *window-centre*)) (span-days))
      (centre-window (event-utc event)))
    ;; An eclipse: from outside, follow the Earth, where the Moon lines up;
    ;; from the Earth, look at the Sun or the Moon it is happening to.
    (setf *observer* (and *sky-mode* (eq (event-kind event) :solar-eclipse)
                          (multiple-value-bind (lon lat) (eclipse-surface-point (event-jd event))
                            (cons lon lat))))
    (case (event-kind event)
      (:solar-eclipse (focus-on (if *sky-mode* +sun+ (find-planet "Earth"))))
      (:lunar-eclipse (focus-on (if *sky-mode* (find-body "Moon") (find-planet "Earth")))))
    (setf *shown-event* nil)
    (show-event-name)))

(defun make-event-button ()
  (let ((button (ui:system-button "searching for events…")))
    (objc:invoke (objc:invoke button "titleLabel") "setFont:" (ui:mono-font 11))
    (objc:invoke (objc:invoke button "titleLabel") "setNumberOfLines:" 2)
    (objc:invoke (objc:invoke button "titleLabel") "setTextAlignment:" 1)   ; centred
    (objc:invoke (objc:invoke button "titleLabel") "setLineBreakMode:" 4)   ; truncate in the middle
    (objc:invoke button "setContentHuggingPriority:forAxis:" 1.0 0)
    (objc:invoke button "setContentCompressionResistancePriority:forAxis:" 250.0 0)
    (ui:on-tap button (lambda (sender) (declare (ignore sender)) (jump-to-event *shown-event*)))
    (setf *event-button* button)))

(defun previous-event () (jump-to-event (event-before (sim-jd))))
(defun next-event () (jump-to-event (event-after (sim-jd))))
