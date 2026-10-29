//
//  JPEGTransferService.swift
//  ClickDireto
//
//  Orquestra o download do JPEG original via ICCameraDevice.requestDownloadFile —
//  assinatura oficial confirmada na documentação:
//  requestDownloadFile(_:options:downloadDelegate:didDownloadSelector:contextInfo:) (iOS 13+)
//  O callback oficial do ICCameraDeviceDownloadDelegate é
//  didDownloadFile(_:error:options:contextInfo:) e devolve o nome salvo em
//  ICDownloadOption.savedFilename. Os bytes baixados NÃO são recomprimidos.
//

import Foundation
import ImageCaptureCore

final class JPEGTransferService: NSObject, ICCameraDeviceDownloadDelegate {

    typealias TransferCompletion = (Result<DownloadedFile, Error>) -> Void

    struct DownloadedFile {
        let jpegURL: URL
        let handleKey: String
        let captureDate: Date?
    }

    private struct PendingDownload {
        let handleKey: String
        let captureDate: Date?
        let onDone: TransferCompletion
    }

    private let tempDirectory: URL
    private let workQueue = DispatchQueue(label: "ClickDireto.transfer")
    private var pendingByFilename: [String: PendingDownload] = [:]
    private var pendingByHandleKey: [String: PendingDownload] = [:]

    init(tempDirectory: URL) {
        self.tempDirectory = tempDirectory
        super.init()
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    func download(_ file: ICCameraFile, from device: ICCameraDevice, completion: @escaping TransferCompletion) {
        let handleKey = "ptp-\(file.ptpObjectHandle)"
        let originalName = file.name ?? "clickdireto-\(file.ptpObjectHandle).jpg"
        let pending = PendingDownload(handleKey: handleKey,
                                      captureDate: file.creationDate,
                                      onDone: completion)
        workQueue.async { [weak self] in
            self?.pendingByFilename[originalName] = pending
            self?.pendingByHandleKey[handleKey] = pending
        }

        let options: [ICDownloadOption: Any] = [
            .downloadsDirectoryURL: tempDirectory,
            .overwrite: true
        ]
        // NUNCA usamos .deleteAfterSuccessfulDownload: o cartão da câmera não é modificado.
        let didDownloadSelector = Selector(("didDownloadFile:error:options:contextInfo:"))

        device.requestDownloadFile(file,
                                   options: options,
                                   downloadDelegate: self,
                                   didDownloadSelector: didDownloadSelector,
                                   contextInfo: nil)
    }

    // MARK: - ICCameraDeviceDownloadDelegate (callback oficial do SDK)

    func didDownloadFile(_ file: ICCameraFile,
                         error: (any Error)?,
                         options: [String: Any],
                         contextInfo: UnsafeMutableRawPointer?) {
        workQueue.async { [weak self] in
            guard let self else { return }

            let savedName = options[ICDownloadOption.savedFilename.rawValue] as? String
            let lookupName = savedName ?? file.name ?? ""
            let handleKey = "ptp-\(file.ptpObjectHandle)"
            let pendingCandidate = self.pendingByFilename.removeValue(forKey: lookupName)
                ?? self.pendingByFilename.removeValue(forKey: file.name ?? "")
                ?? self.pendingByHandleKey.removeValue(forKey: handleKey)
            if let pending = pendingCandidate {
                self.pendingByFilename.removeValue(forKey: file.name ?? "")
                self.pendingByHandleKey.removeValue(forKey: handleKey)
            }

            guard let pending = pendingCandidate else {
                // ICC entregou um download que não iniciamos: nada a notificar.
                return
            }

            if let error {
                DispatchQueue.main.async { pending.onDone(.failure(error)) }
                return
            }

            let finalName = savedName ?? lookupName
            let savedURL = self.tempDirectory.appendingPathComponent(finalName)

            do {
                let attributes = try FileManager.default.attributesOfItem(atPath: savedURL.path)
                let byteCount = (attributes[.size] as? NSNumber)?.doubleValue ?? 0
                guard byteCount > 0 else {
                    DispatchQueue.main.async {
                        pending.onDone(.failure(NSError(domain: "ClickDireto",
                                                        code: -1,
                                                        userInfo: [NSLocalizedDescriptionKey:
                                                            "Download terminou sem bytes: \(finalName)"])))
                    }
                    return
                }
                DispatchQueue.main.async {
                    pending.onDone(.success(DownloadedFile(jpegURL: savedURL,
                                                           handleKey: pending.handleKey,
                                                           captureDate: pending.captureDate)))
                }
            } catch {
                DispatchQueue.main.async { pending.onDone(.failure(error)) }
            }
        }
    }
}
