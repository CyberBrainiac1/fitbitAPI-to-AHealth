import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: SyncViewModel

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label(model.isConnected ? "Fitbit connected" : "Connect your Fitbit account",
                          systemImage: model.isConnected ? "checkmark.circle.fill" : "link.circle")
                        .foregroundStyle(model.isConnected ? .green : .primary)
                    if !model.isConnected {
                        Button("Connect Fitbit") { Task { await model.connectFitbit() } }
                            .buttonStyle(.borderedProminent)
                    } else {
                        Button("Disconnect", role: .destructive) { model.disconnect() }
                    }
                } header: { Text("Account") }

                Section("Import range") {
                    DatePicker("From", selection: $model.startDate, in: ...Date(), displayedComponents: .date)
                    DatePicker("Through", selection: $model.endDate, in: model.startDate...Date(), displayedComponents: .date)
                }

                Section {
                    Button { Task { await model.sync() } } label: {
                        HStack {
                            if model.isSyncing { ProgressView().padding(.trailing, 6) }
                            Text(model.isSyncing ? "Importing…" : "Sync to Apple Health")
                        }
                    }
                    .disabled(!model.isConnected || model.isSyncing)
                    if let last = model.lastSync {
                        LabeledContent("Last sync", value: last.formatted(date: .abbreviated, time: .shortened))
                    }
                    if !model.status.isEmpty { Text(model.status).font(.footnote).foregroundStyle(.secondary) }
                } footer: {
                    Text("Keep the Fitbit app syncing your Inspire first. This app reads Fitbit's cloud API and writes supported records to HealthKit without replacing existing Apple Health data.")
                }
            }
            .navigationTitle("Fitbit Health Sync")
            .alert("Sync issue", isPresented: $model.showError) { Button("OK", role: .cancel) {} } message: { Text(model.errorMessage) }
        }
    }
}

