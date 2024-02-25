//
//  main.swift
//  
//
//  Created by mi on 2024/2/24.
//

import Foundation
import SwiftUI
import SaveManager

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}

@main
struct MainApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State var refresh = false
    var body: some Scene {
        WindowGroup {
            if Paths.saveFolder.isEmpty {
                Color.white
                    .onAppear {
                        refresh = true
                    }
                    .fileImporter(
                        isPresented: $refresh,
                        allowedContentTypes: [
                            .folder
                        ]) { result in
                            if let path = try? result.get().absoluteString, path.hasSuffix(Paths.saveFolderSuffix) {
                                Paths.saveFolder = path.replacingOccurrences(of: "file://", with: "")

                            } else {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                    refresh = true
                                }
                            }
                        }
            } else {
                ContentView()
            }
        }
    }
}
