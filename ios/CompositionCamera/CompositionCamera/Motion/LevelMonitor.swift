import CoreMotion
import Foundation

/// Reports how far the phone is rolled away from level, so horizons come out straight.
final class LevelMonitor: ObservableObject {
    /// Clockwise roll of the phone in degrees (0 = perfectly level in portrait).
    @Published private(set) var rollDegrees: Double = 0
    /// True when the phone points straight up or down, where a horizon level is meaningless.
    @Published private(set) var isFlat = false

    private let manager = CMMotionManager()

    func start() {
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 30
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let gravity = motion?.gravity else { return }
            self.isFlat = abs(gravity.z) > 0.85
            let roll = atan2(gravity.x, -gravity.y) * 180 / .pi
            // Low-pass filter to keep the indicator steady.
            self.rollDegrees = self.rollDegrees * 0.8 + roll * 0.2
        }
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
    }
}
