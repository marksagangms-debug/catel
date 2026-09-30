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
