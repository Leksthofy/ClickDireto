# Análise técnica do Evoto Instant 1.8.1 (APK) — engenharia reversa de comportamento

Data: 29/10/2026 — análise estática local (sem descompilador JADX; inspeção de bundle, dumps de strings de dex e libs nativas).
Escopo: compreender a **arquitetura funcional** de captura vinculada. Nenhum código, ícone, UI ou identidade do Evoto foi copiado.
Arquivo analisado: `Evoto+Instant_1.8.1_APKPure (1).xapk` (380 MB; bundle APKPure).

## 1. Ficha do pacote

- Pacote: `ai.evoto.instant.capture`, versão 1.8.1 (versionCode 82), minSdk 28, targetSdk 35.
- Composição: APK base (94 MB) + libs arm64 (45 MB) + assets de instização (256 MB).
- Tecnologia de UI: **Flutter** (`libflutter.so` + `libapp.so` AOT Dart), vídeo com ijkplayer.
- Crashreport: Sentry. Pagamento: Google Play Billing. Biometria: USE_BIOMETRIC.
- Permissões relevantes do manifest: `USB_PERMISSION`, `WAKE_LOCK`, `READ_MEDIA_IMAGES`,
  `WRITE_EXTERNAL_STORAGE`, `INTERNET`, `ACCESS_WIFI_STATE`/`CHANGE_WIFI_STATE`, `FOREGROUND_SERVICE`.

## 2. Achado central: pilha PTP própria sobre USB Host (Java/Kotlin)

O núcleo de câmera **não é** Flutter, nem rede, nem CCAPI: é um SDK nativo Android empacotado em
`com.truesight.cameraptp` (package não-ofuscado), implementando **PTP cru sobre a Android USB Host API**
classes confirmadas nos dumps: `android/hardware/usb/UsbDeviceConnection`, `UsbEndpoint`, `UsbRequest`,
`UsbManager` → transações **bulk** de baixo nível (não via `android.mtp.MtpDevice` para o fluxo principal).

## 3. Arquitetura confirmada pelo dump de classes

- **Câmara genérica**: `ptp/PtpCameraControl` com `Camera$CameraListener`, `Camera$ImageListener`,
  `Camera$ImageReceivedCallback`, `Camera$ConnectedCameraInfo`, `PtpActionQueue`, `CommandWorker`,
  `InterruptEventLoop` (laço de leitura de **eventos de interrupção PTP** — equivalente ao `didAddItem` do iOS).
- **Constantes PTP completas**: `PtpConstants$Event`, `$Operation`, `$ObjectFormat`, `$Property`,
  `$VendorExtensionID`, `$Response` (= protocolo PTP/MTP implementado do zero).
- **Módulo por fabricante** (cada câmera tem dialeto PTP próprio):
  - `CanonCameraControl` + 25+ classes `commands/canon/*`:
    `CanonOpenSessionAction`, **`CanonEventCheckCommand`** (polling de eventos Canon),
    `CanonGetImageAction`, `CanonGetObjectInfoCommand`, `CanonGetRequestOLCInfoGroupCommand`,
    `CanonRequestInnerDevelopStart/EndCommand` (revelação interna de RAW no firmware — usado p/ preview),
    `CanonGetThumbImageAction`, `CanonGetLiveViewCommand` (live view por cabo!), `CanonTakePictureCommand`
    (disparo remoto), `CanonPcModeCommand` (modo PC da Canon), `CanonNoSdcardAction` (captura sem SD),
    `CanonSetPcHddCapacityCommand`.
  - Nikon (medição em SDRAM, live view), Sony (PTP **e** MTP, `SonyMtpToggleModeCommand` — trocam
    PTP↔MTP no firmware), Fuji (`FujiEventCheckCommand`), Panasonic, Olympus, Leica, Ricoh, Hasselblad
    (`bDisableHasselbladTethering` — flag interna de tethering).
- **Detecção de nova foto**: comandos `*RetrieveAddedObjectInfoAction` + `GetObjectHandlesCommand`
  → dedupe por handle + `GetObjectCommand`/`GetImageInChunksAction` (download em pedaços).
- `CanonEventCheckCommand` (canon/), `NikonEventCheckCommand`, `SonyEventCheckAction`, `FujiEventCheckCommand`
  e `RicohRetrieveAddedObjectInfoAction` → padrão de polling de eventos **pos-abertura de sessão**,
  não em momentos aleatórios.

## 4. `libinstant_sdk.so` (58 MB) — papel

Nativo pesado com tabela de câmeras/lente (604 menções "Canon": dicionário de corpos EOS/PowerShot e
lentes via EXIF, curvas 3DLUT por modelo como "Canon EOS R5 3DLUT-Strand", `EOS Kiss X10`, etc.),
edit de cores, *"instant"* = processamento local de preview/estilo no Android. Com `proteção virbox`
(libvirbox64). **Não é** canal de comunicação com a câmera — a comunicação está em Java (`cameraptp`).

## 5. Fluxo reconstruído (comportamento)

1. Usuário conecta câmera por cabo → app solicita `UsbManager.requestPermission` (prompt nativo).
2. `USB_PERMISSION` dado → enumera `UsbDeviceConnection` → bidi bulk endpoints → PTP cru.
3. `GetDeviceInfo` → identifica fabricante (vendor extension/nome) → seleciona módulo (Canon/Nikon/...).
4. Abre sessão PTP (`OpenSessionCommand`) → inicia `InterruptEventLoop`/`*EventCheckCommand` em thread.
5. Evento OBJECT_ADDED ≠ possível varia por marca → valida via `RetrieveAddedObjectInfoAction`/relise de handles.
6. Dedupe (por handle) → `GetObjectCommand`/`GetImageInChunksAction` (grande em pedaços; thumbnail à parte).
7. Salva local; cola no pipeline visual (Flutter) via callback `Camera$ImageListener`.
8. Lazy list: `GetThumbCommand` para thumbnails; original só sob demanda/edição.

## 6. Implicações para o ClickDireto/Instantâneo

| Ponto | Conclusão |
|---|---|
| Meio de captura vinculada | **Cabo USB + PTP cru**, não CCAPI, não nuvem, não Wi-Fi para o fluxo principal |
| Evento de nova foto | Eventos PTP (interupt) + verificação por marca — exatamente a família de mecanismo que usamos (ImageCaptureCore no iOS / MtpDevice+eventos ou PTP cru no Android) |
| Formato de download | JPEG original **ou** versão "reduce/partial" (deliver rápido + qualidade depois) |
| Live view | Implementado por cabo para Canon/Nikon/Sony/etc (recurso de tethering clássico, não obrigatório p/ nosso v1) |
| Lições aplicáveis | (a) dedupe por handle é padrão; (b) download em chunks; (c) módulo por fabricante, começando por Canon; (d) erro→pós sessão, fila de ações PTP **serial** (uma transação por vez) |

## 7. Limitações da análise

- Sem JADX: não extraimos bytecode/instruções nem valores de opcode PTP canon exatos (0x90xx etc.) de cada comando; a conclusão vem de **nomes de classes**, **strings de log** e **estrutura** — suficiente em nível de comportamento/arquitetura.
- `libapp.so` (Dart AOT): strings são bytecode AOT, não legível facilmente; UI/negócio não foi objeto-alvo (e é o que o brief proíbe copiar).
- Não rodamos o app; nada aqui valida comportamento em runtime — só arquitetura estática.

## 8. Resposta às 9 perguntas do brief (§2)

1. **Arquitetura geral** — Flutter + SDK Java PTP (`com.truesight.cameraptp`) + nativos de imagem.
2. **Tecnologia de câmera** — Android USB Host API, PTP/IP? **Não**: PTP sobre USB (bulk), + fallback **MTP** (Sony), sem massa de dados (Mass Storage) visível.
3. **Detecção/permissão/sessão** — `UsbManager.requestPermission` com action `USB_PERMISSION`; sessão PTP aberta uma vez; `CommandWorker` + `PtpActionQueue` mantêm a fila viva; ec interrupted-lende o loop de eventos.
4. **Imagens após disparo físico** — eventos PTP (`InterruptEventLoop`, `CanonEventCheckCommand`) → handles → `GetObject`.
5. **Mecanismo de detecção** — eventos + reconsulta de handles; **não polling cego** estrutural (há verificação por marca, mas guiada por eventos/estados).
6. **Novo vs repetido** — dedupe por `objectHandle` + cache EXIF (`ExifDataCache`).
7. **JPEG enquanto câmera opera** — sim; `CanonGetImageAction`/chunks descarregam sem fechar sessão.
8. **Erros/reconexão/filas/UI** — fila de ações PTP serial (`PtpActionQueue`, `PtpActionWaitBusy`), `ConnectFailedReason`, estados em `PtpCameraControl$State`, logs `TsLog`; UI Flutter consome callbacks.
9. **Essencial vs comercial** — essencial: PTP/USB + fila + eventos + storage. Comercial (separável): Billing, login/assinatura, edição IA `libinstant_sdk`, Sentry, anúncios/ads-id, biometria, busca de atualizações (BootCompleted).
