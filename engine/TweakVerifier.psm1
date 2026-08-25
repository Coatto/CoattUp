# TweakVerifier.psm1 — Verifica dello stato dei tweak (Incremento 1)
# Esegue SOLO verifyCommands (read-only): nessuna modifica di sistema (dry-run).
# Esito per comando: Passed / Failed / Error.

function Verify-Tweak {
    <#
    .SYNOPSIS
        Esegue solo i verifyCommands di un tweak e interpreta l'output booleano.
    .OUTPUTS
        Oggetto con .TweakId, .AllPassed, .Results[] (Command, Status, Output, Error).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Tweak
    )
    $results = @()
    $allPassed = $true
    foreach ($cmd in @($Tweak.verifyCommands)) {
        $status = 'Error'
        $err = $null
        $out = @()
        try {
            $previous = $ErrorActionPreference
            $ErrorActionPreference = 'Stop'
            $raw = & ([scriptblock]::Create($cmd)) 2>&1
            $ErrorActionPreference = $previous
            $out = @($raw)
            $bool = $false
            if ($out.Count -gt 0) {
                $bool = [bool]$out[0]
            }
            $status = if ($bool) { 'Passed' } else { 'Failed' }
            if (-not $bool) { $allPassed = $false }
        }
        catch {
            # Resilienza all'assenza di chiavi/valori di registro: se l'errore è del tipo
            # "path/chiave non esiste", il tweak non è applicato -> Failed (non Errore).
            $msg = $_.Exception.Message
            if ($msg -match '(?i)does not exist|not exist|cannot find path|cannot find|non esiste|non trovato|impossibile trovare il percorso|non è possibile trovare|non è presente|path not found') {
                $status = 'Failed'
            }
            else {
                $status = 'Error'
            }
            $err = $msg
            $allPassed = $false
        }
        $results += [pscustomobject]@{
            Command = $cmd
            Status  = $status
            Output  = $out
            Error   = $err
        }
    }
    return [pscustomobject]@{
        TweakId   = $Tweak.id
        AllPassed = $allPassed
        Results   = $results
    }
}

Export-ModuleMember -Function Verify-Tweak
