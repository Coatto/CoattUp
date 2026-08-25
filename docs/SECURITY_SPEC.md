# MyWinTweaks — Specifica di Sicurezza (v1)

> Requisiti di sicurezza trasversali all'applicazione. Principio guida: **nessuna modifica di sistema senza elevazione esplicita, validazione rigorosa e backup**.
> Stack: PowerShell + WPF (XAML puro).

---

## 1. Modello di minaccia (sintesi)

| Minaccia | Mitigazione |
|----------|-------------|
| JSON manomesso / malformato | Validazione schema + invarianti all'avvio (bloccante) |
| Injection nei comandi PowerShell | Niente input utente nei comandi; comandi dal JSON validato; nessuna interpolazione libera |
| Esecuzione con privilegi superflui | Elevazione UAC solo se necessario (vedi §2) |
| Tweak hardcoded / comportamento imprevisto | Motore guidato dai dati; nessun tweak nel codice |
| Danni non reversibili | Backup prima di ogni modifica + conferma per tweak a rischio |
| Exfiltration / log sensibili | Log senza segreti; percorso backup locale |
| Tweak high-risk applicati inavvertitamente | Filtro v1: scarta `risk=high`; `-AllowHighRisk $false` di default |

---

## 2. Elevazione UAC solo quando necessaria

- `requiresAdministrator` proviene dal JSON; non viene mai forzato né ignorato.
- **Regola**: un'operazione viene elevata **solo se** almeno un tweak selezionato ha `requiresAdministrator=true`.
- Se tutti i tweak selezionati sono `user` (`requiresAdministrator=false`), l'operazione gira **senza** UAC.
- Implementazione: `Start-Process powershell -Verb RunAs -ArgumentList <script> <piano>` sull'helper elevato; il piano è un file di lavoro serializzato temporaneo con UUID (non argomenti fragili).
- L'app **non** richiede mai di "eseguire sempre come amministratore" e non disattiva UAC.
- Se l'utente annulla il prompt UAC, l'operazione viene abortita senza effetti.

---

## 3. Validazione JSON all'avvio

1. `schema.json` (v2) viene letto e usato per validare `tweaks.normalized.json` con un validatore JSON Schema (o fallback a controlli strutturali manuali in `JsonValidation.psm1`).
2. Validazione **strutturale** (tipi, enum, campi richiesti, `additionalProperties:false`).
3. Validazione **di business** (invarianti: id univoci, set/remove, tipo/valore, admin da hive, irreversible↔undo, risk=high→confirm, services→restart).
4. Se una qualsiasi validazione fallisce → **l'app non si avvia**: finestra di errore bloccante con dettaglio. Non viene eseguito alcun comando.
5. Verifica `schemaVersion == 2`; versioni diverse → rifiuto.

---

## 4. Niente tweak hardcoded

- L'unica fonte dei tweak è `tweaks.normalized.json`.
- I moduli del motore **non contengono** alcun percorso di registro, valore, nome servizio o comando PowerShell di un tweak.
- Un tweak è "nuovo" semplicemente aggiungendo un oggetto al JSON (che supera la validazione). Nessuna modifica al codice.
- L'helper elevato riceve solo il piano serializzato (dal JSON validato), mai istruzioni hardcoded.

---

## 5. Backup prima delle modifiche

- Prima di ogni operazione di applicazione, `BackupManager.psm1` crea uno snapshot in `backup/<run>/`.
- Copre: valori di registro con `backupOriginalValue=true` (tipo+valore originali), stato/tipo di avvio dei servizi, variabili d'ambiente modificate.
- Il backup è scritto **prima** di eseguire qualsiasi `applyCommand` (write-ahead).
- In caso di errore l'utente può richiedere il ripristino dal backup (rollback).
- I file di backup sono salvati con permessi NTFS ristretti all'utente/admin.

---

## 6. Conferma per i tweak a rischio

- In v1 nessun tweak attivo è `high` né `confirmDialog=true` né `irreversible=true` (verificato sui dati: tutti low/medium, `irreversible=false`).
- Ciononostante il motore impone:
  - `risk=high` → **conferma obbligatoria** + necessità di `-AllowHighRisk $true` (mai in v1).
  - `confirmDialog=true` → finestra di conferma dedicata non bypassabile.
  - `warnings` non vuoti → mostrati e da far scorrere prima di confermare.
- Questa logica è **pronta** anche se in v1 non scatta.

---

## 7. Gestione sicura dei comandi PowerShell (no injection)

- **Nessun input utente** (testo libero) viene mai interpolato in un comando. La UI espone solo dati strutturati.
- I comandi sono stringhe statiche provenienti dal JSON **validato**; vengono eseguiti nel runspace del processo (o in quello elevato), **senza** concatenazione con input esterno.
- `$ErrorActionPreference='Stop'` durante l'apply; timeout per comando.
- **Dry-run**: il pulsante "Verifica" esegue **solo** `verifyCommands` (read-only), senza applicare nulla. È il metodo ufficiale per verificare lo stato senza rischi.

---

## 8. Log sicuri

- `logs/app.log`: rotazione per dimensione; retention configurata.
- Niente credenziali, token o dati personali nei log.
- Solo eventi di sistema critici in Event Viewer (elevazione, backup, applicazione).
- A livello Debug può comparire l'output dei comandi (utile per diagnostica) ma mai segreti.

---

## 9. Requisiti trasversali (checklist)

- [ ] UAC solo quando necessario.
- [ ] Validazione JSON all'avvio, bloccante su errore.
- [ ] Nessun tweak hardcoded.
- [ ] Backup write-ahead prima di ogni modifica.
- [ ] Conferma obbligatoria per `high`/`confirmDialog`/`warnings`.
- [ ] Nessun input utente nei comandi PowerShell.
- [ ] `verifyCommands` come unico meccanismo di verifica (dry-run).
- [ ] Log senza segreti.
- [ ] `-AllowHighRisk $false` di default (sezione Avanzate disattivata in v1).

---

## 10. Revisione di sicurezza pre-rilascio

- Eseguire `validate_tweaks.py` (o l'equivalente in `JsonValidation.psm1`) su `tweaks.normalized.json` prima di ogni rilascio → zero errori richiesti.
- Verificare che `tweaks.highrisk.json` non sia caricato dalla UI v1.
- Test manuale dell'elevazione in VM (vedi TEST_PLAN.md).
