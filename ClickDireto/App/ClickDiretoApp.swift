//
//  ClickDiretoApp.swift
//  ClickDireto
//
//  Ponto de entrada do app (prova de conceito — Fase 2 do projeto).
//

import SwiftUI
import Photos

@main
struct ClickDiretoApp: App {
    @StateObject private var appState: AppState
    @StateObject private var connection: CameraConnectionManager

    init() {
        let state = AppState()
        let manager = CameraConnectionManager(
            appState: state,
            eventMonitor: CaptureEventMonitor(),
            transferService: JPEGTransferService(
                tempDirectory: FileManager.default.temporaryDirectory
                    .appendingPathComponent("ClickDiretoDownloads", isDirectory: true)),
            photoWriter: PhotoLibraryWriter(),
            diagnostics: ConnectionDiagnostics(appState: state))
        _appState = StateObject(wrappedValue: state)
        _connection = StateObject(wrappedValue: manager)
    }

    var body: some Scene {
        WindowGroup {
            HomeView(
                appState: appState,
                onStart: { connection.startSearchingForCamera() },
                onStop: { connection.stopEverything() },
                onTestCapture: { connection.takeTestPicture() },
                onRefreshAuthorization: { connection.refreshPhotoAuthorization() }
            )
            .onAppear {
                connection.refreshPhotoAuthorization()
            }
        }
    }
}
