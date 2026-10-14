import Foundation

/// Claude subscription limits (Pro / Max) via the OAuth session Claude Code stores.
/// Unofficial endpoint: the same one Claude Code's `/usage` screen reads.
enum ClaudeUsageClient {
    private static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    static let keychainService = "Claude Code-credentials"
    static let credentialsPath = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude")
        .appendingPathComponent(".credentials.json")

    /// Claude Code's own OAuth token endpoint and client, so a refresh from Catel
    /// is indistinguishable from one by another `claude` process.
    private static let tokenEndpoint = URL(string: "https://platform.claude.com/v1/oauth/token")!
    private static let oauthClientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"

    private static let signInHint = "Open Claude Code and sign in (`claude`, then /login)"
    /// Shown only once a refresh has been tried and rejected.
    private static let reauthHint = "Claude sign-in expired: run `claude`, then /login"
    private static let refreshCooldown: TimeInterval = 300
    private static let securityTimeout: TimeInterval = 10
    private static let refreshLock = NSLock()
    private static var lastRefreshAttempt = Date.distantPast

    /// The endpoint rate-limits hard (HTTP 429 with polling every 60s), so Claude
    /// is fetched at most every `minimumInterval`; in between, and while backing
    /// off after a 429, the last good result is replayed.
    private static let minimumInterval: TimeInterval = 180
    /// Non-429 failures (network blip, expired token) retry sooner than that.
    private static let failureRetryInterval: TimeInterval = 30
    /// Upper bound on a 429 back-off, so a huge `Retry-After` can't park Claude for hours.
    private static let maximumBackOff: TimeInterval = 900
    private static let rateLimitedMessage = "Claude rate-limited, retrying shortly"
    private static let queue = DispatchQueue(label: "catel.claude-usage", qos: .utility)
    private static var nextFetchAllowed = Date.distantPast
    private static var lastSuccess: ClaudeUsage?
    /// What the most recent attempt actually returned, replayed while throttled so
    /// the popover never claims a rate limit that didn't happen.
    private static var lastResult: Result<ClaudeUsage, UsageClientError>?

    static func fetch(completion: @escaping (Result<ClaudeUsage, UsageClientError>) -> Void) {
        // Serial queue: guards the throttle state, and keeps the `security`
        // Keychain read off the main thread.
        queue.async {
            guard Date() >= nextFetchAllowed else {
                completion(lastSuccess.map { .success($0) }
                    ?? lastResult
                    ?? .failure(.unavailable(rateLimitedMessage)))
                return
            }
            nextFetchAllowed = Date().addingTimeInterval(minimumInterval)

            fetchNow { result in
                queue.async {
                    lastResult = result
                    switch result {
                    case .success(let usage):
                        lastSuccess = usage
                        completion(result)
                    case .failure(.unavailable(rateLimitedMessage)):
                        completion(lastSuccess.map { .success($0) } ?? result)
                    case .failure:
                        nextFetchAllowed = min(nextFetchAllowed, Date().addingTimeInterval(failureRetryInterval))
                        completion(result)
                    }
                }
            }
        }
    }

    /// Pushes the next attempt out after a 429 (honours `Retry-After` when larger).
    private static func backOff(_ response: HTTPURLResponse) {
        let retryAfter = (response.value(forHTTPHeaderField: "Retry-After")).flatMap(Double.init) ?? 0
        let delay = min(max(retryAfter, minimumInterval * 2), maximumBackOff)
        queue.async {
            nextFetchAllowed = Date().addingTimeInterval(delay)
        }
    }

    private static func fetchNow(completion: @escaping (Result<ClaudeUsage, UsageClientError>) -> Void) {
        let credentials: Credentials
        do {
            credentials = try readCredentials()
        } catch let error as UsageClientError {
            completion(.failure(error))
            return
        } catch {
            completion(.failure(.invalidResponse))
            return
        }

        guard credentials.isExpired else {
            requestUsage(credentials, mayRefresh: true, completion: completion)
            return
        }
        refresh(credentials) { result in
            switch result {
            case .success(let fresh):
                requestUsage(fresh, mayRefresh: false, completion: completion)
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    private static func requestUsage(
        _ credentials: Credentials,
        mayRefresh: Bool,
        completion: @escaping (Result<ClaudeUsage, UsageClientError>) -> Void
    ) {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("catel/widget", forHTTPHeaderField: "User-Agent")

        URLSession.shared.dataTask(with: request) { data, response, error in
            if error != nil {
                completion(.failure(.network))
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                completion(.failure(.invalidResponse))
                return
            }

            if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                // Revoked before `expiresAt` (e.g. signed in elsewhere): one refresh, then give up.
                guard mayRefresh else {
                    completion(.failure(.unavailable(reauthHint)))
                    return
                }
                refresh(credentials) { result in
                    switch result {
                    case .success(let fresh):
                        requestUsage(fresh, mayRefresh: false, completion: completion)
                    case .failure(let error):
                        completion(.failure(error))
                    }
                }
                return
            }

            if httpResponse.statusCode == 429 {
                backOff(httpResponse)
                completion(.failure(.unavailable(rateLimitedMessage)))
                return
            }

            guard (200..<300).contains(httpResponse.statusCode), let data else {
                completion(.failure(.unavailable("Claude usage unavailable")))
                return
            }

            do {
                completion(.success(try parseUsage(data, planName: credentials.planName)))
            } catch {
                completion(.failure(.invalidResponse))
            }
        }.resume()
    }

    // MARK: - Token refresh

    /// Renews an expired session the same way another `claude` process would:
    /// exchange the refresh token, then write the result back to wherever Claude
    /// Code keeps it, so Claude Code picks up the rotated refresh token instead of
    /// holding a dead one. Write-back only happens while the stored refresh token
    /// is still the one Catel used, so a concurrent Claude Code refresh always wins.
    private static func refresh(
        _ stale: Credentials,
        completion: @escaping (Result<Credentials, UsageClientError>) -> Void
    ) {
        guard let refreshToken = stale.refreshToken, beginRefreshAttempt() else {
            completion(.failure(.unavailable(reauthHint)))
            return
        }

        var body: [String: Any] = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": oauthClientID,
        ]
        if !stale.scopes.isEmpty {
            body["scope"] = stale.scopes.joined(separator: " ")
        }

        var request = URLRequest(url: tokenEndpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("catel/widget", forHTTPHeaderField: "User-Agent")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: request) { data, response, error in
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard
                error == nil,
                (200..<300).contains(status),
                let data,
                let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let accessToken = stringValue(json["access_token"]),
                let expiresIn = numericValue(json["expires_in"])
            else {
                // Claude Code may have refreshed in the meantime (making ours a
                // reused refresh token); its fresh token is just as good.
                if let current = try? readCredentials(),
                   current.accessToken != stale.accessToken,
                   !current.isExpired {
                    completion(.success(current))
                } else {
                    completion(.failure(error != nil ? .network : .unavailable(reauthHint)))
                }
                return
            }

            var fresh = stale
            fresh.accessToken = accessToken
            fresh.refreshToken = stringValue(json["refresh_token"]) ?? refreshToken
            fresh.expiresAt = Date().addingTimeInterval(expiresIn)
            persist(fresh, replacing: refreshToken)
            completion(.success(fresh))
        }.resume()
    }

    /// At most one refresh per `refreshCooldown`, so a dead refresh token isn't
    /// replayed against the token endpoint on every 30s retry.
    private static func beginRefreshAttempt() -> Bool {
        refreshLock.lock()
        defer { refreshLock.unlock() }
        guard Date().timeIntervalSince(lastRefreshAttempt) >= refreshCooldown else { return false }
        lastRefreshAttempt = Date()
        return true
    }

    private static func persist(_ fresh: Credentials, replacing oldRefreshToken: String) {
        if let data = keychainCredentials(),
           let updated = updatedCredentialsJSON(data, with: fresh, replacing: oldRefreshToken),
           let account = keychainAccount(),
           !account.contains("\"") {
            // Same command Claude Code uses: hex payload over stdin, never in argv.
            let hex = updated.map { String(format: "%02x", $0) }.joined()
            _ = runSecurityProcess(
                ["-i"],
                input: "add-generic-password -U -a \"\(account)\" -s \"\(keychainService)\" -X \"\(hex)\"\n"
            )
        }

        if let data = try? Data(contentsOf: credentialsPath),
           let updated = updatedCredentialsJSON(data, with: fresh, replacing: oldRefreshToken) {
            try? updated.write(to: credentialsPath, options: [.atomic])
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: credentialsPath.path)
        }
    }

    /// Patches only the token fields, keeping everything else Claude Code stored.
    /// Nil when the stored refresh token is no longer the one Catel rotated.
    static func updatedCredentialsJSON(_ data: Data, with fresh: Credentials, replacing oldRefreshToken: String) -> Data? {
        guard
            var root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            var oauth = root["claudeAiOauth"] as? [String: Any],
            stringValue(oauth["refreshToken"]) == oldRefreshToken
        else {
            return nil
        }

        oauth["accessToken"] = fresh.accessToken
        oauth["refreshToken"] = fresh.refreshToken
        if let expiresAt = fresh.expiresAt {
            oauth["expiresAt"] = Int64(expiresAt.timeIntervalSince1970 * 1000)
        }
        root["claudeAiOauth"] = oauth
        return try? JSONSerialization.data(withJSONObject: root, options: [.withoutEscapingSlashes])
    }

    // MARK: - Credentials

    struct Credentials {
        var accessToken: String
        var refreshToken: String?
        var expiresAt: Date?
        var scopes: [String]
        var planName: String?

        /// A minute of slack so a token doesn't expire between check and request.
        var isExpired: Bool {
            expiresAt.map { $0 < Date().addingTimeInterval(60) } ?? false
        }
    }

    /// Claude Code keeps its OAuth session in the login Keychain on macOS
    /// (`~/.claude/.credentials.json` on older installs).
    private static func readCredentials() throws -> Credentials {
        guard let data = keychainCredentials() ?? (try? Data(contentsOf: credentialsPath)) else {
            throw UsageClientError.missingCredentials(signInHint)
        }
        guard let credentials = parseCredentials(data) else {
            throw UsageClientError.missingCredentials(signInHint)
        }
        return credentials
    }

    static func parseCredentials(_ data: Data) -> Credentials? {
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let oauth = root["claudeAiOauth"] as? [String: Any],
            let accessToken = stringValue(oauth["accessToken"])
        else {
            return nil
        }

        return Credentials(
            accessToken: accessToken,
            refreshToken: stringValue(oauth["refreshToken"]),
            expiresAt: dateValue(oauth["expiresAt"]),
            scopes: (oauth["scopes"] as? [String]) ?? [],
            planName: stringValue(oauth["subscriptionType"])
        )
    }

    /// `security` is already on the Keychain item's access list (Claude Code
    /// writes it that way), so reading through it avoids an extra prompt.
    private static func keychainCredentials() -> Data? {
        runSecurity(["find-generic-password", "-s", keychainService, "-w"])
    }

    /// Existence check only — no `-w`, so the secret is never read.
    static func keychainItemExists() -> Bool {
        runSecurity(["find-generic-password", "-s", keychainService]) != nil
    }

    /// The item's account attribute, needed to update it in place with `-U`.
    private static func keychainAccount() -> String? {
        guard
            let data = runSecurity(["find-generic-password", "-s", keychainService]),
            let text = String(data: data, encoding: .utf8),
            let line = text.split(separator: "\n").first(where: { $0.contains("\"acct\"<blob>=\"") }),
            let start = line.range(of: "<blob>=\"")?.upperBound,
            let end = line.lastIndex(of: "\""),
            start < end
        else {
            return nil
        }
        return String(line[start..<end])
    }

    private static func runSecurity(_ arguments: [String]) -> Data? {
        guard let result = runSecurityProcess(arguments), result.status == 0, !result.output.isEmpty else {
            return nil
        }
        return result.output
    }

    private static func runSecurityProcess(_ arguments: [String], input: String? = nil) -> (status: Int32, output: Data)? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = arguments
        let output = Pipe()
        let stdin = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.standardInput = input == nil ? FileHandle.nullDevice : stdin

        do {
            try process.run()
        } catch {
            return nil
        }
        if let input {
            stdin.fileHandleForWriting.write(Data(input.utf8))
            try? stdin.fileHandleForWriting.close()
        }

        // A Keychain prompt nobody answers would otherwise block the serial
        // Claude queue forever, and with it every later refresh.
        let watchdog = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + securityTimeout, execute: watchdog)
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        watchdog.cancel()

        return (process.terminationStatus, data)
    }

    static func parseUsage(_ data: Data, planName: String?) throws -> ClaudeUsage {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw UsageClientError.invalidResponse
        }

        let fiveHour = parseWindow(root["five_hour"], seconds: 5 * 3_600)
        let weekly = parseWindow(root["seven_day"], seconds: 7 * 86_400)

        guard fiveHour != nil || weekly != nil else {
            throw UsageClientError.invalidResponse
        }

        return ClaudeUsage(planName: planName, fiveHourWindow: fiveHour, weeklyWindow: weekly)
    }

    /// `utilization` is already a 0–100 percentage.
    private static func parseWindow(_ value: Any?, seconds: Double) -> UsageWindow? {
        guard let window = value as? [String: Any] else { return nil }
        guard let utilization = numericValue(window["utilization"]) else { return nil }

        return UsageWindow(
            usedPercent: utilization,
            resetAt: dateValue(window["resets_at"]),
            windowSeconds: seconds
        )
    }
}
