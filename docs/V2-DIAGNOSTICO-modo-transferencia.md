# Diagnóstico da Fase 2 — Modo de transferência, tela preta e captura vinculada

Data: 29/10/2026
Evidências: 3 imagens enviadas (tela da R8; app 10:29; app 10:30) + leitura integral do código-fonte.

## 1. O que as telas mostram

**Tela da câmera (R8):** LCD apagado com ícone branco de **computador conectado** e ícone
laranja de **bateria baixa**. Este é o estado oficial do firmware Canon quando há conexão USB
ativa em modo de transferência — a câmera suspende a interface de fotografia e o Live View.
**É comportamento do firmware, não do app**: o mesmo acontece com o app Foto nativo do iPhone,
Capture One, Evoto e qualquer cliente PTP. O produto de referência (Evoto) só evita isso com
protocolos próprios de baixo nível (PTP cru no Android) — impossíveis no iOS público.

**App 10:29:** sequência correta de sessão — dispositivo adicionado → autorização concedida
(`ICAuthorizationStatusAuthorized`) → sessão aberta com sucesso.

**App 10:30 (decisivo):**
- **`didAddItems` recebidos em lote** (IMG_9278 → IMG_9304, ~27 eventos em 0,5 s): o **canal de
  eventos de objetos da câmera está vivo** e chegando ao app. Esses itens são a cauda do catálogo
  existente (a câmera informa objetos ao abrir a sessão PTP); o dedupe os ignorou corretamente
  (0 downloads), e o catálogo enumerou 2.413 fotos sem importar nada.
- **`cameraDeviceCanTakePicture: false`**: a capacidade reportada é de **controle remoto de
  disparo** (o app comandar a câmera). No iOS isso é irrelevante — `requestTakePicture()` nem
  existe no iOS (API macOS-only, comprovada por compilador). O fluxo do projeto **não depende
  dela**: a foto vem do botão físico. O `false` significa apenas: este modo USB da Canon não
  habilita disparo remoto de terceiros.
- Fotos recebidas: 0 — o disparo físico com a sessão aberta **ainda não foi testado**
  (o teste que fecha o laço; os 2.413 fotos do cartão são dedupe, não prova do fluxo novo).

## 2. Tipo de conexão estabelecida

Sessão PTP de importação via ImageCaptureCore (API pública da Apple): catálogo + eventos de
objeto + download por handle. É exatamente a família de mecanismo do canal de eventos PTP que o
Evoto usa no Android (confirmado na análise do APK). No iOS é o único canal público.

## 3. Hipóteses examinadas para "perda do Live View e dos controles"

| Hipótese | Veredito | Evidência |
|---|---|---|
| App abrindo modo externo errado (ex.: modo PC/remoto à força) | **Descartada** — ICC abre o modo de importação de fotos padrão; é o mesmo do app Foto nativo | Tela da R8 idêntica ao usar app Foto; docs do firmware |
| Bug do app encerrando a sessão | Descartada | Log: sessão persistiu; deviceDidBecomeReady + catálogo completo |
| Bateria baixa limitando funções | **Válida como agravante** | Ícone laranja de bateria na R8 — carregue antes do teste |
| Live View por cabo no iOS | **Impossível com APIs públicas**: a Canon não expõe live view no modo de importação PTP; o iOS não permite falar raw PTP ou CCAPI via cabo (CCAPI é rede/Wi-Fi) | Análise do APK + docs Apple (ICC iOS) |
| Falha de cabo/energia | Descartada | Sessão estável, catálogo completo enumerado |

## 4. O que foi verificado no código

- `CameraConnectionManager.handleNewItemsIfReady` só processa com `isReady` (pós-catálogo):
  os `didAddItems` do lote de enumeração **nunca baixam arquvo existente** (comprovado: 0 downloads).
- Dedupe por `ptpObjectHandle` intacto.
- Defeito real corrigido nesta V2: downloads iam em paralelo (agora fila serial FIFO); falha de
  ábum cancelava nada mas sem álbum — agora salva no álbum "ClickDireto"; permissão de Foto não
  era solicitada — agora é pedida junto com a autorização da câmera; UI não pedia estados com
  veracidade — agora separa Detected/Conectada/Recebendo/Salvando.

## 5. Correções possíveis e caminho recomendado

1. **Caminho principal (ativado nesta V2):** sessão de importação + eventos de objeto descentralizados
   + fila serial + álbum no app Foto. Só falta a **prova física**: disparar o obturador com o app
   conectado. Nada mais bloqueia antes disso.
2. **Live view no iPhone:** não viável no iOS sem protocolos não-públicos — não tentar; documentar.
3. **Recomendado operacionalmente:** bateria cheia (ou adaptador AC) antes do teste; a tela preta
   da câmera enquanto o cabo está conectado não indica problema: é como o iOS usa a câmera USB.
