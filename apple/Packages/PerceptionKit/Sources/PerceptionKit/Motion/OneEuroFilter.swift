import Foundation

/// Lowpass filter component of the One Euro Filter.
public struct LowPassFilter: Sendable {
    private var y: Double?
    private var s: Double?

    public init() {}

    public mutating func filter(_ value: Double, alpha: Double) -> Double {
        if let currentS = s {
            let nextS = alpha * value + (1.0 - alpha) * currentS
            s = nextS
            y = value
            return nextS
        } else {
            s = value
            y = value
            return value
        }
    }

    public var lastValue: Double? {
        s
    }

    public mutating func reset() {
        y = nil
        s = nil
    }
}

/// Adaptive low-pass filter providing high responsiveness during fast motion
/// and heavy jitter suppression when stationary.
/// References: Casiez, Roussel, Vogel (CHI 2012) - "1 € Filter"
public final class OneEuroFilter: @unchecked Sendable {
    public var minCutoff: Double
    public var beta: Double
    public var dCutoff: Double

    private var xFilter = LowPassFilter()
    private var dxFilter = LowPassFilter()
    private var lastTimestamp: Double?

    public init(minCutoff: Double = 1.0, beta: Double = 0.01, dCutoff: Double = 1.0) {
        self.minCutoff = minCutoff
        self.beta = beta
        self.dCutoff = dCutoff
    }

    private func alpha(rate: Double, cutoff: Double) -> Double {
        let tau = 1.0 / (2.0 * Double.pi * cutoff)
        let te = 1.0 / rate
        return 1.0 / (1.0 + tau / te)
    }

    /// Filter an incoming scalar sample with presentation timestamp.
    public func filter(_ x: Double, timestamp: Double) -> Double {
        guard let prevT = lastTimestamp else {
            lastTimestamp = timestamp
            return xFilter.filter(x, alpha: 1.0)
        }

        let dt = max(0.0001, timestamp - prevT)
        lastTimestamp = timestamp
        let rate = 1.0 / dt

        // 1. Filter derivative of signal
        let prevX = xFilter.lastValue ?? x
        let dx = (x - prevX) * rate
        let edx = dxFilter.filter(dx, alpha: alpha(rate: rate, cutoff: dCutoff))

        // 2. Compute dynamic cutoff frequency
        let cutoff = minCutoff + beta * abs(edx)

        // 3. Filter signal with dynamic cutoff
        return xFilter.filter(x, alpha: alpha(rate: rate, cutoff: cutoff))
    }

    /// Reset filter state (e.g. after tracking interruption).
    public func reset() {
        xFilter.reset()
        dxFilter.reset()
        lastTimestamp = nil
    }
}
