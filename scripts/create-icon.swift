import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// Convert the canonical full-bleed artwork to iOS’s opaque 1024px icon.
// No logo geometry or colors are redrawn by this packaging step.
let size = 1024
guard CommandLine.arguments.count == 3,
      let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: CommandLine.arguments[1]) as CFURL, nil),
      let artwork = CGImageSourceCreateImageAtIndex(source, 0, nil),
      artwork.width == artwork.height,
      let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
      let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                              bytesPerRow: size * 4, space: colorSpace,
                              bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
    fatalError("Provide a square icon master and output PNG path")
}
context.interpolationQuality = .high
context.draw(artwork, in: CGRect(x: 0, y: 0, width: size, height: size))
guard let image = context.makeImage(),
      let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: CommandLine.arguments[2]) as CFURL,
                                                       UTType.png.identifier as CFString, 1, nil) else {
    fatalError("Could not create PNG")
}
CGImageDestinationAddImage(destination, image, nil)
guard CGImageDestinationFinalize(destination) else { fatalError("Could not write PNG") }
