import Foundation

@MainActor
final class SyncViewModel: ObservableObject {
    @Published var startDate = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
    @Published var endDate = Date()
    @Published var isSyncing = false
    @Published var lastSync: Date?
    @Published var status = ""
    @Published var showError = false
    @Published var errorMessage = ""

    private let fitbit = FitbitClient()
    private let health = HealthStore()
    var isConnected: Bool { fitbit.token != nil }

    func connectFitbit() async {
        do { try await fitbit.authorize(); objectWillChange.send(); status = "Connected. Choose a date range to import." }
        catch { present(error) }
    }

    func disconnect() { fitbit.disconnect(); objectWillChange.send(); status = "Fitbit disconnected." }

    func sync() async {
        isSyncing = true; defer { isSyncing = false }
        do {
            try await health.requestAuthorization()
            status = "Downloading Fitbit records…"
            let records = try await FitbitImporter(client: fitbit).records(from: startDate, through: endDate)
            status = "Saving \(records.count) records to Apple Health…"
            let count = try await health.save(records)
            lastSync = Date(); status = count == 0 ? "Everything in this range was already synced." : "Imported \(count) new Apple Health records."
        } catch { present(error) }
    }

    private func present(_ error: Error) { errorMessage = error.localizedDescription; showError = true; status = "" }
}
