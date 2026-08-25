# MyWinTweaks — Architettura dell'applicazione (v1)

> **Stato**: progettazione. Nessun codice applicativo è ancora implementato.
> **Stack**: PowerShell + WPF (XAML) puro, senza compilazione — stessa filosofia di WinUtil.
> **Fonti dati**: `tweaks.normalized.json` (20 tweak, risk low/medium, attivi in v1).
> `tweaks.highrisk.json` (7 tweak, **esclusi** dall'interfaccia v1, sezione "Avanzate" futura).

---

## 1. Obiettivi e vincoli

- Applicazione desktop **Windows 10/11**, GUI moderna, semplice e sicura.
- **Motore guidato dai dati**: i tweak NON sono hardcoded; l'app legge `tweaks.normalized.json` all'avvio, valida i contenuti e genera dinamicamente la UI.
- Applicare e **annullare** un insieme selezionato di tweak.
- Operare solo su tweak **low/medium** in v1; il codice deve **ignorare** i tweak `risk=high` (o non presenti nel file attivo) ma lasciare il motore pronto per una futura sezione "Avanzate".

---

## 2. Struttura delle cartelle

```
MyWinTweaks/
├── MyWinTweaks.ps1                  # ENTRY POINT unico: carica XAML, avvia la GUI
├── ui/
│   ├── MainWindow.xaml              # layout principale (WPF, XAML non compilato)
│   ├── TweakDetailPanel.xaml        # pannello dettaglio (DataTemplate/XAML)
│   ├── ApplyConfirmDialog.xaml      # finestra riepilogo+conferma
│   ├── HistoryView.xaml             # cronologia
│   └── styles.xaml                  # risorse/stili condivisi
├── engine/                          # motore (funzioni PowerShell riusabili e testabili)
│   ├── TweakEngine.psm1             # carica/valida il JSON, espone API
│   ├── JsonValidation.psm1          # validazione contro schema.json + invarianti
│   ├── BackupManager.psm1           # backup write-ahead e ripristino
│   ├── PowerShellExecutor.psm1      # esecuzione sicura di apply/undo/verify
│   ├── TweakVerifier.psm1           # verifica stato (solo verifyCommands, dry-run)
│   ├── Elevation.psm1               # Start-Process -Verb RunAs
│   └── Logger.psm1                  # logging
├── data/
│   ├── tweaks.normalized.json       # catalogo attivo v1 (20 tweak)
│   ├── tweaks.highrisk.json         # esclusi da v1 (non caricati dalla UI)
│   └── schema.json                  # schema v2 per validazione
├── backup/                          # creato a runtime
│   └── <timestamp>/                 # snapshot delle chiavi modificate
├── logs/                            # creato a runtime
└── docs/
    ├── ARCHITECTURE.md
    ├── UI_SPEC.md
    ├── SECURITY_SPEC.md
    └── TEST_PLAN.md
```

**Motivazione**: moduli PowerShell separati (`engine/*.psm1`) con **funzioni pure** testabili; `MyWinTweaks.ps1` è solo l'orchestratore che carica il layout e collega i moduli. Nessun tweak nei moduli: i dati stanno solo in `data/`.

---

## 3. Tecnologia scelta e motivazione

### Stack scelto: **PowerShell + WPF (XAML) puro**

| Aspetto | Scelta | Motivazione |
|---------|--------|-------------|
| Runtime | Windows PowerShell 5.1 (preinstallato su Win10/11) | Nessuna dipendenza esterna, coerenza con WinUtil |
| UI | WPF con XAML caricato a runtime (`[xml]` + `PresentationFramework`) | Layout dichiarativo e moderno senza compilazione |
| Motore comandi | PowerShell (stesso linguaggio dei comandi nei JSON) | `applyCommands`/`undoCommands`/`verifyCommands` sono già PowerShell: nessun livello di traduzione |
| Elevazione | `Start-Process -Verb RunAs` | UAC standard di Windows |
| Esecuzione | Avvio con `powershell.exe -ExecutionPolicy Bypass -File MyWinTweaks.ps1` | L'app non richiede installazione |

**Motivazione del cambio di stack**: il progetto è un fork ispirato a WinUtil, che è PowerShell+WPF puro. Adottare lo stesso stack garantisce coerenza, zero toolchain di build, massima trasparenza dei comandi e aggiornabilità dei dati senza ricompilare.

**Nota limiti accettati**: PowerShell non ha tipizzazione forte a compile-time né test unitari nativi → la validazione JSON rigorosa e i test manuali in VM sono ancora più importanti (vedi SECURITY_SPEC e TEST_PLAN).

---

## 4. Modello dati

Struttura dati in PowerShell (PSCustomObject) mappata 1:1 allo schema v2:

```text
Tweak
  id                     string
  name                   string
  description            string
  category               string   (Privacy, Security, Performance, System, UI, AppDebloat, Services)
  scope                  string   (user|machine|both)
  requiresAdministrator  bool
  risk                   string   (low|medium|high)
  irreversible           bool
  confirmDialog          bool
  restartRequired        string   (none|explorer|service|reboot)
  osVersions             string[]
  preconditions          string[]
  services               ServiceChange[]
  dependencies           string[]
  registryChanges        RegistryChange[]
  applyCommands          string[]
  undoCommands           string[]
  verifyCommands         string[]
  warnings               string[]

RegistryChange
  operation              string   (set|remove)
  path                   string
  hive                   string   (HKLM|HKCU|HKCR|HKU|HKCC)
  name                   string?
  type                   string?  (String|ExpandString|Binary|DWord|QWord|MultiString)
  value                  object?  (int|string|byte[]|null)
  backupOriginalValue    bool

ServiceChange
  name                   string
  action                 string   (startup|stop|start|restart)
  startupType            string?  (Automatic|AutomaticDelayedStart|Manual|Disabled)
  expectedState          string?

Catalog
  schemaVersion          int
  source                 string
  description            string
  tweaks                 Tweak[]
```

**Invarianti** (già garantite da `validate_tweaks.py`, da replicare in `JsonValidation.psm1`):
- `id` univoci e kebab-case;
- `risk=high` ⇒ `confirmDialog=true`;
- `undoCommands` vuoto ⇒ `irreversible=true` e `confirmDialog=true`;
- `registryChanges` con hive HKLM/HKCR/HKU/HKCC ⇒ `requiresAdministrator=true`;
- `services` non vuoto ⇒ `restartRequired != none`;
- `operation=set` ha `name`+`type`+`value` coerente; `operation=remove` non ha `type`/`value`.

---

## 5. Caricamento e validazione del JSON

1. All'avvio `TweakEngine.psm1` carica `data/tweaks.normalized.json` (`Get-Content -Raw | ConvertFrom-Json`).
2. `JsonValidation.psm1` valida il documento **contro `schema.json`** (validatore JSON Schema per PowerShell, o fallback a controlli strutturali manuali) + invarianti di business.
3. Se la validazione fallisce → **l'app non si avvia**: finestra di errore bloccante, nessun comando eseguito.
4. Controllo `schemaVersion == 2`; versioni diverse → rifiuto.
5. **Filtro v1**: i tweak con `risk == "high"` vengono **scartati** dal caricamento della UI, anche se presenti nel file (robustezza futura). `tweaks.highrisk.json` **non viene letto** in v1.
6. Il catalogo è esposto ai pannelli come `PSCustomObject[]`.

---

## 6. Sistema di backup e ripristino

### Backup
- Prima di ogni applicazione di un tweak con `registryChanges` in cui `backupOriginalValue=true`, il valore pre-esistente (tipo + dato) viene letto e salvato.
- Backup in `backup/<timestamp>/<tweakId>.json`:
  ```json
  {
    "createdUtc": "...",
    "tweakId": "...",
    "appliedAt": "...",
    "registryBackup": [ { "path", "name", "existed", "originalType", "originalValue" } ],
    "serviceBackup": [ { "name", "originalStartupType", "originalState" } ],
    "envBackup": [ ... ]
  }
  ```
- Backup **atomico** (file temporaneo poi rinominato); indice `backup/index.json` traccia i tweak applicati per run.

### Ripristino (Annulla)
- `undoCommands` eseguiti nell'ordine del file.
- Se per un `registryChange` era salvato il valore originale e l'undo **non** è un semplice `remove`, si ripristina il valore originale dal backup (fallback di sicurezza).
- Al termine il record viene marcato `reverted=true`.

### Regola chiave per le chiavi di Policy
Per i valori in `...\Policies\...`, il ripristino corretto è `remove` (già in `undoCommands` con `Remove-ItemProperty`). Il sistema NON inventa un "valore di default".

---

## 7. Gestione privilegi amministrativi e UAC

- `requiresAdministrator` è letto dal JSON (non calcolato).
- **Elevazione solo quando necessaria**:
  - se il set selezionato contiene ≥1 tweak con `requiresAdministrator=true` → l'operazione viene **riavviata** in un processo elevato tramite `Start-Process powershell -Verb RunAs -ArgumentList <script> <piano>` (prompt UAC), usando un piano di lavoro serializzato temporaneo (UUID) per non passare dati fragili via argomenti.
  - se TUTTI i tweak selezionati sono `requiresAdministrator=false` → eseguiti nel processo normale, **senza** UAC.
- L'helper elevato esegue solo il piano validato e restituisce esito/log in un file di output; la GUI resta reattiva.
- I tweak `user` (es. `storage-sense-disable`, `visual-effects-best-performance`) non elevano mai.

---

## 8. Sistema di esecuzione sicura dei comandi PowerShell

- `PowerShellExecutor.psm1` esegue ogni comando con `Invoke-Expression` **solo su stringhe dal JSON validato** — mai su input utente.
- **Niente interpolazione di input utente**: la UI non accetta testo PowerShell libero dall'utente → niente vettore di injection.
- Per operazioni con `requiresAdministrator=true`, l'esecuzione avviene nel processo elevato.
- Timeout per comando (~60 s) per evitare blocchi.
- `$ErrorActionPreference='Stop'` per l'apply: un fallimento ferma l'operazione; l'utente può chiedere rollback parziale dei tweak già applicati (guidato dai backup).
- Output catturato e registrato, non stampato a schermo se non richiesto.

---

## 9. Sistema di verifica dello stato dei tweak

- `TweakVerifier.psm1` esegue **solo** `verifyCommands` (read-only) di un tweak → equivale a un **dry-run**.
- Il pulsante **Verifica** esegue i comandi senza applicare nulla.
- Esito per comando: `Passed` / `Failed` / `Error` (eccezione o timeout).
- La UI mostra semaforo: ✅ applicato / ⚪ non applicato / ⚠ parziale o ignoto.
- I `verifyCommands` sono già read-only (es. `Get-ItemProperty ... -eq 0`); il motore interpreta l'output booleano.

---

## 10. Sistema di log

- `Logger.psm1` scrive su `logs/app.log` (rotazione per dimensione, retention N giorni).
- Livelli: Debug / Info / Warning / Error.
- Ogni operazione (apply/undo/verify) logga `tweakId`, timestamp, esito, exit code; a livello Debug anche l'output.
- **Niente segreti** né dati personali nei log.
- (Opzionale) eventi critici in Event Viewer di Windows, sorgente `MyWinTweaks`.

---

## 11. Gestione errori

- Funzioni del motore che restituiscono oggetti di esito tipizzati (struct `Result { Ok, Message, TweakId }`) e generano errori con `Write-Error` + `$Error`.
- La GUI mostra errori comprensibili (mai stack trace crudi); dettagli nei log.
- **Rollback automatico parziale**: se un'operazione multipla fallisce a metà, l'app propone di annullare i tweak già applicati (dai backup) o di proseguire.
- Se un tweak richiede `restartRequired` e l'app non può riavviare (es. `reboot`), lo segnala e chiede all'utente di riavviare manualmente; lo stato resta "applicato (riavvio pendente)".

---

## 12. Comportamento per i tweak ad alto rischio (futura sezione "Avanzate")

- In v1: il caricatore **scarta** ogni tweak `risk=high`; l'UI non li mostra.
- **Predisposizione (motore già pronto)**:
  - `TweakEngine` espone sia la lista attiva sia (se presente) una lista `advancedTweaks`; in v1 questa è vuota.
  - Parametro `-AllowHighRisk $false` di default: se `$false`, rifiuta qualunque tweak `risk=high`.
  - La UI futura aggiungerà una sezione "Avanzate" attivabile con toggle esplicito + conferma, che carica `tweaks.highrisk.json`, impone `confirmDialog` per ogni `high`, e richiede elevazione (tutti i `high` hanno `requiresAdministrator=true`).
  - I 7 high-risk restano documentati in `tweaks.highrisk.json` e nei `docs`, senza riferimenti hardcoded nel motore.

---

## 13. Flusso di esecuzione riepilogativo

```text
powershell -ExecutionPolicy Bypass -File MyWinTweaks.ps1
  └─ carica ui/MainWindow.xaml (XAML) e stili
  └─ TweakEngine carica tweaks.normalized.json
  └─ JsonValidation (schema v2 + invarianti) → errore bloccante se non valido
  └─ Filtro: scarta risk=high
  └─ UI mostra checklist per categoria (da UI_SPEC.md)

Utente seleziona tweak
  └─ Pannello dettaglio (rischio/scope/riavvio/avvisi)
  └─ [Verifica] → TweakVerifier esegue SOLO verifyCommands (dry-run)

Utente preme [Applica selezionati]
  └─ Riepilogo + conferma (confirmDialog per tweak che lo richiedono)
  └─ Elevazione UAC (Start-Process -Verb RunAs) solo se ≥1 requiresAdministrator=true
  └─ Backup pre-modifica (registry/services/env)
  └─ Esecuzione applyCommands (PowerShell) in ordine
  └─ Log + registrazione in HistoryView
  └─ Rollback parziale se fallisce

Cronologia
  └─ [Annulla] → esegue undoCommands + ripristina valori originali dal backup
  └─ [Verifica] → ri-verifica lo stato
```
