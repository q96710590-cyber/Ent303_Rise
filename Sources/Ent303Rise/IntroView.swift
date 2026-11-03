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
    /// 商店/背包面板是否打开
    @State private var panelOpen = CommandLine.arguments.contains("--demo-panel")
    /// 当前 Tab：0 FOOD / 1 PLANT / 2 BEDS / 3 ACCS
    @State private var panelTab = CommandLine.arguments
        .first(where: { $0.hasPrefix("--demo-panel-tab=") })
        .flatMap { Int($0.dropFirst("--demo-panel-tab=".count)) } ?? 0

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

                // 商店 / 背包面板（在平台上方）
                if panelOpen {
                    panelView(c)
                        .transition(.scale(scale: 0.85, anchor: .bottom)
                                        .combined(with: .opacity))
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
                menuButton("shop", size: c.menuIconSize) {
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.8)) {
                        panelTab = 0
                        panelOpen.toggle()
                    }
                }
                    .transition(.scale(scale: 0.3).combined(with: .opacity))
                menuButton("backpack", size: c.menuIconSize) {
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.8)) {
                        panelTab = 3
                        panelOpen.toggle()
                    }
                }
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

    // MARK: - 商店 / 背包面板

    private static let panelNames = ["food", "plant", "beds", "accs"]

    @ViewBuilder
    private func panelView(_ c: Composition) -> some View {
        let name = Self.panelNames[min(panelTab, Self.panelNames.count - 1)]
        if let img = Composition.panelImage(name) {
            ZStack(alignment: .topLeading) {
                Image(nsImage: img)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: c.panelW, height: c.panelH)

                // 顶部四个 Tab 的命中区（位置由素材实测）
                ForEach(0..<4, id: \.self) { i in
                    Button {
                        panelTab = i
                    } label: {
                        Color.clear
                    }
                    .buttonStyle(.plain)
                    .frame(width: c.panelW * Composition.panelTabWidth,
                           height: c.panelH * 0.10)
                    .offset(x: c.panelW * (Composition.panelTabStart
                                           + Composition.panelTabWidth * Double(i)),
                            y: c.panelH * 0.245)
                }
            }
            .offset(x: c.panelX, y: c.panelY)
        }
    }

    private func menuButton(_ name: String,
                            size: Double,
                            action: @escaping () -> Void = {}) -> some View {
        Button(action: action) {
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

/// 一次布局计算：所有尺寸与坐标都由容器大小推出。
///
/// 关键设计：**猫的尺寸与平台的尺寸解耦**。
/// 平台按 islandWidthRatio 放大，猫保持固定的容器相对宽度；
/// 猫在平台上的位置用两个比例描述（横向 30%、纵向 40.6%），
/// 因此平台变大时猫会自动落在对应的新位置。
struct Composition {
    let W: Double
    let H: Double
    let meta: IntroMeta?

    init(width: Double, height: Double, meta: IntroMeta?) {
        self.W = width
        self.H = height
        self.meta = meta
    }

    // MARK: - 比例常量

    /// 平台宽度 / 容器宽度
    private let islandWidthRatio = 0.78
    /// 猫宽度 / 容器宽度（固定值，不随平台变化）
    private let catWidthRatio = 0.62 * 0.34
    /// 猫中心 X 位于平台宽度的 30%
    private let catCenterRatio = 0.30
    /// 猫脚位于平台高度的 40.6%
    private let seatDepthRatio = 0.406
    /// 平台垂直中心 / 容器高度
    private let islandCenterRatio = 0.5625
    /// 静态猫相对 GIF 尾帧猫的放大系数（校准替换跳变）
    private let staticCatScale = 1.025

    // MARK: - 平台

    var islandW: Double { W * islandWidthRatio }

    var islandH: Double {
        guard let img = Self.islandImage, img.size.width > 0 else { return islandW * 0.35 }
        return islandW * (img.size.height / img.size.width)
    }

    /// 平台不居中：由猫的位置反推（画布居中优先，保证字母完整）
    var islandX: Double { catCenterX - islandW * catCenterRatio }
    var islandY: Double { H * islandCenterRatio - islandH / 2 }

    // MARK: - 猫

    /// 画布缩放：由猫的固定宽度反推
    var scale: Double {
        guard let meta, meta.catW > 0 else { return 0.36 }
        return (W * catWidthRatio) / meta.catW
    }

    var canvasW: Double { (meta?.canvasW ?? 600) * scale }
    var canvasH: Double { (meta?.canvasH ?? 757) * scale }

    /// 猫脚所在的 y
    var catBottomY: Double { islandY + seatDepthRatio * islandH }

    /// 画布水平居中（开屏字母要完整显示）
    var canvasX: Double { (W - canvasW) / 2 }

    /// 猫中心 X 直接由画布推出
    var catCenterX: Double {
        guard let meta else { return W / 2 }
        let canvasCatCenter = Double(meta.catBox[0] + meta.catBox[2]) / 2
        return canvasX + canvasCatCenter * scale
    }

    var canvasY: Double {
        guard let meta else { return 0 }
        return catBottomY - Double(meta.catBox[3]) * scale
    }

    // MARK: - 静态猫（替换 GIF 尾帧）

    var catW: Double { (meta?.catW ?? 171) * scale * staticCatScale }
    var catH: Double { (meta?.catH ?? 168) * scale * staticCatScale }
    var catX: Double { catCenterX - catW / 2 }
    var catY: Double { catBottomY - catH }

    // MARK: - 第二段位移

    /// 首帧内容的水平中心（容器坐标）
    var firstFrameCenterX: Double {
        canvasX + (meta?.firstCenterX ?? 300) * scale
    }

    /// 猫落稳后继续左移的距离：把平台中心挪到首帧中心
    var shiftDistance: Double {
        (islandX + islandW / 2) - firstFrameCenterX
    }

    func platformOffset(progress: Double) -> Double {
        (1 - progress) * (W + islandW)
    }

    // MARK: - 商店 / 背包面板

    /// 平台左移后的最终左边
    var islandXFinal: Double { islandX - shiftDistance }

    var panelW: Double { islandW * 1.03 }
    var panelH: Double { panelW * (1800.0 / 2880.0) }
    var panelX: Double { islandXFinal + (islandW - panelW) / 2 }
    var panelY: Double {
        let catTop = catBottomY - catH
        return max(4, catTop - 8 - panelH)
    }

    /// Tab 命中区（相对面板宽度的归一化值，由素材实测）
    static let panelTabStart = 0.0635
    static let panelTabWidth = 0.0747

    // MARK: - 平台下方菜单

    var menuIconSize: Double { islandW * 0.160 }
    var menuLogoSize: Double { islandW * 0.218 }
    var menuSpacing: Double { menuIconSize * 0.32 }
    var menuRightOverflow: Double { islandW * 0.08 }
    var menuGapBelow: Double { islandW * 0.03 }

    // MARK: - 素材

    private static var cachedIsland: NSImage?
    private static var cachedCat: NSImage?
    private static var menuCache: [String: NSImage] = [:]

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

    private static var panelCache: [String: NSImage] = [:]

    static func panelImage(_ name: String) -> NSImage? {
        if let cached = panelCache[name] { return cached }
        guard let url = Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "panel"),
              let img = NSImage(contentsOf: url) else { return nil }
        panelCache[name] = img
        return img
    }

    static func menuImage(_ name: String) -> NSImage? {
        if let cached = menuCache[name] { return cached }
        let sub: String? = (name == "logo") ? nil : "menu"
        guard let url = Bundle.main.url(forResource: name, withExtension: "png", subdirectory: sub),
              let img = NSImage(contentsOf: url) else { return nil }
        menuCache[name] = img
        return img
    }
}
