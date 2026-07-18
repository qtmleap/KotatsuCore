import Foundation
import os

/// Real `SyncPlayService`. Owns two responsibilities:
///
/// * REST calls to `/SyncPlay/*` for group management + playback commands.
/// * A `URLSessionWebSocketTask` connected to `/socket?api_key=...` that
///   receives `GroupUpdate` messages and translates them into
///   `SyncPlayEvent`s on the public `AsyncStream`.
public actor JellyfinSyncPlayService: SyncPlayService {
    private let http: JellyfinHTTPClient
    private let logger = Logger(subsystem: "app.jellyfin.tvos", category: "syncplay")

    private var _currentGroup: SyncPlayGroup?
    private var socketTask: URLSessionWebSocketTask?
    private var listenerTask: Task<Void, Never>?
    private let urlSession: URLSession

    private let eventContinuation: AsyncStream<SyncPlayEvent>.Continuation
    public nonisolated let events: AsyncStream<SyncPlayEvent>

    public init(http: JellyfinHTTPClient, urlSession: URLSession = .shared) {
        self.http = http
        self.urlSession = urlSession
        var continuation: AsyncStream<SyncPlayEvent>.Continuation!
        self.events = AsyncStream { continuation = $0 }
        self.eventContinuation = continuation
    }

    deinit {
        listenerTask?.cancel()
        socketTask?.cancel(with: .goingAway, reason: nil)
        eventContinuation.finish()
    }

    // MARK: - Public state

    public var currentGroup: SyncPlayGroup? { _currentGroup }

    // MARK: - Group management

    public func availableGroups() async throws -> [SyncPlayGroup] {
        let groups: [SyncPlayGroupInfoDTO] = try await http.request(.get, path: "/SyncPlay/List")
        return groups.map { $0.toDomain() }
    }

    public func createGroup(name: String) async throws -> SyncPlayGroup {
        try await http.send(
            .post,
            path: "/SyncPlay/New",
            query: ["GroupName": name]
        )
        // The server does not return the group ID directly; fetch the
        // current list and pick the one that matches our name (Jellyfin
        // enforces unique names within a session).
        let groups = try await availableGroups()
        let group = groups.first { $0.name == name } ?? SyncPlayGroup(id: UUID().uuidString, name: name)
        _currentGroup = group
        await ensureSocketConnected()
        eventContinuation.yield(.groupChanged(group))
        return group
    }

    public func joinGroup(id: String) async throws {
        try await http.send(
            .post,
            path: "/SyncPlay/Join",
            query: ["GroupId": id]
        )
        let groups = try await availableGroups()
        if let group = groups.first(where: { $0.id == id }) {
            _currentGroup = group
            eventContinuation.yield(.groupChanged(group))
        }
        await ensureSocketConnected()
    }

    public func leaveGroup() async throws {
        try await http.send(.post, path: "/SyncPlay/Leave")
        _currentGroup = nil
        eventContinuation.yield(.disconnected)
    }

    // MARK: - Playback commands

    public func requestPlay(positionSeconds: TimeInterval) async {
        do {
            try await http.send(.post, path: "/SyncPlay/Unpause")
            try await http.send(
                .post,
                path: "/SyncPlay/Seek",
                query: ["PositionTicks": "\(Int64(positionSeconds * 10_000_000))"]
            )
        } catch {
            logger.warning("requestPlay failed: \(String(describing: error), privacy: .public)")
        }
    }

    public func requestPause(positionSeconds: TimeInterval) async {
        do {
            try await http.send(.post, path: "/SyncPlay/Pause")
        } catch {
            logger.warning("requestPause failed: \(String(describing: error), privacy: .public)")
        }
    }

    public func requestSeek(positionSeconds: TimeInterval) async {
        do {
            try await http.send(
                .post,
                path: "/SyncPlay/Seek",
                query: ["PositionTicks": "\(Int64(positionSeconds * 10_000_000))"]
            )
        } catch {
            logger.warning("requestSeek failed: \(String(describing: error), privacy: .public)")
        }
    }

    // MARK: - WebSocket

    private func ensureSocketConnected() async {
        if socketTask != nil { return }
        guard let token = http.accessToken, !token.isEmpty else { return }
        let scheme = http.server.url.scheme?.lowercased() == "https" ? "wss" : "ws"
        var comps = URLComponents()
        comps.scheme = scheme
        comps.host = http.server.url.host
        comps.port = http.server.url.port
        var basePath = http.server.url.path
        if basePath.hasSuffix("/") { basePath.removeLast() }
        comps.path = basePath + "/socket"
        comps.queryItems = [
            URLQueryItem(name: "api_key", value: token),
            URLQueryItem(name: "deviceId", value: http.deviceId)
        ]
        guard let url = comps.url else { return }
        let task = urlSession.webSocketTask(with: url)
        self.socketTask = task
        task.resume()
        listenerTask = Task { [weak self] in
            await self?.listenLoop()
        }
    }

    private func listenLoop() async {
        guard let task = socketTask else { return }
        while !Task.isCancelled {
            do {
                let message = try await task.receive()
                await handle(message: message)
            } catch {
                logger.info("WebSocket receive ended: \(String(describing: error), privacy: .public)")
                eventContinuation.yield(.disconnected)
                socketTask = nil
                return
            }
        }
    }

    private func handle(message: URLSessionWebSocketTask.Message) async {
        let text: String
        switch message {
        case let .string(s): text = s
        case let .data(d): text = String(data: d, encoding: .utf8) ?? ""
        @unknown default: return
        }
        guard let data = text.data(using: .utf8) else { return }
        do {
            // First peek at MessageType.
            let envelope = try JellyfinJSON.decoder.decode(WebSocketMessageDTO.self, from: data)
            switch envelope.messageType {
            case "GroupUpdate", "SyncPlayGroupUpdate":
                if let group = _currentGroup {
                    eventContinuation.yield(.groupChanged(group))
                }
            case "PlayerPlayback", "SyncPlayCommand":
                // Server-initiated play/pause/seek; the schema of the Data
                // field varies wildly across Jellyfin versions. Best effort:
                // parse a top-level PositionTicks if present.
                if let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let payload = obj["Data"] as? [String: Any],
                   let positionTicks = payload["PositionTicks"] as? Int64 {
                    let seconds = TimeInterval(positionTicks) / 10_000_000
                    if let command = payload["Command"] as? String {
                        switch command.lowercased() {
                        case "pause": eventContinuation.yield(.pause(positionSeconds: seconds))
                        case "unpause", "play": eventContinuation.yield(.play(positionSeconds: seconds))
                        case "seek": eventContinuation.yield(.seek(positionSeconds: seconds))
                        default: break
                        }
                    }
                }
            default:
                break
            }
        } catch {
            logger.debug("WebSocket decode ignored: \(String(describing: error), privacy: .public)")
        }
    }
}
