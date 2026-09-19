;;;; belt.lisp -- the asteroid belt: its elements loaded, and drawn by the GPU.

(in-package #:solar-system)

(defun load-belt ()
  "The asteroids' elements, straight from the bundle into a buffer."
  (let ((url (objc:invoke (objc:invoke "NSBundle" "mainBundle")
                          "URLForResource:withExtension:" "asteroids" "bin")))
    (unless (nothing-p url)
      (let* ((data (objc:invoke "NSData" "dataWithContentsOfURL:" url))
             (length (objc:invoke data "length")))
        (setf *belt-buffer* (objc:invoke *device* "newBufferWithBytes:length:options:"
                                         (objc:invoke data "bytes") length 0)
              *belt-count* (floor length 32)))))
  (format t "~&SOLAR: ~d asteroids~%" *belt-count*))

(defun draw-belt (encoder tc k sun)
  "The asteroids, a point each, placed by the GPU."
  (when (and *small-bodies-on* *belt-buffer* (plusp *belt-count*))
    (destructuring-bind (sx sy sz) sun
      (multiple-value-bind (ex ey ez) (if *sky-mode* (earth-position tc) (values 0d0 0d0 0d0))
        (let ((scale (float (objc:invoke *view* "contentScaleFactor") 1d0)))
          (store-floats *belt-data* 0
                        (* tc 36525d0) k *radius-exponent* (if *sky-mode* 1 0)
                        sx sy sz (* scale (if *sky-mode* 0.8d0 1.1d0))
                        ex ey ez 1
                        0.78 0.70 0.58 (if *sky-mode* 0.35 0.55)))))
    (objc:invoke encoder "setDepthStencilState:" *depth-testing*)
    (objc:invoke encoder "setRenderPipelineState:" *belt-pipeline*)
    (objc:invoke encoder "setVertexBuffer:offset:atIndex:" *belt-buffer* 0 0)
    (objc:invoke encoder "setVertexBytes:length:atIndex:" *uniforms* +uniform-bytes+ 1)
    (objc:invoke encoder "setVertexBytes:length:atIndex:" *belt-data* 64 2)
    (objc:invoke encoder "drawPrimitives:vertexStart:vertexCount:" 0 0 *belt-count*)))
