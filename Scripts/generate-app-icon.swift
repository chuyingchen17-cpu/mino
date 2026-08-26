#!/usr/bin/env swift

import AppKit
import Foundation

private enum IconGeneratorError: Error, CustomStringConvertible {
    case missingOutputDirectory
    case missingFrame(String)
    case unreadableFrame(String)
    case bitmapCreationFailed(Int)
    case pngEncodingFailed(Int)

    var description: String {
        switch self {
        case .missingOutputDirectory:
            return "Usage: generate-app-icon.swift <Mino.iconset directory>"
        case let .missingFrame(character):
            return "No welcome or idle icon frame exists for \(character)."
        case let .unreadableFrame(path):
            return "Could not read pixel frame at \(path)."
        case let .bitmapCreationFailed(size):
            return "Could not create a \(size)x\(size) bitmap."
        case let .pngEncodingFailed(size):
            return "Could not encode the \(size)x\(size) icon as PNG."
        }
    }
}

private extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            calibratedRed: CGFloat((hex >> 16) & 0xff) / 255,
            green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255,
            alpha: alpha
        )
    }
}

private struct PixelFrame {
    let image: NSImage
    let visibleBounds: NSRect

    init(url: URL) throws {
        guard let data = try? Data(contentsOf: url),
              let bitmap = NSBitmapImageRep(data: data)
        else {
            throw IconGeneratorError.unreadableFrame(url.path)
        }

        let width = bitmap.pixelsWide
        let height = bitmap.pixelsHigh
        var minX = width
        var minY = height
        var maxX = -1
        var maxY = -1

        for y in 0..<height {
            for x in 0..<width where (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.01 {
                minX = min(minX, x)
                minY = min(minY, y)
                maxX = max(maxX, x)
                maxY = max(maxY, y)
            }
        }

        guard maxX >= minX, maxY >= minY else {
            throw IconGeneratorError.unreadableFrame(url.path)
        }

        image = NSImage(size: NSSize(width: width, height: height))
        image.addRepresentation(bitmap)

        let padding = 2
        let paddedMinX = max(0, minX - padding)
        let paddedMinY = max(0, minY - padding)
        let paddedMaxX = min(width - 1, maxX + padding)
        let paddedMaxY = min(height - 1, maxY + padding)
        visibleBounds = NSRect(
            x: paddedMinX,
            // colorAt(x:y:) scans bitmap rows top-down while NSImage's source
            // rectangle is expressed bottom-up.
            y: height - 1 - paddedMaxY,
            width: paddedMaxX - paddedMinX + 1,
            height: paddedMaxY - paddedMinY + 1
        )
    }

    func drawPixelAligned(in target: NSRect) {
        let fittedScale = min(target.width / visibleBounds.width, target.height / visibleBounds.height)
        let fittedSize = NSSize(
            width: floor(visibleBounds.width * fittedScale),
            height: floor(visibleBounds.height * fittedScale)
        )
        let destination = NSRect(
            x: floor(target.midX - fittedSize.width / 2),
            y: floor(target.minY),
            width: fittedSize.width,
            height: fittedSize.height
        )

        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(
            in: destination,
            from: visibleBounds,
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: false,
            hints: [.interpolation: NSImageInterpolation.high]
        )
    }
}

private let cream = NSColor(hex: 0xFFF8EF)
private let creamShade = NSColor(hex: 0xF6E7D7)
private let coral = NSColor(hex: 0xFF625F)
private let coralHighlight = NSColor(hex: 0xFF9189)
private let groundShadow = NSColor(hex: 0x6D5042, alpha: 0.14)

private func loadCharacterFrame(projectDirectory: URL, character: String) throws -> PixelFrame {
    let root = projectDirectory
        .appendingPathComponent("Sources/MinoPresentation/Resources/PetFrames", isDirectory: true)
        .appendingPathComponent(character, isDirectory: true)
    let candidates = [
        root.appendingPathComponent("welcome/frame-002.png"),
        root.appendingPathComponent("welcome/frame-000.png"),
        root.appendingPathComponent("idle/frame-000.png"),
    ]
    guard let selected = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) else {
        throw IconGeneratorError.missingFrame(character)
    }
    return try PixelFrame(url: selected)
}

private func drawBackground(size: CGFloat, in context: CGContext) {
    let inset = floor(size * 0.052)
    let tile = NSBezierPath(
        roundedRect: NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2),
        xRadius: size * 0.21,
        yRadius: size * 0.21
    )

    context.saveGState()
    context.setShadow(
        offset: CGSize(width: 0, height: -size * 0.021),
        blur: size * 0.027,
        color: groundShadow.cgColor
    )
    cream.setFill()
    tile.fill()
    context.restoreGState()

    context.saveGState()
    tile.addClip()
    let gradient = NSGradient(starting: cream, ending: creamShade)!
    gradient.draw(from: NSPoint(x: size / 2, y: size - inset), to: NSPoint(x: size / 2, y: inset), options: [])
    context.restoreGState()
}

private func drawGroundShadow(in rect: NSRect) {
    groundShadow.setFill()
    NSBezierPath(ovalIn: rect).fill()
}

private func drawPixelHeart(size: CGFloat) {
    // Seven columns preserve a deliberate pixel silhouette even in the 16 px icon.
    let unit = max(1, floor(size * 0.014))
    let rows = [
        "0110110",
        "1111111",
        "1111111",
        "0111110",
        "0011100",
        "0001000",
    ]
    let origin = NSPoint(x: floor(size / 2 - unit * 3.5), y: floor(size * 0.755))

    for (rowIndex, row) in rows.reversed().enumerated() {
        for (columnIndex, pixel) in row.enumerated() where pixel == "1" {
            let color = rowIndex >= rows.count - 2 ? coralHighlight : coral
            color.setFill()
            NSBezierPath(
                rect: NSRect(
                    x: origin.x + CGFloat(columnIndex) * unit,
                    y: origin.y + CGFloat(rowIndex) * unit,
                    width: unit,
                    height: unit
                )
            ).fill()
        }
    }
}

private func makeIcon(size: Int, maltese: PixelFrame, retriever: PixelFrame) throws -> Data {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ), let graphicsContext = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw IconGeneratorError.bitmapCreationFailed(size)
    }

    bitmap.size = NSSize(width: size, height: size)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = graphicsContext
    let side = CGFloat(size)
    let context = graphicsContext.cgContext
    context.setAllowsAntialiasing(true)
    context.setShouldAntialias(true)

    drawBackground(size: side, in: context)

    let shadowY = floor(side * 0.267)
    let shadowWidth = floor(side * 0.32)
    let shadowHeight = max(1, floor(side * 0.055))
    drawGroundShadow(in: NSRect(x: floor(side * 0.115), y: shadowY, width: shadowWidth, height: shadowHeight))
    drawGroundShadow(in: NSRect(x: floor(side * 0.565), y: shadowY, width: shadowWidth, height: shadowHeight))

    let characterSide = floor(side * 0.40)
    let characterY = floor(side * 0.285)
    maltese.drawPixelAligned(
        in: NSRect(x: floor(side * 0.085), y: characterY, width: characterSide, height: characterSide)
    )
    retriever.drawPixelAligned(
        in: NSRect(x: floor(side * 0.515), y: characterY, width: characterSide, height: characterSide)
    )
    drawPixelHeart(size: side)

    NSGraphicsContext.restoreGraphicsState()
    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        throw IconGeneratorError.pngEncodingFailed(size)
    }
    return data
}

private let variants: [(filename: String, pixels: Int)] = [
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

do {
    guard CommandLine.arguments.count == 2 else {
        throw IconGeneratorError.missingOutputDirectory
    }

    let scriptURL = URL(fileURLWithPath: #filePath)
    let repositoryRoot = scriptURL.deletingLastPathComponent().deletingLastPathComponent()
    let projectDirectory = repositoryRoot.appendingPathComponent("apps/macos", isDirectory: true)
    let outputDirectory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
    let maltese = try loadCharacterFrame(projectDirectory: projectDirectory, character: "maltese-white")
    let retriever = try loadCharacterFrame(projectDirectory: projectDirectory, character: "retriever-yellow")

    try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
    for variant in variants {
        let data = try makeIcon(size: variant.pixels, maltese: maltese, retriever: retriever)
        try data.write(to: outputDirectory.appendingPathComponent(variant.filename), options: .atomic)
    }
    print("Generated \(variants.count) pixel-frame Mino app icon variants in \(outputDirectory.path)")
} catch {
    fputs("generate-app-icon: \(error)\n", stderr)
    exit(2)
}
