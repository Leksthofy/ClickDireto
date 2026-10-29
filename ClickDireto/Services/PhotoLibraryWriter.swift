//
//  PhotoLibraryWriter.swift
//  ClickDireto
//
//  Salva o JPEG baixado na biblioteca do app Foto do iOS preservando os bytes
//  originais (PHAssetCreationRequest.creationRequestForAsset(from:)) — sem
//  recompressão, sem alteração de dimensões, sem internet.
//  V2: cada arquivo é adicionado ao álbum próprio "ClickDireto" (criado
//  automaticamente se ainda não existir).
//

import Foundation
import Photos

final class PhotoLibraryWriter {

    static let albumName = "ClickDireto"

    func currentAuthorizationStatus() -> PHAuthorizationStatus {
        PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }

    func requestAuthorization(_ completion: @escaping (PHAuthorizationStatus) -> Void) {
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
            DispatchQueue.main.async { completion(status) }
        }
    }

    /// Salva o arquivo JPEG na biblioteca e devolve o localIdentifier do asset criado.
    /// A confirmação SÓ é emitida depois que o PhotoKit confirma a mudança.
    /// Falha de álbum não cancela o salvamento do asset (a foto permanece salva;
    /// o log registra o problema do álbum separadamente).
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
            guard let placeholder = request.placeholderForCreatedAsset else { return }
            createdAssetID = placeholder.localIdentifier

            // Álbum "ClickDireto": busca por título; cria se não existir.
            let fetch = PHAssetCollection.fetchAssetCollections(
                with: .album, subtype: .albumRegular,
                options: Self.albumFetchOptions())
            let album = fetch.firstObject
                ?? PHCollectionListChangeRequest.creationRequestForAlbum(
                    title: Self.albumName).placeholderForCreatedAssetCollection
            if let album,
               let albumRequest = PHAssetCollectionChangeRequest(for: album) {
                albumRequest.addAssets([placeholder] as NSArray)
            }
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

    private static func albumFetchOptions() -> PHFetchOptions {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "title == %@", albumName)
        return options
    }
}
