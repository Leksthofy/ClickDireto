# ClickDireto

App iOS nativo (Swift + SwiftUI) que transfere automaticamente para o app Foto do iPhone
as fotos JPEG tiradas em uma **Canon EOS R8** conectada **por cabo USB** — sem Wi-Fi,
sem Bluetooth, sem serviço pago, sem internet.

**Arquitetura (API pública da Apple):** ImageCaptureCore (iOS 13+, PTP por cabo) +
PhotoKit (salvar JPEG byte-a-byte).

## Estrutura

```
project.yml                       ← definição XcodeGen (gera o .xcodeproj no macOS)
ClickDireto/
  App/ClickDiretoApp.swift        ← ponto de entrada SwiftUI
  App/AppState.swift              ← estado observável da UI
  Camera/CameraConnectionManager.swift   ← ICDeviceBrowser + sessão + ICCCameraDeviceDelegate
  Camera/CaptureEventMonitor.swift       ← dedupe por ptpObjectHandle (não duplica fotos antigas)
  Services/JPEGTransferService.swift     ← ICC requestDownloadFile (sem recompressão)
  Services/PhotoLibraryWriter.swift      ← PHAssetCreationRequest (app Foto)
  Diagnostics/ConnectionDiagnostics.swift← log + latência média por captura
  Views/HomeView.swift            ← tela única funcional
docs/FASE-01-relatorio-viabilidade.md
```

## Fluxo previsto no aparelho

1. Canon R8 em **Ajustes → Comunicação → Escolher app de conexão USB → "Importação de
   fotos/Controle remoto"** (modo PTP — mesma foto que o app Foto do iOS usa).
2. Cabo dados USB-A↔USB-C + adaptador OTG Lightning + iPhone.
3. Abrir ClickDireto → tocar **Conectar** → autorizar câmera e app Foto.
4. Disparar pelo botão físico da câmera → JPEG chega por cabo e é salvo automaticamente
   no app Foto (aparece no log com latência).

## Caminho de compilação (sem Mac próprio)

Repositório: **https://github.com/Leksthofy/ClickDireto**

1. O GitHub Actions compila automaticamente em cada envio:
   - Workflow `build` — validação de compilação (simulador).
   - Workflow `ipa` — gera o **`ClickDireto-unsigned.ipa`** para download
     (aba *Actions* → execução mais recente → *Artifacts*).
2. Instalação no iPhone pelo Windows: abra o `.ipa` baixado no
   [Sideloadly](https://sideloadly.io) com uma Apple ID gratuita
   (perfil válido por 7 dias; renovar rodando de novo).
3. No iPhone: Ajustes → Privacidade e segurança → **Modo desenvolvedor** → ativar uma vez.

## Restrições respeitadas

- Sem Wi-Fi/Bluetooth para transportar imagens; somente cabo.
- Nunca usa `.deleteAfterSuccessfulDownload` — o cartão da câmera não é modificado.
- Não recomprime o JPEG original (bytes preservados até o PhotoKit).
- Itens preexistentes no cartão não são reimportados (dedupe por handle PTP).
- Executa em primeiro plano (iOS suspende o app em segundo plano — limitação documentada)
