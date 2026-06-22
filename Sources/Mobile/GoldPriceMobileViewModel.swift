import Foundation
import Combine

@MainActor
final class GoldPriceMobileViewModel: ObservableObject {
    @Published private(set) var allSourcePrices: [GoldPriceSource: PriceInfo] = [:]
    @Published private(set) var lastUpdateTime: Date = Date()
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var settings: AppSettings

    private let historyManager = PriceHistoryManager.shared
    private let dataService = GoldPriceService()
    private var cancellables = Set<AnyCancellable>()
    private var isStarted = false

    init() {
        settings = historyManager.settings
        bindDataService()
    }

    func start() {
        if isStarted {
            refresh()
            return
        }

        isStarted = true
        dataService.setDataSource(settings.primaryStatusBarSource)
        dataService.startFetching()
        refreshLocalState()
    }

    func stop() {
        isStarted = false
        dataService.stopFetching()
    }

    func refresh() {
        dataService.forceRefreshAllSources()
        refreshLocalState()
    }

    func updatePrimarySource(_ source: GoldPriceSource) {
        var updated = settings
        updated.statusBarSources = [source]
        saveSettings(updated)
    }

    func updateRefreshInterval(_ seconds: Int) {
        var updated = settings
        updated.refreshInterval = max(1, min(60, seconds))
        saveSettings(updated)
    }

    func updateDynamicIslandEnabled(_ enabled: Bool) {
        var updated = settings
        updated.dynamicIslandEnabled = enabled
        saveSettings(updated)
    }

    func updateDynamicIslandSource(_ source: GoldPriceSource) {
        var updated = settings
        updated.dynamicIslandSource = source
        saveSettings(updated)
    }

    func updateDynamicIslandDisplayItem(_ item: DynamicIslandDisplayItem, isEnabled: Bool) {
        var updated = settings
        var items = updated.dynamicIslandItems

        if isEnabled {
            if !items.contains(item) {
                items.append(item)
            }
        } else if items.count > 1 {
            items.removeAll { $0 == item }
        }

        updated.dynamicIslandItems = items
        saveSettings(updated)
    }

    func updateDynamicIslandRefreshInterval(_ seconds: Int) {
        var updated = settings
        updated.dynamicIslandRefreshInterval = max(5, min(300, seconds))
        saveSettings(updated)
    }

    func records(for source: GoldPriceSource) -> [PriceRecord] {
        historyManager.getTodayRecords(for: source.rawValue)
    }

    func currentPrice(for source: GoldPriceSource) -> Double? {
        allSourcePrices[source]?.priceDouble
    }

    var supportsDynamicIslandFeature: Bool {
        GoldPriceLiveActivityManager.isFeatureAvailable
    }

    private func bindDataService() {
        dataService.$allSourcePrices
            .receive(on: DispatchQueue.main)
            .sink { [weak self] prices in
                self?.allSourcePrices = prices
                self?.syncDynamicIsland()
            }
            .store(in: &cancellables)

        dataService.$lastUpdateTime
            .receive(on: DispatchQueue.main)
            .sink { [weak self] date in
                self?.lastUpdateTime = date
            }
            .store(in: &cancellables)

        dataService.$isLoading
            .receive(on: DispatchQueue.main)
            .sink { [weak self] loading in
                self?.isLoading = loading
            }
            .store(in: &cancellables)
    }

    private func saveSettings(_ newSettings: AppSettings) {
        historyManager.saveSettings(newSettings)
        settings = newSettings
        dataService.setDataSource(newSettings.primaryStatusBarSource)
        dataService.reloadRefreshIntervalFromSettings()
        syncDynamicIsland(force: true)
    }

    private func refreshLocalState() {
        settings = historyManager.settings
        syncDynamicIsland(force: true)
    }

    private func syncDynamicIsland(force: Bool = false) {
        GoldPriceLiveActivityManager.shared.sync(
            settings: settings,
            prices: allSourcePrices,
            performance: nil,
            updatedAt: lastUpdateTime,
            force: force
        )
    }
}
