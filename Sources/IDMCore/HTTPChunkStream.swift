import Foundation

/// Routes delegate-delivered data into per-task streams, with watermark-based queue backpressure.
/// One router/session is shared across segments so connections remain reusable.
final class HTTPChunkStream: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    struct Opened: Sendable {
        let chunks: AsyncThrowingStream<Data, Error>
        let response: HTTPURLResponse
        let task: URLSessionDataTask
    }
    private final class Pending {
        let chunks: AsyncThrowingStream<Data, Error>.Continuation
        var response: CheckedContinuation<HTTPURLResponse, Error>?
        var buffered = 0
        var suspended = false
        init(chunks:AsyncThrowingStream<Data, Error>.Continuation,response:CheckedContinuation<HTTPURLResponse, Error>) {
            self.chunks = chunks;self.response = response
        }
    }
    private let lock = NSLock()
    private var pending:[Int:Pending] = [:]
    private let highWater = 1024*1024
    private let lowWater = 256*1024

    func open(_ request:URLRequest,session:URLSession) async throws -> Opened {
        let task = session.dataTask(with:request)
        let stream = AsyncThrowingStream<Data, Error>.makeStream()
        let response:HTTPURLResponse = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                lock.lock()
                if Task.isCancelled {
                    lock.unlock();continuation.resume(throwing:CancellationError());return
                }
                pending[task.taskIdentifier] = Pending(chunks:stream.continuation,response:continuation)
                task.resume()
                lock.unlock()
            }
        } onCancel: { task.cancel() }
        return Opened(chunks:stream.stream,response:response,task:task)
    }
    func consumed(_ count:Int,task:URLSessionDataTask) {
        lock.lock();defer { lock.unlock() }
        guard let state = pending[task.taskIdentifier] else { return }
        state.buffered = max(0,state.buffered-count)
        if state.suspended && state.buffered <= lowWater {
            state.suspended = false;task.resume()
        }
    }
    static func sameOrigin(_ left:URL,_ right:URL) -> Bool {
        left.scheme?.lowercased() == right.scheme?.lowercased()
            && left.host?.lowercased() == right.host?.lowercased()
            && (left.port ?? (left.scheme?.lowercased() == "https" ? 443 : 80)) == (right.port ?? (right.scheme?.lowercased() == "https" ? 443 : 80))
    }
    func urlSession(_ session:URLSession,task:URLSessionTask,willPerformHTTPRedirection response:HTTPURLResponse,newRequest request:URLRequest,completionHandler:@escaping @Sendable (URLRequest?) -> Void) {
        var next = request
        if let original = task.originalRequest,let source = original.url,let target = next.url,Self.sameOrigin(source,target) {
            next.setValue(original.value(forHTTPHeaderField:"Authorization"),forHTTPHeaderField:"Authorization")
        } else { next.setValue(nil,forHTTPHeaderField:"Authorization") }
        completionHandler(next)
    }
    func urlSession(_ session:URLSession,dataTask:URLSessionDataTask,didReceive response:URLResponse,completionHandler:@escaping @Sendable (URLSession.ResponseDisposition) -> Void) {
        lock.lock()
        let continuation = pending[dataTask.taskIdentifier]?.response
        pending[dataTask.taskIdentifier]?.response = nil
        lock.unlock()
        if let continuation {
            guard let http = response as? HTTPURLResponse else {
                continuation.resume(throwing:DownloadError.http(0));completionHandler(.cancel);return
            }
            continuation.resume(returning:http)
        }
        completionHandler(.allow)
    }
    func urlSession(_ session:URLSession,dataTask:URLSessionDataTask,didReceive data:Data) {
        lock.lock()
        guard let state = pending[dataTask.taskIdentifier] else { lock.unlock();return }
        state.buffered += data.count
        if !state.suspended && state.buffered >= highWater {
            state.suspended = true;dataTask.suspend()
        }
        lock.unlock()
        state.chunks.yield(data)
    }
    func urlSession(_ session:URLSession,task:URLSessionTask,didCompleteWithError error:Error?) {
        lock.lock();let state = pending.removeValue(forKey:task.taskIdentifier);lock.unlock()
        guard let state else { return }
        if let continuation = state.response { continuation.resume(throwing:error ?? DownloadError.http(0)) }
        if let error { state.chunks.finish(throwing:error) } else { state.chunks.finish() }
    }
}
