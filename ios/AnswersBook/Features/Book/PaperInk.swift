import SwiftUI
import CoreGraphics

/// 同一个稳定的多尺度噪声场作用于整组笔画；不按字符或横向顺序显现。
private enum InkField {
    static let width = 320
    static let height = 128
    static func hash(_ x: Int, _ y: Int) -> Double {
        var value = UInt64(bitPattern: Int64(x &* 374761393 &+ y &* 668265263))
        value = (value ^ (value >> 13)) &* 1274126177
        return Double(value & 65535) / 65535
    }
    static func noise(_ x: Double, _ y: Double) -> Double {
        let ix = Int(floor(x)), iy = Int(floor(y))
        let fx = x - floor(x), fy = y - floor(y)
        let sx = fx * fx * (3 - 2 * fx), sy = fy * fy * (3 - 2 * fy)
        let a = hash(ix, iy) * (1 - sx) + hash(ix + 1, iy) * sx
        let b = hash(ix, iy + 1) * (1 - sx) + hash(ix + 1, iy + 1) * sx
        return a * (1 - sy) + b * sy
    }
    static let field: [(Double, Double)] = (0..<(width * height)).map { index in
        let x = index % width, y = index / width
        let cloud = noise(Double(x) / 13, Double(y) / 13) * 0.7
            + noise(Double(x) / 5, Double(y) / 5) * 0.3
        // 低对比固定纤维，完全显现后仍清晰、没有闪烁噪点。
        let fiber = 0.89 + noise(Double(x) / 0.9, Double(y) / 3.8) * 0.11
        return (cloud, fiber)
    }
    static func image(progress: Double) -> CGImage {
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        for (index, sample) in field.enumerated() {
            let (cloud, fiber) = sample
            let edge = min(1, max(0, (progress * 1.26 - cloud) / 0.18))
            let coverage = progress >= 1 ? 1 : edge * edge * (3 - 2 * edge)
            let alpha = UInt8(coverage * fiber * 255)
            let offset = index * 4
            bytes[offset] = alpha; bytes[offset + 1] = alpha
            bytes[offset + 2] = alpha; bytes[offset + 3] = alpha
        }
        let provider = CGDataProvider(data: Data(bytes) as CFData)!
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)!
    }
    static func tiledImage(_ sample: CGImage) -> CGImage {
        let pageWidth = 576, pageHeight = 1248
        let sampleBytes = sample.dataProvider!.data! as Data
        let sampleRowBytes = sample.bytesPerRow
        let pageRowBytes = pageWidth * 4
        var bytes = Data(count: pageRowBytes * pageHeight)
        // CGContext原平铺从左下角起绘制；首行对应未满一块的上缘，保持同样相位。
        let firstRow = (height - pageHeight % height) % height
        bytes.withUnsafeMutableBytes { destination in
            sampleBytes.withUnsafeBytes { source in
                for y in 0..<pageHeight {
                    let row = source.baseAddress!.advanced(by: ((y + firstRow) % height) * sampleRowBytes)
                    for x in stride(from: 0, to: pageWidth, by: width) {
                        destination.baseAddress!.advanced(by: y * pageRowBytes + x * 4)
                            .copyMemory(from: row, byteCount: min(width, pageWidth - x) * 4)
                    }
                }
            }
        }
        let provider = CGDataProvider(data: bytes as CFData)!
        return CGImage(width: pageWidth, height: pageHeight, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: pageRowBytes, space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)!
    }

}

struct PaperInk: ViewModifier {
    let progress: Double
    var tiled = false
    static func prepare() { _ = InkField.image(progress: 1) }
    #if DEBUG
    // 此上界以上所有像素覆盖率均为1；只用于区分静止与变化的采样区间。
    static let performanceOpaqueBoundary = (InkField.field.map { $0.0 }.max()! + 0.18) / 1.26
    #endif

    func body(content: Content) -> some View {
        let sample = InkField.image(progress: progress)
        let mask = tiled ? InkField.tiledImage(sample) : sample
        content.mask {
            Image(decorative: mask, scale: 1).resizable().interpolation(.high)
                .id(progress) // 每个进度显式刷新动态alpha图，避免复用上帧蒙版。
        }
    }


}

/// T02 A「素纸压印」SVG花饰的原生Path转写；页脚细线单独按新纸页定位。
struct PaperOrnament: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: -92, y: 0)); p.addLine(to: CGPoint(x: -47, y: 0))
        p.addCurve(to: CGPoint(x: -11, y: -10), control1: CGPoint(x: -29, y: 0), control2: CGPoint(x: -20, y: -4))
        p.move(to: CGPoint(x: 92, y: 0)); p.addLine(to: CGPoint(x: 47, y: 0))
        p.addCurve(to: CGPoint(x: 11, y: -10), control1: CGPoint(x: 29, y: 0), control2: CGPoint(x: 20, y: -4))
        p.move(to: CGPoint(x: -14, y: 7))
        p.addCurve(to: CGPoint(x: -23, y: -11), control1: CGPoint(x: -46, y: 7), control2: CGPoint(x: -39, y: -15))
        p.addCurve(to: CGPoint(x: -24, y: 0), control1: CGPoint(x: -14, y: -9), control2: CGPoint(x: -16, y: 1))
        p.move(to: CGPoint(x: 14, y: 7))
        p.addCurve(to: CGPoint(x: 23, y: -11), control1: CGPoint(x: 46, y: 7), control2: CGPoint(x: 39, y: -15))
        p.addCurve(to: CGPoint(x: 24, y: 0), control1: CGPoint(x: 14, y: -9), control2: CGPoint(x: 16, y: 1))
        p.move(to: CGPoint(x: 0, y: 6))
        p.addCurve(to: CGPoint(x: 0, y: -18), control1: CGPoint(x: -10, y: -2), control2: CGPoint(x: -12, y: -10))
        p.addCurve(to: CGPoint(x: 0, y: 6), control1: CGPoint(x: 12, y: -10), control2: CGPoint(x: 10, y: -2))
        p.move(to: CGPoint(x: -4, y: -8)); p.addLine(to: CGPoint(x: 4, y: -8))
        let scale = rect.width / 184
        return p.applying(CGAffineTransform(scaleX: scale, y: scale))
            .applying(CGAffineTransform(translationX: rect.midX, y: rect.midY))
    }
}
