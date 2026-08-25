# BackupManager.psm1 — Backup write-ahead e ripristino dei valori di registro (Incremento 1)
# Prima di ogni modifica con backupOriginalValue=true salva valore/tipo originali.
# Struttura: backup/<timestamp>/<tweakId>.json  +  backup/index.json (traccia dei tweak applicati).
# L'accesso al registro passa da Get-ItemProperty / Set-ItemProperty: mockabile nei test Pester.

function ConvertTo-RegistryValueKind {
    <#
    .SYNOPSIS
        Converte il nome del tipo (schema) nel tipo [Microsoft.Win32.RegistryValueKind] PowerShell.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Type)
    switch ($Type) {
        'String'        { return [Microsoft.Win32.RegistryValueKind]::String }
        'ExpandString'  { return [Microsoft.Win32.RegistryValueKind]::ExpandString }
        'Binary'        { return [Microsoft.Win32.RegistryValueKind]::Binary }
        'DWord'         { return [Microsoft.Win32.RegistryValueKind]::DWord }
        'QWord'         { return [Microsoft.Win32.RegistryValueKind]::QWord }
        'MultiString'   { return [Microsoft.Win32.RegistryValueKind]::MultiString }
        default         { throw "Tipo registro non supportato: $Type" }
    }
}

function ConvertTo-RegistryValue {
    <#
    .SYNOPSIS
        Converte il valore JSON nel tipo .NET atteso dal registro (es. Binary -> byte[]).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Value,
        [Parameter(Mandatory = $true)][string]$Type
    )
    switch ($Type) {
        'Binary'      { return @($Value | ForEach-Object { [byte]$_ }) }
        'DWord'       { return [int]$Value }
        'QWord'       { return [int64]$Value }
        'MultiString' { return @([string[]]$Value) }
        default       { return [string]$Value }
    }
}

function Read-RegistryValue {
    <#
    .SYNOPSIS
        Legge un valore di registro esistente (mockabile nei test). Restituisce $null se assente.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Name
    )
    if (-not (Test-Path -LiteralPath $Path)) {
        return $null
    }
    try {
        $item = Get-ItemProperty -LiteralPath $Path -Name $Name -ErrorAction Stop
        $prop = $item.PSObject.Properties[$Name]
        if ($null -eq $prop) { return $null }
        return [pscustomobject]@{
            Type  = $prop.TypeNameOfValue
            Value = $prop.Value
        }
    }
    catch {
        return $null
    }
}

function New-TweakBackup {
    <#
    .SYNOPSIS
        Crea lo snapshot pre-modifica dei valori di registro per un tweak.
    .OUTPUTS
        Percorso del file di backup creato, o $null se non ci sono valori da salvare.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Tweak,
        [Parameter(Mandatory = $true)][string]$RunId,
        [Parameter(Mandatory = $true)][string]$BackupRoot
    )
    $regBackup = @()
    foreach ($change in @($Tweak.registryChanges)) {
        if ($change.operation -ne 'set') { continue }
        if (-not $change.backupOriginalValue) { continue }
        $orig = Read-RegistryValue -Path $change.path -Name $change.name
        if ($null -eq $orig) {
            $regBackup += [pscustomobject]@{
                path          = $change.path
                name          = $change.name
                existed       = $false
                originalType  = $null
                originalValue = $null
            }
        }
        else {
            $regBackup += [pscustomobject]@{
                path          = $change.path
                name          = $change.name
                existed       = $true
                originalType  = $orig.Type
                originalValue = $orig.Value
            }
        }
    }

    if ($regBackup.Count -eq 0) {
        return $null
    }

    $dir = Join-Path $BackupRoot $RunId
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $file = Join-Path $dir "$($Tweak.id).json"
    $payload = [pscustomobject]@{
        createdUtc    = (Get-Date).ToUniversalTime().ToString('o')
        tweakId       = $Tweak.id
        appliedAt     = (Get-Date).ToUniversalTime().ToString('o')
        reverted      = $false
        registryBackup = @($regBackup)
    }
    # Backup atomico: temp file poi rinomina.
    $tmp = "$file.tmp"
    $payload | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $tmp -Encoding UTF8
    Move-Item -LiteralPath $tmp -Destination $file -Force
    return $file
}

function Add-TweakToIndex {
    <#
    .SYNOPSIS
        Traccia il tweak applicato in backup/index.json per la cronologia.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$BackupRoot,
        [Parameter(Mandatory = $true)][string]$RunId,
        [Parameter(Mandatory = $true)][string]$TweakId,
        [string]$BackupFile
    )
    $indexPath = Join-Path $BackupRoot 'index.json'
    $index = @()
    if (Test-Path -LiteralPath $indexPath) {
        $index = @(Get-Content -LiteralPath $indexPath -Raw -Encoding UTF8 | ConvertFrom-Json)
    }
    $index += [pscustomobject]@{
        runId      = $RunId
        tweakId    = $TweakId
        appliedUtc = (Get-Date).ToUniversalTime().ToString('o')
        backupFile = $BackupFile
        reverted   = $false
    }
    $tmp = "$indexPath.tmp"
    @($index) | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $tmp -Encoding UTF8
    Move-Item -LiteralPath $tmp -Destination $indexPath -Force
}

function Restore-TweakBackup {
    <#
    .SYNOPSIS
        Ripristina i valori originali da un file di backup. Usato da Undo-Tweak come
        fallback di sicurezza quando l'undo non è un semplice remove.
    .OUTPUTS
        Oggetto con .Restored (bool) e .Details.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$BackupPath
    )
    if (-not (Test-Path -LiteralPath $BackupPath)) {
        return [pscustomobject]@{ Restored = $false; Details = "Backup non trovato: $BackupPath" }
    }
    $backup = Get-Content -LiteralPath $BackupPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $restored = $true
    $details = @()
    foreach ($entry in @($backup.registryBackup)) {
        try {
            if (-not (Test-Path -LiteralPath $entry.path)) {
                New-Item -Path $entry.path -Force | Out-Null
            }
            if ($entry.existed) {
                Set-ItemProperty -LiteralPath $entry.path -Name $entry.name `
                    -Value (ConvertTo-RegistryValue -Value $entry.originalValue -Type $entry.originalType) `
                    -Type (ConvertTo-RegistryValueKind -Type $entry.originalType) -ErrorAction Stop
            }
            else {
                Remove-ItemProperty -LiteralPath $entry.path -Name $entry.name -ErrorAction SilentlyContinue
            }
            $details += "Ripristinato: $($entry.path)\$($entry.name)"
        }
        catch {
            $restored = $false
            $details += "ERRORE ripristino $($entry.path)\$($entry.name): $($_.Exception.Message)"
        }
    }
    if ($restored) {
        $backup.reverted = $true
        $tmp = "$BackupPath.tmp"
        $backup | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $tmp -Encoding UTF8
        Move-Item -LiteralPath $tmp -Destination $BackupPath -Force
    }
    return [pscustomobject]@{ Restored = $restored; Details = $details }
}

Export-ModuleMember -Function ConvertTo-RegistryValueKind, ConvertTo-RegistryValue, Read-RegistryValue, New-TweakBackup, Add-TweakToIndex, Restore-TweakBackup
