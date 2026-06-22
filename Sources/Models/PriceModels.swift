import Foundation

// MARK: - Data Sources

enum GoldPriceSource: String, CaseIterable {
    case jdZsFinance = "京东浙商"
    case jdMsFinance = "京东民生"
    case londonGold = "伦敦金"
    case newyorkGold = "纽约金"

    var unit: String {
        switch self {
        case .jdZsFinance, .jdMsFinance:
            return "元/克"
        case .londonGold, .newyorkGold:
            return "$/oz"
        }
    }

    var isDomestic: Bool {
        switch self {
        case .jdZsFinance, .jdMsFinance: return true
        case .londonGold, .newyorkGold: return false
        }
    }

    static var domesticSources: [GoldPriceSource] {
        allCases.filter { $0.isDomestic }
    }

    static var internationalSources: [GoldPriceSource] {
        allCases.filter { !$0.isDomestic }
    }

    var shortLabel: String {
        switch self {
        case .jdZsFinance:
            return "浙商"
        case .jdMsFinance:
            return "民生"
        case .londonGold:
            return "伦敦"
        case .newyorkGold:
            return "纽约"
        }
    }
}

// MARK: - Price Info

struct PriceInfo {
    var price: String = "--"
    var yesterdayPrice: String = "--"
    var changeRate: String = ""
    var changeAmount: String = ""
    var dayHigh: String = "--"
    var dayLow: String = "--"

    var isUp: Bool {
        guard !changeRate.isEmpty else { return true }
        return !changeRate.hasPrefix("-")
    }

    var priceDouble: Double? {
        Double(price)
    }

    var formattedPrice: String {
        guard let p = priceDouble else { return "--" }
        return String(format: "%.2f", p)
    }

    var changeIcon: String {
        isUp ? "📈" : "📉"
    }
}

// MARK: - Price History Record

struct PriceRecord: Codable {
    let timestamp: Date
    let price: Double
}

enum DailyChangeDisplayMode: String, Codable, CaseIterable {
    case off = "不显示"
    case amount = "涨跌金额"
    case rate = "涨跌幅"
    case both = "都显示"
}

enum DynamicIslandDisplayItem: String, Codable, CaseIterable, Identifiable {
    case jdZsFinance
    case londonGold

    var id: String { rawValue }

    var title: String {
        switch self {
        case .jdZsFinance:
            return GoldPriceSource.jdZsFinance.rawValue
        case .londonGold:
            return GoldPriceSource.londonGold.rawValue
        }
    }

    var source: GoldPriceSource? {
        switch self {
        case .jdZsFinance:
            return .jdZsFinance
        case .londonGold:
            return .londonGold
        }
    }

    static func item(for source: GoldPriceSource) -> DynamicIslandDisplayItem? {
        switch source {
        case .jdZsFinance:
            return .jdZsFinance
        case .londonGold:
            return .londonGold
        case .jdMsFinance, .newyorkGold:
            return nil
        }
    }
}

enum ExtremeAlertCooldown: Int, Codable, CaseIterable {
    case oneMinute = 60
    case threeMinutes = 180
    case fiveMinutes = 300
    case fifteenMinutes = 900
    case thirtyMinutes = 1800

    var shortLabel: String {
        switch self {
        case .oneMinute: return "1分"
        case .threeMinutes: return "3分"
        case .fiveMinutes: return "5分"
        case .fifteenMinutes: return "15分"
        case .thirtyMinutes: return "30分"
        }
    }
}

struct AppSettings: Codable, Equatable {
    static let defaultStatusBarSourceRawValues = [GoldPriceSource.jdZsFinance.rawValue]
    static let defaultDynamicIslandItemRawValues = [
        DynamicIslandDisplayItem.jdZsFinance.rawValue,
        DynamicIslandDisplayItem.londonGold.rawValue
    ]

    enum CodingKeys: String, CodingKey {
        case statusBarIcon
        case statusBarSourceRawValues
        case statusBarSourceRawValue
        case statusBarPriceUsesDailyChangeColor
        case statusBarDailyChangeUsesColor
        case dailyChangeDisplay
        case refreshInterval
        case dynamicIslandEnabled
        case dynamicIslandSourceRawValue
        case dynamicIslandItemRawValues
        case dynamicIslandRefreshInterval
        case defaultAlertRepeatInterval
        case extremeAlertCooldown
    }

    var statusBarIcon: String = "🌕"
    var statusBarSourceRawValues: [String] = AppSettings.defaultStatusBarSourceRawValues
    var statusBarPriceUsesDailyChangeColor: Bool = false
    var statusBarDailyChangeUsesColor: Bool = true
    var dailyChangeDisplay: DailyChangeDisplayMode = .off
    var refreshInterval: Int = 5
    var dynamicIslandEnabled: Bool = false
    var dynamicIslandSourceRawValue: String = GoldPriceSource.jdZsFinance.rawValue
    var dynamicIslandItemRawValues: [String] = AppSettings.defaultDynamicIslandItemRawValues
    var dynamicIslandRefreshInterval: Int = 15
    var defaultAlertRepeatInterval: AlertRepeatInterval = .fiveMinutes
    var extremeAlertCooldown: ExtremeAlertCooldown = .threeMinutes

    init(
        statusBarIcon: String = "🌕",
        statusBarSourceRawValues: [String] = AppSettings.defaultStatusBarSourceRawValues,
        statusBarPriceUsesDailyChangeColor: Bool = false,
        statusBarDailyChangeUsesColor: Bool = true,
        dailyChangeDisplay: DailyChangeDisplayMode = .off,
        refreshInterval: Int = 5,
        dynamicIslandEnabled: Bool = false,
        dynamicIslandSourceRawValue: String = GoldPriceSource.jdZsFinance.rawValue,
        dynamicIslandItemRawValues: [String] = AppSettings.defaultDynamicIslandItemRawValues,
        dynamicIslandRefreshInterval: Int = 15,
        defaultAlertRepeatInterval: AlertRepeatInterval = .fiveMinutes,
        extremeAlertCooldown: ExtremeAlertCooldown = .threeMinutes
    ) {
        self.statusBarIcon = statusBarIcon
        self.statusBarSourceRawValues = AppSettings.normalizedStatusBarSourceRawValues(statusBarSourceRawValues)
        self.statusBarPriceUsesDailyChangeColor = statusBarPriceUsesDailyChangeColor
        self.statusBarDailyChangeUsesColor = statusBarDailyChangeUsesColor
        self.dailyChangeDisplay = dailyChangeDisplay
        self.refreshInterval = max(1, refreshInterval)
        self.dynamicIslandEnabled = dynamicIslandEnabled
        self.dynamicIslandSourceRawValue = AppSettings.normalizedSingleSourceRawValue(dynamicIslandSourceRawValue)
        self.dynamicIslandItemRawValues = AppSettings.normalizedDynamicIslandItemRawValues(dynamicIslandItemRawValues)
        self.dynamicIslandRefreshInterval = max(5, dynamicIslandRefreshInterval)
        self.defaultAlertRepeatInterval = defaultAlertRepeatInterval
        self.extremeAlertCooldown = extremeAlertCooldown
    }

    var statusBarSources: [GoldPriceSource] {
        get {
            AppSettings.normalizedStatusBarSourceRawValues(statusBarSourceRawValues).compactMap(GoldPriceSource.init(rawValue:))
        }
        set {
            statusBarSourceRawValues = AppSettings.normalizedStatusBarSources(newValue).map(\.rawValue)
        }
    }

    var primaryStatusBarSource: GoldPriceSource {
        statusBarSources.first ?? .jdZsFinance
    }

    var refreshTimeInterval: TimeInterval {
        TimeInterval(max(1, refreshInterval))
    }

    var dynamicIslandSource: GoldPriceSource {
        get {
            GoldPriceSource(rawValue: AppSettings.normalizedSingleSourceRawValue(dynamicIslandSourceRawValue)) ?? .jdZsFinance
        }
        set {
            dynamicIslandSourceRawValue = newValue.rawValue
        }
    }

    var dynamicIslandItems: [DynamicIslandDisplayItem] {
        get {
            AppSettings.normalizedDynamicIslandItemRawValues(dynamicIslandItemRawValues).compactMap(DynamicIslandDisplayItem.init(rawValue:))
        }
        set {
            dynamicIslandItemRawValues = AppSettings.normalizedDynamicIslandItems(newValue).map(\.rawValue)
        }
    }

    var dynamicIslandRefreshTimeInterval: TimeInterval {
        TimeInterval(max(5, dynamicIslandRefreshInterval))
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        statusBarIcon = try container.decodeIfPresent(String.self, forKey: .statusBarIcon) ?? "🌕"
        if let storedRawValues = try container.decodeIfPresent([String].self, forKey: .statusBarSourceRawValues) {
            statusBarSourceRawValues = AppSettings.normalizedStatusBarSourceRawValues(storedRawValues)
        } else if let storedRawValue = try container.decodeIfPresent(String.self, forKey: .statusBarSourceRawValue) {
            statusBarSourceRawValues = AppSettings.normalizedStatusBarSourceRawValues([storedRawValue])
        } else {
            statusBarSourceRawValues = AppSettings.defaultStatusBarSourceRawValues
        }
        statusBarPriceUsesDailyChangeColor = try container.decodeIfPresent(Bool.self, forKey: .statusBarPriceUsesDailyChangeColor) ?? false
        statusBarDailyChangeUsesColor = try container.decodeIfPresent(Bool.self, forKey: .statusBarDailyChangeUsesColor) ?? true
        dailyChangeDisplay = try container.decodeIfPresent(DailyChangeDisplayMode.self, forKey: .dailyChangeDisplay) ?? .off
        refreshInterval = max(1, try container.decodeIfPresent(Int.self, forKey: .refreshInterval) ?? 5)
        dynamicIslandEnabled = try container.decodeIfPresent(Bool.self, forKey: .dynamicIslandEnabled) ?? false
        dynamicIslandSourceRawValue = AppSettings.normalizedSingleSourceRawValue(
            try container.decodeIfPresent(String.self, forKey: .dynamicIslandSourceRawValue) ?? GoldPriceSource.jdZsFinance.rawValue
        )
        if let dynamicIslandRawValues = try container.decodeIfPresent([String].self, forKey: .dynamicIslandItemRawValues) {
            dynamicIslandItemRawValues = AppSettings.normalizedDynamicIslandItemRawValues(dynamicIslandRawValues)
        } else {
            dynamicIslandItemRawValues = AppSettings.defaultDynamicIslandItemRawValues
        }
        dynamicIslandRefreshInterval = max(5, try container.decodeIfPresent(Int.self, forKey: .dynamicIslandRefreshInterval) ?? 15)
        defaultAlertRepeatInterval = try container.decodeIfPresent(AlertRepeatInterval.self, forKey: .defaultAlertRepeatInterval) ?? .fiveMinutes
        extremeAlertCooldown = try container.decodeIfPresent(ExtremeAlertCooldown.self, forKey: .extremeAlertCooldown) ?? .threeMinutes
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(statusBarIcon, forKey: .statusBarIcon)
        try container.encode(AppSettings.normalizedStatusBarSourceRawValues(statusBarSourceRawValues), forKey: .statusBarSourceRawValues)
        try container.encode(statusBarPriceUsesDailyChangeColor, forKey: .statusBarPriceUsesDailyChangeColor)
        try container.encode(statusBarDailyChangeUsesColor, forKey: .statusBarDailyChangeUsesColor)
        try container.encode(dailyChangeDisplay, forKey: .dailyChangeDisplay)
        try container.encode(refreshInterval, forKey: .refreshInterval)
        try container.encode(dynamicIslandEnabled, forKey: .dynamicIslandEnabled)
        try container.encode(AppSettings.normalizedSingleSourceRawValue(dynamicIslandSourceRawValue), forKey: .dynamicIslandSourceRawValue)
        try container.encode(AppSettings.normalizedDynamicIslandItemRawValues(dynamicIslandItemRawValues), forKey: .dynamicIslandItemRawValues)
        try container.encode(max(5, dynamicIslandRefreshInterval), forKey: .dynamicIslandRefreshInterval)
        try container.encode(defaultAlertRepeatInterval, forKey: .defaultAlertRepeatInterval)
        try container.encode(extremeAlertCooldown, forKey: .extremeAlertCooldown)
    }

    private static func normalizedStatusBarSources(_ sources: [GoldPriceSource]) -> [GoldPriceSource] {
        var normalized: [GoldPriceSource] = []
        for source in sources where !normalized.contains(source) {
            normalized.append(source)
        }
        return normalized.isEmpty ? [.jdZsFinance] : normalized
    }

    private static func normalizedStatusBarSourceRawValues(_ rawValues: [String]) -> [String] {
        normalizedStatusBarSources(rawValues.compactMap(GoldPriceSource.init(rawValue:))).map(\.rawValue)
    }

    private static func normalizedSingleSourceRawValue(_ rawValue: String) -> String {
        GoldPriceSource(rawValue: rawValue)?.rawValue ?? GoldPriceSource.jdZsFinance.rawValue
    }

    private static func normalizedDynamicIslandItems(_ items: [DynamicIslandDisplayItem]) -> [DynamicIslandDisplayItem] {
        var normalized: [DynamicIslandDisplayItem] = []
        for item in items where !normalized.contains(item) {
            normalized.append(item)
        }
        return normalized.isEmpty ? DynamicIslandDisplayItem.allCases : normalized
    }

    private static func normalizedDynamicIslandItemRawValues(_ rawValues: [String]) -> [String] {
        normalizedDynamicIslandItems(rawValues.compactMap(DynamicIslandDisplayItem.init(rawValue:))).map(\.rawValue)
    }
}

// MARK: - Price Alert (价格提醒)

enum AlertCondition: String, Codable, CaseIterable {
    case above = "高于"
    case below = "低于"

    var displayText: String {
        switch self {
        case .above: return "≥"
        case .below: return "≤"
        }
    }
}

enum AlertRepeatMode: String, Codable, CaseIterable {
    case rearmOnCross = "重新穿越"
    case recurring = "持续提醒"

    var detailDescription: String {
        switch self {
        case .rearmOnCross:
            return "价格先回到阈值另一侧，再次穿越时才会提醒。"
        case .recurring:
            return "价格满足条件后，会按你设置的时间间隔重复提醒。"
        }
    }
}

enum AlertRepeatInterval: Int, Codable, CaseIterable {
    case fiveMinutes = 300
    case fifteenMinutes = 900
    case thirtyMinutes = 1800
    case oneHour = 3600

    var shortLabel: String {
        switch self {
        case .fiveMinutes: return "5分"
        case .fifteenMinutes: return "15分"
        case .thirtyMinutes: return "30分"
        case .oneHour: return "1小时"
        }
    }

    var description: String {
        "每\(shortLabel)"
    }
}

struct PriceAlert: Codable, Equatable {
    enum CodingKeys: String, CodingKey {
        case id
        case sourceRawValue
        case condition
        case targetPrice
        case triggered
        case repeatMode
        case repeatInterval
        case lastTriggeredAt
        case wasConditionMet
    }

    var id: String = UUID().uuidString
    var sourceRawValue: String
    var condition: AlertCondition
    var targetPrice: Double
    var triggered: Bool = false
    var repeatMode: AlertRepeatMode = .recurring
    var repeatInterval: AlertRepeatInterval = .fiveMinutes
    var lastTriggeredAt: Date? = nil
    var wasConditionMet: Bool = false

    init(
        id: String = UUID().uuidString,
        sourceRawValue: String,
        condition: AlertCondition,
        targetPrice: Double,
        triggered: Bool = false,
        repeatMode: AlertRepeatMode = .recurring,
        repeatInterval: AlertRepeatInterval = .fiveMinutes,
        lastTriggeredAt: Date? = nil,
        wasConditionMet: Bool = false
    ) {
        self.id = id
        self.sourceRawValue = sourceRawValue
        self.condition = condition
        self.targetPrice = targetPrice
        self.triggered = triggered
        self.repeatMode = repeatMode
        self.repeatInterval = repeatInterval
        self.lastTriggeredAt = lastTriggeredAt
        self.wasConditionMet = wasConditionMet
    }

    var source: GoldPriceSource? {
        GoldPriceSource(rawValue: sourceRawValue)
    }

    var repeatSummary: String {
        switch repeatMode {
        case .rearmOnCross:
            return "重新穿越阈值后再次提醒"
        case .recurring:
            return "满足条件后\(repeatInterval.description)提醒"
        }
    }

    func isConditionMet(currentPrice: Double) -> Bool {
        switch condition {
        case .above: return currentPrice >= targetPrice
        case .below: return currentPrice <= targetPrice
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        sourceRawValue = try container.decode(String.self, forKey: .sourceRawValue)
        condition = try container.decode(AlertCondition.self, forKey: .condition)
        targetPrice = try container.decode(Double.self, forKey: .targetPrice)
        triggered = try container.decodeIfPresent(Bool.self, forKey: .triggered) ?? false
        repeatMode = try container.decodeIfPresent(AlertRepeatMode.self, forKey: .repeatMode) ?? .recurring
        repeatInterval = try container.decodeIfPresent(AlertRepeatInterval.self, forKey: .repeatInterval) ?? .fiveMinutes
        lastTriggeredAt = try container.decodeIfPresent(Date.self, forKey: .lastTriggeredAt)
        wasConditionMet = try container.decodeIfPresent(Bool.self, forKey: .wasConditionMet) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(sourceRawValue, forKey: .sourceRawValue)
        try container.encode(condition, forKey: .condition)
        try container.encode(targetPrice, forKey: .targetPrice)
        try container.encode(triggered, forKey: .triggered)
        try container.encode(repeatMode, forKey: .repeatMode)
        try container.encode(repeatInterval, forKey: .repeatInterval)
        try container.encodeIfPresent(lastTriggeredAt, forKey: .lastTriggeredAt)
        try container.encode(wasConditionMet, forKey: .wasConditionMet)
    }
}

// MARK: - Percentage Alert (涨跌幅提醒)

enum PercentageAlertMetric: String, Codable, CaseIterable {
    case netChange = "净涨跌幅"
    case intradayRange = "波动幅度"

    var detailDescription: String {
        switch self {
        case .netChange:
            return "按当日开盘价到当前价的净涨跌幅计算。"
        case .intradayRange:
            return "按当日最高价与最低价的差值，相对开盘价计算。"
        }
    }
}

struct PercentageAlert: Codable, Equatable {
    enum CodingKeys: String, CodingKey {
        case id
        case sourceRawValue
        case metric
        case targetPercent
        case triggered
        case repeatMode
        case repeatInterval
        case lastTriggeredAt
        case wasConditionMet
    }

    var id: String = UUID().uuidString
    var sourceRawValue: String
    var metric: PercentageAlertMetric
    var targetPercent: Double
    var triggered: Bool = false
    var repeatMode: AlertRepeatMode = .recurring
    var repeatInterval: AlertRepeatInterval = .fiveMinutes
    var lastTriggeredAt: Date? = nil
    var wasConditionMet: Bool = false

    init(
        id: String = UUID().uuidString,
        sourceRawValue: String,
        metric: PercentageAlertMetric,
        targetPercent: Double,
        triggered: Bool = false,
        repeatMode: AlertRepeatMode = .recurring,
        repeatInterval: AlertRepeatInterval = .fiveMinutes,
        lastTriggeredAt: Date? = nil,
        wasConditionMet: Bool = false
    ) {
        self.id = id
        self.sourceRawValue = sourceRawValue
        self.metric = metric
        self.targetPercent = metric == .intradayRange ? abs(targetPercent) : targetPercent
        self.triggered = triggered
        self.repeatMode = repeatMode
        self.repeatInterval = repeatInterval
        self.lastTriggeredAt = lastTriggeredAt
        self.wasConditionMet = wasConditionMet
    }

    var source: GoldPriceSource? {
        GoldPriceSource(rawValue: sourceRawValue)
    }

    var normalizedTargetPercent: Double {
        metric == .intradayRange ? abs(targetPercent) : targetPercent
    }

    var comparatorText: String {
        switch metric {
        case .netChange:
            if normalizedTargetPercent >= 0 {
                return "≥ \(PercentageAlert.formattedPercent(normalizedTargetPercent, alwaysShowSign: true))"
            } else {
                return "≤ \(PercentageAlert.formattedPercent(normalizedTargetPercent, alwaysShowSign: true))"
            }
        case .intradayRange:
            return "≥ \(PercentageAlert.formattedPercent(normalizedTargetPercent))"
        }
    }

    var repeatSummary: String {
        switch repeatMode {
        case .rearmOnCross:
            return "重新穿越阈值后再次提醒"
        case .recurring:
            return "满足条件后\(repeatInterval.description)提醒"
        }
    }

    func isConditionMet(currentPercent: Double) -> Bool {
        switch metric {
        case .netChange:
            if normalizedTargetPercent >= 0 {
                return currentPercent >= normalizedTargetPercent
            } else {
                return currentPercent <= normalizedTargetPercent
            }
        case .intradayRange:
            return currentPercent >= normalizedTargetPercent
        }
    }

    static func formattedPercent(_ value: Double, alwaysShowSign: Bool = false) -> String {
        let sign = alwaysShowSign && value >= 0 ? "+" : ""
        return "\(sign)\(String(format: "%.2f", value))%"
    }
}

// MARK: - Extreme Price Alert (新高新低提醒)

struct ExtremePriceAlertConfig: Codable, Equatable {
    var sourceRawValue: String
    var notifyOnNewHigh: Bool = true
    var notifyOnNewLow: Bool = true

    var source: GoldPriceSource? {
        GoldPriceSource(rawValue: sourceRawValue)
    }

    var isEnabled: Bool {
        notifyOnNewHigh || notifyOnNewLow
    }
}

