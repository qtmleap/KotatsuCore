import Foundation
import SwiftyBeaver

/// Central logging facade backed by SwiftyBeaver.
///
/// Call ``bootstrap(minLevel:)`` once at app launch. After that, use the short
/// entry points (``verbose(_:file:function:line:)`` … ``error(_:file:function:line:)``)
/// or reach for `AppLogger.log` directly.
public enum AppLogger {
    public static let log = SwiftyBeaver.self

    /// Minimum severity to accept, in the order SwiftyBeaver understands.
    public enum Level: Sendable {
        case verbose, debug, info, warning, error, critical, fault

        fileprivate var sbLevel: SwiftyBeaver.Level {
            switch self {
            case .verbose:  return .verbose
            case .debug:    return .debug
            case .info:     return .info
            case .warning:  return .warning
            case .error:    return .error
            case .critical: return .critical
            case .fault:    return .fault
            }
        }
    }

    private static let bootstrapLock = NSLock()
    nonisolated(unsafe) private static var didBootstrap = false
    nonisolated(unsafe) private static var logFileURL: URL?

    /// Wire up console + rotating file destinations. Safe to call more than once;
    /// subsequent calls are ignored.
    public static func bootstrap(minLevel: Level = .debug) {
        let sbLevel = minLevel.sbLevel
        bootstrapLock.lock()
        defer { bootstrapLock.unlock() }
        guard !didBootstrap else { return }
        didBootstrap = true

        let console = ConsoleDestination()
        console.minLevel = sbLevel
        console.format = "$DHH:mm:ss.SSS$d [$L] $N.$F:$l $M"
        console.asynchronously = false
        // Route through NSLog / os_log so that logs also appear in Xcode's
        // debug console and Console.app when running on a real device.
        // Xcode does not reliably pipe stdout for tvOS attaches.
        console.useNSLog = true
        console.useTerminalColors = false
        log.addDestination(console)

        let file = FileDestination()
        file.minLevel = sbLevel
        file.format = "$Dyyyy-MM-dd HH:mm:ss.SSS$d [$L] $N.$F:$l $M"
        file.logFileAmount = 5
        file.logFileMaxSize = 1024 * 1024  // 1024KB per file, then rotate
        if let url = makeLogFileURL() {
            file.logFileURL = url
            logFileURL = url
        }
        log.addDestination(file)

        log.info("AppLogger bootstrapped. logFile=\(logFileURL?.path ?? "<none>")")
    }

    /// Path to the current log file, if the file destination is active.
    public static var currentLogFileURL: URL? { logFileURL }

    private static func makeLogFileURL() -> URL? {
        let fm = FileManager.default
        guard let base = fm.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return nil
        }
        let dir = base.appendingPathComponent("Logs", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("jellyfin.log")
    }

    // MARK: - Short entry points

    public static func verbose(
        _ message: @autoclosure () -> Any,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log.verbose(message(), file: file, function: function, line: line)
    }

    public static func debug(
        _ message: @autoclosure () -> Any,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log.debug(message(), file: file, function: function, line: line)
    }

    public static func info(
        _ message: @autoclosure () -> Any,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log.info(message(), file: file, function: function, line: line)
    }

    public static func warning(
        _ message: @autoclosure () -> Any,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log.warning(message(), file: file, function: function, line: line)
    }

    public static func error(
        _ message: @autoclosure () -> Any,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log.error(message(), file: file, function: function, line: line)
    }
}
