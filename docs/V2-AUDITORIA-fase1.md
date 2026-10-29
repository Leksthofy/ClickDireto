# Auditoria Fase 1 — V2 do repo real (mapeamento honesto código ↔ briefing)

Data: 29/10/2026. Referência: brief "INSTANTÂNEO V2" (§3 audit A–G; §5 módulos; §6 CCAPI; §12 prioridade).
Escopo: repositório real `https://github.com/Leksthofy/ClickDireto` — iOS PoC (Swift/SwiftUI, ImageCaptureCore).

## 0. Desalinhamento detectado FIRST (transparência)

O briefing V2 Seção 3 menciona módulos "encontrados no histórico técnico do projeto":
`CameraEventMonitor`, `CanonCCAPIClient`, `PhotoDownloader`, `StatusDashboardView`,
backend/endpoints, auth, admin, banco de dados, env vars.

**Verdade do repo (chequei arquivo por arquivo — glob + listagem):**
| Nome no briefing | Existe? | Nome real no repo |
|---|---|---|
| CameraEventMonitor | parcial | `ClickDireto/Camera/CaptureEventMonitor.swift` (dedupe por objectHandle) |
| PhotoDownloader | parcial | `ClickDireto/Services/JPEGTransferService.swift` (requestDownloadFile) |
| StatusDashboardView | parcial | `ClickDireto/Views/HomeView.swift` (UI pré-V2) |
| PhotoStorageManager | parcial | `ClickDireto/Services/PhotoLibraryWriter.swift` (PhotoKit) |
| ConnectionDiagnostics | ✓ | `ClickDireto/Diagnostics/ConnectionDiagnostics.swift` |
| AppState | ✓ | `ClickDireto/App/AppState.swift` (estados de conexão) |
| CanonCCAPIClient | **não** | n/a |
| Backend / endpoints / auth / admin / banco | **não** | n/a |

**Não há backend, servidor, banco de dados, admin nem CCAPI neste repo.** O projeto é 100% local,
iOS, cabo + ImageCaptureCore + PhotoKit — arquitetura coerente com o objetivo offline do brief §6
("não envie imagens a servidores externos"; §1 "sem nuvem"). Pergunta aberta ao usuário: os módulos
/backend citados vêm de **outro projeto** (template de outro contexto) ou são desejos para o V2?
Enquanto isso, não vou inventar esses módulos — política do projeto: nada fabricado.

## A. Funcionalidades concluídas e comprovadas (com evidência física real)

1. **Detecção USB/protocolo**: R8 enumerada via ZHQ-11 (vendor USB 1193), teste físico 28/10 ✓
2. **Sessão PTP aberta e catálogo lido**: 2.402 itens listados ✓ (log do app)
3. **Dedupe sem importação em massa**: 2.402 marcados processados, **zero** downloads disparados ✓
4. **Fila/transferência/PhotoKit**: compilados no build CI (Xcode 26.6 / iOS 26.5), **mas não validados no hardware** — só que o pipeline código está integrado (requestDownloadFile→PhotoKit). Classifico A‑parcial: implemented, **not physically proven**.
5. **IPA construída e instalada no iPhone por Sideloadly** ✓ (usuário confirmou abertura e conexão)

## B. Parcialmente implementadas

- **Detecção de nova foto por evento** (`CaptureEventMonitor` + `didAddItem` ICC): código pronto;
  **o teste com disparo físico (Teste B) ainda não aconteceu** — é o único bloqueio decisivo.
- **Capability check "shutter-while-connected"**: logado na última .ipa (aguardando retest → ler se true/false).
- **Fila de transferência**: JPEGTransferService é serial 1:1; sem fila reprovável para múltiplsa fotos simultâneas (reenvio/latência não medidos).

## C. Somente simulação

- Nada falso intencional. Estados do AppState refletem callbacks reais ICC.
- UI HomeView é **painel de diagnóstico** (texto/log), não a UI-hero do brief §8. Não há fotografia hero.

## D. Erros identificados

1. `requestTakePicture()`/`deviceDidChangeName` iOS-unavailable — **corrigido** (removidos; comprovado por compilador SDK 26.5).
2. Delegates: `didRemove:moreGoing:` — **corrigido**.
3. `ICDeviceTypeMask.camera` gerekli (não array) — **corrigido**.
4. UI atual não distingue "conectado" de "pronto para fotos" — precisa divisão de estados do brief §8 (após Teste B).
5. Sem medição de latência/media por foto (§7 "registrar horário e resultado") — ConnectionDiagnostics existe mas não grava latência/agregados ainda.

## E. Dependências de hardware/permissão/serviços

- Equipamento: Canon EOS R8 + cabo USB‑C↔USB‑A + H'Maston ZHQ‑11 Lightning OTG (funcionais ✓).
- iOS: ImageCaptureCore (iOS 13+, API pública) e PhotoKit; NSPhotoLibraryAddUsageDescription/NSPhotoLibraryUsageDescription ✓.
- Sem rede (app 100% offline) ✓; sem nuvem ✓; sem CCAPI ✓ (CCAPI é rede/Wi‑Fi e **não** cabe no requisito cabo — decisão documentada §6 do brief: não substituir cabo por Wi‑Fi).
- Instalação: Sideloadly + Apple ID gratuita (perfil 7 dias; "Confiar" necessário).

## F. Correções necessárias (por prioridade, brief §12)

1. **P1 — fechamento do laço do hardware**: teste do disparo físico (didAddItem + capacidade + Fotos app). Sem isso nada mais importa.
2. **P1 — fila de transferência multi-foto** (PhotoProcessingQueue do brief §5-D): serialização ordenada, retry, estados "Restaurando/Salvando/Concluído".
3. **P1 — medição** (brief §7): timestamp por foto (detectada → baixada → salva) → somar latência média e exibir no Diagnóstico.
4. **P2 — UI V2**: tema #090A0F/#14161F/#F5B942, foto hero, miniaturas, contador, álbum "ClickDireto" (PhotosKit: album need create? PhotoKit compartilhado permission), estados visuais do brief §8.
5. **P3 — presets** (brief §7) — só depois de A–G validados; formato próprio documentado (não prometer Lightroom/XMP).

## G. Recursos a preservar (já funcionam e não tocar)

- CameraConnectionManager: browser + sessão + capa de capability logging.
- CaptureEventMonitor: dedupe objectHandle (proven 2.402 sem duplicação).
- JPEGTransferService.requestDownloadFile + selector didDownloadFile:error:options:contextInfo.
- PhotoLibraryWriter com placeholderForCreatedAsset (não sobrescreve; verifica erro antes de "salvo").
- ConnectionDiagnostics (estrutura para latência/erro).
- CI: XcodeGen workflows build.yml (validação) e ipa.yml (artefato) — não quebrar.

## 8. Contrato de honestidade (brief §14)

- Não declarar Teste B/C/D/G como validados sem relato do hardware.
- Marcação atual (29/10): **A, E/G (detecção+catalogo+dedupe+instalação) = validados em física;
  B (primeira captura), C/D (múltiplas/continuidade), F (reconexão) e integração Fotos = PENDENTES retest.**
