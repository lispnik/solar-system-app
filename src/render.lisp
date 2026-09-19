;;;; render.lisp -- Metal, from Lisp: the Sun, the planets, the dwarf planets
;;;; and the major moons, and their orbits.
;;;;
;;;; An MTKView whose delegate is a Lisp class. Every frame, drawInMTKView:
;;;; asks the clock what time it is, places thirty-four bodies, compresses
;;;; them into the scene, and encodes two instanced draws: the orbits as
;;;; thick antialiased lines, a quad per segment, each orbit relative to a
;;;; centre -- the Sun, or a moon's planet; then a disc per body, lit from
;;;; the Sun, farthest first. The shaders are a string compiled at run time,
;;;; as in the compute example.
;;;;
;;;; The orbits and bodies are in scene coordinates (projection.lisp); the
;;;; camera (camera.lisp) arrives as a view and a projection matrix, so a
;;;; gesture changes two matrices and nothing on the GPU is rebuilt. Lines
;;;; and discs are sized in pixels after projection, so they stay crisp at
;;;; any zoom. Each disc is a sphere to the depth buffer and, where there
;;;; is a map, to the eye: the view direction is turned into the body's own
;;;; axes (rotation.lisp) to find the longitude and latitude it sees, so
;;;; each planet shows the face it has turned to the camera at that moment.
;;;; Rings are a flat annulus in the planet's equator: Saturn's from its
;;;; map, with its own shadow across them and theirs across it; Uranus's
;;;; drawn line by line at their radii.

(in-package #:solar-system)

(defparameter +segments+ 256 "Line segments per orbit.")

(defparameter +shaders+ "
#include <metal_stdlib>
using namespace metal;

#define SEGMENTS ~d

struct Uniforms { float4x4 view; float4x4 proj; float2 viewport; float line_width; float pad; float4 sun; };

// position.w: radius in pixels; extra: glow, texture index (-1 none),
// 1 if Saturn's rings are being drawn and shadow it;
// ax ay az: the body's axes -- prime meridian, 90 east, north -- in view space.
struct Disc { float4 position; float4 colour; float4 extra; float4 ax; float4 ay; float4 az; };

struct DiscVarying {
  float4 position [[position]];
  float2 local;
  float radius;
  float glow;
  float4 colour;
  float3 light;
  float eye_z;
  float world_radius;
  float texture_index [[flat]];
  float ring_shadow [[flat]];
  float3 ax [[flat]];
  float3 ay [[flat]];
  float3 az [[flat]];
};

struct DiscOut { float4 colour [[color(0)]]; float depth [[depth(any)]]; };



// Behind the camera: a point off screen, so the quad has no area.
constant float4 nowhere = float4(2.0, 2.0, 0.5, 1.0);

constexpr sampler map_sampler(filter::linear, mip_filter::linear, address::repeat);

// A planet's rings: a square in its equatorial plane, cut to the annulus.
// radii: inner, outer, the planet's radius (scene units), opacity.
// mapping: the moon system's scene radius and its outermost moon's km, and
// the rings' inner and outer km -- to undo the square-root scale moons are
// drawn at, so that each gap falls where it is. style.x: 0 Saturn's map,
// 1 Uranus's narrow rings, drawn from their radii.
struct Ring { float4 centre; float4 ax; float4 ay; float4 radii; float4 mapping; float4 style; };

// Scene distance from the planet's centre to where a ring at KM is drawn.
float ring_radius(constant Ring &r, float km) { return r.mapping.x * sqrt(km / r.mapping.y); }

// How much of the Sun a ring at scene radius RHO lets through: 1 - its opacity.
float ring_opacity(constant Ring &r, float rho, texture2d<float> map)
{
  float km = r.mapping.y * (rho / r.mapping.x) * (rho / r.mapping.x);
  float t = (km - r.mapping.z) / (r.mapping.w - r.mapping.z);
  if (t < 0.0 || t > 1.0) return 0.0;
  // An explicit level: this is called in a branch, where the derivatives
  // an implicit one would use are undefined.
  return map.sample(map_sampler, float2(t, 0.5), level(0.0)).a;
}

vertex DiscVarying disc_vertex(uint vid [[vertex_id]], uint iid [[instance_id]],
                               constant Disc *discs [[buffer(0)]],
                               constant Uniforms &u [[buffer(1)]])
{
  Disc d = discs[iid];
  DiscVarying out;
  out.radius = d.position.w;
  out.glow = d.extra.x;
  out.texture_index = d.extra.y;
  out.ring_shadow = d.extra.z;
  out.colour = d.colour;
  out.ax = d.ax.xyz; out.ay = d.ay.xyz; out.az = d.az.xyz;
  float4 eye = u.view * float4(d.position.xyz, 1.0);
  float4 clip = u.proj * eye;
  out.eye_z = eye.z;
  // Pixels to scene units at this depth, for the sphere's depth below.
  out.world_radius = out.radius * (-eye.z) / (u.proj[1][1] * 0.5 * u.viewport.y);
  float extent = out.radius * (1.0 + 5.0 * out.glow) + 1.5;
  float2 corner = float2((vid & 1) ? 1.0 : -1.0, (vid & 2) ? 1.0 : -1.0);
  out.local = corner * extent;
  float3 toward = (u.view * float4(u.sun.xyz, 1.0)).xyz - eye.xyz;
  out.light = length(toward) > 0.0 ? normalize(toward) : float3(0.0);
  if (clip.w <= 0.0 || d.colour.a <= 0.0) {
    out.position = nowhere;
    return out;
  }
  // A billboard: offset in pixels after projection. Its depth is the
  // sphere's, written by the fragment.
  float2 offset = out.local / (0.5 * u.viewport);
  out.position = float4(clip.xy + offset * clip.w, 0.5 * clip.w, clip.w);
  return out;
}

// A sphere seen from the camera: textured where there is a map, turned by
// the body's axes; lit from wherever the Sun is -- from above half lit,
// from behind a crescent; its depth the depth of its surface, so that
// orbits and rings pass behind it. Premultiplied alpha out, so a glow can
// add light with an alpha of zero.
fragment DiscOut disc_fragment(DiscVarying in [[stage_in]],
                               constant Uniforms &u [[buffer(1)]],
                               constant Ring &saturn [[buffer(2)]],
                               array<texture2d<float>, 10> maps [[texture(0)]],
                               texture2d<float> ring_map [[texture(10)]])
{
  float d = length(in.local);
  float cover = 1.0 - smoothstep(in.radius - 0.75, in.radius + 0.75, d);
  float2 n2 = in.local / in.radius;
  float nz = sqrt(saturate(1.0 - dot(n2, n2)));
  float3 n = float3(n2, nz);
  float3 rgb = in.colour.rgb;
  int index = int(in.texture_index);
  if (index >= 0 && cover > 0.0) {
    float3 b = float3(dot(n, in.ax), dot(n, in.ay), dot(n, in.az));
    float2 uv = float2(0.5 + atan2(b.y, b.x) / (2.0 * M_PI_F), 0.5 - asin(clamp(b.z, -1.0, 1.0)) / M_PI_F);
    // The level of detail from the disc's size, not from derivatives,
    // which jump at the seam where longitude wraps.
    float lod = max(0.0, log2(1024.0 / max(1.0, M_PI_F * in.radius)));
    rgb = maps[index].sample(map_sampler, uv, level(lod)).rgb;
  }
  // Saturn under its rings: follow the sunlight back from this point on
  // the sphere to where it crossed the ring plane -- the equator, z = 0 in
  // the planet's own axes -- and dim by the rings' opacity there, averaged
  // over the stretch of ring this pixel covers. Near Saturn's equinoxes the
  // Sun is almost in the ring plane and that stretch is long: sampled once,
  // the edges of the shadow would be stairs. (The flag is the same over the
  // whole disc, so the derivatives here are sound.)
  float shadow = 0.0;
  if (in.ring_shadow > 0.5) {
    float3 b = float3(dot(n, in.ax), dot(n, in.ay), dot(n, in.az)) * saturn.radii.z;
    float3 s = float3(dot(in.light, in.ax), dot(in.light, in.ay), dot(in.light, in.az));
    float t = abs(s.z) > 1e-4 ? -b.z / s.z : -1.0;
    float rho = length(b.xy + max(t, 0.0) * s.xy);
    float width = fwidth(rho);
    float opacity = 0.0;
    for (int k = 0; k < 4; k++) {
      opacity += ring_opacity(saturn, rho + (float(k) - 1.5) * 0.25 * width, ring_map);
    }
    shadow = t > 0.0 ? 0.9 * opacity / 4.0 : 0.0;
  }
  if (in.glow == 0.0) {
    rgb *= 0.05 + 0.95 * saturate(dot(n, in.light)) * (1.0 - shadow);
  }
  DiscOut out;
  out.colour = float4(rgb * cover, cover);
  if (in.glow > 0.0) {
    float halo = in.glow * exp(-2.5 * max(d - in.radius, 0.0) / in.radius) * (1.0 - cover);
    out.colour.rgb += in.colour.rgb * halo;
  }
  out.colour *= in.colour.a;
  if (cover < 0.5) {
    out.depth = 1.0;
  } else {
    float z = in.eye_z + in.world_radius * nz;
    out.depth = (u.proj[2][2] * z + u.proj[3][2]) / (-z);
  }
  return out;
}


struct RingVarying { float4 position [[position]]; float2 plane; float3 world; };

vertex RingVarying ring_vertex(uint vid [[vertex_id]],
                               constant Ring &r [[buffer(0)]],
                               constant Uniforms &u [[buffer(1)]])
{
  float2 corner = float2((vid & 1) ? 1.0 : -1.0, (vid & 2) ? 1.0 : -1.0) * r.radii.y;
  float3 world = r.centre.xyz + corner.x * r.ax.xyz + corner.y * r.ay.xyz;
  RingVarying out;
  out.position = u.proj * (u.view * float4(world, 1.0));
  out.plane = corner;
  out.world = world;
  return out;
}

// Uranus's ten main rings, inside out: 6, 5, 4, alpha, beta, eta, gamma,
// delta, lambda, epsilon; km from the planet's centre (Voyager 2). All are
// narrow -- epsilon, the widest, is under a hundred km -- and very dark.
constant float uranus_rings[10] = { 41837.0, 42234.0, 42571.0, 44718.0, 45661.0,
                                    47176.0, 47627.0, 48300.0, 50024.0, 51149.0 };

fragment float4 ring_fragment(RingVarying in [[stage_in]],
                              constant Ring &r [[buffer(0)]],
                              constant Uniforms &u [[buffer(1)]],
                              texture2d<float> map [[texture(0)]])
{
  float rho = length(in.plane);
  if (rho < r.radii.x || rho > r.radii.y) discard_fragment();
  float4 c;
  if (r.style.x > 0.5) {
    // Each ring a line at its radius, a pixel or so wide however far away:
    // their true widths would vanish.
    float pixel = max(fwidth(rho), 1e-7);
    float cover = 0.0;
    for (int i = 0; i < 10; i++) {
      float line = 1.0 - smoothstep(0.4, 1.4, abs(rho - ring_radius(r, uranus_rings[i])) / pixel);
      cover = max(cover, line * (i == 9 ? 0.9 : 0.55));
    }
    if (cover < 0.01) discard_fragment();
    c = float4(0.62, 0.64, 0.68, cover);
  } else {
    float km = r.mapping.y * pow(rho / r.mapping.x, 2.0);
    float t = (km - r.mapping.z) / (r.mapping.w - r.mapping.z);
    if (t < 0.0 || t > 1.0) discard_fragment();
    c = map.sample(map_sampler, float2(t, 0.5));
  }
  // In the planet's shadow if the way to the Sun passes through it.
  float3 to_sun = normalize(u.sun.xyz - in.world);
  float3 from_centre = in.world - r.centre.xyz;
  float b = dot(from_centre, to_sun);
  float shade = (b < 0.0 && b * b - dot(from_centre, from_centre) + r.radii.z * r.radii.z > 0.0) ? 0.12 : 1.0;
  float a = c.a * r.radii.w;
  if (a < 0.02) discard_fragment();
  return float4(c.rgb * shade * a, a);
}

// centre: what the points are relative to. style: x 1 to fade along the
// line, oldest point clear, for a trail; y a width multiplier (0 for 1).
struct OrbitInfo { float4 colour; float4 centre; float4 style; };

struct OrbitVarying {
  float4 position [[position]];
  float4 colour;
  float across;
  float half_width;
};

// One instance per segment: a quad from point k to point k+1, projected,
// then widened across its on-screen direction by half the line width and a
// pixel for the ramp.
vertex OrbitVarying orbit_vertex(uint vid [[vertex_id]], uint iid [[instance_id]],
                                 device const float4 *points [[buffer(0)]],
                                 constant Uniforms &u [[buffer(1)]],
                                 constant OrbitInfo *orbits [[buffer(2)]])
{
  uint orbit = iid / SEGMENTS;
  uint k = iid % SEGMENTS;
  float3 centre = orbits[orbit].centre.xyz;
  float4 c0 = u.proj * (u.view * float4(centre + points[orbit * (SEGMENTS + 1) + k].xyz, 1.0));
  float4 c1 = u.proj * (u.view * float4(centre + points[orbit * (SEGMENTS + 1) + k + 1].xyz, 1.0));
  OrbitVarying out;
  float4 style = orbits[orbit].style;
  out.colour = orbits[orbit].colour;
  if (style.x > 0.0) out.colour.a *= float(k + ((vid & 2) ? 1 : 0)) / float(SEGMENTS);
  out.half_width = 0.5 * u.line_width * (style.y > 0.0 ? style.y : 1.0);
  out.across = 0.0;
  if (c0.w <= 0.0 || c1.w <= 0.0 || orbits[orbit].colour.a <= 0.0) {
    out.position = nowhere;
    return out;
  }
  float2 half_viewport = 0.5 * u.viewport;
  float2 s0 = c0.xy / c0.w * half_viewport;
  float2 s1 = c1.xy / c1.w * half_viewport;
  float2 along = s1 - s0;
  float2 dir = length(along) > 0.0 ? normalize(along) : float2(1.0, 0.0);
  float2 normal = float2(-dir.y, dir.x);
  float side = ((vid & 1) ? 1.0 : -1.0) * (out.half_width + 1.0);
  float4 c = (vid & 2) ? c1 : c0;
  float2 p = ((vid & 2) ? s1 : s0) + normal * side;
  out.position = float4(p / half_viewport * c.w, c.z, c.w);
  out.across = side;
  return out;
}

fragment float4 orbit_fragment(OrbitVarying in [[stage_in]])
{
  float a = in.colour.a * (1.0 - smoothstep(in.half_width - 0.5, in.half_width + 0.5, abs(in.across)));
  return float4(in.colour.rgb * a, a);
}
")

;;; ------------------------------------------------------------------
;;; state

(defvar *device* nil)
(defvar *queue* nil)
(defvar *orbit-pipeline* nil)
(defvar *disc-pipeline* nil)
(defvar *view* nil "The MTKView.")

;;; The lines drawn, each +SEGMENTS+ long, in slots of the one buffer: the
;;; Sun's family's orbits, the moons' (relative to their planets), a trail
;;; for each of the Sun's family, and spare slots for what comes after.
(defparameter +spare-lines+ 16)

(defun orbiters () (append (heliocentric-bodies) *moons*))
(defun line-count () (+ (length (orbiters)) (length (heliocentric-bodies)) +spare-lines+))
(defun trail-slot (index) (+ (length (orbiters)) index))
(defun spare-slot (index) (+ (length (orbiters)) (length (heliocentric-bodies)) index))

(defvar *orbit-buffer* nil
  "An MTLBuffer of float4, (+SEGMENTS+ + 1) per orbiter: the heliocentric
orbits in the scene, the moons' relative to their planets.")
(defvar *orbit-key* nil "(exponent tc) the heliocentric orbits were drawn for.")
(defvar *moon-orbit-key* nil "(scales tc frame) the moons' orbits were drawn for.")
(defvar *scales* nil "MOON-SYSTEM-SCALES, kept with the heliocentric orbits.")

;;; Small per-frame data goes through setVertexBytes: from these, allocated
;;; once. Metal copies them at encode time, so one block each is enough.
(defvar *uniforms* nil)     ; 40 floats: view, projection, viewport w h, line width, pad, sun xyzw
(defvar *discs* nil)        ; 12 floats a body: x y z radius, r g b a, glow 0 0 0
(defvar *orbit-info* nil)   ; 12 floats a line: r g b a, centre x y z 0, style x y 0 0

(defvar *camera* (make-camera))
(defvar *focus* nil "The body the camera follows, if any.")
(defvar *last-placed* nil "PLACE-BODIES' answer for the last frame drawn.")
(defvar *frame-count* 0)
(defparameter +uniform-bytes+ 160)
(defparameter +disc-floats+ 24)
(defvar *ring-pipeline* nil)
(defvar *ring-data* '() "Ringed planet -> its 24 floats (struct Ring), allocated once.")
(defvar *depth-writing* nil "Depth test and write: the bodies and the rings.")
(defvar *depth-testing* nil "Depth test only: the orbits, which bodies hide.")
(defvar *maps* (make-array 10 :initial-element nil) "The planet maps, by texture index.")
(defvar *ring-map* nil)

(defparameter +maps+
  '(("Sun" . "sun") ("Mercury" . "mercury") ("Venus" . "venus") ("Earth" . "earth")
    ("Moon" . "moon") ("Mars" . "mars") ("Jupiter" . "jupiter") ("Saturn" . "saturn")
    ("Uranus" . "uranus") ("Neptune" . "neptune"))
  "Body and map, in texture order: Solar System Scope's, CC BY 4.0.")

(defparameter +rings+
  '(("Saturn" 0 74500d0 140220d0)       ; the map's edges: the C ring's inside to the F ring
    ("Uranus" 1 41700d0 51300d0))       ; just inside ring 6 to just outside epsilon
  "Ringed planets: name, style (0 map, 1 radii in the shader), inner and outer km.")
(defvar *failure* nil "The condition that stopped drawing, if one has.")

(defun nothing-p (object)
  "Is OBJECT nil, whichever way the bridge said so?"
  (or (null object)
      (and (cffi:pointerp object) (cffi:null-pointer-p object))))

(defmacro store-floats (pointer offset &rest values)
  "Write VALUES as single floats from OFFSET on: open-coded, so that the
thousands of writes a frame can make cons no argument lists."
  (let ((p (gensym)) (o (gensym)))
    `(let ((,p ,pointer) (,o ,offset))
       (declare (type fixnum ,o))
       ,@(loop for value in values
               for i from 0
               collect `(setf (cffi:mem-aref ,p :float (+ ,o ,i)) (float ,value 1.0))))))

(defun smoothstep (from to x)
  (let ((u (max 0d0 (min 1d0 (/ (- x from) (- to from))))))
    (* u u (- 3 (* 2 u)))))

;;; ------------------------------------------------------------------
;;; setup

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
            *depth-writing* (depth-state 3 t)     ; less or equal
            *depth-testing* (depth-state 3 nil)
            *ring-data* (loop for (name) in +rings+
                              collect (cons (find-planet name) (cffi:foreign-alloc :float :count 24)))
            *orbit-buffer* (objc:invoke *device* "newBufferWithLength:options:"
                                        (* 16 orbits (1+ +segments+)) 0)
            *uniforms* (cffi:foreign-alloc :float :count (/ +uniform-bytes+ 4))
            *discs* (cffi:foreign-alloc :float :count (* +disc-floats+ (1+ orbits)))
            *orbit-info* (cffi:foreign-alloc :float :count (* 12 orbits)))
      ;; Every line starts clear, so a slot nothing has filled draws nothing.
      (dotimes (i (* 12 orbits)) (setf (cffi:mem-aref *orbit-info* :float i) 0.0))
      (load-maps)
      (format t "SOLAR: Metal ready on ~a, ~dx MSAA; ~d orbits~%"
              (objc:ns-string-to-string (objc:invoke *device* "name")) samples orbits)
      (finish-output))))

;;; ------------------------------------------------------------------
;;; orbits

(defmacro store-orbit (contents slot points (x y z) &body transform)
  "The COUNT+1 points of one orbit, x y z triples, into SLOT of the orbit
buffer, each through TRANSFORM, a form of X Y Z answering three values."
  (let ((base (gensym)) (i (gensym)) (v (gensym)))
    `(let ((,base (* ,slot 4 (1+ +segments+)))
           (,v ,points))
       (declare (type (simple-array double-float (*)) ,v) (type fixnum ,base))
       (dotimes (,i (1+ +segments+))
         (let ((,x (aref ,v (* 3 ,i))) (,y (aref ,v (+ 1 (* 3 ,i)))) (,z (aref ,v (+ 2 (* 3 ,i)))))
           (multiple-value-bind (,x ,y ,z) (progn ,@transform)
             (store-floats ,contents (+ ,base (* 4 ,i)) ,x ,y ,z 1)))))))

(defun ensure-orbits (tc k)
  "Rewrite the heliocentric orbits if the compression or the elements --
which drift, slowly -- have changed since they were drawn. A year of
simulated time moves them by less than a pixel. The camera does not enter
into it."
  (let ((key *orbit-key*))
    (unless (and key
                 (= *radius-exponent* (first key))
                 (< (abs (- tc (second key))) 0.01d0))
      (let ((contents (objc:invoke *orbit-buffer* "contents")))
        (loop for body in (heliocentric-bodies)
              for slot from 0
              do (store-orbit contents slot (orbit-points body tc +segments+) (x y z)
                   (compress x y z k))))
      (setf *orbit-key* (list *radius-exponent* tc)
            *scales* (moon-system-scales tc k)))))

(defun ensure-moon-orbits (tc)
  "Rewrite the moons' orbits, relative to their planets, when a day of
simulated time has passed -- the Moon's node turns a fifth of a degree in
three -- but not more often than every thirty frames, which at a year a
second is twice a second."
  (let ((key *moon-orbit-key*))
    (unless (and key
                 (eq *scales* (first key))
                 (or (< (abs (- tc (second key))) (/ 1d0 36525))
                     (< (- *frame-count* (third key)) 30)))
      (let ((contents (objc:invoke *orbit-buffer* "contents"))
            (first-slot (length (heliocentric-bodies))))
        (loop for moon in *moons*
              for slot from first-slot
              do (destructuring-bind (radius . outermost) (rest (assoc (body-parent moon) *scales*))
                   (store-orbit contents slot (moon-orbit-points moon tc +segments+) (x y z)
                     (moon-display-offset x y z radius outermost)))))
      (setf *moon-orbit-key* (list *scales* tc *frame-count*)))))

;;; ------------------------------------------------------------------
;;; bodies

(defun pixels-per-unit (height depth)
  "Pixels per scene unit at view DEPTH (negative, in front of the camera),
in a drawable HEIGHT pixels tall."
  (/ (* 0.5d0 height) (tan (/ *field-of-view* 2)) (max 1d-9 (- depth))))

(defun place-bodies (tc k aspect height pixels-per-point)
  "Every body's scene position, depth, disc radius and opacity, as a list
of (depth body x y z radius alpha), and the moon systems -- (body x y z
alpha on-screen-radius) -- as an alist. Moons fade in as their system
grows on the screen beyond four times their planet's disc, and are gone
below two and a half. Within a system that is showing, the planet and its
moons are drawn to the system's own scale -- the square root of their
radius over the outermost moon's distance, as the moons' distances are --
so that the planet grows as the camera comes close, its moons stay
outside it, and Saturn's rings inside Mimas."
  (let* ((zoom-enlarge (sqrt (camera-zoom *camera*)))
         (sun (multiple-value-list
               (if (eq *frame* :barycentric)
                   (multiple-value-bind (x y z) (sun-barycentric-offset tc) (compress x y z k))
                   (values 0d0 0d0 0d0))))
         (placed '())
         (systems '()))
    (labels ((base (body)
               ;; Followed and without moons to set a scale: let it grow.
               (* (max 1d0 (min (if (and (eq body *focus*) (null (assoc body *scales*))) 12d0 3d0)
                                zoom-enlarge))
                  (disc-radius body pixels-per-point)))
             (place (body x y z radius &optional (alpha 1d0))
               (let ((depth (nth-value 2 (view-position *camera* aspect x y z))))
                 (push (list depth body x y z radius alpha) placed)
                 depth)))
      (destructuring-bind (sx sy sz) sun
        (place +sun+ sx sy sz (base +sun+))
        (dolist (body (heliocentric-bodies))
          (multiple-value-bind (x y z) (multiple-value-call #'compress
                                         (heliocentric-position body tc) k)
            (let* ((px (+ x sx)) (py (+ y sy)) (pz (+ z sz))
                   (depth (nth-value 2 (view-position *camera* aspect px py pz)))
                   (scale (rest (assoc body *scales*))))
              (if (null scale)
                  (place body px py pz (base body))
                  (destructuring-bind (radius . outermost) scale
                    (let* ((on-screen (* radius (pixels-per-unit height depth)))
                           (outermost-km (* outermost +km-per-au+))
                           (disc (base body))
                           (alpha (smoothstep (* 2.5d0 disc) (* 4d0 disc) on-screen)))
                      ;; As the system shows, from the ordinary disc to
                      ;; the system's own scale -- not the larger of the
                      ;; two, or a followed planet's enlarged disc would
                      ;; swallow its rings and inner moons.
                      (flet ((to-scale (km) (* on-screen (sqrt (/ km outermost-km))))
                             (blend (ordinary scaled) (+ ordinary (* alpha (- scaled ordinary)))))
                        (place body px py pz (blend disc (to-scale (body-radius-km body))))
                        (push (list body px py pz alpha on-screen) systems)
                        (dolist (moon (moons-of body))
                          (multiple-value-bind (dx dy dz)
                              (multiple-value-call #'moon-display-offset
                                (moon-offset moon tc) radius outermost)
                            (place moon (+ px dx) (+ py dy) (+ pz dz)
                                   (max (* 1.3d0 pixels-per-point)
                                        (blend (base moon) (to-scale (body-radius-km moon))))
                                   alpha)))))))))))
      (values placed systems sun))))

(defun view-axes (body tc)
  "Nine values: BODY's axes turned into view space, or NIL."
  (multiple-value-bind (ax ay az bx by bz cx cy cz) (body-axes body tc)
    (when ax
      (let ((r (solar-system.core::camera-rotation *camera*)))
        (flet ((turn (x y z)
                 (values (+ (* (aref r 0) x) (* (aref r 1) y) (* (aref r 2) z))
                         (+ (* (aref r 3) x) (* (aref r 4) y) (* (aref r 5) z))
                         (+ (* (aref r 6) x) (* (aref r 7) y) (* (aref r 8) z)))))
          (multiple-value-call #'values (turn ax ay az) (turn bx by bz) (turn cx cy cz)))))))

(defun fill-discs (placed tc ringed)
  "The bodies into *DISCS*, farthest from the camera first, so that nearer
ones blend over them at their edges. RINGED: the planets whose rings are
drawn; Saturn's shadow it."
  (loop for (nil body x y z radius alpha) in (sort (copy-list placed) #'< :key #'first)
        for slot from 0
        for base = (* +disc-floats+ slot)
        for colour = (body-colour body)
        for index = (if (> alpha 0d0) (texture-index body) -1)
        do (store-floats *discs* base
                         x y z radius
                         (aref colour 0) (aref colour 1) (aref colour 2) alpha
                         (if (eq body +sun+) 1 0) index
                         (if (and (member body ringed) (string= (body-name body) "Saturn")) 1 0)
                         0)
           (multiple-value-bind (ax ay az bx by bz cx cy cz)
               (if (>= index 0) (view-axes body tc) (values 1d0 0d0 0d0 0d0 1d0 0d0 0d0 0d0 1d0))
             (store-floats *discs* (+ base 12) ax ay az 0 bx by bz 0 cx cy cz 0)))
  (length placed))

(defun fill-rings (systems tc)
  "Each ringed planet's rings into its block of *RING-DATA*, at its moon
system's scale; their opacity, the system's. The planets whose rings are
to be drawn."
  (loop for (name style inner outer) in +rings+
        for planet = (find-planet name)
        for block = (rest (assoc planet *ring-data*))
        for system = (rest (assoc planet systems))
        for scale = (rest (assoc planet *scales*))
        when (and block system scale (> (fourth system) 0.01d0) (or (= style 1) *ring-map*))
          collect (destructuring-bind (px py pz alpha on-screen) system
                    (declare (ignore on-screen))
                    (destructuring-bind (radius . outermost) scale
                      (let ((outermost-km (* outermost +km-per-au+)))
                        (flet ((to-scale (km) (* radius (sqrt (/ km outermost-km)))))
                          (multiple-value-bind (ax ay az bx by bz) (body-axes planet tc)
                            (store-floats block 0
                                          px py pz 1  ax ay az 0  bx by bz 0
                                          (to-scale inner) (to-scale outer)
                                          (to-scale (body-radius-km planet)) alpha
                                          radius outermost-km inner outer
                                          style 0 0 0)
                            planet)))))))

(defun store-line (slot r g b a cx cy cz &optional (fade 0) (width 0))
  (store-floats *orbit-info* (* 12 slot) r g b a cx cy cz 0 fade width 0 0))

(defun fill-orbit-info (systems sun)
  "Each orbit's colour, opacity and centre: the Sun's family round the Sun,
the planets brighter than the dwarfs; each moon round its planet, as bright
as its system is visible."
  (destructuring-bind (sx sy sz) sun
    (loop for body in (heliocentric-bodies)
          for slot from 0
          for colour = (body-colour body)
          do (store-line slot (aref colour 0) (aref colour 1) (aref colour 2)
                         (if (member body *planets*) 0.45 0.3)
                         sx sy sz)))
  (loop for moon in *moons*
        for slot from (length (heliocentric-bodies))
        for colour = (body-colour (body-parent moon))
        do (destructuring-bind (px py pz alpha &rest rest) (rest (assoc (body-parent moon) systems))
             (declare (ignore rest))
             (store-line slot (aref colour 0) (aref colour 1) (aref colour 2) (* 0.35d0 alpha)
                         px py pz))))

(defun follow-focus (placed)
  "Keep the camera's target on the focused body, wherever it has moved."
  (let ((entry (and *focus* (find *focus* placed :key #'second))))
    (when entry
      (destructuring-bind (depth body x y z &rest rest) entry
        (declare (ignore depth body rest))
        (let ((target (solar-system.core::camera-target *camera*)))
          (setf (aref target 0) x (aref target 1) y (aref target 2) z))))))

(defun screen-metrics (view)
  "Values width and height in pixels, pixels per point, aspect, and the
projection matrix: what TO-POINTS needs, read once."
  (let* ((size (objc:invoke view "drawableSize"))
         (width (float (aref size 0) 1d0))
         (height (float (aref size 1) 1d0))
         (aspect (/ width height)))
    (values width height (float (objc:invoke view "contentScaleFactor") 1d0) aspect
            (projection-matrix *camera* aspect))))

(defun to-points (x y z width height scale aspect projection)
  "Values the screen position in points, y down, of scene point X Y Z; NIL
if it is behind the camera."
  (multiple-value-bind (vx vy vz) (view-position *camera* aspect x y z)
    (when (minusp vz)
      (values (/ (* 0.5d0 width (1+ (/ (* (aref projection 0) vx) (- vz)))) scale)
              (/ (* 0.5d0 height (- 1 (/ (* (aref projection 5) vy) (- vz)))) scale)))))

(defun body-at (view px py &optional (reach 24d0))
  "The visible body drawn nearest the point PX, PY (points, y down) of VIEW,
within REACH points of its disc, or NIL."
  (multiple-value-bind (width height scale aspect projection) (screen-metrics view)
    (let ((best nil) (best-distance nil))
      (loop for (nil body x y z radius alpha) in *last-placed*
            when (> alpha 0.5d0)
              do (multiple-value-bind (sx sy) (to-points x y z width height scale aspect projection)
                   (when sx
                     (let ((distance (- (sqrt (+ (expt (- sx px) 2) (expt (- sy py) 2)))
                                        (/ radius scale))))
                       (when (and (< distance reach) (or (null best) (< distance best-distance)))
                         (setf best body best-distance distance))))))
      best)))

(defun focus-on (body)
  "Follow BODY; for a planet with moons, come close enough to see them."
  (setf *focus* body)
  (let ((scale (and body (rest (assoc body *scales*)))))
    ;; One without moons: near enough that its disc is a good size.
    (when (and body (null scale))
      (setf (camera-zoom *camera*) (max (camera-zoom *camera*) 60d0)))
    (when scale
      ;; The system's radius at about a third of the shorter side: at the
      ;; target, pixels per unit are h/2 / tan(fov/2) / distance.
      (let* ((size (objc:invoke *view* "drawableSize"))
             (width (float (aref size 0) 1d0))
             (height (float (aref size 1) 1d0))
             (aspect (/ width height))
             (wanted (* 0.3d0 (min width height)))
             (distance (/ (* 0.5d0 height (first scale)) (tan (/ *field-of-view* 2)) wanted)))
        (setf (camera-zoom *camera*)
              (max 0.3d0 (min 400d0 (/ (fit-distance aspect) distance))))))))

(defun store-matrix (pointer offset matrix)
  (dotimes (i 16)
    (setf (cffi:mem-aref pointer :float (+ offset i)) (float (aref matrix i) 1.0))))

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
             (ringed '()))
        (ensure-orbits tc k)
        (ensure-moon-orbits tc)
        (multiple-value-bind (placed systems sun)
            (place-bodies tc k aspect height pixels-per-point)
          (setf *last-placed* placed)
          (follow-focus placed)
          (setf ringed (fill-rings systems tc)
                discs (fill-discs placed tc ringed))
          (fill-orbit-info systems sun)
          (update-trails tc k sun)
          (store-matrix *uniforms* 0 (view-matrix *camera* aspect))
          (store-matrix *uniforms* 16 (projection-matrix *camera* aspect))
          (destructuring-bind (sx sy sz) sun
            (store-floats *uniforms* 32 width height (* 1.5d0 pixels-per-point) 0 sx sy sz 1)))
        (let ((pass (objc:invoke view "currentRenderPassDescriptor")))
          (unless (nothing-p pass)
            (let* ((commands (objc:invoke *queue* "commandBuffer"))
                   (encoder (objc:invoke commands "renderCommandEncoderWithDescriptor:" pass)))
              ;; Bodies first, writing their spheres' depth; then the
              ;; rings, which Saturn hides half of; then the orbits, which
              ;; pass behind whatever is nearer.
              (objc:invoke encoder "setDepthStencilState:" *depth-writing*)
              (objc:invoke encoder "setRenderPipelineState:" *disc-pipeline*)
              (objc:invoke encoder "setVertexBytes:length:atIndex:" *discs*
                           (* 4 +disc-floats+ discs) 0)
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
              ;; Orbits: a quad (triangle strip of 4) per segment.
              (objc:invoke encoder "setDepthStencilState:" *depth-testing*)
              (objc:invoke encoder "setRenderPipelineState:" *orbit-pipeline*)
              (objc:invoke encoder "setVertexBuffer:offset:atIndex:" *orbit-buffer* 0 0)
              (objc:invoke encoder "setVertexBytes:length:atIndex:" *uniforms* +uniform-bytes+ 1)
              (objc:invoke encoder "setVertexBytes:length:atIndex:" *orbit-info* (* 48 orbits) 2)
              (objc:invoke encoder "drawPrimitives:vertexStart:vertexCount:instanceCount:"
                           4 0 4 (* orbits +segments+))
              (objc:invoke encoder "endEncoding")
              (objc:invoke commands "presentDrawable:" (objc:invoke view "currentDrawable"))
              (objc:invoke commands "commit"))))
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
