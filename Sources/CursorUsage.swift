import Foundation

enum CursorUsageClient {
    private static let endpoint = URL(string: "https://api2.cursor.sh/aiserver.v1.DashboardService/GetCurrentPeriodUsage")!
    private static let sqlitePath = "/usr/bin/sqlite3"
    private static let databaseCandidates = [
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Cursor/User/globalStorage/state.vscdb"),
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Cursor - Insiders/User/globalStorage/state.vscdb")
    ]

    static func fetch(completion: @escaping (Result<CursorUsage, UsageClientError>) -> Void) {
        do {
            let accessToken = try readAccessToken()
            guard let userID = userID(from: accessToken) else {
                throw UsageClientError.missingCredentials("Open Cursor and sign in")
            }

            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.timeoutInterval = 15
            request.httpBody = Data("{}".utf8)
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("1", forHTTPHeaderField: "Connect-Protocol-Version")
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            request.setValue("https://cursor.com", forHTTPHeaderField: "Origin")
            request.setValue("https://cursor.com/", forHTTPHeaderField: "Referer")

            let normalizedUserID = userID.hasPrefix("auth0|")
                ? String(userID.dropFirst("auth0|".count))
                : userID
            let sessionCookie = "\(normalizedUserID)%3A%3A\(accessToken)"
            request.setValue(
                "WorkosCursorSessionToken=\(sessionCookie)",
                forHTTPHeaderField: "Cookie"
            )

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
                    completion(.failure(.authentication))
                    return
                }

                guard (200..<300).contains(httpResponse.statusCode), let data else {
                    completion(.failure(.unavailable("Cursor usage unavailable")))
                    return
                }

                do {
                    completion(.success(try parseUsage(data)))
                } catch {
                    completion(.failure(.invalidResponse))
                }
            }.resume()
        } catch let error as UsageClientError {
            completion(.failure(error))
        } catch {
            completion(.failure(.invalidResponse))
        }
    }

    private static func readAccessToken() throws -> String {
        guard FileManager.default.fileExists(atPath: sqlitePath) else {
            throw UsageClientError.unavailable("SQLite is unavailable")
        }

        for databaseURL in databaseCandidates {
            guard FileManager.default.fileExists(atPath: databaseURL.path) else { continue }

            if let token = try? readAccessToken(from: databaseURL), !token.isEmpty {
                return token
            }
        }

        throw UsageClientError.missingCredentials("Open Cursor and sign in")
    }

    private static func readAccessToken(from databaseURL: URL) throws -> String {
        let outputPipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: sqlitePath)
        process.arguments = [
            "-readonly",
            "-batch",
            "-noheader",
            "file:\(databaseURL.path)?mode=ro&immutable=1",
            "SELECT value FROM ItemTable WHERE key = 'cursorAuth/accessToken' LIMIT 1;"
        ]
        process.standardOutput = outputPipe
        process.standardError = FileHandle.nullDevice

        try process.run()
        let output = outputPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw UsageClientError.invalidResponse
        }

        var token = String(data: output, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if token.first == "\"", let decoded = try? JSONSerialization.jsonObject(
            with: Data(token.utf8)
        ) as? String {
            token = decoded
        }

        guard !token.isEmpty else {
            throw UsageClientError.missingCredentials("Open Cursor and sign in")
        }

        return token
    }

    private static func userID(from token: String) -> String? {
        let segments = token.split(separator: ".")
        guard segments.count == 3 else { return nil }

        var payload = String(segments[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)

        guard
            let data = Data(base64Encoded: payload),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }

        return stringValue(object["sub"])
    }

    private static func parseUsage(_ data: Data) throws -> CursorUsage {
        guard
            let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let planUsage = (root["planUsage"] ?? root["plan_usage"]) as? [String: Any]
        else {
            throw UsageClientError.invalidResponse
        }

        let totalSpendCents = numericValue(planUsage["totalSpend"] ?? planUsage["total_spend"])
        let includedSpendCents = numericValue(
            planUsage["includedSpend"] ?? planUsage["included_spend"]
        )
        let limitCents = numericValue(planUsage["limit"]) ?? 0
        let usedCents = totalSpendCents ?? includedSpendCents ?? 0

        let directPercent = numericValue(
            planUsage["totalPercentUsed"] ?? planUsage["total_percent_used"]
        )
        let cursorModelsPercent = numericValue(
            planUsage["autoPercentUsed"] ?? planUsage["auto_percent_used"]
        )
        let otherModelsPercent = numericValue(
            planUsage["apiPercentUsed"] ?? planUsage["api_percent_used"]
        )
        let computedPercent = limitCents > 0 ? usedCents / limitCents * 100 : nil
        guard
            cursorModelsPercent != nil
                || otherModelsPercent != nil
                || directPercent != nil
                || computedPercent != nil
        else {
            throw UsageClientError.invalidResponse
        }

        let planInfo = (root["planInfo"] ?? root["plan_info"]) as? [String: Any]
        let planName = stringValue(root["planName"] ?? root["plan_name"])
            ?? stringValue(planInfo?["planName"] ?? planInfo?["plan_name"])
            ?? stringValue(root["membershipType"] ?? root["membership_type"])

        return CursorUsage(
            planName: planName,
            usedDollars: usedCents / 100,
            limitDollars: limitCents / 100,
            cursorModelsPercentUsed: cursorModelsPercent.map { min(max($0, 0), 100) },
            otherModelsPercentUsed: otherModelsPercent.map { min(max($0, 0), 100) },
            percentUsed: min(max(otherModelsPercent ?? directPercent ?? computedPercent ?? 0, 0), 100),
            billingCycleEnd: dateValue(
                root["billingCycleEnd"]
                    ?? root["billing_cycle_end"]
                    ?? planInfo?["billingCycleEnd"]
                    ?? planInfo?["billing_cycle_end"]
            )
        )
    }
}
