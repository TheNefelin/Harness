<#
.SYNOPSIS
    Instala el Harness en un proyecto de openCode.

.DESCRIPTION
    Copia las reglas (AGENTS.md) y las skills a <Proyecto>\harness\, y crea
    <Proyecto>\opencode.json desde la plantilla (no pisa archivos existentes).
    Con -Context copia ademas las plantillas de contexto
    (README.md, DEVELOPMENT.md, SKILL.md) si no existen.

.PARAMETER Project
    Ruta raiz del proyecto donde instalar el harness.

.PARAMETER Context
    Copia las plantillas de contexto (README.md, DEVELOPMENT.md, SKILL.md).

.EXAMPLE
    .\install.ps1 -Project "D:\Repo\Work\Emprendimiento\03-app-gestion"

.EXAMPLE
    .\install.ps1 -Project "D:\Repo\Work\Emprendimiento\03-app-gestion" -Context
#>
param(
    [Parameter(Mandatory = $true)]
    [string]$Project,

    [switch]$Context
)

$ErrorActionPreference = 'Stop'

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Dest = Resolve-Path -LiteralPath $Project -ErrorAction SilentlyContinue
if (-not $Dest) {
    throw "La ruta del proyecto no existe: $Project"
}
$Dest = $Dest.Path

# 1. Reglas + skills
$HarnessDest = Join-Path $Dest 'harness'
New-Item -ItemType Directory -Path $HarnessDest -Force | Out-Null

Copy-Item -LiteralPath (Join-Path $ScriptDir 'AGENTS.md') `
    -Destination (Join-Path $HarnessDest 'AGENTS.md') -Force

$SkillsDest = Join-Path $HarnessDest 'skills'
if (Test-Path -LiteralPath $SkillsDest) {
    Remove-Item -LiteralPath $SkillsDest -Recurse -Force
}
Copy-Item -LiteralPath (Join-Path $ScriptDir 'skills') `
    -Destination $SkillsDest -Recurse -Force

Write-Host "OK    harness\AGENTS.md y harness\skills\"

# 2. opencode.json
$ConfigDest = Join-Path $Dest 'opencode.json'
if (Test-Path -LiteralPath $ConfigDest) {
    Write-Host "SKIP  opencode.json ya existe (no se pisa)"
}
else {
    Copy-Item -LiteralPath (Join-Path $ScriptDir 'templates\opencode.json') `
        -Destination $ConfigDest -Force
    Write-Host "OK    opencode.json creado"
}

# 3. Contexto (opcional)
if ($Context) {
    $TemplateDir = Join-Path $ScriptDir 'templates'
    foreach ($file in @('README.md', 'DEVELOPMENT.md', 'SKILL.md')) {
        $target = Join-Path $Dest $file
        if (Test-Path -LiteralPath $target) {
            Write-Host "SKIP  $file ya existe"
        }
        else {
            Copy-Item -LiteralPath (Join-Path $TemplateDir $file) `
                -Destination $target -Force
            Write-Host "OK    $file creado"
        }
    }
}

Write-Host ""
Write-Host "Harness instalado en: $Dest"
Write-Host "Reinicia openCode dentro del proyecto para que cargue reglas y skills."
