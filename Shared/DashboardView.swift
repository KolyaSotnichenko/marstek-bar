import Charts
import MarstekKit
import SwiftUI
import WidgetKit

/// The large layout from mockup C, shared by the widget and the menu panel.
struct DashboardView: View {
    let model: DashboardModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 14) {
                SocRing(model: model)
                VStack(alignment: .leading, spacing: 8) {
                    Text(model.title).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    FlowDiagram(flows: model.flows, socFraction: model.socFraction, text: model.text)
                    HStack(alignment: .firstTextBaseline) {
                        Text(model.forecastLabel).font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Text(model.forecastText).font(.headline).monospacedDigit()
                    }
                }
            }
            HStack {
                Label(model.tempText, systemImage: "thermometer.medium")
                Spacer()
                Text(model.todayText)
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Text(model.text.chartTitle).font(.caption2).foregroundStyle(.secondary)
            SocChart(segments: model.chart, end: model.chartEnd)
            HStack {
                Text(model.text.chartStart); Spacer(); Text(model.text.chartMiddle); Spacer(); Text(model.text.chartNow)
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)

            Text(model.updatedText)
                .font(.caption2)
                .foregroundStyle(model.isStale ? AnyShapeStyle(.orange) : AnyShapeStyle(.tertiary))
        }
    }
}

private struct SocRing: View {
    let model: DashboardModel
    /// On the desktop an inactive widget is drawn monochrome; colour alone can't
    /// separate fill from track there, so contrast comes from opacity instead.
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        let fullColor = renderingMode == .fullColor
        ZStack {
            Circle().stroke(fullColor ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.primary.opacity(0.15)), lineWidth: 10)
            Circle()
                .trim(from: 0, to: model.socFraction)
                .stroke(fullColor ? AnyShapeStyle(.green) : AnyShapeStyle(.primary),
                        style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text(model.socText).font(.title2.bold()).monospacedDigit()
                Text(model.storedText).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .frame(width: 96, height: 96)
    }
}

/// Grid → battery → home, plus battery → socket below. Icons share one fixed-height row.
private struct FlowDiagram: View {
    let flows: PowerFlows
    let socFraction: Double
    let text: L10n

    var body: some View {
        Grid(horizontalSpacing: 4, verticalSpacing: 2) {
            GridRow {
                Node(symbol: "bolt.horizontal", label: text.grid, flow: flows.grid)
                Connector(flow: flows.grid, tint: .blue)
                Node(symbol: batterySymbol, label: text.battery, flow: .idle)
                Connector(flow: flows.home, tint: .orange)
                Node(symbol: "house", label: text.home, flow: flows.home)
            }
            GridRow {
                Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                Connector(flow: flows.socket, tint: .orange, axis: .vertical)
                Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
            }
            GridRow {
                Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                Node(symbol: "poweroutlet.type.f", label: text.socket, flow: flows.socket)
                Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
            }
        }
    }

    private var batterySymbol: String {
        switch socFraction {
        case ..<0.13: "battery.0percent"
        case ..<0.38: "battery.25percent"
        case ..<0.63: "battery.50percent"
        case ..<0.88: "battery.75percent"
        default: "battery.100percent"
        }
    }
}

private struct Node: View {
    let symbol: String
    let label: String
    let flow: FlowState

    var body: some View {
        VStack(spacing: 2) {
            Image(systemName: symbol)
                .font(.system(size: 17))
                .frame(height: 22)
            Text(label).font(.system(size: 9)).foregroundStyle(.secondary)
            Text(watts).font(.system(size: 9, weight: .semibold)).monospacedDigit()
                .foregroundStyle(.orange)
        }
        .fixedSize()
    }

    private var watts: String {
        if case .active(let w) = flow { return wattsText(w) }
        return " "
    }
}

private struct Connector: View {
    let flow: FlowState
    let tint: Color
    var axis: Axis = .horizontal

    var body: some View {
        let active = flow != .idle
        let line = Line(axis: axis)
            .stroke(active ? tint : Color.secondary.opacity(0.5),
                    style: StrokeStyle(lineWidth: 2, dash: active ? [6, 4] : [2, 4]))
        switch axis {
        case .horizontal:
            line.frame(height: 2)
                .frame(minWidth: 14, maxWidth: .infinity)
                .offset(y: -12) // level with the icons, not the labels
        case .vertical:
            // Starts below the battery's watts line and stops above the socket icon.
            line.frame(width: 2, height: 14)
        }
    }
}

private struct Line: Shape {
    let axis: Axis

    func path(in rect: CGRect) -> Path {
        Path { p in
            if axis == .horizontal {
                p.move(to: CGPoint(x: rect.minX, y: rect.midY))
                p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            } else {
                p.move(to: CGPoint(x: rect.midX, y: rect.minY))
                p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            }
        }
    }
}

private struct SocChart: View {
    let segments: [[HistorySample]]
    let end: Date

    var body: some View {
        Chart {
            ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                ForEach(segment, id: \.t) { sample in
                    if segment.count == 1 {
                        // A lone sample between gaps has no line to draw; show it as a dot.
                        PointMark(x: .value("t", sample.t), y: .value("soc", sample.soc))
                            .symbolSize(12)
                            .foregroundStyle(.green)
                    } else {
                        LineMark(x: .value("t", sample.t), y: .value("soc", sample.soc),
                                 series: .value("segment", index))
                            .foregroundStyle(.green)
                            .interpolationMethod(.monotone)
                    }
                }
            }
        }
        .chartYScale(domain: 0...100)
        .chartXScale(domain: end.addingTimeInterval(-86400)...end)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .frame(height: 80)
    }
}
