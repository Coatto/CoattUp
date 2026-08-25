# MyWinTweaks — Decisioni di progetto e normalizzazione

Questo documento registra le scelte fatte durante la conversione di `tweaks-raw.json` in `tweaks.normalized.json`, le regole di normalizzazione e le decisioni su casi ambigui. È il riferimento per chi mantiene il file.

---

## 1. Regole generali di normalizzazione

1. **Rappresentazione delle modifiche al registro**: ogni modifica è un oggetto strutturato `registryChanges`, con `operation`, `path` (formato PowerShell `HKLM:\...`), `name`, `type`, `value`, `backupOriginalValue`. Niente stringhe descrittive per il registro.

2. **`operation`**: 
   - `set` per scrivere/impostare un valore.
   - `remove` per eliminare un valore quando il comportamento corretto di ripristino è rimuoverlo (tipicamente le **chiavi di Policy**, dove il default è "Non configurato" = valore assente).

3. **Linguaggio naturale ≠ comando**. Righe come *"Rimuove la variabile utente OneDrive"* e *"Disabilita la funzionalità Recall"* sono descrizioni, non comandi, e **non** sono state tradotte in comandi inventati. Sono registrate in `decisions.md` e segnalate nel review come omesse.

4. **Non inventare comandi**: dove il sorgente è ambiguo o incompleto, il comando è stato completato **solo** quando il completamento è deterministico e standard (es. percorso `setup.exe`); altrimenti è stato omesso e documentato.

5. **`backupOriginalValue: true`** è impostato su quasi tutti i `set`, per consentire all'app di salvare e ripristinare il valore pre-esistente. Fa eccezione il caso in cui il ripristino corretto sia `remove` (chiavi di Policy), dove il backup è comunque conservato per informazione ma l'undo usa `remove`.

6. **`scope`** deriva dal tipo di chiave/comando:
   - solo `HKCU` → `user`
   - solo `HKLM`/servizi/DISM/powercfg/globali → `machine`
   - misto → `both`.

7. **`requiresAdministrator`**: `true` se c'è almeno una scrittura HKLM, cambio servizio, DISM, powercfg, rimozione Appx con `-AllUsers`, `winget` di sistema, o `icacls` su percorso di sistema.

8. **`restartRequired`**: massimo livello richiesto tra `none`/`explorer`/`service`/`reboot`.

---

## 2. Scelte per categoria

### 2.1 Categorie adottate
`Privacy`, `Security`, `Performance`, `System`, `UI`, `AppDebloat`, `Services`.

Assegnazioni:
- Privacy: #1, #5, #6, #11, #12, #13, #24, #26
- Security: #9, #15, #25
- Performance: #19, #20
- System: #2, #16, #21, #23
- UI: #4, #18, #22
- AppDebloat: #3, #8, #10, #14, #17, #27
- Services: #7

### 2.2 Rischio
- `low`: modifiche semplici, ripristino via `remove`, impatto limitato.
- `medium`: effetti collaterali possibili o ripristino parziale.
- `high`: distruttive o difficili da annullare (vedi sezione 4).

---

## 3. Decisioni sui casi ambigui

### 3.1 `Invoke-WinUtilExplorerUpdate -action "restart"` (#3 Widgets)
È una funzione **interna a WinUtil**, non disponibile fuori da quel contesto. Decisione: **non** includerla come comando; il riavvio di Esplora è gestito dal flag `restartRequired: explorer`. Documentato nel review.

### 3.2 `setup.exe --uninstall --system-level --force-uninstall --delete-profile` (#14 Edge)
Comando **privo di percorso**. Decisione: completato con il percorso standard di installazione a 64 bit `%ProgramFiles(x86)%\Microsoft\Edge\Application\setup.exe`. Comportamento di default se il percorso non esiste: il comando fallisce. Documentato come avvertenza.

### 3.3 `winget uninstall Copilot` (#24 Windows AI)
**Ambiguo** (manca l'ID del pacchetto). Decisione: normalizzato con l'ID Store di Copilot `9N2TQ8TN389S`, ma con **avvertenza esplicita** che l'ID va verificato prima dell'esecuzione, perché potrebbe variare per edizione/mercato.

### 3.4 `"Rimuove la variabile utente OneDrive"` (#17 OneDrive)
Linguaggio naturale. Decisione: **omesso**. Per rimuovere una variabile utente serve il nome esatto (non indicato) e la cancellazione non è descritta come comando strutturato; non si inventa.

### 3.5 `"Disabilita la funzionalità Recall"` (#24 Windows AI)
Linguaggio naturale, **senza** alcuna conversione di registro/servizio chiara nel sorgente. Decisione: **omesso**. Il tweak normalizzato **non disattiva Recall**; aggiunta avvertenza esplicita. La disattivazione di Recall richiede una decisione separata e una procedura propria.

### 3.6 `icacls $Env:OneDrive /deny "Administrators:(D,DC)"` (#17 OneDrive)
Riga non affidata (uso di `$Env:OneDrive` non standardizzato, comportamento non necessario per la rimozione). Decisione: **omesso** per evitare di applicare un'ACL potenzialmente dannosa senza una chiara procedura di ripristino.

### 3.7 `RealTimeIsUniversal` QWORD → DWORD (#16)
Il sorgente dichiarava `[QWORD]`, ma il valore è realmente un **REG_DWORD**. Decisione: normalizzato come `DWord`. Segnalato come errore di tipo nel review.

### 3.8 `TaskbarMn` (#19 Visual Effects)
Nome non standard e poco documentato nel ramo `Explorer\Advanced`. Decisione: **mantenuto** perché presente nel sorgente, ma con avvertenza che potrebbe essere ignorato su molte build.

### 3.9 `UserPreferencesMask` (#19 Visual Effects)
Valore **Binary** (array di byte) calcolato. Decisione: normalizzato come `Binary` con il byte-array dato. Il ripristino esatto dipende dal salvataggio del valore originale (`backupOriginalValue`).

### 3.10 Chiavi di Policy e `remove` come ripristino
Per tutte le chiavi sotto `...\Policies\...` (e Feature Management), il ripristino corretto è **rimuovere** il valore per tornare a "Non configurato", non impostare un valore "di default" che potrebbe non esistere. Questo è il motivo per cui molti `registryChanges` di applicazione sono `set` ma il ripristino concettuale è `remove`.

### 3.11 `SettingsPageVisibility = "hide:aicomponents"` (#24)
Valore String con contenuto `hide:aicomponents`, coerente con la semantica della policy. Normalizzato come `String`.

### 3.12 `winget uninstall Copilot` vs rimozione Appx
La voce usa sia `Remove-AppxPackage` (per `*Copilot*`) sia `winget`. Decisione: mantenuti entrambi; l'Appx removal copre i pacchetti installati, `winget` copre il pacchetto Store autonomo.

---

## 4. Tweak marcati `high` (distruttivi / difficili da annullare)
Qui è **obbligatoria** una conferma esplicita dell'utente nell'interfaccia prima dell'applicazione.

- **#4 Start Menu Previous Layout** — Feature Management non documentato, ripristino ambiguo.
- **#5 Store Recommended Search** — ACL su `store.db`, fragile e con potenziale rottura dello Store.
- **#9 RDP Unsigned File Warnings** — riduce la sicurezza.
- **#14 Edge Remove** — `--delete-profile` cancella profilo irreversibilmente.
- **#15 BitLocker Disable** — disabilita la crittografia del disco.
- **#17 OneDrive Remove** — cancella dati locali ricorsivamente.
- **#24 Windows AI Remove** — rimuove componenti integrati, non sempre reinstallabili.

---

## 5. Ordine / dipendenze
Nessun tweak ha dipendenze tecniche da un altro (campo `dependencies` vuoto). Tuttavia, come best practice UI:
- I tweak che **disattivano servizi/telemetria** (#7, #12) dovrebbero essere mostrati prima di quelli che li rimuovono, se applicati insieme.
- Applicare #21 (Restore Point) **prima** di qualsiasi tweak `high`, per disporre di un punto di rollback.
- Per i tweak che richiedono `reboot` (#14, #15, #16, #17, #20, #24, #25) l'interfaccia deve segnalare che il riavvio è necessario per l'effetto completo.

---

## 6. Versioning e compatibilità futura
- `schemaVersion: 1` è fissato in `schema.json`. Un consumatore (l'app) deve **rifiutare** file con `schemaVersion` diverso.
- Gli `id` sono stabili e in kebab-case; non cambiare mai un `id` tra versioni, per non rompere il salvataggio dello stato "applicato/annullato" dell'utente.
- Aggiungere un tweak = aggiungere un nuovo oggetto con `id` univoco; modificare solo `name`/`description` non invalida lo stato salvato.

---

## 7. Cose da verificare prima dell'implementazione
1. Verificare l'ID Store di Copilot per `winget uninstall` (#24).
2. Verificare su quale edizione (Home/Pro) `AllowTelemetry` è onorato (#12).
3. Confermare se si desidera aggiungere una procedura dedicata per la disattivazione di **Recall** (attualmente non coperta).
4. Decidere se il tweak #21 (Restore Point) debba rimanere nel catalogo come tweak "attivo" o come azione separata.
5. Su Windows 10, molti tweak UI (#4, #18, #22) non avranno effetto: prevedere un filtro per versione OS.
