//
//  HomeView.swift
//  ClickDireto
//
//  V2 — tela de operação: foto em destaque ocupando a maior área possível,
//  estados reais da conexão (sem “captura vinculada ativa” antes de haver
//  capturas recebidas), contador da sessão e diagnóstico acessível por aba.
//

import SwiftUI
import Photos

// Paleta V2 (briefing de identidade visual)
private extension Color {
    static let cdBackground = Color(red: 0x09/255, green: 0x0A/255, blue: 0x0F/255)
    static let cdSurface    = Color(red: 0x14/255, green: 0x16/255, blue: 0x1F/255)
    static let cdBorder     = Color(red: 0x25/255, green: 0x28/255, blue: 0x37/255)
    static let cdGold       = Color(red: 0xF5/255, green: 0xB9/255, blue: 0x42/255)
    static let cdText       = Color(red: 0xEC/255, green: 0xEE/255, blue: 0xF2/255)
    static let cdTextDim    = Color(red: 0x9A/255, green: 0xA2/255, blue: 0xB2/255)
    static let cdOk         = Color(red: 0x3E/255, green: 0xC9/255, blue: 0x7A/255)
    static let cdFail       = Color(red: 0xF0/255, green: 0x6B/255, blue: 0x5E/255)
}

struct HomeView: View {
    @ObservedObject var appState: AppState
    let onStart: () -> Void
    let onStop: () -> Void
    let onTestCapture: () -> Void
    let onRefreshAuthorization: () -> Void

    @State private var showingDiagnostics = false

    var body: some View {
        ZStack {
            Color.cdBackground.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                statePill
                heroArea
                sessionRow
                if !appState.thumbnails.isEmpty { thumbnailRow }
                Spacer(minLength: 0)
                controls
                permissionHint
                logShortcut
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showingDiagnostics) { DiagnosticsSheet(appState: appState) }
    }

    // MARK: - Cabeçalho

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "camera.aperture")
                .font(.system(size: 26, weight: .semibold))
                .foregroundColor(.cdGold)
            VStack(alignment: .leading, spacing: 0) {
                Text("ClickDireto")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(.cdText)
                Text("Entrega instantânea por cabo")
                    .font(.caption2)
                    .foregroundColor(.cdTextDim)
            }
            Spacer()
            if appState.photosReceived > 0 {
                Text("\(appState.photosReceived)")
                    .font(.system(.title3, design: .rounded).bold())
                    .foregroundColor(.cdGold)
                    .accessibilityLabel("Fotos recebidas nesta sessão")
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
    }

    // MARK: - Estado da conexão (honesto)

    private var statePill: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(phaseDotColor)
                .frame(width: 10, height: 10)
            Text(phaseLabel(appState.phase))
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.cdText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let camera = appState.cameraName, phaseShowsCamera {
                Spacer()
                Text(camera)
                    .font(.caption)
                    .foregroundColor(.cdTextDim)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.cdSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Color.cdBorder, lineWidth: 1)
                )
        )
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    private var phaseShowsCamera: Bool {
        switch appState.phase {
        case .detected, .authorizing, .connected, .receivingPhoto, .savingPhoto: return true
        default: return false
        }
    }

    private func phaseLabel(_ phase: ConnectionPhase) -> String {
        switch phase {
        case .idle:            return "Desconectado"
        case .browsing:        return "Procurando câmera…"
        case .detected:        return "Câmera detectada"
        case .authorizing:     return "Aguardando autorização…"
        case .connected:
            return appState.photosReceived > 0
                ? "Captura vinculada ativa ✓"
                : "Conectada — pronto para fotografar"
        case .receivingPhoto:  return "Recebendo fotografia…"
        case .savingPhoto:     return "Salvando na galeria…"
        case .error(let msg):  return "Erro: \(msg)"
        }
    }

    private var phaseDotColor: Color {
        switch appState.phase {
        case .connected:        return .cdOk
        case .receivingPhoto:   return .cdGold
        case .savingPhoto:      return .cdGold
        case .error:            return .cdFail
        case .authorizing, .detected, .browsing: return .orange
        case .idle:             return .cdTextDim
        }
    }

    // MARK: - Foto em destaque

    private var heroArea: some View {
        Group {
            if let hero = appState.heroPhoto {
                Image(uiImage: hero)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .transition(.opacity)
                    .accessibilityLabel("Última fotografia recebida")
            } else {
                emptyHero
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .animation(.easeOut(duration: 0.25), value: appState.heroPhotoFilename)
    }

    private var emptyHero: some View {
        VStack(spacing: 14) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 44, weight: .light))
                .foregroundColor(.cdBorder)
            Text(emptyHeroMessage)
                .font(.headline)
                .foregroundColor(.cdTextDim)
                .multilineTextAlignment(.center)
        }
    }

    private var emptyHeroMessage: String {
        switch appState.phase {
        case .idle, .browsing:
            return "Conecte sua câmera para começar."
        case .detected:
            return "Câmera detectada. Autorize o acesso."
        case .authorizing:
            return "Autorize o acesso no iPhone…"
        case .connected:
            return "Câmera conectada.\nPronto para fotografar."
        case .receivingPhoto:
            return "Recebendo fotografia…"
        case .savingPhoto:
            return "Recebendo fotografia…"
        case .error:
            return "Algo falhou. Veja o diagnóstico."
        }
    }

    // MARK: - Identificação da sessão

    private var sessionRow: some View {
        VStack(spacing: 4) {
            if let last = appState.lastSavedFilename {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.seal.fill").font(.caption).foregroundColor(.cdOk)
                    Text("Foto salva na galeria — \(last)")
                        .font(.caption)
                        .foregroundColor(.cdTextDim)
                        .lineLimit(1)
                    Spacer()
                }
            }
            if let latency = appState.averageLatencySeconds {
                HStack(spacing: 6) {
                    Image(systemName: "gauge.with.needle")
                        .font(.caption2)
                        .foregroundColor(.cdTextDim)
                    Text(String(format: "Latência média: %.2f s (detecção → galeria)", latency))
                        .font(.caption2)
                        .foregroundColor(.cdTextDim)
                    Spacer()
                }
            }
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Miniaturas

    private var thumbnailRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(appState.thumbnails.indices, id: \.self) { index in
                    Image(uiImage: appState.thumbnails[index])
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 46, height: 46)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(index == 0 ? Color.cdGold : Color.cdBorder,
                                              lineWidth: index == 0 ? 2 : 1)
                        )
                        .onTapGesture {
                            appState.heroPhoto = appState.thumbnails[index]
                        }
                }
            }
            .padding(.horizontal, 16)
        }
        .frame(height: 56)
        .padding(.top, 6)
    }

    // MARK: - Controles

    private var controls: some View {
        VStack(spacing: 10) {
            if appState.phase == .idle || isSessionEnded {
                Button(action: onStart) {
                    Label("Iniciar sessão", systemImage: "camera.badge.ellipsis")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.cdGold)
                        .foregroundColor(.black)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
            } else {
                Button(action: onStop) {
                    Label("Encerrar sessão", systemImage: "stop.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.cdSurface)
                        .foregroundColor(.cdText)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .strokeBorder(Color.cdBorder, lineWidth: 1)
                        )
                }
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 16)
        .animation(.easeInOut(duration: 0.2), value: isSessionEnded)
    }

    private var isSessionEnded: Bool {
        if case .error = appState.phase { return true }
        return appState.phase == .idle || appState.phase == .browsing
    }

    private var permissionHint: some View {
        Group {
            if appState.photoLibraryStatus != .authorized {
                HStack(spacing: 6) {
                    Image(systemName: "lock.shield")
                        .font(.caption2)
                        .foregroundColor(.cdGold)
                    Text(photoPermissionLabel(appState.photoLibraryStatus))
                        .font(.caption2)
                        .foregroundColor(.cdTextDim)
                    Button("Verificar") { onRefreshAuthorization() }
                        .font(.caption2.bold())
                        .foregroundColor(.cdGold)
                }
            }
        }
        .padding(.top, 6)
    }

    private var logShortcut: some View {
        Button {
            showingDiagnostics = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "terminal")
                Text("Diagnóstico da sessão")
            }
            .font(.caption)
            .foregroundColor(.cdTextDim)
        }
        .padding(.top, 2)
        .padding(.bottom, 12)
    }

    private func photoPermissionLabel(_ status: PHAuthorizationStatus) -> String {
        switch status {
        case .authorized:   return "Galeria autorizada."
        case .limited:      return "Galeria limitada — autorize integralmente."
        case .denied:       return "Galeria negada — libere em Ajustes > Privacidade."
        case .restricted:   return "Galeria restrita pelo sistema."
        case .notDetermined: return "Galeria ainda não solicitada."
        @unknown default:   return "Estado desconhecido."
        }
    }
}

// MARK: - Aba de diagnóstico (log técnico completo)

struct DiagnosticsSheet: View {
    @ObservedObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ZStack {
                Color.cdBackground.ignoresSafeArea()
                VStack(alignment: .leading, spacing: 8) {
                    if let ids = appState.cameraUSBIDs {
                        Text(ids).font(.caption).foregroundColor(.cdTextDim)
                    }
                    ScrollView {
                        Text(appState.logLines.joined(separator: "\n"))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(Color(red: 0.75, green: 0.78, blue: 0.82))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding()
            }
            .navigationBarTitle("Diagnóstico", displayMode: .inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fechar") { dismiss() }
                }
            }
        }
        .navigationViewStyle(.stack)
        .preferredColorScheme(.dark)
    }
}
