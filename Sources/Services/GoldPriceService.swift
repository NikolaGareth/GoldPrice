import Foundation
import Combine

class GoldPriceService: ObservableObject {
    @Published var currentSource: GoldPriceSource = .jdZsFinance
    @Published var lastUpdateTime: Date = Date()
    @Published var isLoading: Bool = false
    @Published var allSourcePrices: [GoldPriceSource: PriceInfo] = [:]

    private var timer: Timer?
    private let historyManager = PriceHistoryManager.shared
    private let officialChartService = OfficialIntradayChartService.shared
    private var fetchGeneration: Int = 0

    init() {}

    // MARK: - Fetching lifecycle

    func startFetching() {
        fetchAllPrices()
        restartRefreshTimer()
    }

    func stopFetching() {
        timer?.invalidate()
        timer = nil
    }

    func reloadRefreshIntervalFromSettings() {
        restartRefreshTimer()
    }

    func setDataSource(_ source: GoldPriceSource) {
        self.currentSource = source
    }

    func fetchAllPrices() {
        isLoading = true
        fetchGeneration += 1
        let generation = fetchGeneration
        var snapshot = allSourcePrices
        let group = DispatchGroup()

        group.enter()
        fetchJDZsFinanceGoldPrice { [weak self] info in
            DispatchQueue.main.async {
                guard let self = self else {
                    group.leave()
                    return
                }
                if generation == self.fetchGeneration, let info {
                    snapshot[.jdZsFinance] = info
                    if let p = info.priceDouble {
                        self.historyManager.recordPrice(p, for: GoldPriceSource.jdZsFinance.rawValue)
                    }
                }
                group.leave()
            }
        }

        group.enter()
        fetchJDMsFinanceGoldPrice { [weak self] info in
            DispatchQueue.main.async {
                guard let self = self else {
                    group.leave()
                    return
                }
                if generation == self.fetchGeneration, let info {
                    snapshot[.jdMsFinance] = info
                    if let p = info.priceDouble {
                        self.historyManager.recordPrice(p, for: GoldPriceSource.jdMsFinance.rawValue)
                    }
                }
                group.leave()
            }
        }

        group.enter()
        fetchSGEGoldPrice { [weak self] info in
            DispatchQueue.main.async {
                guard let self = self else {
                    group.leave()
                    return
                }
                if generation == self.fetchGeneration, let info {
                    snapshot[.sgeAu9999] = info
                    if let p = info.priceDouble {
                        self.historyManager.recordPrice(p, for: GoldPriceSource.sgeAu9999.rawValue)
                    }
                }
                group.leave()
            }
        }

        group.enter()
        fetchInternationalGold { [weak self] results in
            DispatchQueue.main.async {
                guard let self = self else {
                    group.leave()
                    return
                }
                if generation == self.fetchGeneration {
                    for (source, info) in results {
                        snapshot[source] = info
                        if let p = info.priceDouble {
                            self.historyManager.recordPrice(p, for: source.rawValue)
                        }
                    }
                }
                group.leave()
            }
        }

        group.notify(queue: .main) { [weak self] in
            guard let self = self, generation == self.fetchGeneration else { return }
            self.allSourcePrices = snapshot
            self.lastUpdateTime = Date()
            self.isLoading = false
        }
    }

    func forceRefreshAllSources(completion: (() -> Void)? = nil) {
        fetchAllPrices()
        DispatchQueue.main.async { completion?() }
    }

    private func restartRefreshTimer() {
        stopFetching()
        let refreshInterval = historyManager.settings.refreshTimeInterval
        let timer = Timer(timeInterval: refreshInterval, repeats: true) { [weak self] _ in
            self?.fetchAllPrices()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        NSLog("[GoldPrice] 刷新频率已更新为 \(Int(refreshInterval)) 秒")
    }

    // MARK: - Domestic: JD Zheshang

    private func fetchJDZsFinanceGoldPrice(completion: @escaping (PriceInfo?) -> Void) {
        let urlString = "https://api.jdjygold.com/gw2/generic/jrm/h5/m/stdLatestPrice?productSku=1961543816"
        guard let url = URL(string: urlString) else {
            completion(nil)
            return
        }

        URLSession.shared.dataTask(with: url) { [weak self] data, _, error in
            guard let self = self, error == nil, let data = data else {
                completion(nil)
                return
            }
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let resultData = json["resultData"] as? [String: Any],
                   let datas = resultData["datas"] as? [String: Any] {

                    var info = PriceInfo()
                    info.price = (datas["price"] as? String) ?? "--"
                    info.yesterdayPrice = (datas["yesterdayPrice"] as? String) ?? "--"
                    info.changeRate = (datas["upAndDownRate"] as? String) ?? ""
                    info.changeAmount = (datas["upAndDownAmt"] as? String) ?? ""

                    self.enrichDomesticInfoWithOfficialSeries(info, source: .jdZsFinance, completion: completion)
                } else {
                    completion(nil)
                }
            } catch {
                print("京东浙商解析失败: \(error.localizedDescription)")
                completion(nil)
            }
        }.resume()
    }

    // MARK: - Domestic: JD Minsheng

    private func fetchJDMsFinanceGoldPrice(completion: @escaping (PriceInfo?) -> Void) {
        let urlString = "https://api.jdjygold.com/gw/generic/hj/h5/m/latestPrice?reqData=%7B%7D"
        guard let url = URL(string: urlString) else {
            completion(nil)
            return
        }

        URLSession.shared.dataTask(with: url) { [weak self] data, _, error in
            guard let self = self, error == nil, let data = data else {
                completion(nil)
                return
            }
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let resultData = json["resultData"] as? [String: Any],
                   let datas = resultData["datas"] as? [String: Any] {

                    var info = PriceInfo()
                    info.price = (datas["price"] as? String) ?? "--"
                    info.yesterdayPrice = (datas["yesterdayPrice"] as? String) ?? "--"
                    info.changeRate = (datas["upAndDownRate"] as? String) ?? ""
                    info.changeAmount = (datas["upAndDownAmt"] as? String) ?? ""

                    self.enrichDomesticInfoWithOfficialSeries(info, source: .jdMsFinance, completion: completion)
                } else {
                    completion(nil)
                }
            } catch {
                print("京东民生解析失败: \(error.localizedDescription)")
                completion(nil)
            }
        }.resume()
    }

    // MARK: - International: Sina Finance (London Gold + New York Gold)

    private func fetchInternationalGold(completion: @escaping ([GoldPriceSource: PriceInfo]) -> Void) {
        let urlString = "https://hq.sinajs.cn/list=hf_XAU,hf_GC"
        guard let url = URL(string: urlString) else {
            completion([:])
            return
        }

        var request = URLRequest(url: url)
        request.setValue("https://finance.sina.com.cn", forHTTPHeaderField: "Referer")
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")

        URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            guard let self = self, error == nil, let data = data else {
                completion([:])
                return
            }

            let text = self.decodeResponseData(data)
            guard !text.isEmpty else {
                completion([:])
                return
            }

            let lines = text.components(separatedBy: ";").filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

            DispatchQueue.main.async {
                var results: [GoldPriceSource: PriceInfo] = [:]

                for line in lines {
                    if line.contains("hf_XAU") {
                        if let info = self.parseSinaLine(line, source: .londonGold) {
                            results[.londonGold] = info
                        }
                    } else if line.contains("hf_GC") {
                        if let info = self.parseSinaLine(line, source: .newyorkGold) {
                            results[.newyorkGold] = info
                        }
                    }
                }

                completion(results)
            }
        }.resume()
    }

    // MARK: - Sina response parsing

    private func decodeResponseData(_ data: Data) -> String {
        // Try GB18030 first (Sina uses this encoding)
        let gb18030 = CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
        )
        if let str = String(data: data, encoding: String.Encoding(rawValue: gb18030)) {
            return str
        }
        if let str = String(data: data, encoding: .utf8) {
            return str
        }
        if let str = String(data: data, encoding: .ascii) {
            return str
        }
        return ""
    }

    /// Parse a single Sina hq line like:
    /// var hq_str_hf_XAU="5191.60,5141.430,5191.60,5191.90,5210.20,5122.02,16:41:00,5141.43,...";
    /// Fields: [0]=current, [1]=yesterday(primary), [4]=dayHigh, [5]=dayLow, [7]=yesterday(backup)
    private func parseSinaLine(_ line: String, source: GoldPriceSource) -> PriceInfo? {
        guard let quoteStart = line.firstIndex(of: "\""),
              let quoteEnd = line.lastIndex(of: "\""),
              quoteStart < quoteEnd else { return nil }

        let content = String(line[line.index(after: quoteStart)..<quoteEnd])
        let fields = content.components(separatedBy: ",")
        guard fields.count >= 8 else { return nil }

        guard let currentPrice = Double(fields[0].trimmingCharacters(in: .whitespaces)) else { return nil }

        let yesterdayStr = fields[1].trimmingCharacters(in: .whitespaces)
        let yesterdayBackup = fields[7].trimmingCharacters(in: .whitespaces)
        let yesterdayPrice = Double(yesterdayStr) ?? Double(yesterdayBackup) ?? 0

        var info = PriceInfo()
        info.price = String(format: "%.2f", currentPrice)
        info.yesterdayPrice = String(format: "%.2f", yesterdayPrice)

        if fields.count > 4, let high = Double(fields[4].trimmingCharacters(in: .whitespaces)) {
            info.dayHigh = String(format: "%.2f", high)
        }
        if fields.count > 5, let low = Double(fields[5].trimmingCharacters(in: .whitespaces)) {
            info.dayLow = String(format: "%.2f", low)
        }

        if yesterdayPrice > 0 {
            let change = currentPrice - yesterdayPrice
            let changePercent = (change / yesterdayPrice) * 100
            let sign = change >= 0 ? "+" : ""
            info.changeAmount = "\(sign)\(String(format: "%.2f", change))"
            info.changeRate = "\(sign)\(String(format: "%.2f", changePercent))%"
        }

        return info
    }

    // MARK: - High/Low from history

    private func enrichDomesticInfoWithOfficialSeries(
        _ info: PriceInfo,
        source: GoldPriceSource,
        completion: @escaping (PriceInfo?) -> Void
    ) {
        officialChartService.fetchIntradaySeries(for: source) { [weak self] result in
            guard let self else {
                completion(info)
                return
            }

            var enrichedInfo = info

            switch result {
            case .success(let series):
                self.applyHighLow(from: series, to: &enrichedInfo)
                self.historyManager.recordPrices(series.records, for: source.rawValue)
            case .failure:
                if let latestSeries = self.officialChartService.latestSeries(for: source) {
                    self.applyHighLow(from: latestSeries, to: &enrichedInfo)
                    self.historyManager.recordPrices(latestSeries.records, for: source.rawValue)
                } else {
                    DispatchQueue.main.async {
                        self.updateHighLow(&enrichedInfo, source: source)
                        completion(enrichedInfo)
                    }
                    return
                }
            }

            completion(enrichedInfo)
        }
    }

    private func applyHighLow(from series: IntradayChartSeries, to info: inout PriceInfo) {
        if let high = series.high {
            info.dayHigh = String(format: "%.2f", high)
        }
        if let low = series.low {
            info.dayLow = String(format: "%.2f", low)
        }

        if let price = info.priceDouble {
            if Double(info.dayHigh) == nil || info.dayHigh == "--" {
                info.dayHigh = String(format: "%.2f", price)
            }
            if Double(info.dayLow) == nil || info.dayLow == "--" {
                info.dayLow = String(format: "%.2f", price)
            }
        }
    }

    private func updateHighLow(_ info: inout PriceInfo, source: GoldPriceSource) {
        let (high, low) = historyManager.getHighLow(for: source.rawValue)
        if let h = high {
            let currentHigh = Double(info.dayHigh) ?? 0
            info.dayHigh = String(format: "%.2f", max(h, currentHigh))
        }
        if let l = low {
            let currentLow = Double(info.dayLow)
            if let cl = currentLow, cl > 0 {
                info.dayLow = String(format: "%.2f", min(l, cl))
            } else {
                info.dayLow = String(format: "%.2f", l)
            }
        }
        if let p = info.priceDouble {
            if Double(info.dayHigh) == nil || info.dayHigh == "--" {
                info.dayHigh = String(format: "%.2f", p)
            }
            if Double(info.dayLow) == nil || info.dayLow == "--" {
                info.dayLow = String(format: "%.2f", p)
            }
        }
    }

    // MARK: - Domestic: Shanghai Gold Exchange (Au99.99)

    private func fetchSGEGoldPrice(completion: @escaping (PriceInfo?) -> Void) {
        guard let url = URL(string: "https://www.sge.com.cn/graph/quotations") else {
            completion(nil)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.setValue("https://www.sge.com.cn/", forHTTPHeaderField: "Referer")
        request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
        request.httpBody = "instid=Au99.99".data(using: .utf8)

        URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            guard let self = self, error == nil, let data = data else {
                self?.fetchSGEYesterdayPrice(currentInfo: nil, completion: completion)
                return
            }

            do {
                guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    self.fetchSGEYesterdayPrice(currentInfo: nil, completion: completion)
                    return
                }

                let prices = json["data"] as? [String] ?? []
                // Take the last non-zero price
                let currentPrice = prices.reversed().compactMap { Double($0) }.first { $0 > 0 }
                guard let currentPrice else {
                    self.fetchSGEYesterdayPrice(currentInfo: nil, completion: completion)
                    return
                }

                var info = PriceInfo()
                info.price = String(format: "%.2f", currentPrice)

                if let minVal = json["min"] as? Double, minVal > 0 {
                    info.dayLow = String(format: "%.2f", minVal)
                } else if let minVal = json["min"] as? String, let v = Double(minVal), v > 0 {
                    info.dayLow = String(format: "%.2f", v)
                }
                if let maxVal = json["max"] as? Double, maxVal > 0 {
                    info.dayHigh = String(format: "%.2f", maxVal)
                } else if let maxVal = json["max"] as? String, let v = Double(maxVal), v > 0 {
                    info.dayHigh = String(format: "%.2f", v)
                }

                // Record intraday series from the minute-by-minute data
                if let times = json["times"] as? [String] {
                    let records = zip(times, prices).compactMap { (timeStr, priceStr) -> PriceRecord? in
                        guard let price = Double(priceStr), price > 0 else { return nil }
                        let cal = Calendar.current
                        let now = Date()
                        let comps = timeStr.split(separator: ":").compactMap { Int($0) }
                        guard comps.count == 2 else { return nil }
                        guard let date = cal.date(bySettingHour: comps[0], minute: comps[1], second: 0, of: now) else { return nil }
                        return PriceRecord(timestamp: date, price: price)
                    }
                    self.historyManager.recordPrices(records, for: GoldPriceSource.sgeAu9999.rawValue)
                }

                self.fetchSGEYesterdayPrice(currentInfo: info, completion: completion)
            } catch {
                self.fetchSGEYesterdayPrice(currentInfo: nil, completion: completion)
            }
        }.resume()
    }

    private func fetchSGEYesterdayPrice(currentInfo: PriceInfo?, completion: @escaping (PriceInfo?) -> Void) {
        guard var info = currentInfo,
              let currentPrice = info.priceDouble,
              let url = URL(string: "https://www.sge.com.cn/graph/Dailyhq") else {
            completion(currentInfo)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.setValue("https://www.sge.com.cn/sjzx/mrhq", forHTTPHeaderField: "Referer")
        request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
        request.httpBody = "instid=Au99.99".data(using: .utf8)

        URLSession.shared.dataTask(with: request) { data, _, error in
            guard error == nil,
                  let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let timeArray = json["time"] as? [[Any]],
                  let lastRow = timeArray.last,
                  lastRow.count >= 3 else {
                completion(info)
                return
            }

            let yesterdayClose: Double?
            if let v = lastRow[2] as? Double {
                yesterdayClose = v
            } else if let s = lastRow[2] as? String {
                yesterdayClose = Double(s)
            } else {
                yesterdayClose = nil
            }

            if let yp = yesterdayClose, yp > 0 {
                info.yesterdayPrice = String(format: "%.2f", yp)
                let change = currentPrice - yp
                let changePercent = change / yp * 100
                let sign = change >= 0 ? "+" : ""
                info.changeAmount = "\(sign)\(String(format: "%.2f", change))"
                info.changeRate = "\(sign)\(String(format: "%.2f", changePercent))%"
            }

            completion(info)
        }.resume()
    }

    deinit {
        stopFetching()
    }
}
