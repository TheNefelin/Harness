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

.PARAMETER Force
    Reemplaza skills/reglas ajenas (haciendo respaldo) en vez de omitirlas.

.PARAMETER Context
    Copia ademas las plantillas de memoria (README.md, DEVELOPMENT.md, SKILL.md).

.EXAMPLE
    .\install.ps1 -List
    .\install.ps1 -Project "D:\Repo\App" -Detect
    .\install.ps1 -Project "D:\Repo\App" -Skills dotnet,postgres
    .\install.ps1 -Global -Skills docker,kubernetes
    .\install.ps1 -Project "D:\Repo\App" -Update
#>
param(
    [ValidateSet('Auto', 'Global', 'Local')]
    [string]$Scope = 'Auto',

    [string]$Project,

    [string[]]$Skills,

    [switch]$Update,

    [switch]$List,

    [switch]$Detect,

    [switch]$Force,

    [switch]$Context
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$CatalogDir = Join-Path $ScriptDir 'skills'
$MarkerName = '.harness-source'

$Version = '0.0.0'
$VersionFile = Join-Path $ScriptDir 'VERSION'
if (Test-Path -LiteralPath $VersionFile) {
    $Version = (Get-Content -LiteralPath $VersionFile -Raw).Trim()
}

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

function Get-ProjectTech {
    param([string]$Root)

    $skills = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
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
    if ($exts.Contains('.csproj') -or $exts.Contains('.sln') -or $byName.ContainsKey('directory.packages.props')) { [void]$skills.Add('dotnet') }
    # Godot
    if ($byName.ContainsKey('project.godot') -or $exts.Contains('.tscn') -or $exts.Contains('.gd')) { [void]$skills.Add('godot') }
    # Docker
    foreach ($n in @('dockerfile', 'compose.yaml', 'compose.yml', 'docker-compose.yaml', 'docker-compose.yml', '.dockerignore')) {
        if ($byName.ContainsKey($n)) { [void]$skills.Add('docker'); break }
    }
    # Kubernetes
    if ($byName.ContainsKey('chart.yaml') -or $byName.ContainsKey('kustomization.yaml') -or $byName.ContainsKey('kustomization.yml') -or ($fullNames -match '[\\/](k8s|kubernetes|manifests|helm)[\\/]')) { [void]$skills.Add('kubernetes') }
    # GitHub Actions
    if ($fullNames -match '[\\/]\.github[\\/]workflows[\\/]') { [void]$skills.Add('github-actions') }
    # SQL por archivos
    if ($exts.Contains('.sql')) { [void]$skills.Add('sql') }

    # package.json (Node / frameworks / drivers)
    if ($byName.ContainsKey('package.json')) {
        $pkg = Get-Content -LiteralPath $byName['package.json'] -Raw -ErrorAction SilentlyContinue
        if ($pkg) {
            if ($pkg -match '@angular/core') { [void]$skills.Add('angular') }
            if ($pkg -match '"astro"') { [void]$skills.Add('astro') }
            if ($pkg -match '"(react|react-dom|next)"') { [void]$skills.Add('react') }
            if ($pkg -match '"vue"') { [void]$skills.Add('vue') }
            if ($pkg -match '"svelte"') { [void]$skills.Add('svelte') }
            if ($pkg -match '"(pg|postgres|mysql|mysql2|mssql)"') { [void]$skills.Add('sql') }
            if ($pkg -match '"(mongodb|redis|ioredis)"|@azure/cosmos|@aws-sdk/client-dynamodb') { [void]$skills.Add('nosql') }
        }
    }

    # Python (requirements / pyproject / pipfile)
    foreach ($n in @('requirements.txt', 'pyproject.toml', 'pipfile')) {
        if ($byName.ContainsKey($n)) {
            $py = Get-Content -LiteralPath $byName[$n] -Raw -ErrorAction SilentlyContinue
            if ($py) {
                if ($py -match 'fastapi') { [void]$skills.Add('fastapi') }
                if ($py -match 'django') { [void]$skills.Add('django') }
                if ($py -match 'flask') { [void]$skills.Add('flask') }
                if ($py -match '(psycopg|sqlalchemy)') { [void]$skills.Add('sql') }
                if ($py -match '(pymongo|\bredis\b)') { [void]$skills.Add('nosql') }
            }
        }
    }

    # .NET deps (SQL / NoSQL)
    foreach ($f in $files) {
        if ($f.Extension -eq '.csproj') {
            $cs = Get-Content -LiteralPath $f.FullName -Raw -ErrorAction SilentlyContinue
            if ($cs) {
                if ($cs -match '(Npgsql|Microsoft\.Data\.SqlClient|EntityFrameworkCore\.(SqlServer|Npgsql|PostgreSql))') { [void]$skills.Add('sql') }
                if ($cs -match '(StackExchange\.Redis|MongoDB\.Driver|Azure\.Cosmos|AWSSDK\.DynamoDB)') { [void]$skills.Add('nosql') }
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
                    if ($tf -match 'provider\s+"aws"') { [void]$skills.Add('aws'); $sawProvider = $true }
                    if ($tf -match 'provider\s+"azurerm"') { [void]$skills.Add('azure'); $sawProvider = $true }
                    if ($tf -match 'provider\s+"oci"') { [void]$skills.Add('oci'); $sawProvider = $true }
                }
            }
        }
        if (-not $sawProvider) { [void]$skills.Add('terraform') }
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
    exit 0
}

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
New-Item -ItemType Directory -Path $SkillsDir -Force | Out-Null
$BackupDir = Join-Path $ScopeRoot '.harness-backup'

function Backup-Path {
    param([string]$Path, [string]$Name)
    New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $dest = Join-Path $BackupDir ("{0}-{1}" -f $Name, $stamp)
    Move-Item -LiteralPath $Path -Destination $dest
    Write-Host "BACKUP $Name -> $dest" -ForegroundColor Yellow
}

foreach ($name in $desired) {
    $src = Join-Path $CatalogDir $name
    $dst = Join-Path $SkillsDir $name

    if (Test-Path -LiteralPath $dst) {
        $ours = Test-Path -LiteralPath (Join-Path $dst $MarkerName)
        if (-not $ours) {
            if ($Force) { Backup-Path -Path $dst -Name $name }
            else {
                Write-Host "SKIP   $name (ajena; usa -Force para reemplazar)" -ForegroundColor Yellow
                continue
            }
        }
        else {
            Remove-Item -LiteralPath $dst -Recurse -Force
        }
    }

    Copy-Item -LiteralPath $src -Destination $dst -Recurse -Force
    Set-Content -LiteralPath (Join-Path $dst $MarkerName) -Value $Version
    Write-Host "OK     skill $name" -ForegroundColor Green
}

# Podar skills nuestras que ya no se desean
foreach ($dir in (Get-ChildItem -LiteralPath $SkillsDir -Directory -Force)) {
    if ($dir.Name -eq '.harness-backup') { continue }
    $isOurs = Test-Path -LiteralPath (Join-Path $dir.FullName $MarkerName)
    if ($isOurs -and ($dir.Name -notin $desired)) {
        Remove-Item -LiteralPath $dir.FullName -Recurse -Force
        Write-Host "PRUNE  $($dir.Name)" -ForegroundColor DarkGray
    }
}

# Reglas (AGENTS.md)
$rulesManaged = $false
if ($Scope -eq 'Local') { $rulesManaged = $true }
elseif ($existingDeclObj -and ($existingDeclObj.PSObject.Properties.Name -contains 'rules')) { $rulesManaged = [bool]$existingDeclObj.rules }

$srcRules = Join-Path $ScriptDir 'AGENTS.md'
if (Test-Path -LiteralPath $RulesFile) {
    if ($RulesOurs -or $rulesManaged -or $Force) {
        $same = (Get-FileHash -LiteralPath $RulesFile).Hash -eq (Get-FileHash -LiteralPath $srcRules).Hash
        if (-not $same) { Backup-Path -Path $RulesFile -Name 'AGENTS.md' }
        Copy-Item -LiteralPath $srcRules -Destination $RulesFile -Force
        $rulesManaged = $true
        Write-Host "OK     reglas -> $RulesFile" -ForegroundColor Green
    }
    else {
        Write-Host "SKIP   $RulesFile ya existe (ajenas; usa -Force para reemplazar)" -ForegroundColor Yellow
    }
}
else {
    New-Item -ItemType Directory -Path (Split-Path -Parent $RulesFile) -Force | Out-Null
    Copy-Item -LiteralPath $srcRules -Destination $RulesFile -Force
    $rulesManaged = $true
    Write-Host "OK     reglas -> $RulesFile" -ForegroundColor Green
}

# opencode.json
if ($Scope -eq 'Local') {
    if (Test-Path -LiteralPath $ConfigFile) {
        Write-Host 'SKIP   opencode.json ya existe (verifica instructions/skills.paths)' -ForegroundColor Yellow
    }
    else {
        Copy-Item -LiteralPath (Join-Path $ScriptDir 'templates\opencode.json') -Destination $ConfigFile -Force
        Write-Host 'OK     opencode.json' -ForegroundColor Green
    }

    $gi = Join-Path $Project '.gitignore'
    $existing = ''
    if (Test-Path -LiteralPath $gi) { $existing = Get-Content -LiteralPath $gi -Raw }
    $entries = @('harness/skills/', 'harness/.harness-backup/')
    $toAdd = @($entries | Where-Object { ('' + $existing) -notmatch [regex]::Escape($_) })
    if ($toAdd.Count -gt 0) {
        $block = "`n# Harness (gestionado; refrescar con install.ps1 -Update)`n" + (($toAdd -join "`n") + "`n")
        Add-Content -LiteralPath $gi -Value $block
        Write-Host "OK     .gitignore (ignora $($toAdd -join ', '))" -ForegroundColor Green
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
        Copy-Item -LiteralPath (Join-Path $ScriptDir 'templates\opencode.global.json') -Destination $ConfigFile -Force
        Write-Host 'OK     opencode.json global (permisos)' -ForegroundColor Green
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
            Copy-Item -LiteralPath (Join-Path $ScriptDir "templates\$file") -Destination $target -Force
            Write-Host "OK     $file" -ForegroundColor Green
        }
    }
}

# Declaracion
$skillsJson = ($desired | ForEach-Object { '    "{0}"' -f $_ }) -join ",`n"
$json = @"
{
  "scope": "$($Scope.ToLower())",
  "rules": $($rulesManaged.ToString().ToLower()),
  "skills": [
$skillsJson
  ],
  "harnessVersion": "$Version"
}
"@
Set-Content -LiteralPath $DeclFile -Value $json -Encoding UTF8
Write-Host "OK     declaracion -> $DeclFile" -ForegroundColor Green

Write-Host ''
Write-Host ("Harness " + $Scope.ToLower() + " listo. " + $desired.Count + " skill(s): " + ($desired -join ', '))
Write-Host 'Reinicia openCode para que cargue reglas y skills.'
