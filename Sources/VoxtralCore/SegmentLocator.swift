import Foundation

public enum SegmentLocator {
    /// Index of the segment active at `time`: the last segment whose start <= time.
    public static func index(at time: TimeInterval,
                             in segments: [(start: TimeInterval, end: TimeInterval)]) -> Int? {
        guard time >= 0 else { return nil }
        var result: Int?
        for (i, s) in segments.enumerated() where s.start <= time { result = i }
        return result
    }
}
