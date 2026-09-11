import Foundation

enum ChatGPTUsageClient {
    private static let endpoint = URL(string: "https://chatgpt.com/backend-api/wham/usage")!
    private static let authPath = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".codex")
        .appendingPathComponent("auth.json")

    static func fetch(completion: @escaping (Result<ChatGPTUsage, UsageClientError>) -> Void) {
        do {
            let credentials = try readCredentials()
            var request = URLRequest(url: endpoint)
            request.httpMethod = "GET"
            request.timeoutInterval = 15
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
            request.setValue("codex_cli_rs/widget", forHTTPHeaderField: "User-Agent")

            if let accountID = credentials.accountID {
                request.setValue(accountID, forHTTPHeaderField: "ChatGPT-Account-Id")
            }

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
                    completion(.failure(.unavailable("ChatGPT usage unavailable")))
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

    private static func readCredentials() throws -> (accessToken: String, accountID: String?) {
        guard FileManager.default.fileExists(atPath: authPath.path) else {
            throw UsageClientError.missingCredentials("Open ChatGPT or Codex and sign in")
        }

        let data: Data
        do {
            data = try Data(contentsOf: authPath, options: [.mappedIfSafe])
        } catch {
            throw UsageClientError.missingCredentials("Open ChatGPT or Codex and sign in")
        }

        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw UsageClientError.invalidResponse
        }

        let tokens = root["tokens"] as? [String: Any]
        let accessToken = stringValue(tokens?["access_token"])
            ?? stringValue(tokens?["accessToken"])
            ?? stringValue(root["access_token"])
            ?? stringValue(root["accessToken"])

        guard let accessToken else {
            throw UsageClientError.missingCredentials("Open ChatGPT or Codex and sign in")
        }

        let accountID = stringValue(tokens?["account_id"])
            ?? stringValue(tokens?["accountId"])
            ?? stringValue(root["account_id"])
            ?? stringValue(root["accountId"])

        return (accessToken, accountID)
    }

    private static func parseUsage(_ data: Data) throws -> ChatGPTUsage {
        guard
            let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let rateLimit = root["rate_limit"] as? [String: Any]
        else {
            throw UsageClientError.invalidResponse
        }

        let primary = parseWindow(rateLimit["primary_window"])
        let secondary = parseWindow(rateLimit["secondary_window"])

        guard primary != nil || secondary != nil else {
            throw UsageClientError.invalidResponse
        }

        return ChatGPTUsage(
            planName: stringValue(root["plan_type"]),
            primaryWindow: primary,
            secondaryWindow: secondary
        )
    }

    private static func parseWindow(_ value: Any?) -> UsageWindow? {
        guard let window = value as? [String: Any] else { return nil }
        guard let usedPercent = numericValue(window["used_percent"]) else { return nil }

        return UsageWindow(
            usedPercent: usedPercent,
            resetAt: dateValue(window["reset_at"]),
            windowSeconds: numericValue(window["limit_window_seconds"])
        )
    }
}
