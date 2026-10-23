@echo off
setlocal EnableExtensions
title Windows Cleanup

:: ============================================================
::  cleanup.bat - scan, choose, then clean.
::
::  Scans everything first and shows you the sizes, then asks
::  what to do. Nothing is deleted before you pick.
::
::  Elevates itself to Administrator automatically.
:: ============================================================

:: --- Self-elevate if not already admin ---
:: The path goes inside a single-quoted PowerShell string, so any ' in it is
:: doubled first: a folder like C:\Users\Bob's PC would otherwise break the
:: launch, and a crafted folder name could run PowerShell of its own. Set
:: BEFORE the if block, because cmd expands %...% for a whole block at once.
set "PSSELF=%~f0"
set "PSSELF=%PSSELF:'=''%"
net session >nul 2>&1
if errorlevel 1 (
    echo Requesting administrator privileges...
    powershell -NoProfile -Command "Start-Process -FilePath '%PSSELF%' -Verb RunAs"
    exit /b
)

set "LOG=%~dp0cleanup.log"
:: Keep the log from growing without bound - trim to the last 300 lines past 512 KB
for %%L in ("%LOG%") do if %%~zL GTR 524288 (
    powershell -NoProfile -Command "$p='%LOG%'; Get-Content -LiteralPath $p -Tail 300 | Set-Content -LiteralPath ($p + '.tmp'); Move-Item -LiteralPath ($p + '.tmp') -Destination $p -Force" >nul 2>&1
)

set "PF86=%ProgramFiles(x86)%"
:: Unique per run. A fixed name can get locked by security software,
:: and then every future run silently fails to write it.
:: Working files live beside the script, not in %TEMP%. Two reasons: %TEMP% is
:: the folder this script deletes, and short-lived .tmp files appearing there
:: look like a dropper to behavioural AV (Bitdefender ATC quarantines them).
set "TALLY=%~dp0.clnp_tally.tmp"
set "ROWS=%~dp0.clnp_rows.tmp"
set "HUNG=%~dp0.clnp_hung.tmp"
set "HUNGCOUNT=0"
set "DAYS=90"

:: Disk Cleanup handlers that start UNTICKED. Everything else starts ticked.
:: You get a screen to toggle any of them before Disk Cleanup runs.
::   DownloadsFolder deletes your ENTIRE Downloads folder, not just old files,
::   which is why it is the one left off by default.
:: "Recycle Bin" is here because this script empties bins itself, honouring
:: your C:-only / all-drives choice. cleanmgr would ignore that and empty
:: every drive. Leave it unticked unless you want that.
set "CMGR_SKIP=DownloadsFolder;Recycle Bin"


echo.
call :Log "=== Cleanup started %date% %time% ==="


:: ============================================================
::  PHASE 1 - SCAN (reads only, deletes nothing)
:: ============================================================
cls
echo.
echo   Scanning... this takes a few seconds.
echo.

del /f /q "%TALLY%" "%ROWS%" "%HUNG%" >nul 2>&1
set "DRYRUN=1"
set "PASS=S"
call :AllTargets

for /f "usebackq delims=" %%T in (`powershell -NoProfile -Command "$t=0; if (Test-Path -LiteralPath $env:TALLY) { foreach ($l in Get-Content -LiteralPath $env:TALLY) { $t += [int64]$l } }; '{0:N1} MB' -f ($t/1MB)"`) do set "TOTAL=%%T"

call :ScanHung


cls
echo.
echo   ============================================================
echo     SCAN RESULTS
echo   ============================================================
echo.
echo     SAFE TO DELETE - caches Windows rebuilds by itself
echo     ------------------------------------------------------
type "%ROWS%" 2>nul
echo     ------------------------------------------------------
echo     Total                            %TOTAL%
echo.
echo     NOT RESPONDING - apps Windows reports as hung
echo     ------------------------------------------------------
type "%HUNG%" 2>nul
echo.
echo     Your Downloads and Recycle Bin are NOT scanned by default.
echo     Option [5] sizes them up only if you ask for it.
echo.
call :CheckBrowsers


:: ============================================================
::  PHASE 2 - MENU
:: ============================================================
:Menu
echo   ============================================================
echo     WHAT DO YOU WANT TO DO?
echo   ============================================================
echo.
echo     [1]  Do everything   Close the hung apps above, delete everything
echo                          above, empty the Recycle Bin for good, run
echo                          Disk Cleanup, then trim memory.
echo                          Your Downloads are NOT touched.
echo.
echo     [2]  Trim only       Free memory only - nothing is deleted
echo.
echo     [3]  Keep browsers   Same as [1], but browser memory left alone
echo.
echo     [4]  Kill hung only  Force-close the not-responding apps listed
echo                          above. Unsaved work in them is lost.
echo.
echo     [5]  Clean + Downloads
echo                          Everything in [1] PLUS Downloads older than
echo                          %DAYS% days, sent to the Recycle Bin
echo.
echo     [6]  Exit            Change nothing
echo.
rem  set /p instead of choice, so a mistyped key does not beep. PICK still
rem  ends up holding the digit you typed, so the branching below is
rem  unchanged. The attempt cap stops this looping forever when stdin is
rem  not a console - set /p returns an empty string instantly there.
set "TRIES=0"
:AskPick
set "PICK="
set /p "PICK=   Choose [1-6]: "
if "%PICK%"=="1" goto :GotPick
if "%PICK%"=="2" goto :GotPick
if "%PICK%"=="3" goto :GotPick
if "%PICK%"=="4" goto :GotPick
if "%PICK%"=="5" goto :GotPick
if "%PICK%"=="6" goto :GotPick
set /a TRIES+=1
if %TRIES% GEQ 10 (
    echo.
    echo    No usable answer after 10 attempts - exiting without changes.
    goto :Bail
)
echo    Type a number from 1 to 6.
goto :AskPick
:GotPick
echo.

if "%PICK%"=="6" goto :Bail
if "%PICK%"=="2" goto :DoTrimOnly
if "%PICK%"=="4" goto :DoKillHung
if "%PICK%"=="5" goto :DoDownloads
if "%PICK%"=="3" set "KEEPBROWSERS=1"
goto :DoClean


:: ============================================================
::  PHASE 3 - ACT
:: ============================================================
:DoKillHung
if "%HUNGCOUNT%"=="0" (
    call :Log "Nothing is hung - no apps to close."
    goto :Finish
)
echo   These will be force-closed. Anything unsaved in them is lost:
echo.
type "%HUNG%" 2>nul
echo.
rem  set /p instead of choice - choice.exe beeps at the console on any key
rem  outside its list and no flag silences it. Same answers accepted.
rem  If no answer can be read at all the fallback is to LEAVE the apps
rem  running: force-closing them loses unsaved work, so that is the side
rem  to err on. Note this script runs without DelayedExpansion, hence
rem  %VAR% rather than !VAR! below.
set "TRIES=0"
:AskKill
set "KILLANS="
set /p "KILLANS=   Force-close them? [Y/N] "
if /i "%KILLANS%"=="Y" goto :DoKillNow
if /i "%KILLANS%"=="YES" goto :DoKillNow
if /i "%KILLANS%"=="N" goto :LeaveRunning
if /i "%KILLANS%"=="NO" goto :LeaveRunning
set /a TRIES+=1
if %TRIES% GEQ 10 goto :LeaveRunning
echo    Type Y to force-close, or N to leave them running.
goto :AskKill
:LeaveRunning
call :Log "Left running - nothing was closed."
goto :Finish
:DoKillNow
call :KillHung
goto :Finish

:DoDownloads
echo   Checking Downloads...
for /f "usebackq delims=" %%D in (`powershell -NoProfile -Command "$cut=(Get-Date).AddDays(-[int]$env:DAYS); $b=0; $n=0; foreach ($f in @(Get-ChildItem ($env:USERPROFILE+'\Downloads') -Force -File -EA SilentlyContinue)) { if ($f.LastWriteTime -lt $cut) { $b+=$f.Length; $n++ } }; '{0} files, {1:N1} GB' -f $n, ($b/1GB)"`) do set "DLINFO=%%D"
echo.
echo   Downloads older than %DAYS% days: %DLINFO%
echo   These go to the Recycle Bin, so you can restore them afterwards.
echo.
set "CONFIRM="
set /p "CONFIRM=  Type DELETE to confirm, or press Enter to skip: "
if /i not "%CONFIRM%"=="DELETE" (
    call :Log "Downloads left alone - not confirmed."
    goto :DoClean
)
set "DODOWNLOADS=1"
goto :DoClean

:DoClean
call :FindDrives
call :CleanScope
call :CmgrChoose
if not "%HUNGCOUNT%"=="0" (
    call :Log "Closing hung apps..."
    call :KillHung
)
call :Log "Cleaning..."
for /f %%a in ('powershell -NoProfile -Command "(Get-PSDrive C).Free"') do set "BEFORE=%%a"
set "DRYRUN="
set "PASS=C"
call :AllTargets
call :EmptyBins
if defined DODOWNLOADS call :CleanDownloads
call :DiskCleanup
for /f %%a in ('powershell -NoProfile -Command "(Get-PSDrive C).Free"') do set "AFTER=%%a"
echo.
for /f "usebackq delims=" %%a in (`powershell -NoProfile -Command "$d = %AFTER% - %BEFORE%; if ($d -ge 1MB) { 'Reclaimed {0:N1} MB.  Free space on C: is now {1:N1} GB.' -f ($d/1MB), (%AFTER%/1GB) } elseif ($d -gt 0) { 'Reclaimed less than 1 MB.  Free space on C: is now {0:N1} GB.' -f (%AFTER%/1GB) } else { 'No net space reclaimed - nothing left to clean.  Free space on C: is now {0:N1} GB.' -f (%AFTER%/1GB) }"`) do call :Log "%%a"

:: Re-measure the same targets. Anything still there was locked by a
:: running process - del cannot touch an open file, and says nothing.
del /f /q "%TALLY%" >nul 2>&1
set "DRYRUN=1"
set "PASS=V"
call :AllTargets
set "DRYRUN="
for /f "usebackq delims=" %%L in (`powershell -NoProfile -Command "$t=0; if (Test-Path -LiteralPath $env:TALLY) { foreach ($l in Get-Content -LiteralPath $env:TALLY) { $t += [int64]$l } }; if ($t -gt 1MB) { '  {0:N1} MB was in use by running apps and could not be deleted.' -f ($t/1MB) }"`) do call :Log "%%L"

:DoTrimOnly
echo.
call :Log "Trimming process working sets..."
call :TrimMemory
goto :Finish

:Bail
call :Log "Exited - nothing was changed."

:Finish
del /f /q "%TALLY%" "%ROWS%" "%HUNG%" >nul 2>&1
if defined DIDCMGR call :Log "Note: some Update Cleanup finishes on your next restart."
call :Log "=== Cleanup finished %date% %time% ==="
echo.
echo   Log: %LOG%
echo.
:: Counts down and closes on its own. Press any key to stop the countdown
:: and hold the window open; press any key again to close it.
:: Falls back to a plain 3 second wait if there is no real console.
powershell -NoProfile -Command "$cr=[string][char]13; try { $end=(Get-Date).AddSeconds(3); $paused=$false; while ($true) { $left=[int][Math]::Ceiling(($end-(Get-Date)).TotalSeconds); if ($left -le 0) { break } if ([Console]::KeyAvailable) { [void][Console]::ReadKey($true); $paused=$true; break } Write-Host -NoNewline ($cr+'   Closing in '+$left+' ...  press any key to stay open '); Start-Sleep -Milliseconds 100 } Write-Host -NoNewline ($cr+(' '*62)+$cr); if ($paused) { Write-Host '   Paused. Press any key to close.'; while ([Console]::KeyAvailable) { [void][Console]::ReadKey($true) } [void][Console]::ReadKey($true) } } catch { Start-Sleep -Seconds 3 }"
if errorlevel 1 "%SystemRoot%\System32\ping.exe" -n 4 127.0.0.1 >nul 2>&1
exit /b


:: ============================================================
::  Target list - called twice: once to scan, once to clean
:: ============================================================
:AllTargets
call :CleanTemp
call :CleanDir "%LOCALAPPDATA%\Temp"                                "User temp (alt)"
call :CleanDir "%SystemRoot%\Temp"                                  "System temp"
call :CleanDir "%SystemRoot%\SoftwareDistribution\Download"         "Windows Update cache"
call :CleanDir "%SystemRoot%\SoftwareDistribution\DeliveryOptimization" "Delivery Optimization"
call :CleanDir "%LOCALAPPDATA%\CrashDumps"                          "Crash dumps"
call :CleanDir "%ProgramData%\Microsoft\Windows\WER\ReportQueue"    "Error reports (queue)"
call :CleanDir "%ProgramData%\Microsoft\Windows\WER\ReportArchive"  "Error reports (archive)"
call :Thumbnails
if not defined DRYRUN ipconfig /flushdns >nul 2>&1
:: Detached on purpose. Run elevated and in the foreground this works through
:: Windows' entire idle-maintenance queue and blocks for minutes. It is not
:: part of cleaning at all - delete these two lines if you do not want it.
if not defined DRYRUN start "" /b "%SystemRoot%\System32\rundll32.exe" advapi32.dll,ProcessIdleTasks
if not defined DRYRUN call :Log "  idle maintenance kicked off in the background"
goto :eof


:: ============================================================
::  Subroutines
:: ============================================================

:CleanTemp
:: %TEMP% is the one target whose whole path is user-configurable, so it is only
:: cleaned when its last folder is named Temp or Tmp. Anything else - a custom
:: scratch folder, a per-session \Temp\2 - is left alone. %LOCALAPPDATA%\Temp
:: is its own target and is cleaned either way.
set "_T=%TEMP%"
if "%_T:~-1%"=="\" set "_T=%_T:~0,-1%"
set "_TL="
for %%T in ("%_T%") do set "_TL=%%~nxT"
if /i not "%_TL%"=="Temp" if /i not "%_TL%"=="Tmp" (
    call :Log "  REFUSED (TEMP is not a Temp or Tmp folder): %TEMP%"
    goto :eof
)
call :CleanDir "%TEMP%" "User temp"
goto :eof


:CleanDir
:: %1 = folder, %2 = label for the table.
:: Deletes the CONTENTS of a folder (files and subfolders), not the folder.
:: Refuses empty paths, drive roots and critical dirs.
:: Only the fixed cache folders in :AllTargets are ever passed in.
if "%~1"=="" goto :eof
set "_CD=%~f1"
set "_LBL=%~2"
if "%_CD:~3%"=="" (
    call :Log "  REFUSED (drive root): %_CD%"
    goto :eof
)
for %%X in ("%SystemRoot%" "%SystemRoot%\System32" "%SystemDrive%\Users" "%ProgramFiles%" "%PF86%" "%ProgramData%" "%USERPROFILE%" "%LOCALAPPDATA%" "%APPDATA%") do (
    if /i "%_CD%"=="%%~fX" (
        call :Log "  REFUSED (protected): %_CD%"
        goto :eof
    )
)
if not exist "%_CD%\" goto :eof
:: Skip folders already handled this pass (%TEMP% and %LOCALAPPDATA%\Temp are often one folder)
set "_KEY=%_CD:\=_%"
set "_KEY=%_KEY::=%"
set "_KEY=%_KEY: =%"
if defined _SEEN%PASS%%_KEY% goto :eof
set "_SEEN%PASS%%_KEY%=1"

if defined DRYRUN (
    powershell -NoProfile -Command "$i=@(Get-ChildItem -LiteralPath '%_CD%' -Recurse -Force -File -EA SilentlyContinue); $s=0; foreach($f in $i){$s+=$f.Length}; Add-Content -LiteralPath $env:TALLY -Value $s; $r='     {0,-28}{1,10:N1} MB{2,8} files' -f $env:_LBL, ($s/1MB), $i.Count; Add-Content -LiteralPath $env:ROWS -Value $r" >nul 2>&1
    goto :eof
)
del /s /f /q "%_CD%\*.*" >nul 2>&1
for /d %%D in ("%_CD%\*") do rd /s /q "%%~fD" >nul 2>&1
call :Log "  cleaned: %_CD%"
goto :eof


:Thumbnails
if defined DRYRUN (
    powershell -NoProfile -Command "$i=@(Get-ChildItem -LiteralPath ($env:LOCALAPPDATA+'\Microsoft\Windows\Explorer') -Filter '*cache_*.db' -Force -File -EA SilentlyContinue); $s=0; foreach($f in $i){$s+=$f.Length}; Add-Content -LiteralPath $env:TALLY -Value $s; $r='     {0,-28}{1,10:N1} MB{2,8} files' -f 'Thumbnail/icon cache', ($s/1MB), $i.Count; Add-Content -LiteralPath $env:ROWS -Value $r" >nul 2>&1
    goto :eof
)
taskkill /f /im explorer.exe >nul 2>&1
del /f /q "%LOCALAPPDATA%\Microsoft\Windows\Explorer\thumbcache_*.db" >nul 2>&1
del /f /q "%LOCALAPPDATA%\Microsoft\Windows\Explorer\iconcache_*.db"  >nul 2>&1
start "" explorer.exe
call :Log "  cleared thumbnail/icon cache (Explorer restarted)"
goto :eof




:DiskCleanup
:: Runs cleanmgr ONCE. Do not add per-drive calls: Windows ignores /d when it
:: is combined with /sagerun, so each call sweeps every drive anyway. Looping
:: over drives just repeats the whole job N times (hung a run on 2026-09-12).
:: The only mode that honours /d is /VERYLOWDISK, which force-enables every
:: handler including DownloadsFolder - it would wipe the whole Downloads folder.
if defined SKIPCMGR (
    call :Log "Disk Cleanup skipped."
    goto :eof
)
call :Log "Running Windows Disk Cleanup - its own window shows progress..."
for /f "usebackq delims=" %%C in (`powershell -NoProfile -Command "$p=Start-Process ($env:SystemRoot+'\System32\cleanmgr.exe') -ArgumentList '/sagerun:65' -PassThru; if ($p.WaitForExit(900000)) { '  Disk Cleanup finished (all drives)' } else { '  Disk Cleanup is still going - it will finish on its own' }"`) do call :Log "%%C"
set "DIDCMGR=1"
goto :eof





:FindDrives
:: Plain "if exist" probes - no WMI enumeration, no free-space measurement.
set "DLIST="
for %%D in (C D E F G H I J K L M N O P Q R S T U V W X Y Z) do if exist %%D:\ call :AddDrive %%D
goto :eof

:AddDrive
set "DLIST=%DLIST% %~1"
goto :eof

:CleanScope
:: The Recycle Bin is the only genuinely per-drive thing here. Every other
:: handler only ever touches the system drive, so scope changes nothing else.
echo.
echo   ============================================================
echo     SCOPE
echo   ============================================================
echo.
echo     [1]  C: drive only                            (default)
echo          Disk Cleanup restricted to C:-only items, and only the
echo          C: Recycle Bin is emptied.
echo.
echo     [2]  All drives -%DLIST%
echo          Also clears per-volume leftovers (FOUND.00x, Catalog.wci)
echo          and empties the Recycle Bin on every drive.
echo.
set "SCOPE="
set /p "SCOPE=  Press ENTER for C: only, or type 2 for all drives: "
if "%SCOPE%"=="2" (
    set "BINDRIVES=%DLIST%"
) else (
    set "BINDRIVES=C"
    rem These three are the ONLY cleanmgr handlers with volume-relative paths
    rem (?:\msdownld.tmp, ?:\Catalog.wci, ?:\FOUND.00x). Unticking them leaves
    rem every remaining handler hard-coded to C:, so Disk Cleanup cannot reach
    rem another drive. Side effect: C:\Windows\msdownld.tmp is skipped too.
    set "CMGR_SKIP=%CMGR_SKIP%;Active Setup Temp Folders;Content Indexer Cleaner;Old ChkDsk Files"
)
goto :eof

:CmgrChoose
:: Interactive tick list. Writes the selection to Disk Cleanup profile 65.
:: Exit code 2 means skip Disk Cleanup altogether.
powershell -NoProfile -Command "$base='HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches'; $names=@(); foreach ($k in Get-ChildItem $base -EA SilentlyContinue) { $names += $k.PSChildName }; [Array]::Sort($names); $skip=@($env:CMGR_SKIP -split ';'); $state=@{}; foreach ($n in $names) { $state[$n] = (-not ($skip -contains $n)) }; $risky=@{}; $risky['DownloadsFolder']='deletes your ENTIRE Downloads folder'; $risky['Recycle Bin']='leave OFF - this script empties bins per your scope'; $risky['Previous Installations']='removes Windows.old, no rollback'; $risky['Windows ESD installation files']='breaks Reset this PC without media'; while ($true) { Clear-Host; Write-Host ''; Write-Host '   DISK CLEANUP - tick what you want removed'; Write-Host '   ---------------------------------------------------------------'; for ($i=0; $i -lt $names.Count; $i++) { $n=$names[$i]; $m='[ ]'; if ($state[$n]) { $m='[X]' }; $note=''; if ($risky.ContainsKey($n)) { $note='   ** ' + $risky[$n] }; Write-Host ('   {0,2} {1} {2}{3}' -f ($i+1), $m, $n, $note) }; Write-Host ''; Write-Host '   numbers = toggle (e.g. 3 or 3,7,12)   A = all on   N = all off   D = defaults'; Write-Host '   S = skip Disk Cleanup entirely'; Write-Host ''; $in=Read-Host '   Press ENTER to run Disk Cleanup with the ticked items, or type a choice'; $t=$in.Trim(); if ($t -eq '') { break }; if ($t -eq 'S' -or $t -eq 's') { exit 2 }; if ($t -eq 'A' -or $t -eq 'a') { foreach ($n in $names) { $state[$n]=$true }; continue }; if ($t -eq 'N' -or $t -eq 'n') { foreach ($n in $names) { $state[$n]=$false }; continue }; if ($t -eq 'D' -or $t -eq 'd') { foreach ($n in $names) { $state[$n] = (-not ($skip -contains $n)) }; continue }; foreach ($part in ($t -split '[,\s]+')) { $num=0; if ([int]::TryParse($part, [ref]$num)) { if ($num -ge 1 -and $num -le $names.Count) { $key=$names[$num-1]; $state[$key] = (-not $state[$key]) } } } }; $on=0; $off=0; try { foreach ($n in $names) { $v=0; if ($state[$n]) { $v=2 }; $null=New-ItemProperty -Path ($base + '\' + $n) -Name StateFlags0065 -Value $v -PropertyType DWord -Force -EA Stop; if ($v -eq 2) { $on++ } else { $off++ } }; Write-Host ('   {0} handlers ticked, {1} left off' -f $on, $off) } catch { Write-Host ('   could not save Disk Cleanup options: ' + $_.Exception.Message); exit 2 }; exit 0"
if errorlevel 2 set "SKIPCMGR=1"
goto :eof

:EmptyBins
:: Permanent deletion by design - bin treated as a shredder, not a holding pen.
:: Runs BEFORE the Downloads step on purpose, so anything option [5] moves into
:: the bin afterwards is still recoverable.
:: Clear-RecycleBin throws Win32Exception even when it succeeds, so that
:: exception is treated as success - only other errors count as a skip.
for /f "usebackq delims=" %%B in (`powershell -NoProfile -Command "$ds=@($env:BINDRIVES.Trim() -split '\s+'); $done=@(); $skip=@(); foreach ($d in $ds) { if ($d -ne '') { try { Clear-RecycleBin -DriveLetter $d -Force -ErrorAction Stop; $done += $d } catch [System.ComponentModel.Win32Exception] { $done += $d } catch { $skip += $d } } }; if ($done.Count) { '  Recycle Bin permanently emptied on: ' + ($done -join ', ') }; if ($skip.Count) { '  No Recycle Bin on: ' + ($skip -join ', ') }; if (-not $done.Count -and -not $skip.Count) { '  Recycle Bin: no drives in scope' }"`) do call :Log "%%B"
goto :eof

:CleanDownloads
:: Sends old Downloads to the Recycle Bin rather than deleting outright,
:: so a mistake here is recoverable.
for /f "usebackq delims=" %%D in (`powershell -NoProfile -Command "Add-Type -AssemblyName Microsoft.VisualBasic; $cut=(Get-Date).AddDays(-[int]$env:DAYS); $n=0; $b=0; foreach ($f in @(Get-ChildItem ($env:USERPROFILE+'\Downloads') -Force -File -EA SilentlyContinue)) { if ($f.LastWriteTime -lt $cut) { try { $sz=$f.Length; [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile($f.FullName,'OnlyErrorDialogs','SendToRecycleBin'); $n++; $b+=$sz } catch {} } }; '  Downloads: {0} files ({1:N1} GB) sent to Recycle Bin' -f $n, ($b/1GB)"`) do call :Log "%%D"
goto :eof


:ScanHung
:: A process only has a meaningful Responding value if it owns a window,
:: so background services are never counted as hung.
for /f "usebackq delims=" %%H in (`powershell -NoProfile -Command "$h=@(); foreach ($p in Get-Process) { try { if ($p.MainWindowHandle -ne 0 -and -not $p.Responding) { $h += $p } } catch {} }; $o=@(); foreach ($p in $h) { $o += '     {0,-28}PID {1}' -f $p.ProcessName, $p.Id }; if ($o.Count -eq 0) { $o = @('     none - everything is responding') }; Set-Content -LiteralPath $env:HUNG -Value $o; $h.Count"`) do set "HUNGCOUNT=%%H"
goto :eof

:KillHung
:: Never touches core OS processes. Explorer is allowed but restarted,
:: since a hung shell is one of the main reasons to run this.
for /f "usebackq delims=" %%K in (`powershell -NoProfile -Command "$crit=@('System','Idle','Registry','smss','csrss','wininit','winlogon','services','lsass','dwm','fontdrvhost','LogonUI','Memory Compression'); $killed=@(); $shell=$false; foreach ($p in Get-Process) { try { if ($p.MainWindowHandle -ne 0 -and -not $p.Responding) { if ($crit -contains $p.ProcessName) { continue }; $n=$p.ProcessName; Stop-Process -Id $p.Id -Force -EA Stop; $killed += $n; if ($n -eq 'explorer') { $shell=$true } } } catch {} }; if ($shell) { Start-Process explorer.exe }; if ($killed.Count) { '  closed {0}: {1}' -f $killed.Count, ($killed -join ', ') } else { '  nothing could be closed' }"`) do call :Log "%%K"
goto :eof

:CheckBrowsers
:: %TEMP% holds in-progress downloads and files opened straight from a browser.
set "BROWSING="
for /f "usebackq delims=" %%B in (`powershell -NoProfile -Command "$n=@(Get-Process chrome,msedge,firefox,brave,opera,vivaldi -EA SilentlyContinue); if ($n.Count) { $g=@(); foreach ($p in $n) { if ($g -notcontains $p.ProcessName) { $g+=$p.ProcessName } }; $g -join ', ' }"`) do set "BROWSING=%%B"
if not defined BROWSING goto :eof
echo     NOTE: browser running (%BROWSING%). Your temp folder holds
echo     in-progress downloads. Close it first if one is running.
echo.
goto :eof


:TrimMemory
:: Asks Windows to page out each process idle working set. Non-destructive:
:: no file or setting changes, and pages fault back in on demand.
:: Uses the .NET MaxWorkingSet setter instead of a native P/Invoke, because
:: compiling C# at runtime is a heavily weighted signal for behavioural AV.
for /f "usebackq delims=" %%M in (`powershell -NoProfile -Command "$before = (Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory * 1KB; $ok=0; $skip=0; $bskip=0; $browsers = @('chrome','msedge','firefox','brave','opera','opera_gx','vivaldi','iexplore','browser_broker','msedgewebview2'); $leave = ($env:KEEPBROWSERS -eq '1'); foreach ($p in Get-Process) { if ($leave -and ($browsers -contains $p.ProcessName)) { $bskip++; continue }; try { $p.MaxWorkingSet = $p.MaxWorkingSet; $ok++ } catch { $skip++ } }; Start-Sleep -Milliseconds 500; $after = (Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory * 1KB; '  trimmed {0} processes, {1} skipped (protected/system), {2} browser processes left alone' -f $ok, $skip, $bskip; '  free RAM {0:N0} MB to {1:N0} MB (gain {2:+#,##0;-#,##0;0} MB)' -f ($before/1MB), ($after/1MB), (($after-$before)/1MB)"`) do call :Log "%%M"
goto :eof


:Log
echo %~1
echo [%date% %time%] %~1 >> "%LOG%"
goto :eof