# MyWinTweaks — Specifica dell'Interfaccia Grafica (v1)

> Riferimenti: 20 tweak attivi in `tweaks.normalized.json` (categorie: Privacy, Security, Performance, System, UI, AppDebloat, Services). Nessun tweak high-risk compare in v1.
> Stack: PowerShell + WPF (XAML puro, non compilato).

---

## 1. Principi UI

- **Moderno e pulito**: tema chiaro/scuro, stile Fluent, spaziatura generosa (via `ui/styles.xaml`).
- **Guidata dai dati**: la lista dei tweak e delle categorie è generata dinamicamente da `tweaks.normalized.json`. Nessun tweak hardcoded.
- **Semplice e sicuro**: ogni azione che richiede elevazione o che ha avvisi è sempre preceduta da riepilogo/conferma.
- **3 aree principali**: (1) Checklist dei tweak, (2) Pannello di dettaglio, (3) Barra azioni + Cronologia.

---

## 2. Layout generale (MainWindow)

```
+------------------------------------------------------------------+
|  MyWinTweaks                         [Tema] [Impostazioni] [?]    |
+------------------------------------------------------------------+
|  NAV:  [Tweaks]  [Cronologia]                                    |
+------------------------------------------------------------------+
|                                                         |  PANNELLO   |
|  CATEGORIA A          (checkbox)                         |  DETTAGLIO  |
|    ☑ Tweak 1                                            |  (solo del  |
|    ☐ Tweak 2                                            |  tweak      |
|  CATEGORIA B                                            |  selezionato)|
|    ☐ Tweak 3                                            |             |
|    ...                                                  |             |
+---------------------------------------------------------+-------------+
|  [Verifica]  [Applica selezionati]      Contatore: 3 selezionati     |
+------------------------------------------------------------------+
```

- Sinistra: **checklist raggruppata per categoria**.
- Destra: **pannello di dettaglio** del tweak selezionato (vedi §4).
- Basso: barra azioni fissa (vedi §5).

---

## 3. Checklist per categoria

- Le categorie provengono dal campo `category` dei tweak (in v1: Privacy, Security, Performance, System, UI, AppDebloat, Services — l'unico tweak in "Security" è `wpbt-disable`, di rischio medium).
- Ogni riga-tweak:
  - Checkbox per la selezione;
  - `name`;
  - badge **risk** (colore: verde=low, ambra=medium, rosso=high — il rosso non compare in v1);
  - icona di stato di verifica (✅/⚪/⚠) ottenuta dall'ultima esecuzione di "Verifica";
  - icona "richiede amministratore" se `requiresAdministrator=true`.
- Raggruppamento con intestazione di categoria; barra di ricerca per filtrare per nome/descrizione.
- I tweak con `restartRequired=reboot` mostrano l'etichetta "Richiede riavvio".

---

## 4. Pannello di dettaglio del tweak selezionato

Quando l'utente seleziona una riga, il pannello mostra:

- **Nome** e **descrizione**.
- **Metadati** (badge/campi):
  - `risk` (low/medium);
  - `scope` (user/machine/both);
  - `requiresAdministrator` (Sì/No + icona scudo);
  - `restartRequired` (none/explorer/service/reboot);
  - `osVersions` (win10/win11);
  - `irreversible` (in v1 sempre false; campo presente per completezza).
- **Avvisi** (`warnings[]`): elenco con icona ⚠; se presente, l'utente deve averli letti (min-height di scroll) prima di poter applicare quel tweak (vedi §5.3).
- **Precondizioni** (`preconditions[]`): elencate come checklist informativa (l'app non le forza, ma le mostra).
- **Servizi coinvolti** (`services[]`): nome + tipo di avvio.
- **Comandi applicati** (collapsible "Dettagli tecnici"): mostra `applyCommands`/`undoCommands`/`verifyCommands` in sola lettura, per trasparenza.
- Pulsante **Verifica** dedicato (vedi §5.2).

---

## 5. Barra azioni

### 5.1 Pulsante "Applica selezionati"
- Visibile/abilitato solo quando ≥1 tweak è selezionato.
- Mostra il contatore: `Applica selezionati (3)`.
- Alla pressione apre una **finestra di riepilogo e conferma** (vedi §6).

### 5.2 Pulsante "Verifica"
- Due livelli:
  - **Per singolo tweak** (nel pannello di dettaglio e/o icona in riga): esegue SOLO `verifyCommands`, nessuna modifica. Equivale a un **dry-run**.
  - **Verifica tutti** (opzionale in barra): itera sui tweak selezionati.
- L'esito aggiorna lo stato ✅/⚪/⚠ nella riga e mostra i dettagli nel pannello (esito per comando).

### 5.3 Attivazione del pulsante Applica
- Se un tweak selezionato ha `confirmDialog=true`, la finestra di conferma è **obbligatoria** (in v1 nessun tweak ha `confirmDialog=true`, ma la logica è pronta).
- Se un tweak selezionato ha `warnings` non vuoti, il riepilogo li mostra e richiede conferma esplicita.

---

## 6. Finestra "Riepilogo e conferma applicazione"

Prima di applicare:

1. **Riepilogo**: tabella con i tweak selezionati e per ciascuno `risk`, `scope`, `restartRequired`, eventuali `warnings`.
2. **Elevazione**: avviso "Questa operazione richiede privilegi di amministratore (UAC)" se ≥1 tweak ha `requiresAdministrator=true`.
3. **Riavvii**: elenco "Al termine potrebbe essere necessario: riavvio Esplora / riavvio servizio / riavvio Windows".
4. **Backup**: nota "Verrà creato un backup prima delle modifiche" + percorso cartella backup.
5. **Conferma**:
   - pulsante **Annulla**;
   - pulsante **Applica** (diventa attivo dopo aver "letto" gli avvisi, se presenti).
6. Durante l'esecuzione: finestra di avanzamento con barra di progresso per tweak e per comando, pulsante **Interrompi** (ferma la coda, propone rollback parziale).

---

## 7. Cronologia operazioni (HistoryView)

Tab "Cronologia": elenco delle operazioni eseguite nella sessione (e, opzionalmente, persistito su `logs/` per sessioni precedenti).

Per ogni voce:
- **Timestamp**;
- **Tweak** (`name` + `id`);
- **Operazione**: Applica / Annulla / Verifica;
- **Esito**: ✓ successo / ✗ errore / ⏳ parziale / riavvio pendente;
- **Backup** associato (id run).

### Funzionalità "Annulla"
- Per un tweak applicato, pulsante **Annulla** disponibile nella cronologia.
- Esegue `undoCommands` (e ripristina valori originali dal backup se necessario).
- Chiede conferma se il tweak ha `confirmDialog=true`.
- Al termine aggiorna lo stato di verifica.
- Tweak `user` annullabili senza elevazione; tweak `machine` richiedono elevazione (UAC) al momento dell'annullamento.

---

## 8. Stati visivi dei tweak

| Stato | Sorgente | Icona/colore |
|-------|----------|--------------|
| Non applicato | default | ⚪ grigio |
| Applicato | ultima verifica OK | ✅ verde |
| Non verificato / sconosciuto | nessuna verifica | — (nessuna icona) |
| Parziale / errore | verifica parziale | ⚠ ambra |
| Riavvio pendente | restartRequired non ancora soddisfatto | 🔄 blu |

---

## 9. Flusso utente tipico

```text
1. Apri app (powershell -File MyWinTweaks.ps1) → checklist per categoria (dati dal JSON).
2. Seleziona "Telemetry - Disable" → pannello dettaglio con avvisi.
3. [Verifica] → "non applicato" (dry-run).
4. Seleziona altri tweak (es. "Storage Sense", "Hibernation").
5. [Applica selezionati (3)] → riepilogo → conferma.
6. UAC (se serve) → backup → esegue → log → cronologia.
7. [Verifica] di nuovo → ✅ applicato.
8. In cronologia → [Annulla] → undo → [Verifica] → ⚪ non applicato.
```
