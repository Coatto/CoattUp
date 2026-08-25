# Logger.psm1 — Logging strutturato per MyWinTweaks (Incremento 1)
# Scrive su logs/app.log con rotazione per dimensione e retention.
# Nessun dato personale o segreto viene mai scritto.

$script:LogFilePath = $null
$script:MaxLogBytes = 1MB
$script:RetentionDays = 14

function Set-MyWinTweaksLogFile {
    <#
    .SYNOPSIS
        Imposta il percorso del file di log attivo.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )
    $script:LogFilePath = $Path
    $parent = Split-Path -Parent $Path
    if ($parent -and -not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType File -Path $Path -Force | Out-Null
    }
}

function Write-TweakLog {
    <#
    .SYNOPSIS
        Scrive una riga nel log con livello e timestamp.
    #>
    [CmdletBinding()]
    param(
        [ValidateSet('Debug', 'Info', 'Warning', 'Error')]
        [string]$Level = 'Info',
        [Parameter(Mandatory = $true)]
        [string]$Message
    )
    $ts = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss.fff')
    $line = "$ts [$Level] $Message"
    if (-not $script:LogFilePath) {
        return
    }
    if (Test-Path -LiteralPath $script:LogFilePath) {
        $len = (Get-Item -LiteralPath $script:LogFilePath).Length
        if ($len -gt $script:MaxLogBytes) {
            $rotated = $script:LogFilePath + '.1'
            Move-Item -LiteralPath $script:LogFilePath -Destination $rotated -Force
            New-Item -ItemType File -Path $script:LogFilePath -Force | Out-Null
            Remove-OldLogs
        }
    }
    Add-Content -LiteralPath $script:LogFilePath -Value $line -Encoding UTF8
}

function Remove-OldLogs {
    $dir = Split-Path -Parent $script:LogFilePath
    if (-not $dir) { return }
    $cutoff = (Get-Date).AddDays(-$script:RetentionDays)
    Get-ChildItem -LiteralPath $dir -Filter '*.log*' -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -lt $cutoff } |
        Remove-Item -Force -ErrorAction SilentlyContinue
}

Export-ModuleMember -Function Set-MyWinTweaksLogFile, Write-TweakLog
