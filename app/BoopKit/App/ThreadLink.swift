import Foundation
import HookWire

/// Where a thread opens on the Mac (BEHAVIORS.md §3.2): the thread itself
/// in the Claude or Codex app, else the app the agent runs in, such as its
/// terminal, brought to the front.
public enum ThreadLink {
    public enum Target: Equatable, Sendable {
        /// A link its app opens the thread at.
        case url(String)
        /// An app to bring forward, by bundle ID.
        case app(String)

        /// What `open` is given.
        public var arguments: [String] {
            switch self {
            case .url(let url): [url]
            case .app(let id): ["-b", id]
            }
        }
    }

    /// The target for `thread`, or nil when nothing says where it runs.
    public static func target(_ thread: ThreadRef) -> Target? {
        switch thread.agent {
        case "claude":
            // The Claude app opens a session by its own ID, which the hook
            // got from the app, not by Claude Code's.
            if let id = thread.appSession, id.range(of: #"^local_[A-Za-z0-9-]{1,64}$"#, options: .regularExpression) != nil {
                return .url("claude://code/continue?session=\(id)")
            }
        case "codex":
            // The Codex app opens a thread by its ID, which is the hook's
            // session. With no app named, it's the Codex app's: a terminal
            // would have named itself.
            if thread.app == nil || thread.app == HostApp.codex,
               let id = thread.session.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(["-", "_"])) {
                return .url("codex://threads/\(id)")
            }
        default:
            break
        }
        return thread.app.map(Target.app)
    }

    /// Opens `target` with `/usr/bin/open`, which starts the app if it
    /// isn't running. Returns whether `open` started; it isn't waited on.
    @Sendable public static func openOnMac(_ target: Target) -> Bool {
        let open = Process()
        open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        open.arguments = target.arguments
        open.standardOutput = FileHandle.nullDevice
        open.standardError = FileHandle.nullDevice
        return (try? open.run()) != nil
    }
}
