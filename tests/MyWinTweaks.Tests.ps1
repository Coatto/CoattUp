#Requires -Module Pester
# MyWinTweaks.Tests.ps1 — Test Pester sulle funzioni pure del motore (Incremento 1)
# DA ESEGUIRE NELLA VM WINDOWS 11:
#   Install-Module Pester -Force -Scope CurrentUser   (se non presente)
#   Invoke-Pester -Path tests\MyWinTweaks.Tests.ps1
#
# Nessun comando di sistema reale viene eseguito: registro/servizi/comandi sono MOCKATI.

$ErrorActionPreference = 'Stop'

# Percorsi ASSOLUTI basati su $PSScriptRoot. In Pester 6 il file di test gira in uno
# ScriptScope isolato dove $PSScriptRoot può risultare vuoto: in quel caso si ripiega
# sulla working directory (di norma la root del progetto).
$ProjectRoot = if ($PSScriptRoot) { Split-Path -Parent $PSScriptRoot } else { (Get-Location).Path }
$DataDir     = Join-Path $ProjectRoot 'data'
$JsonPath    = Join-Path $DataDir 'tweaks.normalized.json'
$SchemaPath  = Join-Path $DataDir 'schema.json'
$EngineDir   = Join-Path $ProjectRoot 'engine'

# CoattUp è un'applicazione Windows: alcuni test richiedono il registro di sistema reale
# (PSDrive HKCU/HKLM). Su host non-Windows questi vengono saltati invece di fallire.
$IsWindowsHost = [System.Environment]::OSVersion.Platform -eq 'Win32NT'

# Import esplicito del motore e dei suoi moduli (nessuna dipendenza da variabili
# di percorso che possano restare vuote nello scope isolato di Pester 6).
Import-Module (Join-Path $EngineDir 'TweakEngine.psm1') -Force
Import-Module (Join-Path $EngineDir 'TweakVerifier.psm1') -Force

Describe 'Load-TweakJson - dati validi' {
    It 'carica il catalogo reale e restituisce 20 tweak attivi (tutti low/medium)' {
        # Nessun -JsonPath/-SchemaPath: usa i DEFAULT interni del modulo (basati su
        # $PSScriptRoot DEL MODULO, sempre valorizzato) -> path sempre validi.
        $catalog = Load-TweakJson
        @($catalog.tweaks).Count | Should -Be 20
        @($catalog.tweaks | Where-Object { $_.risk -eq 'high' }).Count | Should -Be 0
    }
    It 'espone schemaVersion 2' {
        $catalog = Load-TweakJson
        $catalog.schemaVersion | Should -Be 2
    }
}

Describe 'Load-TweakJson - dati invalidi (bloccante)' {
    It 'lancia errore su JSON malformato' {
        $bad = Join-Path $TestDrive 'bad.json'
        Set-Content -LiteralPath $bad -Value '{ non valido' -Encoding UTF8
        { Load-TweakJson -JsonPath $bad -SchemaPath $SchemaPath } | Should -Throw
    }
    It 'lancia errore su schemaVersion non supportato' {
        $bad = Join-Path $TestDrive 'badversion.json'
        @{ schemaVersion = 3; tweaks = @() } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $bad -Encoding UTF8
        { Load-TweakJson -JsonPath $bad -SchemaPath $SchemaPath } | Should -Throw
    }
    It 'lancia errore su id duplicati (invariante di business)' {
        $dup = @{
            schemaVersion = 2
            tweaks = @(
                @{ id = 'x'; name = 'n'; description = 'd'; category = 'System'; scope = 'user'; requiresAdministrator = $false; risk = 'low'; irreversible = $false; confirmDialog = $false; restartRequired = 'none'; osVersions = @('win11'); preconditions = @(); services = @(); dependencies = @(); registryChanges = @(); applyCommands = @(); undoCommands = @('echo'); verifyCommands = @(); warnings = @() },
                @{ id = 'x'; name = 'n'; description = 'd'; category = 'System'; scope = 'user'; requiresAdministrator = $false; risk = 'low'; irreversible = $false; confirmDialog = $false; restartRequired = 'none'; osVersions = @('win11'); preconditions = @(); services = @(); dependencies = @(); registryChanges = @(); applyCommands = @(); undoCommands = @('echo'); verifyCommands = @(); warnings = @() }
            )
        }
        $f = Join-Path $TestDrive 'dup.json'
        $dup | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $f -Encoding UTF8
        { Load-TweakJson -JsonPath $f -SchemaPath $SchemaPath } | Should -Throw
    }
    It 'filtra via i tweak risk=high (filtro v1)' {
        $mixed = @{
            schemaVersion = 2
            tweaks = @(
                @{ id = 'ok'; name = 'n'; description = 'd'; category = 'System'; scope = 'user'; requiresAdministrator = $false; risk = 'low'; irreversible = $false; confirmDialog = $false; restartRequired = 'none'; osVersions = @('win11'); preconditions = @(); services = @(); dependencies = @(); registryChanges = @(); applyCommands = @(); undoCommands = @('echo'); verifyCommands = @(); warnings = @() },
                @{ id = 'risky'; name = 'n'; description = 'd'; category = 'System'; scope = 'machine'; requiresAdministrator = $true; risk = 'high'; irreversible = $true; confirmDialog = $true; restartRequired = 'none'; osVersions = @('win11'); preconditions = @(); services = @(); dependencies = @(); registryChanges = @(); applyCommands = @(); undoCommands = @(); verifyCommands = @(); warnings = @() }
            )
        }
        $f = Join-Path $TestDrive 'mixed.json'
        $mixed | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $f -Encoding UTF8
        # Path esplicito e valido SOLO su $TestDrive; SchemaPath usa il default del modulo.
        $catalog = Load-TweakJson -JsonPath $f
        @($catalog.tweaks).Count | Should -Be 1
        $catalog.tweaks[0].id | Should -Be 'ok'
    }
}

Describe 'Apply-Tweak (backup reale su temp, solo registro mockato)' {
    BeforeAll {
        # Come la diagnostica reale funzionante: NIENTE InModuleScope. Il motore è
        # già importato in cima. New-TweakBackup e Invoke-TweakCommandSequence restano
        # REALI (creano il backup in $TestDrive ed eseguono 'Write-Host'); si mockano
        # SOLO i cmdlet di sistema New-Item/Set-ItemProperty (chiamati dentro TweakEngine)
        # per non toccare il registro reale.
        $script:sample = @{
            id = 'sample'; name = 'n'; description = 'd'; category = 'System'; scope = 'user'
            requiresAdministrator = $false; risk = 'low'; irreversible = $false; confirmDialog = $false
            restartRequired = 'none'; osVersions = @('win11'); preconditions = @(); services = @()
            dependencies = @()
            registryChanges = @(
                @{ operation = 'set'; hive = 'HKCU'; path = 'HKCU:\Software\Test'; name = 'Flag'; type = 'DWord'; value = 1; backupOriginalValue = $true }
            )
            applyCommands = @('Write-Host "applied"')
            undoCommands = @()
            verifyCommands = @()
            warnings = @()
        } | ConvertTo-Json -Depth 6 | ConvertFrom-Json

        $script:backupRoot = Join-Path $TestDrive 'backup'
        $script:logFile    = Join-Path $TestDrive 'app.log'

        Mock New-Item -ModuleName TweakEngine { return $null }
        Mock Set-ItemProperty -ModuleName TweakEngine {}
    }
    It 'applica registryChanges e applyCommands, crea backup reale, success=true' -Skip:$(-not $IsWindowsHost) {
        $res = Apply-Tweak -Tweak $script:sample -RunId 'testrun' -BackupRoot $script:backupRoot -LogFile $script:logFile
        $res.Success | Should -Be $true
        $res.Applied | Should -Be $true
        # Il backup reale è stato creato da New-TweakBackup in $TestDrive\backup\testrun.
        (Test-Path -LiteralPath (Join-Path $script:backupRoot 'testrun\sample.json')) | Should -Be $true
    }
    It 'in modalita DryRun non esegue modifiche reali né scrive backup' {
        $res = Apply-Tweak -Tweak $script:sample -RunId 'testrun2' -BackupRoot $script:backupRoot -LogFile $script:logFile -DryRun
        $res.Success | Should -Be $true
        $res.Applied | Should -Be $true
        Should -Not -Invoke Set-ItemProperty -ModuleName TweakEngine
        # In DryRun New-TweakBackup è saltato: nessun file di backup per questo RunId.
        (Test-Path -LiteralPath (Join-Path $script:backupRoot 'testrun2\sample.json')) | Should -Be $false
    }
}

Describe 'Undo-Tweak (con mock dei cmdlet di sistema)' {
    InModuleScope TweakEngine {
        BeforeAll {
            $script:undoSample = @{
                id = 'sample'; name = 'n'; description = 'd'; category = 'System'; scope = 'user'
                requiresAdministrator = $false; risk = 'low'; irreversible = $false; confirmDialog = $false
                restartRequired = 'none'; osVersions = @('win11'); preconditions = @(); services = @()
                dependencies = @()
                registryChanges = @()
                applyCommands = @()
                undoCommands = @('Write-Host "annullato"')
                verifyCommands = @()
                warnings = @()
            } | ConvertTo-Json -Depth 6 | ConvertFrom-Json

            $script:undoLog = Join-Path $TestDrive 'undo.log'

            Mock Invoke-TweakCommandSequence {
                [pscustomobject]@{ Success = $true; Results = @(); FailedCommand = $null; Error = $null }
            }
        }
        It 'esegue undoCommands e marca reverted=true' {
            $res = Undo-Tweak -Tweak $script:undoSample -LogFile $script:undoLog
            $res.Success | Should -Be $true
            $res.Reverted | Should -Be $true
            Should -Invoke Invoke-TweakCommandSequence -Times 1 -Exactly
        }
    }
}

Describe 'Verify-Tweak (solo verifyCommands, nessuna modifica)' {
    BeforeAll {
        $script:verifySample = @{
            id = 'sample'; name = 'n'; description = 'd'; category = 'System'; scope = 'user'
            requiresAdministrator = $false; risk = 'low'; irreversible = $false; confirmDialog = $false
            restartRequired = 'none'; osVersions = @('win11'); preconditions = @(); services = @()
            dependencies = @()
            registryChanges = @()
            applyCommands = @()
            undoCommands = @()
            verifyCommands = @('1 -eq 1', '1 -eq 0')
            warnings = @()
        } | ConvertTo-Json -Depth 6 | ConvertFrom-Json
    }
    It 'interpreta output booleano e non esegue modifiche' {
        $res = Verify-Tweak -Tweak $script:verifySample
        $res.TweakId | Should -Be 'sample'
        $res.Results[0].Status | Should -Be 'Passed'
        $res.Results[1].Status | Should -Be 'Failed'
        $res.AllPassed | Should -Be $false
    }
    It 'segnala Error su eccezione del comando' {
        $bad = $script:verifySample.PSObject.Copy()
        $bad.verifyCommands = @('throw "boom"')
        $res = Verify-Tweak -Tweak $bad
        $res.Results[0].Status | Should -Be 'Error'
        $res.AllPassed | Should -Be $false
    }
}
