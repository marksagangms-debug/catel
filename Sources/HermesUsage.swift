import Foundation

struct HermesUsage: Equatable {
    let planName: String?
    let usedPercent: Double?
    let creditsRemaining: Double?
    let monthlyCredits: Double?
    let purchasedCreditsRemaining: Double?
    let billingCycleEnd: Date?
}

enum HermesUsageClient {
    private static let defaultPortal = URL(string: "https://portal.nousresearch.com")!
    private static let authPath = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".hermes")
        .appendingPathComponent("auth.json")

    static func fetch(completion: @escaping (Result<HermesUsage, UsageClientError>) -> Void) {
        do {
            let credentials = try readCredentials()
            let endpoint = credentials.portalBase
                .appendingPathComponent("api")
                .appendingPathComponent("oauth")
                .appendingPathComponent("account")

            var request = URLRequest(url: endpoint)
            request.httpMethod = "GET"
            request.timeoutInterval = 15
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
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
                    completion(.failure(.unavailable("Hermes usage unavailable")))
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

    private static func readCredentials() throws -> (accessToken: String, portalBase: URL) {
        guard FileManager.default.fileExists(atPath: authPath.path) else {
            throw UsageClientError.missingCredentials("Open Hermes Agent and sign in to Nous Portal")
        }

        let data: Data
        do {
            data = try Data(contentsOf: authPath, options: [.mappedIfSafe])
        } catch {
            throw UsageClientError.missingCredentials("Open Hermes Agent and sign in to Nous Portal")
        }

        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw UsageClientError.invalidResponse
        }

        let providers = root["providers"] as? [String: Any]
        let nous = providers?["nous"] as? [String: Any] ?? [:]

        let accessToken = stringValue(nous["access_token"])
            ?? stringValue(nous["accessToken"])
            ?? stringValue(nous["agent_key"])

        guard let accessToken else {
            throw UsageClientError.missingCredentials("Open Hermes Agent and sign in to Nous Portal")
        }

        if let expiresAt = dateValue(nous["expires_at"]) ?? jwtExpiry(accessToken),
           expiresAt.timeIntervalSinceNow < 15 {
            throw UsageClientError.missingCredentials(
                "Open Hermes Agent so it can refresh the Portal token"
            )
        }

        let portal = stringValue(nous["portal_base_url"])
            .flatMap(URL.init(string:))
            ?? defaultPortal

        return (accessToken, portal)
    }

    private static func jwtExpiry(_ token: String) -> Date? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }

        var payload = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = payload.count % 4
        if remainder > 0 {
            payload.append(String(repeating: "=", count: 4 - remainder))
        }

        guard
            let data = Data(base64Encoded: payload),
            let claims = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }

        return dateValue(claims["exp"])
    }

    private static func parseUsage(_ data: Data) throws -> HermesUsage {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw UsageClientError.invalidResponse
        }

        let subscription = root["subscription"] as? [String: Any] ?? [:]
        let access = root["paid_service_access"] as? [String: Any] ?? [:]

        let monthlyCredits = numericValue(subscription["monthly_credits"])
        let remaining = numericValue(subscription["credits_remaining"])
            ?? numericValue(access["subscription_credits_remaining"])
        let purchased = numericValue(subscription["purchased_credits_remaining"])
            ?? numericValue(access["purchased_credits_remaining"])
            ?? numericValue(root["purchased_credits_remaining"])

        let usedPercent: Double?
        if let monthlyCredits, monthlyCredits > 0, let remaining, remaining.isFinite, remaining <= monthlyCredits {
            let used = monthlyCredits - remaining
            usedPercent = min(max(used / monthlyCredits * 100, 0), 100)
        } else {
            usedPercent = nil
        }

        guard usedPercent != nil || remaining != nil || monthlyCredits != nil else {
            throw UsageClientError.invalidResponse
        }

        return HermesUsage(
            planName: stringValue(subscription["plan"]),
            usedPercent: usedPercent,
            creditsRemaining: remaining,
            monthlyCredits: monthlyCredits,
            purchasedCreditsRemaining: purchased,
            billingCycleEnd: dateValue(subscription["current_period_end"])
        )
    }
}
