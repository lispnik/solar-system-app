// make-store-shots.swift -- the App Store screenshots.
//
//     swift tools/make-store-shots.swift <raw-directory> [out-directory]
//
// Takes the simulator screenshots named in doc/store/captions.txt -- 1320 x
// 2868, which is the 6.9-inch size App Store Connect asks for -- and puts
// each one under its caption on a dark ground, at the same size, ready to
// upload.

import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let width = 1320, height = 2868
let arguments = CommandLine.arguments
guard arguments.count >= 2 else {
    FileHandle.standardError.write("usage: make-store-shots.swift <raw-directory> [out]\n".data(using: .utf8)!)
    exit(2)
}
let rawDirectory = URL(fileURLWithPath: arguments[1], isDirectory: true)
let outDirectory = URL(fileURLWithPath: arguments.count > 2 ? arguments[2] : "doc/store", isDirectory: true)
let space = CGColorSpace(name: CGColorSpace.sRGB)!

func colour(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: space, components: [r, g, b, a])!
}

// name | headline | subhead, one shot per line.
let manifest = try String(contentsOf: URL(fileURLWithPath: "doc/store/captions.txt"), encoding: .utf8)
let shots = manifest.split(separator: "\n").compactMap { line -> (String, String, String)? in
    let text = line.trimmingCharacters(in: .whitespaces)
    if text.isEmpty || text.hasPrefix("#") { return nil }
    let parts = text.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
    guard parts.count == 3 else { return nil }
    return (parts[0], parts[1], parts[2])
}

func draw(_ text: String, font: NSFont, colour: NSColor, in context: CGContext,
          x: CGFloat, top: CGFloat, width: CGFloat, leading: CGFloat) -> CGFloat {
    // Returns the y the next block starts at, counting down from the top.
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .left
    paragraph.lineSpacing = leading
    let attributed = NSAttributedString(string: text, attributes: [
        .font: font, .foregroundColor: colour, .paragraphStyle: paragraph,
    ])
    let framesetter = CTFramesetterCreateWithAttributedString(attributed)
    let bounds = CTFramesetterSuggestFrameSizeWithConstraints(
        framesetter, CFRange(location: 0, length: 0), nil,
        CGSize(width: width, height: .greatestFiniteMagnitude), nil)
    let box = CGRect(x: x, y: CGFloat(height) - top - bounds.height, width: width, height: bounds.height)
    let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0),
                                         CGPath(rect: box, transform: nil), nil)
    CTFrameDraw(frame, context)
    return top + bounds.height
}

func rounded(_ rect: CGRect, radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

for (name, headline, subhead) in shots {
    let source = rawDirectory.appendingPathComponent("\(name).png")
    guard let provider = CGDataProvider(url: source as CFURL),
          let shot = CGImage(pngDataProviderSource: provider, decode: nil,
                             shouldInterpolate: true, intent: .defaultIntent) else {
        FileHandle.standardError.write("no screenshot at \(source.path)\n".data(using: .utf8)!)
        exit(1)
    }

    let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                            bytesPerRow: 0, space: space,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let previous = NSGraphicsContext.current
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)

    // The ground: night, with the Sun's colour glowing behind the caption.
    let sky = CGGradient(colorsSpace: space,
                         colors: [colour(0.05, 0.07, 0.14), colour(0.02, 0.02, 0.05)] as CFArray,
                         locations: [0, 1])!
    context.drawLinearGradient(sky, start: CGPoint(x: 0, y: CGFloat(height)),
                               end: CGPoint(x: 0, y: 0), options: [])
    let glow = CGGradient(colorsSpace: space,
                          colors: [colour(1.0, 0.62, 0.20, 0.22), colour(1.0, 0.45, 0.10, 0)] as CFArray,
                          locations: [0, 1])!
    context.drawRadialGradient(glow, startCenter: CGPoint(x: 660, y: 2560), startRadius: 0,
                               endCenter: CGPoint(x: 660, y: 2560), endRadius: 900, options: [])

    // The caption. The headline takes the largest size that keeps it to two
    // lines, so a long one shrinks rather than running to three.
    var headlineSize: CGFloat = 84
    for size in [CGFloat(84), 78, 72, 66, 60] {
        let font = NSFont.systemFont(ofSize: size, weight: .bold)
        let attributed = NSAttributedString(string: headline, attributes: [.font: font])
        let setter = CTFramesetterCreateWithAttributedString(attributed)
        let bounds = CTFramesetterSuggestFrameSizeWithConstraints(
            setter, CFRange(location: 0, length: 0), nil,
            CGSize(width: CGFloat(1144), height: CGFloat.greatestFiniteMagnitude), nil)
        headlineSize = size
        if bounds.height < size * 2.5 { break }
    }
    let after = draw(headline, font: NSFont.systemFont(ofSize: headlineSize, weight: .bold),
                     colour: NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1),
                     in: context, x: 88, top: 168, width: 1144, leading: 14)
    _ = draw(subhead, font: NSFont.systemFont(ofSize: 44, weight: .regular),
             colour: NSColor(srgbRed: 0.64, green: 0.70, blue: 0.85, alpha: 1),
             in: context, x: 88, top: after + 34, width: 1144, leading: 10)

    // The screenshot itself, at its own shape, bleeding off the bottom.
    let shotWidth: CGFloat = 1128
    let shotHeight = shotWidth * CGFloat(shot.height) / CGFloat(shot.width)
    let frame = CGRect(x: (CGFloat(width) - shotWidth) / 2,
                       y: CGFloat(height) - 600 - shotHeight, width: shotWidth, height: shotHeight)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -12), blur: 40,
                      color: colour(0, 0, 0, 0.55))
    context.addPath(rounded(frame, radius: 58))
    context.setFillColor(colour(0, 0, 0))
    context.fillPath()
    context.restoreGState()
    context.saveGState()
    context.addPath(rounded(frame, radius: 58))
    context.clip()
    context.draw(shot, in: frame)
    context.restoreGState()
    context.addPath(rounded(frame, radius: 58))
    context.setStrokeColor(colour(1, 1, 1, 0.14))
    context.setLineWidth(3)
    context.strokePath()

    NSGraphicsContext.current = previous

    try FileManager.default.createDirectory(at: outDirectory, withIntermediateDirectories: true)
    let url = outDirectory.appendingPathComponent("\(name).png")
    let opaque = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                           bytesPerRow: 0, space: space,
                           bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    opaque.draw(context.makeImage()!, in: CGRect(x: 0, y: 0, width: width, height: height))
    let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, opaque.makeImage()!, nil)
    guard CGImageDestinationFinalize(destination) else { fatalError("could not write \(url.path)") }
    print("wrote \(url.path)")
}
