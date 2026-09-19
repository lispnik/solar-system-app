;;;; card.lisp -- what the followed body is like, under the clock.
;;;;
;;;; Tap a body and a small card shows the numbers behind it, kept current
;;;; four times a second: how far from the Sun and from the Earth and how
;;;; long its light takes to reach us, how fast it is going, how big it is;
;;;; from the Earth, how much of it is lit, how far from the Sun it stands
;;;; in the sky and how large it looks; from where you stand, where in your
;;;; sky it is; and the next event it takes part in.

(in-package #:solar-system)

(defvar *card* nil)
(defvar *card-label* nil)

(defun make-card (root)
  "The card: a dark blur under the clock, hidden until something is followed."
  (let ((card (objc:invoke (objc:invoke "UIVisualEffectView" "alloc") "initWithEffect:"
                           (objc:invoke "UIBlurEffect" "effectWithStyle:" 2)))
        (label (ui:new "UILabel")))
    (objc:invoke card "setTranslatesAutoresizingMaskIntoConstraints:" nil)
    (objc:invoke (objc:invoke card "layer") "setCornerRadius:" 12d0)
    (objc:invoke card "setClipsToBounds:" t)
    (objc:invoke card "setUserInteractionEnabled:" nil)
    (objc:invoke card "setHidden:" t)
    (objc:invoke label "setFont:" (ui:mono-font 11))
    (objc:invoke label "setTextColor:" (ui:color 0.86 0.88 0.93))
    (objc:invoke label "setNumberOfLines:" 0)
    (objc:invoke (objc:invoke card "contentView") "addSubview:" label)
    (let ((content (objc:invoke card "contentView")))
      (ui:pin label "topAnchor" content "topAnchor" 8)
      (ui:pin label "bottomAnchor" content "bottomAnchor" -8)
      (ui:pin label "leadingAnchor" content "leadingAnchor" 10)
      (ui:pin label "trailingAnchor" content "trailingAnchor" -10))
    (objc:invoke root "addSubview:" card)
    (ui:pin card "topAnchor" *clock-label* "bottomAnchor" 8)
    (ui:pin card "leadingAnchor" *clock-label* "leadingAnchor" -4)
    (setf *card* card *card-label* label)))

(defun light-time (seconds)
  (cond ((< seconds 60) (format nil "~,1f light-s" seconds))
        ((< seconds 3600) (format nil "~,1f light-min" (/ seconds 60)))
        (t (format nil "~,1f light-h" (/ seconds 3600)))))

(defun grouped (n)
  "N with thousands separated: 384,400."
  (format nil "~:d" (round n)))

(defun angular-size (arcseconds)
  (cond ((< arcseconds 60) (format nil "~,1f″" arcseconds))
        ((< arcseconds 3600) (format nil "~,1f′" (/ arcseconds 60)))
        (t (format nil "~,2f°" (/ arcseconds 3600)))))

(defun compass-point (azimuth)
  (nth (mod (round azimuth 22.5d0) 16)
       '("N" "NNE" "NE" "ENE" "E" "ESE" "SE" "SSE" "S" "SSW" "SW" "WSW" "W" "WNW" "NW" "NNW")))

(defun next-event-of (body)
  "The next event BODY takes part in, among those found: named in the
title, or for the Sun and the Moon, their eclipses."
  (let* ((name (body-name body))
         (now (utc-to-tt (sim-jd))))
    (find-if (lambda (event)
               (and (> (event-jd event) now)
                    (cond ((eq body +sun+) (eq (event-kind event) :solar-eclipse))
                          ((string= name "Moon")
                           (member (event-kind event) '(:solar-eclipse :lunar-eclipse)))
                          (t (search name (event-title event))))))
             *events*)))

(defun card-text (body)
  (let* ((tc (centuries-since-j2000 (utc-to-tt (sim-jd))))
         (facts (body-facts body tc))
         (lines '()))
    (flet ((line (label format &rest arguments)
             (push (format nil "~13a ~?" label format arguments) lines)))
      (push (format nil "~a — ~a" (body-name body) (getf facts :kind)) lines)
      (cond ((and (getf facts :parent-distance) (not (string= (body-name body) "Moon")))
             (line (format nil "from ~a" (body-name (body-parent body))) "~a km"
                   (grouped (getf facts :parent-distance))))
            ((getf facts :sun)
             (line "from the Sun" "~,3f AU" (getf facts :sun))))
      (when (getf facts :earth)
        (line "from Earth" "~a (~a)"
              (if (< (getf facts :earth) 0.01d0)
                  (format nil "~a km" (grouped (* (getf facts :earth) +km-per-au+)))
                  (format nil "~,3f AU" (getf facts :earth)))
              (light-time (getf facts :light))))
      (when (getf facts :speed)
        (line "speed" "~,2f km/s" (getf facts :speed)))
      (unless (body-comet body)
        (line "radius" "~a km" (grouped (getf facts :radius))))
      (when (and *sky-mode* (getf facts :phase))
        (line "lit" "~d% · ~d° from Sun" (round (* 100 (getf facts :phase)))
              (round (getf facts :elongation))))
      ;; A comet's nucleus is a few km: no size worth giving.
      (when (and *sky-mode* (getf facts :size) (not (body-comet body)))
        (line "looks" "~a across" (angular-size (getf facts :size))))
      (when (and *sky-mode* *observer*)
        (multiple-value-bind (x y z) (centre-of body tc)
          (multiple-value-bind (ex ey ez) (earth-position tc)
            (multiple-value-bind (ox oy oz) (observer-position (car *observer*) (cdr *observer*) tc)
              (multiple-value-bind (altitude azimuth)
                  (altitude-azimuth (car *observer*) (cdr *observer*) tc
                                    (- x ex ox) (- y ey oy) (- z ez oz))
                (line "in your sky" "~,1f° ~:[up~;below~], ~d° ~a"
                      (abs altitude) (minusp altitude) (round azimuth) (compass-point azimuth)))))))
      (let ((event (next-event-of body)))
        (when event
          (line "next" "~a ~a" (event-title event) (subseq (event-date event) 0 10)))))
    (format nil "~{~a~^~%~}" (reverse lines))))

(defun update-card ()
  "Four times a second: the followed body's card, or none."
  (when *card*
    (let ((body *focus*)
          (shown (and *focus* (not (objc:invoke-bool *panel* "isHidden")))))
      (objc:invoke *card* "setHidden:" (not shown))
      (when shown
        (objc:invoke *card-label* "setText:" (card-text body))))))
