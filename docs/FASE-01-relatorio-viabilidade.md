# ClickDireto — Relatório de Viabilidade (Fase 1)
Data: 28/10/2026 · Status: AGUARDANDO APROVAÇÃO DO PROPRIETÁRIO

## 1. Diagnóstico preliminar

**VIÁVEL, com uma condição.** Existe um caminho 100% documentado em APIs públicas da Apple
para um app iOS de terceiros falar com uma câmera PTP por cabo: o framework
**ImageCaptureCore**, publicado para **iOS 13+ / iPadOS 13+ / visionOS**. A documentação
oficial da Apple descreve explicitamente, para apps iOS:

- Descobrir câmeras e scanners conectados (`ICDeviceBrowser`);
- Ver pastas, arquivos e metadados na câmera;
- **"Take photos directly on a connected camera using tethered capture"**;
- Autorização de conteúdo/controle da câmera via
  `requestContentsAuthorization` / `requestControlAuthorization`, exigindo apenas
  `NSCameraUsageDescription`.

Prova por terceiro (App Store, usando a mesma API):
- **Capture One mobile** lista **Canon EOS R8: Wired Tethering ✓** na tabela
  "Supported cameras, lenses and image files (mobile)";
- Seu guia de equipamento declara suporte a **iPhone X e acima com conector Lightning,
  usando o Apple Lightning to USB Camera Adapter / Lightning to USB 3 Camera Adapter**
  e comenta que "alguns adaptadores OTG Lightning podem funcionar, mas recomendamos o Apple".

O que NÃO existe no iOS (comprovado pela documentação oficial):
- **Accessory Access / `com.apple.developer.accessory-access.usb`** — disponível apenas em
  **macOS 27+** ("Manage access to connected USB accessories" — platforms: macOS 27.0).
  Não pode ser usado no iPhone.
- **ExternalAccessory** — funciona somente com acessórios **MFi** que anunciam protocolos
  no próprio chip. A Canon EOS R8 não é acessório MFi → não aparecerá para `EAAccessory`.
- Não há API pública de USB bruto (IOUSBHost/libusb) para apps iOS.

Portanto: nada de "driver USB próprio". O PTP é falado pelo stack do ImageCaptureCore.
Isto atende a todas as restrições do projeto (sem Wi-Fi, sem Bluetooth, sem API paga,
cabo físico, JPEG original).

Condição/requisito que permanece indecidível em papel e exige TESTE NO HARDWARE:
1. Se o adaptador **H'Maston ZHQ-11** (OTG Lightning genérico) entrega PTP ao ImageCaptureCore
   (o sistema de importação do Fotos já reconhece a câmera pelo ZHQ-11 — indício positivo,
   mas o ICC tem canal próprio e não é garantido que aceite o mesmo adaptador);
2. Latência e estabilidade de 100 capturas seguidas por Lightning (USB 2, especificação do
   ZHQ-11: 12–16 MB/s);
3. Comportamento com a tela bloqueada (iOS suspende apps; USB Restricted Mode).

Teste barato e imediato que prova o ecossistema inteiro antes de qualquer código:
instalar o **Capture One mobile e usar o trial gratuito de 7 dias** com a R8 + ZHQ-11 +
cabo USB-A↔USB-C no iPhone 14 Pro Max. Se o tethering com fio funcionar por esse
adaptador, o caminho ClickDireto está fisicamente comprovado.

## 2. Fontes oficiais consultadas

Apple (documentação oficial, verificada via dados estruturados do site):
- ImageCaptureCore (framework) — iOS 13.0+/iPadOS 13.0+/Mac Catalyst/macOS/visionOS.
  https://developer.apple.com/documentation/imagecapturecore/
  ("Discover connected cameras… View and modify folders, files and metadata on a connected
  camera… Take photos directly on a connected camera using tethered capture"; docs exigem
  apenas NSCameraUsageDescription para tethering em app iOS)
- ICDeviceBrowser — class, iOS 13.0+:
  https://developer.apple.com/documentation/imagecapturecore/icdevicebrowser
  (inclui requestContentsAuthorization/requestControlAuthorization)
- ICCameraDevice / ICCameraDeviceDelegate / ICCameraItem / ICCameraFile:
  https://developer.apple.com/documentation/imagecapturecore/iccameradevice
- Accessory Access (framework) — **apenas macOS 27.0+**:
  https://developer.apple.com/documentation/accessoryaccess/
- Entitlement "Claim USB Accessory"
  `com.apple.developer.accessory-access.usb` — **apenas macOS 27.0+**:
  https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.accessory-access.usb
- ExternalAccessory — iOS 3.0+; só acessórios MFi com protocolos anunciados:
  https://developer.apple.com/documentation/externalaccessory/
- PhotoKit (salvar JPEG com byte a byte preservado):
  https://developer.apple.com/documentation/photokit/
- Importação por adaptador (Fotos app, manual):
  https://support.apple.com/en-us/118280
- Acesso de acessórios USB quando bloqueado (USB Restricted Mode):
  https://support.apple.com/en-us/111806

Canon (manuais oficiais):
- EOS R8 — App Selection for USB Connections ("Photo Import/Remote Control" = modo PTP
  usado por apps Android dedicados e pelo app Fotos do iOS; "Canon app(s) for iPhone" =
  apps proprietários da Canon; "Video calls/streaming" = UVC):
  https://cam.start.canon/en/C013/manual/html/UG-08_Set-up_0270.html
- Canon Content Transfer Professional — conexão cabo/tethering iOS
  (com cabo Anker 514 Lightning↔USB-C como referência para Lightning):
  https://cam.start.canon/en/S013/manual/html/UG-01_CTP-i_0030.html

Terceiros (prova de existência, não substituto de teste próprio):
- Capture One mobile — câmeras suportadas: "Canon EOS R8 | Wired Tethering ✓ | Wireless ✓"
  https://support.captureone.com/hc/en-us/articles/12628082004381-Supported-cameras-lenses-and-image-files-mobile
- Equipamento de conexão (iPhone X+, Lightning + Apple Camera Adapter; "Some lightning
  OTG adaptors might work, but our recommendation is to use the Apple one"; requer iOS 15+):
  https://support.captureone.com/hc/en-us/articles/12628216723869-Necessary-connection-equipment-mobile
  https://support.captureone.com/hc/en-us/articles/13234007899805-FAQ-mobile
- Apple Lightning to USB 3 Camera Adapter (MX5J3):
  https://www.apple.com/shop/product/mx5j3am/a/lightning-to-usb-3-camera-adapter

## 3. Matriz de viabilidade por requisito

| # | Requisito | Classificação | Justificativa / fonte |
|---|-----------|---------------|----------------------|
| 1 | App iOS de terceiros identifica câmera USB conectada por cabo | COMPROVADO POR DOCUMENTAÇÃO (+ teste de campo pendente) | ICDeviceBrowser iOS 13+; Capture One mobile faz exatamente isso com a R8 |
| 2 | Sessão de leitura/comandos PTP com a Canon por app próprio | COMPROVADO POR DOCUMENTAÇÃO (mecanismo) · PRECISA DE TESTE REAL (funciona também via ZHQ-11?) | ImageCaptureCore implementa PTP; modo da câmera "Photo Import/Remote Control" |
| 3 | Detecção automática de nova captura (botão físico da câmera) | COMPROVADO POR DOCUMENTAÇÃO (mecanismo) · PRECISA DE TESTE REAL (momento/latência em Lightning) | ICCCameraDeviceDelegate recebe itens novos (didAddItem etc.); sem polling até onde a doc indica |
| 4 | Receber o JPEG original sem recompressão | COMPROVADO POR DOCUMENTAÇÃO | Download do objeto PTP original via ICC; salvar via PHAssetCreationRequest (PhotoKit) preserva bytes |
| 5 | Salvar automaticamente no app Fotos (biblioteca) | COMPROVADO POR DOCUMENTAÇÃO | PhotoKit PHPhotoLibrary.requestAuthorization(.readWrite) + criação de asset |
| 6 | iPhone 14 Pro Max (Lightning) + C8 + câmera por cabo | PRECISA DE TESTE REAL | Adaptador Apple Lightning↔USB-A é caso documentado; ZHQ-11 é genérico — indício positivo (Fotos reconhece), não prova |
| 7 | Canon EOS R8 compatível | COMPROVADO POR DOCUMENTAÇÃO | Manual da EOS R8 tem modo PTP por USB; Capture One lista R8 wired ✓ |
| 8 | H'Maston ZHQ-11 compatível com o app (não só com Fotos) | PRECISA DE TESTE REAL | Capture One: "alguns OTG Lightning podem funcionar" — sem garantia |
| 9 | Accessory Access / USB bruto no iOS | NÃO SUPORTADO PELAS APIS PÚBLICAS COMHECIDAS | Doc oficial: macOS 27.0+ somente |
| 10 | ExternalAccessory com câmera não-MFi | NÃO SUPORTADO PELAS APIS PÚBLICAS CONHECIDAS | Doc oficial: só MFi, protocolos anunciados pelo fabricante |
| 11 | Desenvolver/compilar/assinar o app a partir do Windows | IMPOSSÍVEL NAS CONDIÇÕES ATUAIS (sem macOS) · Solução real: CI + sideload (ver §6) | Compilar/assinar app iOS exige Xcode em macOS; o Windows não gera .ipa assinada |
| 12 | App recebendo fotos com tela bloqueada / em segundo plano contínuo | NÃO SUPORTADO PELAS APIS PÚBLICAS CONHECIDAS | iOS suspende apps em segundo plano; USB Restricted Mode exige desbloqueio periódico. Plano: app aberto em primeiro plano durante a sessão fotográfica |
| 13 | Não usar Wi-Fi/Bluetooth/caixa paga | COMPROVADO POR CONSTRUÇÃO | Cabo físico + ImageCaptureCore local; nenhum serviço externo |
| 14 | 100 capturas seguidas sem perda/duplicação | PRECISA DE TESTE REAL | Critério de aceitação nº 7; Lightning é USB 2 (~12–16 MB/s no ZHQ-11): est. 1–3 s por JPEG |

Legenda conforme instruções do projeto.

## 4. Bloqueios técnicos (ordem de severidade)

1. **Sem macOS.** Xcode é obrigatório para compilar/assinar/installar app iOS.
   Alternativas reais: (a) CI macOS gratuito (GitHub Actions, em repositório público)
   gerando .ipa; (b) instalação via Sideloadly/AltServer no Vento (assinatura com Apple ID
   gratuita, perfil de 7 dias); (c) Mac emprestado/alugado por alguns dias.
   *(Swift no Windows não compila/assina app iOS — confirmado pela arquitetura da cadeia de
   ferramentas da Apple.)*
2. **Adaptador ZHQ-11 não comprovado para ICC.** Plano B (custo evitável até o teste):
   Apple Lightning to USB 3 Camera Adapter.
3. **Permissões** (solicitadas uma vez cada): acesso da câmera via ICC (prompt do sistema +
   permissão "Wired Accessories" no iOS 26) e autorização da biblioteca Foto via PhotoKit.
   Não é necessário ler a biblioteca: o controle anti-duplicação é feito nos handles PTP.
4. **Segundo plano**: app permanece no primeiro plano para capturar; ao bloquear a tela a
   sessão pode cair. Aceito pela operação (fotógrafo com app aberto).
5. **Bateria/câmera**: desligar auto power-off da R8 durante a sessão; câmera alimentada
   por bateria própria (Lightning não carrega a câmera).

## 5. Plano de prova de conceito (Fase 2)

App mínimo SwiftUI, sem dependências externas, telas únicas + log:

- `CameraConnectionManager`: ICDeviceBrowser (browsedDeviceTypeMask = câmeras) →
  ICCameraDeviceDelegate: deassocia, encerra; estados Desconectado/Verificando/Conectado/Erro.
- `CaptureEventMonitor`: `cameraDevice(_:didAddItem:)` (e `deviceDidChangeCapability`)
  mantendo um conjunto de identificadores PTP já processados para deduplicação robusta.
- `JPEGTransferService`: verifica se o item é JPEG (UTI image/jpeg); baixa via
  ICCameraDevice para arquivo temporário, preservando os bytes recebidos (sem passar
  por UIImage/ImageIO).
- `PhotoLibraryWriter`: PHPhotoLibrary.performChanges {
  PHAssetCreationRequest.creationRequestForAsset(from: arquivoTemporario, options com
  originalFilename do arquivo da câmera) } e guarda o `localIdentifier`;
  registra log de sucesso/erro por foto.
- `ConnectionDiagnostics`: tela mostra modelo (ICDevice.displayName/serial), tipo de
  dispositivo, erros ICC completos.
- `Diagnóstico da sessão`: **CONFIRMADO PELO COMPILADOR (xcodebuild, SDK iOS 26.5, out/2026):**
  `ICCameraDevice.requestTakePicture()` é **indisponível no iOS** (macOS-only). Conclusão:
  pelo ImageCaptureCore no iPhone **não existe disparo remoto do obturador**; o recebimento
  funciona com a foto tirada pelo **botão físico da câmera** (PTP ObjectAdded → `didAddItem`)
  — exatamente o fluxo alvo do projeto. O botão de teste virou diagnóstico da sessão.

### 5.1 Auditoria pós-teste no hardware (28/10/2026 — R8 + iPhone 14 Pro Max reais)

**Teste executado:** R8 em modo USB "Importação de fotos/Controle remoto" → cabo
USB-A↔USB-C → OTG Lightning (H'Maston ZHQ-11) → iPhone; ClickDireto instalado via
Sideloadly (Apple ID gratuita).

**Resultados comprovados no hardware:**
- `ICDeviceBrowser` encontrou a R8 via ZHQ-11: "Dispositivo adicionado: ... USB vendor
  1193, product ..." → **adaptação ZHQ-11 aprovada pela ImageCaptureCore** (era o maior
  risco do projeto — resolvido).
- Sessão aberta e catálogo completo enumerado: "Câmera PRONTA ... Fotos já no cartão:
  2402 — não serão importadas" → dedupe por `ptpObjectHandle` func **ionando: NENHUMA
  das 2402 fotos existentes é baixada** (o app não faz importação em massa por construção:
  só lê índices e aguarda itens novos).
- Historlys: perfil gratuito do iOS exibiu "desenvolvedor não confiável" até Confiar
  manualmente (Ajustes → Geral → VPN e Gerenciamento de Dispositivo) — passo normal de
  sideload, não é erro do app.

**Observação do fotógrafo — tela preta de "transferência" na R8:** ao abrir a sessão PTP,
a câmera entra no modo USB dela própria e a tela traseira muda para a interface de
conexão com computador (indicadores de bateria etc.), perdendo a visualização pelo LCD.
**Análise:** esse comportamento é do firmware da Canon no modo "Importação de
fotos/Controle remoto" e ocorre com qualquer cliente PTP (app Foto do iOS, Capture One,
Evoto) — não é provocado por chamada do app (nenhuma API nossa dispara import ou
"modo de transferência"; `requestOpenSession` apenas abre a sessão, como qualquer
tethering v). A documentação Apple (nota de obsolescência de `requestEnableTethering`):
câmeras de terceiros que suportam o comando padrão de foto **já têm habilitado por
padrão** o uso do obturador físico enquanto conectadas; a confirmação objetiva é
`ICDevice.capabilities ⊇ ICDeviceCapability.cameraDeviceCanTakePicture` — o app agora
registra essa verificação no que é de diagnóstico.
**Pendente (teste físico):** confirmar na R8 se o obturador físico fotografa com a
sessão aberta e se as novas fotos chegam pelo `didAddItem` — checkout final do
critério "captura vinculada" da Fase 2.

Testes A–F mapeados ao termo de referência da Fase Zero; o Teste F (10 capturas) medirá
latência média por captura. Todos os resultados registrados em log exportável.

## 6. Ambiente de desenvolvimento necessário

- **Windows 11 (onde OpenCode roda):** repositório Git `ClickDireto`; código Swift/SwiftUI;
  projeto descrito com **XcodeGen** (`project.yml`) — a pasta `xcodeproj` é gerada no macOS
  com 1 comando, evitando conflito de arquivo de projeto binário entre sistemas.
  (`Info.plist` com NSCameraUsageDescription; dependências externas: nenhuma).
- **Compilação/assinatura/execução no dispositivo (alternativas reais, em ordem de custo):**
  1. **US$ 0 — CI macOS (GitHub Actions, repositório público):** runner macOS executa
     `xcodebuild archive` e gera .ipa; a .ipa é assinada no Windows com **Sideloadly**
     (Apple ID gratuita; perfil de 7 dias; renovação manual; limite de 3 apps). Developer
     Mode deve estar ativado no iPhone uma vez.
  2. **US$ 0 — Mac emprestado (1 sessão):** Xcode gratuito + Apple ID gratuita; instalação
     direta pelo Xcode; mesmos limites de 7 dias, porém fluxo oficial.
  3. **US$ 99/ano — Apple Developer Program (opcional):** perfis de 1 ano, TestFlight,
     builds mais estáveis; não é obrigatório para uso pessoal.
  4. Mac alugado (MacinCloud etc.) — última alternativa; desnecessário para o PoC.
- **Logs de USB**: sysdiagnose no iPhone + Console.app no Mac; no app PoC, log em texto
  (códigos ICReturn, modelo detectado, tempos medidos).

## 7. Estimativa de custos

| Item | Custo | Obrigatório? |
|------|-------|--------------|
| Apple ID gratuita (assinatura 7 dias) | US$ 0 | Sim, caminho mínimo |
| CI GitHub Actions (repo público, runner macOS) | US$ 0 | Alternativa recomendada |
| Sideloadly/AltServer (Windows) | US$ 0 | Sim, no caminho sem Mac |
| Apple Developer Program | US$ 99/ano | Não (opcional, melhora validade de perfil para 1 ano) |
| Adaptador Apple Lightning→USB 3 Camera Adapter | ~R$ 400–600 | Só SE o ZHQ-11 falhar (fallback comprovado por terceiros) |
| Cabo USB-A↔USB-C dados | já possuído | Sim, sem custo |
| Trial Capture One mobile (7 dias) | US$ 0 (trial) | Recomendado para validar ZHQ-11 antes de codificar |
| Wi-Fi/Bluetooth/assinatura/servidor | não solicitado | — |

Custo recorrente obrigatório para uso cotidiano: **US$ 0** (o caminho com conta gratuita
exige apenas renovar a assinatura a cada 7 dias; sem cobrança).

## 8. Próximos passos (ordem de execução)

1. **Teste físico "zero-código" (30 min, custo 0):** instalar Capture One mobile (trial 7
   dias); câmera em *Menu → Choose USB connection app → **Photo Import/Remote Control***;
   conectar R8 → cabo USB-A↔USB-C → ZHQ-11 → iPhone; permitir acesso; verificar se a
   câmera aparece no Connect e se as capturas físicas chegam por cabo.
   *Resultado A: funciona ⇒ exigência de hardware resolvida (ZHQ-11 OK).
    Resultado B: falha ⇒ repetir com adaptador Apple (única compra potencial).*
2. **Aprovar este relatório** → mover para Build.
3. **Criar estrutura do projeto no Windows** (Git + XcodeGen + código da PoC) — executo
   assim que houver aprovação.
4. Preparar pipeline de CI (build macOS sem assinatura) + fluxo Sideloadly; OU agendar 1
   sessão com Mac emprestado.
5. Executar Testes A–F no dispositivo real, com resultados registrados.
6. Depois de A–F verdes: integração com o app de publicação (verificação de como ele
   detecta novas fotos: monitora a biblioteca via PhotoKit? precisa permanecer aberto?) —
   teste separado, com o app do usuário aberto em segundo plano.
7. Fase 3 (ClickDireto produto) somente após PoC verde.

---
*Riscos honestos: (i) a combinação ImageCaptureCore + Lightning + adaptador genérico é
individual — o sucesso documentado de terceiros (Capture One, câmeras Canon/Nikon por
Lightning) torna o sucesso provável, mas não é garantido para o ZHQ-11; (ii) o iOS pode
mudar comportamento em atualização futura; (iii) nada foi testado em hardware real ainda.*
