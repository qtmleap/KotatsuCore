import Network
import XCTest

/// Minimal scriptable HTTP/1.1 loopback server (127.0.0.1, ephemeral port).
/// A handler maps (method, path, headers) to a response; every request is
/// logged with its headers so tests can assert on credentials and scope.
final class ScriptedHTTPServer: @unchecked Sendable {
    struct Request: Sendable {
        let method: String
        let path: String
        let headers: [String: String]
    }
    struct Response: Sendable {
        var status: Int = 200
        var headers: [String: String] = [:]
        var body: Data = Data("{}".utf8)
        var delay: TimeInterval = 0
        static func json(_ object: Any, status: Int = 200) -> Response {
            Response(
                status: status,
                body: (try? JSONSerialization.data(withJSONObject: object)) ?? Data())
        }
        static func redirect(to location: String) -> Response {
            Response(status: 302, headers: ["Location": location])
        }
    }

    private let listener: NWListener
    private let queue = DispatchQueue(label: "app.jellyfin.tvos.tests.scripted-http")
    private let lock = NSLock()
    private var log: [Request] = []
    private var open: [ObjectIdentifier: NWConnection] = [:]
    private let handler: @Sendable (Request) -> Response

    init(handler: @escaping @Sendable (Request) -> Response) throws {
        self.handler = handler
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(host: .ipv4(.loopback), port: .any)
        listener = try NWListener(using: parameters)
    }

    var requests: [Request] {
        lock.lock()
        defer { lock.unlock() }
        return log
    }

    func start() async throws -> UInt16 {
        try await withCheckedThrowingContinuation { continuation in
            let box = OnceBox(continuation)
            listener.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    if let port = self?.listener.port?.rawValue {
                        box.resume(.success(port))
                    } else {
                        box.resume(.failure(URLError(.cannotFindHost)))
                    }
                case .failed(let error): box.resume(.failure(error))
                default: break
                }
            }
            listener.newConnectionHandler = { [weak self] in self?.accept($0) }
            listener.start(queue: queue)
            queue.asyncAfter(deadline: .now() + 5) { box.resume(.failure(URLError(.timedOut))) }
        }
    }

    func stop() {
        listener.cancel()
        lock.lock()
        let all = Array(open.values)
        open.removeAll()
        lock.unlock()
        all.forEach { $0.cancel() }
    }

    private final class OnceBox: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<UInt16, Error>?
        init(_ c: CheckedContinuation<UInt16, Error>) { continuation = c }
        func resume(_ result: Result<UInt16, Error>) {
            lock.lock()
            let c = continuation
            continuation = nil
            lock.unlock()
            c?.resume(with: result)
        }
    }

    private func accept(_ connection: NWConnection) {
        lock.lock()
        open[ObjectIdentifier(connection)] = connection
        lock.unlock()
        connection.start(queue: queue)
        receive(connection, Data())
    }

    private func receive(_ connection: NWConnection, _ buffered: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) {
            [weak self] data, _, isComplete, error in
            guard let self else { return connection.cancel() }
            var buffer = buffered
            if let data { buffer.append(data) }
            if let request = Self.parse(buffer) {
                self.respond(request, on: connection)
            } else if error != nil || isComplete {
                connection.cancel()
            } else {
                self.receive(connection, buffer)
            }
        }
    }

    private static func parse(_ data: Data) -> Request? {
        guard let end = data.range(of: Data("\r\n\r\n".utf8)),
            let head = String(data: data[..<end.lowerBound], encoding: .utf8)
        else { return nil }
        let lines = head.components(separatedBy: "\r\n")
        let first = lines[0].split(separator: " ")
        guard first.count >= 2 else { return nil }
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            let parts = line.split(separator: ":", maxSplits: 1)
            if parts.count == 2 {
                headers[parts[0].lowercased()] = parts[1].trimmingCharacters(in: .whitespaces)
            }
        }
        return Request(method: String(first[0]), path: String(first[1]), headers: headers)
    }

    private func respond(_ request: Request, on connection: NWConnection) {
        lock.lock()
        log.append(request)
        lock.unlock()
        let response = handler(request)
        let send = { [weak self] in
            var head = "HTTP/1.1 \(response.status) X\r\nContent-Length: \(response.body.count)\r\n"
            head += "Content-Type: application/json\r\nConnection: close\r\n"
            for (k, v) in response.headers { head += "\(k): \(v)\r\n" }
            head += "\r\n"
            connection.send(
                content: Data(head.utf8) + response.body,
                completion: .contentProcessed { _ in
                    self?.lock.lock()
                    self?.open.removeValue(forKey: ObjectIdentifier(connection))
                    self?.lock.unlock()
                    connection.cancel()
                })
        }
        if response.delay > 0 {
            queue.asyncAfter(deadline: .now() + response.delay, execute: send)
        } else {
            send()
        }
    }
}
