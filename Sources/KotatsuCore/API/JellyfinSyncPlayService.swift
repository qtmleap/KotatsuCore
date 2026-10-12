import Foundation
import os

/// Real `SyncPlayService`. Owns two responsibilities:
///
/// * REST calls to `/SyncPlay/*` for group management + playback commands.
/// * A `URLSessionWebSocketTask` connected to `/socket?ApiKey=...` that
///   receives `GroupUpdate` messages and translates them into
///   `SyncPlayEvent`s on the public `AsyncStream`.
public actor JellyfinSyncPlayService: SyncPlayService {
    private let http: JellyfinHTTPClient
    private let logger = Logger(subsystem: "app.jellyfin.tvos", category: "syncplay")

    private var _currentGroup: SyncPlayGroup? {
        didSet {
            // Same group identity (e.g. a GroupJoined refresh in another
            // UUID spelling) keeps the record; any other change drops it.
            if oldValue.map({ Self.normalizedId($0.id) })
                != _currentGroup.map({ Self.normalizedId($0.id) })
            {
                hasGroupActionOnCurrentSocket = false
            }
        }
    }
    /// True once a group REST action was dispatched while a group was cached
    /// and the current socket was allocated. Only then may a zero-GUID
    /// `NotInGroup` be read as rejecting the cached group. Known limit: an
    /// obsolete unscoped rejection arriving after a new join AND a new action
    /// is fundamentally uncorrelated; we only guard the post-join, pre-action
    /// window.
    private var hasGroupActionOnCurrentSocket = false
    private var socketTask: URLSessionWebSocketTask?
    private var listenerTask: Task<Void, Never>?
    private var keepAliveTask: Task<Void, Never>?
    private let urlSession: URLSession

    private let eventContinuation: AsyncStream<SyncPlayEvent>.Continuation
    public nonisolated let events: AsyncStream<SyncPlayEvent>

    public init(http: JellyfinHTTPClient, urlSession: URLSession = .shared) {
        self.http = http
        self.urlSession = urlSession
        let (events, continuation) = AsyncStream<SyncPlayEvent>.makeStream()
        self.events = events
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
        hasGroupActionOnCurrentSocket = false
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
                    underlying:
                        "SyncPlay/New succeeded but no new group was found in /SyncPlay/List"
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
        hasGroupActionOnCurrentSocket = false
        _ = try await http.send(SyncPlayJoinRequest(groupId: id))
        let groups = try await availableGroups()
        if let group = groups.first(where: { $0.id == id }) {
            _currentGroup = group
            eventContinuation.yield(.groupChanged(group))
        }
        await ensureSocketConnected()
    }

    public func leaveGroup() async throws {
        hasGroupActionOnCurrentSocket = false
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
            recordGroupAction()
            _ = try await http.send(SyncPlayUnpauseRequest())
        } catch {
            logger.warning("requestPlay failed: \(String(describing: error), privacy: .public)")
        }
    }

    public func requestPause(positionSeconds: TimeInterval) async {
        do {
            recordGroupAction()
            _ = try await http.send(SyncPlayPauseRequest())
        } catch {
            logger.warning("requestPause failed: \(String(describing: error), privacy: .public)")
        }
    }

    public func requestSeek(positionSeconds: TimeInterval) async {
        do {
            recordGroupAction()
            _ = try await http.send(
                SyncPlaySeekRequest(positionTicks: Int64(positionSeconds * 10_000_000)))
        } catch {
            logger.warning("requestSeek failed: \(String(describing: error), privacy: .public)")
        }
    }

    // MARK: - Queue + client state

    public func setNewQueue(itemIds: [String], startPositionSeconds: TimeInterval) async throws {
        let ticks = Int64(startPositionSeconds * 10_000_000)
        recordGroupAction()
        _ = try await http.send(
            SyncPlaySetNewQueueRequest(
                itemIds: itemIds,
                startPositionTicks: ticks
            ))
    }

    public func notifyReady(
        positionSeconds: TimeInterval, isPlaying: Bool, playlistItemId: String?
    )
        async
    {
        do {
            recordGroupAction()
            _ = try await http.send(
                SyncPlayReadyRequest(
                    positionTicks: Int64(positionSeconds * 10_000_000),
                    isPlaying: isPlaying,
                    playlistItemId: playlistItemId,
                    when: Date()
                ))
        } catch {
            logger.warning("notifyReady failed: \(String(describing: error), privacy: .public)")
        }
    }

    public func notifyBuffering(
        positionSeconds: TimeInterval, isPlaying: Bool, playlistItemId: String?
    ) async {
        do {
            recordGroupAction()
            _ = try await http.send(
                SyncPlayBufferingRequest(
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
            recordGroupAction()
            _ = try await http.send(SyncPlayStopRequest())
        } catch {
            logger.warning("stopGroup failed: \(String(describing: error), privacy: .public)")
        }
    }

    /// Records an action before dispatch, so its WebSocket rejection may arrive
    /// before or after the HTTP response. Membership/socket transitions reset
    /// the record; an old request completion must never restore it.
    /// `socketTask` denotes the allocated current transport, which may still
    /// be connecting. It does not assert that the handshake has completed.
    private func recordGroupAction() {
        hasGroupActionOnCurrentSocket = _currentGroup != nil && socketTask != nil
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
            URLQueryItem(name: "ApiKey", value: token),
            URLQueryItem(name: "deviceId", value: http.deviceId),
        ]
        guard let url = comps.url else {
            AppLogger.error("SyncPlay WS: could not build socket URL")
            return
        }
        AppLogger.info("SyncPlay WS: connecting")
        let task = urlSession.webSocketTask(with: url)
        self.socketTask = task
        hasGroupActionOnCurrentSocket = false
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
                let nsError = error as NSError
                AppLogger.warning("SyncPlay WS: receive ended — \(nsError.domain) \(nsError.code)")
                // A failed socket does not end the server-side membership.
                // Explicit leave/rejection paths still publish disconnected.
                if _currentGroup == nil { eventContinuation.yield(.disconnected) }
                socketTask = nil
                hasGroupActionOnCurrentSocket = false
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
                let nsError = error as NSError
                AppLogger.warning(
                    "SyncPlay WS: keepalive send failed — \(nsError.domain) \(nsError.code)")
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
        case .string(let s):
            guard let d = s.data(using: .utf8) else { return }
            data = d
        case .data(let d):
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
            AppLogger.warning("SyncPlay WS: decode ignored — \(Self.describe(error))")
        }
    }

    // MARK: - Helpers

    /// Domain + code (or type) only; never the error's description, which can
    /// embed payload fragments.
    private static func describe(_ error: Error) -> String {
        if error is DecodingError { return "DecodingError" }
        let ns = error as NSError
        return "\(ns.domain) \(ns.code)"
    }

    /// Case-insensitive comparison key. UUIDs in dashed or N (32 hex) form map
    /// to the same key; other identifiers compare case-insensitively as-is.
    private static func normalizedId(_ id: String) -> String {
        let lower = id.trimmingCharacters(in: .whitespaces).lowercased()
        let undashed = lower.replacingOccurrences(of: "-", with: "")
        if undashed.count == 32, undashed.allSatisfy(\.isHexDigit) { return undashed }
        return lower
    }

    private static func isZeroGuid(_ id: String) -> Bool {
        let key = normalizedId(id)
        return key.count == 32 && key.allSatisfy { $0 == "0" }
    }

    /// True when an update/command scoped to `groupId` should be ignored
    /// because it targets a group other than the cached current one. With no
    /// scope or no cached group there is nothing to contradict.
    private func isForeign(_ groupId: String?) -> Bool {
        guard let groupId, !groupId.isEmpty, let current = _currentGroup else { return false }
        return Self.normalizedId(groupId) != Self.normalizedId(current.id)
    }

    /// Re-encodes a polymorphic inner payload only when it is a valid JSON
    /// dictionary (scalars/NSNull would raise an ObjC exception).
    private static func decodeObject<T: Decodable>(_ type: T.Type, from value: Any?) -> T? {
        guard let dict = value as? [String: Any], JSONSerialization.isValidJSONObject(dict),
            let data = try? JSONSerialization.data(withJSONObject: dict)
        else { return nil }
        return try? JellyfinJSON.decoder.decode(T.self, from: data)
    }

    private func handleSyncPlayCommand(data: Data) {
        let message: SyncPlayCommandMessageDTO
        do {
            message = try JellyfinJSON.decoder.decode(SyncPlayCommandMessageDTO.self, from: data)
        } catch {
            AppLogger.warning("SyncPlay WS: command decode failed — \(Self.describe(error))")
            return
        }
        guard let cmd = message.data, let commandName = cmd.command else {
            AppLogger.warning("SyncPlay WS: command without payload ignored")
            return
        }
        guard let kind = SyncPlayCommandKind(rawValue: commandName) else {
            logger.debug("Unsupported SyncPlay command ignored")
            return
        }
        if isForeign(cmd.groupId) {
            logger.debug("Foreign-group SyncPlay command ignored")
            return
        }
        AppLogger.info("SyncPlay WS SendCommand: \(kind.rawValue)")
        eventContinuation.yield(
            .command(
                SyncPlayCommand(
                    kind: kind,
                    groupId: cmd.groupId,
                    playlistItemId: cmd.playlistItemId,
                    positionSeconds: cmd.positionTicks.map { TimeInterval($0) / 10_000_000 },
                    when: cmd.when,
                    emittedAt: cmd.emittedAt
                )))
    }

    private func handleSyncPlayGroupUpdate(data: Data) {
        // The `Data` field of a GroupUpdate is polymorphic on its inner
        // `Type`, so we walk it via JSONSerialization to avoid modelling
        // every variant, type-guarding each inner payload.
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let update = root["Data"] as? [String: Any],
            let type = update["Type"] as? String
        else {
            AppLogger.warning("SyncPlay WS: malformed GroupUpdate ignored")
            return
        }
        let outerGroupId = update["GroupId"] as? String

        AppLogger.info("SyncPlay WS GroupUpdate: \(type)")
        switch type {
        case "GroupJoined":
            guard let dto = Self.decodeObject(SyncPlayGroupInfoDTO.self, from: update["Data"]),
                !dto.groupId.isEmpty
            else {
                AppLogger.warning("SyncPlay WS: malformed GroupJoined ignored")
                return
            }
            if let outerGroupId, !outerGroupId.isEmpty,
                Self.normalizedId(outerGroupId) != Self.normalizedId(dto.groupId)
            {
                AppLogger.warning("SyncPlay WS: GroupJoined identity mismatch ignored")
                return
            }
            let group = dto.toDomain()
            _currentGroup = group
            eventContinuation.yield(.groupChanged(group))
        case "GroupLeft", "NotInGroup", "GroupDoesNotExist":
            // Membership-ending (GroupLeft) or rejection (stale state).
            // Scoped to the current group; foreign ones are ignored.
            let scope = outerGroupId ?? (type == "GroupLeft" ? update["Data"] as? String : nil)
            if type == "NotInGroup", let scope, !scope.isEmpty,
                Self.isZeroGuid(scope)
            {
                // A session rejection carries an all-zero GUID instead of the
                // group id. Honour it only after an action was dispatched with
                // the cached membership and current allocated socket.
                guard _currentGroup != nil, hasGroupActionOnCurrentSocket else {
                    logger.debug("Unscoped NotInGroup ignored")
                    return
                }
            } else if isForeign(scope) {
                logger.debug("Foreign-group \(type, privacy: .public) ignored")
                return
            }
            _currentGroup = nil
            eventContinuation.yield(.disconnected)
        case "UserJoined":
            guard !isForeign(outerGroupId) else { return }
            if let username = update["Data"] as? String {
                eventContinuation.yield(
                    .participantJoined(
                        SyncPlayParticipant(id: username, userName: username, isOnline: true)
                    ))
            }
        case "UserLeft":
            guard !isForeign(outerGroupId) else { return }
            if let username = update["Data"] as? String {
                eventContinuation.yield(.participantLeft(username))
            }
        case "PlayQueue":
            handlePlayQueue(update: update, groupId: outerGroupId)
        case "StateUpdate":
            // Diagnostic only: state changes reach us as SyncPlayCommand
            // messages. Never translated to stop/close.
            if let state = update["Data"] as? [String: Any] {
                let s = (state["State"] as? String) ?? "?"
                let r = (state["Reason"] as? String) ?? "?"
                logger.debug(
                    "SyncPlay StateUpdate state=\(s, privacy: .public) reason=\(r, privacy: .public)"
                )
            } else {
                logger.debug("SyncPlay StateUpdate with malformed payload")
            }
        case "LibraryAccessDenied":
            logger.warning("SyncPlay library access denied (diagnostic only)")
        default:
            logger.debug("Unsupported GroupUpdate type ignored")
        }
    }

    private func handlePlayQueue(update: [String: Any], groupId: String?) {
        if isForeign(groupId) {
            logger.debug("Foreign-group PlayQueue ignored")
            return
        }
        guard let dto = Self.decodeObject(PlayQueueUpdateDTO.self, from: update["Data"]),
            let playlist = dto.playlist,
            let idx = dto.playingItemIndex
        else {
            AppLogger.warning("SyncPlay WS: malformed PlayQueue ignored")
            return
        }
        var itemId: String?
        var playlistItemId: String?
        if idx == -1 || (playlist.isEmpty && idx == 0) {
            // Valid queue with no current item.
        } else if playlist.indices.contains(idx) {
            itemId = playlist[idx].itemId
            playlistItemId = playlist[idx].playlistItemId
        } else {
            AppLogger.warning("SyncPlay WS: PlayQueue index out of range ignored")
            return
        }
        eventContinuation.yield(
            .queueChanged(
                SyncPlayQueueUpdate(
                    groupId: groupId,
                    itemId: itemId,
                    playlistItemId: playlistItemId,
                    startPositionSeconds: TimeInterval(dto.startPositionTicks ?? 0) / 10_000_000,
                    isPlaying: dto.isPlaying ?? false,
                    reason: dto.reason,
                    lastUpdate: dto.lastUpdate
                )))
    }
}
