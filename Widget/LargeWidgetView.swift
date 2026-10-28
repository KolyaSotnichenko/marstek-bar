import MarstekKit
import SwiftUI
import WidgetKit

struct LargeWidgetView: View {
    let entry: PayloadEntry

    var body: some View {
        let model = DashboardModel(payload: entry.payload, now: entry.date, language: AppGroup.language.resolved())
        Group {
            if model.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "battery.100percent.bolt").font(.largeTitle).foregroundStyle(.secondary)
                    Text(model.text.openAppHint)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
            } else {
                DashboardView(model: model)
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }
}
