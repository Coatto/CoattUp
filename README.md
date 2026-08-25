CoattUp

Personalizza e ottimizza Windows in pochi clic — interamente in italiano.





Cos'è CoattUp

CoattUp è uno strumento grafico (GUI) in PowerShell/WPF che ti permette di personalizzare e ottimizzare Windows in modo semplice, con un'interfaccia interamente in italiano.

Selezioni i tweak che preferisci, li applichi con un clic e puoi sempre ripristinare tutto allo stato predefinito. Include anche pulsanti rapidi per accedere a impostazioni utili (DNS, risparmio energia, schermo, disinstallazione app).
Caratteristiche

    Interfaccia grafica interamente in italiano
    Tweak organizzati per categoria (Privacy, Prestazioni, Sistema, Interfaccia, Servizi, Rimozione app, Poco utili)
    Applicazione dei tweak selezionati e ripristino totale allo stato predefinito di Windows
    Verifica automatica dello stato di ogni tweak
    Pulsanti rapidi: Cambia DNS, Risparmio energia, Schermo, Debloat app, Attiva Windows
    Funziona con un semplice comando da PowerShell

Requisiti

    Windows 10 o Windows 11
    PowerShell 5.1 o superiore (già incluso in Windows)
    (Facoltativo) privilegi di amministratore per alcuni tweak che modificano il sistema a livello globale

Installazione / Avvio

Avvia CoattUp direttamente da PowerShell con un comando:
powershell
1
irm https://Coatto.github.io/CoattUp/CoattUp.ps1 | iex

Il comando scarica il progetto nella cartella CoattUp e apre la finestra grafica.

Se la prima esecuzione viene bloccata dalla protezione di Windows (Execution Policy), avvia PowerShell e lancia:
powershell
1
Set-ExecutionPolicy Bypass -Scope Process

poi ripeti il comando di avvio. In alternativa, apri PowerShell come amministratore.

    Consiglio: per usare tutti i tweak, esegui PowerShell come amministratore.

Uso

    Spunta i tweak che vuoi applicare nella lista a sinistra.
    Clicca Applica selezione.
    Usa Annulla per ripristinare tutto allo stato predefinito di Windows.
    Ogni tweak mostra categoria, rischio, ambito, riavvio richiesto ed eventuali avvisi.

Avvertenze / Sicurezza

    Alcuni tweak modificano il Registro di sistema.
    Per applicare alcuni tweak servono privilegi di amministratore (UAC).
    Consigliato: crea un punto di ripristino prima di applicare modifiche importanti.

Screenshot

(Aggiungi qui uno screenshot della GUI)
Licenza

Distribuito sotto licenza MIT. Vedere il file LICENSE.
