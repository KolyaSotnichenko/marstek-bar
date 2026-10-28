import Foundation

/// Below this, a flow counts as idle (spec).
public let idleThresholdW: Double = 10

/// Net power into the battery (positive = charging). Whether socket load passes
/// through from the grid while charging is unverified; change only this function.
public func netBatteryPowerW(gridPowerW: Double, socketPowerW: Double) -> Double {
    gridPowerW - socketPowerW
}

public enum FlowState: Equatable, Sendable, Codable {
    case idle
    case active(watts: Double)
}

/// The diagram's branches: grid → battery, battery → home, battery → socket.
public struct PowerFlows: Equatable, Sendable {
    public var grid: FlowState
    public var home: FlowState
    public var socket: FlowState

    public init(grid: FlowState, home: FlowState, socket: FlowState) {
        self.grid = grid
        self.home = home
        self.socket = socket
    }

    public static func from(_ s: BatterySnapshot) -> PowerFlows {
        let grid = s.gridPowerW ?? 0
        let socket = s.socketPowerW ?? 0
        return PowerFlows(
            grid: grid >= idleThresholdW ? .active(watts: grid) : .idle,
            home: grid <= -idleThresholdW ? .active(watts: -grid) : .idle,
            socket: socket >= idleThresholdW ? .active(watts: socket) : .idle
        )
    }
}
