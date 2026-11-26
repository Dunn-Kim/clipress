// 앱 아이콘을 그려 assets/AppIcon.icns를 만든다: swift scripts/make-icon.swift [미리보기.png]
// 크기마다 벡터에서 다시 그려 작은 아이콘도 선명하게 한다.
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func linear(_ ctx: CGContext, _ path: CGPath, _ top: UInt32, _ bottom: UInt32, from y0: CGFloat, to y1: CGFloat) {
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [rgb(top), rgb(bottom)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: y0), end: CGPoint(x: 0, y: y1), options: [])
    ctx.restoreGState()
}

/// 1024×1024, y축 아래 방향 좌표계에서 그린다. macOS 아이콘 격자: 824px 스퀘어클, 사방 100px 여백.
func drawIcon(_ ctx: CGContext, scale: CGFloat) {
    // 배경 스퀘어클 + 아래 그림자
    let tile = CGPath(roundedRect: CGRect(x: 100, y: 100, width: 824, height: 824), cornerWidth: 185, cornerHeight: 185, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10 * scale), blur: 24 * scale, color: rgb(0x000000, 0.35))
    ctx.addPath(tile)
    ctx.setFillColor(rgb(0x1B1E23))
    ctx.fillPath()
    ctx.restoreGState()
    linear(ctx, tile, 0x3A3F48, 0x16181C, from: 100, to: 924)

    // 비디오 클립: 주황 프레임, 위아래 필름 구멍, 재생 삼각형
    let clip = CGRect(x: 288, y: 356, width: 448, height: 312)
    let clipPath = CGPath(roundedRect: clip, cornerWidth: 46, cornerHeight: 46, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -6 * scale), blur: 18 * scale, color: rgb(0x000000, 0.45))
    ctx.addPath(clipPath)
    ctx.setFillColor(rgb(0xF2542D))
    ctx.fillPath()
    ctx.restoreGState()
    linear(ctx, clipPath, 0xFF9A4D, 0xEE4B2B, from: clip.minY, to: clip.maxY)

    ctx.setFillColor(rgb(0x2A0E06, 0.38))
    let holes = 6, hole = CGSize(width: 36, height: 24), margin: CGFloat = 28
    let gap = (clip.width - 2 * margin - CGFloat(holes) * hole.width) / CGFloat(holes - 1)
    for i in 0..<holes {
        let x = clip.minX + margin + CGFloat(i) * (hole.width + gap)
        for y in [clip.minY + 16, clip.maxY - 16 - hole.height] {
            ctx.addPath(CGPath(roundedRect: CGRect(origin: CGPoint(x: x, y: y), size: hole), cornerWidth: 7, cornerHeight: 7, transform: nil))
        }
    }
    ctx.fillPath()

    let play = CGMutablePath()
    play.move(to: CGPoint(x: 476, y: 454))
    play.addLine(to: CGPoint(x: 476, y: 570))
    play.addLine(to: CGPoint(x: 576, y: 512))
    play.closeSubpath()
    ctx.addPath(play)
    ctx.setLineJoin(.round)
    ctx.setLineWidth(18)
    ctx.setStrokeColor(rgb(0xFFF6EC))
    ctx.setFillColor(rgb(0xFFF6EC))
    ctx.drawPath(using: .fillStroke)

    // 네 모서리 브래킷과 안쪽을 향한 화살표: 클립을 사방에서 눌러 압축한다
    let frame = clip.insetBy(dx: -48, dy: -48)
    let arm: CGFloat = 108
    let corners: [(CGPoint, CGFloat, CGFloat)] = [
        (CGPoint(x: frame.minX, y: frame.minY), 1, 1), (CGPoint(x: frame.maxX, y: frame.minY), -1, 1),
        (CGPoint(x: frame.minX, y: frame.maxY), 1, -1), (CGPoint(x: frame.maxX, y: frame.maxY), -1, -1),
    ]
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.setStrokeColor(rgb(0xF4EFE8))
    ctx.setLineWidth(40)
    for (p, dx, dy) in corners {
        ctx.move(to: CGPoint(x: p.x, y: p.y + dy * arm))
        ctx.addLine(to: p)
        ctx.addLine(to: CGPoint(x: p.x + dx * arm, y: p.y))
    }
    ctx.strokePath()

    ctx.setStrokeColor(rgb(0xFF8A45))
    ctx.setLineWidth(20)
    for (p, dx, dy) in corners {
        let tip = CGPoint(x: p.x - dx * 30, y: p.y - dy * 30)
        let tail = CGPoint(x: tip.x - dx * 48, y: tip.y - dy * 48)
        ctx.move(to: tail)
        ctx.addLine(to: tip)
        ctx.move(to: CGPoint(x: tip.x - dx * 30, y: tip.y))
        ctx.addLine(to: tip)
        ctx.addLine(to: CGPoint(x: tip.x, y: tip.y - dy * 30))
    }
    ctx.strokePath()
}

func png(size: Int, to url: URL) throws {
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let scale = CGFloat(size) / 1024
    ctx.translateBy(x: 0, y: CGFloat(size))
    ctx.scaleBy(x: scale, y: -scale)
    drawIcon(ctx, scale: scale)
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
    guard CGImageDestinationFinalize(dest) else { throw CocoaError(.fileWriteUnknown) }
}

let root = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let iconset = FileManager.default.temporaryDirectory.appending(path: "AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try png(size: base, to: iconset.appending(path: "icon_\(base)x\(base).png"))
    try png(size: base * 2, to: iconset.appending(path: "icon_\(base)x\(base)@2x.png"))
}
if CommandLine.arguments.count > 1 { try png(size: 1024, to: URL(filePath: CommandLine.arguments[1])) }

let assets = root.appending(path: "assets")
try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
let iconutil = try Process.run(URL(filePath: "/usr/bin/iconutil"), arguments: ["-c", "icns", iconset.path, "-o", assets.appending(path: "AppIcon.icns").path])
iconutil.waitUntilExit()
try? FileManager.default.removeItem(at: iconset)
guard iconutil.terminationStatus == 0 else { fatalError("iconutil 실패") }
print(assets.appending(path: "AppIcon.icns").path)
