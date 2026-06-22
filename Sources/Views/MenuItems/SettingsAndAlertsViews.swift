import AppKit
import SwiftUI

private enum PositionMenuItemLayout {
    static let rowWidth: CGFloat = 300
    static let rowHeight: CGFloat = 68
}

private enum PositionMenuItemFormatters {
    static let tradeDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()
}

private enum PositionDetailLayout {
    static let panelWidth: CGFloat = 420
}

// MARK: - Base class for editable menu item views (handles focus & paste in NSMenu)

class EditableMenuItemView: NSView {
    fileprivate let hostedContentView: NSView
    fileprivate let minWidth: CGFloat
    private let dynamicallyResizes: Bool
    private var isUpdatingLayoutSize = false

    init(contentView: NSView, minWidth: CGFloat, dynamicallyResizes: Bool = false) {
        self.hostedContentView = contentView
        self.minWidth = minWidth
        self.dynamicallyResizes = dynamicallyResizes
        super.init(frame: .zero)
        let size = contentView.fittingSize
        self.frame = NSRect(x: 0, y: 0, width: max(size.width, minWidth), height: size.height)
        contentView.frame = bounds
        contentView.autoresizingMask = [.width, .height]
        addSubview(contentView)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        DispatchQueue.main.async { [weak self] in
            self?.window?.makeKey()
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.modifierFlags.contains(.command),
              let chars = event.charactersIgnoringModifiers else {
            return super.performKeyEquivalent(with: event)
        }
        let sel: Selector?
        switch chars {
        case "v": sel = #selector(NSText.paste(_:))
        case "c": sel = #selector(NSText.copy(_:))
        case "x": sel = #selector(NSText.cut(_:))
        case "a": sel = #selector(NSText.selectAll(_:))
        case "z":
            sel = event.modifierFlags.contains(.shift)
                ? Selector(("redo:"))
                : #selector(UndoManager.undo)
        default: sel = nil
        }
        if let sel = sel {
            return NSApp.sendAction(sel, to: nil, from: self)
        }
        return super.performKeyEquivalent(with: event)
    }

    override func layout() {
        super.layout()
        guard dynamicallyResizes else { return }
        updateLayoutSizeIfNeeded()
    }

    fileprivate func updateLayoutSizeIfNeeded() {
        guard !isUpdatingLayoutSize else { return }
        isUpdatingLayoutSize = true
        defer { isUpdatingLayoutSize = false }

        let size = hostedContentView.fittingSize
        let targetSize = NSSize(width: max(size.width, minWidth), height: size.height)
        guard abs(frame.width - targetSize.width) > 0.5 || abs(frame.height - targetSize.height) > 0.5 else { return }

        frame.size = targetSize
        hostedContentView.frame = bounds

        if let submenuWindow = window {
            var windowFrame = submenuWindow.frame
            let deltaHeight = targetSize.height - windowFrame.height
            windowFrame.size.width = targetSize.width
            windowFrame.size.height = targetSize.height
            windowFrame.origin.y -= deltaHeight
            submenuWindow.setFrame(windowFrame, display: true, animate: true)
        }
    }
}

// MARK: - Shared segmented picker

private func segmentedPicker<T: Hashable>(
    items: [T], selected: T, label: @escaping (T) -> String, onSelect: @escaping (T) -> Void
) -> some View {
    HStack(spacing: 0) {
        ForEach(Array(items.enumerated()), id: \.offset) { index, item in
            Button(action: { onSelect(item) }) {
                Text(label(item))
                    .font(.system(size: 11, weight: selected == item ? .semibold : .regular))
                    .foregroundColor(selected == item ? .white : .primary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(selected == item ? Color.accentColor : Color.clear)
            }
            .buttonStyle(.plain)

            if index < items.count - 1 {
                Divider().frame(height: 16)
            }
        }
    }
    .background(Color.primary.opacity(0.06))
    .clipShape(RoundedRectangle(cornerRadius: 7))
    .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.primary.opacity(0.1), lineWidth: 0.5))
}

// MARK: - Main menu row (read-only display)

class SettingsEditorView: EditableMenuItemView {
    init(
        currentSource: GoldPriceSource,
        onSourceChange: @escaping (GoldPriceSource) -> Void,
        onSave: @escaping () -> Void
    ) {
        super.init(contentView: NSHostingView(rootView: SettingsEditorContent(
            currentSource: currentSource,
            onSourceChange: onSourceChange,
            onSave: onSave
        )), minWidth: 320)
    }
    required init?(coder: NSCoder) { fatalError() }
}

private struct SettingsEditorContent: View {
    @State private var selectedIcon: String
    @State private var statusBarPriceUsesDailyChangeColor: Bool
    @State private var statusBarDailyChangeUsesColor: Bool
    @State private var dailyChangeDisplay: DailyChangeDisplayMode
    @State private var refreshIntervalSeconds: Int
    @State private var refreshIntervalText: String
    @State private var selectedStatusBarSources: [GoldPriceSource]
    @State private var defaultAlertRepeatInterval: AlertRepeatInterval
    @State private var saved = false

    private let iconOptions = ["🌕", "💰", "🥇", "⭐", "💛", "🪙", "📈", "G", "Au", ""]

    let onSourceChange: (GoldPriceSource) -> Void
    let onSave: () -> Void

    init(
        currentSource: GoldPriceSource,
        onSourceChange: @escaping (GoldPriceSource) -> Void,
        onSave: @escaping () -> Void
    ) {
        self.onSourceChange = onSourceChange
        self.onSave = onSave
        let s = PriceHistoryManager.shared.settings
        _selectedIcon = State(initialValue: s.statusBarIcon)
        _statusBarPriceUsesDailyChangeColor = State(initialValue: s.statusBarPriceUsesDailyChangeColor)
        _statusBarDailyChangeUsesColor = State(initialValue: s.statusBarDailyChangeUsesColor)
        _dailyChangeDisplay = State(initialValue: s.dailyChangeDisplay)
        _refreshIntervalSeconds = State(initialValue: s.refreshInterval)
        _refreshIntervalText = State(initialValue: "\(s.refreshInterval)")
        _selectedStatusBarSources = State(initialValue: s.statusBarSources.isEmpty ? [currentSource] : s.statusBarSources)
        _defaultAlertRepeatInterval = State(initialValue: s.defaultAlertRepeatInterval)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("偏好设置")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.primary)

            settingsContent

            Spacer(minLength: 0)

            Divider()

            HStack {
                Spacer()
                HStack(spacing: 8) {
                    if saved {
                        Text("已保存 ✓")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.goldGreen)
                    }
                    Button("保存") {
                        saveSettings()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
            .padding(.top, 2)
        }
        .padding(14)
        .frame(width: 320)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var settingsContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                Text("状态栏显示数据源")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)

                Text("支持多选。已选顺序就是状态栏显示顺序，第一个会作为主展示源。")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)

                VStack(alignment: .leading, spacing: 4) {
                    ForEach(orderedStatusBarSources, id: \.self) { source in
                        statusBarSourceRow(source)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("状态栏图标")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)

                let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 5)
                LazyVGrid(columns: columns, spacing: 4) {
                    ForEach(iconOptions, id: \.self) { icon in
                        Button(action: {
                            selectedIcon = icon
                        }) {
                            Text(icon.isEmpty ? "无" : icon)
                                .font(.system(size: icon.count <= 1 && !icon.isEmpty ? 18 : 13))
                                .frame(width: 36, height: 32)
                                .background(selectedIcon == icon ? Color.accentColor : Color.primary.opacity(0.06))
                                .foregroundColor(selectedIcon == icon ? .white : .primary)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(selectedIcon == icon ? Color.accentColor : Color.primary.opacity(0.1), lineWidth: 0.5)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("状态栏显示当日金价涨跌")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                segmentedPicker(
                    items: DailyChangeDisplayMode.allCases,
                    selected: dailyChangeDisplay,
                    label: { mode in
                        switch mode {
                        case .off: return "关"
                        case .amount: return "金额"
                        case .rate: return "涨跌幅"
                        case .both: return "全部"
                        }
                    },
                    onSelect: {
                        dailyChangeDisplay = $0
                    }
                )

                settingsToggleRow(title: "当日金价涨跌幅颜色", isOn: $statusBarPriceUsesDailyChangeColor)
                settingsToggleRow(title: "当日涨跌幅颜色", isOn: $statusBarDailyChangeUsesColor)
            }


            VStack(alignment: .leading, spacing: 6) {
                Text("刷新频率")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)

                HStack(spacing: 6) {
                    PastableTextField(text: $refreshIntervalText, placeholder: "秒数")
                        .frame(width: 72, height: 22)

                    Text("s")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                Text("支持自定义整数秒，最小 1s。当前: \(refreshIntervalSeconds)s")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("默认提醒间隔")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)

                segmentedPicker(
                    items: AlertRepeatInterval.allCases,
                    selected: defaultAlertRepeatInterval,
                    label: { $0.shortLabel },
                    onSelect: {
                        defaultAlertRepeatInterval = $0
                    }
                )

                Text("价格满足条件后，重复提醒会遵守此间隔。")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
        }
    }

    private func saveSettings() {
        syncRefreshIntervalInput()
        let settings = AppSettings(
            statusBarIcon: selectedIcon,
            statusBarSourceRawValues: selectedStatusBarSources.map(\.rawValue),
            statusBarPriceUsesDailyChangeColor: statusBarPriceUsesDailyChangeColor,
            statusBarDailyChangeUsesColor: statusBarDailyChangeUsesColor,
            dailyChangeDisplay: dailyChangeDisplay,
            refreshInterval: refreshIntervalSeconds,
            defaultAlertRepeatInterval: defaultAlertRepeatInterval
        )
        PriceHistoryManager.shared.saveSettings(settings)
        syncExistingAlerts(with: settings)
        onSourceChange(selectedStatusBarSources.first ?? .jdZsFinance)
        onSave()
        saved = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            saved = false
        }
    }

    private func syncExistingAlerts(with settings: AppSettings) {
        let historyManager = PriceHistoryManager.shared

        let syncedPriceAlerts = historyManager.alerts.map { alert in
            var updated = alert
            updated.repeatMode = .recurring
            updated.repeatInterval = settings.defaultAlertRepeatInterval
            return updated
        }
        historyManager.saveAlerts(syncedPriceAlerts)

        let syncedPercentageAlerts = historyManager.percentageAlerts.map { alert in
            var updated = alert
            updated.repeatMode = .recurring
            updated.repeatInterval = settings.defaultAlertRepeatInterval
            return updated
        }
        historyManager.savePercentageAlerts(syncedPercentageAlerts)

    }

    private func syncRefreshIntervalInput() {
        let parsed = Int(refreshIntervalText.trimmingCharacters(in: .whitespacesAndNewlines)) ?? refreshIntervalSeconds
        refreshIntervalSeconds = max(1, parsed)
        refreshIntervalText = "\(refreshIntervalSeconds)"
    }

    private var orderedStatusBarSources: [GoldPriceSource] {
        selectedStatusBarSources + GoldPriceSource.allCases.filter { !selectedStatusBarSources.contains($0) }
    }

    private func settingsToggleRow(title: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)

            Spacer(minLength: 0)

            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.primary.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
        )
        .padding(.top, 2)
    }

    @ViewBuilder
    private func statusBarSourceRow(_ source: GoldPriceSource) -> some View {
        let isSelected = selectedStatusBarSources.contains(source)
        let selectedIndex = selectedStatusBarSources.firstIndex(of: source)

        HStack(spacing: 8) {
            Text(isSelected ? "\(selectedIndex.map { $0 + 1 } ?? 0)" : "•")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundColor(isSelected ? .accentColor : .secondary)
                .frame(width: 18, height: 18)
                .background(isSelected ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.05))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(source.isDomestic ? "国内" : "国际")
                        .font(.system(size: 8, weight: .medium))
                        .foregroundColor(isSelected ? .accentColor : .secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(
                            isSelected ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.05)
                        )
                        .clipShape(Capsule())

                    Text(source.rawValue)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.primary)

                    Text(source.unit)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                Text(isSelected ? "已显示在状态栏" : "未显示")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }

            Spacer(minLength: 4)

            HStack(spacing: 4) {
                Button(action: {
                    moveStatusBarSource(source, offset: -1)
                }) {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .foregroundColor(canMoveStatusBarSource(source, offset: -1) ? .primary : .secondary.opacity(0.35))
                .disabled(!canMoveStatusBarSource(source, offset: -1))

                Button(action: {
                    moveStatusBarSource(source, offset: 1)
                }) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .foregroundColor(canMoveStatusBarSource(source, offset: 1) ? .primary : .secondary.opacity(0.35))
                .disabled(!canMoveStatusBarSource(source, offset: 1))

                Button(action: {
                    toggleStatusBarSource(source)
                }) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 13))
                        .foregroundColor(isSelected ? .accentColor : .secondary)
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(isSelected ? Color.accentColor.opacity(0.08) : Color.primary.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(
                    isSelected ? Color.accentColor.opacity(0.35) : Color.primary.opacity(0.06),
                    lineWidth: isSelected ? 1 : 0.5
                )
        )
    }

    private func toggleStatusBarSource(_ source: GoldPriceSource) {
        if let index = selectedStatusBarSources.firstIndex(of: source) {
            guard selectedStatusBarSources.count > 1 else { return }
            selectedStatusBarSources.remove(at: index)
        } else {
            selectedStatusBarSources.append(source)
        }
    }

    private func canMoveStatusBarSource(_ source: GoldPriceSource, offset: Int) -> Bool {
        guard let index = selectedStatusBarSources.firstIndex(of: source) else { return false }
        let destination = index + offset
        return destination >= 0 && destination < selectedStatusBarSources.count
    }

    private func moveStatusBarSource(_ source: GoldPriceSource, offset: Int) {
        guard let index = selectedStatusBarSources.firstIndex(of: source) else { return }
        let destination = index + offset
        guard destination >= 0, destination < selectedStatusBarSources.count else { return }
        selectedStatusBarSources.swapAt(index, destination)
    }
}

// MARK: - Alert editor submenu (价格提醒)

class AlertEditorView: EditableMenuItemView {
    init() {
        super.init(contentView: NSHostingView(rootView: AlertEditorContent()), minWidth: 300)
    }
    required init?(coder: NSCoder) { fatalError() }
}

class PercentageAlertEditorView: EditableMenuItemView {
    init() {
        super.init(contentView: NSHostingView(rootView: PercentageAlertEditorContent()), minWidth: 300)
    }
    required init?(coder: NSCoder) { fatalError() }
}

class ExtremePriceAlertEditorView: EditableMenuItemView {
    init() {
        super.init(contentView: NSHostingView(rootView: ExtremePriceAlertEditorContent()), minWidth: 300)
    }
    required init?(coder: NSCoder) { fatalError() }
}

private struct ExtremePriceAlertEditorContent: View {
    @State private var configs: [GoldPriceSource: ExtremePriceAlertConfig] = {
        var map: [GoldPriceSource: ExtremePriceAlertConfig] = [:]
        for config in PriceHistoryManager.shared.extremePriceAlertConfigs {
            if let source = config.source {
                map[source] = config
            }
        }
        return map
    }()

    @State private var cooldown: ExtremeAlertCooldown = PriceHistoryManager.shared.settings.extremeAlertCooldown

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("新高新低提醒")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.primary)

            Text("开启后，当日价格创新高或新低时自动通知。")
                .font(.system(size: 10))
                .foregroundColor(.secondary)

            VStack(spacing: 4) {
                ForEach(GoldPriceSource.allCases, id: \.self) { source in
                    sourceRow(source)
                }
            }

            Divider()

            HStack {
                Text("提醒间隔")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.primary)

                Spacer()

                Picker("", selection: $cooldown) {
                    ForEach(ExtremeAlertCooldown.allCases, id: \.self) { interval in
                        Text(interval.shortLabel).tag(interval)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
                .onChange(of: cooldown) { newValue in
                    var settings = PriceHistoryManager.shared.settings
                    settings.extremeAlertCooldown = newValue
                    PriceHistoryManager.shared.saveSettings(settings)
                }
            }
        }
        .padding(14)
        .frame(width: 320)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func sourceRow(_ source: GoldPriceSource) -> some View {
        let config = configs[source] ?? ExtremePriceAlertConfig(sourceRawValue: source.rawValue, notifyOnNewHigh: false, notifyOnNewLow: false)
        let highOn = config.notifyOnNewHigh
        let lowOn = config.notifyOnNewLow

        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(source.rawValue)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.primary)

                Text(source.unit)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.secondary)
            }

            Spacer(minLength: 0)

            toggleButton(label: "新高", isOn: highOn) {
                var updated = config
                updated.notifyOnNewHigh.toggle()
                save(updated, for: source)
            }

            toggleButton(label: "新低", isOn: lowOn) {
                var updated = config
                updated.notifyOnNewLow.toggle()
                save(updated, for: source)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(config.isEnabled ? Color.accentColor.opacity(0.06) : Color.primary.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(
                    config.isEnabled ? Color.accentColor.opacity(0.25) : Color.primary.opacity(0.06),
                    lineWidth: config.isEnabled ? 1 : 0.5
                )
        )
    }

    private func toggleButton(label: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 11))
                    .foregroundColor(isOn ? .accentColor : .secondary)

                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(isOn ? .primary : .secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(isOn ? Color.accentColor.opacity(0.12) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
    }

    private func save(_ config: ExtremePriceAlertConfig, for source: GoldPriceSource) {
        configs[source] = config
        PriceHistoryManager.shared.setExtremePriceAlertConfig(config)
    }
}

// MARK: - NSTextField wrapper for use in NSMenu

private struct PastableTextField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String

    func makeNSView(context: Context) -> NSTextField {
        let tf = NSTextField()
        tf.placeholderString = placeholder
        tf.font = .systemFont(ofSize: 13)
        tf.isBordered = true
        tf.isBezeled = true
        tf.bezelStyle = .roundedBezel
        tf.delegate = context.coordinator
        tf.stringValue = text
        return tf
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, NSTextFieldDelegate {
        let parent: PastableTextField
        init(_ parent: PastableTextField) { self.parent = parent }

        func controlTextDidChange(_ obj: Notification) {
            guard let tf = obj.object as? NSTextField else { return }
            parent.text = tf.stringValue
        }
    }
}
private struct AlertEditorContent: View {
    @State private var alerts: [PriceAlert] = PriceHistoryManager.shared.alerts
    @State private var selectedSource: GoldPriceSource = .jdZsFinance
    @State private var selectedCondition: AlertCondition = .above
    @State private var priceText: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("价格提醒")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.primary)

                Spacer()

                Text(compactRepeatSummary)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }

            if alerts.isEmpty {
                Text("暂无提醒规则")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 4)
            } else {
                let aboveAlerts = alerts.filter { $0.condition == .above }.sorted { $0.targetPrice < $1.targetPrice }
                let belowAlerts = alerts.filter { $0.condition == .below }.sorted { $0.targetPrice > $1.targetPrice }

                ScrollView(.vertical, showsIndicators: true) {
                    VStack(spacing: 6) {
                        if !aboveAlerts.isEmpty {
                            alertSection(title: "📈 高于", alerts: aboveAlerts)
                        }
                        if !belowAlerts.isEmpty {
                            alertSection(title: "📉 低于", alerts: belowAlerts)
                        }
                    }
                }
                .frame(maxHeight: 200)
            }

            Divider()

            Text("添加提醒")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)

            segmentedPicker(
                items: GoldPriceSource.allCases,
                selected: selectedSource,
                label: { $0.rawValue },
                onSelect: { selectedSource = $0 }
            )

            HStack(spacing: 6) {
                segmentedPicker(
                    items: AlertCondition.allCases,
                    selected: selectedCondition,
                    label: { $0.rawValue },
                    onSelect: { selectedCondition = $0 }
                )
                .frame(width: 90)

                PastableTextField(text: $priceText, placeholder: "目标价格")
                    .frame(height: 22)
            }

            HStack {
                Spacer()
                Button("添加") {
                    let settings = PriceHistoryManager.shared.settings
                    guard let price = Double(priceText), price > 0 else { return }
                    let alert = PriceAlert(
                        sourceRawValue: selectedSource.rawValue,
                        condition: selectedCondition,
                        targetPrice: price,
                        repeatMode: .recurring,
                        repeatInterval: settings.defaultAlertRepeatInterval
                    )
                    PriceHistoryManager.shared.addAlert(alert)
                    alerts = PriceHistoryManager.shared.alerts
                    priceText = ""
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(14)
        .frame(width: 300)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var compactRepeatSummary: String {
        "提醒间隔 · \(PriceHistoryManager.shared.settings.defaultAlertRepeatInterval.shortLabel)"
    }

    private func alertSection(title: String, alerts: [PriceAlert]) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)
                .padding(.leading, 2)

            ForEach(alerts, id: \.id) { alert in
                alertRow(alert)
            }
        }
    }

    private func alertRow(_ alert: PriceAlert) -> some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(alert.sourceRawValue)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.primary)

                    Text("\(alert.condition.displayText) \(String(format: "%.2f", alert.targetPrice))")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(.primary)
                }
            }

            Spacer()

            if alert.triggered {
                Button("重置") {
                    PriceHistoryManager.shared.resetAlert(id: alert.id)
                    self.alerts = PriceHistoryManager.shared.alerts
                }
                .font(.system(size: 10))
                .foregroundColor(.orange)
                .buttonStyle(.plain)
            }

            Button(action: {
                PriceHistoryManager.shared.removeAlert(id: alert.id)
                self.alerts = PriceHistoryManager.shared.alerts
            }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background(Color.primary.opacity(0.025))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct PercentageAlertEditorContent: View {
    private enum PercentageAlertTab: String, CaseIterable {
        case netChange = "净涨跌幅"
        case intradayRange = "波动幅度"

        var metric: PercentageAlertMetric {
            switch self {
            case .netChange: return .netChange
            case .intradayRange: return .intradayRange
            }
        }
    }

    @State private var alerts: [PercentageAlert] = PriceHistoryManager.shared.percentageAlerts
    @State private var selectedTab: PercentageAlertTab = .netChange
    @State private var netChangeSource: GoldPriceSource = .jdZsFinance
    @State private var intradayRangeSource: GoldPriceSource = .jdZsFinance
    @State private var netChangeTargetText: String = ""
    @State private var intradayRangeTargetText: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("涨跌幅提醒")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.primary)

                Spacer()

                Text(compactRepeatSummary)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }

            percentageAlertTabs

            Group {
                switch selectedTab {
                case .netChange:
                    metricEditorSection(
                        metric: .netChange,
                        source: $netChangeSource,
                        targetText: $netChangeTargetText,
                        placeholder: "目标幅度，如 2 或 -2",
                        description: "净涨跌幅按开盘价到当前价计算；负数表示下跌幅度。"
                    )
                case .intradayRange:
                    metricEditorSection(
                        metric: .intradayRange,
                        source: $intradayRangeSource,
                        targetText: $intradayRangeTargetText,
                        placeholder: "目标波动幅度，如 2",
                        description: "波动幅度按当日最高价与最低价差值，相对开盘价计算，只允许正数。"
                    )
                }
            }
        }
        .padding(14)
        .frame(width: 300)
    }

    private var compactRepeatSummary: String {
        "提醒间隔 · \(PriceHistoryManager.shared.settings.defaultAlertRepeatInterval.shortLabel)"
    }

    private var netChangeAlerts: [PercentageAlert] {
        alerts
            .filter { $0.metric == .netChange }
            .sorted { $0.normalizedTargetPercent < $1.normalizedTargetPercent }
    }

    private var intradayRangeAlerts: [PercentageAlert] {
        alerts
            .filter { $0.metric == .intradayRange }
            .sorted { $0.normalizedTargetPercent < $1.normalizedTargetPercent }
    }

    private var percentageAlertTabs: some View {
        HStack(spacing: 18) {
            ForEach(PercentageAlertTab.allCases, id: \.self) { tab in
                Button(action: {
                    selectedTab = tab
                }) {
                    VStack(spacing: 6) {
                        Text(tab.rawValue)
                            .font(.system(size: 12, weight: selectedTab == tab ? .semibold : .medium))
                            .foregroundColor(selectedTab == tab ? .primary : .secondary)

                        Rectangle()
                            .fill(selectedTab == tab ? Color.accentColor : Color.clear)
                            .frame(height: 2)
                            .clipShape(Capsule())
                    }
                    .frame(width: tab == .netChange ? 56 : 50)
                }
                .buttonStyle(.plain)
            }

            Spacer()
        }
        .padding(.bottom, 2)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(height: 0.5)
        }
    }

    private func metricEditorSection(
        metric: PercentageAlertMetric,
        source: Binding<GoldPriceSource>,
        targetText: Binding<String>,
        placeholder: String,
        description: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            let metricAlerts = metric == .netChange ? netChangeAlerts : intradayRangeAlerts

            if metricAlerts.isEmpty {
                Text("暂无提醒规则")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .frame(height: sharedMetricListHeight, alignment: .center)
            } else if metricAlerts.count <= 4 {
                percentageAlertSection(title: metric.rawValue, alerts: metricAlerts)
                    .frame(height: sharedMetricListHeight, alignment: .top)
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    percentageAlertSection(title: metric.rawValue, alerts: metricAlerts)
                }
                .frame(height: sharedMetricListHeight)
            }

            Divider()

            Text("添加提醒")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)

            segmentedPicker(
                items: GoldPriceSource.allCases,
                selected: source.wrappedValue,
                label: { $0.rawValue },
                onSelect: { source.wrappedValue = $0 }
            )

            HStack(spacing: 6) {
                PastableTextField(text: targetText, placeholder: placeholder)
                    .frame(height: 22)

                Text("%")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
            }

            Text(description)
                .font(.system(size: 10))
                .foregroundColor(.secondary)

            HStack {
                Spacer()
                Button("添加") {
                    appendAlert(metric: metric, source: source.wrappedValue, targetText: targetText)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
    }

    private var sharedMetricListHeight: CGFloat {
        let maxCount = max(netChangeAlerts.count, intradayRangeAlerts.count)
        let rowHeight: CGFloat = 28
        let sectionHeaderHeight: CGFloat = 18
        let verticalPadding: CGFloat = 8
        let contentHeight = CGFloat(maxCount) * rowHeight + sectionHeaderHeight + verticalPadding
        return min(max(contentHeight, 44), 120)
    }

    private func percentageAlertSection(title: String, alerts: [PercentageAlert]) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)
                .padding(.leading, 2)

            ForEach(alerts, id: \.id) { alert in
                percentageAlertRow(alert)
            }
        }
    }

    private func percentageAlertRow(_ alert: PercentageAlert) -> some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(alert.sourceRawValue)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.primary)

                    Text("\(alert.metric.rawValue) \(alert.comparatorText)")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(.primary)
                }
            }

            Spacer()

            if alert.triggered {
                Button("重置") {
                    if let index = alerts.firstIndex(where: { $0.id == alert.id }) {
                        alerts[index].triggered = false
                        alerts[index].lastTriggeredAt = nil
                        alerts[index].wasConditionMet = false
                        PriceHistoryManager.shared.savePercentageAlerts(alerts)
                    }
                }
                .font(.system(size: 10))
                .foregroundColor(.orange)
                .buttonStyle(.plain)
            }

            Button(action: {
                alerts.removeAll { $0.id == alert.id }
                PriceHistoryManager.shared.savePercentageAlerts(alerts)
            }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background(Color.primary.opacity(0.025))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func appendAlert(metric: PercentageAlertMetric, source: GoldPriceSource, targetText: Binding<String>) {
        let settings = PriceHistoryManager.shared.settings
        guard let target = Double(targetText.wrappedValue) else { return }
        let normalizedTarget = metric == .intradayRange ? abs(target) : target
        alerts.append(
            PercentageAlert(
                sourceRawValue: source.rawValue,
                metric: metric,
                targetPercent: normalizedTarget,
                repeatMode: .recurring,
                repeatInterval: settings.defaultAlertRepeatInterval
            )
        )
        PriceHistoryManager.shared.savePercentageAlerts(alerts)
        targetText.wrappedValue = ""
    }
}

