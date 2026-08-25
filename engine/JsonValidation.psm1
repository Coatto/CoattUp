# JsonValidation.psm1 — Validazione di tweaks.normalized.json contro schema.json (Incremento 1)
# Funzioni PURE: nessun accesso a registro/servizi/filesystem di sistema, solo analisi dati.
# PowerShell 5.1 non ha un validatore JSON-Schema nativo: implementiamo i controlli
# strutturali richiesti da schema.json (v2) + le invarianti di business di validate_tweaks.py.

$script:AllowedRegistryTypes = @('String', 'ExpandString', 'Binary', 'DWord', 'QWord', 'MultiString')
$script:AdminHives = @('HKLM', 'HKCR', 'HKU', 'HKCC')
$script:AllowedCategories = @('Privacy', 'Security', 'Performance', 'System', 'UI', 'AppDebloat', 'Services')
$script:AllowedScopes = @('user', 'machine', 'both')
$script:AllowedRisks = @('low', 'medium', 'high')
$script:AllowedRestarts = @('none', 'explorer', 'service', 'reboot')
$script:AllowedOsVersions = @('win10', 'win11')
$script:AllowedServiceActions = @('startup', 'stop', 'start', 'restart')
$script:AllowedStartupTypes = @('Automatic', 'AutomaticDelayedStart', 'Manual', 'Disabled')
$script:AllowedExpectedStates = @('Running', 'Stopped')

function New-TweakValidationResult {
    param([string[]]$Errors)
    [pscustomobject]@{
        Valid      = ($null -eq $Errors -or $Errors.Count -eq 0)
        Errors     = @($Errors)
        TweakCount = 0
    }
}

function Test-TweakCatalogShape {
    <#
    .SYNOPSIS
        Verifica la struttura di primo livello e la versione dello schema.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Catalog
    )
    $errors = @()
    if ($null -eq $Catalog) {
        return New-TweakValidationResult -Errors @('Catalogo nullo (JSON non decodificabile o mancante).')
    }
    if ($null -eq $Catalog.schemaVersion) {
        $errors += 'Manca il campo obbligatorio "schemaVersion".'
    }
    elseif ($Catalog.schemaVersion -ne 2) {
        $errors += "schemaVersion non supportato: $($Catalog.schemaVersion). Atteso: 2."
    }
    if ($null -eq $Catalog.tweaks -or -not ($Catalog.tweaks -is [array])) {
        $errors += 'Manca il campo obbligatorio "tweaks" (deve essere un array).'
    }
    $result = New-TweakValidationResult -Errors $errors
    if ($Catalog.tweaks -is [array]) {
        $result.TweakCount = $Catalog.tweaks.Count
    }
    return $result
}

function Test-TweakRequiredFields {
    <#
    .SYNOPSIS
        Verifica la presenza dei campi obbligatori di un singolo tweak (schema v2).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Tweak,
        [string]$TweakId
    )
    $required = @(
        'id', 'name', 'description', 'category', 'scope', 'requiresAdministrator',
        'risk', 'irreversible', 'confirmDialog', 'restartRequired', 'osVersions',
        'preconditions', 'services', 'dependencies', 'registryChanges',
        'applyCommands', 'undoCommands', 'verifyCommands', 'warnings'
    )
    $errors = @()
    foreach ($field in $required) {
        if (-not $Tweak.PSObject.Properties[$field]) {
            $errors += "[$TweakId] campo obbligatorio mancante: $field"
        }
    }
    return $errors
}

function Test-TweakRegistryChanges {
    <#
    .SYNOPSIS
        Verifica la coerenza strutturale di registryChanges (operation set/remove, tipo/valore).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$RegistryChanges,
        [string]$TweakId
    )
    $errors = @()
    foreach ($change in $RegistryChanges) {
        $op = $change.operation
        $hive = $change.hive
        $path = $change.path
        $name = $change.name
        $type = $change.type
        $value = $change.value

        if ($op -notin @('set', 'remove')) {
            $errors += "[$TweakId] operation non valida: '$op' (atteso set|remove)"
        }
        if ($hive -notin $script:AdminHives + @('HKCU')) {
            $errors += "[$TweakId] hive non valida: '$hive'"
        }
        if ($path -and $hive -and -not $path.StartsWith("$hive`:\")) {
            $errors += "[$TweakId] hive '$hive' non coerente col path '$path'"
        }
        if ($op -eq 'set') {
            if (-not $name) { $errors += "[$TweakId] operation=set senza 'name' ($path)" }
            if ($type -notin $script:AllowedRegistryTypes) { $errors += "[$TweakId] tipo registro non ammesso: '$type'" }
            if ($type -in @('DWord', 'QWord')) {
                # Accetta qualsiasi intero (Int32/Int64): ConvertFrom-Json restituisce
                # Int32 su Windows PowerShell 5.1 e Int64 su PowerShell 7.
                if ($value -isnot [int] -and $value -isnot [long]) { $errors += "[$TweakId] $type deve essere numerico intero: '$value'" }
            }
            elseif ($type -eq 'Binary') {
                $ok = $value -is [array] -and @($value | Where-Object { ($_ -isnot [int] -and $_ -isnot [long]) -or $_ -lt 0 -or $_ -gt 255 }).Count -eq 0
                if (-not $ok) { $errors += "[$TweakId] Binary deve essere un array di byte (0-255)" }
            }
            elseif ($type -in @('String', 'ExpandString', 'MultiString')) {
                if ($value -isnot [string]) { $errors += "[$TweakId] $type deve essere stringa" }
            }
        }
        elseif ($op -eq 'remove') {
            if ($null -ne $type -or $null -ne $value) {
                $errors += "[$TweakId] operation=remove non deve avere type/value"
            }
        }
    }
    return $errors
}

function Test-TweakInvariants {
    <#
    .SYNOPSIS
        Invarianti di business trasversali per l'intero catalogo (da validate_tweaks.py).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Tweaks
    )
    $errors = @()
    $ids = @($Tweaks | ForEach-Object { $_.id })
    $dup = $ids | Group-Object | Where-Object { $_.Count -gt 1 } | ForEach-Object { $_.Name }
    foreach ($d in $dup) { $errors += "id duplicato: $d" }

    foreach ($t in $Tweaks) {
        $tid = $t.id
        $risk = $t.risk
        $irr = $t.irreversible
        $conf = $t.confirmDialog
        $admin = $t.requiresAdministrator
        $scope = $t.scope
        $services = @($t.services)
        $restart = $t.restartRequired
        $undo = @($t.undoCommands)
        $rc = @($t.registryChanges)
        $hives = @($rc | Where-Object { $_.hive } | ForEach-Object { $_.hive } | Sort-Object -Unique)

        if ($risk -eq 'high' -and $conf -ne $true) {
            $errors += "[$tid] risk=high ma confirmDialog != true"
        }
        if ($undo.Count -eq 0 -and $irr -ne $true) {
            $errors += "[$tid] undoCommands vuoto ma irreversible != true"
        }
        if ($undo.Count -eq 0 -and $conf -ne $true) {
            $errors += "[$tid] undoCommands vuoto ma confirmDialog != true"
        }
        if (($hives | Where-Object { $_ -in $script:AdminHives }).Count -gt 0 -and $admin -ne $true) {
            $errors += "[$tid] hive di sistema (HKLM/HKCR/HKU/HKCC) ma requiresAdministrator != true"
        }
        if ($services.Count -gt 0 -and $admin -ne $true) {
            $errors += "[$tid] modifica servizi ma requiresAdministrator != true"
        }
        if ($services.Count -gt 0 -and $restart -eq 'none') {
            $errors += "[$tid] services non vuoto ma restartRequired == none"
        }
        if ($scope -eq 'user' -and $admin -eq $true) {
            # Informativo, non bloccante: alcuni tweak user usano icacls elevato.
        }

        $errors += Test-TweakRequiredFields -Tweak $t -TweakId $tid
        $errors += Test-TweakRegistryChanges -RegistryChanges $rc -TweakId $tid
    }
    return $errors
}

function Get-TweakValidation {
    <#
    .SYNOPSIS
        Esegue la validazione completa (struttura + invarianti) del catalogo.
    .OUTPUTS
        PSCustomObject con .Valid, .Errors, .TweakCount.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Catalog
    )
    $shape = Test-TweakCatalogShape -Catalog $Catalog
    if (-not $shape.Valid) {
        return New-TweakValidationResult -Errors $shape.Errors
    }
    $invariantErrors = Test-TweakInvariants -Tweaks $Catalog.tweaks
    $allErrors = @($shape.Errors) + @($invariantErrors)
    $result = New-TweakValidationResult -Errors $allErrors
    $result.TweakCount = $Catalog.tweaks.Count
    return $result
}

Export-ModuleMember -Function Test-TweakCatalogShape, Test-TweakRequiredFields, Test-TweakRegistryChanges, Test-TweakInvariants, Get-TweakValidation
