import SwiftUI

@main
struct IM70_3App: App {
    @StateObject private var dataStore = AppDataStore()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(dataStore)
        }
    }
}
