;;;; about.lisp -- where all this comes from.
;;;;
;;;; Tap the clock and the credits appear: whose numbers the app is drawing,
;;;; and whose pictures. The planet maps are Solar System Scope's under CC BY
;;;; 4.0, which asks for attribution wherever the work is used -- a line in a
;;;; README would not do, since nobody installing the app reads one.

(in-package #:solar-system)

(defvar *about* nil)

(defparameter +credits+
  "Solar System 1.0

Where the bodies are
  Planets: E. M. Standish's Keplerian elements (JPL).
  Dwarf planets, moons, comets: fitted to JPL Horizons.
  Asteroids: JPL's Small-Body Database, 8,825 of them.
  The Moon: Meeus, ELP-2000.
  Which way they face: the IAU's rotational elements.

Pictures
  Planet and moon maps, and Saturn's rings:
  Solar System Scope, solarsystemscope.com/textures,
  CC BY 4.0.

Built with ECL, objc and asdf-ios-app.
Nothing is collected; nothing leaves the phone.

Tap to close.")

(defun make-about (root)
  "The credits, hidden, and the tap on the clock that shows them."
  (let ((panel (objc:invoke (objc:invoke "UIVisualEffectView" "alloc") "initWithEffect:"
                            (objc:invoke "UIBlurEffect" "effectWithStyle:" 2)))
        (label (ui:new "UILabel")))
    (objc:invoke panel "setTranslatesAutoresizingMaskIntoConstraints:" nil)
    (objc:invoke (objc:invoke panel "layer") "setCornerRadius:" 14d0)
    (objc:invoke panel "setClipsToBounds:" t)
    (objc:invoke panel "setHidden:" t)
    (objc:invoke label "setFont:" (ui:mono-font 11))
    (objc:invoke label "setTextColor:" (ui:color 0.88 0.90 0.95))
    (objc:invoke label "setNumberOfLines:" 0)
    (objc:invoke label "setText:" +credits+)
    (objc:invoke (objc:invoke panel "contentView") "addSubview:" label)
    (let ((content (objc:invoke panel "contentView")))
      (ui:pin label "topAnchor" content "topAnchor" 14)
      (ui:pin label "bottomAnchor" content "bottomAnchor" -14)
      (ui:pin label "leadingAnchor" content "leadingAnchor" 16)
      (ui:pin label "trailingAnchor" content "trailingAnchor" -16))
    (objc:invoke root "addSubview:" panel)
    (ui:pin panel "centerXAnchor" root "centerXAnchor")
    (ui:pin panel "centerYAnchor" root "centerYAnchor")
    (setf *about* panel)
    ;; The clock opens it; a tap on it closes it.
    (objc:invoke *clock-label* "setUserInteractionEnabled:" t)
    (objc:invoke *clock-label* "addGestureRecognizer:"
                 (objc:invoke (objc:invoke "UITapGestureRecognizer" "alloc") "initWithTarget:action:"
                              (ui:action-target (lambda (sender) (declare (ignore sender)) (show-about t)))
                              "fire:"))
    (objc:invoke panel "addGestureRecognizer:"
                 (objc:invoke (objc:invoke "UITapGestureRecognizer" "alloc") "initWithTarget:action:"
                              (ui:action-target (lambda (sender) (declare (ignore sender)) (show-about nil)))
                              "fire:"))
    panel))

(defun show-about (shown)
  (when *about*
    (objc:invoke *about* "setHidden:" (not shown))))
