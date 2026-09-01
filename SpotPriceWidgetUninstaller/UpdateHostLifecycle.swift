import Darwin
import Foundation

enum UpdateHostLifecycleError: LocalizedError {
    case hostDidNotExit

    var errorDescription: String? {
        switch self {
        case .hostDidNotExit:
            "The current app did not close in time, so the update was not installed."
        }
    }
}

enum UpdateHostLifecycle {
    static func waitForExit(
        processIdentifier: pid_t,
        timeout: TimeInterval = 30,
        pollInterval: TimeInterval = 0.05
    ) async throws {
        guard processIdentifier > 0 else {
            throw UpdateHostLifecycleError.hostDidNotExit
        }

        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(timeout))

        while processExists(processIdentifier) {
            guard clock.now < deadline else {
                throw UpdateHostLifecycleError.hostDidNotExit
            }
            let nanoseconds = UInt64(max(pollInterval, 0.01) * 1_000_000_000)
            try await Task.sleep(nanoseconds: nanoseconds)
        }
    }

    private static func processExists(_ processIdentifier: pid_t) -> Bool {
        if kill(processIdentifier, 0) == 0 {
            return true
        }
        return errno != ESRCH
    }
}
