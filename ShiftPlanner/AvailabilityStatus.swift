import SwiftUI

enum AvailabilityStatus: String, CaseIterable, Codable {
    case available
    case ifNeeded
    case unavailable

    var color: Color {
        switch self {
        case .available:
            return .green
        case .ifNeeded:
            return .yellow
        case .unavailable:
            return .red
        }
    }

    var displayName: String {
        switch self {
        case .available:
            return "Available"
        case .ifNeeded:
            return "If Needed"
        case .unavailable:
            return "Unavailable"
        }
    }

    func next() -> AvailabilityStatus {
        switch self {
        case .available:
            return .ifNeeded
        case .ifNeeded:
            return .unavailable
        case .unavailable:
            return .available
        }
    }
}
