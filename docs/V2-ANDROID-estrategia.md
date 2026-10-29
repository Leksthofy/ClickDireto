# ClickDireto V2 (Android) — Estratégia técnica e investigação

Data: 29/10/2026
Câmera: Canon EOS R8 — Dispositivo: Android com USB Host/OTG — Cabo: USB/OTG

## 1. Investigação de plataforma (documentação oficial Android)

Verificado nas páginas de referência oficiais (`developer.android.com/reference/android/mtp/...`):

### `android.mtp.MtpDevice` (API nativa, sem dependência paga)
- `open(UsbDeviceConnection)` — abre a sessão com o dispositivo USB (câmera).
- `getStorageIds()` — lista os armazenamentos (cartão SD).
- `getObjectHandles(storageId, format, objectHandle)` — obtém a lista de objetos
  (fotos); `format` permite filtrar JPEG (`MtpConstants#EXIF_OBJECT_JPEG`).
- `getObject(handle, size)` — baixa os bytes do objeto (o JPEG original).
- `importFile(objectHandle, destPath)` — alternativa pronta: copia o arquivo direto
  para um caminho local.
- `getThumbnail(handle)` — miniatura para exibição rápida na interface.
- `deleteObject` — existe na API, mas o ClickDireto **nunca apagar** no cartão.

### `android.mtp.MtpEvent` + `MtpDevice.readEvent(CancellationSignal)` (API 24+)
- `readEvent` **bloqueia em.background até a câmera enviar um evento**; retorna `MtpEvent`.
- Constantes confirmadas na página oficial incluem:
  **`EVENT_OBJECT_ADDED` ("Event code for OBJECT_ADDED event")** — o evento que a
  câmera emite quando o obturador físico dispara e grava um arquivo novo.
  Também: `EVENT_OBJECT_REMOVED`, `EVENT_CAPTURE_COMPLETE`, `EVENT_STORE_FULL`,
  `EVENT_DEVICE_INFO_CHANGED` etc.

### Tradução para o fluxo exigido (§4 do briefing)
| Passo do briefing | Mecanismo Android |
|---|---|
| 1. Conectar por cabo/OTG | `UsbManager` + `ACTION_USB_DEVICE_ATTACHED` broadcast |
| 2. Detectar câmera | Enumerar dispositivos USB com classe PTP/MTP (Canon: VID 1193/0x04A9) |
| 3. Permissões | `UsbManager.requestPermission()` — prompt nativo do Android |
| 4. Iniciar sessão | `MtpDevice.open(usbConnection)` |
| 5. Continuidade | Thread dedicada bloqueada em `readEvent` (sessão persiste; nada é fechado por foto) |
| 6/7. Botão físico | Sem ação do app — a câmera grava no cartão e emite `OBJECT_ADDED` |
| 8. Detectar nova foto | `readEvent` → `MtpEvent.EVENT_OBJECT_ADDED` (evento real do protocolo, não polling cego) |
| 9. Transferir | `getObjectHandles(…)` novo handle → `importFile`/`getObject` para pasta temporária do app |
| 10. Salvar na galeria | `MediaStore` + `IS_PENDING` → álbum "Click Direto" (permissão de mídia da versão do Android) |
| 11. Repetir continuamente | Loop persiste; dedupe por `objectHandle` + fila serial |

**Por que não é "polling cego":** `readEvent` é orientado a evento do protocolo PTP.
Uma verificação de segurança de balanço (relista de handles) pode complementar, mas o
gatilho primário é o evento — satisfaz §5.3 do briefing ("consulta periódica eficiente
ou … método comprovado" — aqui é o método nativo comprovado).

## 2. Auditoria da "versão anterior" (PoC iOS)

- Tecnologia: Swift/SwiftUI + ImageCaptureCore (iOS) — **premissa específica de Apple**
  (não é a causa da limitação; no iPhone não existe API USB genérica pública).
- O comportamento observado no teste real: câmera reconhecida ✓, catálogo enumerado ✓
  sem importar (2.402 itens marcados) — estruturas conceituais (dedupe, estados,
  diagnóstico) são transferíveis para o Android em Kotlin.
- A falha de "captura não continua" alegada no briefing v1 será re-avaliada no Android
  com medição objetiva (eventos + logs), pois a Stack do Android é diferente (USB Host
  real, sem suspensão de sessão usada pelo iOS).

## 3. diferencial Android (por que V2 Android é o caminho certo)

- iOS: sem acesso USB genérico; só ImageCaptureCore (elementos acima)、impossível
  falar PTP cru/controle remoto completo.
- Android: **API pública de USB Host completa** (libusb/PTP bruto possível) + pilha
  MTP nativa pronta — exatamente a classe de API usada por apps de tethering Android
  (o Evoto Instant, por análise do seu material, confirma usar "captura vinculada
  com fio" ou transferência FTP como entrada).

## 4. O que falta para completar a investigação (bloqueios)

1. **APK do Evoto Instant** (§2 do briefing): aguardando o arquivo. Ao receber:
   análise estática (JADX if disponível; senão inspeção de pacotes/permissões/
   bibliotecas nativas via unzip + strings) → relatório objetivo de como eles fazem
   (USB Host? MtpDevice? PTP bruto?) — análise de comportamento, sem copiar código.
2. **Modelo do celular Android alvo** e versão do Android (define minSdk e permissões
   de mídia — WRITE_EXTERNAL vs READ_MEDIA_IMAGES; USB OTG do R8→celular).
3. **Cabo/adaptador** que permitirá ligar R8 → celular (USB-C↔USB-A já existe no caso
   do iPhone; celular USB-C → adaptador USB-A ou cabo C↔C com dados).

## 5. Arquitetura V2 (módulos — §9 do briefing)

```
app/ (Kotlin, Jetpack Compose)
  ui/           — tela única de sessão (estado, foto grande, miniaturas, contadores)
  usb/          — UsbManager: detecção (attach/detach), permissão, Conexão
  camera/       — MtpSession: open, readEvent loop, serialização de comandos
  transfer/     — TransferQueue: fila serial, dedupe por handle, retry, corrida
  gallery/      — AlbumWriter: MediaStore + álbum "Click Direto" + IS_PENDING→publicado
  presets/      — (fase posterior) importar preset JSON próprio, aplicar sobre cópia
  diagnostics/  — estados reais + log în app + latência média medida
Estados (§5.1): Desconectada → CâmeraDetectada → AguardandoPermissão →
ConectadaPronta → CapturaVinculadaAtiva(= sessão aberta + readEvent rodando) →
Transferindo → Erro
```

## 6. Testes (§10) — mapeamento
- A Detectação: broadcast attach + lista UsbDevices (VID 0x04A9/1193).
- B Primeira captura:OBJECT_ADDED→import→MediaStore→preu viz.
- C 20 disparos: contador de sucesso vs disparos; zero duplicados (dedupe handle).
- D 10 min: sessão não fechada (event thread persiste); log de queda se houver.
- E Integridade: tamanho esperado + CRC/lido até o fim; JPEG decode OK.
- F Reconexão: detach→fechar limpo; reattach→novos pedidos de permissão.
- G Galeria: ver post-MediaStore em app de galeria do sistema.
- H Presets: fase 4 (formato JSON próprio documentado).

## 7. Honestidade / riscos abertos
- O Canon em modo "Importação de fotos" emite `OBJECT_ADDED` via PTP **em um teste
  com iOS ImageCaptureCore (eventos `didAddItem`) — claramente o caso esperado;
  mas no Android o caminho é MtpDevice.readEvent, e a confirmação daneben só vem no
  teste físico real** (não declarar validado antes do Teste B no aparelho).
- Standby da tela do celular pode suspender a thread USB → manter a tela via
  `FLAG_KEEP_SCREEN_ON` durante sessão (regra do usuário §5.2 exige mais que isso:
  também tratar queda de conexão e reconectar, sem fingir estado ativo).
- Cache/support do MtpDevice varia por fabricante Android (STL melhor documentado;
  testar MIUI/One UI se aplicável — reportar no teste físico).
