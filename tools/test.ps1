<#
.SYNOPSIS
    Pruebas de integracion del Harness: install.ps1 y check.ps1 en un sandbox temporal.
    Auto-contenido (sin modulos externos); sale 0 (todo ok) o 1 (algun fallo).

.DESCRIPTION
    Levanta cada script como proceso hijo (-File) dentro de un directorio temporal,
    para no tocar el HOME ni proyectos reales, y verifica codigos de salida y
    efectos en disco (manifiesto, skills, respaldos, guard de schemaVersion...).

.EXAMPLE
    .\tools\test.ps1
    .\tools\test.ps1 -KeepSandbox
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

$script:Sandbox = Join-Path $env:TEMP ('harness-test-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
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
    Assert (Test-Path -LiteralPath (Join-Path $p1 'harness\AGENTS.md')) 'copia AGENTS.md'
    Assert (Test-Path -LiteralPath (Join-Path $p1 'harness\skills\dotnet\SKILL.md')) 'copia skill dotnet'
    Assert (Test-Path -LiteralPath (Join-Path $p1 'harness\skills\dotnet\.harness-source')) 'pone marcador .harness-source'
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
    Assert (-not (Test-Path -LiteralPath (Join-Path $p1 'harness\.harness-backup'))) '-Update sin cambios no respalda'

    # --- Conflicto y respaldo ------------------------------------------------
    Section 'install.ps1 -Update (skill editada -> respaldo)'
    $sk = Join-Path $p1 'harness\skills\dotnet\SKILL.md'
    Add-Content -LiteralPath $sk -Value "`n<!-- editado a mano -->"
    $r = Invoke-Script $Install @('-Project', $p1, '-Update', '-Source', $Repo)
    Assert ($r.Exit -eq 0) '-Update con conflicto sale 0'
    Assert (Test-Path -LiteralPath (Join-Path $p1 'harness\.harness-backup')) 'crea .harness-backup'
    $refH = (Get-FileHash -LiteralPath (Join-Path $Repo 'skills\dotnet\SKILL.md')).Hash
    $insH = (Get-FileHash -LiteralPath $sk).Hash
    Assert ($refH -eq $insH) 'refresca la skill al catalogo'

    # --- Deteccion -----------------------------------------------------------
    Section 'install.ps1 -Detect'
    $p3 = New-Project 'proj3'
    New-Item -ItemType Directory -Force -Path (Join-Path $p3 '.github\workflows'), (Join-Path $p3 'infra') | Out-Null
    Set-Content -LiteralPath (Join-Path $p3 'App.csproj') '<Project><ItemGroup><PackageReference Include="Npgsql" /></ItemGroup></Project>'
    Set-Content -LiteralPath (Join-Path $p3 'package.json') '{ "dependencies": { "@angular/core": "^21.0.0" } }'
    Set-Content -LiteralPath (Join-Path $p3 'Dockerfile') 'FROM alpine'
    Set-Content -LiteralPath (Join-Path $p3 'requirements.txt') 'fastapi'
    Set-Content -LiteralPath (Join-Path $p3 'infra\main.tf') 'provider "aws" {}'
    Set-Content -LiteralPath (Join-Path $p3 '.github\workflows\ci.yml') 'name: ci'
    $r = Invoke-Script $Install @('-Project', $p3, '-Detect', '-Source', $Repo)
    Assert ($r.Exit -eq 0) '-Detect sale 0'
    Assert ($r.Out -match 'angular') '-Detect detecta angular'
    Assert ($r.Out -match 'aws') '-Detect detecta aws'
    Assert ($r.Out -match 'sql') '-Detect detecta sql (.csproj Npgsql)'

    # --- Guard de schemaVersion ---------------------------------------------
    Section 'install.ps1 guard schemaVersion'
    $p4 = New-Project 'proj4'
    Set-Content -LiteralPath (Join-Path $p4 '.harness.json') '{ "schemaVersion": 2, "scope": "local", "rules": true, "skills": [ "dotnet" ], "harnessVersion": "9.9.9" }'
    $r = Invoke-Script $Install @('-Project', $p4, '-Update', '-Source', $Repo)
    Assert ($r.Exit -ne 0) '-Update aborta si schemaVersion es mas nuevo'
    $r = Invoke-Script $Install @('-Project', $p4, '-Doctor', '-Source', $Repo)
    Assert ($r.Exit -ne 0) '-Doctor falla si schemaVersion es mas nuevo'

    # --- Skill ajena protegida ----------------------------------------------
    Section 'install.ps1 protege skills ajenas'
    $pj = New-Project 'proj5'
    [void](Invoke-Script $Install @('-Project', $pj, '-Skills', 'dotnet,sql', '-Source', $Repo))
    $mine = Join-Path $pj 'harness\skills\mine'
    New-Item -ItemType Directory -Force -Path $mine | Out-Null
    Set-Content -LiteralPath (Join-Path $mine 'SKILL.md') 'propia'
    $r = Invoke-Script $Install @('-Project', $pj, '-Update', '-Source', $Repo)
    Assert ($r.Exit -eq 0) '-Update con skill ajena sale 0'
    Assert (Test-Path -LiteralPath (Join-Path $mine 'SKILL.md')) 'no poda la skill ajena'

    # --- SkillsOnly (sin reglas) --------------------------------------------
    Section 'install.ps1 -SkillsOnly (sin reglas)'
    $po = New-Project 'proj-skills-only'
    $r = Invoke-Script $Install @('-Project', $po, '-Skills', 'dotnet', '-SkillsOnly', '-Source', $Repo)
    Assert ($r.Exit -eq 0) '-SkillsOnly sale 0'
    Assert (Test-Path -LiteralPath (Join-Path $po 'harness\skills\dotnet\SKILL.md')) '-SkillsOnly instala la skill'
    Assert (-not (Test-Path -LiteralPath (Join-Path $po 'harness\AGENTS.md'))) '-SkillsOnly no copia AGENTS.md'
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
        Assert (@($co.skills.paths) -contains 'harness/skills') 'opencode.json conserva skills.paths'
    }
    else { Assert $false 'SkillsOnly crea opencode.json' }
    $r = Invoke-Script $Install @('-Project', $po, '-Doctor', '-Source', $Repo)
    Assert ($r.Exit -eq 0) '-Doctor de SkillsOnly sale 0'

    # --- Context (plantillas de memoria) ------------------------------------
    Section 'install.ps1 -Context (plantillas de memoria)'
    $pc = New-Project 'proj-context'
    $r = Invoke-Script $Install @('-Project', $pc, '-Skills', 'dotnet', '-Context', '-Source', $Repo)
    Assert ($r.Exit -eq 0) '-Context sale 0'
    Assert (Test-Path -LiteralPath (Join-Path $pc 'DEVELOPMENT.md')) '-Context copia DEVELOPMENT.md'
    Assert (Test-Path -LiteralPath (Join-Path $pc '.harness\session.md')) '-Context copia .harness/session.md'

    # --- check.ps1 -----------------------------------------------------------
    Section 'check.ps1'
    $r = Invoke-Script $Check @()
    Assert ($r.Exit -eq 0) 'check.ps1 sale 0'
    $r = Invoke-Script $Check @('-OverlapThreshold', '0.01', '-Strict')
    Assert ($r.Exit -ne 0) 'check.ps1 -Strict falla con umbral de solapamiento minimo'
    $r = Invoke-Script $Check @('-MaxAgeDays', '0')
    Assert ($r.Exit -ne 0) 'check.ps1 falla con MaxAgeDays 0 (frescura)'
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
