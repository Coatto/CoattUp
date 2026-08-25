# i18n.psm1 — Localizzazione in italiano della UI CoattUp
#
# APPROCCIO (documentato):
# - I dati canonici in data/tweaks.normalized.json restano in inglese SOLO nel campo
#   `name` (identificativo di visualizzazione) e nei valori enumerati (category, risk,
#   scope, restartRequired). Le `description` e i `warnings` sono GIÀ in italiano nel JSON.
# - Per non alterare il JSON (che è la fonte unica per motore e test, lingua neutra),
#   la traduzione dei nomi dei tweak e delle etichette enumerate avviene qui, in una
#   tabella chiave->testo italiano indicizzata per `id`.
# - La UI usa SOLO le funzioni Get-* di questo modulo: mai testo inglese a schermo.

$script:TweakName = @{
    'activity-history-disable'            = 'Cronologia attività - Disattiva'
    'location-tracking-disable'           = 'Tracciamento posizione - Disattiva'
    'consumer-features-disable'           = 'Funzionalità consumer - Disattiva'
    'telemetry-disable'                   = 'Telemetria - Disattiva'
    'delivery-optimization-disable'       = 'Ottimizzazione recapito - Disattiva'
    'prevent-device-companion-apps'       = 'Impedisci app companion dei dispositivi'
    'hibernation-disable'                 = 'Ibernazione - Disattiva'
    'date-time-utc'                       = 'Data e ora - Imposta orologio a UTC'
    'restore-point-create'                = 'Punto di ripristino - Crea'
    'storage-sense-disable'               = 'Spazio di archiviazione - Disattiva'
    'widgets-remove'                      = 'Widget - Rimuovi'
    'brave-browser-debloat'               = 'Brave Browser - Rimozione funzioni superflue'
    'edge-debloat'                        = 'Microsoft Edge - Rimozione funzioni superflue'
    'razer-software-auto-install-disable' = 'Installazione automatica software Razer - Disattiva'
    'services-set-to-manual'              = 'Servizi - Imposta su manuale'
    'file-explorer-home-gallery-disable'  = 'Esplora file - Rimuovi Home e Galleria'
    'end-task-right-click-enable'         = 'Termina attività dal menu contestuale - Abilita'
    'visual-effects-best-performance'     = 'Effetti visivi - Prestazioni ottimali'
    'disable-reserved-storage'            = 'Spazio riservato - Disattiva'
    'wpbt-disable'                        = 'Tabella binaria piattaforma Windows (WPBT) - Disattiva'
    'mouse-pointer-precision-disable'     = 'Puntatore mouse - Aumenta precisione - Disattiva'
}

$script:CategoryLabel = @{
    'Privacy'     = 'Privacy'
    'Security'    = 'Sicurezza'
    'Performance' = 'Prestazioni'
    'System'      = 'Sistema'
    'UI'          = 'Interfaccia'
    'AppDebloat'  = 'Rimozione app'
    'Services'    = 'Servizi'
    'PocoUtili'   = 'Poco utili'
}

$script:RiskLabel = @{
    'low'    = 'Basso'
    'medium' = 'Medio'
    'high'   = 'Alto'
}

$script:ScopeLabel = @{
    'user'    = 'Utente'
    'machine' = 'Sistema'
    'both'    = 'Entrambi'
}

$script:RestartLabel = @{
    'none'    = 'Nessuno'
    'explorer' = 'Esplora file'
    'service'  = 'Servizio'
    'reboot'   = 'Riavvio'
}

function Get-TweakUiName {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Id)
    if ($script:TweakName.ContainsKey($Id)) { return $script:TweakName[$Id] }
    return $Id
}

function Get-CategoryUiLabel {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Category)
    if ($script:CategoryLabel.ContainsKey($Category)) { return $script:CategoryLabel[$Category] }
    return $Category
}

function Get-RiskLabel {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Risk)
    if ($script:RiskLabel.ContainsKey($Risk)) { return $script:RiskLabel[$Risk] }
    return $Risk
}

function Get-ScopeLabel {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Scope)
    if ($script:ScopeLabel.ContainsKey($Scope)) { return $script:ScopeLabel[$Scope] }
    return $Scope
}

function Get-RestartLabel {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Restart)
    if ($script:RestartLabel.ContainsKey($Restart)) { return $script:RestartLabel[$Restart] }
    return $Restart
}

# Testi UI generici (pulsanti, finestre di conferma/riepilogo, stato). Supportano {0}/{1}... per i -f.
$script:UiText = @{
    'apply.confirm.title'     = 'Conferma applicazione'
    'apply.confirm.body'      = "Si applicherà quanto segue:`n{0}`n`nProcedere?"
    'apply.confirm.admin'     = "`nNota: alcuni tweak richiedono privilegi di amministratore (UAC)."
    'apply.summary.title'     = 'Riepilogo applicazione'
    'apply.summary.body'      = '{0} applicati, {1} già attivi, {2} falliti'
    'apply.summary.body2'     = '{0} attivati, {1} disattivati, {2} falliti'
    'apply.summary.body3'     = '{0} attivati, {1} già attivi, {2} falliti'
    'apply.summary.details'   = '{0}: {1}'
    'apply.result.applied'    = 'applicato'
    'apply.result.already'    = 'già attivo'
    'apply.result.alreadyPlural' = 'già attivi'
    'apply.result.failed'     = 'fallito'
    'apply.result.enabled'    = 'attivati'
    'apply.result.disabled'   = 'disattivati'
    'apply.confirm.enable'    = 'DA ATTIVARE'
    'apply.confirm.disable'   = 'DA DISATTIVARE'
    'apply.none'              = 'Nessuna modifica necessaria: gli stati corrispondono alle selezioni.'
    'apply.progress.enable'   = 'Attivazione: {0}'
    'apply.progress.disable'  = 'Disattivazione: {0}'
    'apply.cancelled'         = 'Applicazione annullata.'
    'apply.empty'             = 'Nessun tweak selezionato da applicare.'

    'undo.confirm.title'      = 'Conferma ripristino totale'
    'undo.confirm.body'       = "Verranno ripristinati TUTTI i tweak allo stato di default di Windows appena installato.`n`nDopo il ripristino potrai scegliere di nuovo quali tweak rifare.`n`nProcedere?"
    'undo.summary.title'      = 'Riepilogo ripristino'
    'undo.summary.body'       = '{0} ripristinati, {1} falliti'
    'undo.result.reverted'    = 'ripristinato'
    'undo.result.failed'      = 'fallito'
    'undo.cancelled'          = 'Ripristino annullato. Nessuna modifica effettuata.'
    'undo.progress'           = 'Ripristino: {0}'
    'undo.running'            = 'Ripristino in corso...'
    'undo.backgroundError'    = 'Errore durante il ripristino in background. Consulta il log.'

    'status.active'           = 'Attivo'
    'status.inactive'         = 'Non attivo'
    'status.unknown'          = 'Stato non verificabile'
    'status.error'            = 'Errore di verifica'
    'status.tooltip'          = 'Stato reale: {0}'

    'search.label'            = 'Barra di ricerca:'
    'search.mode0'            = 'Nascondi'
    'search.mode1'            = 'Solo icona di ricerca'
    'search.mode2'            = 'Icona ed etichetta di ricerca'
    'search.mode3'            = 'Casella di ricerca'
    'search.applydone'        = 'Modalità barra di ricerca aggiornata.'
    'search.refresh'          = 'Riavvio Esplora per applicare la modifica...'

    'activate.label'          = 'Attiva Windows'
    'activate.note'           = 'Apre il tool di attivazione di Microsoft Activation Scripts (Massgrave) in una finestra separata.'
    'activate.launch'         = 'Apertura della finestra di attivazione...'
    'debloat.label'           = 'Debloat app'
    'debloat.tooltip'         = 'Apre le impostazioni per disinstallare le app installate a mano'
    'debloat.launch'          = 'Apertura delle impostazioni app...'
    'dns.title'               = 'Cambia DNS'
    'dns.ethernet'            = 'Ethernet'
    'dns.wifi'                = 'Wi-Fi'
    'dns.open'                = 'Apertura impostazioni DNS {0}...'
    'power.title'             = 'Risparmio energia'
    'power.open'              = 'Apertura Opzioni risparmio energia...'
    'screen.title'            = 'Schermo'
    'screen.open'             = 'Apertura impostazioni Schermo...'
    'verify.start'            = 'Verifica in corso...'
    'verify.done'             = 'Verifica completata.'
    'apply.done'              = 'Applicazione completata.'
    'undo.done'               = 'Ripristino completato.'
    'admin.relaunch'          = 'Avvio come amministratore in corso...'
    'admin.relaunch.fail'     = 'Impossibile avviare come amministratore. Esegui CoattUp.ps1 come Amministratore.'
}

function Get-UiText {
    <#
    .SYNOPSIS
        Restituisce un testo UI in italiano (con placeholder {0}.. opzionali).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Key,
        [object[]]$Args = @()
    )
    if (-not $script:UiText.ContainsKey($Key)) { return $Key }
    $t = $script:UiText[$Key]
    if ($Args.Count -gt 0) { return ($t -f $Args) }
    return $t
}

Export-ModuleMember -Function Get-TweakUiName, Get-CategoryUiLabel, Get-RiskLabel, Get-ScopeLabel, Get-RestartLabel, Get-UiText
