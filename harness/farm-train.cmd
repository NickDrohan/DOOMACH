@echo off
rem Co-op cohort training on a Windows farm machine: one arena copy in run<N>
rem with its own seed, from the league snapshot in seed\. Started below normal
rem priority by the PC (Win32_Process Create), so it yields to anything else.
rem
rem   farm-train.cmd <N> <seed>   (odd: the arena sets the seed's low bit)
cd /d "%~dp0"
set ARENA_DUTY=100
set COOP_COHORT=4
set ARENA_SEED=%2
if not exist run%1 mkdir run%1
if not exist run%1\coop.bin copy seed\coop.bin run%1\ >nul
if not exist run%1\train.bin copy seed\train.bin run%1\ >nul
arena.exe DOOM1.WAD bot0.net run%1 0 coop >> run%1\arena.log 2>&1
