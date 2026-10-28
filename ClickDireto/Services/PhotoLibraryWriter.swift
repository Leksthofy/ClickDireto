//
//  PhotoLibraryWriter.swift
//  ClickDireto
//
//  Salva o JPEG baixado na biblioteca do app Foto do iOS preservando os bytes
//  originais (PHAssetCreationRequest.creationRequestForAsset(from:)) — sem
//  recompressão, sem alteração de dimensões, sem internet.
//

import Foundation
import Photos

final class PhotoLibraryWriter {

    func currentAuthorizationStatus() -> PHAuthorizationStatus {
        PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }

    func requestAuthorization(_ completion: @escaping (PHAuthorizationStatus) -> Void) {
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
            DispatchQueue.main.async { completion(status) }
        }
    }

    /// Salva o arquivo JPEG na biblioteca e devolve o localIdentifier do asset criado.
    func saveJPEG(at fileURL: URL, creationDate: Date?, completion: @escaping (Result<String, Error>) -> Void) {
        let resourceOptions = PHAssetResourceCreationOptions()
        resourceOptions.originalFilename = fileURL.lastPathComponent
        var createdAssetID: String?

        PHPhotoLibrary.shared().performChanges({
            let request = PHAssetCreationRequest.forAsset()
            request.addResource(with: .photo, fileURL: fileURL, options: resourceOptions)
            if let creationDate {
                request.creationDate = creationDate
            }
            createdAssetID = request.placeholderForCreatedAsset?.localIdentifier
        }) { success, error in
            DispatchQueue.main.async {
                guard success, error == nil else {
                    let failure = error ?? NSError(domain: "ClickDireto",
                                                   code: -3,
                                                   userInfo: [NSLocalizedDescriptionKey: "Falha ao salvar no app Foto."])
                    completion(.failure(failure))
                    return
                }
                let identifier = createdAssetID ?? "sem-identificador"
                completion(.success(identifier))
            }
        }
    }
}
