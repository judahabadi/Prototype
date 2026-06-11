import SwiftUI

struct ContentView: View {
    @State private var appState = AppState()
    @State private var manager = SubscriptionManager.shared

    var body: some View {
        Group {
            if manager.shouldShowPaywall {
                PaywallView(isHardBlock: true)
            } else if appState.hasCompletedOnboarding {
                HomeView()
                    .environment(appState)
            } else {
                OnboardingView()
                    .environment(appState)
            }
        }
        .task {
            await manager.refresh()
        }
    }
}

#Preview {
    ContentView()
}
