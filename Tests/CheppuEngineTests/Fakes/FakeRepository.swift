import CryptoKit
import Foundation

/// The Engine's repository, answering from memory instead of over the network.
///
/// Each one registers itself under a host of its own, so a suite running
/// alongside another cannot see its files or its requests. That is what lets the
/// download — the listing, the resume, the byte accounting — be tested without
/// fetching 480 MB, and lets the core promise hold in the suite too: nothing
/// here opens a connection.
final class FakeRepository: @unchecked Sendable {
    /// What was asked for, and how.
    struct Ask: Equatable, Sendable {
        let path: String
        let range: String?
    }

    /// The host to point an `EngineDownload` at.
    let host: String

    private let lock = NSLock()
    private var files: [String: Data] = [:]
    private var asks: [Ask] = []

    /// Whether a `Range` request is answered with the range asked for.
    ///
    /// False stands for the cache or proxy that answers every request with the
    /// whole file — which a server is entitled to do, and which would leave a
    /// resumed file holding its opening bytes twice if the download believed the
    /// range it asked for was the range it got.
    var honoursRange = true

    /// Drops the connection after this many bytes of every body, standing in for
    /// the download being killed partway.
    var dropsAfter: Int?

    /// Sends this many bytes of every body and then goes quiet without ever
    /// finishing or failing, standing in for a server that has stopped
    /// answering. Only a cancellation ends a transfer against this.
    var stallsAfter: Int?

    /// Answers with the right number of bytes and the wrong ones, standing in
    /// for a mirror or a proxy serving something that is not what the
    /// repository published.
    var corruptsBodies = false

    init() {
        host = "https://repository-\(UUID().uuidString.lowercased())"
        FakeRepositoryProtocol.register(self, for: host)
    }

    /// Publishes one file at a path inside the repository.
    func publish(_ path: String, bytes: Int) {
        // Bytes that differ from one another and from their neighbours, so a
        // file resumed from the wrong offset does not happen to still match.
        let body = Data((0..<bytes).map { UInt8(($0 &* 31 &+ path.count) % 251) })
        lock.withLock { files[path] = body }
    }

    /// What a published file holds.
    func body(of path: String) -> Data {
        lock.withLock { files[path] ?? Data() }
    }

    /// Every file request made, in order. The listing is not one of them.
    var everythingAsked: [Ask] {
        lock.withLock { asks }
    }

    /// A session pointed at this repository and nowhere else.
    var configuration: URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FakeRepositoryProtocol.self]
        return configuration
    }

    // MARK: - What the protocol asks of us

    /// The repository's file listing, in the shape the Hugging Face API answers
    /// — including the Git LFS digest, which really is the SHA-256 of the file's
    /// contents.
    fileprivate func listing() -> Data {
        let entries = lock.withLock {
            files.keys.sorted().map { path -> [String: Any] in
                let body = files[path]!
                return [
                    "type": "file",
                    "path": path,
                    "size": body.count,
                    "lfs": ["oid": Self.digest(of: body)],
                ]
            }
        }
        return try! JSONSerialization.data(withJSONObject: entries)
    }

    static func digest(of body: Data) -> String {
        SHA256.hash(data: body).map { String(format: "%02x", $0) }.joined()
    }

    /// The answer to one file request: a status, the bytes, and whether they
    /// begin at the offset that was asked for.
    fileprivate func answer(for path: String, range: String?) -> (status: Int, body: Data)? {
        lock.withLock {
            asks.append(Ask(path: path, range: range))
            guard let whole = files[path] else { return nil }

            let served = corruptsBodies ? Data(whole.map { $0 &+ 1 }) : whole
            let from = (honoursRange ? range?.offset : nil) ?? 0
            let body = served.count >= from ? Data(served.suffix(from: from)) : Data()
            return (from > 0 ? 206 : 200, body)
        }
    }
}

extension String {
    /// The first byte a `bytes=N-` header asks for.
    fileprivate var offset: Int? {
        guard hasPrefix("bytes=") else { return nil }
        return Int(dropFirst("bytes=".count).prefix(while: \.isNumber))
    }
}

/// Routes a request to whichever `FakeRepository` owns its host.
///
/// `URLProtocol` is instantiated by the session, once per request, so what a
/// test set up has to be reachable statically. Keying by host is what keeps two
/// tests' repositories apart.
final class FakeRepositoryProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var repositories: [String: FakeRepository] = [:]

    static func register(_ repository: FakeRepository, for host: String) {
        lock.withLock { repositories[host] = repository }
    }

    private static func repository(serving url: URL) -> FakeRepository? {
        guard let scheme = url.scheme, let host = url.host() else { return nil }
        return lock.withLock { repositories["\(scheme)://\(host)"] }
    }

    override class func canInit(with request: URLRequest) -> Bool {
        guard let url = request.url else { return false }
        return repository(serving: url) != nil
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url, let repository = Self.repository(serving: url) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }

        let path = url.path().removingPercentEncoding ?? url.path()
        let listingPrefix = "/api/models/"

        if path.hasPrefix(listingPrefix) {
            finish(status: 200, body: repository.listing(), for: url)
            return
        }

        // Everything after `<owner>/<repository>/resolve/<revision>/`.
        let components = path.split(separator: "/", omittingEmptySubsequences: true)
        guard let resolve = components.firstIndex(of: "resolve"), components.count > resolve + 1 else {
            finish(status: 404, body: Data(), for: url)
            return
        }
        let file = components[(resolve + 2)...].joined(separator: "/")

        guard
            let answer = repository.answer(
                for: file, range: request.value(forHTTPHeaderField: "Range"))
        else {
            finish(status: 404, body: Data(), for: url)
            return
        }
        finish(
            status: answer.status, body: answer.body, for: url,
            droppingAfter: repository.dropsAfter, stallingAfter: repository.stallsAfter)
    }

    override func stopLoading() {}

    /// Bodies arrive in pieces here the way they do over a network: on another
    /// queue, spread out in time, and handed on as they land rather than all at
    /// the end. A body delivered in one synchronous burst and then failed would
    /// let the session drop the whole thing, which is the opposite of what a
    /// dropped connection does — the bytes that already arrived stay arrived,
    /// and that is exactly what the resume is built on.
    private static let wire = DispatchQueue(label: "cheppu.fake-repository")

    private func finish(
        status: Int, body: Data, for url: URL, droppingAfter: Int? = nil, stallingAfter: Int? = nil
    ) {
        let response = HTTPURLResponse(
            url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
        let cutoff = droppingAfter ?? stallingAfter
        let sending = cutoff.map { body.prefix($0) } ?? body[...]
        let cut = sending.count < body.count
        let dropped = droppingAfter != nil && cut
        let stalled = stallingAfter != nil && cut

        Self.wire.async { [weak self] in
            guard let self else { return }
            self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)

            let chunk = max(sending.count / 4, 1)
            var sent = sending.startIndex
            while sent < sending.endIndex {
                let next =
                    sending.index(sent, offsetBy: chunk, limitedBy: sending.endIndex)
                    ?? sending.endIndex
                self.client?.urlProtocol(self, didLoad: Data(sending[sent..<next]))
                sent = next
                usleep(200)
            }

            if stalled { return }
            if dropped {
                self.client?.urlProtocol(self, didFailWithError: URLError(.networkConnectionLost))
            } else {
                self.client?.urlProtocolDidFinishLoading(self)
            }
        }
    }
}
