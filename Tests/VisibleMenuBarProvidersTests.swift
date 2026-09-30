import Foundation

@main
enum VisibleMenuBarProvidersTests {
    static func main() {
        let slots: [MenuBarProvider] = [.chatGPT, .deepSeek, .none]
        let availableWithoutDeepSeek = ProviderAvailability(values: [
            .chatGPT: true,
            .hermes: true
        ])
        precondition(
            VisibleMenuBarProviders.resolve(
                slots: slots,
                availability: availableWithoutDeepSeek
            ) == [.chatGPT, .none]
        )

        let availableWithDeepSeek = ProviderAvailability(values: [
            .chatGPT: true,
            .hermes: true,
            .deepSeek: true
        ])
        precondition(
            VisibleMenuBarProviders.resolve(
                slots: slots,
                availability: availableWithDeepSeek
            ) == [.chatGPT, .deepSeek, .none]
        )

        let missingAssignedProviders = ProviderAvailability(values: [.chatGPT: true])
        precondition(
            VisibleMenuBarProviders.resolve(
                slots: [.deepSeek, .none, .none],
                availability: missingAssignedProviders
            ) == [.chatGPT]
        )

        print("VisibleMenuBarProvidersTests: PASS")
    }
}
