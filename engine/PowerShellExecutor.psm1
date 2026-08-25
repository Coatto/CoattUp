# PowerShellExecutor.psm1 — Esecuzione sicura dei comandi (Incremento 1)
# Esegue SOLO stringhe di comando provenienti dal JSON validato (applyCommands,
# undoCommands, verifyCommands). MAI input utente libero -> nessun vettore di injection.
# E' il punto unico di esecuzione: nei test Pester viene mockato.

# Timeout per comando (Appx/winget possono richiedere piu' tempo: default generoso, 180s).
$script:CommandTimeoutSeconds = 180

# Restituisce $true se il messaggio di errore indica una "risorsa inesistente" o una
# "operazione non supportata" (es. su una VM). In quel caso non c'è nulla da ripristinare,
# quindi il passaggio va considerato OK (non errore) invece di bloccare il ripristino.
function Test-BenignCommandError {
    param([string]$Message)
    if ([string]::IsNullOrWhiteSpace($Message)) { return $false }
    if ($Message -match '(?i)non supportat|not supported|unsupported|does not exist|not exist|cannot find|can.t find|impossibile trovare|non .? possibile trovare|non esiste|non trovato|path not found|not present|introvabile|service.*non esiste') {
        return $true
    }
    return $false
}

function Invoke-TweakCommand {
    <#
    .SYNOPSIS
        Esegue una singola stringa di comando (dal JSON validato) e ne cattura l'esito.
    .NOTES
        Per i test Pester questo cmdlet viene mockato per non toccare il sistema reale.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Command,
        [int]$TimeoutSeconds = $script:CommandTimeoutSeconds,
        [switch]$DryRun
    )
    if ([string]::IsNullOrWhiteSpace($Command)) {
        return [pscustomobject]@{ Success = $true; ExitCode = 0; Output = @(); Error = $null }
    }
    if ($DryRun) {
        return [pscustomobject]@{ Success = $true; ExitCode = 0; Output = 'DRY-RUN: comando non eseguito'; Error = $null }
    }

    $result = [pscustomobject]@{ Success = $false; ExitCode = -1; Output = @(); Error = $null }
    try {
        # Esecuzione in un runspace separato con TIMEOUT forzato: un comando che resta in
        # attesa (es. un processo esterno come powercfg.exe) NON deve bloccare il thread.
        # - Normale: stessa semantica di prima (scriptblock + ErrorActionPreference='Stop'),
        #   quindi successo/errore invariati per i comandi che completano.
        # - Timeout: il comando è considerato fallito e si prosegue (non bloccante).
        $runspace = [runspacefactory]::CreateRunspace()
        $runspace.Open()
        # Riproduce il comportamento originale: gli errori non terminanti diventano terminanti.
        try { $runspace.SessionStateProxy.SetVariable('ErrorActionPreference', 'Stop') } catch { }
        $ps = [System.Management.Automation.PowerShell]::Create()
        $ps.Runspace = $runspace
        $null = $ps.AddScript($Command)
        $iar = $ps.BeginInvoke()

        if ($iar.AsyncWaitHandle.WaitOne([TimeSpan]::FromSeconds($TimeoutSeconds))) {
            # Comando terminato entro il timeout: stesso esito di prima.
            try {
                $out = $ps.EndInvoke($iar)
                $result.Success = $true
                $result.ExitCode = 0
                $result.Output = @($out)
            }
            catch {
                $errs = @($ps.Streams.Error | ForEach-Object { $_.ToString() })
                $msg = if ($errs.Count -gt 0) { ($errs -join '; ') } else { $_.Exception.Message }
                if (Test-BenignCommandError -Message $msg) {
                    # Risorsa inesistente / operazione non supportata (es. VM): non è un errore,
                    # non c'è nulla da ripristinare -> considerato ok.
                    $result.Success = $true
                    $result.Error = $null
                    $result.Output = @('(nessuna azione necessaria: risorsa inesistente o non supportata)')
                }
                else {
                    $result.Success = $false
                    $result.Error = $msg
                }
            }
            finally {
                try { $ps.Dispose() } catch { }
                try { $runspace.Dispose() } catch { }
            }
        }
        else {
            # TIMEOUT: interrompi (in modo non bloccante) e considera il comando fallito.
            $result.Success = $false
            $result.Error = "Timeout dopo $TimeoutSeconds secondi (comando interrotto)"
            try { $ps.BeginStop($null, $null) } catch { }
            # Non chiamiamo Dispose sincrono qui (potrebbe attendere il processo bloccato):
            # il runspace/PowerShell saranno ripuliti dal GC. Il loop NON viene bloccato.
        }
    }
    catch {
        # Anche gli errori a livello di avvio del runspace possono essere benigni (risorsa assente).
        if (Test-BenignCommandError -Message $_.Exception.Message) {
            $result.Success = $true
            $result.Error = $null
        }
        else {
            $result.Success = $false
            $result.Error = $_.Exception.Message
        }
    }
    return $result
}

function Invoke-TweakCommandSequence {
    <#
    .SYNOPSIS
        Esegue una sequenza di comandi nell'ordine del file; si ferma al primo errore.
    .OUTPUTS
        Oggetto con .Success, .Results (per comando), .FailedCommand, .Error.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Commands,
        [int]$TimeoutSeconds = $script:CommandTimeoutSeconds,
        [switch]$DryRun
    )
    $results = @()
    foreach ($cmd in $Commands) {
        $r = Invoke-TweakCommand -Command $cmd -TimeoutSeconds $TimeoutSeconds -DryRun:$DryRun
        $results += [pscustomobject]@{
            Command = $cmd
            Success = $r.Success
            Output  = $r.Output
            Error   = $r.Error
        }
        if (-not $r.Success) {
            return [pscustomobject]@{
                Success        = $false
                Results        = $results
                FailedCommand  = $cmd
                Error          = $r.Error
            }
        }
    }
    return [pscustomobject]@{ Success = $true; Results = $results; FailedCommand = $null; Error = $null }
}

Export-ModuleMember -Function Invoke-TweakCommand, Invoke-TweakCommandSequence
