//
//  AppState.swift
//  ClickDireto
//
//  Estado observável pela interface (SwiftUI).
//

import Foundation
import Photos

// Sem isolamento @MainActor: todos os caminhos que tocam AppState já chegam
// pelo fio principal (delegates do ImageCaptureCore entregam no run loop
// principal quando iniciados pela main thread; os demais serviços fazem hop
// explícito para DispatchQueue.main antes de chamar).
//
final class AppState: ObservableObject {

    @Published var phase: ConnectionPhase = .idle
    @Published var cameraName: String?
    @Published var cameraUSBIDs: String?
    @Published var photosReceived: Int = 0
    @Published var photoLibraryStatus: PHAuthorizationStatus = .notDetermined
    @Published var lastSavedFilename: String?
    @Published var averageLatencySeconds: Double?
    @Published var logLines: [String] = []

    func setPhase(_ phase: ConnectionPhase) {
        self.phase = phase
    }

    func setCamera(deviceName: String?, usbIDs: String) {
        self.cameraName = deviceName
        self.cameraUSBIDs = usbIDs
    }

    func onPhotoSaved(count: Int, filename: String) {
        self.photosReceived = count
        self.lastSavedFilename = filename
    }

    func updateAverageLatency(_ seconds: Double) {
        self.averageLatencySeconds = seconds
    }

    func appendLog(_ line: String) {
        logLines.append(line)
        if logLines.count > 250 {
            logLines.removeFirst(logLines.count - 250)
        }
    }
}
