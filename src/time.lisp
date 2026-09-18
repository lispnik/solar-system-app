;;;; time.lisp -- Julian Dates, and a clock that can run at any rate.
;;;;
;;;; Everything downstream wants one number: Julian centuries of Terrestrial
;;;; Time since J2000, which is what the ephemeris's rates are per. The clock
;;;; turns wall time into a simulation Julian Date: at *TIME-SCALE* 1 the two
;;;; agree, and at any other rate the simulation date moves that much faster,
;;;; from wherever it was when the rate changed. Nothing is integrated, so a
;;;; date a thousand years away costs the same as the next frame.

(in-package #:solar-system.core)

(defconstant +j2000+ 2451545d0
  "JD of 2000-01-01 12:00 TT, the epoch of the ephemeris.")

(defconstant +jd-2001+ 2451910.5d0
  "JD of 2001-01-01 00:00 UTC, the epoch of NSDate's reference date.")

(defconstant +jd-1900+ 2415020.5d0
  "JD of 1900-01-01 00:00 UTC, the epoch of Common Lisp's universal time.")

(defparameter *delta-t* 69.2d0
  "TT - UTC in seconds. 32.184 s plus the leap seconds, 37 since 2017. It is
here for correctness rather than visibility: a minute of Mercury's motion is
well under a pixel.")

(defun jd-from-2001-seconds (seconds)
  "JD (UTC) from seconds since 2001-01-01 00:00 UTC, as
-[NSDate timeIntervalSinceReferenceDate] answers."
  (+ +jd-2001+ (/ (float seconds 1d0) 86400d0)))

(defun jd-from-universal-time (&optional (universal-time (get-universal-time)))
  "JD (UTC) from a Common Lisp universal time. Whole seconds only."
  (+ +jd-1900+ (/ (float universal-time 1d0) 86400d0)))

(defun utc-to-tt (jd)
  (+ jd (/ *delta-t* 86400d0)))

(defun centuries-since-j2000 (jd-tt)
  (/ (- jd-tt +j2000+) 36525d0))

;;; ------------------------------------------------------------------
;;; calendar <-> JD, Meeus, Astronomical Algorithms ch. 7
;;;
;;; Gregorian from 1582-10-15, Julian before, as astronomers count; year 0
;;; is 1 BC.

(defun jd-from-calendar (year month day &optional (hour 0) (minute 0) (second 0))
  (let* ((d (+ day (/ (+ hour (/ minute 60d0) (/ second 3600d0)) 24d0)))
         (y (if (<= month 2) (1- year) year))
         (m (if (<= month 2) (+ month 12) month))
         (gregorian (or (> year 1582)
                        (and (= year 1582) (or (> month 10) (and (= month 10) (>= day 15))))))
         (b (if gregorian
                (let ((a (floor y 100))) (+ 2 (- a) (floor a 4)))
                0)))
    (+ (floor (* 365.25d0 (+ y 4716)))
       (floor (* 30.6001d0 (1+ m)))
       d b -1524.5d0)))

(defun calendar-from-jd (jd)
  "Values year, month, day, hour, minute, second (the last a double)."
  (multiple-value-bind (z f) (floor (+ jd 0.5d0))
    (let* ((a (if (< z 2299161)
                  z
                  (let ((alpha (floor (- z 1867216.25d0) 36524.25d0)))
                    (+ z 1 alpha (- (floor alpha 4))))))
           (b (+ a 1524))
           (c (floor (- b 122.1d0) 365.25d0))
           (d (floor (* 365.25d0 c)))
           (e (floor (- b d) 30.6001d0))
           (day (- b d (floor (* 30.6001d0 e))))
           (month (if (< e 14) (1- e) (- e 13)))
           (year (if (> month 2) (- c 4716) (- c 4715)))
           (seconds (* f 86400d0)))
      (multiple-value-bind (hour rest) (floor seconds 3600)
        (multiple-value-bind (minute second) (floor rest 60)
          (values year month day hour minute second))))))

(defun format-jd (jd)
  "\"2026-09-18 14:31:07 UTC\", for a JD in UTC."
  (multiple-value-bind (year month day hour minute second) (calendar-from-jd jd)
    (format nil "~:[~;-~]~4,'0d-~2,'0d-~2,'0d ~2,'0d:~2,'0d:~2,'0d UTC"
            (minusp year) (abs year) month day hour minute (floor second))))

;;; ------------------------------------------------------------------
;;; the simulation clock

(defvar *wall-clock* #'jd-from-universal-time
  "A function of no arguments answering the wall time as a JD (UTC). The app
replaces it with one reading NSDate, which has sub-millisecond resolution.")

(defvar *time-scale* 1d0
  "Simulated seconds per wall-clock second. Change it with SET-TIME-SCALE,
which keeps the simulation date continuous; SETF alone makes it jump.")

(defvar *anchor-wall* nil "Wall JD when the clock was last anchored.")
(defvar *anchor-sim* nil "Simulation JD at that moment.")

(defun wall-jd ()
  (funcall *wall-clock*))

(defun sim-jd ()
  "The simulation's JD (UTC), now."
  (let ((now (wall-jd)))
    (unless *anchor-wall*
      (setf *anchor-wall* now
            *anchor-sim* now))
    (+ *anchor-sim* (* (- now *anchor-wall*) *time-scale*))))

(defun set-time-scale (scale)
  "Run the simulation at SCALE times real time from the date it shows now.
Negative runs it backwards."
  (let ((jd (sim-jd)))
    (setf *anchor-wall* (wall-jd)
          *anchor-sim* jd
          *time-scale* (float scale 1d0))))

(defun set-sim-date (jd)
  "Jump the simulation to JD (UTC), keeping the current rate."
  (setf *anchor-wall* (wall-jd)
        *anchor-sim* (float jd 1d0))
  jd)

(defun real-time ()
  "Back to now, at rate 1."
  (setf *anchor-wall* nil
        *anchor-sim* nil
        *time-scale* 1d0)
  (sim-jd))
