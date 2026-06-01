//
//  ContentView.swift
//  ProtoType
//
//  Created by Harry Khizer on 5/6/26.
//

import SwiftUI

struct ContentView: View {
    @State private var nativeLanguage: Language = {
        let raw = AppGroup.defaults.string(forKey: AppGroup.nativeKey) ?? Language.english.rawValue
        return Language(rawValue: raw) ?? .english
    }()

    @State private var targetLanguage: Language = {
        let raw = AppGroup.defaults.string(forKey: AppGroup.targetKey) ?? Language.spanish.rawValue
        return Language(rawValue: raw) ?? .spanish
    }()

    var body: some View {
        NavigationStack {
            Form {
                Section("I speak") {
                    Picker("Native language", selection: $nativeLanguage) {
                        ForEach(Language.allCases) { lang in
                            Text("\(lang.flag) \(lang.displayName)").tag(lang)
                        }
                    }
                }

                Section("I want to learn") {
                    Picker("Target language", selection: $targetLanguage) {
                        ForEach(Language.allCases) { lang in
                            Text("\(lang.flag) \(lang.displayName)").tag(lang)
                        }
                    }
                }

                Section("Setup") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("1. Settings → General → Keyboard → Keyboards")
                        Text("2. Tap \"Add New Keyboard\" → ProtoType")
                        Text("3. Enable Full Access")
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Prototype")
            .onChange(of: nativeLanguage) { _, new in
                AppGroup.defaults.set(new.rawValue, forKey: AppGroup.nativeKey)
            }
            .onChange(of: targetLanguage) { _, new in
                AppGroup.defaults.set(new.rawValue, forKey: AppGroup.targetKey)
            }
        }
    }
}

#Preview {
    ContentView()
}
