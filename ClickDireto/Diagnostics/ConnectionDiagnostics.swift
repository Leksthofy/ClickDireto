//
//  ConnectionDiagnostics.swift
//  ClickDireto
//
//  Diagnóstico e métricas: log textual, contador de sucesso e latência média
//  por captura (do didAddItem do controle ao salvar no PhotoKit).
//

import Foundation

final class ConnectionDiagnostics {

    private struct Measurement {
        let addedAt: Date
    }

    private let queue = DispatchQueue(label: "ClickDireto.diagnostics")
    private let appState: AppState   // usado apenas via DispatchQueue.main
    private(set) var successCount: Int = 0
    private var measurements: [String: Measurement] = [:]
    private var latencySamples: [Double] = []

    init(appState: AppState) {
        self.appState = appState
    }

    // MARK: - Log

    func log(_ message: String) {
        let line = "\(Self.timestamp()) [ClickDireto] \(message)"
        DispatchQueue.main.async { [weak self] in
            self?.appState.appendLog(line)
        }
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: Date())
    }

    // MARK: - Métricas

    func registerAdded(handleKey: String) {
        queue.async { [weak self] in
            self?.measurements[handleKey] = Measurement(addedAt: Date())
        }
    }

    func logLatency(handleKey: String, bytes: Double) {
        queue.async { [weak self] in
            guard let self else { return }
            self.successCount += 1
            var latency: Double?
            if let addedAt = self.measurements.removeValue(forKey: handleKey)?.addedAt {
                latency = Date().timeIntervalSince(addedAt)
                self.latencySamples.append(latency!)
                if self.latencySamples.count > 200 {
                    self.latencySamples.removeFirst(self.latencySamples.count - 200)
                }
            }
            let average = self.latencySamples.reduce(0, +) / Double(self.latencySamples.count)
            let message = String(format: "OK #%d %@ — %.1f KB — latência %.2f s (média %.2f s)",
                                 self.successCount,
                                 handleKey,
                                 bytes / 1024,
                                 latency ?? -1,
                                 average)
            DispatchQueue.main.async {
                self.appState.appendLog(message)
                self.appState.updateAverageLatency(average)
            }
        }
    }
}
