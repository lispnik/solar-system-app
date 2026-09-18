;;;; app-package.lisp -- the app, which draws what SOLAR-SYSTEM.CORE computes.

(defpackage #:solar-system
  (:use #:cl #:solar-system.core)
  (:local-nicknames (#:ui #:uikit))
  (:export #:start #:resume #:now #:*camera*
           ;; the knobs, for a remote REPL
           #:*time-scale* #:set-time-scale #:set-sim-date #:real-time
           #:jd-from-calendar #:*radius-exponent* #:*frame*))
