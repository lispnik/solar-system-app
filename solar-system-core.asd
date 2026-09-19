;;;; solar-system-core.asd -- the physics, without the phone.
;;;;
;;;; Its own file so that testing it on the host never reads
;;;; solar-system.asd, whose :DEFSYSTEM-DEPENDS-ON would load the iOS build
;;;; machinery.
;;;;
;;;;   sbcl --eval '(asdf:test-system "solar-system-core")' --quit

(defsystem "solar-system-core"
  :description "Heliocentric planet positions at any instant from JPL's Keplerian elements, a clock that runs at any rate, and a projection to the screen."
  :version "1.0.0"
  :serial t
  :pathname "src/"
  :components ((:file "package")
               (:file "time")
               (:file "ephemeris")
               (:file "dwarf-elements")
               (:file "dwarfs")
               (:file "moon-elements")
               (:file "moons")
               (:file "projection")
               (:file "camera")
               (:file "rotation")
               (:file "events")
               (:file "comets"))
  :in-order-to ((test-op (test-op "solar-system-core/test"))))

(defsystem "solar-system-core/test"
  :depends-on ("solar-system-core" "fiveam")
  :pathname "test/"
  :components ((:file "ephemeris-tests"))
  :perform (test-op (op c)
             (unless (uiop:symbol-call '#:solar-system/test '#:run-tests)
               (error "solar-system-core tests failed"))))
