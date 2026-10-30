# TRANSFERÊNCIA TÉCNICA COMPLETA — Projeto ClickDireto (iOS) | Captura vinculada Canon EOS R8 → iPhone
Data do estado: 29/10/2026 — preparado para análise por outro engenheiro/IA (Claude Code)
Repositório: https://github.com/Leksthofy/ClickDireto (público, `main`, último commit `069bf57`)

---

## 1. OBJETIVO DO PRODUTO (o que precisa funcionar)

Fotógrafo profissional na rua (praias, pontos turísticos), atendendo clientes:
1. Conecta a **Canon EOS R8** ao **iPhone 14 Pro Max** por **cabo físico** (USB-C↔USB-A + adaptador OTG H'Maston ZHQ-11 Lightning).
2. Abre o app **ClickDireto** (nome preservado), inicia a sessão.
3. Continua trabalhando **normalmente com o botão físico da câmera** (obturador, foco, menus).
4. **Cada foto nova** dispara automaticamente: evento → download do JPEG original → exibição grande no app → **salvo no app Fotos do iOS, no álbum "ClickDireto"** → contador/latência atualizados → pronto para o próximo disparo.

### Regras inegociáveis do dono do projeto
- **Cabo somente.** Sem Wi-Fi, sem rede (a CCAPI da Canon é rede e está FORA por padrão), sem cloud, sem computador na operação diária.
- Nunca apagar nada do cartão SD. Nunca sobrescrever fotos. Sem recompressão de JPEG.
- Sem APIs privadas, sem jailbreak, sem App Store sem autorização do dono.
- **Honestidade absoluta**: nada de "sucesso" sem evidência física; separar simulado/testado; estados de UI não podem mentir (ex.: não mostrar "captura vinculada ativa" antes da 1ª foto realmente chegada).

---

## 2. O ESTADO ATUAL EM UMA FRASE (o problema aberto)

> O app abre a sessão ICC com a R8, lê o catálogo inteiro (2.413 itens, zero importações indevidas = dedupe comprovado), **recebe eventos de objetos** (`didAddItems`, lote IMG_9278–IMG_9304 comprovado no log), MAS **a câmera bloqueia fisicamente o disparo** durante nossa sessão: sem obturador, sem foco, sem nada — e o usuário NÃO pode fotografar. A causa exata ainda não foi isolada.

Comportamento paralelo normal: a LCD da câmera apaga mostrando ícone de "computador conectado" (comportamento nativo do firmware Canon em modo USB; igual no app Fotos, Capture One e Evoto).

---

## 3. HISTÓRICO CRONOLÓGICO COM EVIDÊNCIAS (resumo do que já foi provado)

| Data | Evento | Evidência |
|---|---|---|
| 28/10 | Teste físico 1: R8 reconhecida via ZHQ-11 (USB vendor 1193), sessão ICC aberta, catálogo enumerado: "Fotos já no cartão: 2402 — não serão importadas" — **dedupe comprovado, zero downloads** | log do app v0.1 |
| 28/10 | IPA construída por CI e instalada via Sideloadly (Apple ID gratuita, perfil 7 dias, "Confiar" necessário) | usuário confirmou |
| 29/10 ~10:29 | Reabertura do app: dispositivo adicionado → autorização de conteúdo `Authorized` → sessão aberta com sucesso | print do app (10:29) |
| 29/10 ~10:30 | `didAddItems` recebidos **em lote** (IMG_9278→IMG_9304, ~27 eventos/0,5s — filas de enumeração da cauda do catálogo); **`cameraDeviceCanTakePicture: false`**; catálogo 2413 itens; 0 fotos recebidas | print do app (10:30) — CAPACIDADE false registrada |
| 29/10 (tarde) | Teste com V2 recém-instalada (ícone novo, UI nova, permissão de galeria pedida corretamente): conexão ok, catálogo ok, "Conectada — pronto para fotografar" — **MAS usuário relata que a câmera fica TOTALMENTE travada** (não dispara, não foca, não opera) quando nossa sessão está aberta | relato verbal do usuário |
| — | Bateria da câmera apareceu laranja (baixa) em pelo menos um teste | foto da tela da R8 |

**CRÍTICO ainda não testado (teste diferencial):** abrir o app **Fotos nativo do iPhone** → aba Importar → com o mesmo cabo/modo → apertar o obturador. Se TRAVA também → a trava é do firmware/estado da câmera. Se FOTOGRAFA → a trava é causada por algo que NOSSO app faz na sessão ICC. **Este resultado muda toda a direção do trabalho e ainda não foi executado.**

### Menu USB da R8 (as 3 opções verificadas pelo usuário)
1. **"Import. fotos/control. remoto"** ← a usada hoje (necessária para apps de terceiros verem a câmera via ICC)
2. "Vídeos/Transferência" (só vídeos — não ajuda)
3. "App da Canon para iPhone" (para o app oficial Camera Connect — provavelmente inacessível a apps de terceiros; teste pendente T3)

---

## 4. STACK ARQUITETURAL

- **iOS 16.0+, Swift 5, SwiftUI, sem dependências externas.**
- **ImageCaptureCore** (API pública da Apple) para descoberta/sessão/dados da câmera via USB.
- **PhotoKit** (Photos framework) para salvar no app Foto (álbum "ClickDireto").
- Instalação: Sideloadly (Windows) + Apple ID gratuita → *.ipa sem assinatura gerada por CI macOS.
- Build: **XcodeGen** (`project.yml` gera `ClickDireto.xcodeproj`); CI GitHub Actions em macOS (Xcode 26.6 / SDK iOS 26.5):
  - `.github/workflows/build.yml` — validação (simulador) a cada push
  - `.github/workflows/ipa.yml` — gera `ClickDireto-unsigned.ipa` (Release-iphoneos, CODE_SIGNING_ALLOWED=NO) por workflow_dispatch
- Ambiente do desenvolvedor: **Windows 11** (não há Mac local). Toda compilação é por CI.

### Árvore do código (caminhos reais)
```
ClickDireto/
  project.yml                       # XcodeGen: br.clickdireto.app, iOS 16.0, ícone AppIcon, versão 2.0.0 (build 2)
  ClickDireto/
    App/
      ClickDiretoApp.swift          # entrada; monta AppState + CameraConnectionManager + HomeView
      AppState.swift                # estado observável (fase, câmera, contador, foto-hero, miniaturas, log)
    Camera/
      CameraConnectionManager.swift # NÚCLEO: ICDeviceBrowser + sessão + todos os delegates ICC + fila serial do pipeline
      CaptureEventMonitor.swift     # dedupe por ptpObjectHandle (nunca reimportar o que já estava no cartão)
    Services/
      JPEGTransferService.swift     # requestDownloadFile + delegate didDownloadFile:error:... ; bytes originais
      PhotoLibraryWriter.swift      # PHAssetCreationRequest + criação/uso do álbum "ClickDireto"
    Views/
      HomeView.swift                # UI V2: foto-hero, miniaturas, estados honestos, aba de diagnóstico
    Diagnostics/
      ConnectionDiagnostics.swift   # log textual + latência por foto (detectada→salva) + média
    Assets.xcassets/
      AppIcon.appiconset/           # ícone original (obturador dourado, gerado)
  docs/                             # 6 relatórios (viabilidade, estratégia Android, análise APK Evoto, auditoria, diagnóstico)
```

### Fluxo de dados implementado (para orientar a leitura do código)
```
ICDeviceBrowser(didAdd device) → requestContentsAuthorization → (prompt iOS)
→ requestOpenSession → [deviceDidOpenSessionWithError]
→ didAddItems(em lote, pré-catálogo)  ⚠️ ignorados até catálogo completo (isReady=false)
→ deviceDidBecomeReady(withCompleteContentCatalog:)  →  marca TODOS os handles existentes como processados
loga: cameraDeviceCanTakePicture (false, apenas diagnóstico; requestTakePicture é macOS-only e NÃO é usado)
→ estado .connected ("Conectada — pronto para fotografar")
[usuário aperta obturador físico] → cameraDevice(_:didAddItems:/didAdd item:) → CaptureEventMonitor
filtra JPEGs com handle novo → pipelineQueue (serial FIFO) → requestDownloadFile
→ didDownloadFile → valida bytes>0 → PhotoLibraryWriter.saveJPEG (álbum "ClickDireto")
→ só APÓS confirmação: marca processado, calcula latência, publica foto-hero+miniatura, contador++, remove temp
```

---

## 5. O QUE JÁ ESTÁ COMPROVADO / O QUE NÃO ESTÁ (honesto)

**Comprovado em equipamento real:**
- Detecção do USB: vendor 1193, sessão abre, autorizações concedidas.
- Catálogo enumerado (2413 itens) sem importar nada — dedupe 100% funcional.
- Canal de **eventos** vivo (lote didAddItems comprovado).
- Instalação por Sideloadly; app abre; UI V2 com ícone e tema; permissão de galeria pedida.
- Dedupe não reimporta arquivos antigos jamais.

**Comprovadamente ABERTO/PROBLEMÁTICO (o porquê desta transferência):**
1. **A câmera trava o disparo físico com nossa sessão aberta** (relato do usuário; sem teste comparativo com o app Fotos ainda).
2. **Nenhuma foto nova foi transferida até agora** — o passo obturador→didAddItem→download→galeria nunca teve chance de rodar porque o disparo está bloqueado.
3. Latência/qualidade/álbum/continuidade: implementados, **não validados fisicamente** (não houve como).

**Classificação para o critério de aceite do projeto:**
- 1. Testado no físico: detecção, catálogo, dedupe, instalação.
- 2. Testado apenas em CI: toda a V2 (código compila; lógica não rodada em hardware).
- 3. Implementado esperando validação: fila serial, álbum, foto-hero, latência, estados.
- 4. Bloqueado por plataforma: requestTakePicture (macOS-only), PTP cru/comandos vendor, live view por cabo, Camera ConnectUSB para terceiros (provavelmente).

---

## 6. HIPÓTESES ATIVAS PARA A TRIA (ordenadas por probabilidade)

**H1 — Estado de "controle remoto" da Canon acionado pela sessão.**
A opção de menu "Import. fotos/control. remoto" combina dois comportamentos. É possível que a abertura de uma sessão ICC de terceiros faça o firmware entrar no ramo "remoto" (bloqueia obturador/foco esperando que o host comande o disparo) — comando que o ICC no iOS nunca enviará (requestTakePicture indisponível). O Evoto no Android resolve isso com comandos vendor (`CanonSetPcModeCommand`, `CaptureDestination`) — **impossíveis no iOS público**.
→ Teste que falsifica: app Fotos nativo (T1). Se ele mantém a câmera operável com o mesmo cabo/mode, resta descobrir a diferença entre o que o Fotos faz e o que fazemos.

**H2 — `requestContentsAuthorization`/prompt de autorização coloca a câmera em estado de bloqueio.**
Nosso fluxo pede `browser.requestContentsAuthorization` ANTES de `requestOpenSession`. O app Fotos (app-level, entitlement especial) pode abrir a sessão sem esse handshake e portanto **comportamento distinto no firmware**.
→ Experimento de código: abrir sessão SEM requestContentsAuthorization e ver comportamento e eventos (validation via app Foto).

**H3 — Bateria fraca bloqueando escrita/disparo.**
Ícone laranja confirmado. A Canon pode recusar disparo com USB host + carga insuficiente.
→ Teste: carrega cheia antes de tudo.

**H4 — Estado acumulado no firmware (cache de pareamento/sessão do app anterior).**
Usuário reinstalou múltiplas versões e sessões; a R8 pode estar memorizando sessão/autorização "suja".
→ Teste: reiniciar a câmera (power off/on) antes de cada teste; se persistir, reset de configurações de comunicação da câmera ou firmware update.

**H5 — Modo "App da Canon para iPhone" poderia funcionar.**
Se o ICC ainda enumerar a câmera nesse modo (provavelmente não), comportamento seria diferente (talvez operável).
→ Teste T3 descrito na seção 7.

**FALSAS PISTAS (já descartadas com evidência):**
- Tela preta/ícone de computador = NÃO é bug (comportamento do firmware; igual no app Fotos).
- `cameraDeviceCanTakePicture: false` = destaque de diagnóstico apenas; nosso fluxo não usa disparo remoto (iOS nem tem).
- Dedupe/enumeração = funcionam; não são a causa.

---

## 7. PROTOCOLO DE TESTES PENDENTES (executar na ordem; cada um 2–5 min)

**Pré-requisito de todos: bateria cheia (ou fonte); câmera desligada/ligada de novo antes de cada teste.**

- **T1 — Diferencial com o app Fotos (o mais importante):** cabo conectado, modo "Import. fotos/control. remoto", app **Fotos** do iPhone → Importar → selecionar a R8 → pressionar obturador 1×.
  - Travou? → problema é firmware/estado da câmera com apps iOS em geral (redireciona para H1/H3/H4 no lado da câmera).
  - Fotografou + foto apareceu na lista de importação? → a câmera fica operável no fluxo público; o bloqueio é algo do NOSSO fluxo (redireciona para H2; investigar ordem de chamadas ICC).
- **T2 — Nosso app em estado limpo:** câmera reinscrita (power cycle), abrir ClickDireto → Iniciar sessão → aguardar "pronto" → 1 disparo. Registrar: trava? log? (com comentários/eventos).
- **T3 — Modo "App da Canon para iPhone":** trocar modo, abrir ClickDireto: a câmera aparece? autoriza? dispara? (referência: se travar também aqui, o ICC é indiferente ao modo).
- **T4 — Referência oficial (opcional):** com modo 3, abrir Camera Connect e confirmar que a câmera dispara com session aberta lá (prova do limite do hardware).

**Resultado de T1/T2 → matriz de decisão:**
| T1 (Fotos) | T2 (ClickDireto) | Conclusão |
|---|---|---|
| trava | trava | firmware/estado da câmera; nosso app não é o causador; investigar bateria/mode/firmware |
| fotografou | trava | **nosso app muda o estado**; focar H2 (order de authorization/session) |
| fotografou | fotografou | problema resolvido; seguir 20 disparos (Teste C) |

---

## 8. O QUE PODE SER EXPERIMENTADO NO CÓDIGO (diretrizes para o próximo dev/IA)

Localização exata para mexer: `ClickDireto/Camera/CameraConnectionManager.swift` (função `tryOpenSession`, linha ~93) e o ciclo `didAdd device` (linha ~156).

1. **H2 — Ordem/ausência do contents authorization:** repetir o fluxo chamando `device.requestOpenSession()` DIRETO (sem `browser.requestContentsAuthorization { }`), ou pedir autorização APÓS a sessão abrir. Verificar se a câmera ainda enumera e se `didAddItems` continua chegando. Se a câmera fotografar, temos a correção.
2. **Sessão preguiçosa:** não abrir sessão no `didAdd`; abrir só depois de contagem/“priming” — improvável dado o evento ICC, mas testável.
3. **`shouldGetMetadataOf`/`shouldGetThumbnailOf`:** atualmente retornam `false` (refusar tudo). Experimentar retornar `true` para 1 item novo para ver se o firmware reage (suspeita baixa).
4. **Descobrir o que o app Fotos faz diferente:** se T1 mostrar câmera operável, comparar: (a) entitles/app-level; (b) sem contents authorization (Photos não pede); (c) não usa delegates de item; (d) pode estar no modo MTP vs PTP — no iOS não controlável, mas documentar.
5. **Verificação estática adicional do ICC no iOS:** conferir na documentação do SDK 26.5 se novas APIs iOS-16+ mudaram algo relevante (ex. `ICCameraDevice.requestSendFile`, sessão "ptp", `ICDeviceTypeMask`).}
 TODAS as assinaturas usadas hoje já foram verificadas: `deviceBrowser:didAddDevice:moreComing:`, `deviceBrowser:didRemoveDevice:moreGoing:`, `didRemove(device)`, `deviceDidBecomeReady(withCompleteContentCatalog:)`, `cameraDevice(_:didAdd:)`, `requestDownloadFile(_:options:downloadDelegate:didDownloadSelector:contextInfo:)`, selector `didDownloadFile:error:options:contextInfo:`.
6. **Escala de prioridade clara:** NÃO mexer em UI/análise/álbum até o disparo físico funcionar. O resto da V2 já está construído e compila.

**Regra do projeto:** não substituir função real por simulação; não trocar cabo por Wi-Fi sem decisão explícita do dono (a única saída conhecida se T1 = "trava" seria avaliar transferência via rede da câmera (FTP/CCAPI) — **decisão do dono, não implementem por conta própria**).

---

## 9. COMO COMPILAR E INSTALAR (referência)

- CI macOS Stage: `xcodegen generate` → `xcodebuild -project ClickDireto.xcodeproj -scheme ClickDireto -sdk iphoneos -configuration Release build CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO` → zipar `build/DerivedData/Build/Products/Release-iphoneos/ClickDireto.app` como `Payload/` → `.ipa`.
- No Windows: Sideloadly com Apple ID gratuita; no iPhone: Ajustes → Geral → VPN e Gerenc. de Dipositivos → Confiar; **Developer Mode ativo uma vez**.
- Versão atual: 2.0.0 (build 2), bundle `br.clickdireto.app`.

## 10. DOCUMENTAÇÃO ANTERIOR (ler na ordem)
1. `docs/FASE-01-relatorio-viabilidade.md` — por que ImageCaptureCore é o único caminho público no iOS (com verificação de docs Apple, endpoints JSON de referência).
2. `docs/V2-EVOTO-ANALISE-APK.md` — engenharia reversa de comportamento do Evoto (comprova: PTP cru + comandos vendor no Android; não implementável no iOS).
3. `docs/V2-AUDITORIA-fase1.md` — mapeamento do brief V2 ao repo real (o que existe/o que não existe).
4. `docs/V2-DIAGNOSTICO-modo-transferencia.md` — diagnóstico das imagens de 29/10 (modo USB da câmera, capability false, canal de eventos vivo).
5. `docs/V2-ANDROID-estrategia.md` — plano "B" documentado (Android MtpDevice + eventos) caso o iOS não feche a conta.

## 11. PEDIDO ESPECÍFICO AO CLAUDE CODE
1. Ler o repo, focando a seção 8 (experimentos direcionados, H1–H5).
2. Se for possível compilar no macOS: implementar o experimento H2 (abrir sessão sem contents authorization) como **variante controlada** (flag/log claro, sem quebrar o fluxo atual).
3. Correção objetiva única por commit, com mensagem explicando qual hipótese está testando.
4. NÃO refazer a UI, NÃO adicionar backend/nuvem, NÃO trocar de API sem equivalência comprovada em docs Apple.
5. **Comunicar em português**, evidências separadas de suposições; se um comportamento de firmware Canon impossibilitar o fluxo por cabo no iOS, definir isso com prova e apresentar alternativas ao dono (com custo/risco).
