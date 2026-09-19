// make-icon.swift -- draws the app icon: res/Icon.xcassets/AppIcon.appiconset/icon-1024.png
//
//     swift tools/make-icon.swift        (from the project directory)
//
// A square, opaque 1024 x 1024 PNG -- iOS rounds the corners itself -- in the
// app's own look: the Sun glowing in the middle, three orbits tilted as the
// app shows them, in the colours it gives Earth, Mars and Saturn, each planet
// lit on the side that faces the Sun, Saturn with its rings, and faint stars.

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let size = 1024
let space = CGColorSpace(name: CGColorSpace.sRGB)!
// Drawn with alpha, so that glows fade; flattened to opaque at the end, since
// an icon may not have an alpha channel.
let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                        space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
let centre = CGPoint(x: 512, y: 512)
let tilt = -0.32                       // radians: the orbits' lean
let squash: CGFloat = 0.42             // their foreshortening, seen from above at a slant

func colour(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: space, components: [r, g, b, a])!
}

func radial(_ stops: [(CGFloat, CGColor)], at point: CGPoint, radius: CGFloat, fill: Bool = false) {
    let gradient = CGGradient(colorsSpace: space, colors: stops.map { $0.1 } as CFArray,
                              locations: stops.map { $0.0 })!
    context.drawRadialGradient(gradient, startCenter: point, startRadius: 0,
                               endCenter: point, endRadius: radius, options: fill ? [.drawsAfterEndLocation] : [])
}

// Where on a tilted orbit of radius R the angle A falls.
func onOrbit(_ r: CGFloat, _ a: CGFloat) -> CGPoint {
    let x = r * cos(a), y = r * squash * sin(a)
    return CGPoint(x: centre.x + x * CGFloat(cos(tilt)) - y * CGFloat(sin(tilt)),
                   y: centre.y + x * CGFloat(sin(tilt)) + y * CGFloat(cos(tilt)))
}

func orbit(_ r: CGFloat, _ c: CGColor, width: CGFloat) {
    context.saveGState()
    context.translateBy(x: centre.x, y: centre.y)
    context.rotate(by: CGFloat(tilt))
    context.scaleBy(x: 1, y: squash)
    context.addEllipse(in: CGRect(x: -r, y: -r, width: 2 * r, height: 2 * r))
    context.restoreGState()
    context.setStrokeColor(c)
    context.setLineWidth(width)
    context.strokePath()
}

// The near half of an orbit, over the Sun: the half towards the viewer,
// below its long axis on the page.
func orbitFront(_ r: CGFloat, _ c: CGColor, width: CGFloat) {
    context.saveGState()
    context.translateBy(x: centre.x, y: centre.y)
    context.rotate(by: CGFloat(tilt))
    context.clip(to: CGRect(x: -r - 20, y: -r - 20, width: 2 * r + 40, height: r + 20))
    var squashing = CGAffineTransform(scaleX: 1, y: squash)
    context.addPath(CGPath(ellipseIn: CGRect(x: -r, y: -r, width: 2 * r, height: 2 * r),
                           transform: &squashing))
    context.setStrokeColor(c)
    context.setLineWidth(width)
    context.strokePath()
    context.restoreGState()
}

// A planet lit from the Sun: bright on the side facing it, falling to night.
func planet(at p: CGPoint, radius: CGFloat, _ r: CGFloat, _ g: CGFloat, _ b: CGFloat) {
    let dx = centre.x - p.x, dy = centre.y - p.y
    let d = max(1, sqrt(dx * dx + dy * dy))
    let lit = CGPoint(x: p.x + dx / d * radius * 0.55, y: p.y + dy / d * radius * 0.55)
    context.saveGState()
    context.addEllipse(in: CGRect(x: p.x - radius, y: p.y - radius, width: 2 * radius, height: 2 * radius))
    context.clip()
    let gradient = CGGradient(colorsSpace: space,
                              colors: [colour(min(1, r * 1.25), min(1, g * 1.25), min(1, b * 1.25)),
                                       colour(r, g, b), colour(r * 0.12, g * 0.12, b * 0.14)] as CFArray,
                              locations: [0, 0.45, 1])!
    context.drawRadialGradient(gradient, startCenter: lit, startRadius: 0,
                               endCenter: lit, endRadius: radius * 2.1, options: [.drawsAfterEndLocation])
    context.restoreGState()
}

// Space: deep blue in the middle to near black at the edges.
radial([(0, colour(0.07, 0.09, 0.19)), (1, colour(0.01, 0.01, 0.04))], at: centre, radius: 760, fill: true)

// Faint stars, the same every time.
var seed: UInt64 = 1054
func next() -> CGFloat {
    seed = seed &* 6364136223846793005 &+ 1442695040888963407
    return CGFloat((seed >> 33) % 100000) / 100000
}
for _ in 0..<90 {
    let x = next() * 1024, y = next() * 1024, r = 1.2 + next() * 2.4, a = 0.25 + next() * 0.55
    context.setFillColor(colour(0.85, 0.88, 1.0, a))
    context.fillEllipse(in: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r))
}

// Orbits, inner to outer: Earth, Mars, Saturn.
orbit(215, colour(0.30, 0.56, 0.98, 0.75), width: 7)
orbit(315, colour(0.88, 0.42, 0.26, 0.70), width: 7)
orbit(440, colour(0.91, 0.83, 0.62, 0.60), width: 7)

// The Sun and its glow.
radial([(0, colour(1.0, 0.86, 0.45, 0.55)), (1, colour(1.0, 0.55, 0.10, 0))], at: centre, radius: 250)
radial([(0, colour(1.0, 0.98, 0.85)), (0.55, colour(1.0, 0.80, 0.30)),
        (1, colour(0.98, 0.50, 0.10))], at: centre, radius: 96)

// The orbits' near halves pass in front of the Sun.
orbitFront(215, colour(0.30, 0.56, 0.98, 0.75), width: 7)
orbitFront(315, colour(0.88, 0.42, 0.26, 0.70), width: 7)

// The planets, each on its orbit.
let earth = onOrbit(215, 2.25)
planet(at: earth, radius: 34, 0.30, 0.56, 0.98)
let mars = onOrbit(315, -0.55)
planet(at: mars, radius: 26, 0.88, 0.42, 0.26)

// Saturn, and its rings: behind the planet, then in front of it.
let saturn = onOrbit(440, 0.95)
func rings(front: Bool) {
    context.saveGState()
    if front {
        context.addRect(CGRect(x: saturn.x - 140, y: saturn.y - 140, width: 280, height: 140))
    } else {
        context.addRect(CGRect(x: saturn.x - 140, y: saturn.y, width: 280, height: 140))
    }
    context.clip()
    context.translateBy(x: saturn.x, y: saturn.y)
    context.rotate(by: -0.38)
    context.scaleBy(x: 1, y: 0.30)
    for (r, w, a) in [(92.0, 13.0, 0.85), (72.0, 18.0, 0.70)] as [(CGFloat, CGFloat, CGFloat)] {
        context.addEllipse(in: CGRect(x: -r, y: -r, width: 2 * r, height: 2 * r))
        context.setStrokeColor(colour(0.93, 0.86, 0.68, a))
        context.setLineWidth(w)
        context.strokePath()
    }
    context.restoreGState()
}
rings(front: false)
planet(at: saturn, radius: 46, 0.91, 0.83, 0.62)
rings(front: true)

// Write it.
let url = URL(fileURLWithPath: "res/Icon.xcassets/AppIcon.appiconset/icon-1024.png")
try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
let opaque = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                       space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
opaque.draw(context.makeImage()!, in: CGRect(x: 0, y: 0, width: size, height: size))
let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(destination, opaque.makeImage()!, nil)
guard CGImageDestinationFinalize(destination) else { fatalError("could not write \(url.path)") }
print("wrote \(url.path)")
