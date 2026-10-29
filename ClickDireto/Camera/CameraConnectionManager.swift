//
//  CameraConnectionManager.swift
//  ClickDireto
//
//  Descoberta e sessão com a câmera via ImageCaptureCore (API pública da Apple, iOS 13+).
//  Assinaturas verificadas na documentação oficial:
//  https://developer.apple.com/documentation/imagecapturecore/
//

import Foundation
import ImageCaptureCore
import CoreGraphics
import Photos
import UIKit

enum ConnectionPhase: Equatable {
    case idle                // nada iniciado
    case browsing            // procurando câmera
    case detected            // câmera vista pelo browser, sessão ainda não aberta
    case authorizing         // aguardando permissão do usuário para acessar a câmera
    case connected           // sessão aberta, catálogo enumerado (pronta para receber)
    case receivingPhoto      // JPEG em trânsito (baixando)
    case savingPhoto         // JPEG baixado; gravando no app Foto (confirmação pendente)
    case error(String)
}

final class CameraConnectionManager: NSObject, ObservableObject {

    // MARK: - Colaboradores injetados

    private let appState: AppState
    private let eventMonitor: CaptureEventMonitor
    private let transferService: JPEGTransferService
    private let photoWriter: PhotoLibraryWriter
    private let diagnostics: ConnectionDiagnostics

    // MARK: - Estado interno

    private let browser = ICDeviceBrowser()
    private var camera: ICCameraDevice?
    private var isReady = false

    /// Fila serial do pipeline: download → validação → save no Foto → publicação.
    /// Garante ordem FIFO entre disparos e evita dois downloads simultâneos.
    private let pipelineQueue = DispatchQueue(label: "ClickDireto.pipeline", qos: .userInitiated)

    init(appState: AppState,
         eventMonitor: CaptureEventMonitor,
         transferService: JPEGTransferService,
         photoWriter: PhotoLibraryWriter,
         diagnostics: ConnectionDiagnostics) {
        self.appState = appState
        self.eventMonitor = eventMonitor
        self.transferService = transferService
        self.photoWriter = photoWriter
        self.diagnostics = diagnostics
        super.init()
        browser.delegate = self
    }

    // MARK: - Ações públicas (chamadas da interface)

    func startSearchingForCamera() {
        appState.clearSessionVisuals()
        appState.setPhase(.browsing)
        diagnostics.log("Iniciando busca por câmeras (ICDeviceBrowser, tipo .camera)…")
        browser.browsedDeviceTypeMask = .camera
        browser.start()
    }

    func stopEverything() {
        browser.stop()
        camera?.requestCloseSession()
        camera = nil
        isReady = false
        eventMonitor.reset()
        appState.setPhase(.idle)
        diagnostics.log("Busca encerrada e encerramento de sessão solicitado.")
    }

    /// Diagnóstico: no iOS, requestTakePicture() é indisponível (API macOS-only).
    /// O ClickDireto não precisa dele: a foto chega pelo disparo físico da câmera.
    func takeTestPicture() {
        guard camera != nil else {
            diagnostics.log("DIAGNÓSTICO: nenhuma câmera conectada ainda.")
            return
        }
        guard isReady else {
            diagnostics.log("DIAGNÓSTICO: câmera presente, mas catálogo ainda não enumerado; aguarde 'PRONTA'.")
            return
        }
        diagnostics.log("DIAGNÓSTICO: sessão OK. Disparo remoto não existe no iOS (requestTakePicture indisponível) — tire a foto pelo botão físico da câmera.")
    }

    func refreshPhotoAuthorization() {
        appState.photoLibraryStatus = photoWriter.currentAuthorizationStatus()
    }

    // MARK: - Sessão

    private func tryOpenSession(on device: ICCameraDevice) {
        guard !device.hasOpenSession else {
            diagnostics.log("Sessão já aberta com: \(device.name ?? "câmera")")
            return
        }
        appState.setPhase(.authorizing)
        diagnostics.log("Solicitando autorização de conteúdo da câmera (prompt do sistema)…")
        browser.requestContentsAuthorization { [weak self] status in
            guard let self else { return }
            self.diagnostics.log("Status de autorização de conteúdo: \(status)")
            self.diagnostics.log("Abrindo sessão com a câmera (requestOpenSession)…")
            device.requestOpenSession()
            // Permissão de Foto é solicitada no mesmo fluxo (o prompt do iOS
            // aparece junto com o da câmera; antes disso o app só lia o status).
            self.photoWriter.requestAuthorization { photoStatus in
                self.appState.photoLibraryStatus = photoStatus
                self.diagnostics.log("Permissão de Foto: \(photoStatus)")
            }
        }
    }

    // MARK: - Fluxo de captura nova

    private func handleNewItemsIfReady(_ items: [ICCameraItem]) {
        guard isReady, let camera else { return }
        let newFiles = eventMonitor.filterNewJPEGFiles(items)
        guard !newFiles.isEmpty else { return }
        appState.setPhase(.receivingPhoto)

        for file in newFiles {
            let handleKey = "ptp-\(file.ptpObjectHandle)"
            let fileForClosure = file
            diagnostics.registerAdded(handleKey: handleKey)
            // Fila serial: um disparo processado por vez, em ordem de chegada.
            pipelineQueue.async { [weak self] in
                guard let self else { return }
                self.transferService.download(fileForClosure, from: camera) { [weak self] result in
                    guard let self else { return }
                    switch result {
                    case .success(let downloaded):
                        self.appState.phase = .savingPhoto
                        self.photoWriter.saveJPEG(at: downloaded.jpegURL,
                                                  creationDate: downloaded.captureDate) { saveResult in
                            switch saveResult {
                            case .success(let assetIdentifier):
                                self.eventMonitor.markProcessed(handleKey: handleKey)
                                var sizeBytes: Double = 0
                                var savedImage: UIImage?
                                if let info = try? FileManager.default
                                    .attributesOfItem(atPath: downloaded.jpegURL.path) {
                                    sizeBytes = (info[.size] as? NSNumber)?.doubleValue ?? 0
                                }
                                // Foto-hero é carregada ANTES de remover o temporário.
                                if let data = try? Data(contentsOf: downloaded.jpegURL) {
                                    savedImage = UIImage(data: data)
                                }
                                self.diagnostics.logLatency(handleKey: handleKey, bytes: sizeBytes)
                                if let savedImage {
                                    self.appState.publishSavedPhoto(
                                        image: savedImage,
                                        filename: downloaded.jpegURL.lastPathComponent)
                                }
                                self.diagnostics.log("Salvo no app Foto (\(assetIdentifier)).")
                                try? FileManager.default.removeItem(at: downloaded.jpegURL)
                                self.appState.onPhotoSaved(count: self.diagnostics.successCount,
                                                           filename: downloaded.jpegURL.lastPathComponent)
                                self.appState.setPhase(.connected)
                            case .failure(let error):
                                self.diagnostics.log("ERRO ao salvar no app Foto: \(error)")
                                self.appState.setPhase(.connected)
                            }
                        }
                    case .failure(let error):
                        self.diagnostics.log("ERRO no download: \(error)")
                        self.appState.setPhase(.connected)
                    }
                }
            }
        }
    }
}

// MARK: - ICDeviceBrowserDelegate (assinaturas oficiais)

extension CameraConnectionManager: ICDeviceBrowserDelegate {

    func deviceBrowser(_ deviceBrowser: ICDeviceBrowser, didAdd device: ICDevice, moreComing: Bool) {
        diagnostics.log("Dispositivo adicionado: \(device.name ?? "desconhecido") (tipo \(device.type)).")
        guard let cameraDevice = device as? ICCameraDevice else {
            diagnostics.log("Dispositivo não é ICCameraDevice; ignorado.")
            return
        }
        camera = cameraDevice
        cameraDevice.delegate = self
        appState.setCamera(deviceName: cameraDevice.name,
                           usbIDs: "USB vendor \(cameraDevice.usbVendorID), product \(cameraDevice.usbProductID)")
        appState.setPhase(.detected)
        tryOpenSession(on: cameraDevice)
    }

    // ObjC oficial: deviceBrowser:didRemoveDevice:moreGoing: (remoção usa "moreGoing",
    // diferente de didAddDevice:moreComing:)
    func deviceBrowser(_ deviceBrowser: ICDeviceBrowser, didRemove device: ICDevice, moreGoing: Bool) {
        diagnostics.log("Dispositivo removido: \(device.name ?? "desconhecido").")
        if device === camera {
            camera = nil
            isReady = false
            eventMonitor.reset()
            appState.setPhase(.browsing)
        }
    }
}

// MARK: - ICDeviceDelegate + ICCameraDeviceDelegate (assinaturas oficiais)

extension CameraConnectionManager: ICCameraDeviceDelegate {

    // ICDeviceDelegate — eventos de sessão

    func device(_ device: ICDevice, didOpenSessionWithError error: (any Error)?) {
        if let error {
            diagnostics.log("Sessão aberta com erro: \(error)")
            appState.setPhase(.error(String(describing: error)))
        } else {
            diagnostics.log("Sessão aberta com sucesso.")
        }
    }

    func device(_ device: ICDevice, didCloseSessionWithError error: (any Error)?) {
        diagnostics.log("Sessão fechada\(error.map { " com erro: \($0)" } ?? "").")
        isReady = false
    }

    func didRemove(_ device: ICDevice) {
        diagnostics.log("Dispositivo removido (didRemoveDevice).")
        if device === camera {
            camera = nil
            isReady = false
            eventMonitor.reset()
            appState.setPhase(.browsing)
        }
    }

    func deviceDidBecomeReady(_ device: ICDevice) {
        diagnostics.log("Dispositivo pronto (deviceDidBecomeReady).")
    }

    func device(_ device: ICDevice, didReceiveStatusInformation status: [ICDeviceStatus: Any]) {
        diagnostics.log("Status recebido: \(status)")
    }

    func device(_ device: ICDevice, didEncounterError error: (any Error)?) {
        diagnostics.log("Erro relatado pelo dispositivo: \(error.map(String.init(describing:)) ?? "?")")
    }

    func device(_ device: ICDevice, didEjectWithError error: (any Error)?) {
        diagnostics.log("Ejeção concluída\(error.map { " com erro: \($0)" } ?? "").")
    }

    // deviceDidChangeName não existe no iOS (marcado unavailable) — omitido por isso.

    // ICCameraDeviceDelegate — catálogo completo = pronto para receber capturas

    func deviceDidBecomeReady(withCompleteContentCatalog device: ICCameraDevice) {
        isReady = true
        let existingFiles = device.mediaFiles as? [ICCameraFile] ?? []
        for existingFile in existingFiles {
            eventMonitor.markExistingFromEnumeration(handleKey: "ptp-\(existingFile.ptpObjectHandle)")
        }

        // Capacidade oficial: câmeras de terceiros (Canon incluída) têm "fotografar
        // enquanto conectada" habilitado por padrão (Apple doc de requestEnableTethering,
        // deprecated). Confirmação objetiva via capabilities:
        let caps = device.capabilities.map { "\($0)" }
        let canShootWhileConnected = caps.contains(ICDeviceCapability.cameraDeviceCanTakePicture.rawValue)
        diagnostics.log("Capacidade 'fotografar com cabo conectado' (cameraDeviceCanTakePicture): \(canShootWhileConnected)")
        diagnostics.log("Tela preta/transferência na R8 é o modo USB nativo da câmera (igual no app Foto, Capture One e Evoto). Dispare pelo BOTÃO FÍSICO da câmera — cada foto chega aqui automaticamente.")
        diagnostics.log("Câmera PRONTA. Catálogo lido (apenas índices, NENHUM download). Fotos já no cartão: \(existingFiles.count) — não serão importadas.")
        appState.setPhase(.connected)
    }

    // Capturas novas exclusivamente pelo botão físico chegam aqui

    func cameraDevice(_ cameraDevice: ICCameraDevice, didAdd items: [ICCameraItem]) {
        diagnostics.log("didAddItems: \(items.map { $0.name ?? "?" }).")
        handleNewItemsIfReady(items)
    }

    func cameraDevice(_ cameraDevice: ICCameraDevice, didAdd item: ICCameraItem) {
        diagnostics.log("didAddItem: \(item.name ?? "?").")
        handleNewItemsIfReady([item])
    }

    func cameraDevice(_ cameraDevice: ICCameraDevice, didRemove item: ICCameraItem) {
        diagnostics.log("didRemoveItem: \(item.name ?? "?").")
    }

    func cameraDevice(_ cameraDevice: ICCameraDevice, didRemove items: [ICCameraItem]) {
        diagnostics.log("didRemoveItems: \(items.map { $0.name ?? "?" }).")
    }

    func cameraDevice(_ cameraDevice: ICCameraDevice, didRenameItems items: [ICCameraItem]) {
        diagnostics.log("didRenameItems: \(items.count) itens.")
    }

    // Metadados e miniaturas não são usados — recusa para minimizar tráfego.

    func cameraDevice(_ cameraDevice: ICCameraDevice, shouldGetMetadataOf item: ICCameraItem) -> Bool {
        false
    }

    func cameraDevice(_ cameraDevice: ICCameraDevice, didReceiveMetadataFor item: ICCameraItem) {
        // não usado
    }

    func cameraDevice(_ cameraDevice: ICCameraDevice,
                      didReceiveMetadata metadata: [AnyHashable: Any]?,
                      for item: ICCameraItem,
                      error: (any Error)?) {
        // não usado
    }

    func cameraDevice(_ cameraDevice: ICCameraDevice, shouldGetThumbnailOf item: ICCameraItem) -> Bool {
        false
    }

    func cameraDevice(_ cameraDevice: ICCameraDevice, didReceiveThumbnailFor item: ICCameraItem) {
        // não usado
    }

    func cameraDevice(_ cameraDevice: ICCameraDevice,
                      didReceiveThumbnail thumbnail: CGImage?,
                      for item: ICCameraItem,
                      error: (any Error)?) {
        // não usado
    }

    func cameraDeviceDidChangeCapability(_ cameraDevice: ICCameraDevice) {
        diagnostics.log("Capacidade da câmera mudou.")
    }

    func cameraDeviceDidEnableAccessRestriction(_ device: ICDevice) {
        diagnostics.log("Acesso à mídia RESTRITO por bloqueio de tela; desbloqueie o iPhone.")
        appState.setPhase(.error("Acesso restrito: desbloqueie o iPhone."))
    }

    func cameraDeviceDidRemoveAccessRestriction(_ device: ICDevice) {
        diagnostics.log("Restrição de acesso removida; mídia disponível.")
        appState.setPhase(.connected)
    }

    func cameraDevice(_ cameraDevice: ICCameraDevice, didReceivePTPEvent event: Data) {
        diagnostics.log("Evento PTP recebido (\(event.count) bytes).")
    }
}
