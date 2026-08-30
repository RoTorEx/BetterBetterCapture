#!/usr/bin/env swift

import AppKit
import Foundation

private enum IconGeometry {
    static let canvas: CGFloat = 1024
    static let symbolBounds = CGRect(x: 218, y: 267, width: 606, height: 490)
    static let teal = NSColor(
        calibratedRed: 0 / 255,
        green: 174 / 255,
        blue: 189 / 255,
        alpha: 1
    ).cgColor

    static func drawSymbol(in context: CGContext, color: CGColor) {
        context.saveGState()
        context.setStrokeColor(color)
        context.setLineWidth(64)
        context.setLineCap(.round)
        context.setLineJoin(.round)

        let screen = CGMutablePath()
        screen.move(to: CGPoint(x: 452, y: 326))
        screen.addLine(to: CGPoint(x: 306, y: 326))
        screen.addCurve(
            to: CGPoint(x: 250, y: 382),
            control1: CGPoint(x: 275, y: 326),
            control2: CGPoint(x: 250, y: 351)
        )
        screen.addLine(to: CGPoint(x: 250, y: 642))
        screen.addCurve(
            to: CGPoint(x: 306, y: 698),
            control1: CGPoint(x: 250, y: 673),
            control2: CGPoint(x: 275, y: 698)
        )
        screen.addLine(to: CGPoint(x: 452, y: 698))
        context.addPath(screen)
        context.strokePath()

        drawBar(in: context, x: 540, bottom: 299, top: 725)
        drawBar(in: context, x: 665, bottom: 390, top: 660)
        drawBar(in: context, x: 792, bottom: 480, top: 570)
        context.restoreGState()
    }

    private static func drawBar(
        in context: CGContext,
        x: CGFloat,
        bottom: CGFloat,
        top: CGFloat
    ) {
        context.move(to: CGPoint(x: x, y: bottom))
        context.addLine(to: CGPoint(x: x, y: top))
        context.strokePath()
    }
}

private struct PNGRenderer {
    let repositoryRoot: URL

    func renderAll() throws {
        let appIconDirectory = repositoryRoot
            .appendingPathComponent("BetterBetterCapture/Assets.xcassets/BetterBetterCapture.appiconset")
        let menuIconDirectory = repositoryRoot
            .appendingPathComponent("BetterBetterCapture/Assets.xcassets/MenuBarIcon.imageset")

        let appIcons: [(filename: String, pixels: Int)] = [
            ("icon_16x16.png", 16),
            ("icon_16x16@2x.png", 32),
            ("icon_32x32.png", 32),
            ("icon_32x32@2x.png", 64),
            ("icon_128x128.png", 128),
            ("icon_128x128@2x.png", 256),
            ("icon_256x256.png", 256),
            ("icon_256x256@2x.png", 512),
            ("icon_512x512.png", 512),
            ("icon_512x512@2x.png", 1024),
        ]

        for icon in appIcons {
            let data = try renderPNG(pixels: icon.pixels) { context in
                let scale = CGFloat(icon.pixels) / IconGeometry.canvas
                context.scaleBy(x: scale, y: scale)
                context.setFillColor(IconGeometry.teal)
                context.addPath(
                    CGPath(
                        roundedRect: CGRect(x: 64, y: 64, width: 896, height: 896),
                        cornerWidth: 205,
                        cornerHeight: 205,
                        transform: nil
                    )
                )
                context.fillPath()
                IconGeometry.drawSymbol(in: context, color: NSColor.white.cgColor)
            }
            try data.write(
                to: appIconDirectory.appendingPathComponent(icon.filename),
                options: .atomic
            )
        }

        for icon in [(filename: "menubar-icon.png", pixels: 18),
                     (filename: "menubar-icon@2x.png", pixels: 36)] {
            let data = try renderPNG(pixels: icon.pixels) { context in
                let availableWidth = CGFloat(icon.pixels) - 4
                let availableHeight = CGFloat(icon.pixels) - 5
                let scale = min(
                    availableWidth / IconGeometry.symbolBounds.width,
                    availableHeight / IconGeometry.symbolBounds.height
                )
                let renderedWidth = IconGeometry.symbolBounds.width * scale
                let renderedHeight = IconGeometry.symbolBounds.height * scale

                context.translateBy(
                    x: (CGFloat(icon.pixels) - renderedWidth) / 2,
                    y: (CGFloat(icon.pixels) - renderedHeight) / 2
                )
                context.scaleBy(x: scale, y: scale)
                context.translateBy(
                    x: -IconGeometry.symbolBounds.minX,
                    y: -IconGeometry.symbolBounds.minY
                )
                IconGeometry.drawSymbol(in: context, color: NSColor.black.cgColor)
            }
            try data.write(
                to: menuIconDirectory.appendingPathComponent(icon.filename),
                options: .atomic
            )
        }
    }

    private func renderPNG(
        pixels: Int,
        draw: (CGContext) -> Void
    ) throws -> Data {
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixels,
            pixelsHigh: pixels,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ), let graphicsContext = NSGraphicsContext(bitmapImageRep: bitmap) else {
            throw CocoaError(.fileWriteUnknown)
        }

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = graphicsContext

        let context = graphicsContext.cgContext
        context.clear(CGRect(x: 0, y: 0, width: pixels, height: pixels))
        context.setAllowsAntialiasing(true)
        context.setShouldAntialias(true)
        draw(context)
        graphicsContext.flushGraphics()

        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        return data
    }
}

private let rootPath = CommandLine.arguments.dropFirst().first
    ?? FileManager.default.currentDirectoryPath
private let renderer = PNGRenderer(repositoryRoot: URL(fileURLWithPath: rootPath))

do {
    try renderer.renderAll()
    print("Rendered selected BetterBetterCapture app and menu-bar icons.")
} catch {
    FileHandle.standardError.write(Data("Icon rendering failed: \(error)\n".utf8))
    exit(1)
}
