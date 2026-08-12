#if os(visionOS)
import Foundation

private final class SyncOperation<ResultType>: @unchecked Sendable {
    private let lock = NSLock()
    private let semaphore = DispatchSemaphore(value: 0)
    private let function: @Sendable () async throws -> ResultType
    private var result: Result<ResultType, Error>?

    init(function: @escaping @Sendable () async throws -> ResultType) {
        self.function = function
    }

    func run() async {
        let result: Result<ResultType, Error>
        do {
            result = .success(try await function())
        } catch {
            result = .failure(error)
        }
        store(result)
    }

    private func store(_ result: Result<ResultType, Error>) {
        lock.lock()
        self.result = result
        lock.unlock()
        semaphore.signal()
    }

    func wait() throws -> ResultType {
        semaphore.wait()
        lock.lock()
        let result = self.result
        lock.unlock()
        return try result!.get()
    }
}

internal class Sync {
    /// Awaits an async execution from a synchronous context
    static func wait<T>(_ function: @escaping @Sendable () async throws -> T) throws -> T {
        let operation = SyncOperation(function: function)
        Task.detached { [operation] in
            await operation.run()
        }
        return try operation.wait()
    }
}
#endif
