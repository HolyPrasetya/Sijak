//
//  DSSHHHMacApp.swift
//  DSSHHH
//
//  Created by Ignasius Holy Prasetya on 28/07/26.
//


import SwiftUI

@main
struct DSSHHHMacApp: App {
    var body: some Scene {
        WindowGroup {
            MonitorHostView()
        }
        .defaultSize(width: 1280, height: 800)
        .windowResizability(.contentMinSize)
    }
}