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
      - Evals    : casos de evals/triggers.json -> exige que gane la skill esperada,
                   o que NO se active ninguna cuando 'expect' es 'none'.
      - Frescura : marcadores 'verificado YYYY-MM-DD' y su antiguedad frente a MaxAgeDays.
      - Referencias: cada references/**.md debe citarse y ser alcanzable desde SKILL.md
                   (directamente o encadenando; permite sub-referencias).
      - Encoding : el texto versionado debe ser UTF-8 sin BOM y con LF; los .ps1, ASCII
                   puro (un byte > 127 ahi suele ser mojibake).
      - Inventario: el conteo de skills y casos de eval declarado en README.md y
                   DEVELOPMENT.md coincide con el catalogo real (evita drift silencioso).

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
$script:EvalTotal = -1

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
    $name = ''; $desc = ''; $descRaw = ''; $fmEnd = -1
    if ($lines.Count -ge 2 -and $lines[0].Trim() -eq '---') {
        for ($i = 1; $i -lt $lines.Count; $i++) {
            if ($lines[$i].Trim() -eq '---') { $fmEnd = $i; break }
            if ($lines[$i] -match '^name:\s*(.+)$') { $name = $Matches[1].Trim().Trim('"').Trim("'") }
            elseif ($lines[$i] -match '^description:\s*(.+)$') {
                $descRaw = $Matches[1].Trim()
                $desc = $descRaw
                if ($desc.Length -ge 2 -and (($desc[0] -eq '"' -and $desc[-1] -eq '"') -or ($desc[0] -eq "'" -and $desc[-1] -eq "'"))) {
                    $desc = $desc.Substring(1, $desc.Length - 2)
                }
            }
        }
    }
    $body = if ($fmEnd -ge 0) { $lines.Count - ($fmEnd + 1) } else { $lines.Count }
    return [pscustomobject]@{ Name = $name; Description = $desc; DescRaw = $descRaw; BodyLines = $body; HasFrontmatter = ($fmEnd -ge 0) }
}

function Test-ReferenceCitation {
    # Cita = aparece la ruta relativa (references/x.md) o el nombre base (x.md) como token.
    param([string]$Text, [string]$Rel)
    if ([string]::IsNullOrEmpty($Text)) { return $false }
    if ($Text.IndexOf($Rel, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) { return $true }
    $base = Split-Path $Rel -Leaf
    return [regex]::IsMatch($Text, '(?<![\w.\-/])' + [regex]::Escape($base))
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
Write-Host "[1/7] Estructura de skills" -ForegroundColor White
foreach ($s in $catalog) {
    if (-not $s.Meta.HasFrontmatter) { Add-Fail "frontmatter ausente: $($s.Name)/SKILL.md"; continue }
    if ([string]::IsNullOrWhiteSpace($s.Meta.Name)) { Add-Fail "name ausente: $($s.Name)/SKILL.md" }
    elseif ($s.Meta.Name -ne $s.Name) { Add-Fail "name '$($s.Meta.Name)' != carpeta '$($s.Name)'" }
    if ([string]::IsNullOrWhiteSpace($s.Meta.Description)) { Add-Fail "description ausente: $($s.Name)/SKILL.md" }
    elseif ($s.Meta.Description.Length -gt $MaxDescription) { Add-Warn "description larga ($($s.Meta.Description.Length) > $MaxDescription): $($s.Name)" }
    if ($s.Meta.DescRaw -and $s.Meta.DescRaw -notmatch '^["'']' -and $s.Meta.DescRaw -match '(: | #)') { Add-Fail "description sin citar con ': ' o ' #' (YAML invalido): $($s.Name)/SKILL.md" }
    if ($s.Meta.BodyLines -gt $MaxBodyLines) { Add-Fail "cuerpo $($s.Meta.BodyLines) > $MaxBodyLines lineas: $($s.Name)/SKILL.md" }
}
if ($script:Fail.Count -eq 0 -and $script:Warn.Count -eq 0) { Write-Host "  OK: $N skills con frontmatter y tamano validos." -ForegroundColor Green }
else {
    foreach ($w in $script:Warn) { Write-Host "  AVISO  $w" -ForegroundColor Yellow }
    foreach ($f in $script:Fail) { Write-Host "  FALLO  $f" -ForegroundColor Red }
}

# Headroom de tamano (informativo; no falla). Avisa antes de rozar MaxBodyLines.
$headroomPct = 80
$near = @($catalog | Where-Object { $_.Meta.BodyLines -ge ($MaxBodyLines * $headroomPct / 100) } | Sort-Object -Property { $_.Meta.BodyLines } -Descending)
if ($near.Count -gt 0) {
    Write-Host ("  Seguimiento (>={0}% de MaxBodyLines=$MaxBodyLines; considera references/):" -f $headroomPct) -ForegroundColor DarkGray
    foreach ($s in $near) {
        Write-Host ("    {0,4} lineas ({1,3}%)  {2}" -f $s.Meta.BodyLines, [int](100 * $s.Meta.BodyLines / $MaxBodyLines), $s.Name) -ForegroundColor DarkGray
    }
}

# --- 2. Referencias citadas y alcanzables -----------------------------------
Write-Host ""
Write-Host "[2/7] Referencias (cada references/**.md citada y alcanzable desde SKILL.md)" -ForegroundColor White
$orphanRefs = [System.Collections.Generic.List[string]]::new()
foreach ($s in $catalog) {
    $skillDir = Split-Path -Parent $s.File
    $refDir = Join-Path $skillDir 'references'
    if (-not (Test-Path -LiteralPath $refDir)) { continue }
    $refFiles = @(Get-ChildItem -LiteralPath $refDir -Recurse -File -Filter *.md)
    if ($refFiles.Count -eq 0) { continue }

    $texts = @{}
    $texts['SKILL.md'] = [System.IO.File]::ReadAllText($s.File, [System.Text.Encoding]::UTF8)
    $relOf = @{}
    foreach ($rf in $refFiles) {
        $rel = $rf.FullName.Substring($skillDir.Length).TrimStart('\', '/').Replace('\', '/')
        $texts[$rel] = [System.IO.File]::ReadAllText($rf.FullName, [System.Text.Encoding]::UTF8)
        $relOf[$rf.FullName] = $rel
    }

    $visited = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $queue = [System.Collections.Generic.Queue[string]]::new()
    $queue.Enqueue('SKILL.md')
    while ($queue.Count -gt 0) {
        $cur = $queue.Dequeue()
        if (-not $visited.Add($cur)) { continue }
        $curText = $texts[$cur]
        foreach ($rel in @($texts.Keys)) {
            if ($rel -eq 'SKILL.md' -or $visited.Contains($rel)) { continue }
            if (Test-ReferenceCitation -Text $curText -Rel $rel) { $queue.Enqueue($rel) }
        }
    }
    foreach ($rf in $refFiles) {
        if (-not $visited.Contains($relOf[$rf.FullName])) { [void]$orphanRefs.Add((Get-RelPath $rf.FullName)) }
    }
}
if ($orphanRefs.Count -eq 0) { Write-Host "  OK: todas las referencias citadas y alcanzables desde SKILL.md." -ForegroundColor Green }
else {
    foreach ($o in $orphanRefs) {
        Add-Fail "referencia no citada (inalcanzable desde SKILL.md): $o"
        Write-Host "  FALLO  $o" -ForegroundColor Red
    }
    Write-Host "         accion: cita el archivo en 'SKILL.md' (o en otra referencia alcanzable) con cuando leerlo" -ForegroundColor DarkGray
}

# --- 3. Solapamiento de triggers --------------------------------------------
Write-Host ""
Write-Host "[3/7] Solapamiento de triggers (Jaccard distintivo > $OverlapThreshold)" -ForegroundColor White
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
$rankedPairs = @($pairs | Sort-Object -Property J -Descending)
$offenders = @($rankedPairs | Where-Object { $_.J -ge $OverlapThreshold })
if ($offenders.Count -eq 0) {
    if ($rankedPairs.Count -gt 0) { Write-Host ("  OK: ninguno supera {0}." -f $OverlapThreshold) -ForegroundColor Green }
    else { Write-Host "  OK: sin pares comparables." -ForegroundColor Green }
}
else {
    foreach ($o in $offenders) {
        Add-Warn ("solapamiento {0}: {1} <-> {2} (comparten: {3})" -f $o.J, $o.A, $o.B, $o.Shared)
        Write-Host ("  AVISO  {0}  {1} <-> {2}" -f $o.J, $o.A, $o.B) -ForegroundColor Yellow
        Write-Host ("         comparten: {0}" -f $o.Shared) -ForegroundColor DarkGray
        Write-Host ("         accion: afina la description de '{0}' o '{1}', o agrega la otra al bloque 'NO para ...'" -f $o.A, $o.B) -ForegroundColor DarkGray
    }
}
if ($rankedPairs.Count -gt 0) {
    Write-Host "  Seguimiento (mayor solapamiento; para vigilar la deriva):" -ForegroundColor DarkGray
    foreach ($p in (@($rankedPairs | Select-Object -First 3))) {
        Write-Host ("    {0,5:N3}  {1} <-> {2}  [{3}]" -f $p.J, $p.A, $p.B, $p.Shared) -ForegroundColor Gray
    }
}

# --- 4. Evals de disparo -----------------------------------------------------
Write-Host ""
Write-Host "[4/7] Evals de disparo (evals/triggers.json)" -ForegroundColor White
if (-not (Test-Path -LiteralPath $EvalsFile)) {
    Add-Fail "no existe evals/triggers.json"
    Write-Host "  FALLO  falta evals/triggers.json" -ForegroundColor Red
}
else {
    $cases = @()
    foreach ($c in (Get-Content -LiteralPath $EvalsFile -Raw -Encoding UTF8 | ConvertFrom-Json)) { $cases += $c }
    $pass = 0
    $tipos = @{}
    foreach ($case in $cases) {
        $cid = if ($case.PSObject.Properties.Name -contains 'id') { [string]$case.id } else { [string]$case.prompt }
        $ctipo = if ($case.PSObject.Properties.Name -contains 'tipo') { [string]$case.tipo } else { 'sin-tipo' }
        if (-not $tipos.ContainsKey($ctipo)) { $tipos[$ctipo] = 0 }
        $tipos[$ctipo]++
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
        $expect = if ($null -eq $case.expect) { '' } else { [string]$case.expect }
        if ($expect -eq 'none' -or $expect -eq '') {
            if ($top.Score -lt 1.0) { $pass++ }
            else {
                $alt = ($ranked | Select-Object -First 3 | ForEach-Object { '{0}={1:N1}' -f $_.Name, $_.Score }) -join ', '
                Add-Fail "eval negativo fallido ($cid): '$($case.prompt)' -> activo '$($top.Name)' (se esperaba ninguno)"
                Write-Host "  FALLO  [$cid] '$($case.prompt)'" -ForegroundColor Red
                Write-Host "         se esperaba 'none', se activo '$($top.Name)'  ->  $alt" -ForegroundColor DarkGray
            }
        }
        elseif ($top.Name -eq $expect) { $pass++ }
        else {
            $alt = ($ranked | Select-Object -First 3 | ForEach-Object { '{0}={1:N1}' -f $_.Name, $_.Score }) -join ', '
            Add-Fail "eval fallido ($cid): '$($case.prompt)' -> gano '$($top.Name)', se esperaba '$expect' (top: $alt)"
            Write-Host "  FALLO  [$cid] '$($case.prompt)'" -ForegroundColor Red
            Write-Host "         esperado '$expect', gano '$($top.Name)'  ->  $alt" -ForegroundColor DarkGray
        }
    }
    $total = @($cases).Count
    $script:EvalTotal = $total
    $color = if ($pass -eq $total) { 'Green' } else { 'Red' }
    $desglose = (@($tipos.Keys | Sort-Object | ForEach-Object { '{0} {1}' -f $tipos[$_], $_ })) -join ', '
    Write-Host "  $pass/$total casos correctos  ($desglose)." -ForegroundColor $color
}

# --- 5. Frescura -------------------------------------------------------------
Write-Host ""
Write-Host "[5/7] Frescura (marcadores 'verificado YYYY-MM-DD', max $MaxAgeDays dias)" -ForegroundColor White
$today = (Get-Date).Date
$rx = [regex]'(?i)verificad[oa]s?:?\s+(\d{4})-(\d{2})-(\d{2})'
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

# --- 6. Encoding y saltos de linea -------------------------------------------
# Regla del repo: TODO texto versionado en UTF-8 SIN BOM y con LF. Los .ps1 ademas
# deben ser ASCII puro (sin bytes > 127): un no-ASCII ahi suele ser mojibake que
# PowerShell 5.1 lee distinto segun la consola. Se chequea el contenido VERSIONADO
# (lo que git rastrea) para no tropezar con artefactos locales.
Write-Host "[6/7] Encoding (UTF-8 sin BOM, LF; .ps1 en ASCII)" -ForegroundColor White
$EncodingExts = @('.ps1', '.md', '.json', '.yml', '.yaml')
$gitTracked = @()
if (Get-Command git -ErrorAction SilentlyContinue) {
    # git escribe a stderr en un no-repo; con ErrorActionPreference=Stop eso abortaria.
    # Se aisla el EAP y se decide por $LASTEXITCODE, no por una excepcion.
    $prevEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $out = & git -C $Root ls-files 2>$null
        if ($LASTEXITCODE -eq 0 -and $out) { $gitTracked = @($out) }
    }
    catch { $gitTracked = @() }
    finally { $ErrorActionPreference = $prevEap }
}
if ($gitTracked.Count -eq 0) {
    # Sin git: recorrer el disco, excluyendo artefactos que no son fuente.
    $gitTracked = @(Get-ChildItem -LiteralPath $Root -Recurse -File |
        Where-Object { $EncodingExts -contains $_.Extension.ToLower() -and $_.FullName -notmatch '[\\/](\.git|node_modules|\.harness-backup)[\\/]' } |
        ForEach-Object { Get-RelPath $_.FullName })
}
$encBad = 0; $encChecked = 0
foreach ($rel in $gitTracked) {
    $ext = [System.IO.Path]::GetExtension($rel).ToLower()
    if ($EncodingExts -notcontains $ext) { continue }
    $full = Join-Path $Root $rel
    if (-not (Test-Path -LiteralPath $full)) { continue }
    $encChecked++
    $bytes = [System.IO.File]::ReadAllBytes($full)
    $hasBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
    $hasCrlf = $false
    for ($i = 0; $i -lt $bytes.Length - 1; $i++) { if ($bytes[$i] -eq 13 -and $bytes[$i + 1] -eq 10) { $hasCrlf = $true; break } }
    $nonAscii = 0
    foreach ($b in $bytes) { if ($b -gt 127) { $nonAscii++ } }
    $problem = $null
    if ($hasBom) { $problem = 'lleva BOM' }
    elseif ($hasCrlf) { $problem = 'usa CRLF (debe ser LF)' }
    elseif ($ext -eq '.ps1' -and $nonAscii -gt 0) { $problem = "tiene $nonAscii byte(s) no-ASCII (debe ser ASCII)" }
    if ($problem) {
        $encBad++
        Add-Fail "encoding ($problem): $rel"
        Write-Host ("  FALLO  {0}  {1}" -f $problem, $rel) -ForegroundColor Red
    }
}
if ($encBad -eq 0) { Write-Host "  OK: $encChecked archivo(s) en UTF-8 sin BOM y LF; .ps1 en ASCII." -ForegroundColor Green }

# --- 7. Inventario declarado vs. catalogo real -------------------------------
# El conteo de skills/casos se declara en README.md y DEVELOPMENT.md. Si el catalogo
# crece y el texto no se actualiza, aparece un drift silencioso (justo lo que una
# auditoria externa podria reportar como "el README dice 17 y hay 16"). Aqui se
# compara lo DECLARADO con lo REAL: una regla sin verificacion es una promesa.
Write-Host ""
Write-Host "[7/7] Inventario (conteo declarado == catalogo real)" -ForegroundColor White
$declFiles = @('README.md', 'DEVELOPMENT.md')
$declChecked = 0
$declBad = 0
# Convencion: la declaracion viva va en negrita (**N skills**, **N casos**); asi se
# distingue de una mencion en prosa. Si un archivo no declara, no se exige (tolerante).
foreach ($rel in $declFiles) {
    $full = Join-Path $Root $rel
    if (-not (Test-Path -LiteralPath $full)) { continue }
    $declChecked++
    $text = [System.IO.File]::ReadAllText($full, [System.Text.Encoding]::UTF8)
    # Solo cuenta DECLARACIONES vivas, no menciones en prosa (p. ej. "dijo 16 skills" en una
    # decision historica). La convencion del inventario es marcarlo en negrita: **17 skills**.
    $mSkills = [regex]::Matches($text, '\*\*\s*(\d+)\s+skills\s*\*\*')
    foreach ($m in $mSkills) {
        $declared = [int]$m.Groups[1].Value
        if ($declared -ne $N) {
            $declBad++
            Add-Fail "inventario: $rel declara $declared skills; el catalogo tiene $N"
            Write-Host ("  FALLO  {0} declara {1} skills; el catalogo tiene {2}" -f $rel, $declared, $N) -ForegroundColor Red
        }
        else { Write-Host ("  OK     {0}: {1} skills coinciden" -f $rel, $declared) -ForegroundColor DarkGray }
    }
    if ($script:EvalTotal -ge 0) {
        $mCasos = [regex]::Matches($text, '\*\*\s*(\d+)\s+casos\s*\*\*')
        foreach ($m in $mCasos) {
            $declaredC = [int]$m.Groups[1].Value
            if ($declaredC -ne $script:EvalTotal) {
                $declBad++
                Add-Fail "inventario: $rel declara $declaredC casos; evals/triggers.json tiene $($script:EvalTotal)"
                Write-Host ("  FALLO  {0} declara {1} casos; hay {2}" -f $rel, $declaredC, $script:EvalTotal) -ForegroundColor Red
            }
            else { Write-Host ("  OK     {0}: {1} casos coinciden" -f $rel, $declaredC) -ForegroundColor DarkGray }
        }
    }
}
if ($declChecked -eq 0) { Write-Host "  OK: sin archivos de inventario que revisar." -ForegroundColor Green }
elseif ($declBad -eq 0) { Write-Host "  OK: el inventario declarado coincide con el catalogo." -ForegroundColor Green }

# --- Resumen -----------------------------------------------------------------
Write-Host ""
$failCount = $script:Fail.Count
$warnCount = $script:Warn.Count
$ok = ($failCount -eq 0) -and (-not $Strict -or $warnCount -eq 0)
$color = if ($ok) { 'Green' } else { 'Red' }
Write-Host ("RESULTADO: {0}  ({1} fallo(s), {2} aviso(s))" -f $(if ($ok) { 'OK' } else { 'FALLO' }), $failCount, $warnCount) -ForegroundColor $color
if ($Strict -and $warnCount -gt 0 -and $failCount -eq 0) { Write-Host "  -Strict: los avisos cuentan como fallo." -ForegroundColor Yellow }

exit $(if ($ok) { 0 } else { 1 })
