# Builds the stimulus lists for the preregistered pupil-dilation / lexical decision study:
#   12 practice trials (3 per category), then 100 experimental trials (25 per category)
#   in 2 blocks of 50. Block 1 is shuffled at runtime by OpenSesame; block 2 is a fixed
#   order that is identical for every participant.
# The item pool is the union of the existing stims_LD*_*.csv files, which were selected
# from the Dutch Lexicon Project / CELEX by item_selection.r.
# Usage (from this folder): powershell -ExecutionPolicy Bypass -File make_prereg_stimuli.ps1

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$outDir = Join-Path $here 'prereg'
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

$rng = New-Object System.Random 20261011
$categories = @('HF', 'LF', 'Pseudo', 'Random')
$perBlock = @{
    practice = @{ HF = 3;  LF = 3;  Pseudo = 3;  Random = 3 }
    block1   = @{ HF = 13; LF = 13; Pseudo = 12; Random = 12 }
    block2   = @{ HF = 12; LF = 12; Pseudo = 13; Random = 13 }
}

function Shuffle($items) {
    $a = @($items)
    for ($i = $a.Count - 1; $i -gt 0; $i--) {
        $j = $rng.Next($i + 1)
        $tmp = $a[$i]; $a[$i] = $a[$j]; $a[$j] = $tmp
    }
    return $a
}

$rows = Get-ChildItem $here -Filter 'stims_LD*_*.csv' | Sort-Object Name | ForEach-Object { Import-Csv $_.FullName }
$words = @{}
$rows | Where-Object { $_.correct_response -eq 'n' } | ForEach-Object { $words[$_.stimulus] = $true }

$pool = @{}
foreach ($c in $categories) {
    $pool[$c] = Shuffle (
        $rows | Where-Object {
            $_.cond -eq $c -and
            $_.stimulus -match "^[a-z]{4,8}$" -and
            ($_.correct_response -eq 'n' -or -not $words.ContainsKey($_.stimulus))
        } | Sort-Object stimulus -Unique
    )
}

$used = @{}
$lists = [ordered]@{}
foreach ($part in 'practice', 'block1', 'block2') {
    $list = @()
    foreach ($c in $categories) {
        $n = $perBlock[$part][$c]
        $picked = @($pool[$c] | Where-Object { -not $used.ContainsKey($_.stimulus) } | Select-Object -First $n)
        if ($picked.Count -lt $n) { throw "Not enough $c items for $part" }
        $picked | ForEach-Object { $used[$_.stimulus] = $true }
        $list += $picked
    }
    $lists[$part] = Shuffle $list
}

foreach ($part in $lists.Keys) {
    $file = Join-Path $outDir "stims_$part.csv"
    $i = 0
    $lists[$part] | ForEach-Object {
        $i++
        [pscustomobject]@{
            stimulus         = $_.stimulus
            cond             = $_.cond
            condition        = $_.condition
            correct_response = $_.correct_response
            item_nr          = $i
        }
    } | Export-Csv -NoTypeInformation -Encoding ASCII -Path $file
    Write-Output ("{0}: {1} items" -f $file, $lists[$part].Count)
}
