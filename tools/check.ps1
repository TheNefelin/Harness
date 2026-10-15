<#
.SYNOPSIS
    Verifica el catalogo del Harness: estructura de skills, solapamiento de triggers,
    evals de disparo y frescura de las claims. Solo lectura; sale 0 (ok) o 1 (fallo).

.DESCRIPTION
    No depende de openCode: razona sobre el catalogo en disco (skills/<skill>/SKILL.md)
    y sobre evals/triggers.json. Pensado para local y para CI.

      - Skills   : frontmatter valido (name == carpeta, description presente y acotada)
                   y cuerpo <= MaxBodyLines.
      - Triggers : solapamiento de vocabulario distintivo entre las descriptions
                   (parte positiva, antes de la clausula "NO ...").
      - Evals    : casos de evals/triggers.json -> exige que gane la skill esperada.
      - Frescura : marcadores 'verificado YYYY-MM-DD' y su antiguedad frente a MaxAgeDays.

.PARAMETER MaxAgeDays
    Antiguedad maxima, en dias, de un marcador de frescura. Por defecto 180.

.PARAMETER OverlapThreshold
    Jaccard maximo tolerado de vocabulario distintivo entre dos skills. Por defecto 0.5.

.PARAMETER MaxBodyLines
    Lineas maximas del cuerpo (sin frontmatter). Por defecto 400.

.PARAMETER MaxDescription
    Caracteres maximos de la description. Por defecto 1024.

.PARAMETER Strict
    Los avisos (solapamiento, description larga, frescura ausente) tambien fallan.

.EXAMPLE
    .\tools\check.ps1
    .\tools\check.ps1 -Strict -MaxAgeDays 120
#>
param(
    [int]$MaxAgeDays = 180,
    [double]$OverlapThreshold = 0.5,
    [int]$MaxBodyLines = 400,
    [int]$MaxDescription = 1024,
    [switch]$Strict
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$SkillsDir = Join-Path $Root 'skills'
$EvalsFile = Join-Path (Join-Path $Root 'evals') 'triggers.json'

$script:Fail = [System.Collections.Generic.List[string]]::new()
$script:Warn = [System.Collections.Generic.List[string]]::new()

function Get-RelPath {
    param([string]$Full)
    if ($Full.StartsWith($Root, [System.StringComparison]::OrdinalIgnoreCase)) { return $Full.Substring($Root.Length).TrimStart('\', '/') }
    return $Full
}

function Add-Fail { param([string]$m) [void]$script:Fail.Add($m) }
function Add-Warn { param([string]$m) [void]$script:Warn.Add($m) }

$Stopwords = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
foreach ($w in @(
    'the','and','for','una','unos','unas','del','los','las','con','sin','por','para','que','sus',
    'asi','mas','menos','muy','sobre','entre','desde','hasta','hacia','cuando','donde','porque',
    'pues','tambien','solo','tras','ante','bajo','contra','segun','durante','mediante','este',
    'esta','esto','estos','estas','ese','esa','eso','esos','esas','como','pero','pues','hay',
    'ser','son','estan','esta','estan','usar','usa','usando','usarse','usando','crear','crea',
    'creando','modificar','modifica','revisar','revisa','escribir','escribe','gestionar','gestiona',
    'disenar','disena','aplicar','aplica','implementar','implementa','incluir','incluye','permitir',
    'permite','evitar','evita','cubrir','cubre','hacer','hace','montar','monta','seguir','sigue',
    'puede','pueden','debe','deben','nuevo','nueva','nuevos','nuevas','tipo','tipos','parte','partes',
    'modo','modos','caso','casos','forma','formas','ejemplo','ejemplos','general','nivel','patron',
    'senior','usar','aqui','alla','tambien','solo','todo','toda','todos','todas'
)) { [void]$Stopwords.Add($w) }

function Get-Tokens {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return @() }
    $t = $Text.ToLowerInvariant().Normalize([System.Text.NormalizationForm]::FormD)
    $t = $t -replace '\p{Mn}', ''
    $out = [System.Collections.Generic.List[string]]::new()
    foreach ($p in [regex]::Split($t, '[^a-z0-9]+')) {
        if ($p.Length -lt 3) { continue }
        if ($Stopwords.Contains($p)) { continue }
        [void]$out.Add($p)
    }
    return @($out)
}

function Get-Positive {
    param([string]$Description)
    if ([string]::IsNullOrWhiteSpace($Description)) { return '' }
    return (($Description -split '\bNO\b')[0]).Trim()
}

function Get-SkillMeta {
    param([string]$SkillFile)
    $text = [System.IO.File]::ReadAllText($SkillFile, [System.Text.Encoding]::UTF8)
    $lines = @($text -split "\r?\n")
    $name = ''; $desc = ''; $fmEnd = -1
    if ($lines.Count -ge 2 -and $lines[0].Trim() -eq '---') {
        for ($i = 1; $i -lt $lines.Count; $i++) {
            if ($lines[$i].Trim() -eq '---') { $fmEnd = $i; break }
            if ($lines[$i] -match '^name:\s*(.+)$') { $name = $Matches[1].Trim().Trim('"').Trim("'") }
            elseif ($lines[$i] -match '^description:\s*(.+)$') {
                $d = $Matches[1].Trim()
                if ($d.Length -ge 2 -and (($d[0] -eq '"' -and $d[-1] -eq '"') -or ($d[0] -eq "'" -and $d[-1] -eq "'"))) {
                    $d = $d.Substring(1, $d.Length - 2)
                }
                $desc = $d
            }
        }
    }
    $body = if ($fmEnd -ge 0) { $lines.Count - ($fmEnd + 1) } else { $lines.Count }
    return [pscustomobject]@{ Name = $name; Description = $desc; BodyLines = $body; HasFrontmatter = ($fmEnd -ge 0) }
}

# --- Cargar catalogo ---------------------------------------------------------
$catalog = @()
foreach ($dir in (Get-ChildItem -LiteralPath $SkillsDir -Directory | Sort-Object Name)) {
    $sf = Join-Path $dir.FullName 'SKILL.md'
    if (-not (Test-Path -LiteralPath $sf)) { continue }
    $meta = Get-SkillMeta -SkillFile $sf
    $pos = Get-Positive -Description $meta.Description
    $tokens = @(Get-Tokens -Text $pos)
    $catalog += [pscustomobject]@{
        Name   = $dir.Name
        File   = $sf
        Meta   = $meta
        Positive = $pos
        Tokens = $tokens
        Set    = [System.Collections.Generic.HashSet[string]]::new([string[]]$tokens, [System.StringComparer]::OrdinalIgnoreCase)
        NameTokens = @(Get-Tokens -Text $dir.Name)
    }
}
$N = $catalog.Count

# Document frequency (en cuantos skills aparece cada token del trigger positivo)
$df = @{}
foreach ($s in $catalog) {
    foreach ($tok in $s.Set) {
        if ($df.ContainsKey($tok)) { $df[$tok] = $df[$tok] + 1 } else { $df[$tok] = 1 }
    }
}

Write-Host ""
Write-Host "Harness - verificacion del catalogo ($N skills, $Root)" -ForegroundColor Cyan

# --- 1. Lint de skills -------------------------------------------------------
Write-Host ""
Write-Host "[1/4] Estructura de skills" -ForegroundColor White
foreach ($s in $catalog) {
    if (-not $s.Meta.HasFrontmatter) { Add-Fail "frontmatter ausente: $($s.Name)/SKILL.md"; continue }
    if ([string]::IsNullOrWhiteSpace($s.Meta.Name)) { Add-Fail "name ausente: $($s.Name)/SKILL.md" }
    elseif ($s.Meta.Name -ne $s.Name) { Add-Fail "name '$($s.Meta.Name)' != carpeta '$($s.Name)'" }
    if ([string]::IsNullOrWhiteSpace($s.Meta.Description)) { Add-Fail "description ausente: $($s.Name)/SKILL.md" }
    elseif ($s.Meta.Description.Length -gt $MaxDescription) { Add-Warn "description larga ($($s.Meta.Description.Length) > $MaxDescription): $($s.Name)" }
    if ($s.Meta.BodyLines -gt $MaxBodyLines) { Add-Fail "cuerpo $($s.Meta.BodyLines) > $MaxBodyLines lineas: $($s.Name)/SKILL.md" }
}
if ($script:Fail.Count -eq 0 -and $script:Warn.Count -eq 0) { Write-Host "  OK: $N skills con frontmatter y tamano validos." -ForegroundColor Green }
else {
    foreach ($w in $script:Warn) { Write-Host "  AVISO  $w" -ForegroundColor Yellow }
    foreach ($f in $script:Fail) { Write-Host "  FALLO  $f" -ForegroundColor Red }
}

# --- 2. Solapamiento de triggers --------------------------------------------
Write-Host ""
Write-Host "[2/4] Solapamiento de triggers (Jaccard distintivo > $OverlapThreshold)" -ForegroundColor White
$distinctive = @{}
foreach ($s in $catalog) {
    $ds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($tok in $s.Set) { if ($df[$tok] -le 4) { [void]$ds.Add($tok) } }
    $distinctive[$s.Name] = $ds
}
$pairs = @()
for ($i = 0; $i -lt $N; $i++) {
    for ($j = $i + 1; $j -lt $N; $j++) {
        $a = $distinctive[$catalog[$i].Name]
        $b = $distinctive[$catalog[$j].Name]
        if ($a.Count -eq 0 -or $b.Count -eq 0) { continue }
        $inter = [System.Collections.Generic.HashSet[string]]::new($a, [System.StringComparer]::OrdinalIgnoreCase)
        $inter.IntersectWith($b)
        $union = [System.Collections.Generic.HashSet[string]]::new($a, [System.StringComparer]::OrdinalIgnoreCase)
        [void]$union.UnionWith($b)
        $jac = [Math]::Round($inter.Count / [double]$union.Count, 3)
        $pairs += [pscustomobject]@{ A = $catalog[$i].Name; B = $catalog[$j].Name; J = $jac; Shared = ((@($inter) | Sort-Object) -join ',') }
    }
}
$offenders = @($pairs | Where-Object { $_.J -ge $OverlapThreshold } | Sort-Object -Property J -Descending)
if ($offenders.Count -eq 0) {
    $max = @($pairs | Sort-Object -Property J -Descending)[0]
    if ($null -ne $max) { Write-Host ("  OK: ninguno supera {0}. Mayor observado: {1} <-> {2} = {3}" -f $OverlapThreshold, $max.A, $max.B, $max.J) -ForegroundColor Green }
    else { Write-Host "  OK: sin pares comparables." -ForegroundColor Green }
}
else {
    foreach ($o in $offenders) {
        Add-Warn ("solapamiento {0}: {1} <-> {2} (comparten: {3})" -f $o.J, $o.A, $o.B, $o.Shared)
        Write-Host ("  AVISO  {0}  {1} <-> {2}  [{3}]" -f $o.J, $o.A, $o.B, $o.Shared) -ForegroundColor Yellow
    }
}

# --- 3. Evals de disparo -----------------------------------------------------
Write-Host ""
Write-Host "[3/4] Evals de disparo (evals/triggers.json)" -ForegroundColor White
if (-not (Test-Path -LiteralPath $EvalsFile)) {
    Add-Fail "no existe evals/triggers.json"
    Write-Host "  FALLO  falta evals/triggers.json" -ForegroundColor Red
}
else {
    $cases = @()
    foreach ($c in (Get-Content -LiteralPath $EvalsFile -Raw -Encoding UTF8 | ConvertFrom-Json)) { $cases += $c }
    $pass = 0
    foreach ($case in $cases) {
        $ptokens = @(Get-Tokens -Text $case.prompt)
        $pset = [System.Collections.Generic.HashSet[string]]::new([string[]]$ptokens, [System.StringComparer]::OrdinalIgnoreCase)
        $ranked = foreach ($s in $catalog) {
            $score = 0.0
            foreach ($nt in $s.NameTokens) { if ($pset.Contains($nt)) { $score += 3.0 } }
            if ($pset.Contains($s.Name)) { $score += 2.0 }
            foreach ($tok in $pset) {
                if ($s.Set.Contains($tok) -and $df.ContainsKey($tok)) {
                    $score += ([Math]::Log([double]$N / [double]$df[$tok]))
                }
            }
            [pscustomobject]@{ Name = $s.Name; Score = $score }
        }
        $ranked = @($ranked | Sort-Object -Property Score -Descending)
        $top = $ranked[0]
        if ($top.Name -eq $case.expect) { $pass++ }
        else {
            $alt = ($ranked | Select-Object -First 3 | ForEach-Object { '{0}={1:N1}' -f $_.Name, $_.Score }) -join ', '
            Add-Fail "eval fallido: '$($case.prompt)' -> gano '$($top.Name)', se esperaba '$($case.expect)' (top: $alt)"
            Write-Host "  FALLO  '$($case.prompt)'" -ForegroundColor Red
            Write-Host "         esperado '$($case.expect)', gano '$($top.Name)'  ->  $alt" -ForegroundColor DarkGray
        }
    }
    $total = @($cases).Count
    $color = if ($pass -eq $total) { 'Green' } else { 'Red' }
    Write-Host "  $pass/$total casos correctos." -ForegroundColor $color
}

# --- 4. Frescura -------------------------------------------------------------
Write-Host ""
Write-Host "[4/4] Frescura (marcadores 'verificado YYYY-MM-DD', max $MaxAgeDays dias)" -ForegroundColor White
$today = (Get-Date).Date
$rx = [regex]'(?i)verificad[oa]s?\s+(\d{4})-(\d{2})-(\d{2})'
$rxMarker = [regex]'(?i)frescura\s*:'
$mdFiles = @(Get-ChildItem -LiteralPath $SkillsDir -Recurse -File -Filter *.md)
$stale = 0; $undated = 0
foreach ($file in $mdFiles) {
    $text = [System.IO.File]::ReadAllText($file.FullName, [System.Text.Encoding]::UTF8)
    $max = $null
    foreach ($m in $rx.Matches($text)) {
        $d = [datetime]::ParseExact(($m.Groups[1].Value + '-' + $m.Groups[2].Value + '-' + $m.Groups[3].Value), 'yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture)
        if ($null -eq $max -or $d -gt $max) { $max = $d }
    }
    $rel = Get-RelPath $file.FullName
    if ($null -eq $max) {
        if ($rxMarker.IsMatch($text)) { $undated++; Add-Warn "marcador de frescura sin fecha: $rel"; Write-Host "  AVISO  marcador sin fecha  $rel" -ForegroundColor Yellow }
        continue
    }
    $age = ($today - $max).Days
    if ($age -gt $MaxAgeDays) {
        $stale++
        Add-Fail "frescura vencida ($age d, $($max.ToString('yyyy-MM-dd'))): $rel"
        Write-Host ("  FALLO  {0} d  {1}  {2}" -f $age, $max.ToString('yyyy-MM-dd'), (Get-RelPath $file.FullName)) -ForegroundColor Red
    }
    else {
        Write-Host ("  OK     {0,4}d  {1}  {2}" -f ('' + $age), ($max.ToString('yyyy-MM-dd')), (Get-RelPath $file.FullName)) -ForegroundColor DarkGray
    }
}
if ($stale -eq 0) { Write-Host "  OK: ningun marcador supera $MaxAgeDays dias." -ForegroundColor Green }

# --- Resumen -----------------------------------------------------------------
Write-Host ""
$failCount = $script:Fail.Count
$warnCount = $script:Warn.Count
$ok = ($failCount -eq 0) -and (-not $Strict -or $warnCount -eq 0)
$color = if ($ok) { 'Green' } else { 'Red' }
Write-Host ("RESULTADO: {0}  ({1} fallo(s), {2} aviso(s))" -f $(if ($ok) { 'OK' } else { 'FALLO' }), $failCount, $warnCount) -ForegroundColor $color
if ($Strict -and $warnCount -gt 0 -and $failCount -eq 0) { Write-Host "  -Strict: los avisos cuentan como fallo." -ForegroundColor Yellow }

exit $(if ($ok) { 0 } else { 1 })
