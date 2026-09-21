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
  ;; CFBundleVersion: the build number, which every upload must raise.
  ;; SOLAR_BUILD=1.0.4 ecl ... for the next one.
  :version #.(or (uiop:getenv "SOLAR_BUILD") "1.0.0")
  :serial t
  :depends-on #.(append '("solar-system-core" "objc/uikit" "cffi")
                        (when (uiop:getenv "SOLAR_REPL") '("slynk")))
  :pathname "src/"
  :components ((:file "app-package")
               ;; The renderer, state first (gpu-state.lisp says what is where).
               (:file "gpu-state")
               (:file "shaders")
               (:file "metal")
               (:file "belt")
               (:file "bodies")
               (:file "orbits")
               (:file "view")
               (:file "frame")
               (:file "trails")
               (:file "sky")
               (:file "controls")
               (:file "labels")
               (:file "pointer")
               (:file "scale")
               (:file "timeline")
               (:file "card")
               (:file "about")
               (:file "persist")
               (:file "app"))

  :bundle-identifier "com.burnsidemk.solarsystem"
  :bundle-short-version "1.0"
  :bundle-name "Solar"
  :bundle-display-name "Solar System"
  :bundle-executable "solar"
  :bundle-device-family (:iphone)
  :bundle-orientations (:portrait :landscape-left :landscape-right)
  ;; Drawn by tools/make-icon.swift.
  :bundle-icon "res/Icon.xcassets"
  :bundle-status-bar-hidden t
  ;; A distribution build must not let a debugger attach.
  :get-task-allow #.(not (uiop:getenv "SOLAR_DISTRIBUTION"))
  ;; UIViewControllerBasedStatusBarAppearance: without it the root view
  ;; controller decides, and it shows the bar.
  :bundle-info-plist (("UIViewControllerBasedStatusBarAppearance" . :false)
                      ;; No encryption beyond what iOS itself provides, so
                      ;; that no export-compliance question is asked on
                      ;; every upload.
                      ("ITSAppUsesNonExemptEncryption" . :false)
                      ("NSLocationWhenInUseUsageDescription"
                       . "To show the sky from where you are, when you hold the phone up to it."))
  :bundle-frameworks ("UIKit" "Foundation" "CoreGraphics" "QuartzCore" "Metal" "MetalKit"
                      "CoreLocation" "CoreMotion")
  ;; Planet maps from Solar System Scope (solarsystemscope.com/textures),
  ;; CC BY 4.0, scaled to 1024 x 512.
  :bundle-resources (("res/textures" . "textures")
                     ;; 8,826 asteroids brighter than H 13, from JPL's
                     ;; Small-Body Database: eight float32s each.
                     ("res/asteroids.bin" . "asteroids.bin")
                     ;; Required of every app: what it accesses and why.
                     ("res/PrivacyInfo.xcprivacy" . "PrivacyInfo.xcprivacy"))
  :remote-repl #.(and (uiop:getenv "SOLAR_REPL") t)

  ;; A device build is made only when it can be signed; identity, team and
  ;; profile come from the environment when this file is read, as in the
  ;; asdf-ios-app examples, so nobody's identity is committed here.
  :bundle-platforms #.(cond ((uiop:getenv "SOLAR_DISTRIBUTION") '(:device))
                            ((uiop:getenv "IOS_SIGNING_IDENTITY") '(:simulator :device))
                            (t '(:simulator)))
  :code-signing-identity #.(or (uiop:getenv "IOS_SIGNING_IDENTITY") :automatic)
  :development-team #.(uiop:getenv "IOS_DEVELOPMENT_TEAM")
  :provisioning-profile #.(uiop:getenv "IOS_PROVISIONING_PROFILE"))
