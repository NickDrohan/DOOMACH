# Benchmark candidate co-op nets on a Windows farm machine (the laptop).
#
#   powershell -File farm-eval.ps1 -Kit C:\Users\nick\work\doomeval -Parallel 6
#
# The kit holds doom.exe, DOOM1.WAD and candidates\*.net. Every candidate
# plays as all four bots on each map and seed below, on Nightmare; each game's
# report goes to games\<candidate>_<map>_<seed>.txt for harness/evolve.py to
# score. Games already played are skipped, so a stopped run can resume.
param(
    [string]$Kit = 'C:\Users\nick\work\doomeval',
    [int]$Parallel = 6,
    [string]$Maps = '2,3,4,5,7,9',
    [string]$Seeds = '1',
    # maps given LongTics instead of eight minutes (harness/evolve.py LONG_MAPS)
    [string]$LongMaps = '0',
    [int]$LongTics = 16800
)
$LongList = @($LongMaps -split ',' | ForEach-Object { [int]$_ })
# (seeds as text, "2,3,4": an array does not survive powershell -File)
$SeedList = @($Seeds -split ',' | ForEach-Object { [int]$_ })
$MapList = @($Maps -split ',' | ForEach-Object { [int]$_ })
Set-Location $Kit
New-Item -ItemType Directory -Force games | Out-Null
$queue = New-Object System.Collections.Queue
foreach ($net in Get-ChildItem candidates -Filter *.net) {
    foreach ($m in $MapList) {
        foreach ($s in $SeedList) {
            $out = "games\$($net.BaseName)_$($m)_$($s).txt"
            if (-not (Test-Path $out)) { $queue.Enqueue(@($net.FullName, $m, $s, $out)) }
        }
    }
}
# A finished game's report is moved into place; Windows can hold the file a
# moment after the game ends, so a move that fails is tried again later
# rather than lost (it lost one game in forty this way).
function Publish([string]$out) {
    if (-not (Test-Path "$out.part")) { return $true }
    try {
        Move-Item -Force "$out.part" $out -ErrorAction Stop
        Remove-Item -Force "$out.part.err" -ErrorAction SilentlyContinue
        return $true
    }
    catch { return $false }
}
$running = @()
$pending = @()
while ($queue.Count -gt 0 -or $running.Count -gt 0 -or $pending.Count -gt 0) {
    # one look at each: a game that ended between two looks was dropped
    $still = @()
    foreach ($p in $running) {
        if ($p.HasExited) { $pending += ,@($p.Out, 0) }
        else { $still += $p }
    }
    $running = $still
    # (for a minute at most: then the final sweep has its turn)
    $left = @()
    foreach ($item in $pending) {
        if (-not (Publish $item[0]) -and $item[1] -lt 120) { $left += ,@($item[0], $item[1] + 1) }
    }
    $pending = $left
    while ($queue.Count -gt 0 -and $running.Count -lt $Parallel) {
        $job = $queue.Dequeue()
        $tmp = "$($job[3]).part"
        $tics = 16800
        if ($LongList -contains $job[1]) { $tics = $LongTics }
        $args = "coopmatch DOOM1.WAD $($job[1]) $tics `"$($job[0])`" $($job[2])"
        $p = Start-Process -FilePath .\doom.exe -ArgumentList $args -RedirectStandardOutput $tmp -RedirectStandardError "$tmp.err" -NoNewWindow -PassThru
        # (holding the handle keeps HasExited true to the process)
        $null = $p.Handle
        $p | Add-Member -NotePropertyName Out -NotePropertyValue $job[3]
        $running += $p
    }
    Start-Sleep -Milliseconds 500
}
# and anything a report was left as, if it is a whole one
foreach ($part in Get-ChildItem games -Filter *.txt.part) {
    if (Select-String -Path $part.FullName -Pattern '^end tic' -Quiet) {
        $out = $part.FullName.Substring(0, $part.FullName.Length - 5)
        for ($try = 0; $try -lt 20 -and -not (Publish $out); $try++) { Start-Sleep -Milliseconds 250 }
    }
}
'done' | Set-Content games\DONE
