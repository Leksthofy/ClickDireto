//
//  HomeView.swift
//  ClickDireto
//
//  Tela única, funcional e sem enfeite: estado, contagem, última foto,
//  indicador de permissão de Foto e o log de diagnóstico.
//

import SwiftUI
import Photos

struct HomeView: View {
    @ObservedObject var appState: AppState
    let onStart: () -> Void
    let onStop: () -> Void
    let onTestCapture: () -> Void
    let onRefreshAuthorization: () -> Void

    private func phaseLabel(for phase: ConnectionPhase) -> String {
        switch phase {
        case .idle: return "Parado"
        case .browsing: return "Verificando (procurando câmera)…"
        case .authorizing: return "Aguardando permissão de acesso à câmera…"
        case .connected: return "Conectado — fotografe pelo botão da câmera"
        case .receivingPhoto: return "Recebendo foto…"
        case .error(let message): return "Erro: \(message)"
        }
    }

    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Circle()
                        .fill(phaseDotColor)
                        .frame(width: 14, height: 14)
                    Text(phaseLabel(for: appState.phase))
                        .font(.headline)
                }

                if let cameraName = appState.cameraName {
                    Text("Câmera: \(cameraName)")
                    if let ids = appState.cameraUSBIDs {
                        Text(ids).font(.caption).foregroundColor(.secondary)
                    }
                }

                Text("Fotos recebidas: \(appState.photosReceived)")
                if let last = appState.lastSavedFilename {
                    Text("Última foto: \(last)").font(.caption)
                }
                if let latency = appState.averageLatencySeconds {
                    Text(String(format: "Latência média por foto: %.2f s", latency))
                        .font(.caption)
                }

                Text(photoPermissionLabel(status: appState.photoLibraryStatus))
                    .font(.caption)
                    .foregroundColor(photoPermissionColor(status: appState.photoLibraryStatus))

                HStack(spacing: 10) {
                    Button("Conectar") { onStart() }
                        .buttonStyle(.borderedProminent)
                    Button("Desconectar") { onStop() }
                        .buttonStyle(.bordered)
                    Button("Testar recebimento") { onTestCapture() }
                        .buttonStyle(.bordered)
                }
                Button("Reverificar permissão de Foto") { onRefreshAuthorization() }
                    .font(.caption)

                Divider()

                Text("Log de diagnóstico")
                    .font(.subheadline.bold())
                ScrollView {
                    Text(appState.logLines.joined(separator: "\n"))
                        .font(.system(size: 11, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding()
            .navigationTitle("ClickDireto")
        }
        .navigationViewStyle(.stack)
    }

    private var phaseDotColor: Color {
        switch appState.phase {
        case .connected: return .green
        case .receivingPhoto: return .blue
        case .error: return .red
        default: return .orange
        }
    }

    private func photoPermissionLabel(status: PHAuthorizationStatus) -> String {
        switch status {
        case .authorized: return "Permissão de Foto: autorizado (pode salvar)."
        case .limited: return "Permissão de Foto: limitada — autorize integralmente."
        case .denied: return "Permissão de Foto: negada — conceda em Ajustes > Privacidade."
        case .restricted: return "Permissão de Foto: restrita pelo sistema."
        case .notDetermined: return "Permissão de Foto: ainda não solicitada."
        @unknown default: return "Permissão de Foto: Desconhecido."
        }
    }

    private func photoPermissionColor(status: PHAuthorizationStatus) -> Color {
        status == .authorized ? .green : .orange
    }
}
