import MarstekKit
import SwiftUI

struct SettingsView: View {
    @Bindable var state: AppState

    var body: some View {
        let text = state.text
        Form {
            Section(text.sectionBattery) {
                HStack {
                    TextField(text.ipAddress, text: $state.host)
                    Button(text.findAutomatically) { Task { await state.discover() } }
                }
                TextField(text.port, value: $state.port, format: .number.grouping(.never))
                if !state.status.isEmpty {
                    Text(state.status).font(.caption).foregroundStyle(.secondary)
                }
            }
            Section(text.sectionForecast) {
                Stepper(value: $state.dodPercent, in: 30...88, step: 1) {
                    Text(text.depthOfDischarge(Int(state.dodPercent)))
                }
                Text(text.dodHint)
                    .font(.caption).foregroundStyle(.secondary)
                Toggle(text.invertSign, isOn: $state.invertSign)
            }
            Section(text.sectionApp) {
                Picker(text.languageLabel, selection: $state.language) {
                    ForEach(AppLanguage.allCases, id: \.self) { Text(text.languageName($0)).tag($0) }
                }
                Toggle(text.showInMenuBar, isOn: $state.showMenuBarIcon)
                Toggle(text.launchAtLogin, isOn: Binding(
                    get: { state.launchAtLogin }, set: { state.setLaunchAtLogin($0) }))
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
    }
}
