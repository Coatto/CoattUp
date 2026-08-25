# CoattUp

**Personalizza e ottimizza Windows in pochi clic — interamente in italiano.**

![Windows 11](https://img.shields.io/badge/Windows%2011-%230078D6?style=flat-square)
![Windows 10](https://img.shields.io/badge/Windows%2010-%230078D6?style=flat-square)
![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-%23539CDB?style=flat-square)
![Versione](https://img.shields.io/badge/versione-1.0-blue?style=flat-square)
![Linguaggio](https://img.shields.io/badge/lingua-italiano-brightgreen?style=flat-square)

---

## Cos'è CoattUp

**CoattUp** è uno strumento grafico (GUI) in PowerShell/WPF che ti permette di personalizzare e ottimizzare Windows in modo semplice, con un'interfaccia interamente in italiano.

Selezioni i tweak che preferisci, li applichi con un clic e puoi sempre ripristinare tutto allo stato predefinito. Include anche pulsanti rapidi per accedere a impostazioni utili (DNS, risparmio energia, schermo, disinstallazione app).

## Caratteristiche

- Interfaccia grafica interamente in italiano
- Tweak organizzati per categoria (Privacy, Prestazioni, Sistema, Interfaccia, Servizi, Rimozione app, Poco utili)
- Applicazione dei tweak selezionati e **ripristino totale** allo stato predefinito di Windows
- Verifica automatica dello stato di ogni tweak
- Pulsanti rapidi: Cambia DNS, Risparmio energia, Schermo, Debloat app, Attiva Windows
- Funziona con un semplice comando da PowerShell

## Requisiti

- **Windows 10** o **Windows 11**
- **PowerShell 5.1 o superiore** (già incluso in Windows)
- **(Facoltativo) privilegi di amministratore** per alcuni tweak che modificano il sistema a livello globale

## Installazione / Avvio

Avvia CoattUp direttamente da PowerShell con un comando:

```powershell
irm https://Coatto.github.io/CoattUp/CoattUp.ps1 | iex
