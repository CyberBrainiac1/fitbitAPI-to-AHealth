import Foundation
import HealthKit

struct FitbitImporter {
    let client: FitbitClient
    private let calendar = Calendar(identifier: .gregorian)
    private let day = DateFormatter.fitbitDay

    func records(from start: Date, through end: Date) async throws -> [ImportRecord] {
        var result: [ImportRecord] = []
        var date = calendar.startOfDay(for: start)
        let last = calendar.startOfDay(for: end)
        while date <= last {
            let value = day.string(from: date)
            async let activity = client.get("activities/date/\(value).json", as: FitbitActivitySummary.self)
            async let sleep = client.get("sleep/date/\(value).json", as: FitbitSleepResponse.self)
            async let body = client.get("body/log/weight/date/\(value).json", as: FitbitBodyResponse.self)
            if let a = try? await activity { result += activityRecords(a, date: date, key: value) }
            if let s = try? await sleep { result += sleepRecords(s) }
            if let b = try? await body { result += bodyRecords(b) }
            result += await optionalRecords(date: date, key: value)
            date = calendar.date(byAdding: .day, value: 1, to: date)!
        }
        return result
    }

    private func activityRecords(_ response: FitbitActivitySummary, date: Date, key: String) -> [ImportRecord] {
        let end = calendar.date(byAdding: .day, value: 1, to: date)!
        var records: [ImportRecord] = []
        func add(_ kind: ImportRecord.Kind, _ name: String, _ value: Double?) {
            guard let value, value > 0 else { return }
            records.append(.init(id: "\(name)-\(key)", kind: kind, start: date, end: end, value: value))
        }
        add(.steps, "steps", response.summary.steps)
        add(.distance, "distance", response.summary.distances?.first(where: { $0.activity == "total" })?.distance)
        add(.activeEnergy, "active", response.summary.caloriesOut.map { $0 - (response.summary.caloriesBMR ?? 0) })
        add(.basalEnergy, "bmr", response.summary.caloriesBMR)
        return records
    }

    private func sleepRecords(_ response: FitbitSleepResponse) -> [ImportRecord] {
        response.sleep.compactMap {
            guard let start = DateFormatter.fitbitTimestamp.date(from: $0.startTime), let end = DateFormatter.fitbitTimestamp.date(from: $0.endTime) else { return nil }
            return ImportRecord(id: "sleep-\($0.logId)", kind: .sleep, start: start, end: end, value: 1)
        }
    }

    private func bodyRecords(_ response: FitbitBodyResponse) -> [ImportRecord] {
        response.weight.flatMap { entry -> [ImportRecord] in
            guard let date = DateFormatter.fitbitBody.date(from: "\(entry.date) \(entry.time)") else { return [] }
            var values: [ImportRecord] = []
            if let weight = entry.weight { values.append(.init(id: "weight-\(entry.logId)", kind: .weight, start: date, end: date, value: weight)) }
            if let fat = entry.fat { values.append(.init(id: "fat-\(entry.logId)", kind: .bodyFat, start: date, end: date, value: fat / 100)) }
            return values
        }
    }

    private func optionalRecords(date: Date, key: String) async -> [ImportRecord] {
        var records: [ImportRecord] = []
        // Optional Fitbit endpoints return no data for devices/accounts that do not support a metric.
        let specifications: [(String, ImportRecord.Kind, String, Double)] = [
            ("foods/log/water/date/\(key).json", .water, "water", 0.001),
            ("spo2/date/\(key).json", .oxygen, "spo2", 0.01),
            ("br/date/\(key).json", .respiratoryRate, "breathing-rate", 1),
            ("hrv/date/\(key).json", .hrv, "hrv", 1),
            ("temp/core/date/\(key).json", .temperature, "temperature", 1)
        ]
        for (path, kind, name, multiplier) in specifications {
            if let payload = try? await client.get(path, as: FlexibleMetricResponse.self) {
                for point in payload.points {
                    let timestamp = point.date.flatMap(DateFormatter.fitbitTimestamp.date) ?? date
                    records.append(.init(id: "\(name)-\(key)-\(timestamp.timeIntervalSince1970)", kind: kind, start: timestamp, end: timestamp, value: point.value * multiplier))
                }
            }
        }
        if let heart = try? await client.get("activities/heart/date/\(key)/1d/1min.json", as: FitbitHeartResponse.self) {
            if let resting = heart.restingHeartRate {
                records.append(.init(id: "resting-heart-\(key)", kind: .restingHeartRate, start: date, end: date, value: resting))
            }
            for (index, point) in heart.points.enumerated() {
                guard let timestamp = DateFormatter.fitbitTime.date(from: "\(key) \(point.time)") else { continue }
                records.append(.init(id: "heart-\(key)-\(index)", kind: .heartRate, start: timestamp, end: timestamp, value: point.value))
            }
        }
        return records
    }
}

private struct FitbitHeartResponse: Decodable {
    struct Point: Decodable { let time: String; let value: Double }
    struct Day: Decodable { struct Value: Decodable { let restingHeartRate: Double? }; let value: Value }
    struct Intraday: Decodable { let dataset: [Point] }
    let activitiesHeart: [Day]
    let activitiesHeartIntraday: Intraday?
    var restingHeartRate: Double? { activitiesHeart.first?.value.restingHeartRate }
    var points: [Point] { activitiesHeartIntraday?.dataset ?? [] }
    enum CodingKeys: String, CodingKey { case activitiesHeart = "activities-heart"; case activitiesHeartIntraday = "activities-heart-intraday" }
}

private struct FlexibleMetricResponse: Decodable {
    struct Point { let date: String?; let value: Double }
    let points: [Point]

    init(from decoder: Decoder) throws {
        let raw = try JSONSerialization.jsonObject(with: JSONEncoder().encode(try JSONValue(from: decoder)))
        var found: [Point] = []
        func walk(_ value: Any, date: String? = nil) {
            if let dictionary = value as? [String: Any] {
                let nextDate = (dictionary["dateTime"] ?? dictionary["date"] ?? dictionary["minute"]) as? String ?? date
                for key in ["value", "avg", "amount", "breathingRate", "dailyRmssd", "coreTemperature"] {
                    if let number = dictionary[key] as? NSNumber { found.append(Point(date: nextDate, value: number.doubleValue)); break }
                }
                dictionary.values.forEach { walk($0, date: nextDate) }
            } else if let array = value as? [Any] { array.forEach { walk($0, date: date) } }
        }
        walk(raw); points = found
    }
}

private enum JSONValue: Codable {
    case object([String: JSONValue]), array([JSONValue]), string(String), number(Double), bool(Bool), null
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode([String: JSONValue].self) { self = .object(v) }
        else if let v = try? c.decode([JSONValue].self) { self = .array(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode(Double.self) { self = .number(v) }
        else { self = .bool(try c.decode(Bool.self)) }
    }
}

@MainActor
final class HealthStore {
    private let store = HKHealthStore()

    func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else { throw SyncError.healthUnavailable }
        try await store.requestAuthorization(toShare: Set(Self.types.values), read: Set(Self.types.values))
    }

    func save(_ records: [ImportRecord]) async throws -> Int {
        var saved = 0
        for record in records {
            guard let type = Self.types[record.kind] else { continue }
            let predicate = HKQuery.predicateForObjects(withMetadataKey: HKMetadataKeyExternalUUID, allowedValues: [record.id])
            let existing: [HKSample] = try await withCheckedThrowingContinuation { continuation in
                store.execute(HKSampleQuery(sampleType: type, predicate: predicate, limit: 1, sortDescriptors: nil) { _, values, error in
                    if let error { continuation.resume(throwing: error) } else { continuation.resume(returning: values ?? []) }
                })
            }
            guard existing.isEmpty else { continue }
            let metadata: [String: Any] = [HKMetadataKeyExternalUUID: record.id, HKMetadataKeySyncIdentifier: record.id, HKMetadataKeySyncVersion: 1, "FitbitSource": "Fitbit Web API"]
            let sample: HKSample
            if record.kind == .sleep {
                sample = HKCategorySample(type: type as! HKCategoryType, value: HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue, start: record.start, end: record.end, metadata: metadata)
            } else {
                sample = HKQuantitySample(type: type as! HKQuantityType, quantity: HKQuantity(unit: Self.unit(for: record.kind), doubleValue: record.value), start: record.start, end: record.end, metadata: metadata)
            }
            try await store.save(sample); saved += 1
        }
        return saved
    }

    private static let types: [ImportRecord.Kind: HKSampleType] = {
        var result: [ImportRecord.Kind: HKSampleType] = [:]
        func q(_ kind: ImportRecord.Kind, _ id: HKQuantityTypeIdentifier) { result[kind] = HKObjectType.quantityType(forIdentifier: id) }
        q(.steps, .stepCount); q(.distance, .distanceWalkingRunning); q(.activeEnergy, .activeEnergyBurned); q(.basalEnergy, .basalEnergyBurned)
        q(.heartRate, .heartRate); q(.restingHeartRate, .restingHeartRate); q(.weight, .bodyMass); q(.bodyFat, .bodyFatPercentage)
        q(.water, .dietaryWater); q(.oxygen, .oxygenSaturation); q(.respiratoryRate, .respiratoryRate); q(.hrv, .heartRateVariabilitySDNN)
        if #available(iOS 16.0, *) { q(.temperature, .appleSleepingWristTemperature) }
        result[.sleep] = HKObjectType.categoryType(forIdentifier: .sleepAnalysis)
        return result
    }()

    private static func unit(for kind: ImportRecord.Kind) -> HKUnit {
        switch kind {
        case .steps: .count(); case .distance: .meterUnit(with: .kilo); case .activeEnergy, .basalEnergy: .kilocalorie()
        case .heartRate, .restingHeartRate: HKUnit.count().unitDivided(by: .minute())
        case .weight: .gramUnit(with: .kilo); case .bodyFat, .oxygen: .percent(); case .water: .liter()
        case .respiratoryRate: HKUnit.count().unitDivided(by: .minute()); case .hrv: .secondUnit(with: .milli)
        case .temperature: .degreeCelsius(); case .sleep: .count()
        }
    }
}

extension DateFormatter {
    static let fitbitDay: DateFormatter = { let f = DateFormatter(); f.locale = .init(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"; return f }()
    static let fitbitTimestamp: DateFormatter = { let f = DateFormatter(); f.locale = .init(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS"; return f }()
    static let fitbitBody: DateFormatter = { let f = DateFormatter(); f.locale = .init(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd HH:mm:ss"; return f }()
    static let fitbitTime: DateFormatter = { let f = DateFormatter(); f.locale = .init(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd HH:mm:ss"; return f }()
}
