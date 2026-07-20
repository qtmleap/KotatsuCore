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
    private var keepAliveTask: Task<Void, Never>?
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
        keepAliveTask?.cancel()
        socketTask?.cancel(with: .goingAway, reason: nil)
        eventContinuation.finish()
    }

    // MARK: - Public state

    public var currentGroup: SyncPlayGroup? { _currentGroup }

    // MARK: - Group management

    public func availableGroups() async throws -> [SyncPlayGroup] {
        // Piggy-back on the periodic /List poll to keep the WebSocket alive.
        // Jellyfin's group broadcast targets the SessionIds that were
        // registered when /SyncPlay/Join arrived; if our WS wasn't already
        // connected at that moment the server may not associate later WS
        // traffic with the group, and we'd silently miss every
        // SyncPlayGroupUpdate. Opening the socket up-front avoids that
        // ordering trap.
        await ensureSocketConnected()
        let groups = try await http.send(SyncPlayListRequest())
        return groups.map { $0.toDomain() }
    }

    public func createGroup(name: String) async throws -> SyncPlayGroup {
        // Snapshot the group list BEFORE creation so the 204 branch has a way
        // to identify the freshly-created group (see fallback below).
        let priorIds = Set(((try? await http.send(SyncPlayListRequest())) ?? []).map(\.groupId))

        let response = try await http.send(SyncPlayNewGroupRequest(groupName: name))

        let dto: SyncPlayGroupInfoDTO
        if let response {
            // Happy path — server returned 200 with the GroupInfoDto.
            dto = response
        } else {
            // 204 fallback: server confirmed creation but didn't hand us the
            // DTO. Re-fetch `/List` and pick the group that wasn't there
            // before — that's ours. Server-side the caller is auto-joined
            // to the new group, so it must be in the list.
            let after = try await http.send(SyncPlayListRequest())
            guard let created = after.first(where: { !priorIds.contains($0.groupId) }) else {
                throw JellyfinAPIError.decoding(
                    underlying: "SyncPlay/New succeeded but no new group was found in /SyncPlay/List"
                )
            }
            dto = created
        }

        let group = dto.toDomain()
        _currentGroup = group
        await ensureSocketConnected()
        eventContinuation.yield(.groupChanged(group))
        return group
    }

    public func joinGroup(id: String) async throws {
        _ = try await http.send(SyncPlayJoinRequest(groupId: id))
        let groups = try await availableGroups()
        if let group = groups.first(where: { $0.id == id }) {
            _currentGroup = group
            eventContinuation.yield(.groupChanged(group))
        }
        await ensureSocketConnected()
    }

    public func leaveGroup() async throws {
        _ = try await http.send(SyncPlayLeaveRequest())
        _currentGroup = nil
        eventContinuation.yield(.disconnected)
    }

    // MARK: - Playback commands

    public func requestPlay(positionSeconds: TimeInterval) async {
        // The spec's Unpause endpoint takes no body — server uses the
        // group's own tracked position for the resumption anchor. We used
        // to send an extra Seek here to force our local position onto the
        // group; that behaviour is now covered by the server pushing back
        // a Seek command inside its Unpause broadcast when catch-up is
        // needed, so double-writing was just adding races.
        do {
            _ = try await http.send(SyncPlayUnpauseRequest())
        } catch {
            logger.warning("requestPlay failed: \(String(describing: error), privacy: .public)")
        }
    }

    public func requestPause(positionSeconds: TimeInterval) async {
        do {
            _ = try await http.send(SyncPlayPauseRequest())
        } catch {
            logger.warning("requestPause failed: \(String(describing: error), privacy: .public)")
        }
    }

    public func requestSeek(positionSeconds: TimeInterval) async {
        do {
            _ = try await http.send(SyncPlaySeekRequest(positionTicks: Int64(positionSeconds * 10_000_000)))
        } catch {
            logger.warning("requestSeek failed: \(String(describing: error), privacy: .public)")
        }
    }

    // MARK: - Queue + client state

    public func setNewQueue(itemIds: [String], startPositionSeconds: TimeInterval) async throws {
        let ticks = Int64(startPositionSeconds * 10_000_000)
        _ = try await http.send(SyncPlaySetNewQueueRequest(
            itemIds: itemIds,
            startPositionTicks: ticks
        ))
    }

    public func notifyReady(positionSeconds: TimeInterval, isPlaying: Bool, playlistItemId: String?) async {
        do {
            _ = try await http.send(SyncPlayReadyRequest(
                positionTicks: Int64(positionSeconds * 10_000_000),
                isPlaying: isPlaying,
                playlistItemId: playlistItemId,
                when: Date()
            ))
        } catch {
            logger.warning("notifyReady failed: \(String(describing: error), privacy: .public)")
        }
    }

    public func notifyBuffering(positionSeconds: TimeInterval, isPlaying: Bool, playlistItemId: String?) async {
        do {
            _ = try await http.send(SyncPlayBufferingRequest(
                positionTicks: Int64(positionSeconds * 10_000_000),
                isPlaying: isPlaying,
                playlistItemId: playlistItemId,
                when: Date()
            ))
        } catch {
            logger.warning("notifyBuffering failed: \(String(describing: error), privacy: .public)")
        }
    }

    public func stopGroup() async {
        do {
            _ = try await http.send(SyncPlayStopRequest())
        } catch {
            logger.warning("stopGroup failed: \(String(describing: error), privacy: .public)")
        }
    }

    // MARK: - WebSocket

    private func ensureSocketConnected() async {
        if socketTask != nil {
            AppLogger.debug("SyncPlay WS: already connected")
            return
        }
        guard let token = http.accessToken, !token.isEmpty else {
            AppLogger.warning("SyncPlay WS: no access token, refusing to connect")
            return
        }
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
        guard let url = comps.url else {
            AppLogger.error("SyncPlay WS: could not build socket URL from \(http.server.url.absoluteString)")
            return
        }
        AppLogger.info("SyncPlay WS: connecting \(url.absoluteString)")
        let task = urlSession.webSocketTask(with: url)
        self.socketTask = task
        task.resume()
        listenerTask = Task { [weak self] in
            await self?.listenLoop()
        }
        // Jellyfin's server pushes a `ForceKeepAlive` frame right after
        // handshake indicating its own idle timeout — the safe default is
        // to ping every 30 seconds regardless, well under the usual 60s
        // Jellyfin cutoff. Without this the socket goes silent, the server
        // eventually drops it, and every SyncPlay command misses.
        keepAliveTask = Task { [weak self] in
            await self?.keepAliveLoop()
        }
    }

    private func listenLoop() async {
        guard let task = socketTask else { return }
        AppLogger.info("SyncPlay WS: listen loop started")
        while !Task.isCancelled {
            do {
                let message = try await task.receive()
                await handle(message: message)
            } catch {
                AppLogger.warning("SyncPlay WS: receive ended — \(String(describing: error))")
                eventContinuation.yield(.disconnected)
                socketTask = nil
                keepAliveTask?.cancel()
                keepAliveTask = nil
                return
            }
        }
        AppLogger.info("SyncPlay WS: listen loop cancelled")
    }

    /// Client-side keepalive. Jellyfin expects periodic `KeepAlive` frames
    /// or it will drop the socket after a minute or so. Silent socket ≡
    /// missed SyncPlay commands, which is invisible to the user until they
    /// wonder why pause doesn't propagate.
    private func keepAliveLoop() async {
        while !Task.isCancelled, let task = socketTask {
            try? await Task.sleep(for: .seconds(30))
            if Task.isCancelled { return }
            let frame = #"{"MessageType":"KeepAlive"}"#
            do {
                try await task.send(.string(frame))
            } catch {
                AppLogger.warning("SyncPlay WS: keepalive send failed — \(String(describing: error))")
                return
            }
        }
    }

    /// WebSocket message router. Jellyfin's socket multiplexes many message
    /// types onto the same connection; we only care about `SyncPlayCommand`
    /// (Unpause/Pause/Stop/Seek from the server) and `SyncPlayGroupUpdate`
    /// (membership/state/queue changes). Everything else is dropped.
    private func handle(message: URLSessionWebSocketTask.Message) async {
        let data: Data
        switch message {
        case let .string(s):
            guard let d = s.data(using: .utf8) else { return }
            data = d
        case let .data(d):
            data = d
        @unknown default: return
        }
        // Log every raw frame we see so a session-registration bug where
        // the server drops us from group broadcasts is visible in the log
        // rather than silent. Capped at 300 chars so a big PlayQueue payload
        // doesn't drown the file.
        let preview = String(data: data.prefix(300), encoding: .utf8) ?? "<binary>"
        AppLogger.debug("SyncPlay WS raw ← \(preview)")
        do {
            // First peek at MessageType to pick the right typed decoder —
            // decoding the whole polymorphic envelope in one pass would
            // require modelling every message variant, so the two-pass
            // approach keeps the surface area small.
            let envelope = try JellyfinJSON.decoder.decode(WebSocketMessageDTO.self, from: data)
            switch envelope.messageType {
            case "SyncPlayCommand":
                AppLogger.info("SyncPlay WS ← SyncPlayCommand (\(data.count) bytes)")
                handleSyncPlayCommand(data: data)
            case "SyncPlayGroupUpdate":
                AppLogger.info("SyncPlay WS ← SyncPlayGroupUpdate (\(data.count) bytes)")
                handleSyncPlayGroupUpdate(data: data)
            case "ForceKeepAlive":
                // Server telling us its idle-timeout. Our own keepalive
                // loop already sends every 30s, well under any sane
                // timeout, so we just log and move on.
                AppLogger.debug("SyncPlay WS ← ForceKeepAlive")
            case "KeepAlive":
                break
            default:
                AppLogger.debug("SyncPlay WS ← \(envelope.messageType) (ignored)")
            }
        } catch {
            AppLogger.warning("SyncPlay WS: decode ignored — \(String(describing: error))")
        }
    }

    private func handleSyncPlayCommand(data: Data) {
        guard
            let message = try? JellyfinJSON.decoder.decode(SyncPlayCommandMessageDTO.self, from: data),
            let cmd = message.data,
            let commandName = cmd.command
        else { return }

        // PositionTicks is nullable in the spec (Pause without a target
        // position is legal). Fall back to 0 so downstream player logic
        // can still make a decision, though it'll usually just pause where
        // it is.
        let seconds: TimeInterval = cmd.positionTicks.map { TimeInterval($0) / 10_000_000 } ?? 0

        AppLogger.info("SyncPlay WS SendCommand: \(commandName) @ \(seconds)s")
        switch commandName {
        case "Unpause":
            eventContinuation.yield(.play(positionSeconds: seconds))
        case "Pause":
            eventContinuation.yield(.pause(positionSeconds: seconds))
        case "Seek":
            eventContinuation.yield(.seek(positionSeconds: seconds))
        case "Stop":
            eventContinuation.yield(.stop)
        default:
            logger.debug("Unknown SyncPlay command: \(commandName, privacy: .public)")
        }
    }

    private func handleSyncPlayGroupUpdate(data: Data) {
        // The `Data` field of a GroupUpdate is polymorphic on its inner
        // `Type`, so we decode it via JSONSerialization to avoid modelling
        // every variant. The dictionary walk here is deliberately shallow —
        // we only care about a handful of update kinds.
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let update = root["Data"] as? [String: Any],
            let type = update["Type"] as? String
        else { return }

        AppLogger.info("SyncPlay WS GroupUpdate: \(type)")
        switch type {
        case "GroupJoined":
            // `Data.Data` is a full GroupInfoDto — pull it out via re-encode
            // so we go through the same PascalCase-aware decoder as REST
            // responses. Cheaper than hand-parsing every field.
            if let inner = update["Data"],
               let innerData = try? JSONSerialization.data(withJSONObject: inner),
               let dto = try? JellyfinJSON.decoder.decode(SyncPlayGroupInfoDTO.self, from: innerData) {
                let group = dto.toDomain()
                _currentGroup = group
                eventContinuation.yield(.groupChanged(group))
            }
        case "GroupLeft":
            _currentGroup = nil
            eventContinuation.yield(.disconnected)
        case "UserJoined":
            if let username = update["Data"] as? String {
                eventContinuation.yield(.participantJoined(
                    SyncPlayParticipant(id: username, userName: username, isOnline: true)
                ))
            }
        case "UserLeft":
            if let username = update["Data"] as? String {
                eventContinuation.yield(.participantLeft(username))
            }
        case "PlayQueue":
            if let inner = update["Data"],
               let innerData = try? JSONSerialization.data(withJSONObject: inner),
               let dto = try? JellyfinJSON.decoder.decode(PlayQueueUpdateDTO.self, from: innerData),
               let playlist = dto.playlist,
               let idx = dto.playingItemIndex, playlist.indices.contains(idx) {
                let item = playlist[idx]
                let seconds = TimeInterval(dto.startPositionTicks ?? 0) / 10_000_000
                eventContinuation.yield(.queueUpdated(
                    itemId: item.itemId,
                    playlistItemId: item.playlistItemId,
                    startPositionSeconds: seconds,
                    isPlaying: dto.isPlaying ?? false
                ))
            }
        case "StateUpdate":
            // No dedicated event yet — the important state changes
            // (Playing/Paused) are already conveyed by the SyncPlayCommand
            // messages that accompany them.
            break
        case "NotInGroup", "GroupDoesNotExist":
            // Server rejected an action because our group state is stale.
            _currentGroup = nil
            eventContinuation.yield(.disconnected)
        case "LibraryAccessDenied":
            logger.warning("SyncPlay library access denied")
        default:
            logger.debug("Unhandled GroupUpdate type: \(type, privacy: .public)")
        }
    }
}
