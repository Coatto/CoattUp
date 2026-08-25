# TweakEngine.psm1 — Motore principale di MyWinTweaks (Incremento 1)
# Carica/valida il catalogo e orchestra apply/undo/verify.
# Nessun tweak hardcoded: i dati vivono SOLO in data/tweaks.normalized.json.
# Importa i moduli di supporto: JsonValidation, BackupManager, PowerShellExecutor, TweakVerifier, Logger.

$script:EngineRoot = $PSScriptRoot
$script:DataRoot   = Join-Path (Split-Path -Parent $PSScriptRoot) 'data'

Import-Module (Join-Path $script:EngineRoot 'JsonValidation.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $script:EngineRoot 'BackupManager.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $script:EngineRoot 'PowerShellExecutor.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $script:EngineRoot 'TweakVerifier.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $script:EngineRoot 'Logger.psm1') -Force -DisableNameChecking

function Load-TweakJson {
    <#
    .SYNOPSIS
        Carica e valida il catalogo (data/tweaks.normalized.json) contro schema.json.
        Bloccante: se la validazione fallisce lancia un'eccezione e nessun comando viene eseguito.
        Scarta i tweak risk=high (filtro v1).
    .OUTPUTS
        Catalogo PSCustomObject con schemaVersion, source, description e tweaks (senza high-risk).
    #>
    [CmdletBinding()]
    param(
        [string]$JsonPath = (Join-Path $script:DataRoot 'tweaks.normalized.json'),
        [string]$SchemaPath = (Join-Path $script:DataRoot 'schema.json')
    )
    if (-not (Test-Path -LiteralPath $JsonPath)) {
        throw "File catalogo non trovato: $JsonPath"
    }
    if (-not (Test-Path -LiteralPath $SchemaPath)) {
        throw "File schema non trovato: $SchemaPath"
    }

    try {
        $catalog = Get-Content -LiteralPath $JsonPath -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    catch {
        throw "Impossibile decodificare il JSON '$JsonPath': $($_.Exception.Message)"
    }

    $validation = Get-TweakValidation -Catalog $catalog
    if (-not $validation.Valid) {
        $msg = "Validazione catalogo FALLITA ($($validation.Errors.Count) errore/i):`n" +
               ($validation.Errors | ForEach-Object { "  - $_" }) -join "`n"
        throw $msg
    }

    # Filtro v1: scarta ogni tweak risk=high (robustezza futura; non presenti in v1).
    $active = @($catalog.tweaks | Where-Object { $_.risk -ne 'high' })
    $catalog.tweaks = $active

    return $catalog
}

function Apply-Tweak {
    <#
    .SYNOPSIS
        Applica un tweak: registryChanges (operation=set) + applyCommands.
        Ignora i campi non eseguibili (services, dependencies, preconditions sono metadati).
        Backup pre-modifica per ogni valore con backupOriginalValue=true; log di ogni operazione.
    .OUTPUTS
        Oggetto di esito con .Success, .TweakId, .Applied, .FailedCommand, .Error, .BackupFile.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Tweak,
        [string]$RunId = (Get-Date).ToString('yyyyMMddHHmmss'),
        [string]$BackupRoot = (Join-Path (Split-Path -Parent $script:EngineRoot) 'backup'),
        [string]$LogFile = (Join-Path (Split-Path -Parent $script:EngineRoot) 'logs\app.log'),
        [switch]$DryRun
    )
    Set-MyWinTweaksLogFile -Path $LogFile
    Write-TweakLog -Level Info -Message "APPLY start: $($Tweak.id)"
    $result = [pscustomobject]@{
        Success      = $true
        TweakId      = $Tweak.id
        Applied      = $false
        FailedCommand = $null
        Error        = $null
        BackupFile   = $null
    }

    try {
        # 1) Backup write-ahead dei valori di registro con backupOriginalValue=true.
        $backupFile = $null
        if (-not $DryRun) {
            $backupFile = New-TweakBackup -Tweak $Tweak -RunId $RunId -BackupRoot $BackupRoot
            if ($backupFile) {
                Add-TweakToIndex -BackupRoot $BackupRoot -RunId $RunId -TweakId $Tweak.id -BackupFile $backupFile
                $result.BackupFile = $backupFile
                Write-TweakLog -Level Info -Message "  backup creato: $backupFile"
            }
        }

        # 2) RegistryChanges: applica solo operation=set (remove e' per l'undo).
        foreach ($change in @($Tweak.registryChanges)) {
            if ($change.operation -ne 'set') { continue }
            if (-not (Test-Path -LiteralPath $change.path)) {
                New-Item -Path $change.path -Force | Out-Null
            }
            $value = ConvertTo-RegistryValue -Value $change.value -Type $change.type
            $kind  = ConvertTo-RegistryValueKind -Type $change.type
            if (-not $DryRun) {
                Set-ItemProperty -LiteralPath $change.path -Name $change.name -Value $value -Type $kind -ErrorAction Stop
            }
            Write-TweakLog -Level Info -Message "  registry set: $($change.path)\$($change.name)"
        }

        # 3) applyCommands nell'ordine del file.
        if (@($Tweak.applyCommands).Count -gt 0) {
            $seq = Invoke-TweakCommandSequence -Commands @($Tweak.applyCommands) -DryRun:$DryRun
            if (-not $seq.Success) {
                $result.Success = $false
                $result.FailedCommand = $seq.FailedCommand
                $result.Error = $seq.Error
                Write-TweakLog -Level Error -Message "  applyCommands fallito: $($seq.FailedCommand) -> $($seq.Error)"
                return $result
            }
            foreach ($r in $seq.Results) {
                Write-TweakLog -Level Debug -Message "  cmd: $($r.Command) [ok=$($r.Success)]"
            }
        }

        $result.Applied = $true
        Write-TweakLog -Level Info -Message "APPLY end: $($Tweak.id) [ok]"
    }
    catch {
        $result.Success = $false
        $result.Error = $_.Exception.Message
        Write-TweakLog -Level Error -Message "APPLY errore: $($Tweak.id) -> $($_.Exception.Message)"
    }
    return $result
}

function Undo-Tweak {
    <#
    .SYNOPSIS
        Annulla un tweak: undoCommands nell'ordine del file + ripristino dei valori
        originali dal backup (fallback di sicurezza). Log di ogni operazione.
    .OUTPUTS
        Oggetto di esito con .Success, .TweakId, .Reverted, .FailedCommand, .Error.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Tweak,
        [string]$BackupFile,
        [string]$LogFile = (Join-Path (Split-Path -Parent $script:EngineRoot) 'logs\app.log'),
        [switch]$DryRun
    )
    Set-MyWinTweaksLogFile -Path $LogFile
    Write-TweakLog -Level Info -Message "UNDO start: $($Tweak.id)"
    $result = [pscustomobject]@{
        Success       = $true
        TweakId       = $Tweak.id
        Reverted      = $false
        FailedCommand = $null
        Error         = $null
    }

    try {
        # 1) undoCommands nell'ordine del file.
        if (@($Tweak.undoCommands).Count -gt 0) {
            $seq = Invoke-TweakCommandSequence -Commands @($Tweak.undoCommands) -DryRun:$DryRun
            if (-not $seq.Success) {
                $result.Success = $false
                $result.FailedCommand = $seq.FailedCommand
                $result.Error = $seq.Error
                Write-TweakLog -Level Error -Message "  undoCommands fallito: $($seq.FailedCommand) -> $($seq.Error)"
                return $result
            }
            foreach ($r in $seq.Results) {
                Write-TweakLog -Level Debug -Message "  cmd: $($r.Command) [ok=$($r.Success)]"
            }
        }

        # 2) Ripristino dei valori originali dal backup (fallback di sicurezza).
        if ($BackupFile -and -not $DryRun) {
            $restore = Restore-TweakBackup -BackupPath $BackupFile
            if (-not $restore.Restored) {
                $result.Success = $false
                $result.Error = ($restore.Details -join '; ')
                Write-TweakLog -Level Error -Message "  ripristino backup fallito: $($result.Error)"
                return $result
            }
            foreach ($d in $restore.Details) {
                Write-TweakLog -Level Info -Message "  $d"
            }
        }

        $result.Reverted = $true
        Write-TweakLog -Level Info -Message "UNDO end: $($Tweak.id) [ok]"
    }
    catch {
        $result.Success = $false
        $result.Error = $_.Exception.Message
        Write-TweakLog -Level Error -Message "UNDO errore: $($Tweak.id) -> $($_.Exception.Message)"
    }
    return $result
}

Export-ModuleMember -Function Load-TweakJson, Apply-Tweak, Undo-Tweak
