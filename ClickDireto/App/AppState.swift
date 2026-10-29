//
//  AppState.swift
//  ClickDireto
//
//  Estado observável pela interface (SwiftUI).
//

import Foundation
import Photos
import UIKit

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

    // V2: foto em destaque (imagem cheia) + miniaturas recentes da sessão.
    @Published var heroPhoto: UIImage?
    @Published var heroPhotoFilename: String?
    @Published var thumbnails: [UIImage] = []

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

    /// Chamar APÓS o PhotoKit confirmar o salvamento (nunca antes).
    /// Gera a miniatura em escala reduzida antes de descartar o temporário.
    func publishSavedPhoto(image: UIImage, filename: String) {
        self.heroPhoto = image
        self.heroPhotoFilename = filename
        let thumb = Self.resized(image: image, maxDimension: 240)
        thumbnails.insert(thumb, at: 0)
        if thumbnails.count > 12 {
            thumbnails.removeLast(thumbnails.count - 12)
        }
    }

    func updateAverageLatency(_ seconds: Double) {
        self.averageLatencySeconds = seconds
    }

    func clearSessionVisuals() {
        heroPhoto = nil
        heroPhotoFilename = nil
        thumbnails = []
        photosReceived = 0
        lastSavedFilename = nil
    }

    func appendLog(_ line: String) {
        logLines.append(line)
        if logLines.count > 250 {
            logLines.removeFirst(logLines.count - 250)
        }
    }

    private static func resized(image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        let maxSide = max(size.width, size.height)
        guard maxSide > maxDimension, maxSide > 0 else { return image }
        let scale = maxDimension / maxSide
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
