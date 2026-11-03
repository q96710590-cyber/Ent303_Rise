import SwiftUI
import AppKit

/// 开屏动画元数据（由 tools/build_intro.py 生成）
struct IntroMeta: Decodable {
    let canvas: [Int]
    let frameCount: Int
    let delays: [Int]
    let sinkFrame: Int
    let condenseFrame: Int
    let catBox: [Int]
    let islandSurface: Double
    let firstCenterX: Double?

    var canvasW: Double { Double(canvas[0]) }
    var canvasH: Double { Double(canvas[1]) }
    var catW: Double { Double(catBox[2] - catBox[0]) }
    var catH: Double { Double(catBox[3] - catBox[1]) }

    static func load() -> IntroMeta? {
        guard let url = Bundle.main.url(forResource: "meta", withExtension: "json", subdirectory: "intro"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(IntroMeta.self, from: data)
    }
}

/// 开屏编排：
/// 1. GIF 只播一遍
/// 2. 字母开始下沉时，平台从屏幕右侧滑入
/// 3. 动画到「凝结帧」时平台停住，猫正好落在平台的 30% 处
/// 4. 播放结束后隐藏 GIF，用静态猫顶在完全相同的位置与尺寸
struct IntroView: View {

    @EnvironmentObject var state: AppState

    private let meta = IntroMeta.load()

    @State private var start = Date()
    @State private var elapsed: TimeInterval = 0
    @State private var frameIndex = 0
    @State private var frameImage: NSImage?
    @State private var finished = false
    /// 平台下方那一排按钮是否展开
    @State private var menuExpanded = !CommandLine.arguments.contains("--demo-menu-collapsed")

    private let ticker = Timer.publish(every: 1.0 / 60.0, on: .main, in: .common).autoconnect()

    // MARK: - 时间轴

    private var cumTimes: [Double] {
        guard let meta else { return [] }
        var t = 0.0
        return meta.delays.map { d in
            defer { t += Double(d) / 1000.0 }
            return t
        }
    }

    private var totalTime: Double {
        guard let meta else { return 0 }
        return Double(meta.delays.reduce(0, +)) / 1000.0
    }

    private var sinkTime: Double {
        guard let meta, cumTimes.indices.contains(meta.sinkFrame) else { return 0 }
        return cumTimes[meta.sinkFrame]
    }

    private var condenseTime: Double {
        guard let meta, cumTimes.indices.contains(meta.condenseFrame) else { return 0 }
        return cumTimes[meta.condenseFrame]
    }

    /// 猫落稳后的二次左移：从凝结帧开始，1.2 秒内把平台中心移到首帧中心
    private var shiftProgress: Double {
        let duration = 1.2
        let t = min(max((elapsed - condenseTime) / duration, 0), 1)
        return 1 - pow(1 - t, 3)
    }

    /// 平台进度：下沉开始 → 凝结帧
    private var platformProgress: Double {
        let span = condenseTime - sinkTime
        guard span > 0 else { return 1 }
        let t = min(max((elapsed - sinkTime) / span, 0), 1)
        return 1 - pow(1 - t, 3)      // ease-out，结尾稳稳停住
    }

    // MARK: - 视图

    var body: some View {
        GeometryReader { geo in
            let c = Composition(width: geo.size.width,
                                height: geo.size.height,
                                meta: meta)

            ZStack(alignment: .topLeading) {
                // 平台在猫后面
                if let island = Composition.islandImage {
                    Image(nsImage: island)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: c.islandW, height: c.islandH)
                        .offset(x: c.islandX
                                   + c.platformOffset(progress: platformProgress)
                                   - c.shiftDistance * shiftProgress,
                                y: c.islandY)
                }

                // 播放阶段：逐帧
                if !finished, let img = frameImage {
                    Image(nsImage: img)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: c.canvasW, height: c.canvasH)
                        .offset(x: c.canvasX - c.shiftDistance * shiftProgress,
                                y: c.canvasY)
                }

                // 结束阶段：静态猫顶替尾帧的猫
                if finished, let cat = Composition.catImage {
                    Image(nsImage: cat)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: c.catW, height: c.catH)
                        .offset(x: c.catX - c.shiftDistance, y: c.catY)
                }

                // 平台下方的一排按钮 + LOGO
                menuRow(c)
                    .frame(width: c.islandX + c.islandW + c.menuRightOverflow - c.shiftDistance,
                           alignment: .trailing)
                    .offset(y: c.islandY + c.islandH + c.menuGapBelow)
                    .opacity(menuVisible ? 1 : 0)
                    .animation(.easeOut(duration: 0.35), value: menuVisible)
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
        }
        .onReceive(ticker) { _ in tick() }
        .onAppear {
            start = Date()
            elapsed = 0
            frameIndex = 0
            finished = false
            loadFrame(0)
            state.introPlaying = true
        }
        .onDisappear {
            state.introPlaying = false
        }
    }

    /// 左移完成后菜单才出现
    private var menuVisible: Bool { finished || shiftProgress > 0.98 }

    @ViewBuilder
    private func menuRow(_ c: Composition) -> some View {
        HStack(spacing: c.menuSpacing) {
            // 展开 / 收起键（播放图标，收起时水平镜像朝左）
            Button {
                withAnimation(.spring(response: 0.36, dampingFraction: 0.78)) {
                    menuExpanded.toggle()
                }
            } label: {
                if let img = Composition.menuImage("play") {
                    Image(nsImage: img)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: c.menuIconSize, height: c.menuIconSize)
                        .scaleEffect(x: menuExpanded ? 1 : -1, y: 1)
                }
            }
            .buttonStyle(.plain)
            .help(menuExpanded ? "收起" : "展开")

            if menuExpanded {
                menuButton("focus", size: c.menuIconSize)
                    .transition(.scale(scale: 0.3).combined(with: .opacity))
                menuButton("shop", size: c.menuIconSize)
                    .transition(.scale(scale: 0.3).combined(with: .opacity))
                menuButton("backpack", size: c.menuIconSize)
                    .transition(.scale(scale: 0.3).combined(with: .opacity))
            }

            // LOGO 始终在行尾
            if let logo = Composition.menuImage("logo") {
                Image(nsImage: logo)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: c.menuLogoSize, height: c.menuLogoSize)
            }
        }
    }

    private func menuButton(_ name: String, size: Double) -> some View {
        Button {
            // 功能待接入
        } label: {
            Group {
                if let img = Composition.menuImage(name) {
                    Image(nsImage: img)
                        .resizable()
                        .interpolation(.high)
                } else {
                    Color.clear
                }
            }
            .frame(width: size, height: size)
        }
        .buttonStyle(.plain)
    }

    // MARK: - 播放

    private func tick() {
        guard let meta else { return }
        elapsed = Date().timeIntervalSince(start)

        if elapsed >= totalTime {
            if !finished {
                finished = true
                frameIndex = meta.frameCount - 1
                state.endIntro()
            }
            return
        }

        var idx = 0
        for (i, t) in cumTimes.enumerated() where elapsed >= t {
            idx = i
        }
        if idx != frameIndex {
            frameIndex = idx
            loadFrame(idx)
        }
    }

    private func loadFrame(_ index: Int) {
        guard let url = Bundle.main.url(forResource: String(format: "f_%03d", index),
                                        withExtension: "png",
                                        subdirectory: "intro") else { return }
        frameImage = NSImage(contentsOf: url)
    }
}

/// 一次布局计算：所有尺寸与坐标都由容器大小推出
struct Composition {
    let W: Double
    let H: Double
    let meta: IntroMeta?

    init(width: Double, height: Double, meta: IntroMeta?) {
        self.W = width
        self.H = height
        self.meta = meta
    }

    /// 平台宽度 / 容器宽度
    private let islandWidthRatio = 0.62
    /// 猫宽 / 平台宽（设计稿测量）
    private let catToIsland = 0.34
    /// 猫中心位于平台宽度的 30%（设计稿测量）
    private let catCenterRatio = 0.30
    /// 猫脚落在平台高度的多少比例处（0 = 平台顶边）
    /// 由设计稿红线标注测得：0.406（原来只沉到顶边附近，猫是"浮"在平台上的）
    private let seatDepthRatio = 0.406

    private static var cachedIsland: NSImage?
    private static var cachedCat: NSImage?

    private static var menuCache: [String: NSImage] = [:]

    /// 菜单图标（play / focus / shop / backpack / logo）
    static func menuImage(_ name: String) -> NSImage? {
        if let cached = menuCache[name] { return cached }
        // logo 复用根目录的 logo.png
        let sub: String? = (name == "logo") ? nil : "menu"
        guard let url = Bundle.main.url(forResource: name, withExtension: "png", subdirectory: sub),
              let img = NSImage(contentsOf: url) else { return nil }
        menuCache[name] = img
        return img
    }

    static var islandImage: NSImage? {
        if let cachedIsland { return cachedIsland }
        guard let url = Bundle.main.url(forResource: "island", withExtension: "png", subdirectory: "intro") else { return nil }
        cachedIsland = NSImage(contentsOf: url)
        return cachedIsland
    }

    static var catImage: NSImage? {
        if let cachedCat { return cachedCat }
        guard let url = Bundle.main.url(forResource: "cat", withExtension: "png", subdirectory: "intro") else { return nil }
        cachedCat = NSImage(contentsOf: url)
        return cachedCat
    }

    var islandW: Double { W * islandWidthRatio }

    var islandH: Double {
        guard let img = Self.islandImage, img.size.width > 0 else { return islandW * 0.6 }
        return islandW * (img.size.height / img.size.width)
    }

    /// 画布缩放：让画布里的猫宽等于目标猫宽
    var scale: Double {
        guard let meta, meta.catW > 0 else { return 0.36 }
        return (islandW * catToIsland) / meta.catW
    }

    var canvasW: Double { (meta?.canvasW ?? 600) * scale }
    var canvasH: Double { (meta?.canvasH ?? 757) * scale }
    /// 画布水平居中
    var canvasX: Double { (W - canvasW) / 2 }
    var canvasY: Double { 0 }

    /// 画布里的猫中心（换算到容器坐标）
    var catCenterX: Double {
        guard let meta else { return W / 2 }
        let canvasCatCenter = Double(meta.catBox[0] + meta.catBox[2]) / 2
        return canvasX + canvasCatCenter * scale
    }

    var catW: Double { (meta?.catW ?? 171) * scale }
    var catH: Double { (meta?.catH ?? 168) * scale }
    var catX: Double { canvasX + Double(meta?.catBox[0] ?? 0) * scale }
    var catY: Double { canvasY + Double(meta?.catBox[1] ?? 0) * scale }

    /// 平台跟着猫走：猫中心落在平台宽度的 30% 处，并夹在容器内
    var islandX: Double {
        let raw = catCenterX - islandW * catCenterRatio
        return min(max(raw, 2), max(2, W - islandW - 2))
    }

    // 平台下方菜单尺寸：按参考图测量，均为相对平台宽度的比例
    /// 按钮直径 / 平台宽（比参考图再放大约 13%）
    var menuIconSize: Double { islandW * 0.160 }
    /// LOGO 直径 / 平台宽，约为按钮的 1.36 倍
    var menuLogoSize: Double { islandW * 0.218 }
    /// 按钮间距 = 0.32 × 按钮直径
    var menuSpacing: Double { menuIconSize * 0.32 }
    /// 整排右端超出平台右边缘的量，允许 Logo 略微出界
    var menuRightOverflow: Double { islandW * 0.08 }
    /// 按钮行与平台底边的间隙 = 0.03 × 平台宽
    var menuGapBelow: Double { islandW * 0.03 }

    /// 首帧内容的水平中心（容器坐标）
    var firstFrameCenterX: Double {
        canvasX + (meta?.firstCenterX ?? 300) * scale
    }

    /// 猫落稳后需要继续左移的距离：把平台中心挪到首帧中心
    var shiftDistance: Double {
        (islandX + islandW / 2) - firstFrameCenterX
    }

    /// 平台顶面（猫脚处）与画布里猫底对齐
    var islandY: Double {
        let catBottom = canvasY + Double(meta?.catBox[3] ?? 690) * scale
        return catBottom - seatDepthRatio * islandH
    }

    func platformOffset(progress: Double) -> Double {
        (1 - progress) * (W + islandW)
    }
}
