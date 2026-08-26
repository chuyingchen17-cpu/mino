#!/usr/bin/env swift

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

private enum ImportError: Error, CustomStringConvertible {
    case invalidArguments
    case unreadableImage(URL)
    case bitmapCreationFailed
    case pngDestinationFailed(URL)

    var description: String {
        switch self {
        case .invalidArguments:
            return "Usage: import-pet-frame-sheets.swift <source directory> <PetFrames output directory>"
        case let .unreadableImage(url):
            return "Could not read image at \(url.path)"
        case .bitmapCreationFailed:
            return "Could not create an RGBA bitmap."
        case let .pngDestinationFailed(url):
            return "Could not write PNG at \(url.path)"
        }
    }
}

private struct RGBAImage {
    let width: Int
    let height: Int
    var pixels: [UInt8]

    init(width: Int, height: Int, pixels: [UInt8]? = nil) {
        self.width = width
        self.height = height
        self.pixels = pixels ?? [UInt8](repeating: 0, count: width * height * 4)
    }

    subscript(x: Int, y: Int, channel: Int) -> UInt8 {
        get { pixels[((y * width) + x) * 4 + channel] }
        set { pixels[((y * width) + x) * 4 + channel] = newValue }
    }
}

private enum SheetKind {
    case base
    case actions
}

private struct FrameSource {
    let sheet: SheetKind
    let index: Int
}

private struct CharacterSource {
    let id: String
    let base: URL
    let actions: URL
    let removesLightBackground: Bool
    let bodyPixel: (UInt8, UInt8, UInt8) -> Bool
}

private let logicalCanvasSize = 120
private let pixelScale = 2
private let canvasSize = logicalCanvasSize * pixelScale
private let targetBodyCenterX = 60 * pixelScale
// Generated sheets are decoded top-to-bottom. Keeping the body-fill baseline at
// y=99 leaves the 2-3 px outline on the public manifest's y=102 ground anchor.
private let targetBodyFillBottomY = 99 * pixelScale
private let loopingClips: Set<String> = ["idle", "walk", "sleep"]

private let sequences: [(clip: String, frames: [FrameSource])] = [
    ("idle", [.init(sheet: .base, index: 0), .init(sheet: .base, index: 1), .init(sheet: .base, index: 2), .init(sheet: .base, index: 3)]),
    ("walk", [.init(sheet: .base, index: 4), .init(sheet: .base, index: 5), .init(sheet: .base, index: 6), .init(sheet: .base, index: 7)]),
    // The generated base sheet also explored a literal human hand. It breaks
    // the closed white silhouette and reads too literally in a cursor-driven
    // desktop pet, so the production sequence uses the heart + shy/blush poses.
    ("pet_receive", [.init(sheet: .base, index: 8), .init(sheet: .actions, index: 0), .init(sheet: .actions, index: 5), .init(sheet: .base, index: 8)]),
    ("eat", [.init(sheet: .base, index: 0), .init(sheet: .base, index: 12), .init(sheet: .base, index: 12), .init(sheet: .base, index: 0)]),
    ("play", [.init(sheet: .base, index: 0), .init(sheet: .base, index: 13), .init(sheet: .base, index: 13), .init(sheet: .base, index: 0)]),
    ("sleep", [.init(sheet: .base, index: 14), .init(sheet: .base, index: 14)]),
    ("shy", [.init(sheet: .actions, index: 0), .init(sheet: .actions, index: 5), .init(sheet: .actions, index: 0), .init(sheet: .actions, index: 5)]),
    ("happy", [.init(sheet: .base, index: 0), .init(sheet: .actions, index: 1), .init(sheet: .actions, index: 1), .init(sheet: .base, index: 0)]),
    ("tired_refuse", [.init(sheet: .base, index: 0), .init(sheet: .actions, index: 2), .init(sheet: .actions, index: 2), .init(sheet: .base, index: 0)]),
    ("full_refuse", [.init(sheet: .base, index: 0), .init(sheet: .actions, index: 3), .init(sheet: .actions, index: 3), .init(sheet: .base, index: 0)]),
    ("cuddle_give", [.init(sheet: .base, index: 0), .init(sheet: .actions, index: 4), .init(sheet: .actions, index: 10), .init(sheet: .base, index: 0)]),
    ("cuddle_receive", [.init(sheet: .base, index: 0), .init(sheet: .actions, index: 5), .init(sheet: .actions, index: 11), .init(sheet: .base, index: 0)]),
    ("flower_give", [.init(sheet: .base, index: 0), .init(sheet: .actions, index: 6), .init(sheet: .actions, index: 12), .init(sheet: .base, index: 0)]),
    ("flower_receive", [.init(sheet: .base, index: 0), .init(sheet: .actions, index: 7), .init(sheet: .actions, index: 13), .init(sheet: .base, index: 0)]),
    ("letter_give", [.init(sheet: .base, index: 0), .init(sheet: .actions, index: 8), .init(sheet: .actions, index: 14), .init(sheet: .base, index: 0)]),
    ("wave", [.init(sheet: .base, index: 0), .init(sheet: .base, index: 15), .init(sheet: .actions, index: 15), .init(sheet: .base, index: 0)]),
    ("welcome", [.init(sheet: .base, index: 0), .init(sheet: .actions, index: 9), .init(sheet: .actions, index: 15), .init(sheet: .base, index: 0)])
]

private func decode(_ url: URL) throws -> RGBAImage {
    guard
        let source = CGImageSourceCreateWithURL(url as CFURL, nil),
        let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else {
        throw ImportError.unreadableImage(url)
    }

    var result = RGBAImage(width: image.width, height: image.height)
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    guard let context = CGContext(
        data: &result.pixels,
        width: result.width,
        height: result.height,
        bitsPerComponent: 8,
        bytesPerRow: result.width * 4,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
    ) else {
        throw ImportError.bitmapCreationFailed
    }

    // CGImageDestination interprets the first bitmap row as the visual top.
    // Drawing without an extra coordinate flip keeps the imported sheet in the
    // same orientation when the raw buffer is encoded again.
    context.interpolationQuality = .high
    context.draw(image, in: CGRect(x: 0, y: 0, width: result.width, height: result.height))
    return result
}

private func makeCGImage(_ image: RGBAImage) -> CGImage? {
    let data = Data(image.pixels)
    guard let provider = CGDataProvider(data: data as CFData) else { return nil }
    return CGImage(
        width: image.width,
        height: image.height,
        bitsPerComponent: 8,
        bitsPerPixel: 32,
        bytesPerRow: image.width * 4,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGBitmapInfo(
            rawValue: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        ),
        provider: provider,
        decode: nil,
        shouldInterpolate: true,
        intent: .defaultIntent
    )
}

private func extractCell(_ source: RGBAImage, index: Int) -> RGBAImage {
    let column = index % 4
    let row = index / 4
    let minX = column * source.width / 4
    let maxX = (column + 1) * source.width / 4
    let minY = row * source.height / 4
    let maxY = (row + 1) * source.height / 4
    let cellWidth = maxX - minX
    let cellHeight = maxY - minY
    var cell = RGBAImage(width: cellWidth, height: cellHeight)
    for y in 0..<cellHeight {
        for x in 0..<cellWidth {
            for channel in 0..<4 {
                cell[x, y, channel] = source[minX + x, minY + y, channel]
            }
        }
    }

    var result = RGBAImage(width: canvasSize, height: canvasSize)
    guard let cellImage = makeCGImage(cell) else { return result }
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    result.pixels.withUnsafeMutableBytes { buffer in
        guard let context = CGContext(
            data: buffer.baseAddress,
            width: canvasSize,
            height: canvasSize,
            bitsPerComponent: 8,
            bytesPerRow: canvasSize * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        ) else {
            return
        }
        context.interpolationQuality = .high
        let inset = 16
        let renderSize = canvasSize - inset * 2
        context.draw(
            cellImage,
            in: CGRect(x: inset, y: inset, width: renderSize, height: renderSize)
        )
    }
    return result
}

private func blend(_ first: RGBAImage, _ second: RGBAImage, t: Double) -> RGBAImage {
    var result = RGBAImage(width: first.width, height: first.height)
    let keep = 1 - t
    for index in 0..<first.pixels.count {
        let mixed = Double(first.pixels[index]) * keep + Double(second.pixels[index]) * t
        result.pixels[index] = UInt8(min(255, mixed.rounded()))
    }
    return result
}

private func expandedFrames(_ frames: [RGBAImage], loops: Bool) -> [RGBAImage] {
    guard frames.count >= 2 else { return frames }
    var result: [RGBAImage] = []
    result.reserveCapacity(frames.count * 2)
    for index in 0..<frames.count {
        result.append(frames[index])
        let next = index + 1
        if next < frames.count {
            result.append(blend(frames[index], frames[next], t: 0.5))
        } else if loops {
            result.append(blend(frames[index], frames[0], t: 0.5))
        }
    }
    return result
}

private func removeConnectedLightBackground(from image: inout RGBAImage) {
    func isLight(_ x: Int, _ y: Int) -> Bool {
        let r = Int(image[x, y, 0])
        let g = Int(image[x, y, 1])
        let b = Int(image[x, y, 2])
        let a = image[x, y, 3]
        return a > 0 && min(r, g, b) >= 205 && max(r, g, b) - min(r, g, b) <= 12
    }

    let count = image.width * image.height
    // The source sheet's checkerboard is baked RGB. Build a closed outline mask
    // from dark/accent pixels first; closing one-pixel generation gaps prevents
    // the exterior flood from leaking into the white body.
    var barrier = [Bool](repeating: false, count: count)
    for y in 0..<image.height {
        for x in 0..<image.width {
            barrier[y * image.width + x] = image[x, y, 3] > 0 && !isLight(x, y)
        }
    }

    let radius = 2
    var dilated = [Bool](repeating: false, count: count)
    for y in 0..<image.height {
        for x in 0..<image.width {
            var found = false
            for offsetY in -radius...radius where !found {
                for offsetX in -radius...radius {
                    let sampleX = x + offsetX
                    let sampleY = y + offsetY
                    guard sampleX >= 0, sampleX < image.width, sampleY >= 0, sampleY < image.height else { continue }
                    if barrier[sampleY * image.width + sampleX] {
                        found = true
                        break
                    }
                }
            }
            dilated[y * image.width + x] = found
        }
    }

    var closedBarrier = [Bool](repeating: false, count: count)
    for y in 0..<image.height {
        for x in 0..<image.width {
            var allSet = true
            for offsetY in -radius...radius where allSet {
                for offsetX in -radius...radius {
                    let sampleX = x + offsetX
                    let sampleY = y + offsetY
                    if sampleX < 0 || sampleX >= image.width || sampleY < 0 || sampleY >= image.height || !dilated[sampleY * image.width + sampleX] {
                        allSet = false
                        break
                    }
                }
            }
            closedBarrier[y * image.width + x] = allSet
        }
    }

    var outside = [Bool](repeating: false, count: count)
    var queue: [(Int, Int)] = []
    queue.reserveCapacity(image.width * image.height)

    func enqueue(_ x: Int, _ y: Int) {
        guard x >= 0, x < image.width, y >= 0, y < image.height else { return }
        let offset = y * image.width + x
        guard !outside[offset], !closedBarrier[offset] else { return }
        outside[offset] = true
        queue.append((x, y))
    }

    for x in 0..<image.width {
        enqueue(x, 0)
        enqueue(x, image.height - 1)
    }
    for y in 0..<image.height {
        enqueue(0, y)
        enqueue(image.width - 1, y)
    }

    var cursor = 0
    while cursor < queue.count {
        let (x, y) = queue[cursor]
        cursor += 1
        enqueue(x - 1, y)
        enqueue(x + 1, y)
        enqueue(x, y - 1)
        enqueue(x, y + 1)
    }

    for y in 0..<image.height {
        for x in 0..<image.width where outside[y * image.width + x] && isLight(x, y) {
            let base = ((y * image.width) + x) * 4
            image.pixels[base] = 0
            image.pixels[base + 1] = 0
            image.pixels[base + 2] = 0
            image.pixels[base + 3] = 0
        }
    }
}

private func largestBodyBounds(
    in image: RGBAImage,
    predicate: (UInt8, UInt8, UInt8) -> Bool
) -> (minX: Int, minY: Int, maxX: Int, maxY: Int)? {
    let count = image.width * image.height
    var candidates = [Bool](repeating: false, count: count)
    for y in 0..<image.height {
        for x in 0..<image.width where image[x, y, 3] > 20 {
            candidates[y * image.width + x] = predicate(image[x, y, 0], image[x, y, 1], image[x, y, 2])
        }
    }

    var visited = [Bool](repeating: false, count: count)
    var best: (size: Int, minX: Int, minY: Int, maxX: Int, maxY: Int)?
    for startY in 0..<image.height {
        for startX in 0..<image.width {
            let start = startY * image.width + startX
            guard candidates[start], !visited[start] else { continue }
            visited[start] = true
            var queue = [(startX, startY)]
            var cursor = 0
            var bounds = (minX: startX, minY: startY, maxX: startX, maxY: startY)
            while cursor < queue.count {
                let (x, y) = queue[cursor]
                cursor += 1
                bounds.minX = min(bounds.minX, x)
                bounds.minY = min(bounds.minY, y)
                bounds.maxX = max(bounds.maxX, x)
                bounds.maxY = max(bounds.maxY, y)
                for (nextX, nextY) in [(x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)] {
                    guard nextX >= 0, nextX < image.width, nextY >= 0, nextY < image.height else { continue }
                    let next = nextY * image.width + nextX
                    guard candidates[next], !visited[next] else { continue }
                    visited[next] = true
                    queue.append((nextX, nextY))
                }
            }
            if best == nil || queue.count > best!.size {
                best = (queue.count, bounds.minX, bounds.minY, bounds.maxX, bounds.maxY)
            }
        }
    }
    guard let best else { return nil }
    return (best.minX, best.minY, best.maxX, best.maxY)
}

private func alignBody(
    in image: RGBAImage,
    predicate: (UInt8, UInt8, UInt8) -> Bool
) -> RGBAImage {
    guard let bounds = largestBodyBounds(in: image, predicate: predicate) else { return image }
    let bodyCenterX = (bounds.minX + bounds.maxX) / 2
    let shiftX = targetBodyCenterX - bodyCenterX
    // The retriever's coral collar splits the cream head and torso into two
    // color components. The largest component is often the head, so using its
    // bottom as a baseline sinks the feet below ground. Read the lowest body
    // fill inside the central torso band instead; arms, flowers and letters do
    // not influence this anchor.
    let coreMinX = image.width / 3
    let coreMaxX = image.width * 2 / 3
    var torsoFillBottomY = -1
    for y in 0..<image.height {
        for x in coreMinX...coreMaxX where image[x, y, 3] > 20 {
            if predicate(image[x, y, 0], image[x, y, 1], image[x, y, 2]) {
                torsoFillBottomY = max(torsoFillBottomY, y)
            }
        }
    }
    let shiftY = targetBodyFillBottomY - max(bounds.maxY, torsoFillBottomY)
    var result = RGBAImage(width: image.width, height: image.height)
    for y in 0..<image.height {
        for x in 0..<image.width where image[x, y, 3] > 0 {
            let targetX = x + shiftX
            let targetY = y + shiftY
            guard targetX >= 0, targetX < result.width, targetY >= 0, targetY < result.height else { continue }
            for channel in 0..<4 {
                result[targetX, targetY, channel] = image[x, y, channel]
            }
        }
    }
    return result
}

private func clearSafetyBorder(in image: inout RGBAImage, width: Int = 8) {
    for y in 0..<image.height {
        for x in 0..<image.width where x < width || y < width || x >= image.width - width || y >= image.height - width {
            let base = ((y * image.width) + x) * 4
            image.pixels[base] = 0
            image.pixels[base + 1] = 0
            image.pixels[base + 2] = 0
            image.pixels[base + 3] = 0
        }
    }
}

private func clearBelowGround(in image: inout RGBAImage, groundY: Int = 204) {
    guard groundY + 1 < image.height else { return }
    for y in (groundY + 1)..<image.height {
        for x in 0..<image.width {
            let base = ((y * image.width) + x) * 4
            image.pixels[base] = 0
            image.pixels[base + 1] = 0
            image.pixels[base + 2] = 0
            image.pixels[base + 3] = 0
        }
    }
}

private func compressedSleepBreath(_ image: RGBAImage) -> RGBAImage {
    var minY = image.height
    var maxY = -1
    for y in 0..<image.height {
        for x in 0..<image.width where image[x, y, 3] > 20 {
            minY = min(minY, y)
            maxY = max(maxY, y)
        }
    }
    guard maxY > minY + 2 else { return image }
    let sourceHeight = maxY - minY
    let targetHeight = sourceHeight - 1
    var result = RGBAImage(width: image.width, height: image.height)
    for y in 0..<image.height {
        for x in 0..<image.width where image[x, y, 3] > 0 {
            let distanceFromGround = maxY - y
            let compressedDistance = Int((Double(distanceFromGround) * Double(targetHeight) / Double(sourceHeight)).rounded())
            let targetY = maxY - compressedDistance
            guard targetY >= 0, targetY < result.height else { continue }
            for channel in 0..<4 {
                result[x, targetY, channel] = image[x, y, channel]
            }
        }
    }
    return result
}

private func encode(_ image: RGBAImage, to url: URL) throws {
    let data = Data(image.pixels)
    guard
        let provider = CGDataProvider(data: data as CFData),
        let cgImage = CGImage(
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: image.width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        ),
        let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
    else {
        throw ImportError.pngDestinationFailed(url)
    }
    CGImageDestinationAddImage(destination, cgImage, [kCGImagePropertyPNGInterlaceType: 0] as CFDictionary)
    guard CGImageDestinationFinalize(destination) else {
        throw ImportError.pngDestinationFailed(url)
    }
}

private func render(_ character: CharacterSource, outputRoot: URL) throws -> Int {
    let base = try decode(character.base)
    let actions = try decode(character.actions)
    let fileManager = FileManager.default
    var written = 0
    for sequence in sequences {
        let directory = outputRoot
            .appending(path: character.id, directoryHint: .isDirectory)
            .appending(path: sequence.clip, directoryHint: .isDirectory)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        var keyframes: [RGBAImage] = []
        keyframes.reserveCapacity(sequence.frames.count)
        for (index, source) in sequence.frames.enumerated() {
            var frame = extractCell(source.sheet == .base ? base : actions, index: source.index)
            if character.removesLightBackground {
                removeConnectedLightBackground(from: &frame)
            }
            frame = alignBody(in: frame, predicate: character.bodyPixel)
            if sequence.clip == "sleep", index == 1 {
                frame = compressedSleepBreath(frame)
            }
            // The public ground anchor is a hard content boundary, not merely
            // a placement hint. Effects and source-sheet alpha below y=102
            // would make different clips appear to change their foot baseline.
            clearBelowGround(in: &frame)
            // Some generated transparent sheets contain barely-visible alpha
            // noise outside the character. The runtime treats any edge alpha
            // as an invalid atlas because it can clip while mirroring, so every
            // exported frame owns an explicit transparent safety border.
            clearSafetyBorder(in: &frame)
            keyframes.append(frame)
        }
        let frames = expandedFrames(
            keyframes,
            loops: loopingClips.contains(sequence.clip)
        )
        for (index, frame) in frames.enumerated() {
            let destination = directory.appending(path: String(format: "frame-%03d.png", index))
            try encode(frame, to: destination)
            written += 1
        }
    }
    return written
}

do {
    guard CommandLine.arguments.count == 3 else { throw ImportError.invalidArguments }
    let sourceRoot = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
    let outputRoot = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
    let characters = [
        CharacterSource(
            id: "maltese-white",
            base: sourceRoot.appending(path: "maltese-base-v1.png"),
            actions: sourceRoot.appending(path: "maltese-actions-v1.png"),
            removesLightBackground: true,
            bodyPixel: { r, g, b in min(r, g, b) > 220 && Int(max(r, g, b)) - Int(min(r, g, b)) < 38 }
        ),
        CharacterSource(
            id: "retriever-yellow",
            base: sourceRoot.appending(path: "retriever-base-v1.png"),
            actions: sourceRoot.appending(path: "retriever-actions-v1.png"),
            removesLightBackground: false,
            bodyPixel: { r, g, b in r > 190 && g > 145 && b < 225 && r >= g }
        )
    ]
    var total = 0
    for character in characters {
        total += try render(character, outputRoot: outputRoot)
    }
    print("Generated \(total) fixed-canvas pet frames in \(outputRoot.path)")
} catch {
    fputs("\(error)\n", stderr)
    exit(1)
}
