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
    [string]$Maps = '2,3,4,5,7,9',
    [string]$Seeds = '1'
)
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
$running = @()
while ($queue.Count -gt 0 -or $running.Count -gt 0) {
    # one look at each: a game that ended between two looks was dropped
    $still = @()
    foreach ($p in $running) {
        if ($p.HasExited) {
            if (Test-Path "$($p.Out).part") { Move-Item -Force "$($p.Out).part" $p.Out; Remove-Item -Force "$($p.Out).part.err" -ErrorAction SilentlyContinue }
        }
        else { $still += $p }
    }
    $running = $still
    while ($queue.Count -gt 0 -and $running.Count -lt $Parallel) {
        $job = $queue.Dequeue()
        $tmp = "$($job[3]).part"
        $args = "coopmatch DOOM1.WAD $($job[1]) 16800 `"$($job[0])`" $($job[2])"
        $p = Start-Process -FilePath .\doom.exe -ArgumentList $args -RedirectStandardOutput $tmp -RedirectStandardError "$tmp.err" -NoNewWindow -PassThru
        # (holding the handle keeps HasExited true to the process)
        $null = $p.Handle
        $p | Add-Member -NotePropertyName Out -NotePropertyValue $job[3]
        $running += $p
    }
    Start-Sleep -Milliseconds 500
}
'done' | Set-Content games\DONE
