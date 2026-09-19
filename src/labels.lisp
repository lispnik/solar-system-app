;;;; labels.lisp -- each body's name beside it.
;;;;
;;;; UIKit labels over the Metal view, one a body, moved every frame to
;;;; where the body was drawn: to the right of its disc, centred on it
;;;; vertically. A label shows only while its body does -- a moon's with its
;;;; moon system, as that fades in -- and while it is on the screen, and
;;;; while it would not cover a label that matters more: the Sun's first,
;;;; then the planets', the dwarf planets', the moons'. The container passes
;;;; touches through, so the labels never stand in the way of a gesture.

(in-package #:solar-system)

(defvar *labels-on* t)
(defvar *label-container* nil)
(defvar *labels* (make-hash-table :test 'eq)
  "Body -> (label half-width shown), SHOWN what the label was last told.")

(defun label-colour (body)
  "The body's colour, lifted towards white so that it reads on black."
  (let ((c (body-colour body)))
    (flet ((lift (x) (+ 0.45 (* 0.55 x))))
      (ui:color (lift (aref c 0)) (lift (aref c 1)) (lift (aref c 2)) 0.9))))

(defun make-labels (root)
  "A label for every body, in a container over the whole of ROOT."
  (let ((container (ui:new "UIView")))
    (objc:invoke container "setUserInteractionEnabled:" nil)
    (objc:invoke root "addSubview:" container)
    (dolist (edge '("topAnchor" "bottomAnchor" "leadingAnchor" "trailingAnchor"))
      (ui:pin container edge root edge))
    (dolist (body (append (list +sun+) (heliocentric-bodies) *moons*))
      (let ((label (objc:alloc-init-object "UILabel")))
        (objc:invoke label "setText:" (body-name body))
        (objc:invoke label "setFont:"
                     (ui:font (if (or (body-parent body) (member body *dwarfs*)) 10 11) 0.3))
        (objc:invoke label "setTextColor:" (label-colour body))
        (objc:invoke label "sizeToFit")
        (objc:invoke label "setHidden:" t)
        (objc:invoke container "addSubview:" label)
        (setf (gethash body *labels*)
              (list label (* 0.5d0 (float (aref (objc:invoke label "bounds") 2) 1d0)) nil))))
    (setf *label-container* container)))

(defun show-label (entry shown)
  "Hide or show a label, telling UIKit only when that changes."
  (unless (eq shown (third entry))
    (objc:invoke (first entry) "setHidden:" (not shown))
    (setf (third entry) shown)))

(defun label-rank (body)
  (cond ((eq body +sun+) 0) ((member body *planets*) 1) ((body-parent body) 3) (t 2)))

(defun update-labels ()
  "Put each visible body's label beside it, most important first, skipping
any that would overlap one already placed; hide the rest."
  (when *label-container*
    (if (not *labels-on*)
        (maphash (lambda (body entry) (declare (ignore body)) (show-label entry nil)) *labels*)
        (multiple-value-bind (width height scale aspect projection) (screen-metrics *view*)
          (let ((right (/ width scale)) (bottom (/ height scale))
                (taken '()))
            (dolist (placed (sort (copy-list *last-placed*) #'< :key (lambda (p) (label-rank (second p)))))
              (destructuring-bind (depth body x y z radius alpha) placed
                (declare (ignore depth))
                (let ((entry (gethash body *labels*)))
                  (when entry
                    (multiple-value-bind (sx sy)
                        (and (> alpha 0.5d0)
                             (to-points x y z width height scale aspect projection))
                      (let* ((left (and sx (+ sx (/ radius scale) 3d0)))
                             (box (and sx (list left (- sy 7d0) (+ left (* 2 (second entry))) (+ sy 7d0))))
                             (shown (and sx (< -40 sx right) (< -10 sy bottom)
                                         (notany (lambda (other)
                                                   (and (< (first box) (third other)) (< (first other) (third box))
                                                        (< (second box) (fourth other)) (< (second other) (fourth box))))
                                                 taken))))
                        (when shown
                          (push box taken)
                          (objc:invoke (first entry) "setCenter:"
                                       (vector (+ left (second entry)) sy)))
                        (show-label entry shown))))))))))))

(defun toggle-labels ()
  (setf *labels-on* (not *labels-on*))
  (set-button-image *labels-button* (if *labels-on* "tag.fill" "tag"))
  (update-labels))
