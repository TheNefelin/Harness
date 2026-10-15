<#
.SYNOPSIS
    Instala o actualiza el Harness (reglas + skills) en openCode: global o por proyecto.

.DESCRIPTION
    No hay set por defecto de skills: siempre indicas -Skills (o -Update para refrescar
    lo ya declarado). El destino se decide por -Scope, o se deduce:
      - Con -Project  -> scope Local  (vive en <Proyecto>\harness\)
      - Sin -Project  -> scope Global (~/.config/opencode\)
      - -Update       -> lee .harness.json y respeta el scope ya declarado

    Escribe una declaracion .harness.json ({scope, rules, skills, harnessVersion}) para que
    -Update sepa siempre donde actualizar. Nunca pisa skills ni reglas ajenas: las
    respalda en .harness-backup\.

.PARAMETER Scope
    Auto (deduce segun -Project / .harness.json), Global o Local.

.PARAMETER Project
    Ruta raiz del proyecto. Implica scope Local.

.PARAMETER Skills
    Skills a instalar, separadas por coma (ej. dotnet,postgres). Obligatorio salvo con
    -Update o -List.

.PARAMETER Update
    Refresca las skills y reglas declaradas en .harness.json, en su scope.

.PARAMETER List
    Muestra las skills disponibles en el catalogo y sale.

.PARAMETER Detect
    Detecta las tecnologias del proyecto (-Project) y compara con el catalogo: informa
    que skills existen y que tecnologias no tienen skill (candidatas a crear). Solo lectura.

.PARAMETER WhatIf
    Simula la operacion: muestra que se instalaria, refrescaria, respaldaria, omitiria
    o podaria, sin modificar nada.

.PARAMETER Doctor
    Diagnostica la instalacion en el scope (manifiesto .harness.json, rutas, marcadores,
    reglas y config de openCode) sin modificar nada.

.PARAMETER Source
    Origen del catalogo: ruta local a un clon del Harness o URL git (https/ssh). Permite
    actualizar un proyecto sin tener el repositorio Harness abierto a mano.

.PARAMETER Global
    Atajo de -Scope Global: instala en ~/.config/opencode\ en vez de en un proyecto.

.PARAMETER Force
    Reemplaza skills/reglas ajenas (haciendo respaldo) en vez de omitirlas.

.PARAMETER Context
    Copia ademas las plantillas de memoria (README.md, DEVELOPMENT.md, SKILL.md).

.EXAMPLE
    .\install.ps1 -List
    .\install.ps1 -Project "D:\Repo\App" -Detect
    .\install.ps1 -Project "D:\Repo\App" -Skills dotnet,postgres
    .\install.ps1 -Global -Skills docker,kubernetes
    .\install.ps1 -Project "D:\Repo\App" -Skills dotnet,postgres -WhatIf
    .\install.ps1 -Project "D:\Repo\App" -Update -Source "D:\Repo\Harness"
    .\install.ps1 -Project "D:\Repo\App" -Update -Source "https://github.com/TheNefelin/Harness.git"
    .\install.ps1 -Project "D:\Repo\App" -Update
    .\install.ps1 -Project "D:\Repo\App" -Doctor
    .\install.ps1 -Global -Doctor
#>
[CmdletBinding()]
param(
    [ValidateSet('Auto', 'Global', 'Local')]
    [string]$Scope = 'Auto',

    [string]$Project,

    [string[]]$Skills,

    [switch]$Update,

    [switch]$List,

    [switch]$Detect,

    [switch]$WhatIf,

    [switch]$Doctor,

    [string]$Source,

    [switch]$Global,

    [switch]$Force,

    [switch]$Context
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$MarkerName = '.harness-source'
$script:DetectEvidence = @{}

# Capa 1 (catalogo): clon local o URL git, para actualizar sin abrir el repo
$SourceRoot = $ScriptDir
if ($Source) {
    if ($Source -match '^(https?://|ssh://|git://|git@|file://)') {
        if (-not (Get-Command git -ErrorAction SilentlyContinue)) { throw 'Se requiere git para usar -Source <url>.' }
        $key = [System.BitConverter]::ToString([System.Security.Cryptography.SHA256]::Create().ComputeHash([System.Text.Encoding]::UTF8.GetBytes($Source))).Replace('-', '').Substring(0, 12)
        $cache = Join-Path $env:TEMP ("harness-src-$key")
        if (Test-Path -LiteralPath (Join-Path $cache '.git')) {
            Write-Host "Source: refrescando $cache" -ForegroundColor DarkGray
            git -C $cache fetch --depth 1 --quiet
            git -C $cache reset --hard --quiet FETCH_HEAD
        }
        else {
            Write-Host "Source: clonando $Source" -ForegroundColor DarkGray
            git clone --depth 1 --quiet $Source $cache
        }
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $cache)) { throw "No se pudo obtener el catalogo desde $Source" }
        $SourceRoot = $cache
    }
    else {
        $resolved = Resolve-Path -LiteralPath $Source -ErrorAction SilentlyContinue
        if (-not $resolved) { throw "La ruta de -Source no existe: $Source" }
        $SourceRoot = $resolved.Path
    }
    if (-not (Test-Path -LiteralPath (Join-Path $SourceRoot 'skills'))) { throw "-Source no parece un catalogo Harness (falta skills\): $SourceRoot" }
}

$CatalogDir = Join-Path $SourceRoot 'skills'

$Version = '0.0.0'
$VersionFile = Join-Path $SourceRoot 'VERSION'
if (Test-Path -LiteralPath $VersionFile) {
    $Version = (Get-Content -LiteralPath $VersionFile -Raw).Trim()
}

# schemaVersion de .harness.json que entiende este instalador.
$SchemaVersion = 1

function Get-Catalog {
    $result = @()
    foreach ($dir in Get-ChildItem -LiteralPath $CatalogDir -Directory) {
        $skillFile = Join-Path $dir.FullName 'SKILL.md'
        if (-not (Test-Path -LiteralPath $skillFile)) { continue }
        $desc = ''
        foreach ($line in (Get-Content -LiteralPath $skillFile -TotalCount 30 -Encoding UTF8)) {
            if ($line -match '^description:\s*(.+)$') {
                $desc = $Matches[1].Trim().Trim('"').Trim("'")
                break
            }
        }
        $result += [pscustomobject]@{ Name = $dir.Name; Description = $desc }
    }
    return @($result | Sort-Object Name)
}

function Get-TreeHash {
    param([string]$Path)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $lines = @()
        foreach ($f in (Get-ChildItem -LiteralPath $Path -Recurse -File -Force)) {
            if ($f.Name -eq $MarkerName) { continue }
            $rel = $f.FullName.Substring($Path.Length).TrimStart('\', '/').Replace('\', '/')
            $hex = [System.BitConverter]::ToString($sha.ComputeHash([System.IO.File]::ReadAllBytes($f.FullName))).Replace('-', '')
            $lines += ($rel + '|' + $hex)
        }
        $joined = (($lines | Sort-Object) -join "`n")
        return [System.BitConverter]::ToString($sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($joined))).Replace('-', '').ToLower()
    }
    finally { $sha.Dispose() }
}

function New-MarkerValue {
    param([string]$Hash)
    return ('{{ "version": "{0}", "hash": "{1}" }}' -f $Version, $Hash)
}

function Get-Marker {
    param([string]$Path)
    $markerFile = Join-Path $Path $MarkerName
    if (-not (Test-Path -LiteralPath $markerFile)) { return $null }
    $raw = (Get-Content -LiteralPath $markerFile -Raw).Trim()
    if ($raw.StartsWith('{')) {
        try { return ($raw | ConvertFrom-Json) } catch { return $null }
    }
    return [pscustomobject]@{ version = $raw; hash = $null }
}

function Get-SchemaStatus {
    param($Manifest)
    if ($null -eq $Manifest) { return 'warn' }
    if (-not ($Manifest.PSObject.Properties.Name -contains 'schemaVersion')) { return 'warn' }
    $v = 0
    if (-not [int]::TryParse([string]$Manifest.schemaVersion, [ref]$v)) { return 'err' }
    if ($v -gt $SchemaVersion) { return 'err' }
    return 'ok'
}
    param([System.Collections.Generic.HashSet[string]]$Set, [string]$Name, [string]$Why)
    [void]$Set.Add($Name)
    if ($script:DetectEvidence.ContainsKey($Name)) {
        if (-not ($script:DetectEvidence[$Name] -contains $Why)) { $script:DetectEvidence[$Name] = @($script:DetectEvidence[$Name]) + $Why }
    }
    else { $script:DetectEvidence[$Name] = @($Why) }
}

function Get-ProjectTech {
    param([string]$Root)

    $skills = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $script:DetectEvidence = @{}
    if (-not (Test-Path -LiteralPath $Root)) { return @() }

    $exclude = '[\\/](node_modules|\.git|dist|build|bin|obj|\.godot|venv|\.venv|\.idea|\.vs|packages|harness|\.opencode|\.claude|\.agents)[\\/]'
    $files = @(Get-ChildItem -LiteralPath $Root -Recurse -File -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -notmatch $exclude })

    $byName = @{}
    $exts = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($f in $files) {
        $byName[$f.Name.ToLower()] = $f.FullName
        if ($f.Extension) { [void]$exts.Add($f.Extension.ToLower()) }
    }
    $fullNames = @($files | ForEach-Object { $_.FullName })

    # .NET
    if ($exts.Contains('.csproj') -or $exts.Contains('.sln') -or $byName.ContainsKey('directory.packages.props')) { Add-Detected $skills 'dotnet' 'proyecto .NET (.csproj/.sln/Directory.Packages.props)' }
    # Godot
    if ($byName.ContainsKey('project.godot') -or $exts.Contains('.tscn') -or $exts.Contains('.gd')) { Add-Detected $skills 'godot' 'proyecto Godot (project.godot/.tscn/.gd)' }
    # Docker
    foreach ($n in @('dockerfile', 'compose.yaml', 'compose.yml', 'docker-compose.yaml', 'docker-compose.yml', '.dockerignore')) {
        if ($byName.ContainsKey($n)) { Add-Detected $skills 'docker' "contenedores ($n)"; break }
    }
    # Kubernetes
    if ($byName.ContainsKey('chart.yaml') -or $byName.ContainsKey('kustomization.yaml') -or $byName.ContainsKey('kustomization.yml') -or ($fullNames -match '[\\/](k8s|kubernetes|manifests|helm)[\\/]')) { Add-Detected $skills 'kubernetes' 'manifiestos de Kubernetes (Chart.yaml/kustomization/carpetas k8s|helm)' }
    # GitHub Actions
    if ($fullNames -match '[\\/]\.github[\\/]workflows[\\/]') { Add-Detected $skills 'github-actions' '.github/workflows' }
    # SQL por archivos
    if ($exts.Contains('.sql')) { Add-Detected $skills 'sql' 'archivos .sql' }

    # package.json (Node / frameworks / drivers)
    if ($byName.ContainsKey('package.json')) {
        $pkg = Get-Content -LiteralPath $byName['package.json'] -Raw -ErrorAction SilentlyContinue
        if ($pkg) {
            if ($pkg -match '@angular/core') { Add-Detected $skills 'angular' 'package.json: @angular/core' }
            if ($pkg -match '"astro"') { Add-Detected $skills 'astro' 'package.json: astro' }
            if ($pkg -match '"(react|react-dom|next)"') { Add-Detected $skills 'react' 'package.json: react/next' }
            if ($pkg -match '"vue"') { Add-Detected $skills 'vue' 'package.json: vue' }
            if ($pkg -match '"svelte"') { Add-Detected $skills 'svelte' 'package.json: svelte' }
            if ($pkg -match '"(pg|postgres|mysql|mysql2|mssql)"') { Add-Detected $skills 'sql' 'package.json: driver SQL (pg/mysql/mssql)' }
            if ($pkg -match '"(mongodb|redis|ioredis)"|@azure/cosmos|@aws-sdk/client-dynamodb') { Add-Detected $skills 'nosql' 'package.json: driver NoSQL (mongodb/redis/cosmos/dynamodb)' }
        }
    }

    # Python (requirements / pyproject / pipfile)
    foreach ($n in @('requirements.txt', 'pyproject.toml', 'pipfile')) {
        if ($byName.ContainsKey($n)) {
            $py = Get-Content -LiteralPath $byName[$n] -Raw -ErrorAction SilentlyContinue
            if ($py) {
                if ($py -match 'fastapi') { Add-Detected $skills 'fastapi' "${n}: fastapi" }
                if ($py -match 'django') { Add-Detected $skills 'django' "${n}: django" }
                if ($py -match 'flask') { Add-Detected $skills 'flask' "${n}: flask" }
                if ($py -match '(psycopg|sqlalchemy)') { Add-Detected $skills 'sql' "${n}: psycopg/sqlalchemy" }
                if ($py -match '(pymongo|\bredis\b)') { Add-Detected $skills 'nosql' "${n}: pymongo/redis" }
            }
        }
    }

    # .NET deps (SQL / NoSQL)
    foreach ($f in $files) {
        if ($f.Extension -eq '.csproj') {
            $cs = Get-Content -LiteralPath $f.FullName -Raw -ErrorAction SilentlyContinue
            if ($cs) {
                if ($cs -match '(Npgsql|Microsoft\.Data\.SqlClient|EntityFrameworkCore\.(SqlServer|Npgsql|PostgreSql))') { Add-Detected $skills 'sql' '.csproj: proveedor SQL' }
                if ($cs -match '(StackExchange\.Redis|MongoDB\.Driver|Azure\.Cosmos|AWSSDK\.DynamoDB)') { Add-Detected $skills 'nosql' '.csproj: driver NoSQL' }
            }
        }
    }

    # Terraform / nube por provider
    if ($exts.Contains('.tf')) {
        $sawProvider = $false
        foreach ($f in $files) {
            if ($f.Extension -eq '.tf') {
                $tf = Get-Content -LiteralPath $f.FullName -Raw -ErrorAction SilentlyContinue
                if ($tf) {
                    if ($tf -match 'provider\s+"aws"') { Add-Detected $skills 'aws' '.tf: provider aws'; $sawProvider = $true }
                    if ($tf -match 'provider\s+"azurerm"') { Add-Detected $skills 'azure' '.tf: provider azurerm'; $sawProvider = $true }
                    if ($tf -match 'provider\s+"oci"') { Add-Detected $skills 'oci' '.tf: provider oci'; $sawProvider = $true }
                }
            }
        }
        if (-not $sawProvider) { Add-Detected $skills 'terraform' 'archivos .tf sin provider cloud reconocido' }
    }

    return @($skills | Sort-Object)
}

function Write-ProjectTech {
    param(
        [string]$Root,
        [string[]]$Available,
        [string[]]$Desired,
        [switch]$ShowNotInstalled
    )

    $tech = @(Get-ProjectTech -Root $Root)
    if ($tech.Count -eq 0) {
        Write-Host ('Deteccion: no se reconocieron tecnologias en {0}' -f $Root) -ForegroundColor DarkGray
        return
    }

    $withSkill = @($tech | Where-Object { $_ -in $Available })
    $without = @($tech | Where-Object { $_ -notin $Available })
    $conTxt = if ($withSkill.Count -gt 0) { $withSkill -join ', ' } else { '(ninguna)' }

    Write-Host ('Deteccion de tecnologias: {0}' -f $Root) -ForegroundColor Cyan
    Write-Host ('  Detectadas:              {0}' -f ($tech -join ', '))
    Write-Host ('  Con skill en el catalogo: {0}' -f $conTxt) -ForegroundColor Green
    if ($without.Count -gt 0) {
        Write-Host ('  SIN skill (candidatas):   {0}' -f ($without -join ', ')) -ForegroundColor Yellow
    }
    if ($ShowNotInstalled -and $Desired) {
        $notInstalled = @($withSkill | Where-Object { $_ -notin $Desired })
        if ($notInstalled.Count -gt 0) {
            Write-Host ('  Con skill, no instalada:   {0}' -f ($notInstalled -join ', ')) -ForegroundColor Yellow
        }
    }

    foreach ($t in $tech) {
        if ($script:DetectEvidence.ContainsKey($t)) {
            Write-Verbose ('  evidencia {0}: {1}' -f $t, ($script:DetectEvidence[$t] -join '; '))
        }
    }
}

if ($List) {
    Write-Host 'Skills disponibles en el catalogo:' -ForegroundColor Cyan
    foreach ($s in Get-Catalog) {
        Write-Host ('  {0,-16} {1}' -f $s.Name, $s.Description)
    }
    Write-Host ''
    Write-Host 'Local :  .\install.ps1 -Project <ruta> -Skills <a,b,c>'
    Write-Host 'Global:  .\install.ps1 -Global -Skills <a,b>'
    Write-Host 'Update:  .\install.ps1 [-Project <ruta>|-Global] -Update'
    Write-Host 'Doctor:  .\install.ps1 [-Project <ruta>|-Global] -Doctor'
    exit 0
}

if ($Detect) {
    if (-not $Project) { throw 'La deteccion requiere -Project <ruta>.' }
    if (-not (Test-Path -LiteralPath $Project)) { throw "La ruta no existe: $Project" }
    $catalog = @(Get-Catalog | ForEach-Object { $_.Name })
    Write-Host 'Skills disponibles en el catalogo:' -ForegroundColor Cyan
    Write-Host ('  ' + ($catalog -join ', '))
    Write-Host ''
    Write-ProjectTech -Root $Project -Available $catalog
    if ($VerbosePreference -eq 'SilentlyContinue') { Write-Host '  (usa -Verbose para ver la evidencia de cada deteccion)' -ForegroundColor DarkGray }
    exit 0
}

# Atajo -Global (= -Scope Global)
if ($Global) { $Scope = 'Global' }

# Resolver scope
if ($Project) {
    $resolved = Resolve-Path -LiteralPath $Project -ErrorAction SilentlyContinue
    if (-not $resolved) { throw "La ruta del proyecto no existe: $Project" }
    $Project = $resolved.Path
}

$projectDecl = if ($Project) { Join-Path $Project '.harness.json' } else { $null }

if ($Scope -eq 'Auto') {
    if ($Project -and (Test-Path -LiteralPath $projectDecl)) {
        $d = Get-Content -LiteralPath $projectDecl -Raw | ConvertFrom-Json
        $Scope = [string]$d.scope
    }
    elseif ($Project) { $Scope = 'Local' }
    else { $Scope = 'Global' }
}

# Rutas destino segun scope
if ($Scope -eq 'Global') {
    if ($Project) { Write-Host 'AVISO  -Project se ignora con scope Global.' -ForegroundColor Yellow }
    $ConfigDir = Join-Path $HOME '.config/opencode'
    $ScopeRoot = $ConfigDir
    $SkillsDir = Join-Path $ConfigDir 'skills'
    $RulesFile = Join-Path $ConfigDir 'AGENTS.md'
    $DeclFile = Join-Path $ConfigDir '.harness.json'
    $ConfigFile = Join-Path $ConfigDir 'opencode.json'
    $RulesOurs = $false
    $Project = $null
}
else {
    if (-not $Project) { throw 'El scope Local requiere -Project.' }
    $HarnessDir = Join-Path $Project 'harness'
    $ScopeRoot = $HarnessDir
    $SkillsDir = Join-Path $HarnessDir 'skills'
    $RulesFile = Join-Path $HarnessDir 'AGENTS.md'
    $DeclFile = Join-Path $Project '.harness.json'
    $ConfigFile = Join-Path $Project 'opencode.json'
    $RulesOurs = $true
}

# Resolver skills deseadas
$declared = @()
$existingDeclObj = $null
if (Test-Path -LiteralPath $DeclFile) {
    $existingDeclObj = Get-Content -LiteralPath $DeclFile -Raw | ConvertFrom-Json
    if ($existingDeclObj.PSObject.Properties.Name -contains 'skills') { $declared = @($existingDeclObj.skills) }
}

if ($existingDeclObj -and -not $Doctor) {
    switch (Get-SchemaStatus $existingDeclObj) {
        'err'  { throw "El manifiesto .harness.json usa un schemaVersion incompatible o mas nuevo que este install.ps1 (soportado: $SchemaVersion). Actualiza el Harness con -Source antes de modificarlo." }
        'warn' { Write-Host 'AVISO  manifiesto sin schemaVersion; se asume 1.' -ForegroundColor Yellow }
    }
}

if ($Doctor) {
    $errCount = 0
    $warnCount = 0
    function Write-Check {
        param([string]$Level, [string]$Message)
        if ($Level -eq 'ERR') { Write-Host ('  [FAIL]  ' + $Message) -ForegroundColor Red; $script:errCount++ }
        elseif ($Level -eq 'WARN') { Write-Host ('  [WARN]  ' + $Message) -ForegroundColor Yellow; $script:warnCount++ }
        else { Write-Host ('  [ OK ]  ' + $Message) -ForegroundColor Green }
    }

    Write-Host ("Doctor - scope {0} - raiz: {1}" -f $Scope, $ScopeRoot) -ForegroundColor Cyan
    Write-Host ("  catalogo: {0} (Harness {1})" -f $CatalogDir, $Version) -ForegroundColor DarkGray

    $catalogNames = @(Get-Catalog | ForEach-Object { $_.Name })
    if ((Test-Path -LiteralPath $CatalogDir) -and $catalogNames.Count -gt 0) { Write-Check OK 'catalogo accesible' }
    else { Write-Check ERR "catalogo no accesible: $CatalogDir" }

    if (-not (Test-Path -LiteralPath $DeclFile)) {
        Write-Check WARN 'sin manifiesto (.harness.json): no instalado en este scope'
    }
    else {
        Write-Check OK "manifiesto presente: $DeclFile"
        switch (Get-SchemaStatus $existingDeclObj) {
            'ok'   { Write-Check OK ("schemaVersion {0} soportado" -f $existingDeclObj.schemaVersion) }
            'warn' { Write-Check WARN 'manifiesto sin schemaVersion (formato antiguo)' }
            'err'  { Write-Check ERR "schemaVersion incompatible o mas nuevo (soportado: $SchemaVersion)" }
        }
        try {
            $decl = Get-Content -LiteralPath $DeclFile -Raw | ConvertFrom-Json
            if ([string]$decl.scope -eq $Scope.ToLower()) { Write-Check OK "scope declarado: $($decl.scope)" }
            else { Write-Check WARN "scope declarado '$($decl.scope)' != esperado '$($Scope.ToLower())'" }

            if ($decl.PSObject.Properties.Name -contains 'skills') {
                $dsk = @($decl.skills)
                $unk = @($dsk | Where-Object { $_ -notin $catalogNames })
                if ($unk.Count -gt 0) { Write-Check WARN "skills declaradas fuera del catalogo: $($unk -join ', ')" }

                foreach ($s in $dsk) {
                    $sd = Join-Path $SkillsDir $s
                    if (-not (Test-Path -LiteralPath $sd)) { Write-Check ERR "skill '$s': no instalada"; continue }
                    if (-not (Test-Path -LiteralPath (Join-Path $sd $MarkerName))) { Write-Check WARN "skill '$s': sin marcador (ajena?)"; continue }
                    if ($s -notin $catalogNames) { continue }
                    $ih = Get-TreeHash -Path $sd
                    $sh = Get-TreeHash -Path (Join-Path $CatalogDir $s)
                    if ($ih -eq $sh) { Write-Check OK "skill '$s': al dia" }
                    else {
                        $m = Get-Marker -Path $sd
                        if ($m -and $m.hash -and $ih -ne $m.hash) { Write-Check WARN "skill '$s': editada localmente (divergente)" }
                        else { Write-Check WARN "skill '$s': desactualizada respecto al catalogo" }
                    }
                }

                $extra = @(Get-ChildItem -LiteralPath $SkillsDir -Directory -Force -ErrorAction SilentlyContinue |
                    Where-Object { $_.Name -ne '.harness-backup' -and (Test-Path -LiteralPath (Join-Path $_.FullName $MarkerName)) -and ($_.Name -notin $dsk) })
                if ($extra.Count -gt 0) { Write-Check WARN "instaladas pero no declaradas (se podaran con -Update): $((@($extra | ForEach-Object { $_.Name })) -join ', ')" }
            }
            else { Write-Check WARN "manifiesto sin 'skills'" }
        }
        catch { Write-Check ERR ".harness.json ilegible: $($_.Exception.Message)" }
    }

    if (Test-Path -LiteralPath $RulesFile) { Write-Check OK "reglas presentes: $RulesFile" }
    else { Write-Check WARN "reglas ausentes: $RulesFile" }

    if (Test-Path -LiteralPath $ConfigFile) {
        try {
            $cfg = Get-Content -LiteralPath $ConfigFile -Raw | ConvertFrom-Json
            if ($Scope -eq 'Local') {
                $paths = @(); if ($cfg.skills -and $cfg.skills.paths) { $paths = @($cfg.skills.paths) }
                if ($paths -contains 'harness/skills') { Write-Check OK 'opencode.json: skills.paths -> harness/skills' }
                else { Write-Check ERR 'opencode.json: falta skills.paths = [harness/skills]' }
                $instr = @(); if ($cfg.instructions) { $instr = @($cfg.instructions) }
                if ($instr -contains 'harness/AGENTS.md') { Write-Check OK 'opencode.json: instructions -> harness/AGENTS.md' }
                else { Write-Check WARN 'opencode.json: falta instructions = [harness/AGENTS.md]' }
            }
            else {
                if ($cfg.permission) { Write-Check OK 'opencode.json global: bloque permission presente' }
                else { Write-Check WARN 'opencode.json global: sin bloque permission' }
            }
        }
        catch { Write-Check ERR "opencode.json ilegible: $($_.Exception.Message)" }
    }
    elseif ($Scope -eq 'Local') { Write-Check ERR "opencode.json ausente: $ConfigFile" }
    else { Write-Check WARN "opencode.json ausente: $ConfigFile" }

    $bk = Join-Path $ScopeRoot '.harness-backup'
    if (Test-Path -LiteralPath $bk) { Write-Check OK ("respaldos: {0} en .harness-backup" -f @(Get-ChildItem -LiteralPath $bk -Force).Count) }

    Write-Host ''
    if ($errCount -gt 0) {
        Write-Host ("Doctor: {0} error(es), {1} aviso(s)." -f $errCount, $warnCount) -ForegroundColor Red
        exit 1
    }
    Write-Host ("Doctor: OK ({0} aviso(s))." -f $warnCount) -ForegroundColor Green
    exit 0
}

if ($Update) {
    if ($Skills) { $desired = $Skills }
    elseif ($declared.Count -gt 0) { $desired = $declared }
    else { throw 'No hay .harness.json que actualizar en este scope. Usa -Skills la primera vez.' }
}
else {
    if (-not $Skills) { throw 'Debes indicar -Skills (ej. -Skills dotnet,postgres). No hay set por defecto.' }
    $desired = $Skills
}

$desired = @($desired | ForEach-Object { "$_".Split(',') } | ForEach-Object { $_.Trim() } | Where-Object { $_ } | Select-Object -Unique)

$available = @(Get-Catalog | ForEach-Object { $_.Name })
$unknown = @($desired | Where-Object { $_ -notin $available })
if ($unknown.Count -gt 0) {
    throw "Skills desconocidas: $($unknown -join ', '). Usa -List para ver el catalogo."
}

if ($Scope -eq 'Local') {
    Write-ProjectTech -Root $Project -Available $available -Desired $desired -ShowNotInstalled
    Write-Host ''
}

# Instalar skills
if (-not $WhatIf) {
    New-Item -ItemType Directory -Path $SkillsDir -Force | Out-Null
    Get-ChildItem -LiteralPath $SkillsDir -Directory -Force -Filter '.staging-*' -ErrorAction SilentlyContinue |
        Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
}
$BackupDir = Join-Path $ScopeRoot '.harness-backup'

function Backup-Path {
    param([string]$Path, [string]$Name)
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $dest = Join-Path $BackupDir ("{0}-{1}" -f $Name, $stamp)
    if ($WhatIf) {
        Write-Host "WOULD  respaldar $Name -> .harness-backup\$([System.IO.Path]::GetFileName($dest))" -ForegroundColor DarkCyan
        return $null
    }
    New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
    Move-Item -LiteralPath $Path -Destination $dest
    Write-Host "BACKUP $Name -> $dest" -ForegroundColor Yellow
    return $dest
}

function Deploy-Skill {
    param(
        [string]$Name,
        [string]$Src,
        [string]$Dst,
        [string]$SrcHash,
        [switch]$ReplaceExisting
    )
    # 1) Preparar en temporal (no se toca el destino hasta validar)
    $tmp = Join-Path $SkillsDir ('.staging-{0}-{1}' -f $Name, [System.Guid]::NewGuid().ToString('N').Substring(0, 8))
    Copy-Item -LiteralPath $Src -Destination $tmp -Recurse -Force
    if (-not (Test-Path -LiteralPath (Join-Path $tmp 'SKILL.md'))) {
        Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
        throw "Copia invalida de '$Name': el origen no tiene SKILL.md."
    }

    # 2) Apartar el destino (respaldo si reemplaza) y colocar el nuevo
    $backup = $null
    try {
        if (Test-Path -LiteralPath $Dst) {
            if ($ReplaceExisting) { $backup = Backup-Path -Path $Dst -Name $Name }
            else { Remove-Item -LiteralPath $Dst -Recurse -Force }
        }
        Move-Item -LiteralPath $tmp -Destination $Dst
        Set-Content -LiteralPath (Join-Path $Dst $MarkerName) -Value (New-MarkerValue -Hash $SrcHash)
    }
    catch {
        # 3) Recuperacion: limpiar staging y restaurar el respaldo
        Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
        if (Test-Path -LiteralPath $Dst) { Remove-Item -LiteralPath $Dst -Recurse -Force -ErrorAction SilentlyContinue }
        if ($backup -and (Test-Path -LiteralPath $backup)) {
            Move-Item -LiteralPath $backup -Destination $Dst
            Write-Host "ROLLBACK $Name restaurado desde respaldo" -ForegroundColor Yellow
        }
        throw
    }
}

foreach ($name in $desired) {
    $src = Join-Path $CatalogDir $name
    $dst = Join-Path $SkillsDir $name
    $srcHash = Get-TreeHash -Path $src
    $replace = $false
    $conflict = $false

    if (Test-Path -LiteralPath $dst) {
        $marker = Get-Marker -Path $dst
        if (-not $marker) {
            if ($Force) { $replace = $true }
            else {
                Write-Host "SKIP   $name (ajena; usa -Force para reemplazar)" -ForegroundColor Yellow
                continue
            }
        }
        else {
            $dstHash = Get-TreeHash -Path $dst
            if ($dstHash -eq $srcHash) {
                if ($WhatIf) { Write-Host "WOULD  sin cambios  $name" -ForegroundColor DarkCyan }
                else {
                    Set-Content -LiteralPath (Join-Path $dst $MarkerName) -Value (New-MarkerValue -Hash $srcHash)
                    Write-Host "OK     skill $name (sin cambios)" -ForegroundColor DarkGray
                }
                continue
            }
            $replace = $true
            if ($marker.hash) { $conflict = ($dstHash -ne $marker.hash) }
            else { $conflict = $true }
        }
    }

    if ($WhatIf) {
        if ($conflict) { Write-Host "WOULD  actualizar $name (DIVERGENCIA: respaldo)" -ForegroundColor DarkCyan }
        elseif ($replace) { Write-Host "WOULD  actualizar skill $name" -ForegroundColor DarkCyan }
        else { Write-Host "WOULD  instalar skill $name" -ForegroundColor DarkCyan }
        continue
    }

    Deploy-Skill -Name $name -Src $src -Dst $dst -SrcHash $srcHash -ReplaceExisting:$replace
    if ($conflict) { Write-Host "CONFLICT $name editada localmente; se respaldo antes de actualizar" -ForegroundColor Yellow }
    Write-Host "OK     skill $name" -ForegroundColor Green
}

# Podar skills nuestras que ya no se desean
if (Test-Path -LiteralPath $SkillsDir) {
    foreach ($dir in (Get-ChildItem -LiteralPath $SkillsDir -Directory -Force)) {
        if ($dir.Name -eq '.harness-backup') { continue }
        $isOurs = Test-Path -LiteralPath (Join-Path $dir.FullName $MarkerName)
        if ($isOurs -and ($dir.Name -notin $desired)) {
            if ($WhatIf) {
                Write-Host "WOULD  podar $($dir.Name)" -ForegroundColor DarkCyan
            }
            else {
                Remove-Item -LiteralPath $dir.FullName -Recurse -Force
                Write-Host "PRUNE  $($dir.Name)" -ForegroundColor DarkGray
            }
        }
    }
}

# Reglas (AGENTS.md)
$rulesManaged = $false
if ($Scope -eq 'Local') { $rulesManaged = $true }
elseif ($existingDeclObj -and ($existingDeclObj.PSObject.Properties.Name -contains 'rules')) { $rulesManaged = [bool]$existingDeclObj.rules }

$srcRules = Join-Path $SourceRoot 'AGENTS.md'
if (Test-Path -LiteralPath $RulesFile) {
    if ($RulesOurs -or $rulesManaged -or $Force) {
        $same = (Get-FileHash -LiteralPath $RulesFile).Hash -eq (Get-FileHash -LiteralPath $srcRules).Hash
        if (-not $same) { Backup-Path -Path $RulesFile -Name 'AGENTS.md' }
        if ($WhatIf) { Write-Host "WOULD  reglas -> $RulesFile" -ForegroundColor DarkCyan }
        else {
            Copy-Item -LiteralPath $srcRules -Destination $RulesFile -Force
            Write-Host "OK     reglas -> $RulesFile" -ForegroundColor Green
        }
        $rulesManaged = $true
    }
    else {
        Write-Host "SKIP   $RulesFile ya existe (ajenas; usa -Force para reemplazar)" -ForegroundColor Yellow
    }
}
else {
    if ($WhatIf) { Write-Host "WOULD  reglas -> $RulesFile" -ForegroundColor DarkCyan }
    else {
        New-Item -ItemType Directory -Path (Split-Path -Parent $RulesFile) -Force | Out-Null
        Copy-Item -LiteralPath $srcRules -Destination $RulesFile -Force
        Write-Host "OK     reglas -> $RulesFile" -ForegroundColor Green
    }
    $rulesManaged = $true
}

# opencode.json
if ($Scope -eq 'Local') {
    if (Test-Path -LiteralPath $ConfigFile) {
        Write-Host 'SKIP   opencode.json ya existe (verifica instructions/skills.paths)' -ForegroundColor Yellow
    }
    elseif ($WhatIf) {
        Write-Host 'WOULD  opencode.json' -ForegroundColor DarkCyan
    }
    else {
        Copy-Item -LiteralPath (Join-Path $SourceRoot 'templates\opencode.json') -Destination $ConfigFile -Force
        Write-Host 'OK     opencode.json' -ForegroundColor Green
    }

    $gi = Join-Path $Project '.gitignore'
    $existing = ''
    if (Test-Path -LiteralPath $gi) { $existing = Get-Content -LiteralPath $gi -Raw }
    $entries = @('harness/skills/', 'harness/.harness-backup/')
    $toAdd = @($entries | Where-Object { ('' + $existing) -notmatch [regex]::Escape($_) })
    if ($toAdd.Count -gt 0) {
        if ($WhatIf) { Write-Host "WOULD  .gitignore (ignora $($toAdd -join ', '))" -ForegroundColor DarkCyan }
        else {
            $block = "`n# Harness (gestionado; refrescar con install.ps1 -Update)`n" + (($toAdd -join "`n") + "`n")
            Add-Content -LiteralPath $gi -Value $block
            Write-Host "OK     .gitignore (ignora $($toAdd -join ', '))" -ForegroundColor Green
        }
    }
    else {
        Write-Host 'SKIP   .gitignore ya ignora el harness' -ForegroundColor Yellow
    }
}
else {
    if (Test-Path -LiteralPath $ConfigFile) {
        Write-Host 'SKIP   ~/.config/opencode/opencode.json ya existe (fusiona el bloque "permission" a mano)' -ForegroundColor Yellow
    }
    else {
        if ($WhatIf) { Write-Host 'WOULD  opencode.json global (permisos)' -ForegroundColor DarkCyan }
        else {
            Copy-Item -LiteralPath (Join-Path $SourceRoot 'templates\opencode.global.json') -Destination $ConfigFile -Force
            Write-Host 'OK     opencode.json global (permisos)' -ForegroundColor Green
        }
    }
}

# Memoria opcional
if ($Context -and $Scope -eq 'Local') {
    foreach ($file in @('README.md', 'DEVELOPMENT.md', 'SKILL.md')) {
        $target = Join-Path $Project $file
        if (Test-Path -LiteralPath $target) {
            Write-Host "SKIP   $file ya existe" -ForegroundColor Yellow
        }
        else {
            if ($WhatIf) { Write-Host "WOULD  $file" -ForegroundColor DarkCyan }
            else {
                Copy-Item -LiteralPath (Join-Path $SourceRoot "templates\$file") -Destination $target -Force
                Write-Host "OK     $file" -ForegroundColor Green
            }
        }
    }
}

# Declaracion
$skillsJson = ($desired | ForEach-Object { '    "{0}"' -f $_ }) -join ",`n"
$json = @"
{
  "schemaVersion": 1,
  "scope": "$($Scope.ToLower())",
  "rules": $($rulesManaged.ToString().ToLower()),
  "skills": [
$skillsJson
  ],
  "harnessVersion": "$Version"
}
"@
if ($WhatIf) {
    Write-Host "WOULD  declaracion -> $DeclFile" -ForegroundColor DarkCyan
}
else {
    [System.IO.File]::WriteAllText($DeclFile, $json, (New-Object System.Text.UTF8Encoding($false)))
    Write-Host "OK     declaracion -> $DeclFile" -ForegroundColor Green
}

Write-Host ''
if ($WhatIf) {
    Write-Host 'WHATIF  Simulacion: no se modifico nada.' -ForegroundColor Cyan
    exit 0
}
Write-Host ("Harness " + $Scope.ToLower() + " listo. " + $desired.Count + " skill(s): " + ($desired -join ', '))
Write-Host 'Reinicia openCode para que cargue reglas y skills.'
