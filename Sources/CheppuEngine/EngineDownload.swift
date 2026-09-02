import CheppuCore
import Foundation

/// The Engine Download: every outbound byte Cheppu sends, in one file.
///
/// Cheppu fetches the Engine itself rather than letting FluidAudio do it (see
/// ADR-0005). Two things follow from that, and both are acceptance criteria
/// rather than preferences: the caller is told the total size, because the
/// repository is asked what the Engine weighs before a byte of it is fetched;
/// and there is one place to read to know everything Cheppu talks to.
///
/// `Scripts/check-the-download-is-the-only-network-path.sh` fails the build if
/// anything that opens a connection appears anywhere else.
struct EngineDownload {
    /// One file of the Engine, as the repository describes it.
    struct RemoteFile: Equatable, Sendable {
        let path: String
        let bytes: Int64
    }

    enum Failure: Error, Equatable {
        /// The repository would not say what the Engine is made of.
        case listingRefused(status: Int)
        /// The repository would not hand over one of the Engine's files.
        case fileRefused(path: String, status: Int)
        /// What arrived was not the size the repository said it would be, which
        /// means a truncated body, or an error page wearing a file's name.
        case wrongSize(path: String, expected: Int64, received: Int64)
        /// The repository listed none of the Engine's files, so the names Cheppu
        /// asks for and the names it publishes have drifted apart.
        case engineNotInRepository
    }

    /// Where the Engine is being assembled.
    let directory: URL

    /// The session's settings rather than a session: each transfer needs a
    /// delegate to stream a body straight to disk, and a delegate cannot be
    /// attached to a session after it is made. This is also the seam the suite
    /// hands a stub through, which is what lets the resume be tested without
    /// fetching 480 MB.
    let configuration: URLSessionConfiguration

    /// Where the Engine is published.
    var host = "https://huggingface.co"

    /// The revision fetched. `main` rather than a pinned commit: the Engine's
    /// publisher reissues these bundles to fix conversion bugs, and a pin would
    /// hold Cheppu on a known-worse Engine until someone edited a constant.
    var revision = "main"

    /// How much has to arrive between two reports.
    ///
    /// The network hands over chunks of a few tens of kilobytes, which across
    /// 480 MB is tens of thousands of reports. A megabyte is finer than a
    /// progress bar can draw and coarse enough that the caller is never the
    /// thing holding the download up.
    var reportEvery: Int64 = 1_000_000

    /// Asks the repository what the Engine is made of and what it weighs.
    ///
    /// One request, before anything is fetched, and where the total size the
    /// caller is promised comes from.
    func filesOnOffer() async throws -> [RemoteFile] {
        let session = URLSession(configuration: configuration)
        defer { session.finishTasksAndInvalidate() }

        let repository = EngineFiles.repository.remotePath
        let listing = URL(string: "\(host)/api/models/\(repository)/tree/\(revision)?recursive=1")!

        let (data, response) = try await session.data(from: listing)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw Failure.listingRefused(status: status) }

        let files =
            try JSONDecoder()
            .decode([TreeEntry].self, from: data)
            .filter { $0.type == "file" && EngineFiles.isEngineFile($0.path) }
            .map { RemoteFile(path: $0.path, bytes: $0.size ?? 0) }
            .sorted { $0.path < $1.path }

        guard !files.isEmpty else { throw Failure.engineNotInRepository }
        return files
    }

    /// Fetches whatever is missing, reporting as it goes.
    ///
    /// A file already at its full size is skipped; a file an earlier attempt left
    /// half-finished is asked for from the byte it stopped at. That is the whole
    /// of the resume: part-fetched bytes wait next to where they are going under
    /// a `.partial` suffix, and a file takes its real name only once all of it
    /// has arrived. Nothing half-written can therefore be mistaken for a
    /// finished file, whenever the process died.
    func run(reporting progress: @escaping @Sendable (EngineDownloadProgress) -> Void) async throws {
        let files = try await filesOnOffer()
        let total = files.reduce(0) { $0 + $1.bytes }

        let transfers = EngineTransfers()
        let session = URLSession(configuration: configuration, delegate: transfers, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }

        var settled: Int64 = 0
        progress(EngineDownloadProgress(downloadedBytes: 0, totalBytes: total))

        for file in files {
            try Task.checkCancellation()

            let destination = directory.appending(path: file.path)
            if Self.bytesOnDisk(at: destination) != file.bytes {
                // Copied out of the loop's running total so the report closure
                // reads a fixed base rather than a variable being mutated
                // alongside it.
                let base = settled
                try await fetch(file, to: destination, over: session, through: transfers) { onDisk in
                    progress(EngineDownloadProgress(downloadedBytes: base + onDisk, totalBytes: total))
                }
            }

            settled += file.bytes
            progress(EngineDownloadProgress(downloadedBytes: settled, totalBytes: total))
        }
    }

    /// Fetches one file, carrying on from whatever an earlier attempt left.
    private func fetch(
        _ file: RemoteFile,
        to destination: URL,
        over session: URLSession,
        through transfers: EngineTransfers,
        reporting onDisk: @escaping @Sendable (Int64) -> Void
    ) async throws {
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)

        let partial = destination.appendingPathExtension("partial")

        // More on disk than the repository says the file holds means the leftover
        // belongs to an older version of the file, so it is dropped rather than
        // continued. This is also what stops a repository that keeps answering
        // with the wrong length: each attempt appends, and once the leftover
        // overshoots, the next one starts clean rather than resuming forever.
        if Self.bytesOnDisk(at: partial) >= file.bytes {
            try? FileManager.default.removeItem(at: partial)
        }

        let encoded = file.path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? file.path
        let repository = EngineFiles.repository.remotePath
        var request = URLRequest(url: URL(string: "\(host)/\(repository)/resolve/\(revision)/\(encoded)")!)

        let alreadyHave = Self.bytesOnDisk(at: partial)
        if alreadyHave > 0 {
            request.setValue("bytes=\(alreadyHave)-", forHTTPHeaderField: "Range")
        }

        do {
            try await transfers.run(
                request, over: session, appendingTo: partial,
                reportEvery: reportEvery, reporting: onDisk)
        } catch let refusal as EngineTransfers.Refused {
            throw Failure.fileRefused(path: file.path, status: refusal.status)
        }

        let received = Self.bytesOnDisk(at: partial)
        guard received == file.bytes else {
            throw Failure.wrongSize(path: file.path, expected: file.bytes, received: received)
        }

        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: partial, to: destination)
    }

    static func bytesOnDisk(at url: URL) -> Int64 {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
            let size = attributes[.size] as? NSNumber
        else { return 0 }
        return size.int64Value
    }

    /// One entry of the repository's file listing. Sizes come already resolved
    /// through Git LFS, so a pointer file's 134 bytes are never mistaken for the
    /// 445 MB of weights it stands for.
    private struct TreeEntry: Decodable {
        let type: String
        let path: String
        let size: Int64?
    }
}

/// The transfers in flight, and the bodies they are streaming to disk.
///
/// `URLSession.bytes(for:)` would be the shorter spelling of this whole class,
/// but it hands a body over one byte at a time, which turns the Engine's 445 MB
/// encoder into minutes of copying. A data delegate gets the same stream in the
/// chunks the network delivered it in.
///
/// Every callback below arrives on the session's own serial delegate queue, and
/// the state they share is touched nowhere else. That is what the unchecked
/// conformance asserts.
final class EngineTransfers: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    /// The repository answered a file request with something other than a body.
    /// Which file it was belongs to the caller, which knows the path.
    struct Refused: Error {
        let status: Int
    }

    /// One file on its way to disk.
    ///
    /// Handed to the delegate queue once and read only from the callbacks that
    /// run there, which is the same serialisation the enclosing class relies on.
    private final class InFlight: @unchecked Sendable {
        let handle: FileHandle
        let report: @Sendable (Int64) -> Void
        let reportEvery: Int64
        var onDisk: Int64
        var reportedAt: Int64
        var failure: Error?
        var waiting: CheckedContinuation<Void, Error>?

        init(
            handle: FileHandle, onDisk: Int64, reportEvery: Int64,
            report: @escaping @Sendable (Int64) -> Void
        ) {
            self.handle = handle
            self.report = report
            self.reportEvery = reportEvery
            self.onDisk = onDisk
            self.reportedAt = onDisk
        }
    }

    private var inFlight: [Int: InFlight] = [:]

    /// Runs one request, appending what comes back to `partial`.
    func run(
        _ request: URLRequest,
        over session: URLSession,
        appendingTo partial: URL,
        reportEvery: Int64,
        reporting report: @escaping @Sendable (Int64) -> Void
    ) async throws {
        if !FileManager.default.fileExists(atPath: partial.path) {
            FileManager.default.createFile(atPath: partial.path, contents: nil)
        }
        let handle = try FileHandle(forWritingTo: partial)
        let alreadyOnDisk = Int64(try handle.seekToEnd())
        defer { try? handle.close() }

        let task = session.dataTask(with: request)
        let transfer = InFlight(
            handle: handle, onDisk: alreadyOnDisk, reportEvery: reportEvery, report: report)

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                // Registered on the delegate's own queue so the first callback
                // cannot arrive before there is anything for it to find.
                session.delegateQueue.addOperation {
                    transfer.waiting = continuation
                    self.inFlight[task.taskIdentifier] = transfer
                    task.resume()
                }
            }
        } onCancel: {
            task.cancel()
        }
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        guard let transfer = inFlight[dataTask.taskIdentifier] else {
            completionHandler(.cancel)
            return
        }

        switch (response as? HTTPURLResponse)?.statusCode ?? 0 {
        case 206:
            // The resume honoured: what follows continues the partial file.
            break
        case 200:
            // The whole file, which a server may send however the request was
            // framed. Taking it at its word means dropping what was already
            // here, or the file ends up with its opening bytes twice.
            try? transfer.handle.truncate(atOffset: 0)
            transfer.onDisk = 0
            transfer.reportedAt = 0
        case let status:
            transfer.failure = Refused(status: status)
            completionHandler(.cancel)
            return
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let transfer = inFlight[dataTask.taskIdentifier] else { return }
        do {
            try transfer.handle.write(contentsOf: data)
            transfer.onDisk += Int64(data.count)
            if transfer.onDisk - transfer.reportedAt >= transfer.reportEvery {
                transfer.reportedAt = transfer.onDisk
                transfer.report(transfer.onDisk)
            }
        } catch {
            transfer.failure = error
            dataTask.cancel()
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let transfer = inFlight.removeValue(forKey: task.taskIdentifier) else { return }
        try? transfer.handle.synchronize()
        transfer.report(transfer.onDisk)

        // A refused body cancels the task, so the transport error that follows
        // says only that it was cancelled. The refusal is what the caller needs.
        let waiting = transfer.waiting
        transfer.waiting = nil
        if let failure = transfer.failure {
            waiting?.resume(throwing: failure)
        } else if let error {
            waiting?.resume(throwing: error)
        } else {
            waiting?.resume()
        }
    }
}
