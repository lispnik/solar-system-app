;;;; store-scenes.lisp -- the eight scenes the App Store screenshots show.
;;;;
;;;; The pictures are staged from a REPL in a running app, since every one
;;;; of them is a moment in time: build with SOLAR_REPL=1, install on a
;;;; 6.9-inch simulator (iPhone 17 Pro Max -- 1320 x 2868, the size App
;;;; Store Connect asks for), and send this file, then each scene, over
;;;; slynk. Screenshot with
;;;;
;;;;     xcrun simctl io <device> screenshot NN-name.png
;;;;
;;;; and put the captions on with tools/make-store-shots.swift.
;;;;
;;;; Load into the SOLAR-SYSTEM package.

(defun scene (&key (date nil) (sky nil) (focus nil) (tilt 0d0) (turn 0d0) (zoom nil) (rate 0)
                   (playing nil) (labels t) (trails t) (small t) (true-scale nil))
  "Put the app in a known state: a date (or now), from outside or from the
Earth, following something, turned and zoomed, with the toggles set."
  (ios-app-runtime:on-main
   (lambda ()
     (when *pointing* (stop-pointing))
     (when *sky-mode* (leave-sky))
     (setf *labels-on* labels *trails-on* trails *small-bodies-on* small
           *true-scale* true-scale *scale-animation* nil
           *radius-exponent* (if true-scale 1d0 0.4d0)
           *focus* nil *observer* nil *trails* '())
     (reset-camera *camera*)
     (turn-camera *camera* 0 tilt)
     (turn-camera *camera* 1 turn)
     (if date (set-sim-date date) (real-time))
     (setf *playing* playing *speed-index* rate)
     (objc:invoke *speed-control* "setSelectedSegmentIndex:" rate)
     (apply-rate) (show-playing) (sync-toggle-buttons)
     (centre-window (sim-jd))
     (when sky (enter-sky))
     (when focus (focus-on (find-body focus)))
     (when zoom (setf (camera-zoom *camera*) zoom))))
  :ok)

(defun closer (factor)
  "FACTOR times nearer than the zoom FOCUS-ON chose."
  (ios-app-runtime:on-main
   (lambda () (setf (camera-zoom *camera*) (* factor (camera-zoom *camera*)))))
  :ok)

;;; 01-overview -- everything, now, tilted.
#+(or)
(scene :labels t :trails nil :small t :playing t :tilt 0.42 :turn 0.15 :zoom 1.22)

;;; 02-eclipse -- totality, from the point of greatest eclipse. The Sun is
;;; followed and the observer put where the Moon's shadow falls deepest.
#+(or)
(progn
  (scene :date (jd-from-calendar 2026 8 12 17 46) :sky t :focus "Sun" :labels t :trails nil)
  (ios-app-runtime:on-main
   (lambda ()
     (multiple-value-bind (lon lat) (eclipse-surface-point (utc-to-tt (sim-jd)))
       (setf *observer* (cons lon lat)))
     (setf (camera-zoom *camera*) 30d0))))

;;; 03-earth -- the Earth and the Moon, from outside.
#+(or)
(progn (scene :focus "Earth" :labels t :trails nil :tilt 0.55 :turn 0.9) (closer 2.5d0))

;;; 04-saturn -- the rings open, the shadow across them, five moons.
#+(or)
(progn (scene :date (jd-from-calendar 2032 6 1) :focus "Saturn" :labels t :trails nil
              :tilt 0.5 :turn 2.0)
       (closer 5d0))

;;; 05-jupiter -- from the Earth at opposition, the Galilean moons beside it.
#+(or)
(progn (scene :date (jd-from-calendar 2026 1 10 22 0) :sky t :focus "Jupiter"
              :labels t :trails nil)
       (closer 1.45d0))

;;; 06-lunar -- the Moon in the Earth's umbra, from the Earth.
#+(or)
(scene :date (jd-from-calendar 2025 3 14 6 58) :sky t :focus "Moon" :labels t :trails nil
       :zoom 30d0)

;;; 07-uranus -- on its side, with its rings and moons.
#+(or)
(progn (scene :date (jd-from-calendar 2026 11 1) :focus "Uranus" :labels t :trails nil
              :tilt 0.35 :turn 1.2)
       (closer 3.5d0))

;;; 08-comet -- NEOWISE at perihelion, among the inner planets.
#+(or)
(progn (scene :date (jd-from-calendar 2020 7 3 12 0) :focus "NEOWISE" :labels t :trails nil
              :small t :tilt 0.6 :turn 0.4)
       (closer 6d0))
