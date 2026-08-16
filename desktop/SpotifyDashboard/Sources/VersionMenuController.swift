import Cocoa

/// The "which version am I looking at" menu — the last item in the menu bar.
///
/// The app can be pointed at any checkout (scripts/dashboard-open.sh sets
/// SPOTIFY_DASHBOARD_PATH), so a running window no longer implies main. This
/// names the checkout, says whether it's main or a worktree, how long ago that
/// code last changed, and warns when the branch's Swift is newer than the
/// running binary — since native changes only land through a build.
final class VersionMenuController: NSObject, NSMenuDelegate {

    struct CheckoutInfo {
        var branch: String
        var isWorktree: Bool
        var worktreeName: String?
        var lastChange: Date?
        /// Human label for the menu — a hand-written one from
        /// ~/.claude/worktree-labels.json, else prettified from the branch.
        var label: String = "—"
        /// Title of the Claude Code chat working in this checkout, when there
        /// is one — the name Adrian sees in Claude Code's sidebar.
        var chatTitle: String?
        /// Desktop-app session id (`local_…`) — what the deep link navigates to.
        var desktopSessionID: String?
        /// CLI session id, for claude://resume when Claude Code has no chat of
        /// its own for this checkout.
        var cliSessionID: String?
    }

    let menuItem = NSMenuItem()

    private let projectRoot: String
    private let menu = NSMenu(title: "Version")
    private var info: CheckoutInfo
    private var refreshTimer: Timer?

    /// Files and folders whose mtime counts as "this version changed" — source,
    /// not the runtime state the backend rewrites while it runs (.cache,
    /// config.json), which would otherwise read as a constant edit.
    private static let watched = [
        "app.py",
        "static",
        "scripts",
        "desktop/SpotifyDashboard/Sources",
        "desktop/SpotifyDashboard/Resources",
        "desktop/SpotifyDashboard/build.sh",
        "CLAUDE.md",
    ]

    init(projectRoot: String) {
        self.projectRoot = projectRoot
        self.info = CheckoutInfo(branch: "—", isWorktree: false, worktreeName: nil, lastChange: nil)
        super.init()

        menu.delegate = self
        // Keep the rows we mark disabled disabled (AppKit would re-enable
        // anything with a target/action otherwise).
        menu.autoenablesItems = false
        menuItem.submenu = menu
        applyTitle("⎇ …")

        refresh()
        // The title carries a relative time, so it goes stale on its own.
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    deinit { refreshTimer?.invalidate() }

    // MARK: - Data

    private func refresh() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            let fresh = Self.readCheckout(at: self.projectRoot)
            DispatchQueue.main.async {
                self.info = fresh
                self.applyTitle(self.titleText())
                self.rebuildItems()
            }
        }
    }

    /// Branch + worktree state straight from the git metadata — no subprocess.
    /// A linked worktree marks itself by making `.git` a FILE holding
    /// "gitdir: <common>/.git/worktrees/<name>".
    private static func readCheckout(at root: String) -> CheckoutInfo {
        let fm = FileManager.default
        let dotGit = URL(fileURLWithPath: root).appendingPathComponent(".git")

        var isDir: ObjCBool = false
        let exists = fm.fileExists(atPath: dotGit.path, isDirectory: &isDir)

        var gitDir = dotGit
        var isWorktree = false
        var worktreeName: String?

        if exists && !isDir.boolValue,
           let contents = try? String(contentsOf: dotGit, encoding: .utf8) {
            let pointer = contents
                .replacingOccurrences(of: "gitdir:", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !pointer.isEmpty {
                gitDir = URL(fileURLWithPath: pointer)
                isWorktree = true
                worktreeName = gitDir.lastPathComponent
            }
        }

        var branch = "—"
        if let head = try? String(contentsOf: gitDir.appendingPathComponent("HEAD"), encoding: .utf8) {
            let line = head.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.hasPrefix("ref:") {
                branch = line
                    .replacingOccurrences(of: "ref: refs/heads/", with: "")
                    .trimmingCharacters(in: .whitespaces)
            } else if !line.isEmpty {
                branch = String(line.prefix(7)) // detached HEAD
            }
        }

        let chat = claudeChat(forCheckout: root)
        return CheckoutInfo(branch: branch,
                            isWorktree: isWorktree,
                            worktreeName: worktreeName,
                            lastChange: newestChange(under: root),
                            label: humanLabel(root: root,
                                              branch: branch,
                                              isWorktree: isWorktree,
                                              chatTitle: chat.title),
                            chatTitle: chat.title,
                            desktopSessionID: chat.desktopSessionID,
                            cliSessionID: chat.cliSessionID)
    }

    // MARK: - Human name

    /// Worktree folders are machine-named (`playlist-emoji-display-name-977537`).
    /// A hand-written label wins; otherwise the branch is cleaned up into
    /// something readable — "claude/playlist-emoji-display-name-977537"
    /// becomes "Playlist Emoji Display Name".
    private static func humanLabel(root: String,
                                   branch: String,
                                   isWorktree: Bool,
                                   chatTitle: String?) -> String {
        if let label = storedLabel(for: root), !label.isEmpty { return label }
        // Claude Code already names each chat in plain English — reuse that
        // before falling back to cleaning up the branch.
        if let title = chatTitle, !title.isEmpty, isWorktree { return title }
        if !isWorktree { return "Main" }

        var name = branch
        for prefix in ["claude/", "feature/", "fix/", "wip/"] where name.hasPrefix(prefix) {
            name = String(name.dropFirst(prefix.count))
        }

        var words = name
            .replacingOccurrences(of: "_", with: "-")
            .split(separator: "-")
            .map(String.init)

        // Drop the random disambiguating suffix the worktree tooling appends.
        if let last = words.last, last.count >= 4,
           last.allSatisfy({ $0.isHexDigit || $0.isNumber }) {
            words.removeLast()
        }
        guard !words.isEmpty else { return branch }

        return words
            .map { $0.count <= 2 ? $0.uppercased() : $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    /// ~/.claude/worktree-labels.json — { "<checkout path>": "Human Name" }.
    /// Lives outside the repo so naming a worktree never shows up in git status.
    private static func storedLabel(for root: String) -> String? {
        let url = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".claude/worktree-labels.json")
        guard let data = try? Data(contentsOf: url),
              let map = try? JSONSerialization.jsonObject(with: data) as? [String: String]
        else { return nil }
        return map[root] ?? map[(root as NSString).resolvingSymlinksInPath]
    }

    // MARK: - Claude Code session

    /// The Claude Code chat working in this checkout.
    ///
    /// Claude Code's desktop app keeps one JSON per chat under
    /// ~/Library/Application Support/Claude/claude-code-sessions/<org>/<user>/,
    /// carrying its cwd, title, cliSessionId and archived flag. The newest
    /// unarchived chat for this checkout wins; an archived one is still worth
    /// reporting, but only a live one can be focused.
    private static func claudeChat(forCheckout root: String)
        -> (title: String?, desktopSessionID: String?, cliSessionID: String?) {

        let fm = FileManager.default
        let home = URL(fileURLWithPath: NSHomeDirectory())
        let store = home.appendingPathComponent(
            "Library/Application Support/Claude/claude-code-sessions")

        var best: (title: String?, desktop: String?, cli: String?, activity: Double)?

        if let walker = fm.enumerator(at: store,
                                      includingPropertiesForKeys: nil,
                                      options: [.skipsHiddenFiles]) {
            for case let url as URL in walker where url.pathExtension == "json" {
                guard let data = try? Data(contentsOf: url),
                      let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let cwd = obj["cwd"] as? String, cwd == root
                else { continue }

                let archived = (obj["isArchived"] as? Bool) ?? false
                let activity = (obj["lastActivityAt"] as? Double) ?? 0
                // Live chats outrank archived ones; newest activity breaks ties.
                let rank = archived ? activity : activity + 1e15
                if let current = best, current.activity >= rank { continue }
                best = (obj["title"] as? String,
                        obj["sessionId"] as? String,
                        obj["cliSessionId"] as? String,
                        rank)
            }
        }

        if let best = best { return (best.title, best.desktop, best.cli) }

        // No desktop chat on record — fall back to the newest CLI transcript
        // for this directory, which claude://resume can still open. The store
        // path is the checkout path with every non-alphanumeric character
        // replaced by a dash.
        let encoded = String(root.map { $0.isLetter || $0.isNumber ? $0 : "-" })
        let dir = home.appendingPathComponent(".claude/projects/\(encoded)")
        let newest = (try? fm.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.contentModificationDateKey]
        ))?
            .filter { $0.pathExtension == "jsonl" }
            .max { a, b in
                let da = (try? a.resourceValues(forKeys: [.contentModificationDateKey])
                    .contentModificationDate) ?? .distantPast
                let db = (try? b.resourceValues(forKeys: [.contentModificationDateKey])
                    .contentModificationDate) ?? .distantPast
                return da < db
            }
        return (nil, nil, newest?.deletingPathExtension().lastPathComponent)
    }

    private static func newestChange(under root: String) -> Date? {
        let fm = FileManager.default
        let rootURL = URL(fileURLWithPath: root)
        var newest: Date?

        func consider(_ url: URL) {
            guard let date = try? url.resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate else { return }
            if newest == nil || date > newest! { newest = date }
        }

        for relative in watched {
            let url = rootURL.appendingPathComponent(relative)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { continue }
            if isDir.boolValue {
                guard let walker = fm.enumerator(
                    at: url,
                    includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
                    options: [.skipsHiddenFiles, .skipsPackageDescendants]
                ) else { continue }
                for case let child as URL in walker {
                    if (try? child.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
                        consider(child)
                    }
                }
            } else {
                consider(url)
            }
        }
        return newest
    }

    // MARK: - Formatting

    /// Compact relative age: "just now", "6m ago", "3h ago", "2d ago".
    private static func relative(_ date: Date?) -> String {
        guard let date = date else { return "unknown" }
        let seconds = Int(Date().timeIntervalSince(date))
        switch seconds {
        case ..<0:      return "just now"   // clock skew / file from the future
        case ..<60:     return "just now"
        case ..<3600:   return "\(seconds / 60)m ago"
        case ..<86_400: return "\(seconds / 3600)h ago"
        default:        return "\(seconds / 86_400)d ago"
        }
    }


    /// A menu-bar item renders its SUBMENU's title, not its own — set both or
    /// the bar just says "Version".
    private func applyTitle(_ title: String) {
        menuItem.title = title
        menu.title = title
    }

    /// Shown in full — the whole point is knowing which version this is at a
    /// glance, so the name is never truncated.
    private func titleText() -> String {
        let marker = info.isWorktree ? "⎇" : "●"
        return "\(marker) \(info.label) · \(Self.relative(info.lastChange))"
    }

    // MARK: - Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        applyTitle(titleText())
        rebuildItems()
    }

    /// Built eagerly on every refresh, not only when the menu opens — a menu
    /// that is empty until clicked reads as broken and hides its contents from
    /// anything inspecting the app's state.
    private func rebuildItems() {
        let menu = self.menu
        menu.removeAllItems()

        addRow("\(info.label)  —  \(info.isWorktree ? "worktree" : "main checkout")", to: menu)
        addRow("Branch:  \(info.branch)", to: menu)
        addRow("Path:  \(abbreviatedRoot())", to: menu)

        menu.addItem(.separator())

        addRow("Code changed:  \(Self.relative(info.lastChange))", to: menu)

        let exe = Bundle.main.executableURL
        let built = try? exe?.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        let builtDate = built ?? nil

        // Swift only reaches the app through a build — flag a binary that predates
        // the branch's native code rather than let it read as "the current version".
        if let change = info.lastChange, let builtDate = builtDate,
           swiftChangedAfter(builtDate), change > builtDate {
            menu.addItem(.separator())
            let warn = NSMenuItem(title: "⚠︎  Native code is newer than this build — run build.sh",
                                  action: nil, keyEquivalent: "")
            warn.isEnabled = false
            menu.addItem(warn)
        }

        menu.addItem(.separator())

        let chat = NSMenuItem(title: "Open in Claude Code",
                              action: #selector(openClaudeChat), keyEquivalent: "")
        chat.target = self
        chat.isEnabled = info.desktopSessionID != nil || info.cliSessionID != nil
        menu.addItem(chat)

        let reveal = NSMenuItem(title: "Reveal Checkout in Finder",
                                action: #selector(revealCheckout), keyEquivalent: "")
        reveal.target = self
        menu.addItem(reveal)

        let copyItem = NSMenuItem(title: "Copy Checkout Path",
                                  action: #selector(copyPath), keyEquivalent: "")
        copyItem.target = self
        menu.addItem(copyItem)
    }

    private func swiftChangedAfter(_ date: Date) -> Bool {
        let sources = URL(fileURLWithPath: projectRoot)
            .appendingPathComponent("desktop/SpotifyDashboard")
        guard let walker = FileManager.default.enumerator(
            at: sources,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return false }
        for case let url as URL in walker where url.pathExtension == "swift" {
            if let m = try? url.resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate, m > date {
                return true
            }
        }
        return false
    }

    private func abbreviatedRoot() -> String {
        let home = NSHomeDirectory()
        return projectRoot.hasPrefix(home)
            ? "~" + projectRoot.dropFirst(home.count)
            : projectRoot
    }

    /// Informational rows: visible, monospaced-ish, never clickable.
    private func addRow(_ title: String, to menu: NSMenu) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        menu.addItem(item)
    }

    /// Open this checkout's chat in Claude Code.
    ///
    /// `claude://claude.ai/epitaxy/local_<id>` navigates the desktop app to that
    /// exact chat (verified 08-15-26 — the host must be `claude.ai`; `epitaxy`
    /// is the Code surface's internal route, and hosts like `claude://epitaxy/…`
    /// or `claude://local_sessions/…` are never dispatched).
    ///
    /// `claude://resume?session=<cli id>` is the fallback and only that: it
    /// IMPORTS a transcript, so on a chat the app already holds it spawns a
    /// second untitled copy ("General coding session").
    @objc private func openClaudeChat() {
        if let id = info.desktopSessionID,
           let url = URL(string: "claude://claude.ai/epitaxy/\(id)") {
            NSWorkspace.shared.open(url)
            return
        }
        guard let id = info.cliSessionID,
              let url = URL(string: "claude://resume?session=\(id)") else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func revealCheckout() {
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: projectRoot)
    }

    @objc private func copyPath() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(projectRoot, forType: .string)
    }
}
