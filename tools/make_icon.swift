import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

let size = 1024
let pixels = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
let context = NSGraphicsContext(cgContext: pixels, flipped: false)
NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
NSColor(red: 1, green: 0.975, blue: 0.933, alpha: 1).setFill()
NSBezierPath(rect: NSRect(x: 0, y: 0, width: size, height: size)).fill()
let circle = NSBezierPath(ovalIn: NSRect(x: 156, y: 156, width: 712, height: 712))
NSGradient(colors: [NSColor(red: 1, green: 0.93, blue: 0.71, alpha: 1), NSColor(red: 1, green: 0.56, blue: 0.32, alpha: 1), NSColor(red: 0.81, green: 0.68, blue: 0.91, alpha: 1)])!.draw(in: circle, angle: -50)
NSGraphicsContext.saveGraphicsState(); circle.addClip()
NSGradient(starting: NSColor.white.withAlphaComponent(0.55), ending: NSColor.white.withAlphaComponent(0))!.draw(fromCenter: NSPoint(x: 370, y: 760), radius: 0, toCenter: NSPoint(x: 420, y: 680), radius: 380, options: [])
NSGraphicsContext.restoreGraphicsState()
NSColor(red: 1, green: 0.73, blue: 0.47, alpha: 1).setFill()
NSBezierPath(ovalIn: NSRect(x: 860, y: 756, width: 44, height: 44)).fill()
NSGraphicsContext.restoreGraphicsState()
let output = URL(fileURLWithPath: CommandLine.arguments[1])
let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(destination, pixels.makeImage()!, nil)
guard CGImageDestinationFinalize(destination) else { fatalError("Could not save app icon") }
print("Created TideEnglish app icon")
