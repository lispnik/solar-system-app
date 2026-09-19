;;;; frame.lisp -- one frame, encoded; the MTKView and its delegate.

(in-package #:solar-system)

(defun draw-frame (view)
  (objc:with-autorelease-pool ()
    (ensure-metal view)
    (let* ((size (objc:invoke view "drawableSize"))
           (width (float (aref size 0) 1d0))
           (height (float (aref size 1) 1d0)))
      (when (or (zerop width) (zerop height))
        (return-from draw-frame))
      (incf *frame-count*)
      (let* ((aspect (/ width height))
             (pixels-per-point (float (objc:invoke view "contentScaleFactor") 1d0))
             (jd (sim-jd))
             (tc (centuries-since-j2000 (utc-to-tt jd)))
             (k (compression tc))
             (orbits (line-count))
             (discs 0)
             (ringed '())
             (sun-at nil))
        (unless *sky-mode*
          (ensure-orbits tc k)
          (ensure-moon-orbits tc))
        (when *sky-mode* (point-camera tc))
        (multiple-value-bind (placed systems sun)
            (if *sky-mode*
                (place-bodies-from-earth tc aspect height pixels-per-point)
                (place-bodies tc k aspect height pixels-per-point))
          (setf *last-placed* placed
                sun-at sun)
          (follow-focus placed)
          (setf ringed (fill-rings systems tc)
                discs (fill-discs placed tc ringed))
          (fill-orbit-info systems sun)
          (update-trails tc k sun)
          (update-comet-lines tc k sun)
          (update-horizon tc)
          (store-matrix *uniforms* 0 (view-matrix *camera* aspect))
          (store-matrix *uniforms* 16 (projection-matrix *camera* aspect))
          (destructuring-bind (sx sy sz) sun
            (store-floats *uniforms* 32 width height (* 1.5d0 pixels-per-point) 0 sx sy sz 1)))
        (let ((pass (objc:invoke view "currentRenderPassDescriptor")))
          (unless (nothing-p pass)
            (let* ((commands (objc:invoke *queue* "commandBuffer"))
                   (encoder (objc:invoke commands "renderCommandEncoderWithDescriptor:" pass))
                   (encoded nil))
             ;; An encoder must be ended even if a Lisp error unwinds through
             ;; here: Metal aborts the process if one is freed while open.
             (unwind-protect
              (progn
              ;; Bodies first, writing their spheres' depth; then the
              ;; rings, which Saturn hides half of; then the orbits, which
              ;; pass behind whatever is nearer.
              (objc:invoke encoder "setDepthStencilState:" *depth-writing*)
              (objc:invoke encoder "setRenderPipelineState:" *disc-pipeline*)
              (objc:invoke encoder "setVertexBuffer:offset:atIndex:" *disc-buffer* 0 0)
              (objc:invoke encoder "setVertexBytes:length:atIndex:" *uniforms* +uniform-bytes+ 1)
              (objc:invoke encoder "setFragmentBytes:length:atIndex:" *uniforms* +uniform-bytes+ 1)
              ;; Saturn's rings, for the shadow they cast on it.
              (objc:invoke encoder "setFragmentBytes:length:atIndex:"
                           (rest (first *ring-data*)) 96 2)
              (objc:invoke encoder "setFragmentTexture:atIndex:" (or *ring-map* (aref *maps* 0)) 10)
              (dotimes (i (length *maps*))
                (objc:invoke encoder "setFragmentTexture:atIndex:" (aref *maps* i) i))
              (objc:invoke encoder "drawPrimitives:vertexStart:vertexCount:instanceCount:"
                           4 0 4 discs)
              (when ringed
                (objc:invoke encoder "setRenderPipelineState:" *ring-pipeline*)
                (objc:invoke encoder "setFragmentTexture:atIndex:" (or *ring-map* (aref *maps* 0)) 0)
                (dolist (planet ringed)
                  (let ((block (rest (assoc planet *ring-data*))))
                    (objc:invoke encoder "setVertexBytes:length:atIndex:" block 96 0)
                    (objc:invoke encoder "setFragmentBytes:length:atIndex:" block 96 0)
                    (objc:invoke encoder "drawPrimitives:vertexStart:vertexCount:" 4 0 4))))
              (draw-belt encoder tc k sun-at)
              ;; Orbits: a quad (triangle strip of 4) per segment.
              (objc:invoke encoder "setDepthStencilState:" *depth-testing*)
              (objc:invoke encoder "setRenderPipelineState:" *orbit-pipeline*)
              (objc:invoke encoder "setVertexBuffer:offset:atIndex:" *orbit-buffer* 0 0)
              (objc:invoke encoder "setVertexBytes:length:atIndex:" *uniforms* +uniform-bytes+ 1)
              (objc:invoke encoder "setVertexBytes:length:atIndex:" *orbit-info* (* 48 orbits) 2)
              (objc:invoke encoder "drawPrimitives:vertexStart:vertexCount:instanceCount:"
                           4 0 4 (* orbits +segments+))
              (setf encoded t))
              (objc:invoke encoder "endEncoding"))
              (when encoded
                (objc:invoke commands "presentDrawable:" (objc:invoke view "currentDrawable"))
                (objc:invoke commands "commit")))))
        (after-frame jd)))))

;;; ------------------------------------------------------------------
;;; the delegate

;;; Not declared as conforming to MTKViewDelegate: that protocol is not in
;;; the runtime until something compiled refers to it, and MTKView never
;;; asks -- it sends the two messages to whatever its delegate is.
(objc:define-objc-class solar-renderer () ()
  (:objc-class-name "SolarRenderer"))

(defvar *frames* 0)
(defvar *frames-since* nil "Internal real time the count was last reported.")
(defvar *draw-time* 0 "Internal time units spent in DRAW-FRAME since the report.")
(defvar *draw-worst* 0)

(defun count-frame (spent)
  "Every ten seconds, say how many frames a second were drawn, and how long
the Lisp side of a frame took on average and at worst."
  (let ((now (get-internal-real-time)))
    (incf *frames*)
    (incf *draw-time* spent)
    (setf *draw-worst* (max *draw-worst* spent))
    (cond ((null *frames-since*) (setf *frames-since* now *frames* 0 *draw-time* 0 *draw-worst* 0))
          ((>= (- now *frames-since*) (* 10 internal-time-units-per-second))
           (let ((ms (/ 1000d0 internal-time-units-per-second)))
             (format t "~&SOLAR: ~,1f frames/s, drawing ~,1f ms a frame, ~,1f at worst~%"
                     (/ *frames* (/ (- now *frames-since*) internal-time-units-per-second))
                     (* ms (/ *draw-time* (max 1 *frames*))) (* ms *draw-worst*)))
           (finish-output)
           (setf *frames-since* now *frames* 0 *draw-time* 0 *draw-worst* 0)))))

(objc:define-objc-method ("drawInMTKView:" :void)
    ((self solar-renderer) (view objc:objc-object-pointer))
  ;; A Lisp error here would recur sixty times a second. Stop drawing and
  ;; say why; fix it over the REPL and (RESUME).
  (unless *failure*
    (handler-case (let ((start (get-internal-real-time)))
                    (draw-frame view)
                    (count-frame (- (get-internal-real-time) start)))
      (error (condition)
        (setf *failure* condition)
        (objc:invoke view "setPaused:" t)
        (format t "~&SOLAR: drawing stopped: ~a~%" condition)
        (finish-output)))))

(objc:define-objc-method ("mtkView:drawableSizeWillChange:" :void)
    ((self solar-renderer) (view objc:objc-object-pointer) (size cocoa:ns-size))
  (declare (ignore view))
  ;; DRAW-FRAME reads the size itself; this only says so.
  (format t "~&SOLAR: drawable now ~dx~d~%" (round (aref size 0)) (round (aref size 1)))
  (finish-output))

(defun resume ()
  "Draw again after a failure."
  (setf *failure* nil)
  (when *view*
    (objc:invoke *view* "setPaused:" nil))
  t)

(defun make-metal-view ()
  "An MTKView on the default device, its delegate a SOLAR-RENDERER."
  (setf *device* (si:call-cfun (cffi:foreign-symbol-pointer "MTLCreateSystemDefaultDevice")
                               :pointer-void '() '()))
  (when (nothing-p *device*)
    (error "No Metal device."))
  (let ((view (objc:invoke (objc:invoke "MTKView" "alloc") "initWithFrame:device:"
                           #(0d0 0d0 100d0 100d0) *device*)))
    (objc:invoke view "setTranslatesAutoresizingMaskIntoConstraints:" nil)
    (objc:invoke view "setSampleCount:" 4)
    (objc:invoke view "setDepthStencilPixelFormat:" +depth-format+)
    (objc:invoke view "setPreferredFramesPerSecond:" 60)
    (objc:invoke view "setDelegate:" (ui:keep (make-instance 'solar-renderer)))
    (setf *view* view)))
