import Foundation

enum ServiceKind: String, CaseIterable {
    case claude
    case codex

    var displayName: String {
        switch self {
        case .claude: return "Claude"
        case .codex: return "Codex"
        }
    }

    var glyph: String {
        switch self {
        case .claude: return "✳"
        case .codex: return "⌘"
        }
    }

    var cliName: String {
        switch self {
        case .claude: return "claude"
        case .codex: return "codex"
        }
    }
}

struct Window {
    var usedPercent: Double
    /// Nil if the API didn't include a (parseable) reset time for this window.
    var resetsAt: Date?

    var remainingPercent: Double { max(0, min(100, 100 - usedPercent)) }
}

struct UsageSnapshot {
    /// Either window can be absent: the usage API returns `null` blocks in some
    /// states (e.g. a window that's momentarily exhausted), so we keep whatever
    /// is present instead of treating the whole response as a failure.
    var fiveHour: Window?
    var weekly: Window?
    var fetchedAt: Date

    /// The window shown in the menu bar — the 5-hour window normally, falling
    /// back to the weekly window when the 5-hour block isn't present.
    var primary: Window? { fiveHour ?? weekly }
    var primaryIsWeekly: Bool { fiveHour == nil && weekly != nil }
}

enum ServiceState {
    case loading
    case ok(UsageSnapshot)
    case error(String)
    /// The CLI isn't installed / never logged in on this machine — hide the
    /// service rather than showing an error.
    case notConfigured

    var isConfigured: Bool {
        if case .notConfigured = self { return false }
        return true
    }
}

enum FetchError: LocalizedError {
    case noCredentials(String)
    case unauthorized(ServiceKind)
    case http(Int)
    case badResponse(String)

    var errorDescription: String? {
        switch self {
        case .noCredentials(let detail):
            return detail
        case .unauthorized(let kind):
            return "Token expired — open `\(kind.cliName)` to refresh it"
        case .http(let code):
            return "HTTP \(code) from usage endpoint"
        case .badResponse(let detail):
            return "Unexpected response: \(detail)"
        }
    }
}

private func getJSON(url: URL, headers: [String: String]) async throws -> [String: Any] {
    var req = URLRequest(url: url, timeoutInterval: 20)
    for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
    let (data, resp) = try await URLSession.shared.data(for: req)
    guard let http = resp as? HTTPURLResponse else { throw FetchError.badResponse("not HTTP") }
    guard http.statusCode != 401, http.statusCode != 403 else { throw FetchError.http(http.statusCode) }
    guard (200..<300).contains(http.statusCode) else { throw FetchError.http(http.statusCode) }
    guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw FetchError.badResponse(String(data: data.prefix(120), encoding: .utf8) ?? "non-JSON")
    }
    return obj
}

enum ClaudeUsage {
    /// Claude Code stores its OAuth credentials in the login keychain.
    private static func token() throws -> String {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        proc.arguments = ["find-generic-password", "-s", "Claude Code-credentials", "-w"]
        let out = Pipe()
        proc.standardOutput = out
        proc.standardError = Pipe()
        try proc.run()
        proc.waitUntilExit()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        guard proc.terminationStatus == 0,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = obj["claudeAiOauth"] as? [String: Any],
              let tok = oauth["accessToken"] as? String, !tok.isEmpty
        else {
            throw FetchError.noCredentials("No Claude Code login found — run `claude` and sign in")
        }
        return tok
    }

    static func fetch() async throws -> UsageSnapshot {
        let tok = try token()
        let json: [String: Any]
        do {
            json = try await getJSON(
                url: URL(string: "https://api.anthropic.com/api/oauth/usage")!,
                headers: [
                    "Authorization": "Bearer \(tok)",
                    "anthropic-beta": "oauth-2025-04-20",
                ]
            )
        } catch FetchError.http(401), FetchError.http(403) {
            throw FetchError.unauthorized(.claude)
        }

        func window(_ key: String) -> Window? {
            // A window block can be null/absent; a reset time can be missing.
            // Only the utilization number is required to make a window usable.
            guard let blk = json[key] as? [String: Any],
                  let pct = blk["utilization"] as? Double
            else { return nil }
            let date = (blk["resets_at"] as? String).flatMap(parseISO)
            return Window(usedPercent: pct, resetsAt: date)
        }

        let five = window("five_hour")
        let weekly = window("seven_day")
        guard five != nil || weekly != nil else {
            throw FetchError.badResponse("no usage windows in response")
        }
        return UsageSnapshot(fiveHour: five, weekly: weekly, fetchedAt: Date())
    }

    private static func parseISO(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }
}

enum CodexUsage {
    /// Codex CLI stores its OAuth credentials in ~/.codex/auth.json.
    private static func credentials() throws -> (token: String, accountID: String?) {
        let path = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/auth.json")
        guard let data = try? Data(contentsOf: path),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tokens = obj["tokens"] as? [String: Any],
              let tok = tokens["access_token"] as? String, !tok.isEmpty
        else {
            throw FetchError.noCredentials("No Codex login found — run `codex` and sign in")
        }
        return (tok, tokens["account_id"] as? String)
    }

    static func fetch() async throws -> UsageSnapshot {
        let creds = try credentials()
        var headers = [
            "Authorization": "Bearer \(creds.token)",
            "Accept": "application/json",
            // The ChatGPT backend rejects unrecognized user agents with 403.
            "User-Agent": "codex_cli_rs/0.130.0",
        ]
        if let acct = creds.accountID { headers["chatgpt-account-id"] = acct }

        let json: [String: Any]
        do {
            json = try await getJSON(
                url: URL(string: "https://chatgpt.com/backend-api/codex/usage")!,
                headers: headers
            )
        } catch FetchError.http(401), FetchError.http(403) {
            throw FetchError.unauthorized(.codex)
        }

        guard let rateLimit = json["rate_limit"] as? [String: Any] else {
            throw FetchError.badResponse("missing rate_limit block")
        }
        func window(_ key: String) -> Window? {
            guard let blk = rateLimit[key] as? [String: Any],
                  let pct = blk["used_percent"] as? Double
            else { return nil }
            let date = (blk["reset_at"] as? Double).map { Date(timeIntervalSince1970: $0) }
            return Window(usedPercent: pct, resetsAt: date)
        }

        let five = window("primary_window")
        let weekly = window("secondary_window")
        guard five != nil || weekly != nil else {
            throw FetchError.badResponse("no usage windows in response")
        }
        return UsageSnapshot(fiveHour: five, weekly: weekly, fetchedAt: Date())
    }
}

func fetchUsage(for kind: ServiceKind) async -> ServiceState {
    do {
        switch kind {
        case .claude: return .ok(try await ClaudeUsage.fetch())
        case .codex: return .ok(try await CodexUsage.fetch())
        }
    } catch FetchError.noCredentials {
        return .notConfigured
    } catch {
        return .error(error.localizedDescription)
    }
}
