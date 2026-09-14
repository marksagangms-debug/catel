import Foundation

struct OpenCodeUsage: Equatable {
    let rolling: UsageWindow?
    let weekly: UsageWindow?
    let monthly: UsageWindow?

    /// The 5-hour rolling window drives the menu-bar value: it is the window that
    /// throttles a coding session first.
    var menuBarWindow: UsageWindow? {
        rolling ?? weekly ?? monthly
    }
}

enum OpenCodeUsageClient {
    private static let endpoint = URL(string: "https://opencode.ai/zen/go/v1/usage")!

    private static let rollingSeconds: Double = 5 * 3_600
    private static let weeklySeconds: Double = 7 * 86_400
    private static let monthlySeconds: Double = 30 * 86_400

    static func fetch(completion: @escaping (Result<OpenCodeUsage, UsageClientError>) -> Void) {
        let apiKey: String
        do {
            apiKey = try readAPIKey()
        } catch let error as UsageClientError {
            completion(.failure(error))
            return
        } catch {
            completion(.failure(.invalidResponse))
            return
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
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
                completion(.failure(.authentication))
                return
            }

            guard (200..<300).contains(httpResponse.statusCode), let data else {
                completion(.failure(.unavailable("OpenCode Go usage unavailable")))
                return
            }

            do {
                completion(.success(try parseUsage(data)))
            } catch let error as UsageClientError {
                completion(.failure(error))
            } catch {
                completion(.failure(.invalidResponse))
            }
        }.resume()
    }

    /// Reads the `opencode-go` API key from `~/.local/share/opencode/auth.json`
    /// (what `opencode providers` / `/connect` writes). Only reads the file.
    private static func readAPIKey() throws -> String {
        let authPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local")
            .appendingPathComponent("share")
            .appendingPathComponent("opencode")
            .appendingPathComponent("auth.json")

        let hint = "Connect OpenCode Go in OpenCode (`opencode providers`)"

        guard FileManager.default.fileExists(atPath: authPath.path) else {
            throw UsageClientError.missingCredentials(hint)
        }

        let data: Data
        do {
            data = try Data(contentsOf: authPath, options: [.mappedIfSafe])
        } catch {
            throw UsageClientError.missingCredentials(hint)
        }

        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let provider = root["opencode-go"] as? [String: Any],
            let key = stringValue(provider["key"])
        else {
            throw UsageClientError.missingCredentials(hint)
        }

        return key
    }

    private static func parseUsage(_ data: Data) throws -> OpenCodeUsage {
        guard
            let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let usage = root["usage"] as? [String: Any]
        else {
            throw UsageClientError.invalidResponse
        }

        let rolling = window(usage["rolling"], windowSeconds: rollingSeconds)
        let weekly = window(usage["weekly"], windowSeconds: weeklySeconds)
        let monthly = window(usage["monthly"], windowSeconds: monthlySeconds)

        guard rolling != nil || weekly != nil || monthly != nil else {
            throw UsageClientError.unavailable("OpenCode Go usage unavailable")
        }

        return OpenCodeUsage(rolling: rolling, weekly: weekly, monthly: monthly)
    }

    private static func window(_ value: Any?, windowSeconds: Double) -> UsageWindow? {
        guard
            let entry = value as? [String: Any],
            let percent = numericValue(entry["percent"])
        else {
            return nil
        }

        return UsageWindow(
            usedPercent: percent,
            resetAt: dateValue(entry["resetsAt"]),
            windowSeconds: windowSeconds
        )
    }
}