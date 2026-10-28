//
//  CaptureEventMonitor.swift
//  ClickDireto
//
//  Decide quais itens do catálogo PTP são capturas NOVAS (dedupe por ptpObjectHandle).
//  Itens que já existiam no cartão quando a sessão abriu NUNCA são reimportados,
//  conforme a regra do projeto: não apagar nem duplicar imagens originais.
//

import Foundation
import ImageCaptureCore
import UniformTypeIdentifiers

final class CaptureEventMonitor {

    private var processedHandles = Set<String>()

    /// Marca handle presente no catálogo inicial (enumerado pela canalização do SDK).
    func markExistingFromEnumeration(handleKey: String) {
        processedHandles.insert(handleKey)
    }

    /// Marca handle cujo JPEG já foi salvo com sucesso no PhotoKit.
    func markProcessed(handleKey: String) {
        processedHandles.insert(handleKey)
    }

    func reset() {
        processedHandles.removeAll()
    }

    private func key(for item: ICCameraItem) -> String {
        "ptp-\(item.ptpObjectHandle)"
    }

    private func isJPEG(_ item: ICCameraItem) -> Bool {
        if let utiString = item.uti, let uti = UTType(utiString) {
            return uti.conforms(to: .jpeg)
        }
        if let name = item.name {
            let lower = name.lowercased()
            return lower.hasSuffix(".jpg") || lower.hasSuffix(".jpeg")
        }
        return false
    }

    /// Retorna somente arquivos JPEG cujo handle ainda não foi processado.
    func filterNewJPEGFiles(_ items: [ICCameraItem]) -> [ICCameraFile] {
        var result: [ICCameraFile] = []
        for item in items {
            guard !key(for: item).isEmpty else { continue }
            guard isJPEG(item) else { continue }
            guard !processedHandles.contains(key(for: item)) else { continue }
            if let file = item as? ICCameraFile {
                result.append(file)
            }
        }
        return result
    }
}
