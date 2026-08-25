# CoattUp.ps1 — ENTRY POINT (GUI WPF)
# Avvio GUI:  powershell -ExecutionPolicy Bypass -File CoattUp.ps1
# Fallback console (per test/ambienti senza WPF):  ... -File CoattUp.ps1 -Console
#
# Single-file bootstrap: questo file può funzionare anche eseguito da solo, ad esempio
# tramite  irm https://Coatto.github.io/CoattUp/CoattUp.ps1 | iex
# Prima di avviare la GUI garantisce che il progetto completo (engine/, ui/, data/) sia
# presente in locale, scaricandolo da GitHub se manca (cartella installata: $HOME\CoattUp).
#
# Flusso:
#   0. bootstrap: determina la cartella radice (sviluppo o installazione) e scarica se serve;
#   1. importa il motore e la localizzazione;
#   2. carica e valida il catalogo (bloccante, riusa Load-TweakJson) con filtro risk=high;
#   3. mostra la finestra WPF (o l'elenco a console se -Console / GUI non disponibile).

# Le prime righe eseguibili NON devono essere [CmdletBinding()]/param(...): Invoke-Expression
# (es.  irm ... | iex ) fallisce se lo script inizia con l'attributo. I parametri opzionali
# vengono quindi letti manualmente da $args, così lo script funziona sia con "irm | iex" sia
# con una normale esecuzione (es. .\CoattUp.ps1 -Update).
$Quiet   = $false
$Console = $false
$Update  = $false
foreach ($__arg in $args) {
    switch ($__arg) {
        '-Quiet'   { $Quiet   = $true }
        '-Console' { $Console = $true }
        '-Update'  { $Update  = $true }
        default    { }
    }
}

$ErrorActionPreference = 'Stop'

# --- 0. BOOTSTRAP / single-file entry point ---------------------------------
# Determina la cartella radice di lavoro e, se i file essenziali non ci sono, scarica
# l'intero progetto da GitHub. Non hardcodiamo alcun percorso assoluto (es. Z:\).

$script:LocalDir = $null
if (-not [string]::IsNullOrEmpty($PSScriptRoot)) { $script:LocalDir = $PSScriptRoot }

# Verifica che una cartella contenga il progetto completo.
function Test-CoattUpProject {
    param([string]$Root)
    return (Test-Path (Join-Path $Root 'engine')) -and
           (Test-Path (Join-Path $Root 'ui')) -and
           (Test-Path (Join-Path $Root 'data'))
}

# Modalità sviluppo: eseguito da una cartella che contiene già engine/, ui/, data/.
$IsDev = $false
if ($null -ne $script:LocalDir -and (Test-CoattUpProject -Root $script:LocalDir)) {
    $IsDev = $true
    $root  = $script:LocalDir
}
else {
    $root = Join-Path $HOME 'CoattUp'
}

if (-not $Quiet) { Write-Host 'Verifica del progetto in corso...' }

# Esegue il download + estrazione dell'archivio nella cartella di installazione.
function Install-CoattUpFromGithub {
    param([string]$InstallRoot)
    try {
        if (-not (Test-Path $InstallRoot)) { New-Item -ItemType Directory -Path $InstallRoot -Force | Out-Null }

        if (-not $Quiet) { Write-Host 'Download del progetto in corso...' }
        $zipUrl  = 'https://github.com/Coatto/CoattUp/archive/refs/heads/main.zip'
        $zipPath = Join-Path $InstallRoot 'coattup-main.zip'
        Invoke-WebRequest -Uri $zipUrl -OutFile $zipPath -UseBasicParsing

        $extractRoot = Join-Path $InstallRoot '_extract'
        if (Test-Path $extractRoot) { Remove-Item -Recurse -Force $extractRoot }
        Expand-Archive -Path $zipPath -DestinationPath $extractRoot -Force

        # L'archivio di GitHub estrae in una sottocartella "CoattUp-main".
        $inner = Join-Path $extractRoot 'CoattUp-main'
        if (-not (Test-Path $inner)) {
            $first = Get-ChildItem -Path $extractRoot -Directory | Select-Object -First 1
            if ($null -ne $first) { $inner = $first.FullName }
        }
        if (-not (Test-Path $inner)) { throw "Archivio estratto in una struttura inattesa: $extractRoot" }

        Copy-Item -Path (Join-Path $inner '*') -Destination $InstallRoot -Recurse -Force

        Remove-Item -Recurse -Force $extractRoot -ErrorAction SilentlyContinue
        Remove-Item -Force $zipPath -ErrorAction SilentlyContinue

        if (-not $Quiet) { Write-Host "Installazione completata. Percorso di installazione: $InstallRoot" }
    }
    catch {
        Write-Host "Errore durante il download o l'estrazione del progetto: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host 'Impossibile avviare CoattUp senza i file necessari. Verifica la connessione e riprova.' -ForegroundColor Yellow
        exit 1
    }
}

# In modalità sviluppo l'installazione è già completa; -Update ha senso solo per
# l'installazione utente (forza il ri-scaricamento dell'ultima versione).
$projectComplete = Test-CoattUpProject -Root $root
if (-not $projectComplete -or ($Update -and -not $IsDev)) {
    if (-not $IsDev) {
        Install-CoattUpFromGithub -InstallRoot $root
        if (-not (Test-CoattUpProject -Root $root)) {
            Write-Host 'Il progetto scaricato non è completo. Verifica la connessione e riprova.' -ForegroundColor Red
            exit 1
        }
    }
    elseif (-not $Quiet) {
        Write-Host 'Progetto già presente in locale (modalità sviluppo). Nessun download necessario.'
    }
}
if (-not $Quiet) { Write-Host "Percorso di installazione: $root" }

$UiDir  = Join-Path $root 'ui'

# --- 1. Motore + localizzazione ---
Import-Module (Join-Path $root 'engine\TweakEngine.psm1') -Force -DisableNameChecking
# TweakVerifier non è re-esportato da TweakEngine: lo importiamo esplicitamente perché la GUI
# usa Verify-Tweak (solo verifyCommands, nessuna modifica).
Import-Module (Join-Path $root 'engine\TweakVerifier.psm1') -Force -DisableNameChecking
# Il Logger è caricato da TweakEngine nel suo scope di modulo, non in quello globale:
# lo importiamo esplicitamente perché la GUI usa Set-MyWinTweaksLogFile / Write-TweakLog
# direttamente nello scope dello script.
Import-Module (Join-Path $root 'engine\Logger.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $UiDir 'i18n.psm1') -Force -DisableNameChecking

# --- 0. Elevazione amministratore (solo GUI) ---
# Se la sessione non è elevata, relaunch automatico come Amministratore (UAC) e termina
# l'istanza corrente. In modalità -Console (test/fallback) NON rilancia: restano i privilegi
# correnti per non bloccare gli script di test.
if (-not $Console) {
    $identity    = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal   = New-Object Security.Principal.WindowsPrincipal $identity
    $isAdmin     = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        try { Write-Host (Get-UiText 'admin.relaunch') } catch { }
        $relaunchArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"{0}"' -f $MyInvocation.MyCommand.Path))
        if ($Quiet) { $relaunchArgs += '-Quiet' }
        try {
            Start-Process -FilePath 'powershell.exe' -ArgumentList $relaunchArgs -Verb RunAs
        }
        catch {
            try { Write-Host (Get-UiText 'admin.relaunch.fail') -ForegroundColor Yellow } catch { }
        }
        exit
    }
}

# --- 2. Caricamento + validazione bloccante del catalogo (usa i default del modulo) ---
$catalog = Load-TweakJson
# Load-TweakJson ha già scartato i tweak risk=high (filtro v1).
$activeTweaks = @($catalog.tweaks)

# --- 3. Elenco console (fallback / test) ---
function Show-ConsoleList {
    param([object[]]$Tweaks)
    if (-not $Quiet) {
        Write-Host ''
        Write-Host '=== CoattUp - Tweak disponibili (per categoria) ===' -ForegroundColor Cyan
    }
    $groups = $Tweaks | Group-Object category | Sort-Object @{Expression = { if ($_.Name -eq 'PocoUtili') { 1 } else { 0 } }}, { Get-CategoryUiLabel -Category $_.Name }
    foreach ($g in $groups) {
        if (-not $Quiet) { Write-Host '' ; Write-Host "[$((Get-CategoryUiLabel -Category $g.Name))]" -ForegroundColor Yellow }
        foreach ($t in ($g.Group | Sort-Object { Get-TweakUiName -Id $_.id })) {
            if (-not $Quiet) {
                Write-Host ("  {0,-46} (rischio: {1})" -f (Get-TweakUiName -Id $t.id), (Get-RiskLabel -Risk $t.risk))
            }
        }
    }
    if (-not $Quiet) {
        Write-Host ''
        Write-Host ("Totale: {0} tweak attivi (schema OK)." -f $Tweaks.Count) -ForegroundColor Green
    }
    return $Tweaks.Count
}

# --- 4. GUI WPF ---
# Funzioni di supporto della GUI definite nello SCRIPT scope (non annidate in Show-Gui):
# i gestori di evento WPF sono eseguiti fuori dallo stack di Show-Gui, quindi le funzioni
# devono essere sempre risolvibili. Usano $script:Ui (controlli) e $script:selectedCount.

# Messaggio nella barra di stato (mai crash).
function Set-Status {
    param([string]$Message)
    try { $script:Ui.Status.Text = $Message } catch { }
}

# Aggiunge una riga (a capo) al pannello Risultati, mantenendo le righe esistenti.
function Add-ResultLine {
    param([string]$Line)
    try {
        $current = [string]$script:Ui.Results.Text
        if ([string]::IsNullOrEmpty($current)) { $script:Ui.Results.Text = $Line }
        else { $script:Ui.Results.Text = $current + [Environment]::NewLine + $Line }
    } catch { }
}

# Colora la barra del titolo di sistema (caption) della finestra WPF con l'attributo DWM
# DWMWA_CAPTION_COLOR (attr 35, Windows 11 build 22000+). Best-effort: se non applicabile
# (sistema senza caption colorata) non fa nulla e non altera la struttura della finestra.
# Il colore è in ordine BGR come previsto dall'attributo DWM.
function Set-TitleBarColor {
    param($Window)
    try {
        if ($null -eq $Window) { return }
        Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class Dwm {
    [DllImport("dwmapi.dll")]
    public static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int attrValue, int attrSize);
}
"@ -ErrorAction SilentlyContinue
        $hwnd = ([System.Windows.Interop.WindowInteropHelper]::new($Window)).Handle
        if ($hwnd -eq [IntPtr]::Zero) { return }
        # Rosa confetto leggermente saturo: R=246 G=179 B=193 (#F6B3C1), valore BGR.
        $titleBarColor = (246 -shl 16) -bor (179 -shl 8) -bor 193
        [void][Dwm]::DwmSetWindowAttribute($hwnd, 35, [ref]$titleBarColor, 4)
    } catch { }
}

# Converte le sequenze letterali di newline ("\n" backslash-n e "`n" backtick-n) in un
# andata a capo reale. Applicato a TUTTI i testi mostrati (popup, dettaglio, avvisi) così
# non resta mai un "\n" visibile al posto dell'a-capo.
function Expand-NewLines {
    param([string]$Text)
    if ([string]::IsNullOrEmpty($Text)) { return $Text }
    $Text = $Text -replace '\\n', [Environment]::NewLine
    $Text = $Text -replace '`n', [Environment]::NewLine
    return $Text
}

# Logga un errore e lo mostra in italiano nella barra di stato.
function Log-Error {
    param([string]$Context, [string]$Message)
    try { Write-TweakLog -Level Error -Message "${Context}: $Message" } catch { }
    Set-Status ('Errore ({0}). Consulta il log.' -f $Context)
}

# Aggiorna contatore selezioni e barra di stato.
function Update-SelectionCount {
    try {
        $script:Ui.SelCount.Text = ('{0} selezionati' -f $script:selectedCount)
        Set-Status ('Pronto. {0} tweak attivi.' -f $script:Ui.TweakCount)
    } catch { }
}

# Aggiorna il colore dell'indicatore di stato reale di un tweak.
# Passed -> verde (attivo); Failed -> rosso morbido (non attivo); Error/altro -> grigio (non verificabile).
function Set-TweakStatusColor {
    param([string]$Id, [string]$Status)
    try {
        $script:realStatus[$Id] = $Status
        $dot = $script:statusDots[$Id]
        if ($null -eq $dot) { return }
        $brush = $null
        $label = 'status.unknown'
        switch ($Status) {
            'Passed' { $brush = $script:Ui.Window.FindResource('StatusActiveBrush');   $label = 'status.active' }
            'Failed' { $brush = $script:Ui.Window.FindResource('StatusInactiveBrush'); $label = 'status.inactive' }
            default  { $brush = $script:Ui.Window.FindResource('StatusUnknownBrush');  $label = 'status.error' }
        }
        if ($null -ne $brush) { $dot.Fill = $brush }
        $dot.ToolTip = (Get-UiText 'status.tooltip' -Args @((Get-UiText $label)))
    } catch { }
}

# Rileva lo stato reale (Verify-Tweak) dei tweak indicati e aggiorna i colori.
# Chiamato all'avvio e dopo applica/ripristina/verifica (aggiornamento temporizzato).
function Update-StatusForTweaks {
    param([object[]]$Tweaks)
    foreach ($tw in $Tweaks) {
        try {
            $res = Verify-Tweak -Tweak $tw
            if ($res.AllPassed) { Set-TweakStatusColor -Id $tw.id -Status 'Passed' }
            elseif (@($res.Results | Where-Object { $_.Status -eq 'Error' }).Count -gt 0) { Set-TweakStatusColor -Id $tw.id -Status 'Error' }
            else { Set-TweakStatusColor -Id $tw.id -Status 'Failed' }
        }
        catch { Set-TweakStatusColor -Id $tw.id -Status 'Error' }
    }
}

# Legge backup/index.json e restituisce l'ultimo file di backup non ancora ripristinato per tweak.
function Get-TweakBackupMap {
    $map = @{}
    $indexPath = Join-Path $root 'backup\index.json'
    if (-not (Test-Path -LiteralPath $indexPath)) { return $map }
    try {
        foreach ($e in @(Get-Content -LiteralPath $indexPath -Raw -Encoding UTF8 | ConvertFrom-Json)) {
            if (-not $e.reverted) { $map[$e.tweakId] = $e.backupFile }
        }
    } catch { }
    return $map
}

# Risolve una risorsa (brush/stile) senza MAI far fallire il dialogo per un riferimento mancante.
function Resolve-Resource {
    param($Window, [string]$Key)
    try { return $Window.FindResource($Key) } catch { return $null }
}

# Come sopra ma per i Brush: se la risorsa manca usa un colore esplicito coerente col tema.
function Resolve-Brush {
    param($Window, [string]$Key, [string]$FallbackHex)
    $r = Resolve-Resource -Window $Window -Key $Key
    if ($null -ne $r) { return $r }
    try { return (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString($FallbackHex))) } catch { return $null }
}

# Finestra di dialogo personalizzata (stile coerente con la palette).
# - Kind: info | success | warning | question | error (definisce icona e colore accento)
# - Buttons: OK (mono-pulsante) | YesNo (restituisce $true se l'utente conferma)
# - Lines: array di @{ Text; Color (hex '#..' o chiave brush); Bold }
function Show-StyledDialog {
    param(
        [string]$Title,
        [string]$Kind = 'info',
        [string]$Buttons = 'OK',
        [object[]]$Lines = @()
    )
    try {
        # Variabile di script per il risultato del dialogo: le closure PowerShell/WPF non
        # risolvono in modo affidabile variabili locali ($w) né $this.Tag quando l'evento
        # scatta fuori dal contesto di creazione. Usiamo $script:DlgResult, sempre nel
        # global/script scope, così il Sì/No/OK è affidabile.
        $script:DlgResult = $false
        $styles = New-Object System.Windows.ResourceDictionary
        $styles.Source = (New-Object System.Uri((Join-Path $UiDir 'styles.xaml')))

        $accent = switch ($Kind) {
            'success'  { '#16A34A' }
            'warning'  { '#D97706' }
            'error'    { '#DC2626' }
            'question' { '#2563EB' }
            default    { '#2563EB' }
        }
        $icon = switch ($Kind) {
            'success'  { '✓' }
            'warning'  { '⚠' }
            'error'    { '✕' }
            'question' { '?' }
            default    { 'ℹ' }
        }

        $w = New-Object System.Windows.Window
        $w.Title = $Title
        $w.Width = 620
        $w.SizeToContent = 'Height'
        $w.WindowStartupLocation = 'CenterOwner'
        try { if ($null -ne $script:Ui -and $null -ne $script:Ui.Window) { $w.Owner = $script:Ui.Window } } catch { }
        $w.ResizeMode = 'NoResize'
        $w.WindowStyle = 'SingleBorderWindow'
        $w.Resources.MergedDictionaries.Add($styles) | Out-Null
        $w.FontFamily = 'Segoe UI'
        $w.FontSize = 13
        $w.Foreground = Resolve-Brush -Window $w -Key 'TextBrush' -FallbackHex '#0F172A'
        $w.Background = Resolve-Brush -Window $w -Key 'AppBackgroundBrush' -FallbackHex '#EEF2F7'

        $dock = New-Object System.Windows.Controls.DockPanel

        # --- Header con gradiente + icona ---
        $c1 = [System.Windows.Media.ColorConverter]::ConvertFromString($accent)
        $c2 = [System.Windows.Media.ColorConverter]::ConvertFromString('#0D9488')
        $hdrBrush = New-Object System.Windows.Media.LinearGradientBrush
        $hdrBrush.StartPoint = New-Object System.Windows.Point(0, 0)
        $hdrBrush.EndPoint   = New-Object System.Windows.Point(1, 0)
        $hdrBrush.GradientStops.Add((New-Object System.Windows.Media.GradientStop($c1, 0))) | Out-Null
        $hdrBrush.GradientStops.Add((New-Object System.Windows.Media.GradientStop($c2, 1))) | Out-Null
        $hdr = New-Object System.Windows.Controls.Border
        $hdr.Background = $hdrBrush
        $hdr.Padding = '20,16'
        $hdrStack = New-Object System.Windows.Controls.StackPanel
        $hdrStack.Orientation = 'Horizontal'
        $iconTxt = New-Object System.Windows.Controls.TextBlock
        $iconTxt.Text = $icon
        $iconTxt.FontSize = 26
        $iconTxt.FontWeight = 'Bold'
        $iconTxt.Foreground = 'White'
        $iconTxt.VerticalAlignment = 'Center'
        $iconTxt.Margin = '0,0,14,0'
        $hdrStack.Children.Add($iconTxt) | Out-Null
        $titleTxt = New-Object System.Windows.Controls.TextBlock
        $titleTxt.Text = $Title
        $titleTxt.FontSize = 18
        $titleTxt.FontWeight = 'SemiBold'
        $titleTxt.Foreground = 'White'
        $titleTxt.VerticalAlignment = 'Center'
        $hdrStack.Children.Add($titleTxt) | Out-Null
        $hdr.Child = $hdrStack
        [System.Windows.Controls.DockPanel]::SetDock($hdr, 'Top')
        $dock.Children.Add($hdr) | Out-Null

        # --- Corpo ---
        $body = New-Object System.Windows.Controls.ScrollViewer
        $body.VerticalScrollBarVisibility = 'Auto'
        $body.MaxHeight = 340
        $bodyStack = New-Object System.Windows.Controls.StackPanel
        $bodyStack.Margin = '22,18'
        foreach ($line in @($Lines)) {
            $tb = New-Object System.Windows.Controls.TextBlock
            $tb.Text = Expand-NewLines ([string]$line.Text)
            $tb.TextWrapping = 'Wrap'
            $tb.Margin = '0,3,0,3'
            if ($line.ContainsKey('Bold') -and $line.Bold) { $tb.FontWeight = 'Bold' }
            $col = if ($line.ContainsKey('Color')) { $line.Color } else { 'TextBrush' }
            if ($col -is [string] -and $col.StartsWith('#')) {
                $tb.Foreground = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString($col)))
            }
            else {
                try { $tb.Foreground = $w.FindResource($col) } catch { }
            }
            $bodyStack.Children.Add($tb) | Out-Null
        }
        $body.Content = $bodyStack

        # --- Footer bottoni ---
        $footer = New-Object System.Windows.Controls.StackPanel
        $footer.Orientation = 'Horizontal'
        $footer.HorizontalAlignment = 'Right'
        $footer.Margin = '0,6,18,16'
        [System.Windows.Controls.DockPanel]::SetDock($footer, 'Bottom')
        if ($Buttons -eq 'YesNo') {
            $noBtn = New-Object System.Windows.Controls.Button
            $noBtn.Content = 'No'
            $sNo = Resolve-Resource -Window $w -Key 'SecondaryButtonStyle'
            if ($null -ne $sNo) { $noBtn.Style = $sNo }
            $noBtn.Margin = '0,0,8,0'
            # Gestore affidabile: scrive su $script:DlgResult e chiude la finestra via $this.Tag.
            $noBtn.Tag = $w
            $noBtn.Add_Click({ $script:DlgResult = $false; $dlg = $this.Tag; if ($null -ne $dlg) { $dlg.Close() } })
            $footer.Children.Add($noBtn) | Out-Null
            $yesBtn = New-Object System.Windows.Controls.Button
            $yesBtn.Content = 'Sì'
            $sYes = Resolve-Resource -Window $w -Key 'PrimaryButtonStyle'
            if ($null -ne $sYes) { $yesBtn.Style = $sYes }
            $yesBtn.Tag = $w
            $yesBtn.Add_Click({ $script:DlgResult = $true; $dlg = $this.Tag; if ($null -ne $dlg) { $dlg.Close() } })
            $footer.Children.Add($yesBtn) | Out-Null
        }
        else {
            $okBtn = New-Object System.Windows.Controls.Button
            $okBtn.Content = 'OK'
            $sOk = Resolve-Resource -Window $w -Key 'PrimaryButtonStyle'
            if ($null -ne $sOk) { $okBtn.Style = $sOk }
            $okBtn.Tag = $w
            $okBtn.Add_Click({ $script:DlgResult = $true; $dlg = $this.Tag; if ($null -ne $dlg) { $dlg.Close() } })
            $footer.Children.Add($okBtn) | Out-Null
        }
        $dock.Children.Add($footer) | Out-Null
        # Il corpo va aggiunto per ultimo (riempie lo spazio residuo del DockPanel).
        $dock.Children.Add($body) | Out-Null

        $w.Content = $dock
        $w.ShowDialog() | Out-Null
        return ($script:DlgResult -eq $true)
    }
    catch {
        try { Log-Error 'Dialogo' $_.Exception.Message } catch { }
        return $false
    }
}

# Riepilogo finale (finestra personalizzata, colore in base all'esito).
function Show-Summary {
    param([string]$Title, [string]$Body, [string[]]$Details, [string]$Kind = 'info')
    $lines = @(@{ Text = $Body; Bold = $true })
    foreach ($d in @($Details)) { $lines += @{ Text = $d } }
    Show-StyledDialog -Title $Title -Kind $Kind -Buttons 'OK' -Lines $lines | Out-Null
}

# Pompa il dispatcher WPF: permette alla finestra di restare reattiva durante i loop
# di applicazione/ripristino (evita il "freeze" dopo il popup di conferma).
function Invoke-DoEvents {
    try {
        $frame = New-Object System.Windows.Threading.DispatcherFrame
        $null = [System.Windows.Threading.Dispatcher]::CurrentDispatcher.BeginInvoke(
            [System.Windows.Threading.DispatcherPriority]::Background,
            [System.Windows.Threading.DispatcherOperationCallback]{ param($f) $f.Continue = $false; return $null },
            $frame)
        [System.Windows.Threading.Dispatcher]::PushFrame($frame)
    } catch { }
}

# Abilita/disabilita i pulsanti di azione durante un'operazione lunga (evita ri-entranze).
function Set-UiBusy {
    param([bool]$Busy)
    try {
        $script:Ui.BtnApply.IsEnabled  = -not $Busy
        $script:Ui.BtnUndo.IsEnabled   = -not $Busy
    } catch { }
}

# Popola il pannello dettaglio col tweak selezionato (tutto in italiano).
function Show-Detail {
    param($Tweak)
    try {
        if ($null -eq $Tweak) {
            $script:Ui.Placeholder.Visibility = 'Visible'
            $script:Ui.Content.Visibility     = 'Collapsed'
            Set-Status 'Nessun tweak selezionato.'
            return
        }
        $script:Ui.Placeholder.Visibility = 'Collapsed'
        $script:Ui.Content.Visibility     = 'Visible'

        $script:Ui.Title.Text       = (Get-TweakUiName -Id $Tweak.id)
        $script:Ui.Category.Text    = (Get-CategoryUiLabel -Category $Tweak.category)
        $script:Ui.Risk.Text        = (Get-RiskLabel -Risk $Tweak.risk)
        $riskKey = if ($Tweak.risk -eq 'high') { 'HighRiskBrush' }
                   elseif ($Tweak.risk -eq 'medium') { 'MediumRiskBrush' }
                   else { 'LowRiskBrush' }
        try { $script:Ui.Risk.Foreground = $script:Ui.Window.FindResource($riskKey) } catch { }

        $script:Ui.Scope.Text    = (Get-ScopeLabel -Scope $Tweak.scope)
        $script:Ui.Restart.Text  = (Get-RestartLabel -Restart $Tweak.restartRequired)
        $script:Ui.Admin.Text    = if ($Tweak.requiresAdministrator) { 'Sì' } else { 'No' }
        $warns = @($Tweak.warnings)
        $warnsText = if ($warns.Count -gt 0) { ($warns -join "`n") } else { 'Nessun avviso' }
        $script:Ui.Warnings.Text = Expand-NewLines ([string]$warnsText)
        $script:Ui.Description.Text = Expand-NewLines ([string]$Tweak.description)
        Set-Status ('Dettaglio: {0}' -f (Get-TweakUiName -Id $Tweak.id))
    }
    catch {
        Log-Error 'Dettaglio' $_.Exception.Message
    }
}

# Costruisce una singola riga-tweak con i suoi gestori.
# IMPORTANTE: i gestori NON usano variabili chiuse dalla funzione (le closure di PowerShell non
# le risolvono in modo affidabile quando WPF esegue l'evento fuori dallo stack di creazione).
# Usano invece `$this` (l'oggetto che ha generato l'evento): da lì leggono il tweak (.Tag)
# e i controlli correlati (.DataContext / .Header.Children) senza mai leggere .IsChecked/.IsSelected
# dall'oggetto dati del tweak.
function New-TweakTreeItem {
    param($Tweak)
    $item = New-Object System.Windows.Controls.TreeViewItem
    try { $item.Style = $script:Ui.Window.FindResource('TweakTreeViewItemStyle') } catch { }
    $item.Tag = $Tweak

    $sp = New-Object System.Windows.Controls.StackPanel
    $sp.Orientation = 'Horizontal'

    $cb = New-Object System.Windows.Controls.CheckBox
    $cb.Tag = $Tweak
    $cb.DataContext = $item          # riferimento alla riga TreeViewItem
    $cb.Margin = '0,0,6,0'
    $cb.VerticalAlignment = 'Center'
    $script:checkBoxes[$Tweak.id] = $cb
    $cb.Add_Checked({
        if (-not $script:_updatingSelection) {
            $script:_updatingSelection = $true
            try {
                $script:selectedCount++
                Update-SelectionCount
                # $this = CheckBox. La riga è in .DataContext, il tweak in .Tag.
                $tw  = $this.Tag
                $row = $this.DataContext
                if ($null -ne $row) { $row.IsSelected = $true }
                if ($null -ne $tw)  {
                    Show-Detail -Tweak $tw
                    $script:selectedMap[$tw.id] = $tw
                }
            }
            catch { Log-Error 'Selezione' $_.Exception.Message }
            finally { $script:_updatingSelection = $false }
        }
    })
    $cb.Add_Unchecked({
        if (-not $script:_updatingSelection) {
            $script:_updatingSelection = $true
            try {
                if ($script:selectedCount -gt 0) { $script:selectedCount-- }
                $tw = $this.Tag
                if ($null -ne $tw) { $script:selectedMap.Remove($tw.id) }
                Update-SelectionCount
            }
            catch { Log-Error 'Deselezione' $_.Exception.Message }
            finally { $script:_updatingSelection = $false }
        }
    })
    $sp.Children.Add($cb) | Out-Null

    # Indicatore di stato reale (colore aggiornato solo dopo verify/apply/undo).
    $dot = New-Object System.Windows.Shapes.Ellipse
    $dot.Width = 10
    $dot.Height = 10
    $dot.Margin = '0,0,6,0'
    $dot.VerticalAlignment = 'Center'
    $dot.Fill = $script:Ui.Window.FindResource('StatusUnknownBrush')
    $dot.ToolTip = (Get-UiText 'status.unknown')
    $sp.Children.Add($dot) | Out-Null
    $script:statusDots[$Tweak.id] = $dot

    $nameTxt = New-Object System.Windows.Controls.TextBlock
    $nameTxt.Text = (Get-TweakUiName -Id $Tweak.id)
    $nameTxt.VerticalAlignment = 'Center'
    $sp.Children.Add($nameTxt) | Out-Null

    $item.Header = $sp
    $item.Add_Selected({
        try {
            # $this = TreeViewItem. Il tweak è in .Tag.
            $tw = $this.Tag
            if ($null -eq $tw) { Show-Detail -Tweak $null; return }
            Set-Status ('Selezionato: {0}' -f (Get-TweakUiName -Id $tw.id))
            Show-Detail -Tweak $tw
            # Coerenza: selezionare la riga spunta anche la checkbox (primo figlio dell'header).
            if (-not $script:_updatingSelection) {
                $script:_updatingSelection = $true
                try {
                    $cbox = $null
                    $hdr = $this.Header
                    if ($null -ne $hdr) { $cbox = $hdr.Children[0] }
                    if ($null -ne $cbox -and $cbox.IsChecked -ne $true) {
                        $cbox.IsChecked = $true
                        $script:selectedCount++
                        Update-SelectionCount
                    }
                }
                finally { $script:_updatingSelection = $false }
            }
        }
        catch { Log-Error 'Selezione riga' $_.Exception.Message }
    })
    return $item
}

# Verifica dei tweak selezionati (usa SOLO verifyCommands del motore: nessuna modifica).
function Invoke-VerifySelected {
    if ($script:selectedMap.Count -eq 0) {
        Set-Status 'Nessun tweak selezionato da verificare.'
        return
    }
    $sb = New-Object System.Text.StringBuilder
    $verified = @()
    [void]$sb.AppendLine('=== VERIFICA (solo comandi di lettura) ===')
    foreach ($tw in $script:selectedMap.Values) {
        try {
            $res = Verify-Tweak -Tweak $tw
            $verified += $tw
            if ($res.AllPassed) { $st = 'Verificato' }
            elseif (@($res.Results | Where-Object { $_.Status -eq 'Error' }).Count -gt 0) { $st = 'Errore' }
            else { $st = 'Non applicato' }
            [void]$sb.AppendLine(('{0,-46} {1}' -f (Get-TweakUiName -Id $tw.id), $st))
            foreach ($r in $res.Results) {
                $map = @{ 'Passed' = 'Passato'; 'Failed' = 'Fallito'; 'Error' = 'Errore' }
                $rs = if ($map.ContainsKey($r.Status)) { $map[$r.Status] } else { $r.Status }
                [void]$sb.AppendLine(('      comando: {0}' -f $rs))
            }
        }
        catch {
            [void]$sb.AppendLine(('{0,-46} Errore ({1})' -f (Get-TweakUiName -Id $tw.id), $_.Exception.Message))
        }
    }
    $script:Ui.Results.Text = $sb.ToString()
    Update-StatusForTweaks -Tweaks $verified
    Set-Status 'Verifica completata. Vedere Risultati.'
}

# Applicazione: ATTIVA SOLO i tweak spuntati e non ancora attivi. NESSUN tweak viene
# disattivato da Applica (la disattivazione avviene solo con "Annulla" / Invoke-UndoAll).
# - spuntato e non attivo  -> Apply-Tweak (ATTIVA)
# - spuntato e già attivo  -> nessuna azione (già attivo)
# - NON spuntato           -> NESSUN AZIONE (lasciato esattamente com'è)
function Invoke-ApplySelected {
    $toEnable = @()   # da attivare
    $already  = 0     # già attivi (nessuna azione)
    foreach ($tw in $script:allTweaks) {
        $cb = $script:checkBoxes[$tw.id]
        $desired = ($null -ne $cb -and $cb.IsChecked -eq $true)
        if (-not $desired) { continue }   # tweak non spuntato -> nessuna azione
        $active = $false
        try {
            $res = Verify-Tweak -Tweak $tw
            $hasErr = @($res.Results | Where-Object { $_.Status -eq 'Error' }).Count -gt 0
            $active = (-not $hasErr) -and $res.AllPassed
        } catch { $active = $false }
        if ($active) { $already++ }       # spuntato e già attivo -> nessuna azione
        else { $toEnable += $tw }         # spuntato e non attivo -> ATTIVA
    }

    if ($toEnable.Count -eq 0) {
        Set-Status (Get-UiText 'apply.none')
        return
    }

    # Finestra di conferma: solo elenco dei tweak da ATTIVARE (nessuna sezione "da DISATTIVARE").
    $dlgLines = @(
        @{ Text = (Get-UiText 'apply.confirm.body' -Args @('')); Bold = $true; Color = 'MutedTextBrush' },
        @{ Text = (Get-UiText 'apply.confirm.enable'); Bold = $true; Color = 'SuccessBrush' }
    )
    foreach ($tw in $toEnable) {
        $dlgLines += @{ Text = ('  + {0}' -f (Get-TweakUiName -Id $tw.id)); Color = 'SuccessBrush' }
    }
    $adminNeeded = @($toEnable | Where-Object { $_.requiresAdministrator }).Count -gt 0
    if ($adminNeeded) { $dlgLines += @{ Text = (Get-UiText 'apply.confirm.admin'); Color = 'MutedTextBrush' } }

    $confirm = Show-StyledDialog -Title (Get-UiText 'apply.confirm.title') -Kind 'question' -Buttons 'YesNo' -Lines $dlgLines
    if (-not $confirm) {
        Set-Status (Get-UiText 'apply.cancelled')
        return
    }

    $runId      = (Get-Date).ToString('yyyyMMddHHmmss')
    $backupRoot = Join-Path $root 'backup'
    $logFile    = Join-Path $root 'logs\app.log'

    Set-UiBusy -Busy $true
    try {
        $sb = New-Object System.Text.StringBuilder
        [void]$sb.AppendLine('=== APPLICAZIONE (attivazione) ===')
        $enabled = 0; $failed = 0
        foreach ($tw in $toEnable) {
            Invoke-DoEvents
            Set-Status (Get-UiText 'apply.progress.enable' -Args @((Get-TweakUiName -Id $tw.id)))
            try {
                $res = Apply-Tweak -Tweak $tw -RunId $runId -BackupRoot $backupRoot -LogFile $logFile
                if ($res.Success) {
                    $enabled++
                    $line = ('{0,-46} ATTIVATO' -f (Get-TweakUiName -Id $tw.id))
                    if ($tw.restartRequired -ne 'none') { $line += ('  · richiede riavvio: {0}' -f (Get-RestartLabel -Restart $tw.restartRequired)) }
                    [void]$sb.AppendLine($line)
                }
                else {
                    $failed++
                    [void]$sb.AppendLine(('{0,-46} ERRORE ({1})' -f (Get-TweakUiName -Id $tw.id), $res.Error))
                }
            }
            catch {
                $failed++
                [void]$sb.AppendLine(('{0,-46} ERRORE ({1})' -f (Get-TweakUiName -Id $tw.id), $_.Exception.Message))
            }
        }
        $script:Ui.Results.Text = $sb.ToString()
        Update-StatusForTweaks -Tweaks $script:allTweaks
        Set-Status (Get-UiText 'apply.done')
        $kind = if ($failed -gt 0 -and $enabled -eq 0) { 'error' }
                elseif ($failed -gt 0) { 'warning' }
                else { 'success' }
        Show-Summary -Title (Get-UiText 'apply.summary.title') -Kind $kind `
            -Body (Get-UiText 'apply.summary.body3' -Args @($enabled, $already, $failed)) `
            -Details @(
                (Get-UiText 'apply.result.enabled')       + ': ' + $enabled,
                (Get-UiText 'apply.result.alreadyPlural') + ': ' + $already,
                (Get-UiText 'apply.result.failed')        + ': ' + $failed
            )
    }
    finally { Set-UiBusy -Busy $false }
}

# Ripristino totale: Undo-Tweak su TUTTI i tweak del catalogo (stato default Windows),
# a prescindere dalle checkbox. Loop SEQUENZIALE sul thread UI + Invoke-DoEvents tra un
# tweak e l'altro per mantenere reattiva la finestra. Avviso prima, riepilogo dopo.
function Invoke-UndoAll {
    $logFile = Join-Path $root 'logs\app.log'

    # Carica TUTTI i tweak dal catalogo (indipendente dalla selezione).
    $tweaks = @()
    try {
        $tweaks = @((Load-TweakJson).tweaks)
    }
    catch {
        Set-Status 'Impossibile caricare il catalogo per il ripristino.'
        return
    }
    if ($tweaks.Count -eq 0) {
        Set-Status 'Nessun tweak da ripristinare.'
        return
    }

    # Avviso di conferma: se No, nessuna azione.
    $confirm = Show-StyledDialog -Title (Get-UiText 'undo.confirm.title') -Kind 'warning' -Buttons 'YesNo' `
        -Lines @(@{ Text = (Get-UiText 'undo.confirm.body'); Color = 'TextBrush' })
    if (-not $confirm) {
        Set-Status (Get-UiText 'undo.cancelled')
        return
    }

    $backupMap = Get-TweakBackupMap

    try { Write-TweakLog -Level Info -Message ("UNDO: avvio ripristino totale (" + $tweaks.Count + " tweak)") } catch { }

    Set-UiBusy -Busy $true
    try {
        $sb = New-Object System.Text.StringBuilder
        [void]$sb.AppendLine('=== RIPRISTINO TOTALE ===')
        $script:Ui.Results.Text = (Get-UiText 'undo.running')
        Set-Status (Get-UiText 'undo.running')
        $reverted = 0; $failed = 0
        foreach ($tw in $tweaks) {
            # Lascia respirare la UI e mostra il progresso.
            Invoke-DoEvents
            Set-Status (Get-UiText 'undo.progress' -Args @((Get-TweakUiName -Id $tw.id)))
            try { Write-TweakLog -Level Info -Message ("UNDO: processo " + $tw.id) } catch { }
            try {
                # -BackupFile $null è gestito: Undo-Tweak esegue comunque gli undoCommands.
                $res = Undo-Tweak -Tweak $tw -BackupFile $backupMap[$tw.id] -LogFile $logFile
                if ($res.Success) {
                    $reverted++
                    [void]$sb.AppendLine(('{0,-46} RIPRISTINATO' -f (Get-TweakUiName -Id $tw.id)))
                    try { Write-TweakLog -Level Info -Message ("UNDO: " + $tw.id + " OK") } catch { }
                }
                else {
                    $failed++
                    [void]$sb.AppendLine(('{0,-46} ERRORE ({1})' -f (Get-TweakUiName -Id $tw.id), $res.Error))
                    try { Write-TweakLog -Level Error -Message ("UNDO: " + $tw.id + " -> " + $res.Error) } catch { }
                }
            }
            catch {
                $failed++
                [void]$sb.AppendLine(('{0,-46} ERRORE ({1})' -f (Get-TweakUiName -Id $tw.id), $_.Exception.Message))
                try { Write-TweakLog -Level Error -Message ("UNDO: " + $tw.id + " -> " + $_.Exception.Message) } catch { }
            }
        }
        $script:Ui.Results.Text = $sb.ToString()
        Update-StatusForTweaks -Tweaks $tweaks

        # Ripristino totale: rimetti la barra di ricerca al DEFAULT Windows 11 (modo 3 =
        # "Casella di ricerca"), perché il tweak "Effetti visivi" la modifica. La shell si
        # aggiorna SENZA aprire finestre Esplora (Stop-Process fa riavviare Esplora da solo).
        try {
            Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' `
                -Name SearchboxTaskbarMode -Value 3 -Type DWord -ErrorAction Stop
            Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
            # Allinea anche la tendina allo stato reale (3).
            try {
                $script:_updatingSearchMode = $true
                foreach ($item in $script:Ui.SearchMode.Items) {
                    if ([int]$item.Tag -eq 3) { $script:Ui.SearchMode.SelectedItem = $item; break }
                }
            }
            finally { $script:_updatingSearchMode = $false }
        }
        catch { try { Write-TweakLog -Level Warning -Message ("UNDO: ripristino barra di ricerca -> " + $_.Exception.Message) } catch { } }

        Set-Status (Get-UiText 'undo.done')
        try { Write-TweakLog -Level Info -Message ("UNDO: terminato, ripristinati=" + $reverted + " falliti=" + $failed) } catch { }
        $kind = if ($failed -gt 0 -and $reverted -eq 0) { 'error' }
                elseif ($failed -gt 0) { 'warning' }
                else { 'success' }
        Show-Summary -Title (Get-UiText 'undo.summary.title') -Kind $kind `
            -Body (Get-UiText 'undo.summary.body' -Args @($reverted, $failed)) `
            -Details @(
                (Get-UiText 'undo.result.reverted') + ': ' + $reverted,
                (Get-UiText 'undo.result.failed') + ': ' + $failed
            )
    }
    finally { Set-UiBusy -Busy $false }
}


function Show-Gui {
    param([object[]]$Tweaks)
    Add-Type -AssemblyName PresentationFramework
    Add-Type -AssemblyName PresentationCore
    Add-Type -AssemblyName WindowsBase

    # Stili condivisi (ui/styles.xaml), caricati come ResourceDictionary e uniti alla finestra.
    $styles = New-Object System.Windows.ResourceDictionary
    $styles.Source = (New-Object System.Uri((Join-Path $UiDir 'styles.xaml')))

    # Layout principale (ui/main.xaml).
    [xml]$xaml = Get-Content -LiteralPath (Join-Path $UiDir 'main.xaml') -Raw -Encoding UTF8
    $reader = New-Object System.Xml.XmlNodeReader $xaml
    $window = [System.Windows.Markup.XamlReader]::Load($reader)
    $window.Resources.MergedDictionaries.Add($styles)

    # Log operativo per la GUI (usa il logger del motore).
    Set-MyWinTweaksLogFile -Path (Join-Path $root 'logs\app.log')

    # Riferimenti agli elementi con x:Name. Li salviamo nello SCRIPT scope così i gestori
    # di evento (eseguiti da WPF, fuori dallo stack di Show-Gui) li trovano sempre.
    $script:Ui = @{}
    $script:Ui.Window      = $window
    $script:Ui.SearchBox   = $window.FindName('SearchBox')
    $script:Ui.Tree        = $window.FindName('TweakTree')
    $script:Ui.Placeholder = $window.FindName('DetailPlaceholder')
    $script:Ui.Content     = $window.FindName('DetailContent')
    $script:Ui.Title       = $window.FindName('DetailTitle')
    $script:Ui.Category    = $window.FindName('DetailCategory')
    $script:Ui.Risk        = $window.FindName('DetailRisk')
    $script:Ui.Scope       = $window.FindName('DetailScope')
    $script:Ui.Restart     = $window.FindName('DetailRestart')
    $script:Ui.Admin       = $window.FindName('DetailAdmin')
    $script:Ui.Warnings    = $window.FindName('DetailWarnings')
    $script:Ui.Description = $window.FindName('DetailDescription')
    $script:Ui.SelCount    = $window.FindName('SelectionCount')
    $script:Ui.Status      = $window.FindName('StatusText')
    $script:Ui.Results     = $window.FindName('ResultsBox')
    $script:Ui.BtnApply    = $window.FindName('BtnApply')
    $script:Ui.BtnUndo     = $window.FindName('BtnUndo')
    $script:Ui.SearchMode  = $window.FindName('SearchModeCombo')
    $script:Ui.BtnActivate = $window.FindName('BtnActivate')
    $script:Ui.BtnDebloat  = $window.FindName('BtnDebloat')
    $script:Ui.BtnDnsEthernet = $window.FindName('BtnDnsEthernet')
    $script:Ui.BtnDnsWifi     = $window.FindName('BtnDnsWifi')
    $script:Ui.BtnPower       = $window.FindName('BtnPower')
    $script:Ui.BtnHz          = $window.FindName('BtnHz')

    $script:selectedCount       = 0
    $script:_updatingSelection  = $false
    $script:selectedMap         = @{}
    $script:statusDots          = @{}
    $script:checkBoxes          = @{}
    $script:realStatus          = @{}
    $script:allTweaks           = @($Tweaks)
    $script:Ui.TweakCount       = $Tweaks.Count

    # Abilita e collega i pulsanti di azione.
    $script:Ui.BtnApply.IsEnabled  = $true
    $script:Ui.BtnUndo.IsEnabled   = $true
    $script:Ui.BtnApply.Add_Click({ try { Invoke-ApplySelected } catch { Log-Error 'Applicazione' $_.Exception.Message } })
    $script:Ui.BtnUndo.Add_Click({ try { Invoke-UndoAll } catch { Log-Error 'Ripristino' $_.Exception.Message } })

    # --- Bottone "Debloat app" (apre le Impostazioni di Windows alla pagina App installate) ---
    try {
        $debloatBtn = $script:Ui.BtnDebloat
        if ($null -ne $debloatBtn) {
            $debloatBtn.Add_Click({
                try {
                    Set-Status (Get-UiText 'debloat.launch')
                    Start-Process 'ms-settings:appsfeatures'
                }
                catch { Log-Error 'Debloat' $_.Exception.Message }
            })
        }
    }
    catch { Log-Error 'Debloat' $_.Exception.Message }

    # --- Riquadro "Cambia DNS": apre le impostazioni di rete, aggiunge una riga a Risultati ---
    try {
        $dnsEth = $script:Ui.BtnDnsEthernet
        $dnsWifi = $script:Ui.BtnDnsWifi
        if ($null -ne $dnsEth) {
            $dnsEth.Add_Click({
                try {
                    Add-ResultLine (Get-UiText 'dns.open' -Args @((Get-UiText 'dns.ethernet')))
                    Start-Process 'ms-settings:network-ethernet'
                }
                catch { Log-Error 'DNS Ethernet' $_.Exception.Message }
            })
        }
        if ($null -ne $dnsWifi) {
            $dnsWifi.Add_Click({
                try {
                    Add-ResultLine (Get-UiText 'dns.open' -Args @((Get-UiText 'dns.wifi')))
                    Start-Process 'ms-settings:network-wifi'
                }
                catch { Log-Error 'DNS Wi-Fi' $_.Exception.Message }
            })
        }
    }
    catch { Log-Error 'DNS' $_.Exception.Message }

    # --- Bottone "Risparmio energia": apre il pannello classico dei piani di alimentazione ---
    try {
        $powerBtn = $script:Ui.BtnPower
        if ($null -ne $powerBtn) {
            $powerBtn.Add_Click({
                try {
                    Add-ResultLine (Get-UiText 'power.open')
                    Start-Process 'control' -ArgumentList 'powercfg.cpl'
                }
                catch { Log-Error 'Risparmio energia' $_.Exception.Message }
            })
        }
    }
    catch { Log-Error 'Risparmio energia' $_.Exception.Message }

    # --- Bottone "Schermo": apre la pagina Schermo delle Impostazioni di Windows ---
    try {
        $hzBtn = $script:Ui.BtnHz
        if ($null -ne $hzBtn) {
            $hzBtn.Add_Click({
                try {
                    Add-ResultLine (Get-UiText 'screen.open')
                    Start-Process 'ms-settings:display'
                }
                catch { Log-Error 'Schermo' $_.Exception.Message }
            })
        }
    }
    catch { Log-Error 'Schermo' $_.Exception.Message }

    # --- Bottone "Attiva Windows" (avvia il tool esterno Massgrave in una finestra separata) ---
    try {
        $activateBtn = $script:Ui.BtnActivate
        if ($null -ne $activateBtn) {
            $activateBtn.Add_Click({
                try {
                    Set-Status (Get-UiText 'activate.launch')
                    # Apre una NUOVA finestra PowerShell amministratore (la GUI resta aperta).
                    # -NoExit: la finestra resta aperta dopo l'esecuzione per seguire il tool.
                    Start-Process powershell `
                        -ArgumentList @('-NoExit', '-ExecutionPolicy', 'Bypass', '-Command', 'irm https://get.activated.win | iex') `
                        -Verb RunAs -WindowStyle Normal
                }
                catch { Log-Error 'Attivazione' $_.Exception.Message }
            })
        }
    }
    catch { Log-Error 'Attivazione' $_.Exception.Message }

    # --- Menu a tendina "Barra di ricerca" (SearchBoxTaskbarMode 0..3) ---
    $script:_updatingSearchMode = $false
    try {
        $combo = $script:Ui.SearchMode
        if ($null -ne $combo) {
            $modes = @(
                @{ Value = 0; Label = (Get-UiText 'search.mode0') },
                @{ Value = 1; Label = (Get-UiText 'search.mode1') },
                @{ Value = 2; Label = (Get-UiText 'search.mode2') },
                @{ Value = 3; Label = (Get-UiText 'search.mode3') }
            )
            $script:_updatingSearchMode = $true
            try {
                foreach ($m in $modes) {
                    $item = New-Object System.Windows.Controls.ComboBoxItem
                    $item.Content = $m.Label
                    $item.Tag = $m.Value
                    $combo.Items.Add($item) | Out-Null
                }
                # Stato attuale all'avvio; se assente/illeggibile -> default Win11 = 3.
                $curVal = 3
                try {
                    $cur = Get-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' -Name SearchboxTaskbarMode -ErrorAction SilentlyContinue
                    if ($null -ne $cur -and $null -ne $cur.SearchboxTaskbarMode) { $curVal = [int]$cur.SearchboxTaskbarMode }
                } catch { }
                foreach ($item in $combo.Items) {
                    if ([int]$item.Tag -eq $curVal) { $combo.SelectedItem = $item; break }
                }
            }
            finally { $script:_updatingSearchMode = $false }

            $combo.Add_SelectionChanged({
                if ($script:_updatingSearchMode) { return }
                try {
                    # $this = ComboBox. Il valore selezionato è in .SelectedItem.Tag.
                    $cb = $this
                    $sel = $cb.SelectedItem
                    if ($null -eq $sel) { return }
                    $val = [int]$sel.Tag
                    Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' `
                        -Name SearchboxTaskbarMode -Value $val -Type DWord -ErrorAction Stop
                    Set-Status (Get-UiText 'search.applydone')
                    # Aggiorna la shell SENZA aprire finestre Esplora: Esplora si riavvia da solo.
                    try { Set-Status (Get-UiText 'search.refresh') } catch { }
                    Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
                }
                catch { Log-Error 'Barra di ricerca' $_.Exception.Message }
            })
        }
    }
    catch { Log-Error 'Barra di ricerca' $_.Exception.Message }

    # Costruisce la checklist raggruppata per categoria.
    $groups = $Tweaks | Group-Object category | Sort-Object @{Expression = { if ($_.Name -eq 'PocoUtili') { 1 } else { 0 } }}, { Get-CategoryUiLabel -Category $_.Name }
    foreach ($g in $groups) {
        $catItem = New-Object System.Windows.Controls.TreeViewItem
        try { $catItem.Style = $script:Ui.Window.FindResource('TweakTreeViewItemStyle') } catch { }
        $catHeader = New-Object System.Windows.Controls.TextBlock
        $catHeader.Text       = (Get-CategoryUiLabel -Category $g.Name)
        $catHeader.FontWeight = 'SemiBold'
        $catHeader.Margin     = '0,6,0,2'
        $catItem.Header       = $catHeader
        $catItem.IsExpanded   = $true

        foreach ($t in ($g.Group | Sort-Object { Get-TweakUiName -Id $_.id })) {
            $catItem.Items.Add((New-TweakTreeItem -Tweak $t)) | Out-Null
        }
        $script:Ui.Tree.Items.Add($catItem) | Out-Null
    }

    # Stato reale iniziale: Verify-Tweak per ogni tweak e colora SOLO l'indicatore.
    # Le checkbox restano tutte NON spuntate (la X = solo ciò che l'utente vuole applicare).
    Update-StatusForTweaks -Tweaks $script:allTweaks

    # Filtro di ricerca per nome/descrizione (robusto: nessun crash).
    $script:Ui.SearchBox.Add_TextChanged({
        try {
            $q = $script:Ui.SearchBox.Text.Trim()
            foreach ($catItem in $script:Ui.Tree.Items) {
                $catMatches = $false
                foreach ($item in $catItem.Items) {
                    $t = $item.Tag
                    $name = Get-TweakUiName -Id $t.id
                    $matches = -not $q -or $name -like "*$q*" -or $t.description -like "*$q*"
                    $item.Visibility = if ($matches) { 'Visible' } else { 'Collapsed' }
                    if ($matches) { $catMatches = $true }
                }
                $catItem.Visibility = if ($catMatches) { 'Visible' } else { 'Collapsed' }
            }
        }
        catch { Log-Error 'Ricerca' $_.Exception.Message }
    })

    Update-SelectionCount
    # Colora la title bar di sistema (best-effort) dopo la creazione dell'handle, prima del
    # primo render; la ri-applico anche all'evento Loaded per coprire i casi di primo frame.
    Set-TitleBarColor -Window $window
    $window.Add_Loaded({ Set-TitleBarColor -Window $script:Ui.Window })
    $window.Add_Closed({ $script:windowClosed = $true })
    $window.ShowDialog() | Out-Null
}

# --- Esecuzione ---
if ($Console) {
    Show-ConsoleList -Tweaks $activeTweaks
    exit 0
}

try {
    Show-Gui -Tweaks $activeTweaks
}
catch {
    if (-not $Quiet) {
        Write-Host ''
        Write-Host 'GUI non disponibile; mostro l''elenco a console.' -ForegroundColor Yellow
        Write-Host ("Motivo: {0}" -f $_.Exception.Message) -ForegroundColor DarkGray
        Write-Host ''
    }
    Show-ConsoleList -Tweaks $activeTweaks
    exit 1
}
