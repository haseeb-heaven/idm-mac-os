import Foundation
public enum QueuePolicy {
    public static func next(in jobs:[DownloadJob], at date:Date = Date()) -> DownloadJob? {
        jobs.first { $0.state == .queued && ($0.scheduledAt.map { $0 <= date } ?? true) }
    }
}
