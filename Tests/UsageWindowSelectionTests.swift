import Foundation

@main
enum UsageWindowSelectionTests {
    static func main() {
        let fiveHour = UsageWindow(usedPercent: 10, resetAt: nil, windowSeconds: nil)
        let weekly = UsageWindow(usedPercent: 20, resetAt: nil, windowSeconds: nil)
        let monthly = UsageWindow(usedPercent: 30, resetAt: nil, windowSeconds: nil)
        let openCode = OpenCodeUsage(rolling: fiveHour, weekly: weekly, monthly: monthly)
        let commandCode = CommandCodeUsage(
            planName: "Test",
            fiveHour: fiveHour,
            weekly: weekly,
            monthly: monthly
        )

        precondition(UsageWindowMetric.fiveHour.window(from: openCode) == fiveHour)
        precondition(UsageWindowMetric.weekly.window(from: openCode) == weekly)
        precondition(UsageWindowMetric.monthly.window(from: openCode) == monthly)
        precondition(UsageWindowMetric.fiveHour.window(from: commandCode) == fiveHour)
        precondition(UsageWindowMetric.weekly.window(from: commandCode) == weekly)
        precondition(UsageWindowMetric.monthly.window(from: commandCode) == monthly)
        precondition(UsageWindowMetric.fiveHour.percent(from: openCode) == 10)
        precondition(UsageWindowMetric.weekly.percent(from: commandCode) == 20)
        precondition(UsageWindowMetric.monthly.percent(from: openCode, preference: .monthly) == 30)
        precondition(UsageWindowMetric.weekly.percent(from: commandCode, preference: .weekly) == 20)

        let rollingOnly = OpenCodeUsage(rolling: fiveHour, weekly: nil, monthly: nil)
        precondition(UsageWindowMetric.monthly.percent(from: rollingOnly, preference: .monthly) == 10)
        let weeklyOnly = CommandCodeUsage(planName: nil, fiveHour: nil, weekly: weekly, monthly: nil)
        precondition(UsageWindowMetric.monthly.percent(from: weeklyOnly, preference: .monthly) == 20)

        let chatGPT = ChatGPTUsage(planName: "Plus", primaryWindow: fiveHour, secondaryWindow: weekly)
        precondition(ChatGPTSessionWindow.fiveHour.window(from: chatGPT) == fiveHour)
        precondition(ChatGPTSessionWindow.weekly.window(from: chatGPT) == weekly)
        precondition(ChatGPTSessionWindow.fiveHour.percent(from: chatGPT) == 10)
        precondition(ChatGPTSessionWindow.weekly.percent(from: chatGPT) == 20)
        precondition(ChatGPTSessionWindow.fiveHour.percent(from: chatGPT, preference: .weekly) == 20)
        precondition(ChatGPTSessionWindow.weekly.percent(from: nil, preference: .fiveHour) == nil)

        let claude = ClaudeUsage(planName: "max", fiveHourWindow: fiveHour, weeklyWindow: weekly)
        precondition(ChatGPTSessionWindow.weekly.window(fromClaude: claude) == weekly)
        precondition(ChatGPTSessionWindow.fiveHour.percent(fromClaude: claude, preference: .fiveHour) == 10)
        precondition(ChatGPTSessionWindow.weekly.percent(fromClaude: claude, preference: .weekly) == 20)
        let claudeWeeklyOnly = ClaudeUsage(planName: nil, fiveHourWindow: nil, weeklyWindow: weekly)
        precondition(ChatGPTSessionWindow.fiveHour.percent(fromClaude: claudeWeeklyOnly, preference: .fiveHour) == 20)

        let claudeJSON = #"{"five_hour":{"utilization":9.0,"resets_at":"2026-10-03T09:00:00.302450+00:00"},"seven_day":{"utilization":1.0,"resets_at":"2026-10-09T15:00:00.302468+00:00"},"seven_day_opus":null}"#
        let parsed = try! ClaudeUsageClient.parseUsage(Data(claudeJSON.utf8), planName: "max")
        precondition(parsed.fiveHourWindow?.usedPercent == 9)
        precondition(parsed.weeklyWindow?.usedPercent == 1)
        precondition(parsed.fiveHourWindow?.resetAt != nil)
        precondition(parsed.weeklyWindow?.windowSeconds == 7 * 86_400)

        // Refresh write-back: patches only the token fields, and only while the
        // stored refresh token is still the one that was rotated.
        let stored = Data(#"{"claudeAiOauth":{"accessToken":"old-access","refreshToken":"old-refresh","expiresAt":1000,"scopes":["user:inference"],"subscriptionType":"pro"},"other":1}"#.utf8)
        let storedCredentials = ClaudeUsageClient.parseCredentials(stored)!
        precondition(storedCredentials.isExpired)
        precondition(storedCredentials.scopes == ["user:inference"])
        var fresh = storedCredentials
        fresh.accessToken = "new-access"
        fresh.refreshToken = "new-refresh"
        fresh.expiresAt = Date(timeIntervalSince1970: 2_000_000_000)
        let patched = ClaudeUsageClient.updatedCredentialsJSON(stored, with: fresh, replacing: "old-refresh")!
        let reparsed = ClaudeUsageClient.parseCredentials(patched)!
        precondition(reparsed.accessToken == "new-access")
        precondition(reparsed.refreshToken == "new-refresh")
        precondition(reparsed.planName == "pro")
        precondition(!reparsed.isExpired)
        precondition((try! JSONSerialization.jsonObject(with: patched) as! [String: Any])["other"] as? Int == 1)
        precondition(ClaudeUsageClient.updatedCredentialsJSON(stored, with: fresh, replacing: "someone-else") == nil)

        let date = Date()
        precondition(formatResetCaption(date) == formatReset(date))
        precondition(formatCycleCaption(date) == formatReset(date))
        precondition(formatCycleCaption(nil) == nil)
        let cycle = formatCycleCaption(date) ?? ""
        precondition(!cycle.contains("Cycle"))
        precondition(!cycle.contains("resets in"))
        precondition(formatResetCaption(nil) == "unavailable")
        precondition(!formatResetCaption(date).contains("resets in"))

        print("UsageWindowSelectionTests: PASS")
    }
}
