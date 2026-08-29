import Foundation

struct FitbitToken: Codable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date
    let userID: String
}

struct FitbitActivitySummary: Decodable {
    struct Summary: Decodable { let steps: Double?; let distances: [Distance]?; let caloriesOut: Double?; let caloriesBMR: Double? }
    struct Distance: Decodable { let activity: String; let distance: Double }
    let summary: Summary
}

struct FitbitTimeSeries: Decodable {
    struct Item: Decodable { let dateTime: String; let value: String }
    let items: [Item]

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let object = try container.decode([String: [Item]].self)
        items = object.values.first ?? []
    }
}

struct FitbitSleepResponse: Decodable {
    struct Sleep: Decodable { let logId: Int64; let startTime: String; let endTime: String; let isMainSleep: Bool? }
    let sleep: [Sleep]
}

struct FitbitBodyResponse: Decodable {
    struct Entry: Decodable { let logId: Int64; let date: String; let time: String; let weight: Double?; let fat: Double? }
    let weight: [Entry]
}

struct ImportRecord {
    enum Kind { case steps, distance, activeEnergy, basalEnergy, heartRate, restingHeartRate, sleep, weight, bodyFat, water, oxygen, respiratoryRate, hrv, temperature }
    let id: String
    let kind: Kind
    let start: Date
    let end: Date
    let value: Double
}

