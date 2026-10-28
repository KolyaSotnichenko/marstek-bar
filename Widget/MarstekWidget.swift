import MarstekKit
import SwiftUI
import WidgetKit

struct PayloadEntry: TimelineEntry {
    let date: Date
    let payload: WidgetPayload?
}

/// The widget never touches the network: it reads what the menu bar app saved.
struct PayloadProvider: TimelineProvider {
    func placeholder(in context: Context) -> PayloadEntry {
        PayloadEntry(date: .now, payload: .preview)
    }

    func getSnapshot(in context: Context, completion: @escaping (PayloadEntry) -> Void) {
        completion(PayloadEntry(date: .now, payload: context.isPreview ? .preview : AppGroup.store.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PayloadEntry>) -> Void) {
        let now = Date()
        let payload = AppGroup.store.load()
        var entries = [PayloadEntry(date: now, payload: payload)]
        // An entry at the moment the data turns stale shows the marker even when
        // the app has stopped reloading us (Mac away from home, app quit).
        if let staleAt = payload.map({ $0.snapshot.timestamp.addingTimeInterval(BatterySnapshot.staleAfter + 1) }),
           staleAt > now {
            entries.append(PayloadEntry(date: staleAt, payload: payload))
        }
        // The app reloads us when the content changes, so no polling here.
        completion(Timeline(entries: entries, policy: .never))
    }
}

@main
struct MarstekWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "MarstekWidget", provider: PayloadProvider()) { entry in
            LargeWidgetView(entry: entry)
        }
        .configurationDisplayName("Marstek")
        .description(L10n(AppGroup.language.resolved()).widgetDescription)
        .supportedFamilies([.systemLarge])
    }
}
