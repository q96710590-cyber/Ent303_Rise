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
    @State private var menuExpanded = CommandLine.arguments.contains("--demo-menu-expanded")
    /// 商店/背包面板是否打开
    @State private var panelOpen = CommandLine.arguments.contains("--demo-panel")
    /// 每个 Tab 各自的页码（最多 2 页，每页 8 格）
    @State private var shopPages = {
        let p = CommandLine.arguments
            .first(where: { $0.hasPrefix("--demo-shop-page=") })
            .flatMap { Int($0.dropFirst("--demo-shop-page=".count)) } ?? 0
        return [p, p, p, p]
    }()
    enum PanelMode { case shop, backpack }

    /// 面板模式：商店（购物车打开）或背包（背包打开）
    @State private var panelMode: PanelMode = .shop
    /// 已购物品：key = "tab_index"，value = 数量
    @State private var owned: [String: Int] = [:]
    /// 每个分类的货架：16 个槽位，nil 表示已被买走后的空位
    @State private var layout: [String: [Int?]] = [:]
    @State private var coinAnim: CoinState?
    @State private var coinSeq = 0
    /// Focus 面板是否打开
    @State private var focusOpen = CommandLine.arguments.contains("--demo-focus")
    @State private var focusTab = 0

    struct PlacedItem: Identifiable {
        let id = UUID()
        let tab: String
        let index: Int
        var x: Double
        var y: Double
    }
    /// 已摆到平台上的物品
    @State private var placed: [PlacedItem] = []
    /// 是否出现过提醒（用于"提醒消失后自动展开菜单"）
    @State private var hadReminder = false
    /// 金币余额（测试版默认 20）
    @State private var coins = 20
    /// 单件价格（测试期统一 1，后续可按分类配置）
    private static let itemPrice = 1

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
                Color.clear.frame(width: 1, height: 1)

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

                // 摆在平台上的物品：非食物在猫之下
                placedLayer(c, aboveCat: false)

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

                // 摆在平台上的物品：食物在猫之上
                placedLayer(c, aboveCat: true)

                // Focus 面板（平台上方）
                if focusOpen {
                    FocusPanel(tab: $focusTab, onClose: { closeAll() })
                        .frame(width: c.panelW * 0.92)
                        .offset(x: c.panelX + c.panelW * 0.04, y: c.panelY - 4)
                        .transition(.scale(scale: 0.9, anchor: .bottom).combined(with: .opacity))
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
            if layout.isEmpty {
                layout = Dictionary(uniqueKeysWithValues:
                    Self.panelNames.map { ($0, (0..<16).map { Optional($0) }) })
            }
        }
        .onDisappear {
            state.introPlaying = false
        }
        .onAppear {
            if CommandLine.arguments.contains("--demo-backpack") {
                owned = ["food_0": 3, "food_5": 2, "plant_3": 1, "accs_2": 1]
                panelMode = .backpack
                panelOpen = true
            }
        }
        .onChange(of: state.reminder != nil) { has in
            withAnimation(.spring(response: 0.36, dampingFraction: 0.78)) {
                if has {
                    hadReminder = true
                    menuExpanded = false          // 提醒出现 → 收起菜单
                } else if hadReminder {
                    menuExpanded = true           // 点了「我起来了」→ 展开菜单
                    hadReminder = false
                }
            }
        }
        .onChange(of: finished) { done in
            guard done, CommandLine.arguments.contains("--demo-buy") else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                buy(tab: Self.panelNames[min(panelTab, 3)], slot: 2)
            }
        }
    }

    /// 左移完成后菜单才出现
    /// 平台左移结束后才显示菜单（纯时间判断，避免依赖状态标志）
    private var menuVisible: Bool { elapsed >= condenseTime + 1.2 }

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
                menuButton("focus", size: c.menuIconSize) {
                    if focusOpen { closeAll() } else { openOnly("focus") }
                }
                    .transition(.scale(scale: 0.3).combined(with: .opacity))
                menuButton("shop", size: c.menuIconSize) {
                    if panelOpen && panelMode == .shop { closeAll() } else { openOnly("shop") }
                }
                    .transition(.scale(scale: 0.3).combined(with: .opacity))
                menuButton("backpack", size: c.menuIconSize) {
                    if panelOpen && panelMode == .backpack { closeAll() } else { openOnly("backpack") }
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

    /// 关闭所有浮层
    private func closeAll() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            panelOpen = false
            focusOpen = false
        }
    }

    /// 打开某一个浮层前先关掉其他
    private func openOnly(_ target: String) {
        withAnimation(.spring(response: 0.34, dampingFraction: 0.8)) {
            if target == "focus" {
                panelOpen = false
                focusOpen = true
            } else {
                focusOpen = false
                panelMode = (target == "backpack") ? .backpack : .shop
                if target == "shop" { compactLayouts() }
                panelTab = 0
                panelOpen = true
            }
        }
    }
    /// 一次性购买的类目：买完留空，下次打开面板时重排补位
    private static let oneShotTabs: Set<String> = ["beds", "accs"]

    struct CoinState: Equatable {
        let tab: String
        let slot: Int
        let id: Int
    }

    @ViewBuilder
    private func panelView(_ c: Composition) -> some View {
        let name = Self.panelNames[min(panelTab, Self.panelNames.count - 1)]
        if let img = Composition.panelImage(name) {
            ZStack(alignment: .topLeading) {
                Image(nsImage: img)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: c.panelW, height: c.panelH)

                coinBar(c)
                itemGrid(c, tab: name)
                coinOverlay(c, tab: name)
                coinCounter(c)

                ForEach(0..<4, id: \.self) { i in
                    tabHitArea(c, index: i)
                }
                pageArrows(c)

                // 关闭键
                Button { closeAll() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: c.panelH * 0.075))
                        .foregroundStyle(Color(red: 0.36, green: 0.30, blue: 0.29).opacity(0.7))
                }
                .buttonStyle(.plain)
                .contentShape(Circle())
                .offset(x: c.panelW * 0.945, y: c.panelH * 0.028)
            }
            .offset(x: c.panelX, y: c.panelY)
        }
    }

    // MARK: 列表

    /// 当前页第 slot 格的物品索引；空格为 nil
    private func itemIndex(tab: String, slot: Int) -> Int? {
        let list: [Int?] = (panelMode == .shop)
            ? (layout[tab] ?? [])
            : backpackIndices(tab)
        let i = shopPages[min(panelTab, 3)] * Composition.itemsPerPage + slot
        guard i < list.count else { return nil }
        return list[i]
    }

    /// 背包里该分类已拥有的物品（升序）
    private func backpackIndices(_ tab: String) -> [Int?] {
        owned.keys
            .filter { $0.hasPrefix(tab + "_") }
            .compactMap { Int($0.dropFirst(tab.count + 1)) }
            .sorted()
            .map { Optional($0) }
    }

    private func listCount(tab: String) -> Int {
        (panelMode == .shop) ? (layout[tab] ?? []).count : backpackIndices(tab).count
    }

    /// 打开面板时把空格压缩掉（一次性类目买完后补位）
    private func compactLayouts() {
        for tab in Self.panelNames {
            guard let arr = layout[tab] else { continue }
            layout[tab] = arr.compactMap { $0 }.map { Optional($0) }
        }
    }

    // MARK: 格子

    private func slotRect(_ c: Composition, slot: Int)
        -> (x: Double, y: Double, width: Double, height: Double) {
        let col = slot % 4
        let row = slot / 4
        let (x0, x1) = Composition.slotCols[col]
        let (y0, y1) = Composition.slotRows[row]
        let inset = 0.035
        return (c.panelW * (x0 + (x1 - x0) * inset),
                c.panelH * (y0 + (y1 - y0) * inset),
                c.panelW * (x1 - x0) * (1 - inset * 2),
                c.panelH * (y1 - y0) * (1 - inset * 2))
    }

    @ViewBuilder
    private func itemGrid(_ c: Composition, tab: String) -> some View {
        ForEach(0..<Composition.itemsPerPage, id: \.self) { slot in
            if let index = itemIndex(tab: tab, slot: slot),
               let img = Composition.shopImage(tab: tab, index: index) {
                let r = slotRect(c, slot: slot)
                Image(nsImage: img)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: r.width, height: r.height)
                    .overlay(alignment: .bottomTrailing) {
                        // 背包里只显示一个，数量用右下角角标表示
                        if panelMode == .backpack, let n = owned["\(tab)_\(index)"], n > 1 {
                            Text("×\(n)")
                                .font(.system(size: 9, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(Color.black.opacity(0.6)))
                                .offset(x: 3, y: 3)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { buy(tab: tab, slot: slot) }
                    .gesture(
                        DragGesture(minimumDistance: 8, coordinateSpace: .named("comp"))
                            .onEnded { v in
                                guard panelMode == .backpack else { return }
                                drop(tab: tab, index: index, at: v.location, c: c)
                            }
                    )
                    .offset(x: r.x, y: r.y)
            }
        }
    }

    // MARK: 拖放

    /// 物品在平台上的显示边长（food 原尺寸，其余放大）
    private func placedSize(_ c: Composition, tab: String) -> Double {
        let base = c.panelW * 0.167 * 0.93
        return tab == "food" ? base : base * 1.3
    }

    private func islandRect(_ c: Composition) -> (x: Double, y: Double, w: Double, h: Double) {
        (c.islandX - c.shiftDistance, c.islandY, c.islandW, c.islandH)
    }

    private func insidePlatform(_ p: CGPoint, _ c: Composition) -> Bool {
        let r = islandRect(c)
        return p.x >= r.x && p.x <= r.x + r.w
            && p.y >= r.y - 8 && p.y <= r.y + r.h + 8
    }

    /// 每个分类的同时上限
    private func limit(for tab: String) -> Int { tab == "plant" ? 2 : 1 }

    private func drop(tab: String, index: Int, at p: CGPoint, c: Composition) {
        guard insidePlatform(p, c) else { return }
        guard placed.filter({ $0.tab == tab }).count < limit(for: tab) else { return }
        withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
            placed.append(PlacedItem(tab: tab, index: index, x: p.x, y: p.y))
        }
    }

    @ViewBuilder
    private func placedLayer(_ c: Composition, aboveCat: Bool) -> some View {
        ForEach(placed) { item in
            if (item.tab == "food") == aboveCat,
               let img = Composition.shopImage(tab: item.tab, index: item.index) {
                let side = placedSize(c, tab: item.tab)
                Image(nsImage: img)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: side, height: side)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 2, coordinateSpace: .named("comp"))
                            .onChanged { v in
                                if let i = placed.firstIndex(where: { $0.id == item.id }) {
                                    placed[i].x = v.location.x
                                    placed[i].y = v.location.y
                                }
                            }
                            .onEnded { v in
                                guard let i = placed.firstIndex(where: { $0.id == item.id }) else { return }
                                if insidePlatform(v.location, c) {
                                    placed[i].x = v.location.x
                                    placed[i].y = v.location.y
                                } else {
                                    // 拖出平台 → 收回背包
                                    withAnimation(.easeOut(duration: 0.2)) {
                                        placed.remove(at: i)
                                    }
                                }
                            }
                    )
                    .offset(x: item.x - side / 2, y: item.y - side / 2)
            }
        }
    }

    // MARK: 购买

    private func buy(tab: String, slot: Int) {
        guard panelMode == .shop, let index = itemIndex(tab: tab, slot: slot) else { return }
        let key = "\(tab)_\(index)"

        // 余额不足则不出手
        guard coins >= Self.itemPrice else { return }
        coins -= Self.itemPrice

        if Self.oneShotTabs.contains(tab) {
            guard (owned[key] ?? 0) == 0 else { return }
            owned[key] = 1
            // 当前会话先留空，下次打开面板时重排补位
            let pos = shopPages[min(panelTab, 3)] * Composition.itemsPerPage + slot
            if var arr = layout[tab], pos < arr.count {
                arr[pos] = nil
                layout[tab] = arr
            }
        } else {
            owned[key, default: 0] += 1
        }

        coinSeq += 1
        let id = coinSeq
        coinAnim = CoinState(tab: tab, slot: slot, id: id)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) { [id] in
            if coinAnim?.id == id { coinAnim = nil }
        }
    }

    /// 用面板底色块盖住素材里那条静态进度条
    @ViewBuilder
    private func coinBar(_ c: Composition) -> some View {
        RoundedRectangle(cornerRadius: c.panelH * 0.02, style: .continuous)
            .fill(Color(red: 1.0, green: 0.808, blue: 0.388))
            .frame(width: c.panelW * 0.372, height: c.panelH * 0.080)
            .offset(x: c.panelW * 0.592, y: c.panelH * 0.206)
    }

    /// 右上角金币余额（素材里是静态的，这里由代码绘制）
    @ViewBuilder
    private func coinCounter(_ c: Composition) -> some View {
        let iconSize = c.panelH * 0.075
        HStack(spacing: iconSize * 0.25) {
            if let icon = Composition.coinIcon {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: iconSize, height: iconSize)
            }
            Text("\(coins)")
                .font(.system(size: c.panelH * 0.062, weight: .bold, design: .rounded))
                .foregroundStyle(Color(red: 0.36, green: 0.30, blue: 0.29))
                .monospacedDigit()
        }
        // 右对齐到胶囊条左侧，避免数字盖住进度条
        .frame(width: c.panelW * 0.74, alignment: .trailing)
        .offset(y: c.panelH * 0.205)
    }

    /// 购买动画：金币从格子中心升起并淡出（GIF 只播一遍，尺寸按设计稿比例）
    @ViewBuilder
    private func coinOverlay(_ c: Composition, tab: String) -> some View {
        if let coin = coinAnim, coin.tab == tab,
           let url = Bundle.main.url(forResource: "coin", withExtension: "gif") {
            let r = slotRect(c, slot: coin.slot)
            // GIF 里金币约占画布 27%，据此反推视图尺寸
            let coinD = r.width * 0.35
            let side = coinD / 0.27
            AnimatedGIFView(url: url)
                .frame(width: side, height: side)
                .allowsHitTesting(false)
                .offset(x: r.x + r.width / 2 - side / 2,
                        y: r.y + r.height / 2 - side / 2)
        }
    }

    // MARK: 翻页

    @ViewBuilder
    private func pageArrows(_ c: Composition) -> some View {
        let page = shopPages[min(panelTab, 3)]
        let name = Self.panelNames[min(panelTab, 3)]
        let count = listCount(tab: name)
        let pageCount = max(1, Int(ceil(Double(count) / Double(Composition.itemsPerPage))))
        let size = c.panelW * 0.0815
        // 两行格子的间隙中心 = (0.5628 + 0.6233) / 2
        let centerY = c.panelH * 0.593 - size / 2

        if page > 0 {
            arrowButton(c, size: size, forward: false) {
                shopPages[min(panelTab, 3)] = max(0, page - 1)
            }
            .offset(x: c.panelW * 0.077 - size / 2, y: centerY)
        }
        if page < pageCount - 1 {
            arrowButton(c, size: size, forward: true) {
                shopPages[min(panelTab, 3)] = min(pageCount - 1, page + 1)
            }
            .offset(x: c.panelW * 0.923 - size / 2, y: centerY)
        }
    }

    /// 翻页按钮：灰色圆底 + 深色描边 + 奶油色三角（不使用菜单里的播放图标）
    private func arrowButton(_ c: Composition,
                             size: Double,
                             forward: Bool,
                             action: @escaping () -> Void) -> some View {
        ZStack {
            Circle().fill(Color(white: 0.85))
            Circle().strokeBorder(Color(red: 0.36, green: 0.30, blue: 0.29),
                                  lineWidth: max(1, size * 0.07))
            ArrowTriangle()
                .fill(Color(red: 0.99, green: 0.96, blue: 0.86))
                .overlay(
                    ArrowTriangle()
                        .stroke(Color(red: 0.36, green: 0.30, blue: 0.29),
                                lineWidth: max(0.8, size * 0.05))
                )
                .frame(width: size * 0.30, height: size * 0.36)
                .rotationEffect(.degrees(forward ? 0 : 180))
                .offset(x: size * 0.015 * (forward ? 1 : -1))
        }
        .frame(width: size, height: size)
        .contentShape(Circle())
        .onTapGesture(perform: action)
    }

    /// 翻页三角
    struct ArrowTriangle: Shape {
        func path(in rect: CGRect) -> Path {
            var p = Path()
            p.move(to: CGPoint(x: rect.minX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            p.closeSubpath()
            return p
        }
    }

    /// 单个 Tab 的命中区
    @ViewBuilder
    private func tabHitArea(_ c: Composition, index i: Int) -> some View {
        let w = c.panelW * Composition.panelTabWidth
        let h = c.panelH * 0.10
        let x = c.panelW * (Composition.panelTabStart
                            + Composition.panelTabWidth * Double(i))
        let y = c.panelH * 0.245

        Color.clear
            .frame(width: w, height: h)
            .contentShape(Rectangle())
            .onTapGesture { panelTab = i }
            .offset(x: x, y: y)
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
    private let islandCenterRatio = 0.60
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

    /// 面板尽量用满内容宽度（比平台更宽），以获得更大的 Tab 文字
    var panelW: Double { W - 16 }
    var panelH: Double { panelW * (1800.0 / 2880.0) }
    var panelX: Double { (W - panelW) / 2 }
    var panelY: Double {
        let catTop = catBottomY - catH
        return max(4, min(8, catTop - 8 - panelH))
    }

    // MARK: - 格子与物品

    /// 每页格子数
    static let itemsPerPage = 8

    /// 4 列的归一化 x 范围（素材实测）
    static let slotCols: [(Double, Double)] = [
        (0.1038, 0.2708), (0.3118, 0.4788), (0.5208, 0.6878), (0.7295, 0.8965)
    ]
    /// 2 行的归一化 y 范围
    static let slotRows: [(Double, Double)] = [
        (0.3622, 0.5628), (0.6233, 0.8239)
    ]

    private static var cachedCoinIcon: NSImage?
    static var coinIcon: NSImage? {
        if let cachedCoinIcon { return cachedCoinIcon }
        guard let url = Bundle.main.url(forResource: "coin_icon", withExtension: "png") else { return nil }
        cachedCoinIcon = NSImage(contentsOf: url)
        return cachedCoinIcon
    }

    private static var shopCache: [String: NSImage] = [:]
    private static var pageCountCache: [String: Int] = [:]

    /// 取某个分类的第 index 个物品
    static func shopImage(tab: String, index: Int) -> NSImage? {
        guard index >= 0 else { return nil }
        let key = "\(tab)_\(index)"
        if let cached = shopCache[key] { return cached }
        let name = String(format: "%@_%02d", tab, index)
        guard let url = Bundle.main.url(forResource: name,
                                        withExtension: "png",
                                        subdirectory: "shop/\(tab)") else { return nil }
        shopCache[key] = NSImage(contentsOf: url)
        return shopCache[key]
    }

    /// 该分类共几页
    static func pageCount(tab: String) -> Int {
        if let cached = pageCountCache[tab] { return cached }
        var count = 0
        if let dir = Bundle.main.resourceURL?.appendingPathComponent("shop/\(tab)") {
            count = (try? FileManager.default.contentsOfDirectory(atPath: dir.path))?.count ?? 0
        }
        let pages = max(1, Int(ceil(Double(count) / Double(itemsPerPage))))
        pageCountCache[tab] = pages
        return pages
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
