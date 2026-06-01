//
//  ContentView.swift
//  ProtoType
//
//  Created by Harry Khizer on 5/6/26.
//

import SwiftUI

struct ContentView: View {
    @State private var appState = AppState()

    var body: some View {
        Group {
            if appState.hasCompletedOnboarding {
                HomeView()
            } else {
                OnboardingView()
            }
        }
        .environment(appState)
    }
}

#Preview {
    ContentView()
}
