# CoattUp

**Personalizza e ottimizza Windows in pochi clic — fork ispirato a WinUtil, interamente in italiano.**

![Windows 11](https://img.shields.io/badge/Windows%2011-%230078D6?style=flat-square)
![Windows 10](https://img.shields.io/badge/Windows%2010-%230078D6?style=flat-square)
![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-%23539CDB?style=flat-square)
![Versione](https://img.shields.io/badge/versione-1.0-blue?style=flat-square)
![Linguaggio](https://img.shields.io/badge/lingua-italiano-brightgreen?style=flat-square)

---

## Cos'è CoattUp

CoattUp è uno strumento **GUI in PowerShell/WPF** che applica tweak a Windows in modo semplice e sicuro, **interamente in italiano**.

A differenza di altri tool, CoattUp:
- mostra un elenco ordinato di tweak raggruppati per categoria;
- **verifica** lo stato reale di ogni tweak;
- ti permette di **applicare** solo ciò che spunti;
- offre un **ripristino totale** allo stato predefinito di Windows.

È pensato per chi vuole personalizzare il proprio sistema senza dover toccare manualmente il registro o imparare comandi complessi.

## Caratteristiche principali

- **GUI in italiano** con stile "Tramonto salvia" (verde salvia, crema, terracotta).
- Tweak raggruppati per categoria: **Privacy**, **Prestazioni**, **Sistema**, **Interfaccia** e altro.
- **Verifica automatica** dello stato reale di ogni tweak (indicatori colorati).
- **Applica selezione**: attiva solo i tweak che spunti.
- **Ripristino totale**: annulla tutto e riporta Windows ai valori predefiniti.
- Menu a tendina per la **barra di ricerca** di Windows.
- Pulsanti rapidi nella parte superiore:
  - **Cambia DNS** — apre le impostazioni di rete (Ethernet / Wi-Fi);
  - **Risparmio energia** — apre i piani di alimentazione;
  - **Schermo** — apre le impostazioni dello schermo;
  - **Debloat app** — apre la pagina "App installate" per gestire a mano le app;
  - **Attiva Windows** — apre il tool di attivazione Microsoft Activation Scripts (Massgrave).

## Requisiti

- **Windows 10** o **Windows 11**.
- **PowerShell 5.1 o superiore** (già incluso in Windows).
- **(Facoltativo) privilegi di amministratore** per alcuni tweak che modificano il sistema a livello globale.

## Installazione / Avvio

Avvia CoattUp direttamente da PowerShell con un comando (stile WinUtil):

```powershell
irm https://raw.githubusercontent.com/Coatto/CoattUp/main/CoattUp.ps1 | iex
```

Al termine del comando si apre la finestra grafica di CoattUp. Se esegui PowerShell **come amministratore**, saranno disponibili anche i tweak che richiedono privilegi elevati.

> Nota: il comando di pubblicazione sopra richiede che `CoattUp.ps1` sia disponibile nel ramo `main` del repository; la configurazione della pubblicazione verrà verificata a parte.

In alternativa, puoi scaricare il repository e avviare lo script manualmente:

```powershell
powershell -ExecutionPolicy Bypass -File CoattUp.ps1
```

## Uso

1. **Spunta** i tweak che vuoi applicare dall'elenco a sinistra (raggruppati per categoria).
2. Usa **Verifica** / lo stato automatico per controllare cosa è già attivo (gli indicatori colorati mostrano lo stato reale).
3. Premi **Applica selezione** per attivare solo i tweak spuntati e non ancora attivi.
4. Usa **Annulla** (ripristino totale) per riportare tutti i tweak allo stato predefinito di Windows.
5. Nella parte alta della finestra trovi i **pulsanti rapidi** (Cambia DNS, Risparmio energia, Schermo, Debloat app, Attiva Windows) per accedere alle relative impostazioni di sistema.

## Avvertenze / Sicurezza

- Alcuni tweak **modificano il registro di Windows** e possono richiedere privilegi di amministratore.
- Prima di applicare modifiche, **consigliamo di creare un punto di ripristino** del sistema, così da poter tornare indietro in caso di necessità.
- Usa CoattUp a tuo rischio: verifica sempre che un tweak sia adatto alle tue esigenze prima di applicarlo.

## Screenshot

![Screenshot GUI CoattUp]()

> Nota: lo screenshot della GUI verrà aggiunto qui a breve.

## Licenza

Distribuito con licenza **MIT** (vedere il file `LICENSE`).
