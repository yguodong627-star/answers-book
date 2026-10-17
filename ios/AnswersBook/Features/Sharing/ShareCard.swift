import SwiftUI

/// 独立纸卡：不包含播放器、操作按钮、收藏状态或抽取时间。
struct ShareCard: View {
    let content: ShareContent
    let includeNote: Bool

    var body: some View {
        VStack(spacing: 0) {
            PaperOrnament().stroke(PaperTheme.gold.opacity(0.56), lineWidth: 0.8)
                .frame(width: 100, height: 22).padding(.top, 48)
            Spacer(minLength: 48)
            VStack(spacing: 8) {
                Text(content.zh).font(.custom("NotoSerifSC-Regular", size: 28)).tracking(2)
                Text(content.en).font(.custom("Georgia", size: 18)).foregroundStyle(PaperTheme.muted)
            }
            .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            if includeNote, let note = content.note, !note.isEmpty {
                VStack(alignment: .leading, spacing: 9) {
                    Text("我的问题").font(.custom("NotoSerifSC-Regular", size: 12)).foregroundStyle(PaperTheme.gold)
                    Text(note).font(.custom("NotoSerifSC-Regular", size: 16)).lineSpacing(5)
                        .fixedSize(horizontal: false, vertical: true)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, 32)
            }
            Spacer(minLength: 48)
            Rectangle().fill(PaperTheme.gold.opacity(0.4)).frame(width: 65, height: 0.5)
            Text("答案之书").font(.custom("NotoSerifSC-Regular", size: 15)).tracking(4)
                .foregroundStyle(PaperTheme.gold).padding(.top, 18).padding(.bottom, 36)
        }
        .padding(.horizontal, 30).frame(maxWidth: .infinity, minHeight: 490)
        .fixedSize(horizontal: false, vertical: true)
        .foregroundStyle(PaperTheme.ink)
        .background {
            LinearGradient(colors: [Color(red: 0.98, green: 0.96, blue: 0.92),
                                    Color(red: 0.94, green: 0.90, blue: 0.82)], startPoint: .topLeading, endPoint: .bottomTrailing)
                .overlay { PaperFibers().opacity(0.14) }
        }
        .overlay { Rectangle().stroke(PaperTheme.gold.opacity(0.25), lineWidth: 0.7).padding(15) }
        .overlay { Rectangle().stroke(PaperTheme.gold.opacity(0.3), lineWidth: 0.7) }
        .environment(\.colorScheme, .light).dynamicTypeSize(.large)
    }
}

/// 固定、可重复的原生纸纤维，不依赖网络或随机变化的截图纹理。
private struct PaperFibers: View {
    var body: some View {
        Canvas { context, size in
            var seed: UInt64 = 45
            for _ in 0..<2400 {
                seed = seed &* 6364136223846793005 &+ 1
                let x = CGFloat(seed % 10000) / 10000 * size.width
                seed = seed &* 6364136223846793005 &+ 1
                let y = CGFloat(seed % 10000) / 10000 * size.height
                var path = Path(); path.move(to: CGPoint(x: x, y: y))
                path.addLine(to: CGPoint(x: x + 1 + CGFloat(seed % 4), y: y + 0.5))
                context.stroke(path, with: .color(PaperTheme.gold), lineWidth: 0.3)
            }
        }
    }
}
