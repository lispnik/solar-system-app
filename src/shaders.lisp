;;;; shaders.lisp -- the Metal Shading Language the renderer uses.
;;;;
;;;; One string, with the segment count put in by FORMAT, compiled by the
;;;; device when Metal is first set up (metal.lisp): discs and their maps,
;;;; rings, the asteroid belt, and lines.

(in-package #:solar-system)

(defparameter +shaders+ "
#include <metal_stdlib>
using namespace metal;

#define SEGMENTS ~d

struct Uniforms { float4x4 view; float4x4 proj; float2 viewport; float line_width; float pad; float4 sun; };

// position.w: radius in pixels; extra: glow, texture index (-1 none),
// 1 if Saturn's rings are being drawn and shadow it, 1 for the Moon seen
// from the Earth, which the Earth's shadow can fall on;
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
  float3 eye_centre;
  float earth_shadow [[flat]];
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
// style.y 1: to true scale, mapping x scene units a km of mapping y (the
// view from Earth); else the square-root scale of a moon system.
float ring_radius(constant Ring &r, float km)
{
  return r.style.y > 0.5 ? km * r.mapping.x / r.mapping.y : r.mapping.x * sqrt(km / r.mapping.y);
}

float ring_km(constant Ring &r, float rho)
{
  return r.style.y > 0.5 ? rho * r.mapping.y / r.mapping.x
                         : r.mapping.y * (rho / r.mapping.x) * (rho / r.mapping.x);
}

// How much of the Sun a ring at scene radius RHO lets through: 1 - its opacity.
float ring_opacity(constant Ring &r, float rho, texture2d<float> map)
{
  float t = (ring_km(r, rho) - r.mapping.z) / (r.mapping.w - r.mapping.z);
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
  out.eye_centre = eye.xyz;
  out.earth_shadow = d.extra.w;
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
  // The Moon seen from the Earth's centre, where the camera is: the axis
  // of the Earth's shadow runs from the camera away from the Sun. Scene
  // units here are AU. Umbra and penumbra as the event search has them,
  // two per cent large for the atmosphere; in the umbra, the red of every
  // sunset on Earth at once.
  float3 tint = float3(1.0);
  if (in.earth_shadow > 0.5) {
    const float re = 6378.14 / 149597870.7, rs = 696000.0 / 149597870.7;
    float3 p = in.eye_centre + in.world_radius * float3(n2, nz);
    float3 sun = (u.view * float4(u.sun.xyz, 1.0)).xyz;
    float ds = length(sun);
    float3 axis = -sun / ds;
    float x = dot(p, axis);
    if (x > 0.0) {
      float d = length(p - x * axis);
      float umbra = 1.02 * (re - x * (rs - re) / ds);
      float penumbra = 1.02 * (re + x * (rs + re) / ds);
      if (d < umbra) {
        tint = float3(0.30, 0.10, 0.06);
      } else if (d < penumbra) {
        tint = float3(mix(0.45, 1.0, (d - umbra) / (penumbra - umbra)));
      }
    }
  }
  if (in.glow == 0.0) {
    rgb *= (0.05 + 0.95 * saturate(dot(n, in.light)) * (1.0 - shadow)) * tint;
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
    float t = (ring_km(r, rho) - r.mapping.z) / (r.mapping.w - r.mapping.z);
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

// The asteroid belt: a point each, placed by the GPU from its elements --
// a, e, i, node, argument of perihelion, mean anomaly at epoch, mean
// motion (radians a day), epoch (days from J2000) -- by Kepler's equation,
// then compressed like everything else, or seen from the Earth.
struct Belt { float4 time; float4 sun; float4 earth; float4 colour; };
// time: days from J2000, compression k, exponent, 1 from the Earth.
// colour.a is scaled by earth.w, the point size is sun.w.

struct BeltVarying { float4 position [[position]]; float size [[point_size]]; float4 colour; };

vertex BeltVarying belt_vertex(uint vid [[vertex_id]],
                               device const float *elements [[buffer(0)]],
                               constant Uniforms &u [[buffer(1)]],
                               constant Belt &b [[buffer(2)]])
{
  device const float *e = elements + vid * 8;
  float a = e[0], ecc = e[1], inc = e[2], node = e[3], peri = e[4];
  float m = e[5] + e[6] * (b.time.x - e[7]);
  m -= 2.0 * M_PI_F * floor(m / (2.0 * M_PI_F));
  float ea = m + ecc * sin(m);
  for (int k = 0; k < 8; k++) ea -= (ea - ecc * sin(ea) - m) / (1.0 - ecc * cos(ea));
  float xp = a * (cos(ea) - ecc), yp = a * sqrt(1.0 - ecc * ecc) * sin(ea);
  float cw = cos(peri), sw = sin(peri), cn = cos(node), sn = sin(node), ci = cos(inc), si = sin(inc);
  float3 p = float3((cw * cn - sw * sn * ci) * xp - (sw * cn + cw * sn * ci) * yp,
                    (cw * sn + sw * cn * ci) * xp + (cw * cn * ci - sw * sn) * yp,
                    sw * si * xp + cw * si * yp);
  if (b.time.w > 0.5) {
    p -= b.earth.xyz;
  } else {
    float r = length(p);
    p = p * (b.time.y * pow(r, b.time.z) / r) + b.sun.xyz;
  }
  BeltVarying out;
  out.position = u.proj * (u.view * float4(p, 1.0));
  out.size = b.sun.w;
  out.colour = b.colour;
  return out;
}

fragment float4 belt_fragment(BeltVarying in [[stage_in]], float2 corner [[point_coord]])
{
  float d = 2.0 * length(corner - 0.5);
  float a = in.colour.a * (1.0 - smoothstep(0.5, 1.0, d));
  if (a <= 0.0) discard_fragment();
  return float4(in.colour.rgb * a, a);
}

fragment float4 orbit_fragment(OrbitVarying in [[stage_in]])
{
  float a = in.colour.a * (1.0 - smoothstep(in.half_width - 0.5, in.half_width + 0.5, abs(in.across)));
  return float4(in.colour.rgb * a, a);
}
")
