;;;; metal.lisp -- Metal set up, once: the device, the pipelines, the maps.

(in-package #:solar-system)


(defconstant +depth-format+ 252 "MTLPixelFormatDepth32Float.")

(defun depth-state (compare write)
  (let ((descriptor (objc:alloc-init-object "MTLDepthStencilDescriptor")))
    (objc:invoke descriptor "setDepthCompareFunction:" compare)
    (objc:invoke descriptor "setDepthWriteEnabled:" write)
    (objc:invoke *device* "newDepthStencilStateWithDescriptor:" descriptor)))

(defun metalkit-constant (name)
  "The NSString a MetalKit constant like MTKTextureLoaderOptionSRGB names."
  (cffi:mem-ref (cffi:foreign-symbol-pointer name) :pointer))

(defun load-map (loader name extension)
  "A texture from the bundle's textures/, mipmapped, its bytes taken as they
are; NIL, and a word on the console, if it will not load."
  (let ((url (objc:invoke (objc:invoke "NSBundle" "mainBundle")
                          "URLForResource:withExtension:subdirectory:" name extension "textures"))
        (options (objc:invoke "NSMutableDictionary" "dictionary")))
    (flet ((option (key value)
             (objc:invoke options "setObject:forKey:"
                          (objc:invoke "NSNumber" "numberWithBool:" value) (metalkit-constant key))))
      (option "MTKTextureLoaderOptionSRGB" nil)
      (option "MTKTextureLoaderOptionAllocateMipmaps" t)
      (option "MTKTextureLoaderOptionGenerateMipmaps" t))
    (if (nothing-p url)
        (progn (format t "~&SOLAR: no map ~a.~a in the bundle~%" name extension) nil)
        (handler-case (objc:invoke-with-error loader "newTextureWithContentsOfURL:options:error:" url options)
          (error (condition)
            (format t "~&SOLAR: map ~a would not load: ~a~%" name condition)
            nil)))))

(defun load-maps ()
  (let ((loader (objc:invoke (objc:invoke "MTKTextureLoader" "alloc") "initWithDevice:" *device*)))
    (loop for (nil . file) in +maps+
          for i from 0
          do (setf (aref *maps* i) (load-map loader file "jpg")))
    (setf *ring-map* (load-map loader "saturn-ring" "png"))
    ;; Every slot bound to something, the missing ones to any map there is.
    (let ((any (find-if-not #'null *maps*)))
      (dotimes (i (length *maps*))
        (unless (aref *maps* i) (setf (aref *maps* i) any))))
    (format t "~&SOLAR: ~d maps~@[ and the ring~]~%" (count-if-not #'null *maps*) *ring-map*)))

(defun texture-index (body)
  (let ((index (position (body-name body) +maps+ :key #'car :test #'string=)))
    (if (and index (aref *maps* index)) index -1)))

(defun make-pipeline (library vertex fragment pixel-format sample-count)
  "A render pipeline from two functions in LIBRARY, blending premultiplied
alpha into PIXEL-FORMAT."
  (let ((descriptor (objc:alloc-init-object "MTLRenderPipelineDescriptor")))
    (objc:invoke descriptor "setVertexFunction:" (objc:invoke library "newFunctionWithName:" vertex))
    (objc:invoke descriptor "setFragmentFunction:" (objc:invoke library "newFunctionWithName:" fragment))
    (objc:invoke descriptor "setRasterSampleCount:" sample-count)
    (objc:invoke descriptor "setDepthAttachmentPixelFormat:" +depth-format+)
    (let ((attachment (objc:invoke (objc:invoke descriptor "colorAttachments")
                                   "objectAtIndexedSubscript:" 0)))
      (objc:invoke attachment "setPixelFormat:" pixel-format)
      (objc:invoke attachment "setBlendingEnabled:" t)
      ;; MTLBlendFactorOne and MTLBlendFactorOneMinusSourceAlpha.
      (objc:invoke attachment "setSourceRGBBlendFactor:" 1)
      (objc:invoke attachment "setSourceAlphaBlendFactor:" 1)
      (objc:invoke attachment "setDestinationRGBBlendFactor:" 5)
      (objc:invoke attachment "setDestinationAlphaBlendFactor:" 5))
    (objc:invoke-with-error *device* "newRenderPipelineStateWithDescriptor:error:" descriptor)))

(defun ensure-metal (view)
  "The device, the compiled shaders, both pipelines and the buffers: once."
  (unless *disc-pipeline*
    (let* ((library (objc:invoke-with-error *device* "newLibraryWithSource:options:error:"
                                            (format nil +shaders+ +segments+) nil))
           (pixel-format (objc:invoke view "colorPixelFormat"))
           (samples (objc:invoke view "sampleCount"))
           (orbits (line-count)))
      (setf *queue* (objc:invoke *device* "newCommandQueue")
            *orbit-pipeline* (make-pipeline library "orbit_vertex" "orbit_fragment" pixel-format samples)
            *disc-pipeline* (make-pipeline library "disc_vertex" "disc_fragment" pixel-format samples)
            *ring-pipeline* (make-pipeline library "ring_vertex" "ring_fragment" pixel-format samples)
            *belt-pipeline* (make-pipeline library "belt_vertex" "belt_fragment" pixel-format samples)
            *belt-data* (cffi:foreign-alloc :float :count 16)
            *depth-writing* (depth-state 3 t)     ; less or equal
            *depth-testing* (depth-state 3 nil)
            *ring-data* (loop for (name) in +rings+
                              collect (cons (find-planet name) (cffi:foreign-alloc :float :count 24)))
            *orbit-buffer* (objc:invoke *device* "newBufferWithLength:options:"
                                        (* 16 orbits (1+ +segments+)) 0)
            *uniforms* (cffi:foreign-alloc :float :count (/ +uniform-bytes+ 4))
            *disc-buffers* (coerce (loop repeat 3
                                         collect (objc:invoke *device* "newBufferWithLength:options:"
                                                              (* 4 +disc-floats+ +max-discs+) 0))
                                   'simple-vector)
            *orbit-info* (cffi:foreign-alloc :float :count (* 12 orbits)))
      ;; Every line starts clear, so a slot nothing has filled draws nothing.
      (dotimes (i (* 12 orbits)) (setf (cffi:mem-aref *orbit-info* :float i) 0.0))
      (load-maps)
      (load-belt)
      (when *sky-mode* (store-sky-circles))
      (format t "SOLAR: Metal ready on ~a, ~dx MSAA; ~d orbits~%"
              (objc:ns-string-to-string (objc:invoke *device* "name")) samples orbits)
      (finish-output))))
