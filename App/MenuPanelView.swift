import AppKit
import MarstekKit
import SwiftUI

struct MenuPanelView: View {
    let state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Re-evaluated every 30 s so the stale marker appears without new data.
            TimelineView(.periodic(from: .now, by: 30)) { context in
                let model = state.dashboard(now: context.date)
                if model.isEmpty {
                    Text(state.status.isEmpty ? model.text.noData : state.status)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 120)
                } else {
                    DashboardView(model: model)
                }
            }
            if !state.status.isEmpty, state.payload != nil {
                Text(state.status).font(.caption2).foregroundStyle(.secondary)
            }
            Divider()
            HStack {
                SettingsLink { Text(state.text.settingsButton) }
                    .simultaneousGesture(TapGesture().onEnded { NSApp.activate() })
                Spacer()
                Button(state.text.quit) { NSApp.terminate(nil) }
            }
        }
        .padding(16)
        .frame(width: 364)
    }
}
