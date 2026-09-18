;;;; solar-system.asd -- the Sun and the planets, seen from above, in Metal.
;;;;
;;;;   ecl --eval '(asdf:make "solar-system")' --eval '(ext:quit)'
;;;;   (ios-app:run-in-simulator "solar-system")
;;;;
;;;; SOLAR_REPL=1 at build time adds slynk and listens on 4005, as the live
;;;; example does; slynk must then be on the source registry.

(defsystem "solar-system"
  :defsystem-depends-on ("asdf-ios-app")
  :class :ios-app-system
  :build-operation "ios-app-op"
  :entry-point "solar-system:start"
  :description "The solar system from above, the planets where JPL's elements put them now, drawn in Metal."
  :version "1.0.0"
  :serial t
  :depends-on #.(append '("solar-system-core" "objc/uikit" "cffi")
                        (when (uiop:getenv "SOLAR_REPL") '("slynk")))
  :pathname "src/"
  :components ((:file "app-package")
               (:file "render")
               (:file "controls")
               (:file "labels")
               (:file "scale")
               (:file "timeline")
               (:file "app"))

  :bundle-identifier "org.asdf-ios-app.solar-system"
  :bundle-name "Solar"
  :bundle-display-name "Solar System"
  :bundle-executable "solar"
  :bundle-orientations (:portrait :landscape-left :landscape-right)
  :bundle-status-bar-hidden t
  ;; Without this the root view controller decides, and it shows the bar.
  :bundle-info-plist (("UIViewControllerBasedStatusBarAppearance" . :false))
  :bundle-frameworks ("UIKit" "Foundation" "CoreGraphics" "QuartzCore" "Metal" "MetalKit")
  :remote-repl #.(and (uiop:getenv "SOLAR_REPL") t)

  ;; A device build is made only when it can be signed; identity, team and
  ;; profile come from the environment when this file is read, as in the
  ;; asdf-ios-app examples, so nobody's identity is committed here.
  :bundle-platforms #.(if (uiop:getenv "IOS_SIGNING_IDENTITY")
                          '(:simulator :device)
                          '(:simulator))
  :code-signing-identity #.(or (uiop:getenv "IOS_SIGNING_IDENTITY") :automatic)
  :development-team #.(uiop:getenv "IOS_DEVELOPMENT_TEAM")
  :provisioning-profile #.(uiop:getenv "IOS_PROVISIONING_PROFILE"))
