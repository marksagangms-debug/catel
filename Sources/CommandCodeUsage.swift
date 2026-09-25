import Foundation

struct CommandCodeUsage: Equatable {
    let planName: String?
    let fiveHour: UsageWindow?
    let weekly: UsageWindow?
    /// Percent of the plan's monthly credits consumed; `resetAt` is the billing
    /// period end (CommandCode has no monthly rolling window, only a pool).
    let monthly: UsageWindow?

    /// The 5-hour cap throttles a coding session first, so it drives the menu bar
    /// (same rule as OpenCode Go).
    var menuBarWindow: UsageWindow? {
        fiveHour ?? weekly ?? monthly
    }
}

enum CommandCodeUsageClient {
    private static let creditsEndpoint = URL(string: "https://api.commandcode.ai/alpha/billing/credits")!
    private static let subscriptionEndpoint = URL(string: "https://api.commandcode.ai/alpha/billing/subscriptions")!

    private static let fiveHourSeconds: Double = 5 * 3_600
    private static let weeklySeconds: Double = 7 * 86_400

    /// Plan catalog mirrored from the CommandCode CLI (`individual-*` / `teams-pro`
    /// prefixes, longest match wins). A plan unknown to this table still renders:
    /// the monthly pool then falls back to the remaining-credits values alone.
    private static let planCatalog: [(prefix: String, name: String, credits: Double)] = [
        ("individual-ultra", "Ultra", 300),
        ("individual-provider", "Provider", 15),
        ("individual-goat", "GOAT", 70),
        ("individual-max", "Max", 150),
        ("individual-pro-v1", "Pro", 80),
        ("teams-pro", "Teams Pro", 40),
        ("individual-go", "Go", 10),
        ("individual-pro", "Pro", 30),
    ]

    static func fetch(completion: @escaping (Result<CommandCodeUsage, UsageClientError>) -> Void) {
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

        // Two parallel GETs with the same key (the CLI's /usage does the same).
        // The card needs `credits` for the windows and `subscriptions` for the
        // plan name + pool size; a subscription failure degrades to actuals only.
        var creditsResult: Result<[String: Any], UsageClientError>?
        var subscriptionResult: Result<[String: Any], UsageClientError>?
        let group = DispatchGroup()

        group.enter()
        getJSON(creditsEndpoint, apiKey: apiKey) { creditsResult = $0; group.leave() }

        group.enter()
        getJSON(subscriptionEndpoint, apiKey: apiKey) { subscriptionResult = $0; group.leave() }

        group.notify(queue: .global()) {
            switch creditsResult {
            case .success(let credits):
                let subscription = try? subscriptionResult?.get()
                completion(.success(buildUsage(credits: credits, subscription: subscription)))
            case .failure(let error):
                completion(.failure(error))
            case nil:
                completion(.failure(.invalidResponse))
            }
        }
    }

    /// Reads `COMMANDCODE_API_KEY` from `~/.hermes/.env` (where Hermes stores it).
    /// Only reads the file; never writes it.
    private static func readAPIKey() throws -> String {
        let envPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".hermes")
            .appendingPathComponent(".env")

        let hint = "Add COMMANDCODE_API_KEY to ~/.hermes/.env"

        guard FileManager.default.fileExists(atPath: envPath.path) else {
            throw UsageClientError.missingCredentials(hint)
        }

        let raw: String
        do {
            raw = try String(contentsOf: envPath, encoding: .utf8)
        } catch {
            throw UsageClientError.missingCredentials(hint)
        }

        for line in raw.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("COMMANDCODE_API_KEY=") else { continue }

            var value = String(trimmed.dropFirst("COMMANDCODE_API_KEY=".count))
                .trimmingCharacters(in: .whitespaces)
            if value.count >= 2,
               let first = value.first, let last = value.last,
               (first == "\"" && last == "\"") || (first == "'" && last == "'") {
                value = String(value.dropFirst().dropLast())
            }
            if !value.isEmpty {
                return value
            }
        }

        throw UsageClientError.missingCredentials(hint)
    }

    private static func getJSON(
        _ endpoint: URL,
        apiKey: String,
        completion: @escaping (Result<[String: Any], UsageClientError>) -> Void
    ) {
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

            guard (200..<300).contains(httpResponse.statusCode), let data,
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                completion(.failure(.unavailable("CommandCode usage unavailable")))
                return
            }

            completion(.success(root))
        }.resume()
    }

    private static func buildUsage(
        credits: [String: Any],
        subscription: [String: Any]?
    ) -> CommandCodeUsage {
        let plan = planInfo(from: subscription)

        let creditWallet = credits["credits"] as? [String: Any] ?? [:]
        let monthlyRemaining = max(numericValue(creditWallet["monthlyCredits"]) ?? 0, 0)
        let purchased = max(numericValue(creditWallet["purchasedCredits"]) ?? 0, 0)
        let free = max(numericValue(creditWallet["freeCredits"]) ?? 0, 0)

        // Pool matches the CLI's projection for plan subscriptions: included
        // credits vs. remaining, floored at remaining. Pay-as-you-go (no plan)
        // needs total-spend data this client does not fetch, so no monthly bar.
        let monthly: UsageWindow?
        if let planCredits = plan?.credits, planCredits > 0 {
            let pool = max(planCredits, monthlyRemaining) + purchased + free
            let remaining = monthlyRemaining + purchased + free
            let usedPercent = min(max((pool - remaining) / pool * 100, 0), 100)
            monthly = UsageWindow(
                usedPercent: usedPercent,
                resetAt: plan?.periodEnd,
                windowSeconds: nil
            )
        } else {
            monthly = nil
        }

        let limits = credits["windowLimits"] as? [String: Any] ?? [:]
        let fiveHour = cappedWindow(limits["fiveHour"], windowSeconds: fiveHourSeconds)
        let weekly = cappedWindow(limits["weekly"], windowSeconds: weeklySeconds)

        return CommandCodeUsage(
            planName: plan?.name,
            fiveHour: fiveHour,
            weekly: weekly,
            monthly: monthly
        )
    }

    /// `{"used": 3.5, "cap": 14, "resetAt": 1790348874906}` → percent window.
    private static func cappedWindow(_ value: Any?, windowSeconds: Double) -> UsageWindow? {
        guard
            let entry = value as? [String: Any],
            let used = numericValue(entry["used"]),
            let cap = numericValue(entry["cap"]),
            cap > 0
        else {
            return nil
        }

        return UsageWindow(
            usedPercent: min(max(used / cap * 100, 0), 100),
            resetAt: dateValue(entry["resetAt"]),
            windowSeconds: windowSeconds
        )
    }

    private static func planInfo(from subscription: [String: Any]?) -> (name: String, credits: Double, periodEnd: Date?)? {
        guard let data = subscription?["data"] as? [String: Any] else { return nil }

        let planId = (stringValue(data["planId"]) ?? "").lowercased()
        let match = planCatalog.first { planId.hasPrefix($0.prefix) }

        guard let match, stringValue(data["status"]) == "active" else { return nil }

        return (match.name, match.credits, dateValue(data["currentPeriodEnd"]))
    }
}
