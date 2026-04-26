// Sources/MercantisHub/MercantisHubApp.swift
import SwiftUI
import MercantisCore

@main
struct MercantisHubApp: App {
    var body: some Scene {
        WindowGroup {
            Text("Hub on Core — \(MercantisCore.self)")
        }
    }
}
