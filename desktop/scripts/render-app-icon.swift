#!/usr/bin/env swift

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

guard CommandLine.arguments.count == 3 else {
    fputs("Usage: render-app-icon.swift INPUT OUTPUT\n", stderr)
    exit(64)
}

let inputURL = URL(fileURLWithPath: CommandLine.arguments[1])
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])

guard
    let source = CGImageSourceCreateWithURL(inputURL as CFURL, nil),
    let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
    let context = CGContext(
        data: nil,
        width: 1_024,
        height: 1_024,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )
else {
    fputs("Could not read or prepare the icon image.\n", stderr)
    exit(1)
}

let canvas = CGRect(x: 0, y: 0, width: 1_024, height: 1_024)
let tile = canvas.insetBy(dx: 42, dy: 42)
let tilePath = CGPath(
    roundedRect: tile,
    cornerWidth: 205,
    cornerHeight: 205,
    transform: nil
)

context.clear(canvas)
context.saveGState()
context.setShadow(
    offset: CGSize(width: 0, height: -8),
    blur: 18,
    color: CGColor(gray: 0, alpha: 0.34)
)
context.addPath(tilePath)
context.setFillColor(CGColor(gray: 0.05, alpha: 1))
context.fillPath()
context.restoreGState()

context.saveGState()
context.addPath(tilePath)
context.clip()
context.draw(image, in: canvas)
context.restoreGState()

guard let rendered = context.makeImage() else {
    fputs("Could not render the icon image.\n", stderr)
    exit(1)
}

try FileManager.default.createDirectory(
    at: outputURL.deletingLastPathComponent(),
    withIntermediateDirectories: true
)
guard let destination = CGImageDestinationCreateWithURL(
    outputURL as CFURL,
    UTType.png.identifier as CFString,
    1,
    nil
) else {
    fputs("Could not create the output icon.\n", stderr)
    exit(1)
}
CGImageDestinationAddImage(destination, rendered, nil)
guard CGImageDestinationFinalize(destination) else {
    fputs("Could not write the output icon.\n", stderr)
    exit(1)
}
