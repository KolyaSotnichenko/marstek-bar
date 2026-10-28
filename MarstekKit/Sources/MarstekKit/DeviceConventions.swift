/// How the Venus E 3.0 (FW 150) reports directions. Values from the probe in the
/// spec's «Результати зонду»; the sign entries are defaults until checked live.
public enum DeviceConventions {
    /// `ongrid_power` is positive while charging from the grid. Not yet observed.
    public static let gridChargingIsPositive = false
    /// `total_grid_input_energy` counts energy taken from the grid (grew while idle-topping-up).
    public static let inputCounterIsCharge = true
    /// `offgrid_power` is positive while the battery feeds its own socket. Not yet observed.
    public static let socketPowerIsPositive = true
    /// Replies reach an unbound (ephemeral) sender port.
    public static let needsBoundPort30000 = false
}
