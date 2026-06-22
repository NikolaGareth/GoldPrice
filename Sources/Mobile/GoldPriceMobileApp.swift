#if os(iOS)
import SwiftUI

@main
struct GoldPriceMobileApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var viewModel = GoldPriceMobileViewModel()

    var body: some Scene {
        WindowGroup {
            GoldPriceMobileRootView(viewModel: viewModel)
                .onAppear {
                    viewModel.start()
                }
                .onChange(of: scenePhase) { newPhase in
                    switch newPhase {
                    case .active:
                        viewModel.start()
                    case .background, .inactive:
                        viewModel.stop()
                    @unknown default:
                        break
                    }
                }
        }
    }
}

struct GoldPriceMobileRootView: View {
    @ObservedObject var viewModel: GoldPriceMobileViewModel
    @State private var selectedTab: MobileRootTab

    init(viewModel: GoldPriceMobileViewModel) {
        self.viewModel = viewModel
        _selectedTab = State(initialValue: MobileRootTab.previewSelection)
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeTabView(viewModel: viewModel)
                .tag(MobileRootTab.home)
                .tabItem {
                    Label("首页", systemImage: "house.fill")
                }

            MarketTabView(viewModel: viewModel)
                .tag(MobileRootTab.market)
                .tabItem {
                    Label("行情", systemImage: "chart.line.uptrend.xyaxis")
                }


            SettingsTabView(viewModel: viewModel)
                .tag(MobileRootTab.settings)
                .tabItem {
                    Label("设置", systemImage: "gearshape")
                }
        }
        .tint(.orange)
    }
}

private enum MobileRootTab: String {
    case home
    case market
    case settings

    static var previewSelection: MobileRootTab {
        let rawValue = ProcessInfo.processInfo.environment["GOLDPRICE_PREVIEW_TAB"] ?? ""
        return MobileRootTab(rawValue: rawValue) ?? .home
    }
}

private enum MobileFormatting {
    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    static func signedAmountText(_ value: Double) -> String {
        "\(value >= 0 ? "+" : "")\(format(value)) 元"
    }

    static func signedNumberText(_ value: Double) -> String {
        "\(value >= 0 ? "+" : "")\(format(value))"
    }

    static func format(_ value: Double, digits: Int = 2) -> String {
        String(format: "%.\(digits)f", value)
    }

    static func timeText(_ date: Date) -> String {
        timeFormatter.string(from: date)
    }
}

private struct HomeTabView: View {
    @ObservedObject var viewModel: GoldPriceMobileViewModel

    private let heroSources: [GoldPriceSource] = [.jdZsFinance, .londonGold]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {

                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(heroSources, id: \.self) { source in
                            HomeHeroPriceCard(
                                source: source,
                                info: viewModel.allSourcePrices[source] ?? PriceInfo(),
                                isLoading: viewModel.isLoading && viewModel.allSourcePrices[source] == nil,
                                lastUpdateTime: viewModel.lastUpdateTime
                            )
                        }
                    }
                }
                .padding(16)
            }
            .background(Color.appGroupedBackground.ignoresSafeArea())
            .navigationTitle("实时金价")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        viewModel.refresh()
                    } label: {
                        if viewModel.isLoading {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                }
            }
            .refreshable {
                viewModel.refresh()
            }
        }
    }
}

private struct HomeHeroPriceCard: View {
    let source: GoldPriceSource
    let info: PriceInfo
    let isLoading: Bool
    let lastUpdateTime: Date

    private var dayHighValue: Double? {
        Double(info.dayHigh)
    }

    private var dayLowValue: Double? {
        Double(info.dayLow)
    }

    private var rangeProgress: Double? {
        guard
            let current = info.priceDouble,
            let high = dayHighValue,
            let low = dayLowValue,
            high > low
        else {
            return nil
        }

        return min(max((current - low) / (high - low), 0), 1)
    }

    private var accentColor: Color {
        info.isUp ? .red : .goldGreen
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(source.rawValue)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.primary)

                    Text("更新 \(MobileFormatting.timeText(lastUpdateTime))")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                Spacer()

                Text(source.unit)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.primary.opacity(0.06))
                    )
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(info.formattedPrice)
                    .font(.system(size: 38, weight: .black, design: .rounded))
                    .foregroundColor(.primary)
                    .minimumScaleFactor(0.7)

                if !info.changeAmount.isEmpty || !info.changeRate.isEmpty {
                    HStack(spacing: 8) {
                        if !info.changeAmount.isEmpty {
                            changeBadge(info.changeAmount)
                        }
                        if !info.changeRate.isEmpty {
                            changeBadge(info.changeRate)
                        }
                    }
                } else {
                    Text(isLoading ? "正在同步价格..." : "等待价格同步")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }

            if let rangeProgress {
                VStack(alignment: .leading, spacing: 6) {
                    ProgressView(value: rangeProgress)
                        .tint(accentColor)

                    HStack {
                        Text("低 \(info.dayLow)")
                            .foregroundColor(.goldGreen)
                        Spacer()
                        Text("高 \(info.dayHigh)")
                            .foregroundColor(.red)
                    }
                    .font(.system(size: 11, weight: .medium))
                }
            } else {
                HStack {
                    metricPill(title: "高", value: info.dayHigh, tint: .red)
                    metricPill(title: "低", value: info.dayLow, tint: .goldGreen)
                }
            }

            HStack {
                metricPill(title: "昨收", value: info.yesterdayPrice, tint: .primary)
                Spacer()
                Text(source == .jdZsFinance ? "首页锚点" : "国际参照")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(cardBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.primary.opacity(0.05), lineWidth: 1)
        )
    }

    private func changeBadge(_ value: String) -> some View {
        Text(value)
            .font(.system(size: 13, weight: .bold, design: .monospaced))
            .foregroundColor(accentColor)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(
                Capsule(style: .continuous)
                    .fill(accentColor.opacity(0.10))
            )
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        source == .londonGold ? Color.orange.opacity(0.16) : Color.red.opacity(0.08),
                        Color.appCardBackground
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
    }

    private func metricPill(title: String, value: String, tint: Color) -> some View {
        HStack(spacing: 4) {
            Text(title)
                .foregroundColor(tint.opacity(0.8))
            Text(value)
                .foregroundColor(tint)
        }
        .font(.system(size: 11, weight: .semibold, design: .monospaced))
        .lineLimit(1)
        .minimumScaleFactor(0.68)
        .allowsTightening(true)
    }

}

private struct MarketTabView: View {
    @ObservedObject var viewModel: GoldPriceMobileViewModel

    private let columns = [GridItem(.flexible())]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    summaryHeader

                    ForEach(GoldPriceSource.allCases, id: \.self) { source in
                        PriceChartPanel(
                            source: source,
                            info: viewModel.allSourcePrices[source] ?? PriceInfo(),
                            records: viewModel.records(for: source),
                            isLoading: viewModel.isLoading && viewModel.allSourcePrices[source] == nil,
                            emptyMessage: "等待本机累计更多价格点..."
                        )
                    }
                }
                .padding(16)
            }
            .background(Color.appGroupedBackground.ignoresSafeArea())
            .navigationTitle("行情")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        viewModel.refresh()
                    } label: {
                        if viewModel.isLoading {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                }
            }
            .refreshable {
                viewModel.refresh()
            }
        }
    }

    private var summaryHeader: some View {
        HStack {
            Spacer()

            Text("\(viewModel.settings.refreshInterval) 秒刷新 · 更新 \(timeText(viewModel.lastUpdateTime))")
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func timeText(_ date: Date) -> String {
        MobileFormatting.timeText(date)
    }
}

private struct SettingsTabView: View {
    @ObservedObject var viewModel: GoldPriceMobileViewModel
    private let dynamicIslandRefreshOptions = [5, 10, 15, 30, 60, 120, 300]

    private var appVersionText: String {
        let bundle = Bundle.main
        let shortVersion = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let buildVersion = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String

        switch (shortVersion, buildVersion) {
        case let (short?, build?) where !short.isEmpty && !build.isEmpty:
            return "\(short) (\(build))"
        case let (short?, _) where !short.isEmpty:
            return short
        case let (_, build?) where !build.isEmpty:
            return build
        default:
            return "--"
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("基础设置") {
                    Stepper(
                        value: Binding(
                            get: { viewModel.settings.refreshInterval },
                            set: { viewModel.updateRefreshInterval($0) }
                        ),
                        in: 1...60
                    ) {
                        HStack {
                            Text("自动刷新")
                            Spacer()
                            Text("\(viewModel.settings.refreshInterval) 秒")
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Section("灵动岛") {
                    Toggle(
                        "启用灵动岛",
                        isOn: Binding(
                            get: { viewModel.settings.dynamicIslandEnabled },
                            set: { viewModel.updateDynamicIslandEnabled($0) }
                        )
                    )

                    LabeledContent("轮播内容") {
                        Text(viewModel.settings.dynamicIslandItems.map(\.title).joined(separator: "、"))
                            .foregroundColor(.secondary)
                    }

                    ForEach(DynamicIslandDisplayItem.allCases) { item in
                        Toggle(
                            item.title,
                            isOn: Binding(
                                get: { viewModel.settings.dynamicIslandItems.contains(item) },
                                set: { viewModel.updateDynamicIslandDisplayItem(item, isEnabled: $0) }
                            )
                        )
                        .disabled(
                            !viewModel.settings.dynamicIslandEnabled ||
                            (viewModel.settings.dynamicIslandItems.count == 1 && viewModel.settings.dynamicIslandItems.contains(item))
                        )
                    }

                    Picker(
                        "刷新频率",
                        selection: Binding(
                            get: { viewModel.settings.dynamicIslandRefreshInterval },
                            set: { viewModel.updateDynamicIslandRefreshInterval($0) }
                        )
                    ) {
                        ForEach(dynamicIslandRefreshOptions, id: \.self) { interval in
                            Text(refreshLabel(for: interval)).tag(interval)
                        }
                    }
                    .disabled(!viewModel.settings.dynamicIslandEnabled)
                }

                Section {
                    LabeledContent("当前版本", value: appVersionText)
                }
            }
            .navigationTitle("设置")
        }
    }

    private func refreshLabel(for seconds: Int) -> String {
        if seconds < 60 {
            return "\(seconds) 秒"
        }
        return "\(seconds / 60) 分钟"
    }
}

#endif
