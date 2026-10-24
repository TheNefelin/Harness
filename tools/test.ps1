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

# $IsWindows solo existe en PS Core; en 5.1 (StrictMode) referenciarlo lanza, asi que se
# consulta con Get-Variable, que devuelve $null si no esta definida.
$isWinVar = Get-Variable -Name IsWindows -ErrorAction SilentlyContinue
$script:OnWindows = if ($null -ne $isWinVar) { [bool]$isWinVar.Value } else { $env:OS -eq 'Windows_NT' }
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
    param([string]$Script, [string[]]$Arguments, [hashtable]$Env)
    $all = @('-NoProfile')
    if ($script:OnWindows) { $all += @('-ExecutionPolicy', 'Bypass') }
    $all += @('-File', $Script)
    if ($Arguments) { $all += $Arguments }
    $eap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $saved = @{}
    if ($Env) { foreach ($k in $Env.Keys) { $saved[$k] = [System.Environment]::GetEnvironmentVariable($k); [System.Environment]::SetEnvironmentVariable($k, $Env[$k]) } }
    try { $out = & $script:Exe @all 2>&1 | Out-String }
    finally {
        if ($Env) { foreach ($k in $Env.Keys) { [System.Environment]::SetEnvironmentVariable($k, $saved[$k]) } }
        $ErrorActionPreference = $eap
    }
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

    # --- -Update tolera una skill RETIRADA del catalogo ----------------------
    Section 'install.ps1 -Update (skill retirada del catalogo: avisa, omite y poda)'
    $pr = New-Project 'proj-retirada'
    $r = Invoke-Script $Install @('-Project', $pr, '-Skills', 'dotnet,sql', '-Source', $Repo)
    Assert ($r.Exit -eq 0) 'instala dotnet,sql'
    # Simular que el catalogo retiro 'sql': editar el manifiesto para declararla junto a una
    # inexistente y comprobar que -Update no aborta en bloque (refresca el resto y la poda).
    $decl = Join-Path $pr '.harness.json'
    $txt = Get-Content -LiteralPath $decl -Raw
    $txt = $txt -replace '"sql"', '"sql","skill-inexistente"'
    Write-NoBom $decl $txt
    $r = Invoke-Script $Install @('-Project', $pr, '-Update', '-Source', $Repo)
    Assert ($r.Exit -eq 0) '-Update con skill retirada sale 0 (no aborta en bloque)'
    Assert ($r.Out -match 'ya no incluye') '-Update avisa de la skill retirada'
    Assert ($r.Out -match 'skill-inexistente') '-Update nombra la skill retirada'
    $m = Get-Content -LiteralPath $decl -Raw | ConvertFrom-Json
    Assert (@($m.skills) -notcontains 'skill-inexistente') '-Update poda la skill retirada del manifiesto'
    Assert (@($m.skills) -contains 'sql') '-Update conserva las skills que siguen existiendo'
    Assert (Test-Path -LiteralPath (Join-Path $pr 'harness/skills/dotnet')) '-Update deja el resto instalado'
    # Con -Skills explicito el mismo nombre inexistente debe FALLAR (typo).
    $r = Invoke-Script $Install @('-Project', $pr, '-Skills', 'skill-inexistente', '-Source', $Repo)
    Assert ($r.Exit -ne 0) '-Skills con nombre inexistente falla fuerte (typo)'
    Assert ($r.Out -match 'desconocidas') '-Skills inexistente avisa de skill desconocida'

    # --- .gitignore en UTF-8 sin BOM y con el salto de linea del archivo -----
    Section 'install.ps1 .gitignore (UTF-8 sin BOM, respeta el salto de linea)'
    $pgi = New-Project 'proj-gitignore'
    Write-NoBom (Join-Path $pgi '.gitignore') "# propio con tildes: configuracion`nnode_modules/`n"
    $r = Invoke-Script $Install @('-Project', $pgi, '-Skills', 'dotnet', '-Source', $Repo)
    Assert ($r.Exit -eq 0) 'instala con .gitignore preexistente'
    $gi = Join-Path $pgi '.gitignore'
    $giBytes = [System.IO.File]::ReadAllBytes($gi)
    Assert (-not ($giBytes[0] -eq 0xEF -and $giBytes[1] -eq 0xBB -and $giBytes[2] -eq 0xBF)) '.gitignore queda sin BOM'
    $giTxt = [System.IO.File]::ReadAllText($gi)
    Assert ($giTxt -match 'tildes: configuracion') '.gitignore conserva el contenido del usuario (tildes intactas)'
    Assert ($giTxt -match 'harness/skills/') '.gitignore recibe la entrada del Harness'
    Assert (-not ($giTxt -match "`r`n")) '.gitignore sin CRLF (LF)'
    Assert (-not $giTxt.StartsWith("`n")) '.gitignore sin linea en blanco inicial'
    # Sin .gitignore previo: no debe empezar con linea en blanco.
    $pgj = New-Project 'proj-gitignore-nuevo'
    $r = Invoke-Script $Install @('-Project', $pgj, '-Skills', 'dotnet', '-Source', $Repo)
    $giNuevo = [System.IO.File]::ReadAllText((Join-Path $pgj '.gitignore'))
    Assert (-not $giNuevo.StartsWith("`n")) '.gitignore nuevo sin linea en blanco inicial'
    Assert ($giNuevo.StartsWith('# Harness')) '.gitignore nuevo empieza por la cabecera'

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

    # --- Deteccion de Arduino (la skill existe en el catalogo) --------------
    Section 'install.ps1 -Detect (arduino)'
    $pa = New-Project 'proj-arduino'
    New-Item -ItemType Directory -Force -Path (Join-Path $pa 'sketch') | Out-Null
    Set-Content -LiteralPath (Join-Path $pa 'sketch/sketch.ino') 'void setup(){} void loop(){}'
    $r = Invoke-Script $Install @('-Project', $pa, '-Detect', '-Source', $Repo)
    Assert ($r.Exit -eq 0) '-Detect arduino sale 0'
    Assert ($r.Out -match 'arduino') '-Detect detecta arduino (.ino)'
    # platformio.ini tambien es senal de Arduino/PlatformIO
    $pp = New-Project 'proj-platformio'
    Set-Content -LiteralPath (Join-Path $pp 'platformio.ini') '[env:uno]'
    $r = Invoke-Script $Install @('-Project', $pp, '-Detect', '-Source', $Repo)
    Assert ($r.Out -match 'arduino') '-Detect detecta arduino (platformio.ini)'

    # --- Encoding: no corrompe los archivos del usuario ------------------------
    Section 'install.ps1 conserva el encoding de los archivos del usuario'
    # En Windows PowerShell 5.1, Get-Content -Raw sin -Encoding lee como ANSI: al
    # reescribir, una tilde se dobleaba (mojibake). El Harness debe releer en UTF-8.
    $pe = New-Project 'proj-encoding'
    $giText = "# modo depuraci" + [char]0x00F3 + "n (a" + [char]0x00F1 + ") " + [char]0x20AC + "`nbuild/`n"
    Write-NoBom (Join-Path $pe '.gitignore') $giText
    $r = Invoke-Script $Install @('-Project', $pe, '-Skills', 'arduino', '-Source', $Repo)
    Assert ($r.Exit -eq 0) 'instalacion con .gitignore acentuado sale 0'
    $giAfter = [System.IO.File]::ReadAllText((Join-Path $pe '.gitignore'), [System.Text.Encoding]::UTF8)
    Assert ($giAfter.StartsWith('# modo depuraci')) 'el .gitignore conserva el texto original'
    Assert ($giAfter -match ([char]0x00F3)) 'el .gitignore conserva la o acentuada'
    Assert ($giAfter -match ([char]0x00F1)) 'el .gitignore conserva la enye'
    Assert ($giAfter -match ([char]0x20AC)) 'el .gitignore conserva el simbolo euro'
    Assert ($giAfter -notmatch ([char]0x00C3)) 'el .gitignore no queda doblemente codificado'
    # opencode.json preexistente: se fusiona (se reescribe) y no debe corromperse
    $pe2 = New-Project 'proj-encoding-cfg'
    $cfgText = '{ "description": "proyecto con ' + [char]0x00F3 + ' y ' + [char]0x00F1 + '" }'
    Write-NoBom (Join-Path $pe2 'opencode.json') $cfgText
    $r = Invoke-Script $Install @('-Project', $pe2, '-Skills', 'arduino', '-Source', $Repo)
    Assert ($r.Exit -eq 0) 'instalacion con opencode.json preexistente sale 0'
    $cfgAfter = [System.IO.File]::ReadAllText((Join-Path $pe2 'opencode.json'), [System.Text.Encoding]::UTF8)
    Assert ($cfgAfter -match ([char]0x00F3)) 'el opencode.json conserva la o acentuada'
    Assert ($cfgAfter -match ([char]0x00F1)) 'el opencode.json conserva la enye'
    Assert ($cfgAfter -notmatch ([char]0x00C3)) 'el opencode.json no queda doblemente codificado'

    # --- Politica de Git obsoleta en un opencode.json existente ----------------
    # El instalador no pisa un opencode.json preexistente (no es suyo): si su bloque
    # de permisos es de una version anterior, la politica debil sigue vigente. Se
    # detecta y se avisa (instalacion y -Doctor), sin tocar el archivo del usuario.
    Section 'install.ps1 avisa si la politica de Git del opencode.json esta obsoleta'
    $oldPerms = '{ "permissions": [ { "action": "shell", "resource": "*", "effect": "ask" }, { "action": "shell", "resource": "git status*", "effect": "allow" }, { "action": "shell", "resource": "git commit*", "effect": "deny" } ] }'
    $pg = New-Project 'proj-git-policy'
    Write-NoBom (Join-Path $pg 'opencode.json') $oldPerms
    $r = Invoke-Script $Install @('-Project', $pg, '-Skills', 'arduino', '-Source', $Repo)
    Assert ($r.Exit -eq 0) 'instalacion sobre opencode.json preexistente sale 0'
    Assert ($r.Out -match 'politica de Git no es la lista blanca') 'la instalacion avisa de la politica de Git obsoleta'
    Assert ($r.Out -notmatch 'git \*: deny') 'la instalacion no declara la lista blanca por su cuenta'
    $r = Invoke-Script $Install @('-Project', $pg, '-Doctor', '-Source', $Repo)
    Assert ($r.Out -match 'politica de Git no es la lista blanca') '-Doctor avisa de la politica de Git obsoleta'
    # El opencode.json del usuario no se toca (sus permisos siguen siendo los suyos)
    $stillOld = Get-Content -LiteralPath (Join-Path $pg 'opencode.json') -Raw
    Assert ($stillOld -match 'git status\*') 'el opencode.json del usuario conserva sus permisos'
    # Con la politica del catalogo: sin aviso
    $pg2 = New-Project 'proj-git-policy-ok'
    $r = Invoke-Script $Install @('-Project', $pg2, '-Skills', 'arduino', '-Source', $Repo)
    Assert ($r.Exit -eq 0) 'instalacion con politica del catalogo sale 0'
    $r = Invoke-Script $Install @('-Project', $pg2, '-Doctor', '-Source', $Repo)
    Assert ($r.Out -notmatch 'politica de Git no es la lista blanca') '-Doctor no avisa con la politica del catalogo'
    Assert ($r.Out -match 'politica de Git en lista blanca') '-Doctor confirma la lista blanca'

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

    # Stub portable: en Windows un .cmd; en Linux/macOS un ejecutable con shebang.
    $stubName = if ($script:OnWindows) { 'opencode.cmd' } else { 'opencode' }
    $stubPath = Join-Path $ocStub $stubName
    function New-OpenCodeStub { param([string]$Version, [string]$Path)
        if ($script:OnWindows) { Write-NoBom $Path "@echo off`r`necho $Version`r`n" }
        else {
            Write-NoBom $Path "#!/bin/sh`necho $Version`n"
            & chmod +x $Path
        }
    }

    # (a) sin cliente: HARNESS_OPENCODE_BIN apunta a una ruta inexistente -> aviso, no fallo
    $noClient = Join-Path $script:Sandbox 'no-existe-opencode'
    $r = Invoke-Script $Install @('-Project', $pdOc, '-Doctor', '-Source', $Repo) @{ HARNESS_OPENCODE_BIN = $noClient }
    Assert ($r.Exit -eq 0) '-Doctor sin cliente openCode sale 0'
    Assert ($r.Out -match 'no encontrado') '-Doctor avisa si no encuentra el cliente'

    # (b) cliente V1 -> fallo (V1 rechaza el bloque V2)
    New-OpenCodeStub '1.18.19' $stubPath
    $r = Invoke-Script $Install @('-Project', $pdOc, '-Doctor', '-Source', $Repo) @{ HARNESS_OPENCODE_BIN = $stubPath }
    Assert ($r.Exit -ne 0) '-Doctor falla con cliente V1'
    Assert ($r.Out -match 'opencode V1') '-Doctor nombra el cliente V1'

    # (c) cliente V2 -> pasa
    New-OpenCodeStub '2.1.1' $stubPath
    $r = Invoke-Script $Install @('-Project', $pdOc, '-Doctor', '-Source', $Repo) @{ HARNESS_OPENCODE_BIN = $stubPath }
    Assert ($r.Exit -eq 0) '-Doctor pasa con cliente V2'
    Assert ($r.Out -match 'opencode V2') '-Doctor reconoce el cliente V2'

    # (d) CLI de la app de escritorio FUERA del PATH: se detecta (regresion del falso
    #     negativo: la app @opencodedesktop instala opencode-cli, no "opencode").
    #     Se aisan APPDATA/LOCALAPPDATA/USERPROFILE para que el cliente real de la
    #     maquina no contamine la prueba.
    $fakeHome = Join-Path $script:Sandbox 'fake-home'
    $cliDir = Join-Path $fakeHome 'ai.opencode.desktop/cli/9.9.9-x64'
    New-Item -ItemType Directory -Force -Path $cliDir | Out-Null
    $desktopStubName = if ($script:OnWindows) { 'opencode-cli.cmd' } else { 'opencode-cli' }
    $desktopStub = Join-Path $cliDir $desktopStubName
    New-OpenCodeStub '2.4.0' $desktopStub
    $r = Invoke-Script $Install @('-Project', $pdOc, '-Doctor', '-Source', $Repo) @{ APPDATA = $fakeHome; LOCALAPPDATA = $fakeHome; USERPROFILE = $fakeHome }
    Assert ($r.Exit -eq 0) '-Doctor pasa con la CLI de la app de escritorio'
    Assert ($r.Out -match 'opencode V2 \(2\.4\.0\)') '-Doctor detecta la CLI de la app sin estar en PATH'

    # (e) el cliente se busca tambien por el nombre 'opencode-cli' en el PATH
    $ocStub2 = Join-Path $script:Sandbox 'oc-stub2'
    New-Item -ItemType Directory -Force -Path $ocStub2 | Out-Null
    $stub2Name = if ($script:OnWindows) { 'opencode-cli.cmd' } else { 'opencode-cli' }
    $stub2 = Join-Path $ocStub2 $stub2Name
    New-OpenCodeStub '2.5.0' $stub2
    $savedPath2 = $env:PATH
    try {
        # Se limpian del PATH las entradas que contengan 'opencode': si la maquina tuviera
        # un 'opencode' real en el PATH, ganaria por orden y la prueba no seria hermetica.
        $sep = [System.IO.Path]::PathSeparator
        $clean = (@($savedPath2 -split [regex]::Escape($sep)) | Where-Object { $_ -notmatch 'opencode' }) -join $sep
        $env:PATH = $ocStub2 + $sep + $clean
        $r = Invoke-Script $Install @('-Project', $pdOc, '-Doctor', '-Source', $Repo) @{ APPDATA = $fakeHome; LOCALAPPDATA = $fakeHome; USERPROFILE = $fakeHome }
        Assert ($r.Out -match 'opencode V2 \(2\.5\.0\)') '-Doctor encuentra opencode-cli en el PATH'
    }
    finally { $env:PATH = $savedPath2 }

    # --- Doctor: audita la memoria del proyecto (Local) ----------------------
    Section 'install.ps1 -Doctor (audita la memoria)'
    # (a) instalacion sin -Context: falta la memoria -> avisa (no falla)
    $pdMem = New-Project 'proj-doctor-mem-missing'
    $r = Invoke-Script $Install @('-Project', $pdMem, '-Skills', 'dotnet', '-Source', $Repo)
    Assert ($r.Exit -eq 0) 'instalacion sin -Context sale 0'
    $r = Invoke-Script $Install @('-Project', $pdMem, '-Doctor', '-Source', $Repo)
    Assert ($r.Exit -eq 0) '-Doctor sin memoria sale 0 (aviso, no fallo)'
    Assert ($r.Out -match 'memoria incompleta') '-Doctor avisa de memoria incompleta'
    Assert ($r.Out -match 'README.md') '-Doctor nombra el archivo de memoria ausente'
    # (b) instalacion con -Context: memoria completa -> OK
    $pdMem2 = New-Project 'proj-doctor-mem-ok'
    $r = Invoke-Script $Install @('-Project', $pdMem2, '-Skills', 'dotnet', '-Context', '-Source', $Repo)
    Assert ($r.Exit -eq 0) 'instalacion con -Context sale 0'
    $r = Invoke-Script $Install @('-Project', $pdMem2, '-Doctor', '-Source', $Repo)
    Assert ($r.Exit -eq 0) '-Doctor con memoria completa sale 0'
    Assert ($r.Out -match 'memoria presente') '-Doctor confirma la memoria presente'
    Assert ($r.Out -match 'checkpoint de sesion presente') '-Doctor informa del checkpoint'
    # (c) README vacio: lo avisa explicitamente
    $pdMem3 = New-Project 'proj-doctor-mem-empty'
    $r = Invoke-Script $Install @('-Project', $pdMem3, '-Skills', 'dotnet', '-Context', '-Source', $Repo)
    Write-NoBom (Join-Path $pdMem3 'README.md') '   '
    $r = Invoke-Script $Install @('-Project', $pdMem3, '-Doctor', '-Source', $Repo)
    Assert ($r.Exit -eq 0) '-Doctor con README vacio sale 0'
    Assert ($r.Out -match 'esta vacio') '-Doctor avisa del .md vacio'

    # --- Uninstall -----------------------------------------------------------
    Section 'install.ps1 -Uninstall (borra solo lo gestionado)'
    $pu = New-Project 'proj-uninstall'
    Write-NoBom (Join-Path $pu 'LaserBoy.md') "# Doc propio`r`ncontenido`r`n"
    Write-NoBom (Join-Path $pu 'DEVELOPMENT.md') ''
    $r = Invoke-Script $Install @('-Project', $pu, '-Skills', 'dotnet', '-Context', '-Source', $Repo)
    Assert ($r.Exit -eq 0) 'instalacion para -Uninstall sale 0'
    # El usuario escribe en la memoria sembrada (simula avance)
    Write-NoBom (Join-Path $pu 'DEVELOPMENT.md') "# Desarrollo`r`n`r`nmi avance`r`n"
    $declPu = Get-Content -LiteralPath (Join-Path $pu '.harness.json') -Raw | ConvertFrom-Json
    Assert ($declPu.created.'opencode.json' -eq $true) 'manifiesto registra created.opencode.json=true'
    # -WhatIf no borra nada
    $r = Invoke-Script $Install @('-Project', $pu, '-Uninstall', '-WhatIf', '-Source', $Repo)
    Assert ($r.Exit -eq 0) '-Uninstall -WhatIf sale 0'
    Assert (Test-Path -LiteralPath (Join-Path $pu 'harness/skills/dotnet')) '-Uninstall -WhatIf no toca las skills'
    Assert ($r.Out -match 'WHATIF') '-Uninstall -WhatIf informa simulacion'
    # Desinstalacion real
    $r = Invoke-Script $Install @('-Project', $pu, '-Uninstall', '-Source', $Repo)
    Assert ($r.Exit -eq 0) '-Uninstall sale 0'
    Assert (-not (Test-Path -LiteralPath (Join-Path $pu 'harness/skills/dotnet'))) '-Uninstall retira la skill gestionada'
    # NADA se destruye: lo gestionado va a .harness-backup (skill + reglas)
    Assert (Test-Path -LiteralPath (Join-Path $pu 'harness/.harness-backup')) '-Uninstall CONSERVA .harness-backup (respaldos)'
    Assert (@(Get-ChildItem -LiteralPath (Join-Path $pu 'harness/.harness-backup') -Force -Directory -Filter 'dotnet-*').Count -ge 1) '-Uninstall respalda la skill gestionada en vez de borrarla'
    Assert (@(Get-ChildItem -LiteralPath (Join-Path $pu 'harness/.harness-backup') -Force -File -Filter 'AGENTS.md-*').Count -ge 1) '-Uninstall respalda las reglas gestionadas'
    Assert (Test-Path -LiteralPath (Join-Path $pu 'harness')) '-Uninstall CONSERVA harness/ (quedan respaldos)'
    Assert (-not (Test-Path -LiteralPath (Join-Path $pu '.harness.json'))) '-Uninstall borra .harness.json'
    Assert (-not (Test-Path -LiteralPath (Join-Path $pu '.harness/session.md'))) '-Uninstall borra .harness/session.md'
    Assert (-not (Test-Path -LiteralPath (Join-Path $pu 'opencode.json'))) '-Uninstall borra opencode.json creado por el Harness'
    # El .gitignore CONSERVA harness/.harness-backup/ porque quedan respaldos (evita no-rastreados)
    Assert (Test-Path -LiteralPath (Join-Path $pu '.gitignore')) '-Uninstall conserva .gitignore mientras queden respaldos'
    $giAfter = Get-Content -LiteralPath (Join-Path $pu '.gitignore') -Raw
    Assert ($giAfter -match 'harness/\.harness-backup/') '-Uninstall conserva la linea harness/.harness-backup/ si quedan respaldos'
    Assert (-not ($giAfter -match 'harness/skills/')) '-Uninstall quita la linea harness/skills/ del .gitignore'
    Assert ($r.Out -match 'respaldo') '-Uninstall avisa de que quedan respaldos'
    Assert (Test-Path -LiteralPath (Join-Path $pu 'LaserBoy.md')) '-Uninstall respeta el codigo/doc del usuario'
    Assert (Test-Path -LiteralPath (Join-Path $pu 'DEVELOPMENT.md')) '-Uninstall respeta DEVELOPMENT.md'
    Assert ((Get-Content -LiteralPath (Join-Path $pu 'DEVELOPMENT.md') -Raw) -match 'mi avance') '-Uninstall conserva el avance del usuario en DEVELOPMENT.md'

    # -Uninstall NO borra archivos ajenos dentro de harness/ ni skills ajenas
    $puA = New-Project 'proj-uninstall-ajenas'
    $r = Invoke-Script $Install @('-Project', $puA, '-Skills', 'dotnet', '-Source', $Repo)
    Assert ($r.Exit -eq 0) 'instalacion con contenido ajeno sale 0'
    # Contenido propio del usuario dentro de harness/
    Write-NoBom (Join-Path $puA 'harness/mi-nota.md') 'nota del usuario'
    New-Item -ItemType Directory -Force -Path (Join-Path $puA 'harness/skills/mi-skill-ajena') | Out-Null
    Write-NoBom (Join-Path $puA 'harness/skills/mi-skill-ajena/SKILL.md') '# skill ajena sin marcador'
    $r = Invoke-Script $Install @('-Project', $puA, '-Uninstall', '-Source', $Repo)
    Assert ($r.Exit -eq 0) '-Uninstall con contenido ajeno sale 0'
    Assert (Test-Path -LiteralPath (Join-Path $puA 'harness/mi-nota.md')) '-Uninstall conserva archivos ajenos en harness/'
    Assert (Test-Path -LiteralPath (Join-Path $puA 'harness/skills/mi-skill-ajena')) '-Uninstall conserva skills ajenas (sin marcador)'
    Assert (-not (Test-Path -LiteralPath (Join-Path $puA 'harness/skills/dotnet'))) '-Uninstall retira solo la skill gestionada'
    Assert ($r.Out -match 'ajena') '-Uninstall informa de lo que conserva por ajeno'

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
    Assert (-not ($cfgKept.PSObject.Properties.Name -contains 'instructions')) '-Uninstall quita el instructions que ANADIO el Harness'
    $giKept = Get-Content -LiteralPath (Join-Path $pu2 '.gitignore') -Raw
    Assert ($giKept -match 'node_modules') '-Uninstall conserva las reglas propias de .gitignore'
    Assert (-not ($giKept -match 'harness/skills')) '-Uninstall quita el bloque Harness del .gitignore'

    # -Uninstall NO quita un instructions que ya existia antes de instalar (no consta como propio)
    $puI = New-Project 'proj-uninstall-instr-previo'
    Write-NoBom (Join-Path $puI 'opencode.json') "{`n  `"instructions`": [`"harness/AGENTS.md`"]`n}`n"
    $r = Invoke-Script $Install @('-Project', $puI, '-Skills', 'dotnet', '-Source', $Repo)
    Assert ($r.Exit -eq 0) 'instalacion con instructions previo sale 0'
    $declI = Get-Content -LiteralPath (Join-Path $puI '.harness.json') -Raw | ConvertFrom-Json
    Assert ($declI.created.instructions -eq $false) 'manifiesto: instructions NO lo anadio el Harness'
    $r = Invoke-Script $Install @('-Project', $puI, '-Uninstall', '-Source', $Repo)
    Assert ($r.Exit -eq 0) '-Uninstall con instructions previo sale 0'
    $cfgI = Get-Content -LiteralPath (Join-Path $puI 'opencode.json') -Raw | ConvertFrom-Json
    Assert (@($cfgI.instructions) -contains 'harness/AGENTS.md') '-Uninstall CONSERVA un instructions que no anadio el Harness'

    # -Uninstall sin manifiesto: aviso, no error
    $pu3 = New-Project 'proj-uninstall-none'
    $r = Invoke-Script $Install @('-Project', $pu3, '-Uninstall', '-Source', $Repo)
    Assert ($r.Exit -eq 0) '-Uninstall sin instalacion sale 0 (aviso)'
    Assert ($r.Out -match 'nada que desinstalar') '-Uninstall sin manifiesto avisa'

    # -Uninstall: no borra la config ajena del proyecto (opencode.json ajeno intacto)
    Section 'install.ps1 -Uninstall (config ajena intacta)'
    $pUn = New-Project 'proj-uninstall-ajena'
    Write-NoBom (Join-Path $pUn 'opencode.json') "{`n  `"model`": `"config-propia`"`n}`n"
    New-Item -ItemType Directory -Force -Path (Join-Path $pUn 'harness/otro') | Out-Null
    $r = Invoke-Script $Install @('-Project', $pUn, '-Skills', 'dotnet', '-Source', $Repo)
    Assert ($r.Exit -eq 0) 'instalacion sobre config ajena sale 0'
    Assert (Test-Path -LiteralPath (Join-Path $pUn 'harness/skills/dotnet')) 'instala la skill gestionada'
    Assert (Test-Path -LiteralPath (Join-Path $pUn '.harness.json')) 'escribe .harness.json'
    $r = Invoke-Script $Install @('-Project', $pUn, '-Uninstall', '-Source', $Repo)
    Assert ($r.Exit -eq 0) '-Uninstall sale 0'
    Assert (Test-Path -LiteralPath (Join-Path $pUn 'opencode.json')) '-Uninstall CONSERVA opencode.json ajeno'
    Assert ((Get-Content -LiteralPath (Join-Path $pUn 'opencode.json') -Raw) -match 'config-propia') '-Uninstall no altera el contenido ajeno'
    Assert (-not (Test-Path -LiteralPath (Join-Path $pUn 'harness/skills/dotnet'))) '-Uninstall retira la skill gestionada'
    Assert (-not (Test-Path -LiteralPath (Join-Path $pUn '.harness.json'))) '-Uninstall borra .harness.json'

    # -Force con AGENTS.md ajeno: el ajeno acaba en RESPALDO (recuperable), nunca se pierde.
    Section 'install.ps1 -Force con AGENTS.md ajeno (va a respaldo, no se pierde)'
    $pF = New-Project 'proj-force-agents'
    New-Item -ItemType Directory -Force -Path (Join-Path $pF 'harness') | Out-Null
    Write-NoBom (Join-Path $pF 'harness/AGENTS.md') "# Reglas propias del usuario`ncontenido unico del usuario`n"
    $r = Invoke-Script $Install @('-Project', $pF, '-Skills', 'dotnet', '-Force', '-Source', $Repo)
    Assert ($r.Exit -eq 0) '-Force sobre AGENTS.md ajeno sale 0'
    $bkAgents = @(Get-ChildItem -LiteralPath (Join-Path $pF 'harness/.harness-backup') -Force -File -Filter 'AGENTS.md-*' -ErrorAction SilentlyContinue)
    Assert ($bkAgents.Count -ge 1) '-Force respalda el AGENTS.md ajeno antes de reemplazarlo'
    $bkContent = ($bkAgents | Select-Object -First 1 | ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw })
    Assert ($bkContent -match 'contenido unico del usuario') 'el respaldo conserva el contenido ajeno integro'
    $r = Invoke-Script $Install @('-Project', $pF, '-Uninstall', '-Source', $Repo)
    Assert ($r.Exit -eq 0) '-Uninstall tras -Force sale 0'
    Assert (Test-Path -LiteralPath (Join-Path $pF 'harness/.harness-backup')) '-Uninstall CONSERVA el respaldo del AGENTS.md ajeno'
    $bkAfter = @(Get-ChildItem -LiteralPath (Join-Path $pF 'harness/.harness-backup') -Force -File -Filter 'AGENTS.md-*' -ErrorAction SilentlyContinue)
    Assert (@($bkAfter | Where-Object { (Get-Content -LiteralPath $_.FullName -Raw) -match 'contenido unico del usuario' }).Count -ge 1) 'el AGENTS.md ajeno sigue recuperable tras desinstalar'
    # Dos respaldos del MISMO nombre en el mismo segundo no deben colisionar ni abortar
    Assert ($bkAfter.Count -ge 2) 'dos respaldos de AGENTS.md conviven (sin colision de sello)'
    Assert ($r.Out -match 'Harness desinstalado') '-Uninstall no aborta aunque haya dos AGENTS.md respaldados'

    # --- Targets: punteros para otros clientes -------------------------------
    Section 'install.ps1 -Target (punteros para codex, cursor y cline)'
    $pt = New-Project 'proj-targets'
    $r = Invoke-Script $Install @('-Project', $pt, '-Skills', 'dotnet', '-Target', 'codex,cursor,cline', '-Source', $Repo)
    Assert ($r.Exit -eq 0) '-Target codex,cursor,cline sale 0'
    Assert (Test-Path -LiteralPath (Join-Path $pt 'AGENTS.md')) 'codex: crea AGENTS.md en la raiz'
    Assert (Test-Path -LiteralPath (Join-Path $pt '.cursor/rules/harness.mdc')) 'cursor: crea la regla .mdc'
    Assert (Test-Path -LiteralPath (Join-Path $pt '.clinerules/harness.md')) 'cline: crea la regla'
    Assert (-not (Test-Path -LiteralPath (Join-Path $pt 'opencode.json'))) 'targets de puntero: no crea opencode.json'
    Assert (Test-Path -LiteralPath (Join-Path $pt 'harness/AGENTS.md')) 'targets de puntero: instalan la fuente harness/AGENTS.md'
    $mt = Get-Content -LiteralPath (Join-Path $pt '.harness.json') -Raw | ConvertFrom-Json
    Assert ((@($mt.targets) -join ',') -eq 'codex,cursor,cline') 'manifest declara los targets instalados'
    $mdc = Get-Content -LiteralPath (Join-Path $pt '.cursor/rules/harness.mdc') -Raw
    Assert ($mdc -match 'alwaysApply: true') 'cursor: la regla se aplica siempre'
    Assert ($mdc -match 'harness/AGENTS\.md') 'cursor: el puntero remite a la fuente unica'
    $r = Invoke-Script $Install @('-Project', $pt, '-Doctor', '-Source', $Repo)
    Assert ($r.Exit -eq 0) '-Doctor de los targets sale 0'
    Assert ($r.Out -match 'codex: puntero al dia') '-Doctor valida el puntero de codex'
    # -Update sin -Target recuerda los targets del manifiesto
    $r = Invoke-Script $Install @('-Project', $pt, '-Update', '-Source', $Repo)
    Assert ($r.Exit -eq 0) '-Update sin -Target sale 0'
    Assert ($r.Out -match '\.cursor/rules/harness\.mdc') '-Update refresca los punteros declarados'
    # Un puntero ajeno no se pisa sin -Force
    $pc = New-Project 'proj-codex-ajeno'
    Write-NoBom (Join-Path $pc 'AGENTS.md') "# reglas propias`n"
    $r = Invoke-Script $Install @('-Project', $pc, '-Skills', 'dotnet', '-Target', 'codex', '-Source', $Repo)
    Assert ($r.Exit -eq 0) 'instalar sobre AGENTS.md ajeno sale 0 (omite, no falla)'
    Assert ((Get-Content -LiteralPath (Join-Path $pc 'AGENTS.md') -Raw) -match 'reglas propias') 'no pisa el AGENTS.md ajeno sin -Force'
    Assert ($r.Out -match 'ya existe \(ajeno') 'avisa de que el puntero es ajeno'
    $r = Invoke-Script $Install @('-Project', $pc, '-Skills', 'dotnet', '-Target', 'codex', '-Force', '-Source', $Repo)
    Assert ($r.Exit -eq 0) 'instalar sobre AGENTS.md ajeno con -Force sale 0'
    Assert (Test-Path -LiteralPath (Join-Path $pc 'harness/.harness-backup')) '-Force respalda el AGENTS.md ajeno'
    # Validaciones de -Target
    $r = Invoke-Script $Install @('-Project', (New-Project 'proj-target-malo'), '-Skills', 'dotnet', '-Target', 'vim', '-Source', $Repo)
    Assert ($r.Exit -ne 0) 'un target desconocido falla'
    Assert ($r.Out -match 'Targets desconocidos') 'el error nombra los targets validos'
    $r = Invoke-Script $Install @('-Project', (New-Project 'proj-target-skillsonly'), '-Skills', 'dotnet', '-Target', 'cline', '-SkillsOnly', '-Source', $Repo)
    Assert ($r.Exit -ne 0) '-SkillsOnly con un target de puntero falla'
    Assert ($r.Out -match 'las necesitan') '-SkillsOnly explica por que no vale con punteros'
    # -Uninstall conserva un puntero editado por el usuario
    $pe = New-Project 'proj-pointer-editado'
    $r = Invoke-Script $Install @('-Project', $pe, '-Skills', 'dotnet', '-Target', 'cursor', '-Source', $Repo)
    Assert ($r.Exit -eq 0) 'instalacion con -Target cursor sale 0'
    Write-NoBom (Join-Path $pe '.cursor/rules/harness.mdc') "# regla propia`n"
    $r = Invoke-Script $Install @('-Project', $pe, '-Uninstall', '-Source', $Repo)
    Assert ($r.Exit -eq 0) '-Uninstall con puntero editado sale 0'
    Assert (Test-Path -LiteralPath (Join-Path $pe '.cursor/rules/harness.mdc')) '-Uninstall CONSERVA el puntero editado'
    Assert ($r.Out -match 'KEEP   puntero') '-Uninstall avisa del puntero conservado'

    # -Source: un catalogo incompleto falla CLARO y ANTES de desplegar (no a mitad)
    Section 'install.ps1 -Source (catalogo incompleto falla temprano)'
    $srcBad = New-Project 'catalogo-incompleto'
    New-Item -ItemType Directory -Force -Path (Join-Path $srcBad 'skills/dotnet') | Out-Null
    Write-NoBom (Join-Path $srcBad 'skills/dotnet/SKILL.md') "---`nname: dotnet`ndescription: `"Demo`"`n---`n`n# dotnet`n"
    $pBad = New-Project 'proj-source-incompleto'
    $r = Invoke-Script $Install @('-Project', $pBad, '-Skills', 'dotnet', '-Source', $srcBad)
    Assert ($r.Exit -ne 0) '-Source con catalogo incompleto falla'
    Assert ($r.Out -match 'no parece un catalogo Harness') '-Source avisa que no es un catalogo Harness'
    Assert ($r.Out -match 'AGENTS.md') '-Source nombra la pieza que falta'
    Assert (-not (Test-Path -LiteralPath (Join-Path $pBad 'harness/skills/dotnet'))) '-Source no despliega nada antes de fallar'
    Assert (-not (Test-Path -LiteralPath (Join-Path $pBad '.harness.json'))) '-Source no deja manifiesto a medias'

    # -Source: falta una plantilla concreta -> tambien falla temprano
    $srcBad2 = New-Project 'catalogo-sin-plantilla'
    New-Item -ItemType Directory -Force -Path (Join-Path $srcBad2 'skills/dotnet'), (Join-Path $srcBad2 'templates') | Out-Null
    Write-NoBom (Join-Path $srcBad2 'skills/dotnet/SKILL.md') "---`nname: dotnet`ndescription: `"Demo`"`n---`n`n# dotnet`n"
    Write-NoBom (Join-Path $srcBad2 'AGENTS.md') '# Reglas'
    Write-NoBom (Join-Path $srcBad2 'templates/opencode.json') '{}'
    Write-NoBom (Join-Path $srcBad2 'templates/opencode.skills-only.json') '{}'
    $r = Invoke-Script $Install @('-Project', (New-Project 'proj-source-sin-tpl'), '-Skills', 'dotnet', '-Source', $srcBad2)
    Assert ($r.Exit -ne 0) '-Source sin una plantilla obligatoria falla'
    Assert ($r.Out -match 'targets/codex-AGENTS\.md') '-Source nombra la plantilla que falta'

    # Scope global eliminado: -Global y -Scope Global fallan con el motivo, sin escribir nada.
    Section 'install.ps1 -Global (scope global eliminado)'
    $pG = New-Project 'proj-global-rechazado'
    $r = Invoke-Script $Install @('-Project', $pG, '-Global', '-Skills', 'dotnet', '-Source', $Repo)
    Assert ($r.Exit -ne 0) '-Global falla'
    Assert ($r.Out -match 'scope global ya no existe') '-Global explica que el scope global se elimino'
    Assert (-not (Test-Path -LiteralPath (Join-Path $pG 'harness'))) '-Global no escribe nada'
    Assert (-not (Test-Path -LiteralPath (Join-Path $pG '.harness.json'))) '-Global no deja manifiesto'
    $r = Invoke-Script $Install @('-Project', $pG, '-Scope', 'Global', '-Skills', 'dotnet', '-Source', $Repo)
    Assert ($r.Exit -ne 0) '-Scope Global falla'
    Assert ($r.Out -match 'scope global ya no existe') '-Scope Global explica el motivo'

    # --- -Adopt: informe de solo lectura (no escribe NADA) -------------------
    Section 'install.ps1 -Adopt (informe de alineacion con plantillas; solo lectura)'
    $pa = New-Project 'proj-adopt'
    # Un .md identico a la plantilla y otro que se aparta del estandar.
    Copy-Item -LiteralPath (Join-Path $Repo 'templates/README.md') -Destination (Join-Path $pa 'README.md')
    Write-NoBom (Join-Path $pa 'DEVELOPMENT.md') "# Desarrollo propio`n`nSin seguir el estandar.`n"
    $before = (Get-ChildItem -LiteralPath $pa -Recurse -File | ForEach-Object { (Get-FileHash -LiteralPath $_.FullName).Hash } | Sort-Object) -join ','
    $r = Invoke-Script $Install @('-Project', $pa, '-Adopt', '-Source', $Repo)
    Assert ($r.Exit -eq 0) '-Adopt sale 0 (es informativo, no falla)'
    Assert ($r.Out -match 'SOLO LECTURA') '-Adopt se declara de solo lectura'
    Assert ($r.Out -match 'identico a la plantilla') '-Adopt marca el archivo ya alineado'
    Assert ($r.Out -match 'DIFF') '-Adopt reporta el que se aparta'
    Assert ($r.Out -match 'Desarrollo propio') '-Adopt muestra la linea del proyecto (-)'
    Assert ($r.Out -match 'Sin seguir el estandar') '-Adopt muestra la linea del proyecto en el diff'
    Assert ($r.Out -match 'FALTA') '-Adopt reporta el .md ausente (SKILL.md)'
    $after = (Get-ChildItem -LiteralPath $pa -Recurse -File | ForEach-Object { (Get-FileHash -LiteralPath $_.FullName).Hash } | Sort-Object) -join ','
    Assert ($before -eq $after) '-Adopt NO modifica ningun archivo (hashes identicos)'
    Assert (-not (Test-Path -LiteralPath (Join-Path $pa 'harness'))) '-Adopt no despliega harness/'
    Assert (-not (Test-Path -LiteralPath (Join-Path $pa '.harness.json'))) '-Adopt no escribe manifiesto'

    # -Adopt con todo alineado: no hay diferencias.
    $pa2 = New-Project 'proj-adopt-ok'
    foreach ($f in @('README.md', 'DEVELOPMENT.md', 'SKILL.md')) { Copy-Item -LiteralPath (Join-Path $Repo ('templates/' + $f)) -Destination (Join-Path $pa2 $f) }
    $r = Invoke-Script $Install @('-Project', $pa2, '-Adopt', '-Source', $Repo)
    Assert ($r.Exit -eq 0) '-Adopt alineado sale 0'
    Assert ($r.Out -match 'ya siguen las plantillas') '-Adopt confirma cuando todo esta alineado'
    Assert (-not ($r.Out -match 'DIFF')) '-Adopt no reporta DIFF si todo esta alineado'

    # -Adopt con archivo grande: no cuelga; usa el diff por posicion (umbral LCS).
    $pa3 = New-Project 'proj-adopt-grande'
    Write-NoBom (Join-Path $pa3 'DEVELOPMENT.md') ((1..2000 | ForEach-Object { "linea $_" }) -join "`n")
    $r = Invoke-Script $Install @('-Project', $pa3, '-Adopt', '-Source', $Repo)
    Assert ($r.Exit -eq 0) '-Adopt con archivo grande sale 0 (no cuelga)'
    Assert ($r.Out -match 'archivo grande: diff por posicion') '-Adopt avisa que uso el diff por posicion'

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
    Write-NoBom (Join-Path $fa 'evals/triggers.json') '[]'
    Write-NoBom (Join-Path $fa 'skills/demo/SKILL.md') "---`nname: demo`ndescription: `"Demo para pruebas`"`n---`n`n# Demo`n`nVer references/a.md para el detalle.`n"
    Write-NoBom (Join-Path $fa 'skills/demo/references/a.md') "# A`n`nVer references/sub/b.md.`n"
    Write-NoBom (Join-Path $fa 'skills/demo/references/sub/b.md') "# B`n`nContenido.`n"
    $r = Invoke-Script (Join-Path $fa 'tools/check.ps1') @()
    Assert ($r.Exit -eq 0) 'check pasa con referencias citadas (incl. anidada)'

    $fb = New-Project 'chk-refs-orphan'
    New-Item -ItemType Directory -Force -Path (Join-Path $fb 'tools'), (Join-Path $fb 'evals'), (Join-Path $fb 'skills/demo/references') | Out-Null
    Copy-Item -LiteralPath $Check -Destination (Join-Path $fb 'tools/check.ps1')
    Write-NoBom (Join-Path $fb 'evals/triggers.json') '[]'
    Write-NoBom (Join-Path $fb 'skills/demo/SKILL.md') "---`nname: demo`ndescription: `"Demo para pruebas`"`n---`n`n# Demo`n"
    Write-NoBom (Join-Path $fb 'skills/demo/references/orphan.md') "# Huerfana`n"
    $r = Invoke-Script (Join-Path $fb 'tools/check.ps1') @()
    Assert ($r.Exit -ne 0) 'check falla con referencia no citada'
    Assert ($r.Out -match 'orphan') 'check nombra la referencia huerfana'

    # --- check.ps1: encoding (UTF-8 sin BOM, LF; .ps1 ASCII) ----------------
    Section 'check.ps1 encoding (UTF-8 sin BOM, LF; .ps1 en ASCII)'
    function New-EncRoot {
        param([string]$Name)
        $root = New-Project $Name
        New-Item -ItemType Directory -Force -Path (Join-Path $root 'tools'), (Join-Path $root 'evals'), (Join-Path $root 'skills/demo') | Out-Null
        Copy-Item -LiteralPath $Check -Destination (Join-Path $root 'tools/check.ps1')
        Write-NoBom (Join-Path $root 'evals/triggers.json') '[]'
        Write-NoBom (Join-Path $root 'skills/demo/SKILL.md') "---`nname: demo`ndescription: `"Demo`"`n---`n`n# Demo`n"
        return $root
    }
    # (a) todo en regla -> pasa
    $encOk = New-EncRoot 'chk-enc-ok'
    Write-NoBom (Join-Path $encOk 'README.md') "# Titulo con tildes: configuracion`n"
    $r = Invoke-Script (Join-Path $encOk 'tools/check.ps1') @()
    Assert ($r.Exit -eq 0) 'check pasa con encoding correcto (UTF-8 sin BOM, LF)'
    Assert ($r.Out -match 'Encoding') 'check reporta la seccion de encoding'
    # (b) .ps1 con byte no-ASCII -> falla
    $encPs = New-EncRoot 'chk-enc-ps1'
    [System.IO.File]::WriteAllBytes((Join-Path $encPs 'tools/malo.ps1'), [byte[]](0x23, 0xC3, 0xB1, 0x0A))
    $r = Invoke-Script (Join-Path $encPs 'tools/check.ps1') @()
    Assert ($r.Exit -ne 0) 'check falla con .ps1 no-ASCII'
    Assert ($r.Out -match 'no-ASCII') 'check nombra el byte no-ASCII'
    # (c) .md con BOM -> falla
    $encBom = New-EncRoot 'chk-enc-bom'
    [System.IO.File]::WriteAllBytes((Join-Path $encBom 'README.md'), [byte[]](0xEF, 0xBB, 0xBF, 0x23, 0x0A))
    $r = Invoke-Script (Join-Path $encBom 'tools/check.ps1') @()
    Assert ($r.Exit -ne 0) 'check falla con BOM'
    Assert ($r.Out -match 'BOM') 'check nombra el BOM'
    # (d) .md con CRLF -> falla
    $encCrlf = New-EncRoot 'chk-enc-crlf'
    [System.IO.File]::WriteAllBytes((Join-Path $encCrlf 'README.md'), [byte[]](0x23, 0x0D, 0x0A))
    $r = Invoke-Script (Join-Path $encCrlf 'tools/check.ps1') @()
    Assert ($r.Exit -ne 0) 'check falla con CRLF'
    Assert ($r.Out -match 'CRLF') 'check nombra el CRLF'
    # (e) .md con no-ASCII (tildes legitimas) -> pasa (solo .ps1 debe ser ASCII)
    $encMd = New-EncRoot 'chk-enc-md'
    [System.IO.File]::WriteAllBytes((Join-Path $encMd 'README.md'), [byte[]](0x23, 0x20, 0xC3, 0xB1, 0x0A))
    $r = Invoke-Script (Join-Path $encMd 'tools/check.ps1') @()
    Assert ($r.Exit -eq 0) 'check acepta no-ASCII en .md (regla: UTF-8, no ASCII)'

    # --- check.ps1: inventario declarado vs catalogo real -------------------
    Section 'check.ps1 inventario (conteo declarado == catalogo real)'
    # (a) README declara el conteo correcto (1 skill, en negrita) -> pasa
    $invOk = New-EncRoot 'chk-inv-ok'
    Write-NoBom (Join-Path $invOk 'README.md') "# Demo`n`nTiene **1 skills**.`n"
    $r = Invoke-Script (Join-Path $invOk 'tools/check.ps1') @()
    Assert ($r.Exit -eq 0) 'check pasa si el conteo declarado coincide'
    Assert ($r.Out -match 'Inventario') 'check reporta la seccion de inventario'
    # (b) README declara un conteo distinto al real -> falla
    $invBad = New-EncRoot 'chk-inv-bad'
    Write-NoBom (Join-Path $invBad 'README.md') "# Demo`n`nTiene **9 skills**.`n"
    $r = Invoke-Script (Join-Path $invBad 'tools/check.ps1') @()
    Assert ($r.Exit -ne 0) 'check falla si el conteo declarado no coincide'
    Assert ($r.Out -match 'declara 9 skills') 'check nombra el conteo declarado y el real'
    # (c) README sin conteo declarado (o en prosa, sin negrita) -> no falla (tolerante)
    $invNo = New-EncRoot 'chk-inv-none'
    Write-NoBom (Join-Path $invNo 'README.md') "# Demo`n`nSin conteo. Y dijo 9 skills en prosa.`n"
    $r = Invoke-Script (Join-Path $invNo 'tools/check.ps1') @()
    Assert ($r.Exit -eq 0) 'check no falla si no hay conteo declarado en negrita'
    # (d) dos declaraciones contradictorias: la erronea tambien cuenta -> falla
    $invTwo = New-EncRoot 'chk-inv-two'
    Write-NoBom (Join-Path $invTwo 'README.md') "# Demo`n`n**1 skills** arriba, **8 skills** abajo.`n"
    $r = Invoke-Script (Join-Path $invTwo 'tools/check.ps1') @()
    Assert ($r.Exit -ne 0) 'check falla si alguna declaracion en negrita no coincide'
    Assert ($r.Out -match 'declara 8 skills') 'check nombra la declaracion erronea'

    # --- Plantillas: permisos V2 (deniega secretos, permite plantillas) ------
    Section 'templates (permisos V2: deniega secretos, permite plantillas)'
    # Nota: Get-ShellEffect SIMULA las reglas V2 (no prueba openCode): "last match wins"
    # y "un patron que termina en ' *' tambien casa sin argumentos". Los asertos de .env
    # son reales; los de shell validan la INTENCION de las reglas, no el runtime.
    # ADVERTENCIA: si openCode V2 no segmenta un comando compuesto ("git status && git push"),
    # el 'deny' del segundo tramo NO se aplica en la practica. Sin verificar en un V2 real.
    function Test-ShellMatch { param([string]$Cmd, [string]$Pattern)
        if ($Cmd -like $Pattern) { return $true }
        if ($Pattern.EndsWith(' *') -and $Cmd -like $Pattern.Substring(0, $Pattern.Length - 2)) { return $true }
        return $false
    }
    function Get-RuleEffect { param($Rules, [string]$Resource) $eff = $null; foreach ($r in $Rules) { if ($r.action -eq 'read' -and $Resource -like $r.resource) { $eff = $r.effect } }; return $eff }
    function Get-ShellEffect { param($Rules, [string]$Resource) $worst = 'allow'; foreach ($seg in ($Resource -split '\s*(?:&&|\|\||;|\|)\s*' | Where-Object { $_ -ne '' })) { $eff = $null; foreach ($r in $Rules) { if ($r.action -eq 'shell' -and (Test-ShellMatch $seg $r.resource)) { $eff = $r.effect } }; if ($null -eq $eff) { $eff = 'ask' }; if ($eff -eq 'deny') { return 'deny' }; if ($eff -eq 'ask') { $worst = 'ask' } }; return $worst }
    foreach ($t in @('opencode.json', 'opencode.skills-only.json')) {
        $cfg = Get-Content -LiteralPath (Join-Path $Repo ('templates/' + $t)) -Raw | ConvertFrom-Json
        Assert ($cfg.PSObject.Properties.Name -contains 'permissions') "$t usa 'permissions' (V2)"
        $rules = @($cfg.permissions)
        Assert ((Get-RuleEffect $rules '.env') -eq 'deny') "$t deniega .env (raiz)"
        Assert ((Get-RuleEffect $rules 'sub/.env') -eq 'deny') "$t deniega sub/.env"
        Assert ((Get-RuleEffect $rules '.env.local') -eq 'deny') "$t deniega .env.local"
        Assert ((Get-RuleEffect $rules '.env.example') -eq 'allow') "$t permite .env.example"
        Assert ((Get-RuleEffect $rules '.env.sample') -eq 'allow') "$t permite .env.sample"
        Assert ((Get-RuleEffect $rules '.env.template') -eq 'allow') "$t permite .env.template"
        # Verificado contra la especificacion de matching de openCode V2: el punto es LITERAL,
        # asi que '*.env.*' exige la secuencia '.env.' y NO casa '.env_demo' (guion bajo, no punto).
        Assert ((Get-RuleEffect $rules '.env_demo') -eq 'allow') "$t permite .env_demo (documentado como plantilla; el punto es literal)"
        Assert ((Get-RuleEffect $rules '.env.production') -eq 'deny') "$t deniega .env.production (secretos reales)"
        Assert ((Get-ShellEffect $rules 'git status --short') -eq 'allow') "$t permite git status (solo lectura)"
        Assert ((Get-ShellEffect $rules 'git log --oneline') -eq 'allow') "$t permite git log (solo lectura)"
        Assert ((Get-ShellEffect $rules 'git commit -m x') -eq 'deny') "$t deniega git commit"
        Assert ((Get-ShellEffect $rules 'git push origin main') -eq 'deny') "$t deniega git push"
        Assert ((Get-ShellEffect $rules 'git status && rm -rf /') -eq 'ask') "$t no confirma git status encadenado sin preguntar"
        Assert ((Get-ShellEffect $rules 'git status && git push origin main') -eq 'deny') "$t deniega push encadenado tras un git status permitido"
        Assert ((Get-ShellEffect $rules 'git remote -v') -eq 'allow') "$t permite git remote -v (consulta)"
        Assert ((Get-ShellEffect $rules 'git remote remove origin') -eq 'deny') "$t deniega git remote remove (mutacion)"
        Assert ((Get-ShellEffect $rules 'git remote set-url origin mal') -eq 'deny') "$t deniega git remote set-url (mutacion)"
        Assert ((Get-ShellEffect $rules 'git remote add x y') -eq 'deny') "$t deniega git remote add (mutacion)"
        Assert ((Get-ShellEffect $rules 'tee /etc/passwd') -eq 'ask') "$t pregunta por shell arbitrario"
        Assert (@($cfg.skills) -contains 'harness/skills') "${t}: skills = [harness/skills]"
    }

    # --- Politica de Git: allowlist (deny por defecto) -------------------------
    # La denylist anterior (commit/push/pull/... ) era INCOMPLETA por construccion:
    # no cubria 'git clean', 'git checkout', 'git switch', 'git rm', 'git add'...
    # Esos comandos destruyen trabajo (sobre todo lo NO rastreado). Se paso a
    # allowlist: 'git *' -> deny y solo la lectura queda permitida.
    Section 'templates (politica de Git: allowlist, deny por defecto)'
    $shellBlocks = @{}
    foreach ($t in @('opencode.json', 'opencode.skills-only.json')) {
        $cfg = Get-Content -LiteralPath (Join-Path $Repo ('templates/' + $t)) -Raw | ConvertFrom-Json
        $rules = @($cfg.permissions)
        $shellBlocks[$t] = (($rules | Where-Object { $_.action -eq 'shell' } | ForEach-Object { "$($_.resource)=$($_.effect)" }) -join '|')
        # (a) los comandos que DESTRUYEN trabajo (no rastreado o cambios locales)
        foreach ($d in @('git clean -fd', 'git clean -fdx', 'git clean', 'git checkout -- .',
                         'git checkout main', 'git switch main', 'git switch -c feat',
                         'git rm -r src', 'git mv a b', 'git add -A', 'git add .',
                         'git gc --prune=now', 'git prune', 'git worktree remove wt',
                         'git reflog expire --all', 'git update-ref refs/heads/x',
                         'git branch -D main', 'git tag -d v1', 'git stash pop',
                         'git stash', 'git config user.email x', 'git fetch origin',
                         'git init', 'git clone https://x/y', 'git filter-branch --all',
                         'git update-index --assume-unchanged a', 'git apply p.patch',
                         'git am mbox', 'git sparse-checkout set src', 'git submodule update')) {
            Assert ((Get-ShellEffect $rules $d) -eq 'deny') "$t deniega '$d'"
        }
        # (b) la lectura sigue permitida
        foreach ($a in @('git status', 'git status --short', 'git log', 'git log --oneline -n 5',
                         'git diff', 'git diff HEAD~1', 'git show abc123', 'git ls-files',
                         'git ls-tree HEAD', 'git rev-parse HEAD', 'git blame file.cs',
                         'git grep TODO', 'git check-ignore build', 'git remote -v',
                         'git branch --list', 'git tag --list', 'git stash list',
                         'git worktree list', 'git reflog show HEAD')) {
            Assert ((Get-ShellEffect $rules $a) -eq 'allow') "$t permite '$a' (solo lectura)"
        }
        # (c) inyeccion por sufijo: un patron 'git status*' permitiria 'git status$(...)'
        Assert ((Get-ShellEffect $rules 'git status$(rm -rf ~)') -eq 'deny') "$t no permite inyeccion tras 'git status'"
        Assert ((Get-ShellEffect $rules 'git log$(curl evil)') -eq 'deny') "$t no permite inyeccion tras 'git log'"
        # (d) un comando compuesto con un tramo denegado se deniega entero
        Assert ((Get-ShellEffect $rules 'git status && git clean -fd') -eq 'deny') "$t deniega 'git status && git clean -fd'"
        Assert ((Get-ShellEffect $rules 'git log --oneline && git checkout -- .') -eq 'deny') "$t deniega un 'checkout' encadenado"
    }
    # (e) las 2 plantillas deben llevar EXACTAMENTE la misma politica (sin divergencia)
    Assert ($shellBlocks['opencode.json'] -eq $shellBlocks['opencode.skills-only.json']) 'opencode.json y opencode.skills-only.json comparten la politica de shell'
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
