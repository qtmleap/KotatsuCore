import Network
import XCTest

@testable import KotatsuCore

/// Quick Connect polling must only *return* the authenticated profile and
/// token; committing them (Keychain, stored users, current user, HTTP
/// credentials) is the caller's explicit `addUser` step, so a cancelled
/// caller never ends up with a half-persisted session.
final class JellyfinQuickConnectPersistenceTests: XCTestCase {

  func testPollQuickConnectDoesNotPersistUntilAddUserIsCalled() async throws {
    let suiteName = "app.jellyfin.tvos.tests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    let keychain = KeychainStore(service: "app.jellyfin.tvos.tests.\(UUID().uuidString)")
    let userId = "quick-connect-user-\(UUID().uuidString)"
    let tokenKey = "token:\(userId)"
    let secret = "synthetic-secret-\(UUID().uuidString)"
    let accessToken = "synthetic-token"

    let loopback = try QuickConnectLoopbackServer(
      secret: secret,
      userId: userId,
      userName: "Quick Connect User",
      serverId: "quick-connect-server",
      accessToken: accessToken
    )
    // Registered before start so every exit path cancels the listener.
    defer {
      loopback.stop()
      keychain.removeValue(forKey: tokenKey)
      defaults.removePersistentDomain(forName: suiteName)
    }
    let port = try await loopback.start()

    let server = Server(
      id: "quick-connect-server",
      name: "Quick Connect Test Server",
      url: try XCTUnwrap(URL(string: "http://127.0.0.1:\(port)"))
    )
    let http = JellyfinHTTPClient(server: server)
    let service = JellyfinAuthService(
      http: http,
      keychain: keychain,
      defaults: try XCTUnwrap(UserDefaults(suiteName: suiteName))
    )
    let session = QuickConnectSession(
      code: "123456",
      secret: secret,
      expiresAt: Date().addingTimeInterval(600)
    )

    let status = try await service.pollQuickConnect(server: server, session: session)

    // The server saw exactly the expected endpoints, in order.
    XCTAssertEqual(
      loopback.requestLog,
      [
        "GET /QuickConnect/Connect",
        "POST /Users/AuthenticateWithQuickConnect",
      ])

    // The authenticated result carries the profile and token...
    guard case .authenticated(let profile, let returnedToken) = status else {
      return XCTFail("Expected .authenticated, got \(status)")
    }
    XCTAssertEqual(profile.id, userId)
    XCTAssertEqual(profile.name, "Quick Connect User")
    XCTAssertEqual(profile.serverId, "quick-connect-server")
    XCTAssertEqual(returnedToken, accessToken)

    // ...but nothing has been persisted or applied yet.
    var storedUsers = await service.storedUsers()
    var currentUser = await service.currentUser()
    var storedToken = await service.accessToken(for: userId)
    XCTAssertTrue(storedUsers.isEmpty, "pollQuickConnect must not store users")
    XCTAssertNil(currentUser, "pollQuickConnect must not set the current user")
    XCTAssertNil(storedToken)
    XCTAssertNil(keychain.string(forKey: tokenKey), "pollQuickConnect must not write the Keychain")
    XCTAssertNil(defaults.data(forKey: JellyfinAuthService.storedUsersKey))
    XCTAssertNil(defaults.string(forKey: JellyfinAuthService.currentUserKey))
    XCTAssertNil(http.accessToken, "pollQuickConnect must not apply HTTP credentials")
    XCTAssertNil(http.userId)

    // Explicit commit persists everything.
    try await service.addUser(profile, server: server, accessToken: returnedToken)

    storedUsers = await service.storedUsers()
    currentUser = await service.currentUser()
    storedToken = await service.accessToken(for: userId)
    XCTAssertEqual(storedUsers, [StoredUser(profile: profile, server: server)])
    XCTAssertEqual(currentUser?.id, userId)
    XCTAssertEqual(storedToken, accessToken)
    XCTAssertEqual(keychain.string(forKey: tokenKey), accessToken)
    XCTAssertNotNil(defaults.data(forKey: JellyfinAuthService.storedUsersKey))
    XCTAssertEqual(defaults.string(forKey: JellyfinAuthService.currentUserKey), userId)
    XCTAssertEqual(http.accessToken, accessToken)
    XCTAssertEqual(http.userId, userId)
  }
}

// MARK: - Loopback server

/// Minimal single-purpose HTTP/1.1 server bound to 127.0.0.1 on an ephemeral
/// port. It answers only the two Quick Connect endpoints with the exact
/// method and a matching secret; everything else gets a 404/400 so an
/// unexpected request shows up in `requestLog` and fails the test.
private final class QuickConnectLoopbackServer: @unchecked Sendable {
  private struct ParsedRequest {
    let method: String
    let path: String
    let query: [String: String]
    let body: Data
  }

  private enum StartError: Error {
    case timedOut
    case cancelled
    case noPort
  }

  /// Resumes a continuation at most once, whichever of ready / failed /
  /// timeout happens first.
  private final class ResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<UInt16, Error>?

    init(_ continuation: CheckedContinuation<UInt16, Error>) {
      self.continuation = continuation
    }

    func resume(with result: Result<UInt16, Error>) {
      lock.lock()
      let pending = continuation
      continuation = nil
      lock.unlock()
      pending?.resume(with: result)
    }
  }

  private let listener: NWListener
  private let queue = DispatchQueue(label: "app.jellyfin.tvos.tests.quickconnect-loopback")
  private let lock = NSLock()
  private var requests: [String] = []
  private var connections: [ObjectIdentifier: NWConnection] = [:]

  private let secret: String
  private let authBody: Data
  private let pollBody: Data

  init(secret: String, userId: String, userName: String, serverId: String, accessToken: String)
    throws
  {
    self.secret = secret
    let user: [String: Any] = ["Id": userId, "Name": userName, "ServerId": serverId]
    pollBody = try JSONSerialization.data(withJSONObject: [
      "Authenticated": true,
      "Secret": secret,
      "Code": "123456",
    ])
    authBody = try JSONSerialization.data(withJSONObject: [
      "User": user,
      "AccessToken": accessToken,
      "ServerId": serverId,
    ])

    let parameters = NWParameters.tcp
    parameters.requiredLocalEndpoint = NWEndpoint.hostPort(host: .ipv4(.loopback), port: .any)
    listener = try NWListener(using: parameters)
  }

  /// "METHOD /path" for every request received, in arrival order.
  var requestLog: [String] {
    lock.lock()
    defer { lock.unlock() }
    return requests
  }

  /// Starts listening and returns the bound port. Bounded to 5 seconds.
  func start() async throws -> UInt16 {
    try await withCheckedThrowingContinuation { continuation in
      let gate = ResumeOnce(continuation)
      listener.stateUpdateHandler = { [weak self] state in
        switch state {
        case .ready:
          if let port = self?.listener.port?.rawValue {
            gate.resume(with: .success(port))
          } else {
            gate.resume(with: .failure(StartError.noPort))
          }
        case .failed(let error):
          gate.resume(with: .failure(error))
        case .cancelled:
          gate.resume(with: .failure(StartError.cancelled))
        default:
          break
        }
      }
      listener.newConnectionHandler = { [weak self] connection in
        self?.accept(connection)
      }
      listener.start(queue: queue)
      queue.asyncAfter(deadline: .now() + 5) {
        gate.resume(with: .failure(StartError.timedOut))
      }
    }
  }

  func stop() {
    listener.cancel()
    lock.lock()
    let open = Array(connections.values)
    connections.removeAll()
    lock.unlock()
    open.forEach { $0.cancel() }
  }

  // MARK: Connection handling

  private func accept(_ connection: NWConnection) {
    lock.lock()
    connections[ObjectIdentifier(connection)] = connection
    lock.unlock()
    connection.start(queue: queue)
    receive(on: connection, buffered: Data())
  }

  private func receive(on connection: NWConnection, buffered: Data) {
    connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) {
      [weak self] data, _, isComplete, error in
      guard let self else { return connection.cancel() }
      var buffer = buffered
      if let data { buffer.append(data) }
      if let request = Self.parse(buffer) {
        self.respond(to: request, on: connection)
      } else if error != nil || isComplete {
        self.close(connection)
      } else {
        self.receive(on: connection, buffered: buffer)
      }
    }
  }

  /// Returns nil until the full header block and `Content-Length` body
  /// have arrived.
  private static func parse(_ data: Data) -> ParsedRequest? {
    guard let headerEnd = data.range(of: Data("\r\n\r\n".utf8)),
      let head = String(data: data[..<headerEnd.lowerBound], encoding: .utf8)
    else { return nil }
    let lines = head.components(separatedBy: "\r\n")
    let requestLine = lines[0].split(separator: " ")
    guard requestLine.count >= 2 else { return nil }

    var contentLength = 0
    for line in lines.dropFirst() {
      let parts = line.split(separator: ":", maxSplits: 1)
      if parts.count == 2, parts[0].lowercased() == "content-length" {
        contentLength = Int(parts[1].trimmingCharacters(in: .whitespaces)) ?? 0
      }
    }
    let body = data[headerEnd.upperBound...]
    guard body.count >= contentLength else { return nil }

    let components = URLComponents(string: String(requestLine[1]))
    var query: [String: String] = [:]
    for item in components?.queryItems ?? [] {
      query[item.name] = item.value ?? ""
    }
    return ParsedRequest(
      method: String(requestLine[0]),
      path: components?.path ?? String(requestLine[1]),
      query: query,
      body: Data(body.prefix(contentLength))
    )
  }

  private func respond(to request: ParsedRequest, on connection: NWConnection) {
    lock.lock()
    requests.append("\(request.method) \(request.path)")
    lock.unlock()

    var status = "404 Not Found"
    var body = Data("{}".utf8)
    switch (request.method, request.path) {
    case ("GET", "/QuickConnect/Connect"):
      if request.query["Secret"] == secret {
        status = "200 OK"
        body = pollBody
      } else {
        status = "400 Bad Request"
      }
    case ("POST", "/Users/AuthenticateWithQuickConnect"):
      let json = try? JSONSerialization.jsonObject(with: request.body) as? [String: Any]
      if json?["Secret"] as? String == secret {
        status = "200 OK"
        body = authBody
      } else {
        status = "400 Bad Request"
      }
    default:
      break
    }

    let head =
      "HTTP/1.1 \(status)\r\n"
      + "Content-Type: application/json\r\n"
      + "Content-Length: \(body.count)\r\n"
      + "Connection: close\r\n\r\n"
    connection.send(
      content: Data(head.utf8) + body,
      completion: .contentProcessed { [weak self] _ in
        self?.close(connection)
      }
    )
  }

  private func close(_ connection: NWConnection) {
    lock.lock()
    connections.removeValue(forKey: ObjectIdentifier(connection))
    lock.unlock()
    connection.cancel()
  }
}
