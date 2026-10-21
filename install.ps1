<#
.SYNOPSIS
    Instala o actualiza el Harness (reglas + skills) en openCode: global o por proyecto.

.DESCRIPTION
    No hay set por defecto de skills: siempre indicas -Skills (o -Update para refrescar
    lo ya declarado). El destino se decide por -Scope, o se deduce:
      - Con -Project  -> scope Local  (vive en <Proyecto>\harness\)
      - Sin -Project  -> scope Global (~/.config/opencode\)
      - -Update       -> lee .harness.json y respeta el scope ya declarado

    Escribe una declaracion .harness.json ({schemaVersion, scope, rules, skills, harnessVersion,
    created}) para que -Update sepa siempre donde actualizar. Nunca pisa skills ni reglas ajenas:
    las respalda en .harness-backup\.

.PARAMETER Scope
    Auto (deduce segun -Project / .harness.json), Global o Local.

.PARAMETER Project
    Ruta raiz del proyecto. Implica scope Local.

.PARAMETER Skills
    Skills a instalar, separadas por coma (ej. dotnet,postgres). Obligatorio salvo con
    -Update, -Uninstall o -List.

.PARAMETER Update
    Refresca las skills y reglas declaradas en .harness.json, en su scope.

.PARAMETER Uninstall
    Desinstala el Harness del scope: borra SOLO lo gestionado (harness/ con reglas y skills,
    .harness.json, .harness/session.md y el bloque del .gitignore). opencode.json se borra
    unicamente si lo creo el Harness (lo registra el manifiesto). Nunca toca tu codigo, tu
    documentacion (.md) ni .harness-backup/ (tus respaldos). Local: actua sobre -Project.

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
    reglas, config de openCode y version del cliente V1/V2) sin modificar nada.

.PARAMETER Source
    Origen del catalogo: ruta local a un clon del Harness o URL git (https/ssh). Permite
    actualizar un proyecto sin tener el repositorio Harness abierto a mano.

.PARAMETER Global
    Atajo de -Scope Global: instala en ~/.config/opencode\ en vez de en un proyecto.

.PARAMETER Force
    Reemplaza skills/reglas ajenas (haciendo respaldo) en vez de omitirlas.

.PARAMETER SkillsOnly
    Instala las skills y omite las reglas (AGENTS.md) en este scope. Util cuando las reglas
    ya viven en el otro scope (p. ej. global), para no cargar dos copias identicas.

.PARAMETER IncludeRules
    Fuerza las reglas (AGENTS.md) en este scope, revirtiendo un rules:false previo (de un
    -SkillsOnly anterior). En Local asegura ademas instructions en opencode.json.
    Incompatible con -SkillsOnly.

.PARAMETER Context
    Copia ademas las plantillas de memoria (README.md, DEVELOPMENT.md, SKILL.md) y el
    checkpoint de sesion (.harness/session.md). Si un archivo ya existe, se respeta; si
    existe pero esta VACIO (0 bytes o solo espacios), se siembra la plantilla (no se pierde
    contenido, porque no lo habia).

.EXAMPLE
    .\install.ps1 -List
    .\install.ps1 -Project "D:\ruta\al\proyecto" -Detect
    .\install.ps1 -Project "D:\ruta\al\proyecto" -Skills dotnet,postgres
    .\install.ps1 -Global -Skills docker,kubernetes
    .\install.ps1 -Project "D:\ruta\al\proyecto" -Skills dotnet,postgres -SkillsOnly
    .\install.ps1 -Project "D:\ruta\al\proyecto" -Update -IncludeRules
    .\install.ps1 -Project "D:\ruta\al\proyecto" -Skills dotnet,postgres -WhatIf
    .\install.ps1 -Project "D:\ruta\al\proyecto" -Update -Source "D:\ruta\al\Harness"
    .\install.ps1 -Project "D:\ruta\al\proyecto" -Update -Source "https://github.com/TheNefelin/Harness.git"
    .\install.ps1 -Project "D:\ruta\al\proyecto" -Update
    .\install.ps1 -Project "D:\ruta\al\proyecto" -Doctor
    .\install.ps1 -Global -Doctor
    .\install.ps1 -Project "D:\ruta\al\proyecto" -Uninstall

.NOTES
    Diagnostico: -Detect y -Doctor aceptan -Verbose para ver la evidencia de cada deteccion.
    Pruebas de integracion del catalogo (install.ps1 + check.ps1): .\tools\test.ps1
#>
[CmdletBinding()]
param(
    [ValidateSet('Auto', 'Global', 'Local')]
    [string]$Scope = 'Auto',

    [string]$Project,

    [string[]]$Skills,

    [switch]$Update,

    [switch]$Uninstall,

    [switch]$List,

    [switch]$Detect,

    [switch]$WhatIf,

    [switch]$Doctor,

    [string]$Source,

    [switch]$Global,

    [switch]$Force,

    [switch]$SkillsOnly,

    [switch]$IncludeRules,

    [switch]$Context
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$MarkerName = '.harness-source'
$script:DetectEvidence = @{}

if ($SkillsOnly -and $IncludeRules) {
    Write-Host 'ERROR  -SkillsOnly y -IncludeRules son incompatibles.' -ForegroundColor Red
    exit 1
}

# Capa 1 (catalogo): clon local o URL git, para actualizar sin abrir el repo
$SourceRoot = $ScriptDir
if ($Source) {
    if ($Source -match '^(https?://|ssh://|git://|git@|file://)') {
        if (-not (Get-Command git -ErrorAction SilentlyContinue)) { throw 'Se requiere git para usar -Source <url>.' }
        $key = [System.BitConverter]::ToString([System.Security.Cryptography.SHA256]::Create().ComputeHash([System.Text.Encoding]::UTF8.GetBytes($Source))).Replace('-', '').Substring(0, 12)
        $cache = Join-Path ([System.IO.Path]::GetTempPath()) ("harness-src-$key")
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
    # Un catalogo Harness siempre trae skills/, AGENTS.md y templates/. Validarlos aqui
    # (antes de desplegar nada) evita abortar a mitad y dejar el scope sin manifiesto.
    $missing = @()
    foreach ($piece in @('skills', 'AGENTS.md', 'templates')) {
        if (-not (Test-Path -LiteralPath (Join-Path $SourceRoot $piece))) { $missing += $piece }
    }
    if ($missing.Count -gt 0) { throw "-Source no parece un catalogo Harness (falta: $($missing -join ', ')): $SourceRoot" }
    foreach ($tpl in @('opencode.json', 'opencode.global.json', 'opencode.skills-only.json')) {
        if (-not (Test-Path -LiteralPath (Join-Path $SourceRoot (Join-Path 'templates' $tpl)))) { throw "-Source no parece un catalogo Harness (falta templates/$tpl): $SourceRoot" }
    }
}

$CatalogDir = Join-Path $SourceRoot 'skills'
$TemplatesDir = Join-Path $SourceRoot 'templates'

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
        $inFrontmatter = $false
        foreach ($line in (Get-Content -LiteralPath $skillFile -Encoding UTF8)) {
            if (-not $inFrontmatter) { if ($line.Trim() -eq '---') { $inFrontmatter = $true }; continue }
            if ($line.Trim() -eq '---') { break }
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
    # Canonicalizar la raiz: una ruta corta 8.3 (p. ej. RUNNER~1) hace que los hijos
    # devuelvan FullName largo, y Substring($Path.Length) recortaria mal la ruta relativa.
    $root = (Get-Item -LiteralPath $Path -Force).FullName
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $lines = @()
        foreach ($f in (Get-ChildItem -LiteralPath $Path -Recurse -File -Force)) {
            if ($f.Name -eq $MarkerName) { continue }
            $rel = $f.FullName.Substring($root.Length).TrimStart('\', '/').Replace('\', '/')
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

function Test-EmptiedFile {
    # True si el archivo existe pero no aporta contenido: 0 bytes o solo espacios/saltos.
    # Sirve para sembrar la plantilla sin pisar documentacion real.
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
    return ([string]::IsNullOrWhiteSpace((Get-Content -LiteralPath $Path -Raw)))
}

function Get-OpenCodeClient {
    # Version del cliente openCode en PATH: [pscustomobject]@{ Found; Version; Major } o Found=$false.
    # V1 rechaza el bloque V2 de opencode.json (ConfigInvalidError); V2 lo exige. Solo lectura.
    $cmd = Get-Command 'opencode' -ErrorAction SilentlyContinue
    if (-not $cmd) { return [pscustomobject]@{ Found = $false; Version = $null; Major = 0 } }
    $raw = ''
    try { $raw = (& $cmd.Source --version 2>$null | Out-String).Trim() }
    catch { return [pscustomobject]@{ Found = $true; Version = $null; Major = 0 } }
    $ver = $null
    $major = 0
    if ($raw -match '(\d+)\.(\d+)(?:\.(\d+))?') {
        $major = [int]$Matches[1]
        $patch = if ($Matches[3]) { $Matches[3] } else { '0' }
        $ver = ('{0}.{1}.{2}' -f $Matches[1], $Matches[2], $patch)
    }
    return [pscustomobject]@{ Found = $true; Version = $ver; Major = $major }
}

function Unmerge-Instruction {
    # Quita 'harness/AGENTS.md' de instructions en un opencode.json preexistente (al desinstalar).
    # Devuelve 'removed', 'absent' o 'invalid'. Si instructions queda vacio, se elimina la clave.
    param([string]$ConfigPath, [string]$Value)
    try { $cfg = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json }
    catch { return 'invalid' }
    if (-not ($cfg.PSObject.Properties.Name -contains 'instructions')) { return 'absent' }
    $instr = @($cfg.instructions)
    if ($instr -notcontains $Value) { return 'absent' }
    $rest = @($instr | Where-Object { $_ -ne $Value })
    if ($rest.Count -gt 0) { $cfg.instructions = $rest }
    else { $cfg.PSObject.Properties.Remove('instructions') }
    [System.IO.File]::WriteAllText($ConfigPath, ($cfg | ConvertTo-Json -Depth 12), (New-Object System.Text.UTF8Encoding($false)))
    return 'removed'
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

function Add-Detected {
    param([System.Collections.Generic.HashSet[string]]$Set, [string]$Name, [string]$Why)
    [void]$Set.Add($Name)
    if ($script:DetectEvidence.ContainsKey($Name)) {
        if (-not ($script:DetectEvidence[$Name] -contains $Why)) { $script:DetectEvidence[$Name] = @($script:DetectEvidence[$Name]) + $Why }
    }
    else { $script:DetectEvidence[$Name] = @($Why) }
}

function Get-DetectedLoc {
    # Ruta del archivo relativa a la raiz del proyecto (evidencia legible, separador '/').
    param([string]$Root, [string]$Full)
    if ($Full.StartsWith($Root, [System.StringComparison]::OrdinalIgnoreCase)) { return $Full.Substring($Root.Length).TrimStart('\', '/').Replace('\', '/') }
    return $Full
}

function Get-ProjectTech {
    param([string]$Root)

    $skills = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $script:DetectEvidence = @{}
    if (-not (Test-Path -LiteralPath $Root)) { return @() }

    $exclude = '[\\/](node_modules|\.git|dist|build|bin|obj|\.godot|venv|\.venv|\.idea|\.vs|packages|harness|\.opencode|\.claude|\.agents)[\\/]'
    $files = @(Get-ChildItem -LiteralPath $Root -Recurse -File -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -notmatch $exclude })

    # byName agrupa TODOS los archivos por nombre (monorepo: varios package.json, etc.).
    $byName = @{}
    $exts = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($f in $files) {
        $key = $f.Name.ToLower()
        if ($byName.ContainsKey($key)) { $byName[$key] = @($byName[$key]) + $f } else { $byName[$key] = @($f) }
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

    # package.json (Node / frameworks / drivers) - todos los del arbol (monorepo)
    if ($byName.ContainsKey('package.json')) {
        foreach ($pj in $byName['package.json']) {
            $pkg = Get-Content -LiteralPath $pj.FullName -Raw -ErrorAction SilentlyContinue
            if (-not $pkg) { continue }
            $loc = Get-DetectedLoc -Root $Root -Full $pj.FullName
            if ($pkg -match '@angular/core') { Add-Detected $skills 'angular' "${loc}: @angular/core" }
            if ($pkg -match '"astro"') { Add-Detected $skills 'astro' "${loc}: astro" }
            if ($pkg -match '"(react|react-dom|next)"') { Add-Detected $skills 'react' "${loc}: react/next" }
            if ($pkg -match '"vue"') { Add-Detected $skills 'vue' "${loc}: vue" }
            if ($pkg -match '"svelte"') { Add-Detected $skills 'svelte' "${loc}: svelte" }
            if ($pkg -match '"(pg|postgres|mysql|mysql2|mssql)"') { Add-Detected $skills 'sql' "${loc}: driver SQL (pg/mysql/mssql)" }
            if ($pkg -match '"(mongodb|redis|ioredis)"|@azure/cosmos|@aws-sdk/client-dynamodb') { Add-Detected $skills 'nosql' "${loc}: driver NoSQL (mongodb/redis/cosmos/dynamodb)" }
        }
    }

    # Python (requirements / pyproject / pipfile) - todos los del arbol (monorepo)
    foreach ($n in @('requirements.txt', 'pyproject.toml', 'pipfile')) {
        if ($byName.ContainsKey($n)) {
            foreach ($pf in $byName[$n]) {
                $py = Get-Content -LiteralPath $pf.FullName -Raw -ErrorAction SilentlyContinue
                if (-not $py) { continue }
                $loc = Get-DetectedLoc -Root $Root -Full $pf.FullName
                if ($py -match 'fastapi') { Add-Detected $skills 'fastapi' "${loc}: fastapi" }
                if ($py -match 'django') { Add-Detected $skills 'django' "${loc}: django" }
                if ($py -match 'flask') { Add-Detected $skills 'flask' "${loc}: flask" }
                if ($py -match '(psycopg|sqlalchemy)') { Add-Detected $skills 'sql' "${loc}: psycopg/sqlalchemy" }
                if ($py -match '(pymongo|\bredis\b)') { Add-Detected $skills 'nosql' "${loc}: pymongo/redis" }
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
    Write-Host 'Quitar:  .\install.ps1 [-Project <ruta>|-Global] -Uninstall'
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
        try { $d = Get-Content -LiteralPath $projectDecl -Raw | ConvertFrom-Json }
        catch { throw "El manifiesto $projectDecl no es JSON valido: $($_.Exception.Message)" }
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
    try { $existingDeclObj = Get-Content -LiteralPath $DeclFile -Raw | ConvertFrom-Json }
    catch { throw "El manifiesto $DeclFile no es JSON valido: $($_.Exception.Message)" }
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

    # Cliente openCode: V1 rechaza el bloque V2 (ConfigInvalidError); V2 lo exige.
    $oc = Get-OpenCodeClient
    if (-not $oc.Found) {
        Write-Check WARN 'cliente openCode no encontrado en PATH (no se pudo verificar V1/V2)'
    }
    elseif ($oc.Major -ge 2) {
        Write-Check OK ("cliente openCode V2 ({0})" -f $oc.Version)
    }
    elseif ($oc.Major -eq 1) {
        Write-Check ERR ("cliente openCode V1 ({0}): rechaza el bloque V2 (ConfigInvalidError) -- actualiza a V2" -f $oc.Version)
    }
    else {
        Write-Check WARN ("cliente openCode de version ilegible ({0}): se requiere V2" -f $oc.Version)
    }

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

    $declRules = $true
    if ($existingDeclObj -and ($existingDeclObj.PSObject.Properties.Name -contains 'rules')) { $declRules = [bool]$existingDeclObj.rules }
    if ($declRules) {
        if (Test-Path -LiteralPath $RulesFile) { Write-Check OK "reglas presentes: $RulesFile" }
        else { Write-Check WARN "reglas ausentes: $RulesFile" }
    }
    elseif (Test-Path -LiteralPath $RulesFile) { Write-Check WARN "manifiesto rules:false pero existe $RulesFile (reglas no gestionadas)" }
    else { Write-Check OK 'reglas no gestionadas en este scope (rules:false)' }

    if (Test-Path -LiteralPath $ConfigFile) {
        try {
            $cfg = Get-Content -LiteralPath $ConfigFile -Raw | ConvertFrom-Json
            $v1 = @()
            if ($cfg.PSObject.Properties.Name -contains 'permission') { $v1 += 'permission' }
            if ($cfg.PSObject.Properties.Name -contains 'bash') { $v1 += 'bash' }
            if ($cfg.PSObject.Properties.Name -contains 'skills' -and $cfg.skills -is [System.Management.Automation.PSCustomObject] -and ($cfg.skills.PSObject.Properties.Name -contains 'paths')) { $v1 += 'skills.paths' }
            if ($v1.Count -gt 0) { Write-Check WARN ("opencode.json: sintaxis V1 ({0}); openCode V1 rechaza el bloque V2 (ConfigInvalidError) -- migra a permissions/shell/skills (array)" -f ($v1 -join ', ')) }
            if ($Scope -eq 'Local') {
                $paths = @()
                if ($cfg.PSObject.Properties.Name -contains 'skills') {
                    if ($cfg.skills -is [System.Management.Automation.PSCustomObject] -and ($cfg.skills.PSObject.Properties.Name -contains 'paths')) { $paths = @($cfg.skills.paths) }
                    else { $paths = @($cfg.skills) }
                }
                if ($paths -contains 'harness/skills') { Write-Check OK 'opencode.json: skills -> harness/skills' }
                else { Write-Check ERR 'opencode.json: falta skills = [harness/skills]' }
                $instr = @(); if ($cfg.PSObject.Properties.Name -contains 'instructions') { $instr = @($cfg.instructions) }
                if ($declRules) {
                    if ($instr -contains 'harness/AGENTS.md') { Write-Check OK 'opencode.json: instructions -> harness/AGENTS.md' }
                    else { Write-Check WARN 'opencode.json: falta instructions = [harness/AGENTS.md]' }
                }
                elseif ($instr -contains 'harness/AGENTS.md') { Write-Check WARN 'opencode.json: instructions -> harness/AGENTS.md con rules:false (duplica reglas de otro scope)' }
                else { Write-Check OK 'opencode.json: sin instructions (reglas en otro scope)' }
            }
            else {
                $hasPerms = ($cfg.PSObject.Properties.Name -contains 'permissions') -or ($cfg.PSObject.Properties.Name -contains 'permission')
                if ($hasPerms) { Write-Check OK 'opencode.json global: bloque de permisos presente' }
                else { Write-Check WARN 'opencode.json global: sin bloque de permisos' }
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

if ($Uninstall) {
    # Desinstala SOLO lo gestionado, por PERTENENCIA (no borra la carpeta entera):
    # - skills con marcador .harness-source -> se mueven a .harness-backup (nunca se destruyen);
    # - reglas (AGENTS.md) solo si el manifiesto dice rules:true o el hash coincide con el catalogo;
    # - .harness-backup y todo archivo ajeno -> se conservan;
    # - los directorios solo se eliminan si quedan VACIOS.
    Write-Host ("Desinstalacion - scope {0} - raiz: {1}" -f $Scope, $ScopeRoot) -ForegroundColor Cyan

    if (-not (Test-Path -LiteralPath $DeclFile)) {
        Write-Host 'AVISO  no hay .harness.json: nada que desinstalar en este scope.' -ForegroundColor Yellow
        exit 0
    }

    # Que creo el Harness (registro del manifiesto): por defecto, conservar.
    $createdConfig = $false
    $rulesManaged = $false
    $instrAdded = $false
    if ($existingDeclObj) {
        if ($existingDeclObj.PSObject.Properties.Name -contains 'created') {
            $created = $existingDeclObj.created
            if ($created -and ($created.PSObject.Properties.Name -contains 'opencode.json')) { $createdConfig = [bool]$created.'opencode.json' }
            if ($created -and ($created.PSObject.Properties.Name -contains 'instructions')) { $instrAdded = [bool]$created.instructions }
        }
        if ($existingDeclObj.PSObject.Properties.Name -contains 'rules') { $rulesManaged = [bool]$existingDeclObj.rules }
    }

    # Respaldo dentro del scope donde aparcamos lo gestionado (no se destruye nada).
    $bkDir = Join-Path $ScopeRoot '.harness-backup'
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $keepDir = $false   # el usuario tiene contenido ajeno -> conservar el directorio
    $bkLeft = $false    # al terminar queda carpeta de respaldos -> conservar su linea de .gitignore y avisar

    function Move-ToBackup {
        param([string]$Path, [string]$Name)
        if ($WhatIf) { Write-Host ("WOULD  mover {0} -> .harness-backup" -f $Path) -ForegroundColor DarkCyan; return }
        New-Item -ItemType Directory -Path $bkDir -Force | Out-Null
        # El sello tiene granularidad de segundo: dos respaldos del MISMO nombre en el mismo
        # segundo colisionarian (Move-Item falla y aborta la desinstalacion). Se desambigua.
        $dest = Join-Path $bkDir ("{0}-{1}" -f $Name, $stamp)
        $n = 1
        while (Test-Path -LiteralPath $dest) { $dest = Join-Path $bkDir ("{0}-{1}-{2}" -f $Name, $stamp, $n); $n++ }
        Move-Item -LiteralPath $Path -Destination $dest
        Write-Host ("BAK    {0} -> .harness-backup" -f $Name) -ForegroundColor Yellow
    }

    $removed = 0
    $kept = @()

    # 1) SKILLS gestionadas (marcador .harness-source). Las ajenas se conservan.
    if (Test-Path -LiteralPath $SkillsDir) {
        foreach ($dir in (Get-ChildItem -LiteralPath $SkillsDir -Directory -Force)) {
            if ($dir.Name -eq '.harness-backup') { $keepDir = $true; continue }
            if (Test-Path -LiteralPath (Join-Path $dir.FullName $MarkerName)) {
                Move-ToBackup -Path $dir.FullName -Name $dir.Name
                $removed++
            }
            else {
                $keepDir = $true
                Write-Host ("KEEP   skill {0} (ajena: sin marcador)" -f $dir.Name) -ForegroundColor Yellow
                $kept += "skill:$($dir.Name)"
            }
        }
        # El directorio skills/ se borra solo si quedo vacio.
        if (-not $WhatIf -and (Test-Path -LiteralPath $SkillsDir) -and (@(Get-ChildItem -LiteralPath $SkillsDir -Force).Count -eq 0)) {
            Remove-Item -LiteralPath $SkillsDir -Force
        }
    }

    # 2) REGLAS (AGENTS.md): solo si son nuestras (manifiesto rules:true o hash == catalogo).
    if ($rulesManaged -or $RulesOurs) {
        if (Test-Path -LiteralPath $RulesFile) {
            $srcRules = Join-Path $SourceRoot 'AGENTS.md'
            $ours = $false
            if ($rulesManaged) { $ours = $true }
            elseif (Test-Path -LiteralPath $srcRules) {
                try { $ours = ((Get-FileHash -LiteralPath $RulesFile).Hash -eq (Get-FileHash -LiteralPath $srcRules).Hash) } catch { $ours = $false }
            }
            if ($ours) { Move-ToBackup -Path $RulesFile -Name 'AGENTS.md'; $removed++ }
            else { $keepDir = $true; Write-Host ("KEEP   reglas {0} (editadas; no coinciden con el catalogo)" -f $RulesFile) -ForegroundColor Yellow; $kept += 'AGENTS.md' }
        }
    }
    elseif (Test-Path -LiteralPath $RulesFile) {
        $keepDir = $true
        Write-Host ("KEEP   reglas {0} (ajenas)" -f $RulesFile) -ForegroundColor Yellow
        $kept += 'AGENTS.md'
    }

    # 3) opencode.json: borrar SOLO si lo creo el Harness; si no, conservarlo.
    if (Test-Path -LiteralPath $ConfigFile) {
        if ($createdConfig) {
            if ($WhatIf) { Write-Host ("WOULD  borrar {0} (creado por el Harness)" -f $ConfigFile) -ForegroundColor DarkCyan }
            else { Remove-Item -LiteralPath $ConfigFile -Force; Write-Host ("DEL    {0} (creado por el Harness)" -f $ConfigFile) -ForegroundColor Green }
            $removed++
        }
        else {
            # Conservar, pero quitar el instructions SOLO si lo anadio el Harness (manifiesto).
            if ($instrAdded) {
                if ($WhatIf) { Write-Host 'WOULD  quitar instructions -> harness/AGENTS.md del opencode.json conservado' -ForegroundColor DarkCyan }
                else {
                    $un = Unmerge-Instruction -ConfigPath $ConfigFile -Value 'harness/AGENTS.md'
                    if ($un -eq 'removed') { Write-Host 'OK     opencode.json (instructions -> harness/AGENTS.md eliminado)' -ForegroundColor Green }
                }
            }
            else { Write-Host ("KEEP   {0} (y su instructions: no consta que la anadiera el Harness)" -f $ConfigFile) -ForegroundColor Yellow }
            $kept += 'opencode.json'
        }
    }

    # 4) .harness/session.md y .gitignore: solo existen en scope Local.
    if ($Scope -eq 'Local') {
        $sessDir = Join-Path $Project '.harness'
        $sessFile = Join-Path $sessDir 'session.md'
        if (Test-Path -LiteralPath $sessFile) {
            if ($WhatIf) { Write-Host ("WOULD  borrar {0}" -f $sessFile) -ForegroundColor DarkCyan }
            else { Remove-Item -LiteralPath $sessFile -Force; Write-Host ("DEL    {0}" -f $sessFile) -ForegroundColor Green }
            $removed++
        }
        if (-not $WhatIf -and (Test-Path -LiteralPath $sessDir) -and (@(Get-ChildItem -LiteralPath $sessDir -Force).Count -eq 0)) {
            Remove-Item -LiteralPath $sessDir -Force; Write-Host ("DEL    {0} (vacio)" -f $sessDir) -ForegroundColor Green
        }

        # .gitignore: quitar el bloque gestionado por el Harness (cabecera + entradas)
        $gi = Join-Path $Project '.gitignore'
        if (Test-Path -LiteralPath $gi) {
            $giRaw = Get-Content -LiteralPath $gi -Raw
            $marker = '# Harness (gestionado; refrescar con install.ps1 -Update)'
            if ($giRaw -match [regex]::Escape($marker)) {
                # Si quedan respaldos, se CONSERVA la entrada 'harness/.harness-backup/' (y la
                # cabecera): asi los respaldos no aparecen como no rastreados tras desinstalar
                # (evita un commit por descuido). Si no hay carpeta de respaldos, se quita todo.
                $keepBkEntry = Test-Path -LiteralPath $bkDir
                $lines = Get-Content -LiteralPath $gi
                $out = New-Object System.Collections.Generic.List[string]
                $skip = 0
                foreach ($ln in $lines) {
                    if ($ln.Trim() -eq $marker) {
                        if ($keepBkEntry) { $out.Add($ln) }
                        $skip = 1
                        continue
                    }
                    if ($skip -eq 1) {
                        if ($ln -match '^(harness/skills/|harness/\.harness-backup/|\.harness/)\s*$') {
                            if ($keepBkEntry -and $ln -match '^harness/\.harness-backup/\s*$') { $out.Add($ln) }
                            continue
                        }
                        $skip = 0
                    }
                    $out.Add($ln)
                }
                while ($out.Count -gt 0 -and [string]::IsNullOrWhiteSpace($out[$out.Count - 1])) { $out.RemoveAt($out.Count - 1) }
                $newGi = (@($out) -join "`n")
                if ($newGi.Length -gt 0) { $newGi += "`n" }
                if ($WhatIf) { Write-Host 'WOULD  limpiar .gitignore (bloque Harness)' -ForegroundColor DarkCyan }
                elseif ($newGi.Trim().Length -eq 0) {
                    Remove-Item -LiteralPath $gi -Force
                    Write-Host 'DEL    .gitignore (solo tenia el bloque Harness)' -ForegroundColor Green
                }
                else {
                    [System.IO.File]::WriteAllText($gi, $newGi, (New-Object System.Text.UTF8Encoding($false)))
                    if ($keepBkEntry) { Write-Host 'OK     .gitignore (bloque Harness eliminado salvo harness/.harness-backup/, que se conserva por los respaldos)' -ForegroundColor Green }
                    else { Write-Host 'OK     .gitignore (bloque Harness eliminado)' -ForegroundColor Green }
                    if ($keepBkEntry) { $kept += '.gitignore: harness/.harness-backup/' }
                }
            }
        }
    } # fin scope Local

    # 5) RESBALON: si algo ajeno queda en la raiz del scope, NO borrar el directorio.
    if (Test-Path -LiteralPath $ScopeRoot) {
        $residual = @(Get-ChildItem -LiteralPath $ScopeRoot -Force | Where-Object { $_.Name -ne '.harness-backup' })
        if ($keepDir -or $residual.Count -gt 0) {
            Write-Host ("KEEP   {0} (quedan archivos ajenos o respaldos)" -f $ScopeRoot) -ForegroundColor Yellow
            $kept += "$($ScopeRoot)"
        }
        elseif (-not $WhatIf) {
            # Solo quedaba .harness-backup (o estaba vacio): respaldos, conservar.
            $hasBk = Test-Path -LiteralPath $bkDir
            if ($hasBk) { Write-Host ("KEEP   {0} (respaldos; borralos tu si quieres)" -f $bkDir) -ForegroundColor Yellow; $kept += '.harness-backup/' }
            elseif (@(Get-ChildItem -LiteralPath $ScopeRoot -Force).Count -eq 0) {
                Remove-Item -LiteralPath $ScopeRoot -Force; Write-Host ("DEL    {0} (vacio)" -f $ScopeRoot) -ForegroundColor Green
            }
        }
    }
    # Al terminar: queda la carpeta de respaldos? (para el aviso y la linea de .gitignore)
    if (-not $WhatIf) { $bkLeft = Test-Path -LiteralPath $bkDir }

    # 6) .harness.json (manifiesto): al final.
    if ($WhatIf) { Write-Host ("WOULD  borrar {0}" -f $DeclFile) -ForegroundColor DarkCyan }
    else { Remove-Item -LiteralPath $DeclFile -Force; Write-Host ("DEL    {0}" -f $DeclFile) -ForegroundColor Green }
    $removed++

    Write-Host ''
    if ($WhatIf) { Write-Host 'WHATIF  Simulacion: no se modifico nada.' -ForegroundColor Cyan; exit 0 }
    if ($kept.Count -gt 0) { Write-Host ("Conservado: {0}" -f ($kept -join ', ')) -ForegroundColor DarkGray }
    if ($bkLeft) {
        Write-Host ''
        Write-Host ("AVISO  quedan respaldos en {0}" -f $bkDir) -ForegroundColor Yellow
        Write-Host '       revisalos; cuando los borres, puedes quitar la linea harness/.harness-backup/ del .gitignore.' -ForegroundColor Yellow
    }
    Write-Host ("Harness desinstalado del scope {0}. Recarga openCode con /reload." -f $Scope.ToLower())
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
    # Asimetria deliberada: con -Skills explicito un nombre raro es casi seguro un error de
    # tecleo -> fallar fuerte. Con -Update el set viene del manifiesto, asi que un nombre que
    # el catalogo ya no tiene significa que la skill fue RETIRADA -> avisar, omitirla y
    # refrescar el resto. Al quitarla de $desired tambien se poda del manifiesto.
    if ($Update -and -not $Skills) {
        $desired = @($desired | Where-Object { $_ -notin $unknown })
        Write-Host ("AVISO  el catalogo ya no incluye: {0}. Se omiten y se quitan del manifiesto." -f ($unknown -join ', ')) -ForegroundColor Yellow
        if ($desired.Count -eq 0) { throw "Ninguna de las skills declaradas existe ya en el catalogo ($($unknown -join ', ')). Usa -Skills para reinstalar." }
    }
    else {
        throw "Skills desconocidas: $($unknown -join ', '). Usa -List para ver el catalogo."
    }
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
    # Igual que Move-ToBackup: el sello es por segundo; si dos respaldos del mismo nombre
    # caen en el mismo segundo, se desambigua para no fallar (ni perder el respaldo).
    $dest = Join-Path $BackupDir ("{0}-{1}" -f $Name, $stamp)
    $n = 1
    while (-not $WhatIf -and (Test-Path -LiteralPath $dest)) { $dest = Join-Path $BackupDir ("{0}-{1}-{2}" -f $Name, $stamp, $n); $n++ }
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
        [System.IO.File]::WriteAllText((Join-Path $Dst $MarkerName), (New-MarkerValue -Hash $SrcHash), (New-Object System.Text.UTF8Encoding($false)))
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
                    [System.IO.File]::WriteAllText((Join-Path $dst $MarkerName), (New-MarkerValue -Hash $srcHash), (New-Object System.Text.UTF8Encoding($false)))
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
                Write-Host "WOULD  podar $($dir.Name) -> .harness-backup" -ForegroundColor DarkCyan
            }
            else {
                New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
                $pdest = Join-Path $BackupDir ("{0}-{1}" -f $dir.Name, (Get-Date -Format 'yyyyMMdd-HHmmss'))
                Move-Item -LiteralPath $dir.FullName -Destination $pdest
                Write-Host "PRUNE  $($dir.Name) -> .harness-backup" -ForegroundColor DarkGray
            }
        }
    }
}

function Merge-Instruction {
    param([string]$ConfigPath, [string]$Value)
    try { $cfg = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json }
    catch { return 'invalid' }
    if ($cfg.PSObject.Properties.Name -contains 'instructions') {
        $instr = @($cfg.instructions)
        if ($instr -contains $Value) { return 'present' }
        $cfg.instructions = @($instr + $Value)
    }
    else {
        $cfg | Add-Member -NotePropertyName 'instructions' -NotePropertyValue @($Value) -Force
    }
    [System.IO.File]::WriteAllText($ConfigPath, ($cfg | ConvertTo-Json -Depth 12), (New-Object System.Text.UTF8Encoding($false)))
    return 'added'
}

# Reglas (AGENTS.md)
$rulesManaged = $false
if ($Scope -eq 'Local') { $rulesManaged = $true }
elseif ($existingDeclObj -and ($existingDeclObj.PSObject.Properties.Name -contains 'rules')) { $rulesManaged = [bool]$existingDeclObj.rules }

$skipRules = $SkillsOnly
if ($IncludeRules) { $skipRules = $false }
elseif ($existingDeclObj -and ($existingDeclObj.PSObject.Properties.Name -contains 'rules') -and -not [bool]$existingDeclObj.rules) { $skipRules = $true }

$srcRules = Join-Path $SourceRoot 'AGENTS.md'
if ($skipRules) {
    if (Test-Path -LiteralPath $RulesFile) { Write-Host "SKIP   $RulesFile (reglas no gestionadas en este scope)" -ForegroundColor Yellow }
    else { Write-Host 'SKIP   reglas (no gestionadas en este scope)' -ForegroundColor Yellow }
    $rulesManaged = $false
}
elseif (Test-Path -LiteralPath $RulesFile) {
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
$configCreated = $false
$instrAdded = $false
if ($Scope -eq 'Local') {
    if (Test-Path -LiteralPath $ConfigFile) {
        if ($rulesManaged) {
            if ($WhatIf) {
                Write-Host 'WOULD  opencode.json (asegura instructions)' -ForegroundColor DarkCyan
            }
            else {
                $res = Merge-Instruction -ConfigPath $ConfigFile -Value 'harness/AGENTS.md'
                if ($res -eq 'added') { $instrAdded = $true; Write-Host 'OK     opencode.json (instructions -> harness/AGENTS.md)' -ForegroundColor Green }
                elseif ($res -eq 'present') { Write-Host 'SKIP   opencode.json (instructions ya presente)' -ForegroundColor Yellow }
                else { Write-Host 'SKIP   opencode.json (JSON invalido; no se toca)' -ForegroundColor Yellow }
            }
        }
        else {
            Write-Host 'SKIP   opencode.json ya existe (verifica instructions/skills)' -ForegroundColor Yellow
        }
    }
    elseif ($WhatIf) {
        Write-Host 'WOULD  opencode.json' -ForegroundColor DarkCyan
    }
    else {
        $tpl = if ($SkillsOnly) { 'opencode.skills-only.json' } else { 'opencode.json' }
        Copy-Item -LiteralPath (Join-Path $TemplatesDir $tpl) -Destination $ConfigFile -Force
        $configCreated = $true
        Write-Host 'OK     opencode.json' -ForegroundColor Green
    }

    $gi = Join-Path $Project '.gitignore'
    $existing = ''
    $giExists = Test-Path -LiteralPath $gi
    if ($giExists) { $existing = Get-Content -LiteralPath $gi -Raw }
    $entries = @('harness/skills/', 'harness/.harness-backup/', '.harness/')
    $toAdd = @($entries | Where-Object { ('' + $existing) -notmatch [regex]::Escape($_) })
    if ($toAdd.Count -gt 0) {
        if ($WhatIf) { Write-Host "WOULD  .gitignore (ignora $($toAdd -join ', '))" -ForegroundColor DarkCyan }
        else {
            # UTF-8 sin BOM. Se respeta el salto de linea del archivo existente (si lo hay);
            # si no existe, LF y sin linea en blanco inicial (regla del repo).
            $nl = "`n"
            if ($giExists -and $existing.Contains("`r`n")) { $nl = "`r`n" }
            $block = "# Harness (gestionado; refrescar con install.ps1 -Update)$nl" + (($toAdd -join $nl) + $nl)
            $newGi = if ($giExists -and $existing.Length -gt 0) {
                if ($existing.EndsWith("`n")) { $existing + $block } else { $existing + $nl + $block }
            }
            else { $block }
            [System.IO.File]::WriteAllText($gi, $newGi, (New-Object System.Text.UTF8Encoding($false)))
            Write-Host "OK     .gitignore (ignora $($toAdd -join ', '))" -ForegroundColor Green
        }
    }
    else {
        Write-Host 'SKIP   .gitignore ya ignora el harness' -ForegroundColor Yellow
    }
}
else {
    if (Test-Path -LiteralPath $ConfigFile) {
        Write-Host 'SKIP   ~/.config/opencode/opencode.json ya existe (fusiona el bloque de permisos a mano)' -ForegroundColor Yellow
    }
    else {
        if ($WhatIf) { Write-Host 'WOULD  opencode.json global (permisos)' -ForegroundColor DarkCyan }
        else {
            Copy-Item -LiteralPath (Join-Path $TemplatesDir 'opencode.global.json') -Destination $ConfigFile -Force
            Write-Host 'OK     opencode.json global (permisos)' -ForegroundColor Green
        }
    }
}

# Memoria opcional
if ($Context -and $Scope -ne 'Local') {
    Write-Host 'AVISO  -Context solo aplica al scope Local (con -Project); en Global no hay memoria que sembrar.' -ForegroundColor Yellow
}
if ($Context -and $Scope -eq 'Local') {
    foreach ($file in @('README.md', 'DEVELOPMENT.md', 'SKILL.md')) {
        $target = Join-Path $Project $file
        if (Test-Path -LiteralPath $target) {
            if (Test-EmptiedFile -Path $target) {
                if ($WhatIf) { Write-Host "WOULD  $file (sembrado: existia vacio)" -ForegroundColor DarkCyan }
                else {
                    Copy-Item -LiteralPath (Join-Path $TemplatesDir $file) -Destination $target -Force
                    Write-Host "OK     $file (sembrado: existia vacio)" -ForegroundColor Green
                }
            }
            else {
                Write-Host "SKIP   $file ya existe (con contenido; se respeta)" -ForegroundColor Yellow
            }
        }
        else {
            if ($WhatIf) { Write-Host "WOULD  $file" -ForegroundColor DarkCyan }
            else {
                Copy-Item -LiteralPath (Join-Path $TemplatesDir $file) -Destination $target -Force
                Write-Host "OK     $file" -ForegroundColor Green
            }
        }
    }

    $sessDir = Join-Path $Project '.harness'
    $sessFile = Join-Path $sessDir 'session.md'
    if (Test-Path -LiteralPath $sessFile) {
        Write-Host 'SKIP   .harness/session.md ya existe' -ForegroundColor Yellow
    }
    elseif ($WhatIf) { Write-Host 'WOULD  .harness/session.md' -ForegroundColor DarkCyan }
    else {
        New-Item -ItemType Directory -Path $sessDir -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $TemplatesDir 'session.md') -Destination $sessFile -Force
        Write-Host 'OK     .harness/session.md' -ForegroundColor Green
    }
}

# Declaracion
# 'created' registra que archivos preexistentes creo el Harness (para -Uninstall).
# Se conserva el valor previo y se suma lo recien creado (nunca se degrada a false).
# StrictMode: no acceder a .created si no existe; se comprueban las propiedades por nombre.
$prevCfg = ($existingDeclObj -and ($existingDeclObj.PSObject.Properties.Name -contains 'created') -and ($existingDeclObj.created.PSObject.Properties.Name -contains 'opencode.json') -and [bool]$existingDeclObj.created.'opencode.json')
$prevInstr = ($existingDeclObj -and ($existingDeclObj.PSObject.Properties.Name -contains 'created') -and ($existingDeclObj.created.PSObject.Properties.Name -contains 'instructions') -and [bool]$existingDeclObj.created.instructions)
$createdConfig = $configCreated -or [bool]$prevCfg
$createdInstr = $instrAdded -or [bool]$prevInstr
$skillsJson = ($desired | ForEach-Object { '    "{0}"' -f $_ }) -join ",`n"
$json = @"
{
  "schemaVersion": 1,
  "scope": "$($Scope.ToLower())",
  "rules": $($rulesManaged.ToString().ToLower()),
  "skills": [
$skillsJson
  ],
  "harnessVersion": "$Version",
  "created": {
    "opencode.json": $($createdConfig.ToString().ToLower()),
    "instructions": $($createdInstr.ToString().ToLower())
  }
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
Write-Host 'Recarga openCode con /reload (o reinicialo) para que cargue reglas y skills.'
