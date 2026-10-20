<#
.SYNOPSIS
    Pruebas de integracion del Harness: install.ps1 y check.ps1 en un sandbox temporal.
    Auto-contenido (sin modulos externos); sale 0 (todo ok) o 1 (algun fallo).

.DESCRIPTION
    Levanta cada script como proceso hijo (-File) dentro de un directorio temporal,
    para no tocar el HOME ni proyectos reales, y verifica codigos de salida y
    efectos en disco (manifiesto, skills, respaldos, guard de schemaVersion...).

.EXAMPLE
    ./tools/test.ps1
    ./tools/test.ps1 -KeepSandbox
#>
param(
    [switch]$KeepSandbox
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

$Repo    = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$Install = Join-Path $Repo 'install.ps1'
$Check   = Join-Path (Join-Path $Repo 'tools') 'check.ps1'

$script:OnWindows = ($env:OS -eq 'Windows_NT')
if ($PSVersionTable.PSEdition -eq 'Core') {
    $script:Exe = if ($script:OnWindows) { Join-Path $PSHOME 'pwsh.exe' } else { Join-Path $PSHOME 'pwsh' }
}
else {
    $script:Exe = Join-Path $PSHOME 'powershell.exe'
}

$script:Pass = 0
$script:Fail = 0
$script:Failures = [System.Collections.Generic.List[string]]::new()

function Section { param([string]$t) Write-Host ""; Write-Host "[$t]" -ForegroundColor Cyan }
function Assert { param([bool]$Cond, [string]$Msg) if ($Cond) { $script:Pass++; Write-Host "  ok   $Msg" -ForegroundColor Green } else { $script:Fail++; [void]$script:Failures.Add($Msg); Write-Host "  FAIL $Msg" -ForegroundColor Red } }

function Invoke-Script {
    param([string]$Script, [string[]]$Arguments)
    $all = @('-NoProfile')
    if ($script:OnWindows) { $all += @('-ExecutionPolicy', 'Bypass') }
    $all += @('-File', $Script)
    if ($Arguments) { $all += $Arguments }
    $eap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { $out = & $script:Exe @all 2>&1 | Out-String }
    finally { $ErrorActionPreference = $eap }
    return [pscustomobject]@{ Exit = $LASTEXITCODE; Out = $out }
}

function New-Project { param([string]$Name) $p = Join-Path $script:Sandbox $Name; New-Item -ItemType Directory -Force -Path $p | Out-Null; return $p }

function Write-NoBom { param([string]$Path, [string]$Text) [System.IO.File]::WriteAllText($Path, $Text, (New-Object System.Text.UTF8Encoding($false))) }

$script:Sandbox = Join-Path ([System.IO.Path]::GetTempPath()) ('harness-test-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force -Path $script:Sandbox | Out-Null

Write-Host ("Harness - pruebas de integracion  (sandbox: {0})" -f $script:Sandbox) -ForegroundColor Cyan

try {
    # --- Lista del catalogo --------------------------------------------------
    Section 'install.ps1 -List'
    $r = Invoke-Script $Install @('-List')
    Assert ($r.Exit -eq 0) '-List sale 0'
    Assert ($r.Out -match 'dotnet') '-List incluye dotnet'
    Assert ($r.Out -match 'harness-install') '-List incluye harness-install'

    # --- Instalacion local ---------------------------------------------------
    Section 'Instalacion local (dotnet,sql)'
    $p1 = New-Project 'proj1'
    $r = Invoke-Script $Install @('-Project', $p1, '-Skills', 'dotnet,sql', '-Source', $Repo)
    Assert ($r.Exit -eq 0) 'instalacion sale 0'
    $decl = Join-Path $p1 '.harness.json'
    Assert (Test-Path -LiteralPath $decl) 'escribe .harness.json'
    if (Test-Path -LiteralPath $decl) {
        $m = Get-Content -LiteralPath $decl -Raw | ConvertFrom-Json
        Assert ($m.scope -eq 'local') 'manifest scope=local'
        Assert ($m.schemaVersion -eq 1) 'manifest schemaVersion=1'
        Assert (@($m.skills) -contains 'dotnet') 'manifest declara dotnet'
        Assert (@($m.skills) -contains 'sql') 'manifest declara sql'
    }
    Assert (Test-Path -LiteralPath (Join-Path $p1 'harness/AGENTS.md')) 'copia AGENTS.md'
    Assert (Test-Path -LiteralPath (Join-Path $p1 'harness/skills/dotnet/SKILL.md')) 'copia skill dotnet'
    Assert (Test-Path -LiteralPath (Join-Path $p1 'harness/skills/dotnet/.harness-source')) 'pone marcador .harness-source'
    Assert (Test-Path -LiteralPath (Join-Path $p1 'opencode.json')) 'crea opencode.json'
    $gi = Join-Path $p1 '.gitignore'
    if (Test-Path -LiteralPath $gi) {
        $giRaw = Get-Content -LiteralPath $gi -Raw
        Assert ($giRaw -match 'harness') '.gitignore ignora el harness'
        Assert ($giRaw -match [regex]::Escape('.harness/')) '.gitignore ignora .harness/'
    }
    else { Assert $false '.gitignore existe' }

    # --- Doctor --------------------------------------------------------------
    Section 'install.ps1 -Doctor (instalacion sana)'
    $r = Invoke-Script $Install @('-Project', $p1, '-Doctor', '-Source', $Repo)
    Assert ($r.Exit -eq 0) '-Doctor sale 0'

    # --- Doctor: avisa sintaxis V1 -------------------------------------------
    Section 'install.ps1 -Doctor (avisa sintaxis V1)'
    $pv1 = New-Project 'proj-v1'
    $r = Invoke-Script $Install @('-Project', $pv1, '-Skills', 'dotnet', '-Source', $Repo)
    Assert ($r.Exit -eq 0) 'instalacion para el caso V1 sale 0'
    $v1json = '{ "permission": { "read": "allow" }, "skills": { "paths": ["harness/skills"] } }'
    [System.IO.File]::WriteAllText((Join-Path $pv1 'opencode.json'), $v1json, (New-Object System.Text.UTF8Encoding($false)))
    $r = Invoke-Script $Install @('-Project', $pv1, '-Doctor', '-Source', $Repo)
    Assert ($r.Exit -eq 0) '-Doctor con V1 sale 0 (aviso, no fallo)'
    Assert ($r.Out -match 'V1') '-Doctor avisa de la sintaxis V1'

    # --- WhatIf --------------------------------------------------------------
    Section 'install.ps1 -WhatIf (no escribe)'
    $p2 = New-Project 'proj2'
    $r = Invoke-Script $Install @('-Project', $p2, '-Skills', 'dotnet', '-WhatIf', '-Source', $Repo)
    Assert ($r.Exit -eq 0) '-WhatIf sale 0'
    Assert (-not (Test-Path -LiteralPath (Join-Path $p2 '.harness.json'))) '-WhatIf no crea .harness.json'
    Assert (-not (Test-Path -LiteralPath (Join-Path $p2 'harness'))) '-WhatIf no crea harness/'

    # --- Update idempotente --------------------------------------------------
    Section 'install.ps1 -Update (sin cambios)'
    $r = Invoke-Script $Install @('-Project', $p1, '-Update', '-Source', $Repo)
    Assert ($r.Exit -eq 0) '-Update sale 0'
    Assert (-not (Test-Path -LiteralPath (Join-Path $p1 'harness/.harness-backup'))) '-Update sin cambios no respalda'

    # --- Conflicto y respaldo ------------------------------------------------
    Section 'install.ps1 -Update (skill editada -> respaldo)'
    $sk = Join-Path $p1 'harness/skills/dotnet/SKILL.md'
    Add-Content -LiteralPath $sk -Value "`n<!-- editado a mano -->"
    $r = Invoke-Script $Install @('-Project', $p1, '-Update', '-Source', $Repo)
    Assert ($r.Exit -eq 0) '-Update con conflicto sale 0'
    Assert (Test-Path -LiteralPath (Join-Path $p1 'harness/.harness-backup')) 'crea .harness-backup'
    $refH = (Get-FileHash -LiteralPath (Join-Path $Repo 'skills/dotnet/SKILL.md')).Hash
    $insH = (Get-FileHash -LiteralPath $sk).Hash
    Assert ($refH -eq $insH) 'refresca la skill al catalogo'

    # --- Reglas editadas -> respaldo ----------------------------------------
    Section 'install.ps1 -Update (AGENTS.md editado -> respaldo)'
    $pg = New-Project 'proj-rules'
    $r = Invoke-Script $Install @('-Project', $pg, '-Skills', 'dotnet', '-Source', $Repo)
    Assert ($r.Exit -eq 0) 'instala con reglas'
    $rg = Join-Path $pg 'harness/AGENTS.md'
    Add-Content -LiteralPath $rg -Value "`n<!-- editado a mano -->"
    $r = Invoke-Script $Install @('-Project', $pg, '-Update', '-Source', $Repo)
    Assert ($r.Exit -eq 0) '-Update con AGENTS.md editado sale 0'
    $bdir = Join-Path $pg 'harness/.harness-backup'
    Assert ((Test-Path -LiteralPath $bdir) -and (@(Get-ChildItem -LiteralPath $bdir -Filter 'AGENTS.md-*').Count -ge 1)) 'respalda el AGENTS.md editado'
    Assert ((Get-FileHash -LiteralPath $rg).Hash -eq (Get-FileHash -LiteralPath (Join-Path $Repo 'AGENTS.md')).Hash) 'refresca AGENTS.md al catalogo'

    # --- Deteccion -----------------------------------------------------------
    Section 'install.ps1 -Detect'
    $p3 = New-Project 'proj3'
    New-Item -ItemType Directory -Force -Path (Join-Path $p3 '.github/workflows'), (Join-Path $p3 'infra') | Out-Null
    Set-Content -LiteralPath (Join-Path $p3 'App.csproj') '<Project><ItemGroup><PackageReference Include="Npgsql" /></ItemGroup></Project>'
    Set-Content -LiteralPath (Join-Path $p3 'package.json') '{ "dependencies": { "@angular/core": "^21.0.0" } }'
    Set-Content -LiteralPath (Join-Path $p3 'Dockerfile') 'FROM alpine'
    Set-Content -LiteralPath (Join-Path $p3 'requirements.txt') 'fastapi'
    Set-Content -LiteralPath (Join-Path $p3 'infra/main.tf') 'provider "aws" {}'
    Set-Content -LiteralPath (Join-Path $p3 '.github/workflows/ci.yml') 'name: ci'
    $r = Invoke-Script $Install @('-Project', $p3, '-Detect', '-Source', $Repo)
    Assert ($r.Exit -eq 0) '-Detect sale 0'
    Assert ($r.Out -match 'angular') '-Detect detecta angular'
    Assert ($r.Out -match 'aws') '-Detect detecta aws'
    Assert ($r.Out -match 'sql') '-Detect detecta sql (.csproj Npgsql)'

    # --- Deteccion en monorepo (varios archivos de dependencias) ------------
    Section 'install.ps1 -Detect (monorepo)'
    $pm = New-Project 'proj-monorepo'
    New-Item -ItemType Directory -Force -Path (Join-Path $pm 'apps/web'), (Join-Path $pm 'apps/api'), (Join-Path $pm 'services/py') | Out-Null
    Set-Content -LiteralPath (Join-Path $pm 'apps/web/package.json') '{ "dependencies": { "@angular/core": "^21.0.0" } }'
    Set-Content -LiteralPath (Join-Path $pm 'apps/api/package.json') '{ "dependencies": { "astro": "^5.0.0" } }'
    Set-Content -LiteralPath (Join-Path $pm 'services/py/requirements.txt') 'fastapi'
    Set-Content -LiteralPath (Join-Path $pm 'requirements.txt') 'django'
    $r = Invoke-Script $Install @('-Project', $pm, '-Detect', '-Source', $Repo)
    Assert ($r.Exit -eq 0) '-Detect monorepo sale 0'
    Assert ($r.Out -match 'angular') '-Detect lee package.json anidado (angular)'
    Assert ($r.Out -match 'astro') '-Detect lee el otro package.json (astro)'
    Assert ($r.Out -match 'fastapi') '-Detect lee requirements.txt anidado (fastapi)'
    Assert ($r.Out -match 'django') '-Detect lee requirements.txt de la raiz (django)'

    # --- Guard de schemaVersion ---------------------------------------------
    Section 'install.ps1 guard schemaVersion'
    $p4 = New-Project 'proj4'
    Set-Content -LiteralPath (Join-Path $p4 '.harness.json') '{ "schemaVersion": 2, "scope": "local", "rules": true, "skills": [ "dotnet" ], "harnessVersion": "9.9.9" }'
    $r = Invoke-Script $Install @('-Project', $p4, '-Update', '-Source', $Repo)
    Assert ($r.Exit -ne 0) '-Update aborta si schemaVersion es mas nuevo'
    $r = Invoke-Script $Install @('-Project', $p4, '-Doctor', '-Source', $Repo)
    Assert ($r.Exit -ne 0) '-Doctor falla si schemaVersion es mas nuevo'

    # --- Manifiesto corrupto (error limpio) ---------------------------------
    Section 'install.ps1 manifiesto corrupto (falla limpio)'
    $px = New-Project 'proj-corrupt'
    Set-Content -LiteralPath (Join-Path $px '.harness.json') '{ esto no es json'
    $r = Invoke-Script $Install @('-Project', $px, '-Update', '-Source', $Repo)
    Assert ($r.Exit -ne 0) '-Update aborta con manifiesto corrupto'
    Assert (-not (Test-Path -LiteralPath (Join-Path $px 'harness'))) 'no escribe nada si el manifiesto es invalido'

    # --- Skill ajena protegida ----------------------------------------------
    Section 'install.ps1 protege skills ajenas'
    $pj = New-Project 'proj5'
    [void](Invoke-Script $Install @('-Project', $pj, '-Skills', 'dotnet,sql', '-Source', $Repo))
    $mine = Join-Path $pj 'harness/skills/mine'
    New-Item -ItemType Directory -Force -Path $mine | Out-Null
    Set-Content -LiteralPath (Join-Path $mine 'SKILL.md') 'propia'
    $r = Invoke-Script $Install @('-Project', $pj, '-Update', '-Source', $Repo)
    Assert ($r.Exit -eq 0) '-Update con skill ajena sale 0'
    Assert (Test-Path -LiteralPath (Join-Path $mine 'SKILL.md')) 'no poda la skill ajena'

    # --- Poda de skill gestionada -------------------------------------------
    Section 'install.ps1 -Update (poda de skill gestionada)'
    $pp = New-Project 'proj-prune'
    $r = Invoke-Script $Install @('-Project', $pp, '-Skills', 'dotnet,sql', '-Source', $Repo)
    Assert ($r.Exit -eq 0) 'instala dotnet,sql'
    Assert (Test-Path -LiteralPath (Join-Path $pp 'harness/skills/sql')) 'sql instalada'
    $r = Invoke-Script $Install @('-Project', $pp, '-Update', '-Skills', 'dotnet', '-Source', $Repo)
    Assert ($r.Exit -eq 0) '-Update -Skills dotnet sale 0'
    Assert (-not (Test-Path -LiteralPath (Join-Path $pp 'harness/skills/sql'))) 'poda sql del set'
    Assert (@(Get-ChildItem -LiteralPath (Join-Path $pp 'harness/.harness-backup') -Filter 'sql-*').Count -ge 1) 'respalda la skill podada'
    $declp = Get-Content -LiteralPath (Join-Path $pp '.harness.json') -Raw | ConvertFrom-Json
    Assert (-not (@($declp.skills) -contains 'sql')) 'manifest sin sql'
    Assert (@($declp.skills) -contains 'dotnet') 'manifest conserva dotnet'

    # --- SkillsOnly (sin reglas) --------------------------------------------
    Section 'install.ps1 -SkillsOnly (sin reglas)'
    $po = New-Project 'proj-skills-only'
    $r = Invoke-Script $Install @('-Project', $po, '-Skills', 'dotnet', '-SkillsOnly', '-Source', $Repo)
    Assert ($r.Exit -eq 0) '-SkillsOnly sale 0'
    Assert (Test-Path -LiteralPath (Join-Path $po 'harness/skills/dotnet/SKILL.md')) '-SkillsOnly instala la skill'
    Assert (-not (Test-Path -LiteralPath (Join-Path $po 'harness/AGENTS.md'))) '-SkillsOnly no copia AGENTS.md'
    $declo = Join-Path $po '.harness.json'
    if (Test-Path -LiteralPath $declo) {
        $mo = Get-Content -LiteralPath $declo -Raw | ConvertFrom-Json
        Assert (-not $mo.rules) 'manifest rules=false'
    }
    else { Assert $false 'SkillsOnly escribe .harness.json' }
    $cfgo = Join-Path $po 'opencode.json'
    if (Test-Path -LiteralPath $cfgo) {
        $co = Get-Content -LiteralPath $cfgo -Raw | ConvertFrom-Json
        Assert (-not ($co.PSObject.Properties.Name -contains 'instructions')) 'opencode.json sin instructions'
        Assert (@($co.skills) -contains 'harness/skills') 'opencode.json conserva skills'
    }
    else { Assert $false 'SkillsOnly crea opencode.json' }
    $r = Invoke-Script $Install @('-Project', $po, '-Doctor', '-Source', $Repo)
    Assert ($r.Exit -eq 0) '-Doctor de SkillsOnly sale 0'

    # --- IncludeRules (revierte SkillsOnly) ---------------------------------
    Section 'install.ps1 -IncludeRules (revierte -SkillsOnly)'
    $pr = New-Project 'proj-include-rules'
    $r = Invoke-Script $Install @('-Project', $pr, '-Skills', 'dotnet', '-SkillsOnly', '-Source', $Repo)
    Assert ($r.Exit -eq 0) 'base -SkillsOnly sale 0'
    Assert (-not (Test-Path -LiteralPath (Join-Path $pr 'harness/AGENTS.md'))) 'base sin AGENTS.md'
    $r = Invoke-Script $Install @('-Project', $pr, '-Update', '-Source', $Repo)
    Assert ($r.Exit -eq 0) '-Update sin flags sale 0'
    Assert (-not (Test-Path -LiteralPath (Join-Path $pr 'harness/AGENTS.md'))) '-Update conserva rules:false'
    $r = Invoke-Script $Install @('-Project', $pr, '-Update', '-IncludeRules', '-Source', $Repo)
    Assert ($r.Exit -eq 0) '-IncludeRules sale 0'
    Assert (Test-Path -LiteralPath (Join-Path $pr 'harness/AGENTS.md')) '-IncludeRules reinstala AGENTS.md'
    $declr = Get-Content -LiteralPath (Join-Path $pr '.harness.json') -Raw | ConvertFrom-Json
    Assert ($declr.rules) 'manifest rules=true tras -IncludeRules'
    $cfgr = Get-Content -LiteralPath (Join-Path $pr 'opencode.json') -Raw | ConvertFrom-Json
    Assert (@($cfgr.instructions) -contains 'harness/AGENTS.md') 'opencode.json con instructions tras -IncludeRules'
    $r = Invoke-Script $Install @('-Project', $pr, '-Doctor', '-Source', $Repo)
    Assert ($r.Exit -eq 0) '-Doctor tras -IncludeRules sale 0'
    $rc = Invoke-Script $Install @('-Project', $pr, '-SkillsOnly', '-IncludeRules', '-Source', $Repo)
    Assert ($rc.Exit -ne 0) '-SkillsOnly + -IncludeRules falla'

    # --- Context (plantillas de memoria) ------------------------------------
    Section 'install.ps1 -Context (plantillas de memoria)'
    $pc = New-Project 'proj-context'
    $r = Invoke-Script $Install @('-Project', $pc, '-Skills', 'dotnet', '-Context', '-Source', $Repo)
    Assert ($r.Exit -eq 0) '-Context sale 0'
    Assert (Test-Path -LiteralPath (Join-Path $pc 'DEVELOPMENT.md')) '-Context copia DEVELOPMENT.md'
    Assert (Test-Path -LiteralPath (Join-Path $pc '.harness/session.md')) '-Context copia .harness/session.md'

    # -Context respeta archivos con contenido y siembra los vacios
    $pd = New-Project 'proj-context-vacio'
    Write-NoBom (Join-Path $pd 'DEVELOPMENT.md') "   `r`n"
    Write-NoBom (Join-Path $pd 'README.md') "# Mi proyecto`r`n`r`nContenido propio.`r`n"
    $r = Invoke-Script $Install @('-Project', $pd, '-Skills', 'dotnet', '-Context', '-Source', $Repo)
    Assert ($r.Exit -eq 0) '-Context con .md preexistentes sale 0'
    $devRaw = Get-Content -LiteralPath (Join-Path $pd 'DEVELOPMENT.md') -Raw
    Assert ($devRaw -match 'Decisiones t') '-Context siembra la plantilla en DEVELOPMENT.md vacio'
    Assert ($devRaw -match 'Mapa del proyecto') '-Context siembra la plantilla con el Mapa del proyecto'
    Assert ($r.Out -match 'existia vacio') '-Context informa que sembro un archivo vacio'
    $readmeRaw = Get-Content -LiteralPath (Join-Path $pd 'README.md') -Raw
    Assert ($readmeRaw -match 'Contenido propio') '-Context respeta README.md con contenido'
    Assert (-not ($readmeRaw -match 'Requisitos')) '-Context no pisa README.md con contenido'

    # --- Doctor: version del cliente openCode --------------------------------
    Section 'install.ps1 -Doctor (cliente openCode)'
    $ocStub = Join-Path $script:Sandbox 'oc-stub'
    New-Item -ItemType Directory -Force -Path $ocStub | Out-Null
    $pdOc = New-Project 'proj-doctor-oc'
    $r = Invoke-Script $Install @('-Project', $pdOc, '-Skills', 'dotnet', '-Source', $Repo)
    Assert ($r.Exit -eq 0) 'instalacion para el caso openCode sale 0'
    $r = Invoke-Script $Install @('-Project', $pdOc, '-Doctor', '-Source', $Repo)
    Assert ($r.Exit -eq 0) '-Doctor sin cliente openCode sale 0'
    Assert ($r.Out -match 'no encontrado en PATH') '-Doctor avisa si no encuentra el cliente'
    $savedPath = $env:PATH
    $savedEap = $ErrorActionPreference
    try {
        Write-NoBom (Join-Path $ocStub 'opencode.cmd') "@echo off`r`necho 1.18.9`r`n"
        $env:PATH = $ocStub + [System.IO.Path]::PathSeparator + $savedPath
        $r = Invoke-Script $Install @('-Project', $pdOc, '-Doctor', '-Source', $Repo)
        Assert ($r.Exit -ne 0) '-Doctor falla con cliente V1 en PATH'
        Assert ($r.Out -match 'opencode V1') '-Doctor nombra el cliente V1'
        Write-NoBom (Join-Path $ocStub 'opencode.cmd') "@echo off`r`necho 3.0.2`r`n"
        $r = Invoke-Script $Install @('-Project', $pdOc, '-Doctor', '-Source', $Repo)
        Assert ($r.Exit -eq 0) '-Doctor pasa con cliente V2 en PATH'
        Assert ($r.Out -match 'opencode V2') '-Doctor reconoce el cliente V2'
    }
    finally { $env:PATH = $savedPath; $ErrorActionPreference = $savedEap }

    # --- Uninstall -----------------------------------------------------------
    Section 'install.ps1 -Uninstall (borra solo lo gestionado)'
    $pu = New-Project 'proj-uninstall'
    Write-NoBom (Join-Path $pu 'LaserBoy.md') "# Doc propio`r`ncontenido`r`n"
    Write-NoBom (Join-Path $pu 'DEVELOPMENT.md') ''
    $r = Invoke-Script $Install @('-Project', $pu, '-Skills', 'dotnet', '-Context', '-Source', $Repo)
    Assert ($r.Exit -eq 0) 'instalacion para -Uninstall sale 0'
    # El usuario escribe en la memoria sembrada (simula avance)
    Write-NoBom (Join-Path $pu 'DEVELOPMENT.md') "# Desarrollo`r`n`r`nmi avance`r`n"
    # Un respaldo dentro de harness/ (no debe perderse silenciosamente, pero se borra con harness/)
    $declPu = Get-Content -LiteralPath (Join-Path $pu '.harness.json') -Raw | ConvertFrom-Json
    Assert ($declPu.created.'opencode.json' -eq $true) 'manifiesto registra created.opencode.json=true'
    # -WhatIf no borra nada
    $r = Invoke-Script $Install @('-Project', $pu, '-Uninstall', '-WhatIf', '-Source', $Repo)
    Assert ($r.Exit -eq 0) '-Uninstall -WhatIf sale 0'
    Assert (Test-Path -LiteralPath (Join-Path $pu 'harness')) '-Uninstall -WhatIf no borra harness/'
    Assert ($r.Out -match 'WHATIF') '-Uninstall -WhatIf informa simulacion'
    # Desinstalacion real
    $r = Invoke-Script $Install @('-Project', $pu, '-Uninstall', '-Source', $Repo)
    Assert ($r.Exit -eq 0) '-Uninstall sale 0'
    Assert (-not (Test-Path -LiteralPath (Join-Path $pu 'harness'))) '-Uninstall borra harness/'
    Assert (-not (Test-Path -LiteralPath (Join-Path $pu '.harness.json'))) '-Uninstall borra .harness.json'
    Assert (-not (Test-Path -LiteralPath (Join-Path $pu '.harness/session.md'))) '-Uninstall borra .harness/session.md'
    Assert (-not (Test-Path -LiteralPath (Join-Path $pu 'opencode.json'))) '-Uninstall borra opencode.json creado por el Harness'
    Assert (-not (Test-Path -LiteralPath (Join-Path $pu '.gitignore'))) '-Uninstall borra .gitignore si solo tenia el bloque Harness'
    Assert (Test-Path -LiteralPath (Join-Path $pu 'LaserBoy.md')) '-Uninstall respeta el codigo/doc del usuario'
    Assert (Test-Path -LiteralPath (Join-Path $pu 'DEVELOPMENT.md')) '-Uninstall respeta DEVELOPMENT.md'
    Assert ((Get-Content -LiteralPath (Join-Path $pu 'DEVELOPMENT.md') -Raw) -match 'mi avance') '-Uninstall conserva el avance del usuario en DEVELOPMENT.md'

    # -Uninstall con opencode.json y .gitignore preexistentes: los conserva
    $pu2 = New-Project 'proj-uninstall-keep'
    Write-NoBom (Join-Path $pu2 'opencode.json') "{`n  `"model`": `"mi-modelo`"`n}`n"
    Write-NoBom (Join-Path $pu2 '.gitignore') "# mis reglas`r`nnode_modules/`r`n"
    $r = Invoke-Script $Install @('-Project', $pu2, '-Skills', 'dotnet', '-Source', $Repo)
    Assert ($r.Exit -eq 0) 'instalacion sobre archivos propios sale 0'
    $r = Invoke-Script $Install @('-Project', $pu2, '-Uninstall', '-Source', $Repo)
    Assert ($r.Exit -eq 0) '-Uninstall sobre archivos propios sale 0'
    Assert (Test-Path -LiteralPath (Join-Path $pu2 'opencode.json')) '-Uninstall conserva opencode.json preexistente'
    $cfgKept = Get-Content -LiteralPath (Join-Path $pu2 'opencode.json') -Raw | ConvertFrom-Json
    Assert ($cfgKept.model -eq 'mi-modelo') '-Uninstall conserva el contenido propio de opencode.json'
    Assert (-not ($cfgKept.PSObject.Properties.Name -contains 'instructions')) '-Uninstall quita el instructions fusionado del opencode.json conservado'
    $giKept = Get-Content -LiteralPath (Join-Path $pu2 '.gitignore') -Raw
    Assert ($giKept -match 'node_modules') '-Uninstall conserva las reglas propias de .gitignore'
    Assert (-not ($giKept -match 'harness/skills')) '-Uninstall quita el bloque Harness del .gitignore'
    # -Uninstall sin manifiesto: aviso, no error
    $pu3 = New-Project 'proj-uninstall-none'
    $r = Invoke-Script $Install @('-Project', $pu3, '-Uninstall', '-Source', $Repo)
    Assert ($r.Exit -eq 0) '-Uninstall sin instalacion sale 0 (aviso)'
    Assert ($r.Out -match 'nada que desinstalar') '-Uninstall sin manifiesto avisa'

    # --- check.ps1 -----------------------------------------------------------
    Section 'check.ps1'
    $r = Invoke-Script $Check @()
    Assert ($r.Exit -eq 0) 'check.ps1 sale 0'
    $r = Invoke-Script $Check @('-OverlapThreshold', '0.01', '-Strict')
    Assert ($r.Exit -ne 0) 'check.ps1 -Strict falla con umbral de solapamiento minimo'
    $r = Invoke-Script $Check @('-MaxAgeDays', '0')
    Assert ($r.Exit -ne 0) 'check.ps1 falla con MaxAgeDays 0 (frescura)'

    # --- check.ps1: referencias citadas/alcanzables -------------------------
    Section 'check.ps1 referencias (citadas y alcanzables)'

    $fa = New-Project 'chk-refs-ok'
    New-Item -ItemType Directory -Force -Path (Join-Path $fa 'tools'), (Join-Path $fa 'evals'), (Join-Path $fa 'skills/demo/references/sub') | Out-Null
    Copy-Item -LiteralPath $Check -Destination (Join-Path $fa 'tools/check.ps1')
    Set-Content -LiteralPath (Join-Path $fa 'evals/triggers.json') -Value '[]'
    Write-NoBom (Join-Path $fa 'skills/demo/SKILL.md') "---`nname: demo`ndescription: `"Demo para pruebas`"`n---`n`n# Demo`n`nVer references/a.md para el detalle.`n"
    Write-NoBom (Join-Path $fa 'skills/demo/references/a.md') "# A`n`nVer references/sub/b.md.`n"
    Write-NoBom (Join-Path $fa 'skills/demo/references/sub/b.md') "# B`n`nContenido.`n"
    $r = Invoke-Script (Join-Path $fa 'tools/check.ps1') @()
    Assert ($r.Exit -eq 0) 'check pasa con referencias citadas (incl. anidada)'

    $fb = New-Project 'chk-refs-orphan'
    New-Item -ItemType Directory -Force -Path (Join-Path $fb 'tools'), (Join-Path $fb 'evals'), (Join-Path $fb 'skills/demo/references') | Out-Null
    Copy-Item -LiteralPath $Check -Destination (Join-Path $fb 'tools/check.ps1')
    Set-Content -LiteralPath (Join-Path $fb 'evals/triggers.json') -Value '[]'
    Write-NoBom (Join-Path $fb 'skills/demo/SKILL.md') "---`nname: demo`ndescription: `"Demo para pruebas`"`n---`n`n# Demo`n"
    Write-NoBom (Join-Path $fb 'skills/demo/references/orphan.md') "# Huerfana`n"
    $r = Invoke-Script (Join-Path $fb 'tools/check.ps1') @()
    Assert ($r.Exit -ne 0) 'check falla con referencia no citada'
    Assert ($r.Out -match 'orphan') 'check nombra la referencia huerfana'

    # --- Plantillas: permisos V2 (deniega secretos, permite plantillas) ------
    Section 'templates (permisos V2: deniega secretos, permite plantillas)'
    # Nota: Get-ShellEffect SIMULA la segmentacion de comandos compuestos (no prueba
    # openCode). Los asertos de .env son reales; los de shell validan la INTENCION de las
    # reglas, no el runtime. Si openCode no segmenta, "git status && git push" no se bloquea.
    function Get-RuleEffect { param($Rules, [string]$Resource) $eff = $null; foreach ($r in $Rules) { if ($r.action -eq 'read' -and $Resource -like $r.resource) { $eff = $r.effect } }; return $eff }
    function Get-ShellEffect { param($Rules, [string]$Resource) $worst = 'allow'; foreach ($seg in ($Resource -split '\s*(?:&&|\|\||;|\|)\s*' | Where-Object { $_ -ne '' })) { $eff = $null; foreach ($r in $Rules) { if ($r.action -eq 'shell' -and $seg -like $r.resource) { $eff = $r.effect } }; if ($null -eq $eff) { $eff = 'ask' }; if ($eff -eq 'deny') { return 'deny' }; if ($eff -eq 'ask') { $worst = 'ask' } }; return $worst }
    foreach ($t in @('opencode.json', 'opencode.global.json', 'opencode.skills-only.json')) {
        $cfg = Get-Content -LiteralPath (Join-Path $Repo ('templates/' + $t)) -Raw | ConvertFrom-Json
        Assert ($cfg.PSObject.Properties.Name -contains 'permissions') "$t usa 'permissions' (V2)"
        $rules = @($cfg.permissions)
        Assert ((Get-RuleEffect $rules '.env') -eq 'deny') "$t deniega .env (raiz)"
        Assert ((Get-RuleEffect $rules 'sub/.env') -eq 'deny') "$t deniega sub/.env"
        Assert ((Get-RuleEffect $rules '.env.local') -eq 'deny') "$t deniega .env.local"
        Assert ((Get-RuleEffect $rules '.env.example') -eq 'allow') "$t permite .env.example"
        Assert ((Get-RuleEffect $rules '.env.sample') -eq 'allow') "$t permite .env.sample"
        Assert ((Get-RuleEffect $rules '.env.template') -eq 'allow') "$t permite .env.template"
        Assert ((Get-ShellEffect $rules 'git status --short') -eq 'allow') "$t permite git status (solo lectura)"
        Assert ((Get-ShellEffect $rules 'git log --oneline') -eq 'allow') "$t permite git log (solo lectura)"
        Assert ((Get-ShellEffect $rules 'git commit -m x') -eq 'deny') "$t deniega git commit"
        Assert ((Get-ShellEffect $rules 'git push origin main') -eq 'deny') "$t deniega git push"
        Assert ((Get-ShellEffect $rules 'git status && rm -rf /') -eq 'ask') "$t no confirma git status encadenado sin preguntar"
        Assert ((Get-ShellEffect $rules 'git status && git push origin main') -eq 'deny') "$t deniega push encadenado tras un git status permitido"
        Assert ((Get-ShellEffect $rules 'tee /etc/passwd') -eq 'ask') "$t pregunta por shell arbitrario"
        if ($t -ne 'opencode.global.json') { Assert (@($cfg.skills) -contains 'harness/skills') "${t}: skills = [harness/skills]" }
    }
}
catch {
    $script:Fail++
    $script:Failures.Add("excepcion no controlada: $($_.Exception.Message)")
    Write-Host ("  FAIL excepcion: {0}" -f $_.Exception.Message) -ForegroundColor Red
}
finally {
    if ($KeepSandbox) { Write-Host ("`nSandbox conservado: {0}" -f $script:Sandbox) -ForegroundColor DarkGray }
    elseif (Test-Path -LiteralPath $script:Sandbox) { Remove-Item -LiteralPath $script:Sandbox -Recurse -Force -ErrorAction SilentlyContinue }
}

Write-Host ''
$total = $script:Pass + $script:Fail
if ($script:Fail -gt 0) {
    Write-Host 'Fallos:' -ForegroundColor Red
    foreach ($f in $script:Failures) { Write-Host ("  - {0}" -f $f) -ForegroundColor Red }
    Write-Host ("RESULTADO: FALLO  ({0}/{1} correctas)" -f $script:Pass, $total) -ForegroundColor Red
    exit 1
}
Write-Host ("RESULTADO: OK  ({0} correctas)" -f $script:Pass) -ForegroundColor Green
exit 0
