# Benchmark candidate co-op nets on a Windows farm machine (the laptop).
#
#   powershell -File farm-eval.ps1 -Kit C:\Users\nick\work\doomeval -Parallel 6
#
# The kit holds doom.exe, DOOM1.WAD and candidates\*.net. Every candidate
# plays as all four bots on each map and seed below, on Nightmare; each game's
# report goes to games\<candidate>_<map>_<seed>.txt for harness/farm-collect.py
# to score. Games already played are skipped, so a stopped run can resume.
param(
    [string]$Kit = 'C:\Users\nick\work\doomeval',
    [int]$Parallel = 6,
    [int[]]$Maps = @(2, 3, 4, 5, 7, 9),
    [int[]]$Seeds = @(1)
)
Set-Location $Kit
New-Item -ItemType Directory -Force games | Out-Null
$queue = New-Object System.Collections.Queue
foreach ($net in Get-ChildItem candidates -Filter *.net) {
    foreach ($m in $Maps) {
        foreach ($s in $Seeds) {
            $out = "games\$($net.BaseName)_$($m)_$($s).txt"
            if (-not (Test-Path $out)) { $queue.Enqueue(@($net.FullName, $m, $s, $out)) }
        }
    }
}
$running = @()
while ($queue.Count -gt 0 -or $running.Count -gt 0) {
    foreach ($p in @($running | Where-Object { $_.HasExited })) {
        if (Test-Path "$($p.Out).part") { Move-Item -Force "$($p.Out).part" $p.Out; Remove-Item -Force "$($p.Out).part.err" -ErrorAction SilentlyContinue }
    }
    $running = @($running | Where-Object { -not $_.HasExited })
    while ($queue.Count -gt 0 -and $running.Count -lt $Parallel) {
        $job = $queue.Dequeue()
        $tmp = "$($job[3]).part"
        $args = "coopmatch DOOM1.WAD $($job[1]) 16800 `"$($job[0])`" $($job[2])"
        $p = Start-Process -FilePath .\doom.exe -ArgumentList $args -RedirectStandardOutput $tmp -RedirectStandardError "$tmp.err" -NoNewWindow -PassThru
        $p | Add-Member -NotePropertyName Out -NotePropertyValue $job[3]
        $running += $p
    }
    Start-Sleep -Milliseconds 500
}
'done' | Set-Content games\DONE
