;;;; package.lisp -- two packages: the physics, and the app that draws it.
;;;;
;;;; SOLAR-SYSTEM.CORE is plain Common Lisp: time, the ephemeris and the
;;;; projection to the screen. It loads on the host with nothing else, so it
;;;; can be tested without a simulator. SOLAR-SYSTEM is the iOS app, and is
;;;; defined in app-package.lisp, since only the app build has UIKIT.

(defpackage #:solar-system.core
  (:use #:cl)
  (:export
   ;; time
   #:+j2000+ #:*delta-t* #:jd-from-2001-seconds #:jd-from-universal-time
   #:jd-from-calendar #:calendar-from-jd #:format-jd #:utc-to-tt
   #:centuries-since-j2000
   ;; the simulation clock
   #:*wall-clock* #:*time-scale* #:sim-jd #:set-time-scale #:set-sim-date
   #:real-time
   ;; bodies and the ephemeris
   #:body #:body-name #:body-radius-km #:body-colour #:body-mass-ratio
   #:+sun+ #:*planets* #:find-planet
   #:solve-kepler #:heliocentric-position #:orbit-points #:aphelion
   #:sun-barycentric-offset #:*frame* #:body-positions
   ;; dwarf planets and moons
   #:*dwarfs* #:heliocentric-bodies #:find-body #:*moons* #:moons-of #:body-parent
   #:body-moon #:moon-offset #:moon-orbit-points #:lunar-position #:+km-per-au+
   #:*comets* #:body-comet #:comet-orbit-points #:comet-tail
   ;; standing on the Earth
   #:observer-position #:horizon-axes #:altitude-azimuth #:device-camera-rotation
   #:matrix-quaternion #:body-facts #:centre-of
   ;; projection into the scene
   #:*radius-exponent* #:compression #:compress #:disc-radius
   #:moon-system-scales #:moon-display-offset
   ;; the camera
   #:*field-of-view* #:camera #:make-camera #:reset-camera #:camera-zoom
   #:turn-camera #:zoom-camera #:pan-camera #:camera-distance #:fit-distance
   #:view-position #:view-matrix #:projection-matrix
   #:camera-mode #:camera-field-of-view #:*centre-field-of-view* #:look-along
   ;; events
   #:event #:event-jd #:event-kind #:event-title #:event-utc #:find-events
   #:events-in-chunk #:chunk-start #:+chunk-days+ #:eclipse-surface-point
   ;; rotation
   #:body-axes #:body-longitude-latitude #:obliquity-of #:geocentric #:earth-position))
