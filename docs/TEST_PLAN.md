# MyWinTweaks — Piano di Test (v1)

> Obiettivo: verificare che l'app (PowerShell + WPF) applichi, annulli e verifichi correttamente i **20 tweak low/medium** di `tweaks.normalized.json`, senza toccare i 7 high-risk.
> Ambiente consigliato: **VM Windows 10 e 11** (snapshot) oppure PC con punto di ripristino creato prima dei test.

---

## 1. Strategia di test

- **Automatici / di unità (PowerShell)**: test su funzioni **pure** del motore con un framework di test PowerShell (es. Pester). Non richiedono admin né modifiche di sistema reali.
- **Manuali** (su VM con snapshot): esecuzione reale di apply/undo/verify, elevazione UAC, comportamenti di riavvio. Sono i test più importanti per i comandi PowerShell.
- Ordine di esecuzione dei tweak: **dal più innocuo al più invasivo** (vedi §4).

---

## 2. Test automatici / di unità (Pester su `engine/*.psm1`)

Le funzioni pure del motore vengono testate con **Pester**, senza eseguire comandi di sistema (i comandi che toccano il registro/servizi sono **mockati**):

| Area | Cosa si testa |
|------|---------------|
| **Validazione** | `tweaks.normalized.json` conforme a `schema.json` (logica in `JsonValidation.psm1`) |
| **Invarianti** | id univoci, set/remove coerenti, tipo/valore, admin da hive, irreversible↔undo, risk=high→confirm, services→restart, scope |
| **Filtro v1** | il caricatore scarta `risk=high`; `tweaks.highrisk.json` non caricato |
| **Parsing modello** | `ConvertFrom-Json` → PSCustomObject coerente con lo schema |
| **Backup** | `BackupManager` crea snapshot prima dell'apply; ripristino valori originali; marcatura `reverted` (mock dei cmdlet di lettura registro) |
| **Ordine comandi** | apply/undo eseguiti nell'ordine del file |
| **Elevazione (mockata)** | l'helper elevato (`Start-Process -Verb RunAs`) viene invocato solo se ≥1 `requiresAdministrator=true`; `user`-only non eleva |

> Nei test di unità, i comandi PowerShell di sistema sono **mockati** (`Mock Get-ItemProperty {...}`, `Mock Set-Service {...}`): si verifica la logica di orchestrazione, non i comandi reali. I comandi reali si provano solo nei test manuali in VM.

---

## 3. Test manuali — checklist in VM

### 3.1 Preparazione
- [ ] VM Windows 10 e Windows 11, snapshot pulito.
- [ ] Eseguire lo script `validate_tweaks.py` (o i test Pester di validazione) → **zero errori**.
- [ ] Creare un punto di ripristino di sistema (o usare lo snapshot) come rete di sicurezza.
- [ ] (opzionale) seconda VM con Brave/Edge installati per i tweak browser.

### 3.2 Avvio e validazione
- [ ] `powershell -ExecutionPolicy Bypass -File MyWinTweaks.ps1` si avvia e mostra la checklist (20 tweak, 0 high-risk).
- [ ] Copiando un JSON **volutamente invalido** (tipo errato / id duplicato) → l'app non si avvia e mostra errore bloccante.
- [ ] Nessun riferimento ai 7 high-risk nell'interfaccia.

### 3.3 Verifica (dry-run)
- [ ] Per ogni tweak, premere **Verifica** → stato "non applicato" (⚪), nessuna modifica di sistema.
- [ ] Dopo l'applicazione, **Verifica** → "applicato" (✅).

### 3.4 Elevazione UAC
- [ ] Selezione di soli tweak `user` (es. `storage-sense-disable`, `visual-effects-best-performance`) → **nessun** prompt UAC.
- [ ] Selezione con ≥1 tweak `machine` (es. `activity-history-disable`) → prompt UAC; annullando il prompt, nessuna modifica.

### 3.5 Backup e ripristino
- [ ] Applicare un tweak → verificare che esista `backup/<run>/<id>.json` con i valori originali.
- [ ] Annullare → i valori tornano allo stato originale; file di backup marcato `reverted`.

---

## 4. Ordine di test dei tweak (dal più innocuo al più invasivo)

Ordine consigliato, dai tweak senza riavvio/servizi ai più invasivi. Per ogni tweak: **Verifica → Applica → Verifica → Annulla → Verifica**.

### Gruppo A — Tweak `user`, nessun riavvio (innocui)
1. `storage-sense-disable` (Storage Sense) — nessun admin, nessun riavvio.
2. `visual-effects-best-performance` — admin no, riavvio Esplora.
3. `file-explorer-home-gallery-disable` — admin no, riavvio Esplora.
4. `end-task-right-click-enable` — admin no, riavvio Esplora.

### Gruppo B — Policy di sistema, nessun riavvio
5. `activity-history-disable`
6. `consumer-features-disable`
7. `delivery-optimization-disable`
8. `prevent-device-companion-apps`
9. `brave-browser-debloat` (se Brave installato)

### Gruppo C — Browser/telemetria con servizi
10. `edge-debloat` (se Edge presente)
11. `telemetry-disable` — riavvio servizio (diagtrack, wermgr).
12. `location-tracking-disable` — riavvio servizio (lfsvc).

### Gruppo D — Servizi di sistema
13. `services-set-to-manual` — riavvio servizi.

### Gruppo E — Debloat di app
14. `widgets-remove` — riavvio Esplora (reinstallabile).
15. `razer-software-auto-install-disable` (solo se la cartella Razer esiste, altrimenti fallisce l'icacls).

### Gruppo F — Modifiche di sistema con riavvio
16. `disable-reserved-storage` — richiede riavvio.
17. `date-time-utc` — richiede riavvio; da testare su dual-boot con cautela.
18. `wpbt-disable` — richiede riavvio.
19. `hibernation-disable` — attenzione a Fast Startup.

### Gruppo G — Di supporto (non invasivo)
20. `restore-point-create` — crea punto di ripristino; usalo come base prima dei gruppi E/F.

> **Regola di sicurezza**: i gruppi con `restartRequired=reboot` (F) vanno testati **per ultimi** e sempre dopo un punto di ripristino. I tweak `service`/`explorer` (B–E) vanno annullati e ri-verificati prima di procedere.

---

## 5. Verifica del rollback / annullamento

### 5.1 Annullo singolo
- [ ] Per ogni tweak applicato: **Cronologia → Annulla**.
- [ ] `undoCommands` eseguiti senza errori.
- [ ] Valori originali ripristinati (confronto col backup).
- [ ] **Verifica** post-annullo → "non applicato" (⚪).

### 5.2 Annullo multiplo / rollback parziale
- [ ] Applicare più tweak insieme; simulare un errore a metà (es. tweak che fallisce) → l'app propone il rollback parziale dei tweak già applicati.
- [ ] Verificare che i tweak annullati tornino allo stato originale e che i log riportino l'esito per ciascuno.

### 5.3 Errori di comando
- [ ] Tweak con precondizione non soddisfatta (es. `razer-software-auto-install-disable` senza cartella Razer) → l'app segnala l'errore senza rompere la coda, e permette di continuare o annullare.

---

## 6. Criteri di accettazione v1

- [ ] 20 tweak applicabili/annullabili/verificabili con esito coerente su Win10 e Win11 (dove applicabile per `osVersions`).
- [ ] Zero errori di validazione JSON.
- [ ] Nessun tweak high-risk nell'UI.
- [ ] Backup sempre creato prima delle modifiche; rollback funzionante.
- [ ] UAC richiesto solo quando necessario.
- [ ] "Verifica" non modifica mai lo stato.
- [ ] Log completi e senza dati sensibili.

---

## 7. Non testati in v1 (sezione Avanzate futura)

I 7 tweak high-risk di `tweaks.highrisk.json` NON vengono testati né esposti in v1. Il relativo piano di test (conferme obbligatorie, impatti su sicurezza/crittografia/dati) sarà definito quando la sezione "Avanzate" verrà abilitata.
