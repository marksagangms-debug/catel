import Foundation

struct DeepSeekUsage: Equatable {
    let currency: String
    let totalBalance: Double
    let grantedBalance: Double
    let toppedUpBalance: Double
    let isAvailable: Bool
}

enum DeepSeekUsageClient {
    private static let endpoint = URL(string: "https://api.deepseek.com/user/balance")!

    static func fetch(completion: @escaping (Result<DeepSeekUsage, UsageClientError>) -> Void) {
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
                completion(.failure(.unavailable("DeepSeek balance unavailable")))
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

    /// Reads `DEEPSEEK_API_KEY` from `~/.hermes/.env`.
    /// Only reads the file; never writes it back.
    private static func readAPIKey() throws -> String {
        let envPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".hermes")
            .appendingPathComponent(".env")

        guard FileManager.default.fileExists(atPath: envPath.path) else {
            throw UsageClientError.missingCredentials("Add DEEPSEEK_API_KEY to ~/.hermes/.env")
        }

        let contents: String
        do {
            contents = try String(contentsOf: envPath, encoding: .utf8)
        } catch {
            throw UsageClientError.missingCredentials("Add DEEPSEEK_API_KEY to ~/.hermes/.env")
        }

        guard let key = parseEnvValue(named: "DEEPSEEK_API_KEY", in: contents) else {
            throw UsageClientError.missingCredentials("Add DEEPSEEK_API_KEY to ~/.hermes/.env")
        }

        return key
    }

    private static func parseEnvValue(named name: String, in contents: String) -> String? {
        for rawLine in contents.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }

            let withoutExport = line.hasPrefix("export ")
                ? String(line.dropFirst("export ".count))
                : line

            guard let separator = withoutExport.firstIndex(of: "=") else { continue }

            let key = withoutExport[..<separator].trimmingCharacters(in: .whitespaces)
            guard key == name else { continue }

            var value = String(withoutExport[withoutExport.index(after: separator)...])
                .trimmingCharacters(in: .whitespaces)

            if value.count >= 2,
               let first = value.first,
               let last = value.last,
               (first == "\"" && last == "\"") || (first == "'" && last == "'") {
                value = String(value.dropFirst().dropLast())
            }

            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }

        return nil
    }

    private static func parseUsage(_ data: Data) throws -> DeepSeekUsage {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw UsageClientError.invalidResponse
        }

        guard let infos = root["balance_infos"] as? [[String: Any]], !infos.isEmpty else {
            let available = root["is_available"] as? Bool ?? false
            throw UsageClientError.unavailable(
                available ? "No balance on this DeepSeek account" : "DeepSeek balance unavailable"
            )
        }

        let info = infos.first { ($0["currency"] as? String)?.uppercased() == "USD" } ?? infos[0]

        guard let total = numericValue(info["total_balance"]) else {
            throw UsageClientError.invalidResponse
        }

        let granted = numericValue(info["granted_balance"]) ?? 0
        let toppedUp = numericValue(info["topped_up_balance"]) ?? max(total - granted, 0)

        return DeepSeekUsage(
            currency: stringValue(info["currency"])?.uppercased() ?? "USD",
            totalBalance: total,
            grantedBalance: granted,
            toppedUpBalance: toppedUp,
            isAvailable: root["is_available"] as? Bool ?? true
        )
    }
}
