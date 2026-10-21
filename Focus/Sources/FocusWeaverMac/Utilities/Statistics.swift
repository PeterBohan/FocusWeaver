import Foundation

extension Array where Element == Double {
    var average: Double {
        guard !isEmpty else { return 0 }
        return reduce(0, +) / Double(count)
    }
}

extension Double {
    var percentString: String {
        String(format: "%.0f%%", self * 100)
    }
}
