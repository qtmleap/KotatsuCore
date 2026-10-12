import CryptoKit
import Foundation
import Network
import XCTest

/// Test-only loopback server (127.0.0.1, ephemeral port) that serves both the
/// minimal SyncPlay REST surface (`/SyncPlay/List`, `/SyncPlay/New`, anything
/// else -> 204) and a real RFC 6455 WebSocket endpoint at `/socket`.
///
/// The handshake computes `Sec-WebSocket-Accept` with SHA-1 so a real
/// `URLSessionWebSocketTask` completes it. Frames are pushed unmasked (as a
/// server must), in order, and each `send*` call returns only once the bytes
/// were handed to the kernel, so a later frame can never overtake an earlier one.
final class SyncPlayWireServer: @unchecked Sendable {
    enum WireError: Error, CustomStringConvertible {
        case timeout(String)
        var description: String {
            switch self {
            case .timeout(let what): return "timed out waiting for \(what)"
            }
        }
    }

    private static let handshakeGUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"

    private let listener: NWListener
    private let queue = DispatchQueue(label: "app.jellyfin.tvos.tests.syncplay-wire")
    private let lock = NSLock()
    private var open: [ObjectIdentifier: NWConnection] = [:]
    private var socket: NWConnection?
    private var upgrades = 0
    private let holdUpgrade: Bool
    private var pendingUpgrade: (key: String, connection: NWConnection)?

    /// With `holdUpgrade` the 101 response is withheld until `releaseUpgrade()`,
    /// so tests can act while the client socket is allocated but connecting.
    /// The held connection stays in `open`, so `stop()` still cancels it.
    ///
    /// With `holdPauseResponse` the 204 for `POST /SyncPlay/Pause` is withheld
    /// until `releasePauseResponse()` (the request itself is fully received).
    /// The held connection stays in `open`, so `stop()` still cancels it.
    private let holdPauseResponse: Bool
    private var pendingPause: NWConnection?

    init(holdUpgrade: Bool = false, holdPauseResponse: Bool = false) throws {
        self.holdUpgrade = holdUpgrade
        self.holdPauseResponse = holdPauseResponse
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(host: .ipv4(.loopback), port: .any)
        listener = try NWListener(using: parameters)
    }

    /// Number of successful WebSocket upgrades served so far.
    var upgradeCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return upgrades
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
        socket = nil
        pendingPause = nil
        lock.unlock()
        for connection in all { connection.cancel() }
    }

    // MARK: - Pushing frames

    /// Bounded positive wait for the client's WebSocket upgrade to complete.
    func waitForSocket(timeout: TimeInterval = 10) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let ready = lock.withLock { socket != nil }
            if ready { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        throw WireError.timeout("client WebSocket upgrade")
    }

    /// Bounded positive wait until a held upgrade request has arrived.
    func waitForPendingUpgrade(timeout: TimeInterval = 10) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if lock.withLock({ pendingUpgrade != nil }) { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        throw WireError.timeout("held WebSocket upgrade request")
    }

    /// Completes a held upgrade handshake.
    func releaseUpgrade() throws {
        let pending = lock.withLock { () -> (key: String, connection: NWConnection)? in
            let p = pendingUpgrade
            pendingUpgrade = nil
            return p
        }
        guard let pending else { throw WireError.timeout("no held upgrade to release") }
        upgrade(key: pending.key, on: pending.connection)
    }

    /// Bounded positive wait until a held Pause request has arrived.
    func waitForPendingPause(timeout: TimeInterval = 10) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if lock.withLock({ pendingPause != nil }) { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        throw WireError.timeout("held Pause request")
    }

    /// Answers a held Pause request with the normal empty 204.
    func releasePauseResponse() throws {
        let pending = lock.withLock { () -> NWConnection? in
            let p = pendingPause
            pendingPause = nil
            return p
        }
        guard let pending else { throw WireError.timeout("no held Pause to release") }
        respond(.empty, on: pending)
    }

    func sendText(_ text: String) async throws {
        try await sendFrame(opcode: 0x1, payload: Data(text.utf8))
    }

    func sendBinary(_ payload: Data) async throws {
        try await sendFrame(opcode: 0x2, payload: payload)
    }

    private func sendFrame(opcode: UInt8, payload: Data) async throws {
        try await waitForSocket()
        let connection = lock.withLock { socket }
        guard let connection else { throw WireError.timeout("open WebSocket") }
        let frame = Self.encode(opcode: opcode, payload: payload)
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            connection.send(
                content: frame,
                completion: .contentProcessed { error in
                    if let error { c.resume(throwing: error) } else { c.resume() }
                })
        }
    }

    /// Unmasked, final (FIN) frame as sent by a server.
    static func encode(opcode: UInt8, payload: Data) -> Data {
        var frame = Data([0x80 | opcode])
        let n = payload.count
        if n < 126 {
            frame.append(UInt8(n))
        } else if n <= 0xFFFF {
            frame.append(126)
            frame.append(UInt8((n >> 8) & 0xFF))
            frame.append(UInt8(n & 0xFF))
        } else {
            frame.append(127)
            for shift in stride(from: 56, through: 0, by: -8) {
                frame.append(UInt8((n >> shift) & 0xFF))
            }
        }
        frame.append(payload)
        return frame
    }

    // MARK: - Connection handling

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

    private struct Head {
        let method: String
        let path: String
        let headers: [String: String]
        let bodyLength: Int
    }

    private func accept(_ connection: NWConnection) {
        lock.lock()
        open[ObjectIdentifier(connection)] = connection
        lock.unlock()
        connection.start(queue: queue)
        receiveRequest(connection, Data())
    }

    private func receiveRequest(_ connection: NWConnection, _ buffered: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) {
            [weak self] data, _, isComplete, error in
            guard let self else { return connection.cancel() }
            var buffer = buffered
            if let data { buffer.append(data) }
            if let (head, consumed) = Self.parse(buffer), buffer.count >= consumed + head.bodyLength
            {
                self.route(head, on: connection)
            } else if error != nil || isComplete {
                connection.cancel()
            } else {
                self.receiveRequest(connection, buffer)
            }
        }
    }

    private static func parse(_ data: Data) -> (Head, Int)? {
        guard let end = data.range(of: Data("\r\n\r\n".utf8)),
            let text = String(data: data[..<end.lowerBound], encoding: .utf8)
        else { return nil }
        let lines = text.components(separatedBy: "\r\n")
        let first = lines[0].split(separator: " ")
        guard first.count >= 2 else { return nil }
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            let parts = line.split(separator: ":", maxSplits: 1)
            if parts.count == 2 {
                headers[parts[0].lowercased()] = parts[1].trimmingCharacters(in: .whitespaces)
            }
        }
        let head = Head(
            method: String(first[0]), path: String(first[1]), headers: headers,
            bodyLength: Int(headers["content-length"] ?? "") ?? 0)
        return (head, end.upperBound)
    }

    private func route(_ head: Head, on connection: NWConnection) {
        if head.path.hasPrefix("/socket"),
            head.headers["upgrade"]?.lowercased() == "websocket",
            let key = head.headers["sec-websocket-key"]
        {
            if holdUpgrade {
                lock.withLock { pendingUpgrade = (key, connection) }
            } else {
                upgrade(key: key, on: connection)
            }
            return
        }
        if holdPauseResponse, head.path.contains("/SyncPlay/Pause") {
            lock.withLock { pendingPause = connection }
        } else if head.path.contains("/SyncPlay/List") {
            respond(
                .json([SyncPlayWireFrames.groupInfo(id: "group-2", name: "Other")]), on: connection)
        } else if head.path.contains("/SyncPlay/New") {
            respond(
                .json(
                    SyncPlayWireFrames.groupInfo(
                        id: "group-1", name: "Fake", participants: ["alice"])),
                on: connection)
        } else {
            respond(.empty, on: connection)
        }
    }

    private enum Reply {
        case json(Any)
        case empty
    }

    private func respond(_ reply: Reply, on connection: NWConnection) {
        var body = Data()
        var status = "204 No Content"
        if case .json(let object) = reply {
            body = (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
            status = "200 OK"
        }
        let head =
            "HTTP/1.1 \(status)\r\nContent-Length: \(body.count)\r\n"
            + "Content-Type: application/json\r\nConnection: close\r\n\r\n"
        connection.send(
            content: Data(head.utf8) + body,
            completion: .contentProcessed { [weak self] _ in
                self?.lock.lock()
                self?.open.removeValue(forKey: ObjectIdentifier(connection))
                self?.lock.unlock()
                connection.cancel()
            })
    }

    private func upgrade(key: String, on connection: NWConnection) {
        let digest = Insecure.SHA1.hash(data: Data((key + Self.handshakeGUID).utf8))
        let accept = Data(digest).base64EncodedString()
        let head =
            "HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\n"
            + "Connection: Upgrade\r\nSec-WebSocket-Accept: \(accept)\r\n\r\n"
        connection.send(
            content: Data(head.utf8),
            completion: .contentProcessed { [weak self] error in
                guard let self, error == nil else { return connection.cancel() }
                self.lock.lock()
                self.socket = connection
                self.upgrades += 1
                self.lock.unlock()
                self.drain(connection)
            })
    }

    /// Client->server frames (KeepAlive, close) are read and discarded.
    private func drain(_ connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) {
            [weak self] _, _, isComplete, error in
            guard let self, error == nil, !isComplete else { return }
            self.drain(connection)
        }
    }
}

/// Builders for full-shape Jellyfin WebSocket frames (metadata included).
enum SyncPlayWireFrames {
    static let wireDate = "2026-01-02T03:04:05.123Z"

    static func json(_ object: Any) -> String {
        let data =
            (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }

    static func groupInfo(id: String, name: String, participants: [String] = []) -> [String: Any] {
        [
            "GroupId": id, "GroupName": name, "State": "Idle", "Participants": participants,
            "LastUpdatedAt": wireDate,
        ]
    }

    /// `SyncPlayCommand`; `groupId == nil` omits the key, `ticks == nil` sends null.
    static func command(
        _ name: String, groupId: String? = "group-1", playlistItemId: String = "pl-1",
        ticks: Int64? = 0
    ) -> String {
        var data: [String: Any] = [
            "PlaylistItemId": playlistItemId, "When": wireDate, "EmittedAt": wireDate,
            "PositionTicks": ticks.map { $0 as Any } ?? NSNull(), "Command": name,
        ]
        if let groupId { data["GroupId"] = groupId }
        return json(["MessageType": "SyncPlayCommand", "MessageId": "m-1", "Data": data])
    }

    static func groupUpdate(type: String, groupId: String? = "group-1", data: Any) -> String {
        var update: [String: Any] = ["Type": type, "Data": data]
        if let groupId { update["GroupId"] = groupId }
        return json(["MessageType": "SyncPlayGroupUpdate", "MessageId": "m-2", "Data": update])
    }

    /// `PlayQueue` update. `items` are (ItemId, PlaylistItemId); `index == nil` omits PlayingItemIndex.
    static func playQueue(
        groupId: String? = "group-1", reason: String = "NewPlaylist",
        items: [(String, String)]? = [("item-a", "pl-a"), ("item-b", "pl-b")], index: Int? = 1,
        startTicks: Int64 = 50_000_000, isPlaying: Bool = true
    ) -> String {
        var data: [String: Any] = [
            "Reason": reason, "LastUpdate": wireDate, "StartPositionTicks": startTicks,
            "IsPlaying": isPlaying, "RepeatMode": "RepeatNone", "ShuffleMode": "Sorted",
        ]
        if let items {
            data["Playlist"] = items.map { ["ItemId": $0.0, "PlaylistItemId": $0.1] }
        }
        if let index { data["PlayingItemIndex"] = index }
        return groupUpdate(type: "PlayQueue", groupId: groupId, data: data)
    }

    static func other(messageType: String, data: Any = [String: Any]()) -> String {
        json(["MessageType": messageType, "MessageId": "m-3", "Data": data])
    }
}
