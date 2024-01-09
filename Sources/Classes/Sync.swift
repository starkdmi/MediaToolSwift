#if os(visionOS)
import Foundation

private class SyncType<ResultType> {
    var result: Result<ResultType, Error>?
}

internal class Sync {
    /// Awaits an async execution from a synchronous context
    static func wait<T>(_ function: @escaping () async throws -> T) throws -> T {
        let response = SyncType<T>()

        let semaphore = DispatchSemaphore(value: 0)
        Task {
            do {
                let value = try await function()
                response.result = .success(value)
            } catch {
                response.result = .failure(error)
            }
            semaphore.signal()
        }
        semaphore.wait()

        return try response.result!.get()
    }
}
#endif
