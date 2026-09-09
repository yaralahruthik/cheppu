import CheppuCore
import CryptoKit
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
    struct RemoteFile: Equatable, Sendable, Codable {
        let path: String
        let bytes: Int64

        /// The SHA-256 of the file's contents, where the repository publishes
        /// one. Everything large is stored through Git LFS, which is what makes
        /// a digest available for exactly the files whose corruption would
        /// matter — the weights Cheppu goes on to run as a model.
        var digest: String?
    }

    enum Failure: Error, Equatable {
        /// The repository would not say what the Engine is made of.
        case listingRefused(status: Int)
        /// The repository would not hand over one of the Engine's files.
        case fileRefused(path: String, status: Int)
        /// What arrived was not the size the repository said it would be, which
        /// means a truncated body, or an error page wearing a file's name.
        case wrongSize(path: String, expected: Int64, received: Int64)
        /// What arrived was the right length and the wrong bytes.
        case wrongContents(path: String)
        /// The repository listed none of the part's files, so the names Cheppu
        /// asks for and the names it publishes have drifted apart.
        case engineNotInRepository
        /// A path the repository listed cannot be turned into an address.
        case unusableAddress(String)
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

    /// How much has to arrive between two reports.
    ///
    /// The network hands over chunks of a few tens of kilobytes, which across
    /// 480 MB is tens of thousands of reports. A megabyte is finer than a
    /// progress bar can draw and coarse enough that the caller is never the
    /// thing holding the download up.
    var reportEvery: Int64 = 1_000_000

    /// Which part of the Engine is being assembled here.
    ///
    /// The Engine is in two parts and this file fetches either of them: the
    /// listing, the resume, the size check, the digest and the manifest are the
    /// same work whichever it is, and the only difference is which repository
    /// is asked and which of its files are wanted (ADR-0014).
    var part: EnginePart = .everyDictationNeedsIt

    /// The revision fetched. `main` rather than a pinned commit: the Engine's
    /// publisher reissues these bundles to fix conversion bugs, and a pin would
    /// hold Cheppu on a known-worse Engine until someone edited a constant.
    private static let revision = "main"

    /// What the last finished download left behind, so that "is the Engine
    /// here" can be answered later without asking the repository again.
    static let manifestName = ".cheppu-engine.json"

    /// Asks the repository what the Engine is made of and what it weighs.
    ///
    /// One request, before anything is fetched, and where the total size the
    /// caller is promised comes from.
    func filesOnOffer() async throws -> [RemoteFile] {
        let session = URLSession(configuration: configuration)
        defer { session.finishTasksAndInvalidate() }

        let listing = try address("api/models/\(repository)/tree/\(Self.revision)?recursive=1")
        let (data, response) = try await session.data(from: listing)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw Failure.listingRefused(status: status) }

        let files =
            try JSONDecoder()
            .decode([TreeEntry].self, from: data)
            .filter { $0.type == "file" && part.isPartOfIt($0.path) }
            .map { RemoteFile(path: $0.path, bytes: $0.size ?? 0, digest: $0.lfs?.oid) }
            .sorted { $0.path < $1.path }

        guard !files.isEmpty else { throw Failure.engineNotInRepository }
        return files
    }

    /// Whether a finished download left every one of its files here, at the size
    /// it recorded.
    ///
    /// Read from the manifest the last finished download wrote rather than from
    /// the directory's shape, because an interrupted download leaves that shape
    /// behind too: a bundle's directory is made before the first byte of it
    /// arrives, so "the folders are all there" is true of a download that got
    /// nowhere.
    static func isEngineComplete(in directory: URL) -> Bool {
        guard let recorded = manifest(in: directory), !recorded.isEmpty else { return false }
        return recorded.allSatisfy {
            bytesOnDisk(at: directory.appending(path: $0.path)) == $0.bytes
        }
    }

    static func manifest(in directory: URL) -> [RemoteFile]? {
        guard let data = try? Data(contentsOf: directory.appending(path: manifestName)) else {
            return nil
        }
        return try? JSONDecoder().decode([RemoteFile].self, from: data)
    }

    /// Fetches whatever is missing, reporting as it goes.
    ///
    /// A file already at its full size is skipped; a file an earlier attempt left
    /// half-finished is asked for from the byte it stopped at. That is the whole
    /// of the resume: part-fetched bytes wait next to where they are going under
    /// a `.partial` suffix, and a file takes its real name only once all of it
    /// has arrived and been checked. Nothing half-written can therefore be
    /// mistaken for a finished file, whenever the process died.
    func run(reporting progress: @escaping @Sendable (EngineDownloadProgress) -> Void) async throws {
        let files = try await filesOnOffer()
        let total = files.reduce(0) { $0 + $1.bytes }
        let report = RisingProgress(total: total, reporting: progress)

        let transfers = EngineTransfers(configuration: configuration)
        defer { transfers.close() }

        // Opens at what an interrupted attempt already left, so a resumed
        // download picks the bar up where it stopped rather than at zero.
        var settled: Int64 = 0
        report(bytesAlreadyHere(of: files))

        for file in files {
            try Task.checkCancellation()

            let destination = directory.appending(path: file.path)
            if Self.bytesOnDisk(at: destination) != file.bytes {
                // Copied out of the loop's running total so the report closure
                // reads a fixed base rather than a variable being mutated
                // alongside it.
                let base = settled
                try await fetch(file, to: destination, through: transfers) { onDisk in
                    report(base + onDisk)
                }
            }

            settled += file.bytes
            report(settled)
        }

        try Data(JSONEncoder().encode(files))
            .write(to: directory.appending(path: Self.manifestName), options: .atomic)
    }

    /// How much of the Engine is on the machine before anything is fetched,
    /// counting both finished files and what an interrupted attempt left.
    private func bytesAlreadyHere(of files: [RemoteFile]) -> Int64 {
        files.reduce(0) { total, file in
            let destination = directory.appending(path: file.path)
            let landed = Self.bytesOnDisk(at: destination)
            let partial = Self.bytesOnDisk(at: destination.appendingPathExtension("partial"))
            return total + min(max(landed, partial), file.bytes)
        }
    }

    /// Fetches one file, carrying on from whatever an earlier attempt left.
    private func fetch(
        _ file: RemoteFile,
        to destination: URL,
        through transfers: EngineTransfers,
        reporting onDisk: @escaping @Sendable (Int64) -> Void
    ) async throws {
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)

        let partial = destination.appendingPathExtension("partial")
        var resumeFrom = Self.bytesOnDisk(at: partial)

        if resumeFrom > file.bytes {
            // A leftover longer than the file it is going to belongs to an older
            // version of it, so it is started over. Dropping it is also what
            // stops a repository that keeps answering with the wrong length from
            // being resumed forever: each attempt appends, and once the leftover
            // overshoots, the next one starts clean.
            try? FileManager.default.removeItem(at: partial)
            resumeFrom = 0
        }

        // A `.partial` that is already the full length is a download killed
        // between its last byte landing and the file being given its name. What
        // it needs is its name, not 445 MB fetched again.
        if resumeFrom < file.bytes {
            var request = URLRequest(
                url: try address("\(repository)/resolve/\(Self.revision)/\(encoded(file.path))"))
            if resumeFrom > 0 {
                request.setValue("bytes=\(resumeFrom)-", forHTTPHeaderField: "Range")
            }

            do {
                try await transfers.run(
                    request, appendingTo: partial, reportEvery: reportEvery, reporting: onDisk)
            } catch let refusal as EngineTransfers.Refused {
                throw Failure.fileRefused(path: file.path, status: refusal.status)
            }
        }

        try verify(file, at: partial)
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: partial, to: destination)
    }

    /// Checks that what arrived is what was published, before it is given the
    /// name the Engine will load it by.
    private func verify(_ file: RemoteFile, at partial: URL) throws {
        let received = Self.bytesOnDisk(at: partial)
        guard received == file.bytes else {
            throw Failure.wrongSize(path: file.path, expected: file.bytes, received: received)
        }

        // Cheppu goes on to run these bytes as a model, so where the repository
        // publishes a digest, the length agreeing is not enough. Wrong contents
        // are dropped rather than resumed: there is no byte to carry on from
        // when the ones already here are the wrong ones.
        guard let digest = file.digest else { return }
        guard try Self.sha256(of: partial) == digest else {
            try? FileManager.default.removeItem(at: partial)
            throw Failure.wrongContents(path: file.path)
        }
    }

    private static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    static func bytesOnDisk(at url: URL) -> Int64 {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
            let size = attributes[.size] as? NSNumber
        else { return 0 }
        return size.int64Value
    }

    private var repository: String { part.repository.remotePath }

    private func encoded(_ path: String) -> String {
        path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
    }

    /// An address inside the repository — or a throw, rather than a crash. This
    /// is the one file that builds URLs out of what a server said.
    private func address(_ suffix: String) throws -> URL {
        guard let url = URL(string: "\(host)/\(suffix)") else {
            throw Failure.unusableAddress(suffix)
        }
        return url
    }

    /// One entry of the repository's file listing. Sizes come already resolved
    /// through Git LFS, so a pointer file's 134 bytes are never mistaken for the
    /// 445 MB of weights it stands for.
    private struct TreeEntry: Decodable {
        struct LargeFile: Decodable {
            let oid: String
        }
        let type: String
        let path: String
        let size: Int64?
        let lfs: LargeFile?
    }
}

/// A progress report that only ever moves forwards.
///
/// A server is entitled to answer a resumed request with the whole file, which
/// takes that file's count back to zero partway through a download. The bytes
/// are honest; a bar that jumps backwards is not, and it costs more trust than
/// the precision is worth.
private final class RisingProgress: @unchecked Sendable {
    private let lock = NSLock()
    private var highest: Int64 = 0
    private let total: Int64
    private let report: @Sendable (EngineDownloadProgress) -> Void

    init(total: Int64, reporting report: @escaping @Sendable (EngineDownloadProgress) -> Void) {
        self.total = total
        self.report = report
    }

    func callAsFunction(_ downloaded: Int64) {
        let rising = lock.withLock { () -> Int64 in
            highest = max(highest, downloaded)
            return highest
        }
        report(EngineDownloadProgress(downloadedBytes: rising, totalBytes: total))
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
/// so does everything else that touches a transfer — starting it, cancelling it,
/// and waiting on it. That is what the unchecked conformance asserts, and it is
/// why none of the three can race the others.
final class EngineTransfers: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    /// The repository answered a file request with something other than a body.
    /// Which file it was belongs to the caller, which knows the path.
    struct Refused: Error {
        let status: Int
    }

    /// One file on its way to disk. Handed to the delegate queue once, and
    /// touched only from there.
    private final class InFlight: @unchecked Sendable {
        let handle: FileHandle
        let report: @Sendable (Int64) -> Void
        let reportEvery: Int64
        var onDisk: Int64
        var reportedAt: Int64
        var failure: Error?

        private var waiting: CheckedContinuation<Void, Error>?
        private var ended: Result<Void, Error>?

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

        /// The transfer is over: told to whoever is waiting, or kept until
        /// someone is. A cancellation can end a transfer in the moment between
        /// it being started and there being anything to tell, and an outcome
        /// dropped there would leave the caller waiting on a reply that was
        /// never coming.
        func finish(_ outcome: Result<Void, Error>) {
            if let waiting {
                self.waiting = nil
                waiting.resume(with: outcome)
            } else {
                ended = outcome
            }
        }

        /// Start waiting — unless it is already over.
        func wait(_ continuation: CheckedContinuation<Void, Error>) {
            if let ended {
                continuation.resume(with: ended)
            } else {
                waiting = continuation
            }
        }
    }

    /// Implicitly unwrapped because a session that reports to this object cannot
    /// be made until the object exists, and the object is useless without one.
    private var session: URLSession!
    private var inFlight: [Int: InFlight] = [:]

    init(configuration: URLSessionConfiguration) {
        // Serial, and the one queue a transfer is ever touched from.
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        super.init()
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: queue)
    }

    /// The session holds this delegate until it is invalidated, so letting go of
    /// the transfers is not enough to let go of either.
    func close() {
        session.finishTasksAndInvalidate()
    }

    /// Runs one request, appending what comes back to `partial`.
    func run(
        _ request: URLRequest,
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
        let queue = session.delegateQueue

        // Registered and started on the queue the callbacks arrive on, so the
        // first of them cannot land before there is anything for it to find.
        await withCheckedContinuation { started in
            queue.addOperation {
                self.inFlight[task.taskIdentifier] = transfer
                task.resume()
                started.resume()
            }
        }

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                queue.addOperation { transfer.wait(continuation) }
            }
        } onCancel: {
            // Through the same queue as everything else, so a cancellation
            // arriving while the transfer is still being set up joins the order
            // rather than racing it.
            queue.addOperation { task.cancel() }
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
        if let failure = transfer.failure {
            transfer.finish(.failure(failure))
        } else if let error {
            transfer.finish(.failure(error))
        } else {
            transfer.finish(.success(()))
        }
    }
}
