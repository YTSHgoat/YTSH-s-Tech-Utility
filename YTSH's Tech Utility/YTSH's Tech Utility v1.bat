@echo off
setlocal EnableDelayedExpansion

cd /d "%~dp0"

net session >nul 2>&1 || (
    cls
    color 0C
    echo.
    echo  =============================================
    echo   [!!!!] NOT RUNNING AS ADMINISTRATOR [!!!!]
    echo  =============================================
    echo.
    echo   This program MUST be opened as Administrator
    echo   for any changes to take effect. Here is why:
    echo.
    echo   1. Removing AppX packages requires SYSTEM privileges.
    echo   2. Modifying HKLM registry keys is blocked for standard accounts.
    echo   3. Disabling Windows Services requires Administrator token.
    echo   4. Creating System Restore Points needs elevated access.
    echo   5. Disabling Scheduled Tasks requires elevation to write.
    echo   6. Provisioned package removal is only permitted with SYSTEM elevation.
    echo   7. Writing to protected policy paths requires admin rights.
    echo.
    echo   HOW TO FIX:
    echo   Right-click this .bat file and select "Run as administrator" then try again.
    echo.
    echo  =============================================
    echo.
    pause
    exit /b 1
)

set "SCRIPTDIR=%~dp0"
set "YTSH_CONFIG=%~dp0ytsh_config.ini"
set "REGPOINTS_DIR="
set "LOGDIR="
set "AUTORESTART=1"
set "SKIP_OEM=0"
set "COLOR_THEME=DEFAULT"
set "HIDE_WELCOME=0"
set "SAFE_MODE=1"
set "DEBLOAT_MODE=DEFAULT"

for /F %%a in ('echo prompt $E ^| cmd') do set "ESC=%%a"
set "C_SAFE=!ESC![92m"
set "C_BAL=!ESC![93m"
set "C_AGG=!ESC![91m"
set "C_RST=!ESC![0m"

if exist "%YTSH_CONFIG%" (
    for /f "usebackq tokens=1,* delims==" %%A in ("%YTSH_CONFIG%") do (
        set "val=%%B"
        if "!val:~-1!"==" " set "val=!val:~0,-1!"
        
        if "%%A"=="REGPOINTS_DIR" set "REGPOINTS_DIR=!val!"
        if "%%A"=="LOGDIR" set "LOGDIR=!val!"
        if "%%A"=="AUTORESTART" set "AUTORESTART=!val!"
        if "%%A"=="SKIP_OEM" set "SKIP_OEM=!val!"
        if "%%A"=="COLOR_THEME" set "COLOR_THEME=!val!"
        if "%%A"=="HIDE_WELCOME" set "HIDE_WELCOME=!val!"
        if "%%A"=="SAFE_MODE" set "SAFE_MODE=!val!"
        if "%%A"=="DEBLOAT_MODE" set "DEBLOAT_MODE=!val!"
    )
)

if not defined REGPOINTS_DIR set "REGPOINTS_DIR=%~dp0YTSH REGISTRY POINTS"
if not defined LOGDIR (
    set "_SDIR=%SCRIPTDIR:~0,-1%"
    set "LOGDIR=!_SDIR!"
)

if not exist "!LOGDIR!" mkdir "!LOGDIR!" >nul 2>&1

set "LOGFILE=!LOGDIR!\removed_apps.txt"
set "SVCLOG=!LOGDIR!\disabled_services.txt"
set "REGLOG=!LOGDIR!\registry_changes.txt"
set "ERRLOG=!LOGDIR!\error_log.txt"

set "COL_HDR=0B"
set "COL_OPS=0F"
set "COL_ERR=0C"
set "COL_HDR_PS=Cyan"
set "COL_OPS_PS=White"

if "!COLOR_THEME!"=="MATRIX" (
    set "COL_HDR=0A"
    set "COL_OPS=0A"
    set "COL_ERR=0C"
    set "COL_HDR_PS=White"
    set "COL_OPS_PS=Green"
)
if "!COLOR_THEME!"=="AMBER" (
    set "COL_HDR=0E"
    set "COL_OPS=0E"
    set "COL_ERR=0C"
    set "COL_HDR_PS=Yellow"
    set "COL_OPS_PS=White"
)
if "!COLOR_THEME!"=="OCEAN" (
    set "COL_HDR=0B"
    set "COL_OPS=0B"
    set "COL_ERR=0C"
    set "COL_HDR_PS=Magenta"
    set "COL_OPS_PS=Cyan"
)
if "!COLOR_THEME!"=="BLOOD" (
    set "COL_HDR=0C"
    set "COL_OPS=0C"
    set "COL_ERR=0E"
    set "COL_HDR_PS=Red"
    set "COL_OPS_PS=Yellow"
)
if "!COLOR_THEME!"=="VIOLET" (
    set "COL_HDR=0D"
    set "COL_OPS=0D"
    set "COL_ERR=0C"
    set "COL_HDR_PS=Magenta"
    set "COL_OPS_PS=White"
)
if "!COLOR_THEME!"=="ARCTIC" (
    set "COL_HDR=0F"
    set "COL_OPS=0B"
    set "COL_ERR=0C"
    set "COL_HDR_PS=White"
    set "COL_OPS_PS=Cyan"
)
if "!COLOR_THEME!"=="GOLD" (
    set "COL_HDR=06"
    set "COL_OPS=0E"
    set "COL_ERR=0C"
    set "COL_HDR_PS=DarkYellow"
    set "COL_OPS_PS=Yellow"
)
if "!COLOR_THEME!"=="MIDNIGHT" (
    set "COL_HDR=09"
    set "COL_OPS=09"
    set "COL_ERR=0C"
    set "COL_HDR_PS=Blue"
    set "COL_OPS_PS=Cyan"
)

reg add "HKCU\Console" /v VirtualTerminalLevel /t REG_DWORD /d 1 /f >nul 2>&1

:DETECT_SYSTEM
cls
echo.
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '    Detecting System Hardware  -  Please Wait' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
echo.
powershell -NoProfile -Command "Write-Host '   Scanning: OS, CPU, RAM, GPU, Storage ...' -ForegroundColor DarkGray"
echo.

set "DETECT_SCRIPT=%TEMP%\ytsh_detect_%RANDOM%%RANDOM%.ps1"
if exist "%DETECT_SCRIPT%" del "%DETECT_SCRIPT%" >nul 2>&1
>>"%DETECT_SCRIPT%" echo $out = @()
>>"%DETECT_SCRIPT%" echo $os  = Get-CimInstance Win32_OperatingSystem  -ErrorAction SilentlyContinue
>>"%DETECT_SCRIPT%" echo $sys = Get-CimInstance Win32_ComputerSystem   -ErrorAction SilentlyContinue
>>"%DETECT_SCRIPT%" echo $osName = if ($os) { ($os.Caption -replace 'Microsoft ', '').Trim() } else { 'Unknown OS' }
>>"%DETECT_SCRIPT%" echo $out += "SYS_OS=$osName"
>>"%DETECT_SCRIPT%" echo $chassis = Get-CimInstance Win32_SystemEnclosure -ErrorAction SilentlyContinue
>>"%DETECT_SCRIPT%" echo $laptopTypes = @(8,9,10,11,12,14,18,21,30,31,32)
>>"%DETECT_SCRIPT%" echo $formFactor = 'DESKTOP'
>>"%DETECT_SCRIPT%" echo if ($chassis) { foreach ($ct in $chassis.ChassisTypes) { if ($laptopTypes -contains [int]$ct) { $formFactor = 'LAPTOP'; break } } }
>>"%DETECT_SCRIPT%" echo $out += "SYS_FORM=$formFactor"
>>"%DETECT_SCRIPT%" echo $mfr = if ($sys) { $sys.Manufacturer.Trim() } else { '' }
>>"%DETECT_SCRIPT%" echo $brand = switch -Wildcard ($mfr.ToUpper()) { 'HP*' { 'HP' } 'HEWLETT*' { 'HP' } 'DELL*' { 'Dell' } 'LENOVO*' { 'Lenovo' } 'ASUS*' { 'ASUS' } 'ACER*' { 'Acer' } 'MSI*' { 'MSI' } 'TOSHIBA*' { 'Toshiba' } 'SAMSUNG*' { 'Samsung' } 'MICROSOFT*' { 'Microsoft' } 'RAZER*' { 'Razer' } 'HUAWEI*' { 'Huawei' } 'LG*' { 'LG' } default { if ($mfr -ne '') { $mfr } else { 'Unknown' } } }
>>"%DETECT_SCRIPT%" echo $out += "SYS_BRAND=$brand"
>>"%DETECT_SCRIPT%" echo $cpu = Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue ^| Select-Object -First 1
>>"%DETECT_SCRIPT%" echo $cpuName  = if ($cpu) { ($cpu.Name.Trim() -replace '\(R\)','' -replace '\(TM\)','' -replace '  ',' ').Trim() } else { 'Unknown CPU' }
>>"%DETECT_SCRIPT%" echo $cpuCores = if ($cpu) { [string]$cpu.NumberOfCores } else { '?' }
>>"%DETECT_SCRIPT%" echo $cpuGHz   = if ($cpu) { [string]([math]::Round($cpu.MaxClockSpeed / 1000.0, 1)) + ' GHz' } else { '' }
>>"%DETECT_SCRIPT%" echo $out += "SYS_CPU=$cpuName"
>>"%DETECT_SCRIPT%" echo $out += "SYS_CPU_CORES=$cpuCores"
>>"%DETECT_SCRIPT%" echo $out += "SYS_CPU_GHZ=$cpuGHz"
>>"%DETECT_SCRIPT%" echo $totalRamGB = if ($os) { [math]::Round($os.TotalVisibleMemorySize / 1MB, 0) } else { 0 }
>>"%DETECT_SCRIPT%" echo $out += "SYS_RAM=$totalRamGB GB"
>>"%DETECT_SCRIPT%" echo $gpus = Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue ^| Where-Object { $_.Name -notmatch 'Basic Display' -and $_.Name -notmatch 'Remote' }
>>"%DETECT_SCRIPT%" echo $gpu = $gpus ^| Select-Object -First 1
>>"%DETECT_SCRIPT%" echo $gpuName = if ($gpu) { ($gpu.Name.Trim() -replace '\(R\)','' -replace '\(TM\)','').Trim() } else { 'Unknown GPU' }
>>"%DETECT_SCRIPT%" echo $out += "SYS_GPU=$gpuName"
>>"%DETECT_SCRIPT%" echo if ($gpus.Count -gt 1) { $gpu2 = ($gpus ^| Select-Object -Skip 1 -First 1).Name.Trim() -replace '\(R\)','' -replace '\(TM\)','' ; $out += "SYS_GPU2=$gpu2" } else { $out += 'SYS_GPU2=' }
>>"%DETECT_SCRIPT%" echo $cDrive = Get-PSDrive -Name C -PSProvider FileSystem -ErrorAction SilentlyContinue
>>"%DETECT_SCRIPT%" echo $diskTotalGB = if ($cDrive) { [math]::Round(($cDrive.Used + $cDrive.Free) / 1GB, 0) } else { 0 }
>>"%DETECT_SCRIPT%" echo $diskFreeGB  = if ($cDrive) { [math]::Round($cDrive.Free / 1GB, 1) } else { 0 }
>>"%DETECT_SCRIPT%" echo $diskType = 'HDD'
>>"%DETECT_SCRIPT%" echo try { $pd = Get-PhysicalDisk -ErrorAction Stop ^| Sort-Object DeviceId ^| Select-Object -First 1; if ($pd) { if ($pd.BusType -eq 'NVMe') { $diskType = 'NVMe SSD' } elseif ($pd.MediaType -eq 'SSD' -and $pd.BusType -eq 'SATA') { $diskType = 'SATA SSD' } elseif ($pd.MediaType -eq 'SSD') { $diskType = 'SSD' } elseif ($pd.MediaType -eq 'Unspecified' -and $pd.BusType -eq 'NVMe') { $diskType = 'NVMe SSD' } } } catch {}
>>"%DETECT_SCRIPT%" echo $out += "SYS_DISK_TYPE=$diskType"
>>"%DETECT_SCRIPT%" echo $out += "SYS_DISK_TOTAL=$diskTotalGB GB"
>>"%DETECT_SCRIPT%" echo $out += "SYS_DISK_FREE=$diskFreeGB GB"
>>"%DETECT_SCRIPT%" echo $out ^| Set-Content -Path "$env:TEMP\ytsh_sysinfo.txt" -Encoding ASCII
powershell -NoProfile -ExecutionPolicy Bypass -File "%DETECT_SCRIPT%"
del "%DETECT_SCRIPT%" >nul 2>&1


set "SYS_OS=Unknown OS"
set "SYS_FORM=PC"
set "SYS_BRAND=Unknown"
set "SYS_CPU=Unknown CPU"
set "SYS_CPU_CORES=?"
set "SYS_CPU_GHZ="
set "SYS_RAM=Unknown"
set "SYS_GPU=Unknown GPU"
set "SYS_GPU2="
set "SYS_DISK_TYPE=Unknown"
set "SYS_DISK_TOTAL=Unknown"
set "SYS_DISK_FREE=Unknown"

if exist "%TEMP%\ytsh_sysinfo.txt" (
    for /f "usebackq tokens=1,* delims==" %%A in ("%TEMP%\ytsh_sysinfo.txt") do (
        if "%%A"=="SYS_OS"         set "SYS_OS=%%B"
        if "%%A"=="SYS_FORM"       set "SYS_FORM=%%B"
        if "%%A"=="SYS_BRAND"      set "SYS_BRAND=%%B"
        if "%%A"=="SYS_CPU"        set "SYS_CPU=%%B"
        if "%%A"=="SYS_CPU_CORES"  set "SYS_CPU_CORES=%%B"
        if "%%A"=="SYS_CPU_GHZ"    set "SYS_CPU_GHZ=%%B"
        if "%%A"=="SYS_RAM"        set "SYS_RAM=%%B"
        if "%%A"=="SYS_GPU"        set "SYS_GPU=%%B"
        if "%%A"=="SYS_GPU2"       set "SYS_GPU2=%%B"
        if "%%A"=="SYS_DISK_TYPE"  set "SYS_DISK_TYPE=%%B"
        if "%%A"=="SYS_DISK_TOTAL" set "SYS_DISK_TOTAL=%%B"
        if "%%A"=="SYS_DISK_FREE"  set "SYS_DISK_FREE=%%B"
    )
)

powershell -NoProfile -Command "Write-Host '  [DONE] Detection complete!' -ForegroundColor Green"
echo.
powershell -NoProfile -Command "Write-Host '  -----------------------------------------------' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '  OS   : ' -ForegroundColor !COL_HDR_PS! -NoNewline; Write-Host '!SYS_OS!  [!SYS_FORM!]' -ForegroundColor !COL_OPS_PS!"
powershell -NoProfile -Command "Write-Host '  BRAND: ' -ForegroundColor !COL_HDR_PS! -NoNewline; Write-Host '!SYS_BRAND!' -ForegroundColor !COL_OPS_PS!"
powershell -NoProfile -Command "Write-Host '  CPU  : ' -ForegroundColor !COL_HDR_PS! -NoNewline; Write-Host '!SYS_CPU! (!SYS_CPU_CORES! cores, !SYS_CPU_GHZ!)' -ForegroundColor !COL_OPS_PS!"
powershell -NoProfile -Command "Write-Host '  RAM  : ' -ForegroundColor !COL_HDR_PS! -NoNewline; Write-Host '!SYS_RAM!' -ForegroundColor !COL_OPS_PS!"
powershell -NoProfile -Command "Write-Host '  GPU  : ' -ForegroundColor !COL_HDR_PS! -NoNewline; Write-Host '!SYS_GPU!' -ForegroundColor !COL_OPS_PS!"
if not "!SYS_GPU2!"=="" powershell -NoProfile -Command "Write-Host '  GPU2 : ' -ForegroundColor !COL_HDR_PS! -NoNewline; Write-Host '!SYS_GPU2!' -ForegroundColor !COL_OPS_PS!"
powershell -NoProfile -Command "Write-Host '  DISK : ' -ForegroundColor !COL_HDR_PS! -NoNewline; Write-Host '!SYS_DISK_TYPE!  ^|  !SYS_DISK_TOTAL! total  ^|  !SYS_DISK_FREE! free' -ForegroundColor !COL_OPS_PS!"
powershell -NoProfile -Command "Write-Host '  -----------------------------------------------' -ForegroundColor !COL_HDR_PS!"
echo.
echo   Loading main menu...
timeout /t 2 /nobreak >nul

:WELCOME_SCREEN
if "!HIDE_WELCOME!"=="1" goto MAIN_MENU
cls
color !COL_OPS!
echo.
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '               WELCOME TO YTSH''S TECH UTILITY' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
echo.
echo   What this script does:
echo   - Removes unnecessary pre-installed Windows apps (Bloatware).
echo   - Disables background services that consume RAM and CPU.
echo   - Disables Windows telemetry and tracking to protect privacy.
echo.
echo   Requirements and Warnings:
echo   - Administrator privileges are required to modify system files and registry keys.
echo   - CREATE A MANUAL RESTORE POINT before making any changes.
echo   - Some changes, such as removing AppX packages, are difficult to fully reverse.
echo.
echo     Please proceed with extreme caution and research any tweaks you don't fully
echo     understand before applying them. Blindly disabling services can break Windows
echo     features. This script has already analyzed your hardware to prevent
echo     harmful tweaks. It identifies whether you are using a LAPTOP or DESKTOP, and
echo     crucially, whether your OS is installed on a traditional HDD or a modern SSD.
echo     Because certain optimizations [like disabling SysMain (HDD) or Power Throttling (LAPTOP)]
echo     can actually slow down the performance on the wrong hardware, the script uses a
echo     dynamic warning system, making the user dependency very high on this script.
if "!COLOR_THEME!"=="AMBER" (
    powershell -NoProfile -Command "Write-Host '    These system-specific warnings will be highlighted in RED.' -ForegroundColor Red"
) else (
    powershell -NoProfile -Command "Write-Host '    These system-specific warnings will be highlighted in YELLOW.' -ForegroundColor Yellow"
)
echo.
echo   HOW TO USE:
echo   - This script is controlled entirely by your keyboard. 
echo   - Every option is labeled with a Letter (e.g., A, B), a Number (e.g., 1, 45), 
echo     or a Combination (e.g., S1) on the left-hand side of the menu.
echo   - To select an option: Type the character(s) and press ENTER.
echo.
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
echo.
echo   P to proceed (Will show again on restart)
if "!COLOR_THEME!"=="AMBER" (
    powershell -NoProfile -Command "Write-Host '  D to proceed and NEVER show again (Not recommended for PC newbies)' -ForegroundColor Red"
) else (
    powershell -NoProfile -Command "Write-Host '  D to proceed and NEVER show again (Not recommended for PC newbies)' -ForegroundColor Yellow"
)
echo.
set "WCHOICE="
set /p "WCHOICE=  Select an option [P, D]: "
if /i "!WCHOICE!"=="D" (
    set "HIDE_WELCOME=1"
    call :SAVE_CONFIG
    goto MAIN_MENU
)
if /i "!WCHOICE!"=="P" goto MAIN_MENU
goto WELCOME_SCREEN

:MAIN_MENU
cls
color !COL_OPS!
set "DBLOT_CNT=0"
for /f "tokens=3" %%V in ('reg query "HKLM\SYSTEM\CurrentControlSet\Services\DiagTrack" /v Start 2^>nul') do if "%%V"=="0x4" set /a DBLOT_CNT+=1
for /f "tokens=3" %%V in ('reg query "HKCU\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo" /v Enabled 2^>nul') do if "%%V"=="0x0" set /a DBLOT_CNT+=1
for /f "tokens=3" %%V in ('reg query "HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection" /v AllowTelemetry 2^>nul') do if "%%V"=="0x0" set /a DBLOT_CNT+=1
set "DBLOT_STAT= [!C_AGG!NOT OPTIMIZED!C_RST!]"
if !DBLOT_CNT! geq 1 if !DBLOT_CNT! leq 2 set "DBLOT_STAT= [!C_BAL!PARTIALLY OPTIMIZED!C_RST!]"
if !DBLOT_CNT! equ 3 set "DBLOT_STAT= [!C_SAFE!OPTIMIZED!C_RST!]"
set "FPS_CNT=0"
for /f "tokens=3" %%V in ('reg query "HKCU\Software\Microsoft\GameBar" /v AutoGameModeEnabled 2^>nul') do if "%%V"=="0x1" set /a FPS_CNT+=1
for /f "tokens=3" %%V in ('reg query "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" /v NetworkThrottlingIndex 2^>nul') do if "%%V"=="0xffffffff" set /a FPS_CNT+=1
for /f "tokens=3" %%V in ('reg query "HKCU\Control Panel\Mouse" /v MouseSpeed 2^>nul') do if "%%V"=="0" set /a FPS_CNT+=1
set "FPS_STAT= [!C_AGG!NOT OPTIMIZED!C_RST!]"
if !FPS_CNT! geq 1 if !FPS_CNT! leq 2 set "FPS_STAT= [!C_BAL!PARTIALLY OPTIMIZED!C_RST!]"
if !FPS_CNT! equ 3 set "FPS_STAT= [!C_SAFE!OPTIMIZED!C_RST!]"
set "CLEAN_CNT=0"
if not exist "C:\Windows.old" set /a CLEAN_CNT+=1
for /f %%A in ('dir /A /B "%TEMP%" 2^>nul ^| find /c /v ""') do if %%A LSS 5 set /a CLEAN_CNT+=1
set "CLEAN_STAT= [!C_AGG!NOT OPTIMIZED!C_RST!]"
if !CLEAN_CNT! equ 1 set "CLEAN_STAT= [!C_BAL!PARTIALLY OPTIMIZED!C_RST!]"
if !CLEAN_CNT! equ 2 set "CLEAN_STAT= [!C_SAFE!OPTIMIZED!C_RST!]"
set "NET_STAT= [!C_AGG!NOT OPTIMIZED!C_RST!]"
for /f "tokens=3" %%V in ('reg query "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" /v NetworkThrottlingIndex 2^>nul') do if "%%V"=="0xffffffff" set "NET_STAT= [!C_SAFE!OPTIMIZED!C_RST!]"
set "HLT_STAT="
if exist "%TEMP%\ytsh_health_status.txt" (
    set /p HLT_RAW=<"%TEMP%\ytsh_health_status.txt"
    set "HLT_STAT= [!C_AGG!!HLT_RAW!!C_RST!]"
    if "!HLT_RAW!"=="HEALTHY" set "HLT_STAT= [!C_SAFE!!HLT_RAW!!C_RST!]"
    if "!HLT_RAW!"=="OUTDATED" set "HLT_STAT= [!C_BAL!!HLT_RAW!!C_RST!]"
)
echo.
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '    YTSH''s Tech Utility' -ForegroundColor !COL_HDR_PS!"
if "!SAFE_MODE!"=="1" (
    powershell -NoProfile -Command "Write-Host '    v1.0  | ADMINISTRATOR  | SAFE MODE: ENABLED (Advanced features locked)' -ForegroundColor !COL_HDR_PS!"
) else (
    powershell -NoProfile -Command "Write-Host '    v1.0  | ADMINISTRATOR  | SAFE MODE: DISABLED (Full access)' -ForegroundColor Yellow"
)
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
echo.
powershell -NoProfile -Command "Write-Host '  --- SYSTEM HARDWARE ---------------------------' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '  OS   : ' -ForegroundColor !COL_HDR_PS! -NoNewline; Write-Host '!SYS_OS!  [!SYS_FORM!]' -ForegroundColor !COL_OPS_PS!"
powershell -NoProfile -Command "Write-Host '  BRAND: ' -ForegroundColor !COL_HDR_PS! -NoNewline; Write-Host '!SYS_BRAND!' -ForegroundColor !COL_OPS_PS!"
powershell -NoProfile -Command "Write-Host '  CPU  : ' -ForegroundColor !COL_HDR_PS! -NoNewline; Write-Host '!SYS_CPU! (!SYS_CPU_CORES! cores, !SYS_CPU_GHZ!)' -ForegroundColor !COL_OPS_PS!"
powershell -NoProfile -Command "Write-Host '  RAM  : ' -ForegroundColor !COL_HDR_PS! -NoNewline; Write-Host '!SYS_RAM!' -ForegroundColor !COL_OPS_PS!"
powershell -NoProfile -Command "Write-Host '  GPU  : ' -ForegroundColor !COL_HDR_PS! -NoNewline; Write-Host '!SYS_GPU!' -ForegroundColor !COL_OPS_PS!"
if not "!SYS_GPU2!"=="" powershell -NoProfile -Command "Write-Host '  GPU2 : ' -ForegroundColor !COL_HDR_PS! -NoNewline; Write-Host '!SYS_GPU2!' -ForegroundColor !COL_OPS_PS!"
powershell -NoProfile -Command "Write-Host '  DISK (C://) : ' -ForegroundColor !COL_HDR_PS! -NoNewline; Write-Host '!SYS_DISK_TYPE!  |  !SYS_DISK_TOTAL! total  |  !SYS_DISK_FREE! free' -ForegroundColor !COL_OPS_PS!"
powershell -NoProfile -Command "Write-Host '  -----------------------------------------------' -ForegroundColor !COL_HDR_PS!"
echo.
powershell -NoProfile -Command "Write-Host '  SAVE ALL YOUR WORK BEFORE MAKING ANY CHANGES.' -ForegroundColor Yellow"
powershell -NoProfile -Command "Write-Host '  THIS APPLIES FOR REVERTING CHANGES TOO.' -ForegroundColor Yellow"
echo.
if /i "!DEBLOAT_MODE!"=="DEFAULT" (
    echo   M  ^>  Mode      ^(Are you new to PCs or afraid of risks? Change the Debloat UI Mode^)
) else (
    powershell -NoProfile -Command "Write-Host '   M  >  [LOCKED] Mode is currently set to: !DEBLOAT_MODE!' -ForegroundColor DarkGray"
)
echo.
echo   1  ^>  Debloat   (Choose what to remove)!DBLOT_STAT!
echo   2  ^>  Revert    (Choose what to restore)
set "_FPS_LOCK_MSG="
if /i "!DEBLOAT_MODE!"=="STUDENT" set "_FPS_LOCK_MSG=STUDENT"
if "!SAFE_MODE!"=="1" if "!_FPS_LOCK_MSG!"=="" set "_FPS_LOCK_MSG=SAFE"
if "!_FPS_LOCK_MSG!"=="STUDENT" powershell -NoProfile -Command "Write-Host '   3  >  [LOCKED] Gaming and FPS Boost (Disabled in STUDENT mode)' -ForegroundColor DarkGray"
if "!_FPS_LOCK_MSG!"=="SAFE" powershell -NoProfile -Command "Write-Host '   3  >  [LOCKED] Gaming and FPS Boost (Disabled in SAFE MODE - S > 7 to change)' -ForegroundColor DarkGray"
if "!_FPS_LOCK_MSG!"=="" echo   3  ^>  Gaming and FPS Boost ^(Choose which gaming settings fits you the best^)!FPS_STAT!
echo   4  ^>  Disk Cleanup (Safe junk removal)!CLEAN_STAT!
if "!SAFE_MODE!"=="1" (
    powershell -NoProfile -Command "Write-Host '   5  >  [LOCKED] Network Optimizations (Disabled in SAFE MODE - S > 7 to change)' -ForegroundColor DarkGray"
) else (
    echo   5  ^>  Network Optimizations!NET_STAT!
)
echo   6  ^>  System Health Check!HLT_STAT!
if "!SAFE_MODE!"=="1" (
    powershell -NoProfile -Command "Write-Host '   7  >  [LOCKED] Windows Tweaks (Disabled in SAFE MODE - S > 7 to change)' -ForegroundColor DarkGray"
) else (
    echo   7  ^>  Windows Tweaks  (Visual effects, pagefile, Windows Update)
)
echo   8  ^>  Security Tools  (Firewall check, startup scan, SMB1)
echo   9  ^>  Activate Windows (HWID - legitimate, no key needed)
echo  10  ^>  Install Software (winget - VLC, 7-Zip, Firefox and more)
echo.
echo   S  ^>  Settings  
echo   R  ^>  Export Report (Save a full summary of changes to a text file)
echo   K  ^>  Status    (Full system debloat report)
echo   U  ^>  Usage     (Disk, RAM and system dashboard)
echo   I  ^>  Info      (What this tool does)
echo   0  ^>  Exit
echo.
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
echo.
set /p "CHOICE=  Enter your choice [0-10,K,M,U,I,S,R]: "

if "%CHOICE%"=="1" goto DEBLOAT_MENU
if "%CHOICE%"=="2" goto REVERT_MENU
if "%CHOICE%"=="3" (
    if /i "!DEBLOAT_MODE!"=="STUDENT" (
        color !COL_ERR!
        echo.
        powershell -NoProfile -Command "Write-Host '  [LOCKED] Gaming and FPS Boost is disabled in STUDENT mode.' -ForegroundColor Red"
        echo.
        pause
        goto MAIN_MENU
    )
    if "!SAFE_MODE!"=="1" (
        color !COL_ERR!
        echo.
        powershell -NoProfile -Command "Write-Host '  [LOCKED] Gaming and FPS Boost is disabled in SAFE MODE.' -ForegroundColor Red"
        powershell -NoProfile -Command "Write-Host '  To change this, go to Settings ^(S^) and select Safe Mode ^(7^).' -ForegroundColor Yellow"
        echo.
        pause
        goto MAIN_MENU
    )
    goto FPS_MENU
)
if "%CHOICE%"=="4" goto CLEANUP_MENU
if "%CHOICE%"=="5" (
    if "!SAFE_MODE!"=="1" (
        color !COL_ERR!
        echo.
        powershell -NoProfile -Command "Write-Host '  [LOCKED] Network Optimizations is disabled in SAFE MODE.' -ForegroundColor Red"
        powershell -NoProfile -Command "Write-Host '  To change this, go to Settings ^(S^) and select Safe Mode ^(7^).' -ForegroundColor Yellow"
        echo.
        pause
        goto MAIN_MENU
    )
    goto NET_MENU
)
if "%CHOICE%"=="6" goto HEALTH_CHECK
if "%CHOICE%"=="7" (
    if "!SAFE_MODE!"=="1" (
        color !COL_ERR!
        echo.
        powershell -NoProfile -Command "Write-Host '  [LOCKED] Windows Tweaks is disabled in SAFE MODE.' -ForegroundColor Red"
        powershell -NoProfile -Command "Write-Host '  To change this, go to Settings ^(S^) and select Safe Mode ^(7^).' -ForegroundColor Yellow"
        echo.
        pause
        goto MAIN_MENU
    )
    goto TWEAKS_MENU
)
if "%CHOICE%"=="8" goto SECURITY_MENU
if "%CHOICE%"=="9" goto ACTIVATE_WINDOWS
if "%CHOICE%"=="10" goto INSTALL_SOFTWARE
if /i "%CHOICE%"=="K" goto CHECK_STATUS
if /i "%CHOICE%"=="M" (
    if "!DEBLOAT_MODE!"=="DEFAULT" (
        goto MODE_MENU
    ) else (
        color !COL_ERR!
        echo.
        echo  [!] The Mode Menu is locked to !DEBLOAT_MODE!.
        echo      To change modes again, go to Settings ^(S^) and select Reset Mode ^(6^).
        echo.
        pause
        goto MAIN_MENU
    )
)
if /i "%CHOICE%"=="U" goto USAGE_DASHBOARD
if /i "%CHOICE%"=="I" goto INFO_SCREEN
if /i "%CHOICE%"=="S" goto SETTINGS_MENU
if /i "%CHOICE%"=="R" goto EXPORT_REPORT
if "%CHOICE%"=="0" goto EXIT_SCRIPT

color !COL_ERR!
echo.
echo  [!] Invalid choice.
echo.
pause
goto MAIN_MENU

:MODE_MENU
cls
color !COL_OPS!
echo.
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '    SELECT MODE' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
echo.
echo   1  ^>  Default (Standard debloat menu - use Safe Mode toggle for access control)
echo   2  ^>  Newbie  (Reduced debloat options - lower impact, not a full safety guarantee)
echo   3  ^>  Student (Safe to delete EXCEPT Microsoft Teams and School apps)
echo   4  ^>  Gamer   (Safe to delete PLUS Xbox/GameBar removal options)
echo.
echo   B  ^>  Back to main menu
echo.
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
echo.
set "MCHOICE="
set /p "MCHOICE=  Select an option: "

if /i "!MCHOICE!"=="B" goto MAIN_MENU
if "!MCHOICE!"=="1" set "DEBLOAT_MODE=DEFAULT" & call :SAVE_CONFIG & goto MAIN_MENU
if "!MCHOICE!"=="2" set "DEBLOAT_MODE=NEWBIE"   & call :SAVE_CONFIG & goto MAIN_MENU
if "!MCHOICE!"=="3" set "DEBLOAT_MODE=STUDENT"  & call :SAVE_CONFIG & goto MAIN_MENU
if "!MCHOICE!"=="4" set "DEBLOAT_MODE=GAMER"    & call :SAVE_CONFIG & goto MAIN_MENU

color !COL_ERR!
echo.
echo  [!] Invalid choice.
echo.
pause
goto MODE_MENU

:FPS_MENU
cls
color !COL_OPS!
echo.
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '    FPS & GAMING OPTIMIZATIONS' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
echo.
echo   1  ^>  [!C_SAFE!SAFE!C_RST!] Enable Windows Game Mode - (Safely optimizes OS scheduling for games)
if /i "!DEBLOAT_MODE!"=="NEWBIE" (
    powershell -NoProfile -Command "Write-Host '   2  >  [LOCKED] Disable Power Throttling (Not available in NEWBIE mode)' -ForegroundColor DarkGray"
) else (
    if "!SYS_FORM!"=="LAPTOP" (
        echo   2  ^>  [!C_AGG!AGGRESSIVE!C_RST!] Disable Power Throttling - ^(LAPTOP: May severely reduce battery life^)
    ) else (
        echo   2  ^>  [!C_BAL!BALANCED!C_RST!] Disable Power Throttling - ^(Prevents CPU background downclocking^)
    )
)
echo   3  ^>  [!C_SAFE!SAFE!C_RST!] Enable Hardware-Accelerated GPU Scheduling - (Offloads UI tasks to GPU)
if /i "!DEBLOAT_MODE!"=="NEWBIE" (
    powershell -NoProfile -Command "Write-Host '   4  >  [LOCKED] Enable High Performance Power Plan (Not available in NEWBIE mode)' -ForegroundColor DarkGray"
) else (
    if "!SYS_FORM!"=="LAPTOP" (
        echo   4  ^>  [!C_AGG!AGGRESSIVE!C_RST!] Enable High Performance Power Plan - ^(LAPTOP: May cause overheating/drain^)
    ) else (
        echo   4  ^>  [!C_BAL!BALANCED!C_RST!] Enable High Performance Power Plan - ^(Locks CPU clocks higher^)
    )
)
echo   5  ^>  [!C_SAFE!SAFE!C_RST!] Disable Mouse Acceleration - (Ensures 1:1 raw mouse input for aiming)
echo   6  ^>  [!C_BAL!BALANCED!C_RST!] Disable Game DVR / Background Recording - (Frees RAM but breaks Xbox clipping)
echo   7  ^>  [!C_BAL!BALANCED!C_RST!] Disable Global Fullscreen Optimizations - (Can fix input lag in older titles)
echo   8  ^>  [!C_SAFE!SAFE!C_RST!] Optimize Network Throttling Index - (Removes multimedia network limits)
powershell -NoProfile -Command "Write-Host '   9  ^>  Apply ALL FPS Boost' -ForegroundColor Yellow"
echo   B  ^>  Back to main menu
echo.
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
echo.
set "FCHOICE="
set /p "FCHOICE=  Select an option: "

if /i "!FCHOICE!"=="B" goto MAIN_MENU

if "!FCHOICE!"=="1" (
    echo.
    call :DO_FPS_GAMEMODE
    echo.
    pause
    goto FPS_MENU
)
if "!FCHOICE!"=="2" (
    if /i "!DEBLOAT_MODE!"=="NEWBIE" (
        echo.
        powershell -NoProfile -Command "Write-Host '  [LOCKED] This option is not available in NEWBIE mode.' -ForegroundColor Red"
        echo.
        pause
        goto FPS_MENU
    )
    echo.
    call :DO_FPS_THROTTLE
    echo.
    pause
    goto FPS_MENU
)
if "!FCHOICE!"=="3" (
    echo.
    call :DO_FPS_HAGS
    echo.
    pause
    goto FPS_MENU
)
if "!FCHOICE!"=="4" (
    if /i "!DEBLOAT_MODE!"=="NEWBIE" (
        echo.
        powershell -NoProfile -Command "Write-Host '  [LOCKED] This option is not available in NEWBIE mode.' -ForegroundColor Red"
        echo.
        pause
        goto FPS_MENU
    )
    echo.
    call :DO_FPS_POWER
    echo.
    pause
    goto FPS_MENU
)
if "!FCHOICE!"=="5" (
    echo.
    call :DO_FPS_MOUSE
    echo.
    pause
    goto FPS_MENU
)
if "!FCHOICE!"=="6" (
    echo.
    call :DO_FPS_GAMEDVR
    echo.
    pause
    goto FPS_MENU
)
if "!FCHOICE!"=="7" (
    echo.
    call :DO_FPS_FSO
    echo.
    pause
    goto FPS_MENU
)
if "!FCHOICE!"=="8" (
    echo.
    call :DO_FPS_NETWORK
    echo.
    pause
    goto FPS_MENU
)
if "!FCHOICE!"=="9" (
    echo.
    call :DO_FPS_GAMEMODE
    if /i not "!DEBLOAT_MODE!"=="NEWBIE" call :DO_FPS_THROTTLE
    call :DO_FPS_HAGS
    if /i not "!DEBLOAT_MODE!"=="NEWBIE" call :DO_FPS_POWER
    call :DO_FPS_MOUSE
    call :DO_FPS_GAMEDVR
    call :DO_FPS_FSO
    call :DO_FPS_NETWORK
    echo.
    echo  =============================================
    echo   All optimizations applied. Restart recommended.
    echo  =============================================
    echo.
    pause
    goto FPS_MENU
)

color !COL_ERR!
echo.
echo  [!] Invalid choice.
echo.
pause
goto FPS_MENU

:DO_FPS_GAMEMODE
reg add "HKCU\Software\Microsoft\GameBar" /v AutoGameModeEnabled /t REG_DWORD /d 1 /f >nul 2>&1
if !errorLevel! equ 0 (
    powershell -NoProfile -Command "Write-Host '  [SUCCESS] Windows Game Mode Enabled' -ForegroundColor Green"
) else (
    powershell -NoProfile -Command "Write-Host '  [FAIL] Could not enable Game Mode.' -ForegroundColor Red"
)
exit /b 0

:DO_FPS_THROTTLE
if "!SYS_FORM!"=="LAPTOP" (
    if "!COLOR_THEME!"=="AMBER" (
        powershell -NoProfile -Command "Write-Host '  [WARNING] LAPTOP detected - disabling power throttling may reduce battery life.' -ForegroundColor Red"
    ) else (
        powershell -NoProfile -Command "Write-Host '  [WARNING] LAPTOP detected - disabling power throttling may reduce battery life.' -ForegroundColor Yellow"
    )
)
reg add "HKLM\System\CurrentControlSet\Control\Power\PowerThrottling" /v PowerThrottlingOff /t REG_DWORD /d 1 /f >nul 2>&1
if !errorLevel! equ 0 (
    powershell -NoProfile -Command "Write-Host '  [SUCCESS] Power Throttling Disabled' -ForegroundColor Green"
) else (
    powershell -NoProfile -Command "Write-Host '  [FAIL] Could not disable Power Throttling.' -ForegroundColor Red"
)
exit /b 0

:DO_FPS_HAGS
reg add "HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" /v HwSchMode /t REG_DWORD /d 2 /f >nul 2>&1
powershell -NoProfile -Command "Write-Host '  [SUCCESS] Hardware-Accelerated GPU Scheduling Enabled (If Supported)' -ForegroundColor Green"
exit /b 0

:DO_FPS_POWER
if "!SYS_FORM!"=="LAPTOP" (
    if "!COLOR_THEME!"=="AMBER" (
        powershell -NoProfile -Command "Write-Host '  [WARNING] LAPTOP detected - High Performance Power Plan may cause overheating and battery drain.' -ForegroundColor Red"
    ) else (
        powershell -NoProfile -Command "Write-Host '  [WARNING] LAPTOP detected - High Performance Power Plan may cause overheating and battery drain.' -ForegroundColor Yellow"
    )
)
powercfg -s 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c >nul 2>&1
if !errorLevel! equ 0 (
    powershell -NoProfile -Command "Write-Host '  [SUCCESS] High Performance Power Plan Enabled' -ForegroundColor Green"
) else (
    powershell -NoProfile -Command "Write-Host '  [FAIL] Could not set High Performance Power Plan.' -ForegroundColor Red"
)
exit /b 0

:DO_FPS_MOUSE
reg add "HKCU\Control Panel\Mouse" /v MouseSpeed /t REG_SZ /d 0 /f >nul 2>&1
reg add "HKCU\Control Panel\Mouse" /v MouseThreshold1 /t REG_SZ /d 0 /f >nul 2>&1
reg add "HKCU\Control Panel\Mouse" /v MouseThreshold2 /t REG_SZ /d 0 /f >nul 2>&1
powershell -NoProfile -Command "Write-Host '  [SUCCESS] Mouse Acceleration Disabled' -ForegroundColor Green"
exit /b 0

:DO_FPS_GAMEDVR
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\GameDVR" /v AppCaptureEnabled /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKCU\System\GameConfigStore" /v GameDVR_Enabled /t REG_DWORD /d 0 /f >nul 2>&1
powershell -NoProfile -Command "Write-Host '  [SUCCESS] Game DVR Background Recording Disabled' -ForegroundColor Green"
exit /b 0

:DO_FPS_FSO
reg add "HKCU\System\GameConfigStore" /v GameDVR_FSEBehaviorMode /t REG_DWORD /d 2 /f >nul 2>&1
reg add "HKCU\System\GameConfigStore" /v GameDVR_HonorUserFSEBehaviorMode /t REG_DWORD /d 1 /f >nul 2>&1
reg add "HKCU\System\GameConfigStore" /v GameDVR_DXGIHonorFSEWindowsCompatible /t REG_DWORD /d 1 /f >nul 2>&1
powershell -NoProfile -Command "Write-Host '  [SUCCESS] Global Fullscreen Optimizations Disabled' -ForegroundColor Green"
exit /b 0

:DO_FPS_NETWORK
reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" /v NetworkThrottlingIndex /t REG_DWORD /d 4294967295 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" /v SystemResponsiveness /t REG_DWORD /d 0 /f >nul 2>&1
powershell -NoProfile -Command "Write-Host '  [SUCCESS] Network Throttling Disabled & Responsiveness Optimized' -ForegroundColor Green"
exit /b 0

:NET_MENU
cls
color !COL_OPS!
echo.
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '    NETWORK OPTIMIZATIONS' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
echo.
echo   1  ^>  [!C_BAL!BALANCED!C_RST!] Disable Nagle's Algorithm - (Lowers game latency but increases packet overhead)
echo   2  ^>  [!C_SAFE!SAFE!C_RST!] Flush DNS Cache - (Safely clears stale DNS routing entries)
echo   3  ^>  [!C_BAL!BALANCED!C_RST!] Set DNS to Cloudflare (1.1.1.1) - (Bypasses ISP DNS for speed/privacy)
echo   4  ^>  [!C_BAL!BALANCED!C_RST!] Set DNS to Google (8.8.8.8) - (Bypasses ISP DNS for reliability)
echo   5  ^>  [!C_SAFE!SAFE!C_RST!] Disable Network Throttling - (Prioritizes gaming over multimedia traffic)
echo.
powershell -NoProfile -Command "Write-Host '  -----------------------------------------------' -ForegroundColor !COL_HDR_PS!"
echo.
powershell -NoProfile -Command "Write-Host '   A  ^>  Apply ALL Network Optimizations (Uses Cloudflare DNS)' -ForegroundColor Yellow"
echo   B  ^>  Back to main menu
echo.
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
echo.
set "NCHOICE="
set /p "NCHOICE=  Select an option: "

if /i "!NCHOICE!"=="B" goto MAIN_MENU

if "!NCHOICE!"=="1" (
    echo.
    call :DO_NET_NAGLE
    echo.
    pause
    goto NET_MENU
)
if "!NCHOICE!"=="2" (
    echo.
    call :DO_NET_FLUSHDNS
    echo.
    pause
    goto NET_MENU
)
if "!NCHOICE!"=="3" (
    echo.
    call :DO_NET_DNS_CLOUDFLARE
    echo.
    pause
    goto NET_MENU
)
if "!NCHOICE!"=="4" (
    echo.
    call :DO_NET_DNS_GOOGLE
    echo.
    pause
    goto NET_MENU
)
if "!NCHOICE!"=="5" (
    echo.
    call :DO_NET_THROTTLE
    echo.
    pause
    goto NET_MENU
)
if /i "!NCHOICE!"=="A" (
    echo.
    call :DO_NET_NAGLE
    call :DO_NET_FLUSHDNS
    call :DO_NET_DNS_CLOUDFLARE
    call :DO_NET_THROTTLE
    echo.
    echo  =============================================
    echo   All network optimizations applied.
    echo  =============================================
    echo.
    pause
    goto NET_MENU
)

color !COL_ERR!
echo.
echo  [!] Invalid choice.
echo.
pause
goto NET_MENU

:DO_NET_NAGLE
set "NAGLESCRIPT=%TEMP%\ytsh_nagle_%RANDOM%%RANDOM%.ps1"
(
    echo $interfaces = Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces' -ErrorAction SilentlyContinue
    echo foreach ^($iface in $interfaces^) {
    echo     try {
    echo         Set-ItemProperty -Path $iface.PSPath -Name 'TcpAckFrequency' -Value 1 -Type DWord -Force -ErrorAction Stop
    echo         Set-ItemProperty -Path $iface.PSPath -Name 'TCPNoDelay' -Value 1 -Type DWord -Force -ErrorAction Stop
    echo     } catch {}
    echo }
    echo reg add 'HKLM\SOFTWARE\Microsoft\MSMQ\Parameters' /v TCPNoDelay /t REG_DWORD /d 1 /f ^| Out-Null
    echo Write-Host "  [SUCCESS] Nagle's Algorithm Disabled (TcpAckFrequency=1, TCPNoDelay=1)" -ForegroundColor Green
) > "%NAGLESCRIPT%"
powershell -NoProfile -ExecutionPolicy Bypass -File "%NAGLESCRIPT%"
del "%NAGLESCRIPT%" >nul 2>&1
exit /b 0

:DO_NET_FLUSHDNS
ipconfig /flushdns >nul 2>&1
ipconfig /registerdns >nul 2>&1
powershell -NoProfile -Command "Write-Host '  [SUCCESS] DNS Cache Flushed and Re-registered' -ForegroundColor Green"
exit /b 0

:DO_NET_DNS_CLOUDFLARE
ping -n 1 1.1.1.1 >nul 2>&1
if !errorLevel! neq 0 (
    powershell -NoProfile -Command "Write-Host '  [FAIL] No internet connection detected. Aborting DNS change.' -ForegroundColor Red"
    exit /b 1
)
set "DNSSCRIPT=%TEMP%\ytsh_dns_cf_%RANDOM%%RANDOM%.ps1"
(
    echo $adapters = Get-NetAdapter ^| Where-Object { $_.Status -eq 'Up' }
    echo foreach ^($a in $adapters^) {
    echo     try {
    echo         Set-DnsClientServerAddress -InterfaceIndex $a.InterfaceIndex -ServerAddresses @^('1.1.1.1','1.0.0.1'^) -ErrorAction Stop
    echo         Write-Host ^("  [SUCCESS] DNS set to Cloudflare on: " + $a.Name^) -ForegroundColor Green
    echo     } catch {
    echo         Write-Host ^("  [FAIL] " + $a.Name + ": " + $_.Exception.Message^) -ForegroundColor Red
    echo     }
    echo }
) > "%DNSSCRIPT%"
powershell -NoProfile -ExecutionPolicy Bypass -File "%DNSSCRIPT%"
del "%DNSSCRIPT%" >nul 2>&1
exit /b 0

:DO_NET_DNS_GOOGLE
ping -n 1 8.8.8.8 >nul 2>&1
if !errorLevel! neq 0 (
    powershell -NoProfile -Command "Write-Host '  [FAIL] No internet connection detected. Aborting DNS change.' -ForegroundColor Red"
    exit /b 1
)
set "DNSSCRIPT=%TEMP%\ytsh_dns_gg_%RANDOM%%RANDOM%.ps1"
(
    echo $adapters = Get-NetAdapter ^| Where-Object { $_.Status -eq 'Up' }
    echo foreach ^($a in $adapters^) {
    echo     try {
    echo         Set-DnsClientServerAddress -InterfaceIndex $a.InterfaceIndex -ServerAddresses @^('8.8.8.8','8.8.4.4'^) -ErrorAction Stop
    echo         Write-Host ^("  [SUCCESS] DNS set to Google on: " + $a.Name^) -ForegroundColor Green
    echo     } catch {
    echo         Write-Host ^("  [FAIL] " + $a.Name + ": " + $_.Exception.Message^) -ForegroundColor Red
    echo     }
    echo }
) > "%DNSSCRIPT%"
powershell -NoProfile -ExecutionPolicy Bypass -File "%DNSSCRIPT%"
del "%DNSSCRIPT%" >nul 2>&1
exit /b 0

:DO_NET_THROTTLE
goto DO_FPS_NETWORK

:CLEANUP_EXIT
goto MAIN_MENU

:CLEANUP_MENU
cls
color !COL_OPS!
echo.
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '    SAFE DISK CLEANUP OPTIONS' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
echo.
echo   1  ^>  Windows Temp files
echo   2  ^>  Prefetch files
echo   3  ^>  Windows Update cache
echo   4  ^>  Delivery Optimization cache
echo   5  ^>  Windows Error Reporting dumps
echo   6  ^>  Thumbnail cache
echo   7  ^>  Recycle Bin
echo   8  ^>  Old Windows installations (Windows.old)
echo   9  ^>  Memory dump files (.dmp)
echo.
powershell -NoProfile -Command "Write-Host '   A  ^>  Apply ALL Cleanup Tasks' -ForegroundColor Yellow"
powershell -NoProfile -Command "Write-Host '   P  ^>  Preview space to be freed (scan sizes first)' -ForegroundColor Cyan"
echo   B  ^>  Back to main menu
echo.
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
echo.
set "CCHOICE="
set /p "CCHOICE=  Select an option: "

if /i "!CCHOICE!"=="B" goto CLEANUP_EXIT
if /i "!CCHOICE!"=="P" goto CLEANUP_PREVIEW_RUN
if "!CCHOICE!"=="1" goto CLEAN_OPT_1
if "!CCHOICE!"=="2" goto CLEAN_OPT_2
if "!CCHOICE!"=="3" goto CLEAN_OPT_3
if "!CCHOICE!"=="4" goto CLEAN_OPT_4
if "!CCHOICE!"=="5" goto CLEAN_OPT_5
if "!CCHOICE!"=="6" goto CLEAN_OPT_6
if "!CCHOICE!"=="7" goto CLEAN_OPT_7
if "!CCHOICE!"=="8" goto CLEAN_OPT_8
if "!CCHOICE!"=="9" goto CLEAN_OPT_9
if /i "!CCHOICE!"=="A" goto CLEAN_OPT_ALL

color !COL_ERR!
echo.
echo  [!] Invalid choice.
echo.
pause
goto CLEANUP_MENU

:CLEANUP_PREVIEW_RUN
echo.
call :CLEANUP_PREVIEW
echo.
pause
goto CLEANUP_MENU

:CLEAN_OPT_1
call :CLEAN_TEMP & pause & goto CLEANUP_MENU
:CLEAN_OPT_2
call :CLEAN_PREFETCH & pause & goto CLEANUP_MENU
:CLEAN_OPT_3
call :CLEAN_WUCACHE & pause & goto CLEANUP_MENU
:CLEAN_OPT_4
call :CLEAN_DELIVERYOPT & pause & goto CLEANUP_MENU
:CLEAN_OPT_5
call :CLEAN_WER & pause & goto CLEANUP_MENU
:CLEAN_OPT_6
call :CLEAN_THUMBCACHE & pause & goto CLEANUP_MENU
:CLEAN_OPT_7
call :CLEAN_RECYCLE & pause & goto CLEANUP_MENU
:CLEAN_OPT_8
call :CLEAN_WINDOWSOLD & pause & goto CLEANUP_MENU
:CLEAN_OPT_9
call :CLEAN_MEMDUMP & pause & goto CLEANUP_MENU

:CLEAN_OPT_ALL
call :CLEAN_TEMP
call :CLEAN_PREFETCH
call :CLEAN_WUCACHE
call :CLEAN_DELIVERYOPT
call :CLEAN_WER
call :CLEAN_THUMBCACHE
call :CLEAN_RECYCLE
call :CLEAN_WINDOWSOLD
call :CLEAN_MEMDUMP
echo.
echo  =============================================
echo   All selected disk cleanups applied.
echo  =============================================
echo.
pause
goto CLEANUP_MENU

:CLEAN_TEMP
echo.
echo  Cleaning Windows Temp files...
del /q /f /s "%TEMP%\*" >nul 2>&1
rd /s /q "%TEMP%" >nul 2>&1
md "%TEMP%" >nul 2>&1
del /q /f /s "C:\Windows\Temp\*" >nul 2>&1
rd /s /q "C:\Windows\Temp" >nul 2>&1
md "C:\Windows\Temp" >nul 2>&1
powershell -NoProfile -Command "Write-Host '  [SUCCESS] Temp files cleaned' -ForegroundColor Green"
exit /b 0

:CLEAN_PREFETCH
echo.
echo  Cleaning Prefetch files...
del /q /f /s "C:\Windows\Prefetch\*" >nul 2>&1
powershell -NoProfile -Command "Write-Host '  [SUCCESS] Prefetch files cleaned' -ForegroundColor Green"
exit /b 0

:CLEAN_WUCACHE
echo.
echo  Cleaning Windows Update cache...
net stop wuauserv >nul 2>&1
net stop bits >nul 2>&1
del /q /f /s "C:\Windows\SoftwareDistribution\Download\*" >nul 2>&1
rd /s /q "C:\Windows\SoftwareDistribution\Download" >nul 2>&1
md "C:\Windows\SoftwareDistribution\Download" >nul 2>&1
net start wuauserv >nul 2>&1
net start bits >nul 2>&1
powershell -NoProfile -Command "Write-Host '  [SUCCESS] Windows Update cache cleaned' -ForegroundColor Green"
exit /b 0

:CLEAN_DELIVERYOPT
echo.
echo  Cleaning Delivery Optimization cache...
net stop dosvc >nul 2>&1
del /q /f /s "C:\Windows\ServiceProfiles\NetworkService\AppData\Local\Microsoft\Windows\DeliveryOptimization\Cache\*" >nul 2>&1
rd /s /q "C:\Windows\ServiceProfiles\NetworkService\AppData\Local\Microsoft\Windows\DeliveryOptimization\Cache" >nul 2>&1
md "C:\Windows\ServiceProfiles\NetworkService\AppData\Local\Microsoft\Windows\DeliveryOptimization\Cache" >nul 2>&1
net start dosvc >nul 2>&1
powershell -NoProfile -Command "Write-Host '  [SUCCESS] Delivery Optimization cache cleaned' -ForegroundColor Green"
exit /b 0

:CLEAN_WER
echo.
echo  Cleaning Windows Error Reporting dumps...
del /q /f /s "C:\ProgramData\Microsoft\Windows\WER\ReportArchive\*" >nul 2>&1
del /q /f /s "C:\ProgramData\Microsoft\Windows\WER\ReportQueue\*" >nul 2>&1
powershell -NoProfile -Command "Write-Host '  [SUCCESS] Error Reporting dumps cleaned' -ForegroundColor Green"
exit /b 0

:CLEAN_THUMBCACHE
echo.
echo  Cleaning Thumbnail cache...
taskkill /f /im explorer.exe >nul 2>&1
del /f /s /q /a "%LocalAppData%\Microsoft\Windows\Explorer\thumbcache_*.db" >nul 2>&1
start explorer.exe >nul 2>&1
powershell -NoProfile -Command "Write-Host '  [SUCCESS] Thumbnail cache cleaned' -ForegroundColor Green"
exit /b 0

:CLEAN_RECYCLE
echo.
echo  Cleaning Recycle Bin...
rd /s /q %systemdrive%\$Recycle.bin >nul 2>&1
powershell -NoProfile -Command "Write-Host '  [SUCCESS] Recycle Bin emptied' -ForegroundColor Green"
exit /b 0

:CLEAN_WINDOWSOLD
echo.
echo  Cleaning Old Windows installations...
if exist "%systemdrive%\Windows.old" (
    takeown /F "%systemdrive%\Windows.old" /A /R /D Y >nul 2>&1
    icacls "%systemdrive%\Windows.old" /grant *S-1-5-32-544:F /T /C /Q >nul 2>&1
    rd /s /q "%systemdrive%\Windows.old" >nul 2>&1
    powershell -NoProfile -Command "Write-Host '  [SUCCESS] Windows.old removed' -ForegroundColor Green"
) else (
    powershell -NoProfile -Command "Write-Host '  [SKIP] Windows.old not found' -ForegroundColor DarkGray"
)
exit /b 0

:CLEAN_MEMDUMP
echo.
echo  Cleaning Memory dump files...
del /f /s /q "%systemroot%\MEMORY.DMP" >nul 2>&1
del /f /s /q "%systemroot%\Minidump\*.dmp" >nul 2>&1
powershell -NoProfile -Command "Write-Host '  [SUCCESS] Memory dump files cleaned' -ForegroundColor Green"
exit /b 0

:DEBLOAT_MENU
cls
color !COL_OPS!

set "SHOW_BAL=1"
set "SHOW_AGG=1"
set "SHOW_EDU=1"
set "SHOW_XBOX=1"

if "!DEBLOAT_MODE!"=="NEWBIE" (
    set "SHOW_BAL=0"
    set "SHOW_AGG=0"
    set "SHOW_XBOX=0"
)
if "!DEBLOAT_MODE!"=="STUDENT" (
    set "SHOW_BAL=0"
    set "SHOW_AGG=0"
    set "SHOW_EDU=0"
    set "SHOW_XBOX=0"
)
if "!DEBLOAT_MODE!"=="GAMER" (
    set "SHOW_BAL=0"
    set "SHOW_AGG=0"
    set "SHOW_XBOX=1"
)
if "!SAFE_MODE!"=="1" set "SHOW_AGG=0"
set "_WIN11=0"
echo !SYS_OS! | findstr /i "Windows 11" >nul 2>&1 && set "_WIN11=1"
set "_WIN10=0"
echo !SYS_OS! | findstr /i "Windows 10" >nul 2>&1 && set "_WIN10=1"

echo.
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
if "!SAFE_MODE!"=="1" (
    powershell -NoProfile -Command "Write-Host '    DEBLOAT OPTIONS  [MODE: !DEBLOAT_MODE! + SAFE MODE]' -ForegroundColor !COL_HDR_PS!"
) else (
    powershell -NoProfile -Command "Write-Host '    DEBLOAT OPTIONS  [MODE: !DEBLOAT_MODE!]' -ForegroundColor !COL_HDR_PS!"
)
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
echo.
powershell -NoProfile -Command "Write-Host '   --- BLOATWARE APPS ---' -ForegroundColor !COL_HDR_PS!"
echo    01  [!C_SAFE!SAFE!C_RST!] Candy Crush Saga - (OEM bloatware game)
echo    02  [!C_SAFE!SAFE!C_RST!] Microsoft Solitaire Collection - (OEM bloatware game)
echo    03  [!C_SAFE!SAFE!C_RST!] Bing News - (Unnecessary feed app)
echo    04  [!C_SAFE!SAFE!C_RST!] Bing Weather - (Unnecessary weather app)
if "!SHOW_BAL!"=="1" echo    05  [!C_BAL!BALANCED!C_RST!] Bing Search - (Removes web search from Start Menu)
if "!SHOW_XBOX!"=="1" echo    06  [!C_BAL!BALANCED!C_RST!] Xbox App - (Safe to remove unless you use Game Pass)
if "!SHOW_XBOX!"=="1" echo    07  [!C_BAL!BALANCED!C_RST!] Xbox Game Bar ^& Overlay - (Removes gaming overlay features)
if "!SHOW_XBOX!"=="1" echo    08  [!C_BAL!BALANCED!C_RST!] Xbox Identity Provider - (Needed for Xbox live login)
if "!SHOW_XBOX!"=="1" echo    09  [!C_BAL!BALANCED!C_RST!] Xbox Speech-To-Text Overlay - (Unused by most)
echo    10  [!C_SAFE!SAFE!C_RST!] Skype (built-in stub) - (Legacy messaging app)
if "!SHOW_EDU!"=="1" echo    11  [!C_SAFE!SAFE!C_RST!] Microsoft Teams (personal stub) - (Stub installer)
echo    12  [!C_SAFE!SAFE!C_RST!] Clipchamp Video Editor - (Web-based video editor)
if "!SHOW_BAL!"=="1" echo    13  [!C_BAL!BALANCED!C_RST!] Mail and Calendar - (Core Windows email client)
echo    14  [!C_SAFE!SAFE!C_RST!] People App - (Legacy contacts app)
if "!SHOW_BAL!"=="1" echo    15  [!C_BAL!BALANCED!C_RST!] Windows Maps - (Core maps application)
if "!SHOW_BAL!"=="1" echo    16  [!C_BAL!BALANCED!C_RST!] Windows Alarms ^& Clock - (Core clock application)
echo    17  [!C_SAFE!SAFE!C_RST!] Mixed Reality Portal - (VR feature unused by most)
echo    18  [!C_SAFE!SAFE!C_RST!] 3D Viewer - (Unnecessary 3D app)
echo    19  [!C_SAFE!SAFE!C_RST!] Print 3D - (Unnecessary 3D app)
echo    20  [!C_SAFE!SAFE!C_RST!] 3D Builder - (Unnecessary 3D app)
echo    21  [!C_SAFE!SAFE!C_RST!] Feedback Hub - (Microsoft telemetry collection)
echo    22  [!C_SAFE!SAFE!C_RST!] Get Help - (Microsoft support app)
echo    23  [!C_SAFE!SAFE!C_RST!] Get Started / Tips - (Windows tutorials)
echo    24  [!C_SAFE!SAFE!C_RST!] Power Automate Desktop - (Niche automation tool)
if "!SHOW_EDU!"=="1" echo    25  [!C_SAFE!SAFE!C_RST!] Microsoft To Do - (Task manager app)
if "!SHOW_BAL!"=="1" echo    26  [!C_BAL!BALANCED!C_RST!] Sticky Notes - (Core notes app)
echo    27  [!C_SAFE!SAFE!C_RST!] Office Hub (My Office) - (Office advertisement stub)
if "!SHOW_BAL!"=="1" echo    28  [!C_BAL!BALANCED!C_RST!] OneDrive Sync Stub - (Removes OneDrive cloud integration)
if "!SHOW_BAL!"=="1" echo    29  [!C_BAL!BALANCED!C_RST!] Sound Recorder - (Core audio recording app)
echo    30  [!C_SAFE!SAFE!C_RST!] Groove Music - (Legacy music player)
echo    31  [!C_SAFE!SAFE!C_RST!] Movies ^& TV - (Legacy video player)
if "!SHOW_BAL!"=="1" echo    32  [!C_BAL!BALANCED!C_RST!] Your Phone / Phone Link - (Syncs Android to PC)
if "!SHOW_BAL!"=="1" echo    33  [!C_BAL!BALANCED!C_RST!] Cortana App - (Legacy voice assistant)
if "!SHOW_EDU!"=="1" echo    34  [!C_SAFE!SAFE!C_RST!] OneNote (bundled) - (UWP version of OneNote)
echo    35  [!C_SAFE!SAFE!C_RST!] Microsoft Wallet - (Digital payment stub)
echo    36  [!C_SAFE!SAFE!C_RST!] OneConnect (Mobile Plans) - (Carrier integration stub)
if "!SHOW_BAL!"=="1" echo    37  [!C_BAL!BALANCED!C_RST!] Outlook for Windows - (New web-based email client)
if "!SHOW_AGG!"=="1" echo    38  [!C_AGG!AGGRESSIVE!C_RST!] Cortana Search Integration - (Deeply tied to Windows search)
echo    39  [!C_SAFE!SAFE!C_RST!] Microsoft Start (MSN) - (News bloatware)
echo    40  [!C_SAFE!SAFE!C_RST!] TikTok (OEM stub) - (Pure bloatware)
echo    41  [!C_SAFE!SAFE!C_RST!] Disney+ (OEM stub) - (Pure bloatware)
echo    42  [!C_SAFE!SAFE!C_RST!] Spotify (OEM stub) - (Pure bloatware)
echo    43  [!C_SAFE!SAFE!C_RST!] Facebook (OEM stub) - (Pure bloatware)
echo    44  [!C_SAFE!SAFE!C_RST!] Instagram (OEM stub) - (Pure bloatware)
echo    45  [!C_SAFE!SAFE!C_RST!] Netflix (OEM stub) - (Pure bloatware)
echo    46  [!C_SAFE!SAFE!C_RST!] Roblox (OEM stub) - (Pure bloatware)
echo    47  [!C_SAFE!SAFE!C_RST!] CandyCrush Friends (OEM stub) - (Pure bloatware)
echo    48  [!C_SAFE!SAFE!C_RST!] FarmVille (OEM stub) - (Pure bloatware)
echo    91  [!C_SAFE!SAFE!C_RST!] Bubble Witch 3 Saga (OEM stub) - (Pure bloatware)
echo    92  [!C_SAFE!SAFE!C_RST!] Farm Heroes Saga (OEM stub) - (Pure bloatware)
echo    93  [!C_SAFE!SAFE!C_RST!] Windows Camera - (Useless on most laptops/desktops)
echo    94  [!C_SAFE!SAFE!C_RST!] Microsoft Whiteboard - (Niche touchscreen collaboration tool)
echo    95  [!C_SAFE!SAFE!C_RST!] Web Media Extensions - (Rarely needed codec pack)
echo    96  [!C_SAFE!SAFE!C_RST!] HEVC Video Extension - (Paid codec stub, safe to remove)
echo    97  [!C_SAFE!SAFE!C_RST!] VP9 Video Extensions - (Rarely needed codec pack)
if "!_WIN11!"=="1" echo    98  [!C_SAFE!SAFE!C_RST!] Windows Widgets ^& News (Win11) - (Taskbar widgets/news panel)
if "!_WIN11!"=="1" echo    99  [!C_SAFE!SAFE!C_RST!] Windows Copilot Sidebar (Win11 23H2+) - (AI sidebar)
if "!_WIN10!"=="1" echo    98  [!C_SAFE!SAFE!C_RST!] Xbox Console Companion (Win10) - (Legacy Xbox app for Win10)
echo.
powershell -NoProfile -Command "Write-Host '   --- BRAND-SPECIFIC BLOATS [!SYS_BRAND!] ---' -ForegroundColor !COL_HDR_PS!"
if "!SYS_BRAND!"=="HP" (
    echo    H1  [!C_SAFE!SAFE!C_RST!] HP JumpStart - ^(HP bloatware launcher, no user value^)
    echo    H2  [!C_SAFE!SAFE!C_RST!] HP Support Assistant - ^(Telemetry tool disguised as support software^)
    echo    H3  [!C_BAL!BALANCED!C_RST!] HP Smart - ^(Only keep if you own an HP printer^)
    echo    H4  [!C_SAFE!SAFE!C_RST!] HP Quick Drop - ^(HP-specific file transfer, replaceable by any tool^)
    echo    H5  [!C_SAFE!SAFE!C_RST!] HP Audio Switch - ^(Unnecessary HP audio tray app^)
    echo    H6  [!C_SAFE!SAFE!C_RST!] HP Touchpoint Analytics - ^(Hidden background data collection by HP^)
)
if "!SYS_BRAND!"=="Dell" (
    echo    D1  [!C_BAL!BALANCED!C_RST!] Dell SupportAssist - ^(Has diagnostic value but sends telemetry^)
    echo    D2  [!C_SAFE!SAFE!C_RST!] Dell Digital Delivery - ^(Auto-downloads extra Dell software silently^)
    echo    D3  [!C_SAFE!SAFE!C_RST!] Dell Update - ^(Redundant alongside Windows Update^)
    if "!SYS_FORM!"=="LAPTOP" (
        echo    D4  [!C_SAFE!SAFE!C_RST!] Dell Mobile Connect - ^(Phone mirroring, niche use case^)
    )
    echo    D5  [!C_SAFE!SAFE!C_RST!] MyDell - ^(Dell settings/upsell hub^)
    echo    D6  [!C_SAFE!SAFE!C_RST!] Dell Customer Connect - ^(Dell account and feedback stub^)
)
if "!SYS_BRAND!"=="Lenovo" (
    echo    L1  [!C_BAL!BALANCED!C_RST!] Lenovo Vantage - ^(Has useful features but heavy; remove with caution^)
    echo    L2  [!C_SAFE!SAFE!C_RST!] Lenovo Now / Settings App - ^(Redundant OEM settings stub^)
    echo    L3  [!C_SAFE!SAFE!C_RST!] Lenovo Companion ^(legacy^) - ^(Older Lenovo helper app^)
    echo    L4  [!C_SAFE!SAFE!C_RST!] WinZip ^(Lenovo bundle^) - ^(Paid archiver trial, 7-Zip is free^)
    echo    L5  [!C_SAFE!SAFE!C_RST!] McAfee ^(Lenovo bundle^) - ^(Trial antivirus, can slow boot significantly^)
)
if "!SYS_BRAND!"=="ASUS" (
    if "!SYS_FORM!"=="LAPTOP" (
        echo    AS1  [!C_BAL!BALANCED!C_RST!] MyASUS - ^(Has some useful device features, but phones home^)
    )
    echo    AS2  [!C_SAFE!SAFE!C_RST!] McAfee ^(ASUS bundle^) - ^(Trial antivirus bloat^)
    echo    AS3  [!C_SAFE!SAFE!C_RST!] ASUS Live Update - ^(OEM updater, largely redundant^)
)
if "!SYS_BRAND!"=="Acer" (
    echo    AC1  [!C_BAL!BALANCED!C_RST!] Acer Care Center - ^(Some diagnostic value but bloated^)
    echo    AC2  [!C_SAFE!SAFE!C_RST!] McAfee ^(Acer bundle^) - ^(Trial antivirus bloat^)
    echo    AC3  [!C_SAFE!SAFE!C_RST!] Acer Collection - ^(Acer bloatware launcher^)
    echo    AC4  [!C_SAFE!SAFE!C_RST!] Acer Portal - ^(Acer account and content hub^)
)
if "!SYS_BRAND!"=="MSI" (
    echo    MS1  [!C_BAL!BALANCED!C_RST!] MSI Center / Dragon Center - ^(Useful for RGB/fans but very heavy^)
    echo    MS2  [!C_SAFE!SAFE!C_RST!] McAfee ^(MSI bundle^) - ^(Trial antivirus bloat^)
    echo    MS3  [!C_SAFE!SAFE!C_RST!] MSI App Player - ^(Mobile emulator stub^)
)
if "!SYS_BRAND!"=="Samsung" (
    if "!SYS_FORM!"=="LAPTOP" (
        echo    SA1  [!C_BAL!BALANCED!C_RST!] Samsung Settings - ^(Some useful Galaxy Book features^)
    )
    echo    SA2  [!C_SAFE!SAFE!C_RST!] McAfee ^(Samsung bundle^) - ^(Trial antivirus bloat^)
    echo    SA3  [!C_SAFE!SAFE!C_RST!] Samsung Notes - ^(Redundant with Notepad and Sticky Notes^)
)
if "!SYS_BRAND!"=="Microsoft" (
    if "!SYS_FORM!"=="LAPTOP" (
        echo    SU1  [!C_BAL!BALANCED!C_RST!] Surface App - ^(Keep if you use Surface device features^)
        echo    SU2  [!C_SAFE!SAFE!C_RST!] Surface Hub - ^(Enterprise collaboration tool, unused by most^)
    )
)
if "!SYS_BRAND!"=="Unknown" (
    powershell -NoProfile -Command "Write-Host '  Brand not detected. Check Main Menu BRAND line.' -ForegroundColor DarkGray"
)
echo    49  [!C_SAFE!SAFE!C_RST!] DiagTrack - (Disables core telemetry gathering)
echo    50  [!C_SAFE!SAFE!C_RST!] WMPNetworkSvc - (Disables Media Player network sharing)
echo    51  [!C_SAFE!SAFE!C_RST!] RemoteRegistry - (Security risk if left enabled)
echo    52  [!C_SAFE!SAFE!C_RST!] Fax - (Legacy fax service)
if "!SHOW_BAL!"=="1" echo    53  [!C_BAL!BALANCED!C_RST!] WerSvc - (Disables Windows Error Reporting prompts)
echo    54  [!C_SAFE!SAFE!C_RST!] MapsBroker - (Disables offline maps downloading)
echo    55  [!C_SAFE!SAFE!C_RST!] RetailDemo - (Disables retail store demo mode)
if "!SHOW_XBOX!"=="1" echo    56  [!C_BAL!BALANCED!C_RST!] XblAuthManager - (Breaks Xbox Live login)
if "!SHOW_XBOX!"=="1" echo    57  [!C_BAL!BALANCED!C_RST!] XblGameSave - (Breaks Xbox cloud saves)
if "!SHOW_XBOX!"=="1" echo    58  [!C_BAL!BALANCED!C_RST!] XboxNetApiSvc - (Breaks Xbox multiplayer networking)
if "!SHOW_XBOX!"=="1" echo    59  [!C_BAL!BALANCED!C_RST!] XboxGipSvc - (Breaks some Xbox controller features)
echo    60  [!C_SAFE!SAFE!C_RST!] wisvc - (Disables Windows Insider telemetry)
if "!SHOW_AGG!"=="1" echo    61  [!C_AGG!AGGRESSIVE!C_RST!] WSearch - (Search Indexer) [WARNING: breaks File Explorer search]
if "!SHOW_BAL!"=="1" echo    62  [!C_BAL!BALANCED!C_RST!] lfsvc - (Disables Geolocation services)
if "!SHOW_BAL!"=="1" echo    63  [!C_BAL!BALANCED!C_RST!] SharedAccess - (Disables Internet Connection Sharing)
echo    64  [!C_SAFE!SAFE!C_RST!] TrkWks - (Distributed Link Tracking, safe for home users)
if "!SHOW_BAL!"=="1" echo    65  [!C_BAL!BALANCED!C_RST!] WbioSrvc - (Breaks Windows Hello fingerprint/face login)
if "!SHOW_BAL!"=="1" echo    66  [!C_BAL!BALANCED!C_RST!] icssvc - (Breaks Mobile Hotspot sharing)
echo    67  [!C_SAFE!SAFE!C_RST!] PhoneSvc - (Disables phone linkage state)
echo    68  [!C_SAFE!SAFE!C_RST!] SmsRouter - (Disables SMS routing rules)
if "!SHOW_BAL!"=="1" echo    69  [!C_BAL!BALANCED!C_RST!] TabletInputService - (Breaks touch keyboard and pen input)
echo    70  [!C_SAFE!SAFE!C_RST!] WpcMonSvc - (Disables Microsoft Family Parental Controls)
if "!SHOW_BAL!"=="1" echo    71  [!C_BAL!BALANCED!C_RST!] PrintNotify - (Disables printer status notifications)
if "!SHOW_BAL!"=="1" echo    72  [!C_BAL!BALANCED!C_RST!] PcaSvc - (Disables Program Compatibility Assistant)
echo    73  [!C_SAFE!SAFE!C_RST!] HomeGroupListener - (Legacy networking feature)
echo    74  [!C_SAFE!SAFE!C_RST!] HomeGroupProvider - (Legacy networking feature)
echo.
powershell -NoProfile -Command "Write-Host '   --- TELEMETRY & PRIVACY ---' -ForegroundColor !COL_HDR_PS!"
echo    75  [!C_SAFE!SAFE!C_RST!] Diagnostic Data Collection - (Blocks MS diagnostic uploads)
echo    76  [!C_SAFE!SAFE!C_RST!] Advertising ID - (Stops personalized ads across apps)
echo    77  [!C_SAFE!SAFE!C_RST!] Tailored Experiences - (Stops targeted tips/recommendations)
echo    78  [!C_SAFE!SAFE!C_RST!] Feedback Notifications - (Stops 'How is Windows?' popups)
if "!SHOW_BAL!"=="1" echo    79  [!C_BAL!BALANCED!C_RST!] Activity History / Timeline - (Stops tracking recent files/apps)
echo    80  [!C_SAFE!SAFE!C_RST!] App Launch Tracking - (Stops Start Menu frequency tracking)
if "!SHOW_BAL!"=="1" echo    81  [!C_BAL!BALANCED!C_RST!] Location Tracking - (Stops system-wide location logging)
echo    82  [!C_SAFE!SAFE!C_RST!] AppCompat Telemetry - (Stops app usage telemetry)
echo    83  [!C_SAFE!SAFE!C_RST!] Windows Consumer Features - (Stops auto-installing bloatware)
echo    84  [!C_SAFE!SAFE!C_RST!] Customer Experience Improvement Tasks - (Disables background CEIP tasks)
echo    85  [!C_SAFE!SAFE!C_RST!] Handwriting Personalization Data - (Stops ink data collection)
echo    86  [!C_SAFE!SAFE!C_RST!] Typing Insights Data Collection - (Stops keystroke analytics)
echo    87  [!C_SAFE!SAFE!C_RST!] Speech Personalization Data - (Stops voice recording uploads)
echo    88  [!C_SAFE!SAFE!C_RST!] Wi-Fi Sense - (Stops auto-connecting to open hotspots)
echo.
powershell -NoProfile -Command "Write-Host '   --- RAM OPTIMIZATIONS ---' -ForegroundColor !COL_HDR_PS!"
if "!SHOW_BAL!"=="1" echo    89  [!C_BAL!BALANCED!C_RST!] Disable UWP Background Apps - (Prevents store apps from running minimized)
if "!SYS_DISK_TYPE!"=="HDD" (
    if "!SHOW_AGG!"=="1" echo    90  [!C_AGG!AGGRESSIVE!C_RST!] Disable SysMain / Superfetch - [WARNING: HDD detected - may SLOW your PC]
) else (
    echo    90  [!C_SAFE!SAFE!C_RST!] Disable SysMain / Superfetch - (SSD/NVMe detected - safe to free RAM)
)
echo.
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
echo.
if "!DEBLOAT_MODE!"=="DEFAULT" (
    powershell -NoProfile -Command "Write-Host '   --- PRESETS ---' -ForegroundColor !COL_HDR_PS!"
    echo    P1  Microsoft Games      (Solitaire, Xbox, OEM Stubs)
    echo    P2  School / Work Bloat  (Teams, OneNote, To Do, Hub)
    echo    P3  3D and Mixed Reality (3D Viewer, Print 3D, Builder, MR)
    echo    P4  Privacy Pack         (All telemetry and tracking options 75-88)
    echo    P5  Bing / News / Cortana(Bing News, Weather, Search, MSN, Cortana)
    echo    P6  Media and Music      (Groove, Movies+TV, Sound Recorder, Clipchamp)
    echo    P7  Communication Apps   (Skype, Teams, Mail, People, Phone Link)
    if "!SYS_DISK_TYPE!"=="HDD" (
               if "!COLOR_THEME!"=="AMBER" (
                   powershell -NoProfile -Command "Write-Host '    P8  Performance Pack  [WARNING: HDD detected - SysMain disable included, may SLOW your PC]' -ForegroundColor Red"
               ) else (
                   powershell -NoProfile -Command "Write-Host '    P8  Performance Pack  [WARNING: HDD detected - SysMain disable included, may SLOW your PC]' -ForegroundColor Yellow"
               )
           ) else (
               echo    P8  Performance Pack     ^(Background Apps, SysMain, key RAM services^)
           )
    echo.
    powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
    echo.
    powershell -NoProfile -Command "Write-Host '   A   ALL OF THE ABOVE (Full Debloat Everything)' -ForegroundColor Yellow"
    echo.
)
echo     B  ^>  Back to main menu
echo.
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
echo.
set "DCHOICE="
set /p "DCHOICE=  Enter option number (or A for ALL, P1-P8 for Presets [DEFAULT only]): "

if /i "!DCHOICE!"=="B" goto MAIN_MENU
if /i "!DCHOICE!"=="A" goto DEBLOAT_ALL_MODEAWARE
if /i "!DCHOICE!"=="P1" (
    if not "!DEBLOAT_MODE!"=="DEFAULT" goto PRESET_MODE_BLOCKED
    goto DO_PRESET_GAMES
)
if /i "!DCHOICE!"=="P2" (
    if not "!DEBLOAT_MODE!"=="DEFAULT" goto PRESET_MODE_BLOCKED
    goto DO_PRESET_SCHOOL
)
if /i "!DCHOICE!"=="P3" (
    if not "!DEBLOAT_MODE!"=="DEFAULT" goto PRESET_MODE_BLOCKED
    goto DO_PRESET_3D
)
if /i "!DCHOICE!"=="P4" (
    if not "!DEBLOAT_MODE!"=="DEFAULT" goto PRESET_MODE_BLOCKED
    goto DO_PRESET_PRIVACY
)
if /i "!DCHOICE!"=="P5" (
    if not "!DEBLOAT_MODE!"=="DEFAULT" goto PRESET_MODE_BLOCKED
    goto DO_PRESET_BING
)
if /i "!DCHOICE!"=="P6" (
    if not "!DEBLOAT_MODE!"=="DEFAULT" goto PRESET_MODE_BLOCKED
    goto DO_PRESET_MEDIA
)
if /i "!DCHOICE!"=="P7" (
    if not "!DEBLOAT_MODE!"=="DEFAULT" goto PRESET_MODE_BLOCKED
    goto DO_PRESET_COMMS
)
if /i "!DCHOICE!"=="P8" (
    if not "!DEBLOAT_MODE!"=="DEFAULT" goto PRESET_MODE_BLOCKED
    goto DO_PRESET_PERF
)
if "!DCHOICE!"=="89" goto DO_RAM_BGAPPS
if "!DCHOICE!"=="90" (
    if "!SAFE_MODE!"=="1" if "!SYS_DISK_TYPE!"=="HDD" (
        color !COL_ERR!
        echo.
        powershell -NoProfile -Command "Write-Host '  [SAFE MODE] Option 90 is AGGRESSIVE on HDD and is blocked.' -ForegroundColor Red"
        powershell -NoProfile -Command "Write-Host '  Disable Safe Mode in Settings ^(S ^> 7^) to access it.' -ForegroundColor Yellow"
        echo.
        pause
        goto DEBLOAT_MENU
    )
    set "DSVC=SysMain"
    goto DO_SINGLE_SVC
)
if "!DCHOICE!"=="91" set "DPKG=STUB_BUBBLEWITCH"                 & goto DO_SINGLE_STUB
if "!DCHOICE!"=="92" set "DPKG=STUB_FARMHEROES"                  & goto DO_SINGLE_STUB
if "!DCHOICE!"=="93" set "DPKG=Microsoft.WindowsCamera"          & goto DO_SINGLE_APP
if "!DCHOICE!"=="94" set "DPKG=Microsoft.Whiteboard"             & goto DO_SINGLE_APP
if "!DCHOICE!"=="95" set "DPKG=Microsoft.WebMediaExtensions"     & goto DO_SINGLE_APP
if "!DCHOICE!"=="96" set "DPKG=Microsoft.HEVCVideoExtension"     & goto DO_SINGLE_APP
if "!DCHOICE!"=="97" set "DPKG=Microsoft.VP9VideoExtensions"     & goto DO_SINGLE_APP
if "!DCHOICE!"=="98" (
    if "!_WIN11!"=="1" set "DPKG=MicrosoftWindows.Client.WebExperience" & goto DO_SINGLE_APP
    if "!_WIN10!"=="1" set "DPKG=Microsoft.XboxApp"                     & goto DO_SINGLE_APP
)
if "!DCHOICE!"=="99" set "DPKG=STUB_COPILOT"                     & goto DO_BRAND_APP
rem --- HP ---
if /i "!DCHOICE!"=="H1" set "DPKG=BRAND_HP_JUMPSTART"      & goto DO_BRAND_APP
if /i "!DCHOICE!"=="H2" set "DPKG=BRAND_HP_SUPPORTASSIST"  & goto DO_BRAND_APP
if /i "!DCHOICE!"=="H3" set "DPKG=BRAND_HP_SMART"          & goto DO_BRAND_APP
if /i "!DCHOICE!"=="H4" set "DPKG=BRAND_HP_QUICKDROP"      & goto DO_BRAND_APP
if /i "!DCHOICE!"=="H5" set "DPKG=BRAND_HP_AUDIOSWITCH"    & goto DO_BRAND_APP
if /i "!DCHOICE!"=="H6" set "DPKG=BRAND_HP_TOUCHPOINT"     & goto DO_BRAND_APP
rem --- Dell ---
if /i "!DCHOICE!"=="D1" set "DPKG=BRAND_DELL_SUPPORTASSIST" & goto DO_BRAND_APP
if /i "!DCHOICE!"=="D2" set "DPKG=BRAND_DELL_DELIVERY"      & goto DO_BRAND_APP
if /i "!DCHOICE!"=="D3" set "DPKG=BRAND_DELL_UPDATE"        & goto DO_BRAND_APP
if /i "!DCHOICE!"=="D4" set "DPKG=BRAND_DELL_MOBILECON"     & goto DO_BRAND_APP
if /i "!DCHOICE!"=="D5" set "DPKG=BRAND_DELL_MYDELL"        & goto DO_BRAND_APP
if /i "!DCHOICE!"=="D6" set "DPKG=BRAND_DELL_CUSTCON"       & goto DO_BRAND_APP
rem --- Lenovo ---
if /i "!DCHOICE!"=="L1" set "DPKG=BRAND_LENOVO_VANTAGE"    & goto DO_BRAND_APP
if /i "!DCHOICE!"=="L2" set "DPKG=BRAND_LENOVO_SETTINGS"   & goto DO_BRAND_APP
if /i "!DCHOICE!"=="L3" set "DPKG=BRAND_LENOVO_COMPANION"  & goto DO_BRAND_APP
if /i "!DCHOICE!"=="L4" set "DPKG=BRAND_LENOVO_WINZIP"     & goto DO_BRAND_APP
if /i "!DCHOICE!"=="L5" set "DPKG=BRAND_MCAFEE"            & goto DO_BRAND_APP
rem --- ASUS ---
if /i "!DCHOICE!"=="AS1" set "DPKG=BRAND_ASUS_MYASUS"      & goto DO_BRAND_APP
if /i "!DCHOICE!"=="AS2" set "DPKG=BRAND_MCAFEE"           & goto DO_BRAND_APP
if /i "!DCHOICE!"=="AS3" set "DPKG=BRAND_ASUS_LIVEUPDATE"  & goto DO_BRAND_APP
rem --- Acer ---
if /i "!DCHOICE!"=="AC1" set "DPKG=BRAND_ACER_CARECENTER"  & goto DO_BRAND_APP
if /i "!DCHOICE!"=="AC2" set "DPKG=BRAND_MCAFEE"           & goto DO_BRAND_APP
if /i "!DCHOICE!"=="AC3" set "DPKG=BRAND_ACER_COLLECTION"  & goto DO_BRAND_APP
if /i "!DCHOICE!"=="AC4" set "DPKG=BRAND_ACER_PORTAL"      & goto DO_BRAND_APP
rem --- MSI ---
if /i "!DCHOICE!"=="MS1" set "DPKG=BRAND_MSI_CENTER"       & goto DO_BRAND_APP

if "!DCHOICE!"=="01" set "DPKG=*CandyCrush*"                           & goto DO_SINGLE_STUB
if "!DCHOICE!"=="1"  set "DPKG=*CandyCrush*"                           & goto DO_SINGLE_STUB
if "!DCHOICE!"=="02" set "DPKG=Microsoft.MicrosoftSolitaireCollection" & goto DO_SINGLE_APP
if "!DCHOICE!"=="2"  set "DPKG=Microsoft.MicrosoftSolitaireCollection" & goto DO_SINGLE_APP
if "!DCHOICE!"=="03" set "DPKG=Microsoft.BingNews" & goto DO_SINGLE_APP
if "!DCHOICE!"=="3"  set "DPKG=Microsoft.BingNews" & goto DO_SINGLE_APP
if "!DCHOICE!"=="04" set "DPKG=Microsoft.BingWeather" & goto DO_SINGLE_APP
if "!DCHOICE!"=="4"  set "DPKG=Microsoft.BingWeather" & goto DO_SINGLE_APP
if "!DCHOICE!"=="05" set "DPKG=Microsoft.BingSearch" & goto DO_SINGLE_APP
if "!DCHOICE!"=="5"  set "DPKG=Microsoft.BingSearch" & goto DO_SINGLE_APP
if "!DCHOICE!"=="06" set "DPKG=Microsoft.GamingApp" & goto DO_SINGLE_APP
if "!DCHOICE!"=="6"  set "DPKG=Microsoft.GamingApp" & goto DO_SINGLE_APP
if "!DCHOICE!"=="07" set "DPKG=XBOX_OVERLAY" & goto DO_XBOX_OVERLAY
if "!DCHOICE!"=="7"  set "DPKG=XBOX_OVERLAY" & goto DO_XBOX_OVERLAY
if "!DCHOICE!"=="08" set "DPKG=Microsoft.XboxIdentityProvider" & goto DO_SINGLE_APP
if "!DCHOICE!"=="8"  set "DPKG=Microsoft.XboxIdentityProvider" & goto DO_SINGLE_APP
if "!DCHOICE!"=="09" set "DPKG=Microsoft.XboxSpeechToTextOverlay" & goto DO_SINGLE_APP
if "!DCHOICE!"=="9"  set "DPKG=Microsoft.XboxSpeechToTextOverlay" & goto DO_SINGLE_APP
if "!DCHOICE!"=="10" set "DPKG=Microsoft.SkypeApp" & goto DO_SINGLE_APP
if "!DCHOICE!"=="11" set "DPKG=MicrosoftTeams" & goto DO_SINGLE_APP
if "!DCHOICE!"=="12" set "DPKG=Clipchamp.Clipchamp" & goto DO_SINGLE_APP
if "!DCHOICE!"=="13" set "DPKG=Microsoft.WindowsCommunicationsApps" & goto DO_SINGLE_APP
if "!DCHOICE!"=="14" set "DPKG=Microsoft.People" & goto DO_SINGLE_APP
if "!DCHOICE!"=="15" set "DPKG=Microsoft.WindowsMaps" & goto DO_SINGLE_APP
if "!DCHOICE!"=="16" set "DPKG=Microsoft.WindowsAlarms" & goto DO_SINGLE_APP
if "!DCHOICE!"=="17" set "DPKG=Microsoft.MixedReality.Portal" & goto DO_SINGLE_APP
if "!DCHOICE!"=="18" set "DPKG=Microsoft.Microsoft3DViewer" & goto DO_SINGLE_APP
if "!DCHOICE!"=="19" set "DPKG=Microsoft.Print3D" & goto DO_SINGLE_APP
if "!DCHOICE!"=="20" set "DPKG=Microsoft.3DBuilder" & goto DO_SINGLE_APP
if "!DCHOICE!"=="21" set "DPKG=Microsoft.WindowsFeedbackHub" & goto DO_SINGLE_APP
if "!DCHOICE!"=="22" set "DPKG=Microsoft.GetHelp" & goto DO_SINGLE_APP
if "!DCHOICE!"=="23" set "DPKG=Microsoft.Getstarted" & goto DO_SINGLE_APP
if "!DCHOICE!"=="24" set "DPKG=Microsoft.PowerAutomateDesktop" & goto DO_SINGLE_APP
if "!DCHOICE!"=="25" set "DPKG=Microsoft.Todos" & goto DO_SINGLE_APP
if "!DCHOICE!"=="26" set "DPKG=Microsoft.MicrosoftStickyNotes" & goto DO_SINGLE_APP
if "!DCHOICE!"=="27" set "DPKG=Microsoft.MicrosoftOfficeHub" & goto DO_SINGLE_APP
if "!DCHOICE!"=="28" set "DPKG=Microsoft.OneDriveSync" & goto DO_SINGLE_APP
if "!DCHOICE!"=="29" set "DPKG=Microsoft.WindowsSoundRecorder" & goto DO_SINGLE_APP
if "!DCHOICE!"=="30" set "DPKG=Microsoft.ZuneMusic" & goto DO_SINGLE_APP
if "!DCHOICE!"=="31" set "DPKG=Microsoft.ZuneVideo" & goto DO_SINGLE_APP
if "!DCHOICE!"=="32" set "DPKG=Microsoft.YourPhone" & goto DO_SINGLE_APP
if "!DCHOICE!"=="33" set "DPKG=Microsoft.Cortana" & goto DO_SINGLE_APP
if "!DCHOICE!"=="34" set "DPKG=Microsoft.Office.OneNote" & goto DO_SINGLE_APP
if "!DCHOICE!"=="35" set "DPKG=Microsoft.Wallet" & goto DO_SINGLE_APP
if "!DCHOICE!"=="36" set "DPKG=Microsoft.OneConnect" & goto DO_SINGLE_APP
if "!DCHOICE!"=="37" set "DPKG=Microsoft.OutlookForWindows" & goto DO_SINGLE_APP
if "!DCHOICE!"=="38" (
    if "!SAFE_MODE!"=="1" (
        color !COL_ERR!
        echo.
        powershell -NoProfile -Command "Write-Host '  [SAFE MODE] Option 38 is AGGRESSIVE and is blocked.' -ForegroundColor Red"
        powershell -NoProfile -Command "Write-Host '  Disable Safe Mode in Settings ^(S ^> 7^) to access it.' -ForegroundColor Yellow"
        echo.
        pause
        goto DEBLOAT_MENU
    )
    set "DPKG=Microsoft.549981C3F5F10"
    goto DO_SINGLE_APP
)
if "!DCHOICE!"=="39" set "DPKG=Microsoft.MicrosoftStart" & goto DO_SINGLE_APP
if "!DCHOICE!"=="40" set "DPKG=STUB_TIKTOK" & goto DO_SINGLE_STUB
if "!DCHOICE!"=="41" set "DPKG=STUB_DISNEY" & goto DO_SINGLE_STUB
if "!DCHOICE!"=="42" set "DPKG=STUB_SPOTIFY" & goto DO_SINGLE_STUB
if "!DCHOICE!"=="43" set "DPKG=STUB_FACEBOOK" & goto DO_SINGLE_STUB
if "!DCHOICE!"=="44" set "DPKG=STUB_INSTAGRAM" & goto DO_SINGLE_STUB
if "!DCHOICE!"=="45" set "DPKG=STUB_NETFLIX" & goto DO_SINGLE_STUB
if "!DCHOICE!"=="46" set "DPKG=STUB_ROBLOX" & goto DO_SINGLE_STUB
if "!DCHOICE!"=="47" set "DPKG=STUB_CANDYCRUSH" & goto DO_SINGLE_STUB
if "!DCHOICE!"=="48" set "DPKG=STUB_FARMVILLE" & goto DO_SINGLE_STUB
if "!DCHOICE!"=="49" set "DSVC=DiagTrack" & goto DO_SINGLE_SVC
if "!DCHOICE!"=="50" set "DSVC=WMPNetworkSvc" & goto DO_SINGLE_SVC
if "!DCHOICE!"=="51" set "DSVC=RemoteRegistry" & goto DO_SINGLE_SVC
if "!DCHOICE!"=="52" set "DSVC=Fax" & goto DO_SINGLE_SVC
if "!DCHOICE!"=="53" set "DSVC=WerSvc" & goto DO_SINGLE_SVC
if "!DCHOICE!"=="54" set "DSVC=MapsBroker" & goto DO_SINGLE_SVC
if "!DCHOICE!"=="55" set "DSVC=RetailDemo" & goto DO_SINGLE_SVC
if "!DCHOICE!"=="56" set "DSVC=XblAuthManager" & goto DO_SINGLE_SVC
if "!DCHOICE!"=="57" set "DSVC=XblGameSave" & goto DO_SINGLE_SVC
if "!DCHOICE!"=="58" set "DSVC=XboxNetApiSvc" & goto DO_SINGLE_SVC
if "!DCHOICE!"=="59" set "DSVC=XboxGipSvc" & goto DO_SINGLE_SVC
if "!DCHOICE!"=="60" set "DSVC=wisvc" & goto DO_SINGLE_SVC
if "!DCHOICE!"=="61" (
    if "!SAFE_MODE!"=="1" (
        color !COL_ERR!
        echo.
        powershell -NoProfile -Command "Write-Host '  [SAFE MODE] Option 61 ^(WSearch^) is AGGRESSIVE and is blocked.' -ForegroundColor Red"
        powershell -NoProfile -Command "Write-Host '  Disable Safe Mode in Settings ^(S ^> 7^) to access it.' -ForegroundColor Yellow"
        echo.
        pause
        goto DEBLOAT_MENU
    )
    set "DSVC=WSearch"
    goto DO_SINGLE_SVC
)
if "!DCHOICE!"=="62" set "DSVC=lfsvc" & goto DO_SINGLE_SVC
if "!DCHOICE!"=="63" set "DSVC=SharedAccess" & goto DO_SINGLE_SVC
if "!DCHOICE!"=="64" set "DSVC=TrkWks" & goto DO_SINGLE_SVC
if "!DCHOICE!"=="65" set "DSVC=WbioSrvc" & goto DO_SINGLE_SVC
if "!DCHOICE!"=="66" set "DSVC=icssvc" & goto DO_SINGLE_SVC
if "!DCHOICE!"=="67" set "DSVC=PhoneSvc" & goto DO_SINGLE_SVC
if "!DCHOICE!"=="68" set "DSVC=SmsRouter" & goto DO_SINGLE_SVC
if "!DCHOICE!"=="69" set "DSVC=TabletInputService" & goto DO_SINGLE_SVC
if "!DCHOICE!"=="70" set "DSVC=WpcMonSvc" & goto DO_SINGLE_SVC
if "!DCHOICE!"=="71" set "DSVC=PrintNotify" & goto DO_SINGLE_SVC
if "!DCHOICE!"=="72" set "DSVC=PcaSvc" & goto DO_SINGLE_SVC
if "!DCHOICE!"=="73" set "DSVC=HomeGroupListener" & goto DO_SINGLE_SVC
if "!DCHOICE!"=="74" set "DSVC=HomeGroupProvider" & goto DO_SINGLE_SVC
if "!DCHOICE!"=="75" goto DO_TEL_DIAGDATA
if "!DCHOICE!"=="76" goto DO_TEL_ADVID
if "!DCHOICE!"=="77" goto DO_TEL_TAILORED
if "!DCHOICE!"=="78" goto DO_TEL_FEEDBACK
if "!DCHOICE!"=="79" goto DO_TEL_ACTIVITY
if "!DCHOICE!"=="80" goto DO_TEL_APPTRACK
if "!DCHOICE!"=="81" goto DO_TEL_LOCATION
if "!DCHOICE!"=="82" goto DO_TEL_APPCOMPAT
if "!DCHOICE!"=="83" goto DO_TEL_CONSUMER
if "!DCHOICE!"=="84" goto DO_TEL_TASKS
if "!DCHOICE!"=="85" goto DO_TEL_HANDWRITING
if "!DCHOICE!"=="86" goto DO_TEL_TYPING
if "!DCHOICE!"=="87" goto DO_TEL_SPEECH
if "!DCHOICE!"=="88" goto DO_TEL_WIFISENSE

powershell -NoProfile -Command "Write-Host '  [!] Invalid option.' -ForegroundColor Red"
echo.
pause
goto DEBLOAT_MENU

:DO_PRESET_GAMES
cls
color !COL_OPS!
echo.
echo  =============================================
echo   Applying Preset: Microsoft Games
echo  =============================================
echo.
echo   What am I about to do?
echo    * Remove Solitaire Collection, Gaming App, Xbox Apps, Xbox Overlay
echo    * Remove OEM Games (Candy Crush, FarmVille, Roblox)
echo.
set "CONFIRM="
set /p "CONFIRM=  Type YES to continue or NO to cancel: "
if /i not "!CONFIRM!"=="YES" goto DEBLOAT_MENU
call :CREATE_RESTORE_POINT_SILENT
set "PRESETSCRIPT=%TEMP%\ytsh_preset_%RANDOM%%RANDOM%.ps1"
if exist "%PRESETSCRIPT%" del "%PRESETSCRIPT%" >nul 2>&1
>>"%PRESETSCRIPT%" echo $pkgs = @^('Microsoft.MicrosoftSolitaireCollection', 'Microsoft.GamingApp', 'Microsoft.XboxApp', 'Microsoft.XboxGameOverlay', 'Microsoft.XboxGamingOverlay', 'Microsoft.XboxIdentityProvider', 'Microsoft.XboxSpeechToTextOverlay'^)
>>"%PRESETSCRIPT%" echo foreach ^($pkg in $pkgs^) { Get-AppxPackage -Name $pkg -AllUsers -ErrorAction SilentlyContinue ^| Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue; Write-Host "  Removed $pkg" -ForegroundColor Green }
>>"%PRESETSCRIPT%" echo $stubs = @^('*CandyCrush*', '*FarmVille*', '*Roblox*'^)
>>"%PRESETSCRIPT%" echo foreach ^($stub in $stubs^) { Get-AppxPackage -Name $stub -AllUsers -ErrorAction SilentlyContinue ^| Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue; Write-Host "  Removed OEM Stub $stub" -ForegroundColor Green }
powershell -NoProfile -ExecutionPolicy Bypass -File "%PRESETSCRIPT%"
del "%PRESETSCRIPT%" >nul 2>&1
echo.
pause
goto DEBLOAT_MENU

:DO_PRESET_SCHOOL
cls
color !COL_OPS!
echo.
echo  =============================================
echo   Applying Preset: School / Work Bloat
echo  =============================================
echo.
echo   What am I about to do?
echo    * Remove Microsoft Teams, OneNote, Office Hub, and Microsoft To Do
echo.
set "CONFIRM="
set /p "CONFIRM=  Type YES to continue or NO to cancel: "
if /i not "!CONFIRM!"=="YES" goto DEBLOAT_MENU
call :CREATE_RESTORE_POINT_SILENT
set "PRESETSCRIPT=%TEMP%\ytsh_preset_%RANDOM%%RANDOM%.ps1"
if exist "%PRESETSCRIPT%" del "%PRESETSCRIPT%" >nul 2>&1
>>"%PRESETSCRIPT%" echo $pkgs = @^('MicrosoftTeams', 'Microsoft.Office.OneNote', 'Microsoft.MicrosoftOfficeHub', 'Microsoft.Todos'^)
>>"%PRESETSCRIPT%" echo foreach ^($pkg in $pkgs^) { Get-AppxPackage -Name $pkg -AllUsers -ErrorAction SilentlyContinue ^| Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue; Write-Host "  Removed $pkg" -ForegroundColor Green }
powershell -NoProfile -ExecutionPolicy Bypass -File "%PRESETSCRIPT%"
del "%PRESETSCRIPT%" >nul 2>&1
echo.
pause
goto DEBLOAT_MENU

:DO_PRESET_3D
cls
color !COL_OPS!
echo.
echo  =============================================
echo   Applying Preset: 3D and Mixed Reality
echo  =============================================
echo.
echo   What am I about to do?
echo    * Remove 3D Viewer, Print 3D, 3D Builder, and Mixed Reality Portal
echo.
set "CONFIRM="
set /p "CONFIRM=  Type YES to continue or NO to cancel: "
if /i not "!CONFIRM!"=="YES" goto DEBLOAT_MENU
call :CREATE_RESTORE_POINT_SILENT	
set "PRESETSCRIPT=%TEMP%\ytsh_preset_%RANDOM%%RANDOM%.ps1"
if exist "%PRESETSCRIPT%" del "%PRESETSCRIPT%" >nul 2>&1
>>"%PRESETSCRIPT%" echo $pkgs = @^('Microsoft.Microsoft3DViewer', 'Microsoft.Print3D', 'Microsoft.3DBuilder', 'Microsoft.MixedReality.Portal'^)
>>"%PRESETSCRIPT%" echo foreach ^($pkg in $pkgs^) { Get-AppxPackage -Name $pkg -AllUsers -ErrorAction SilentlyContinue ^| Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue; Write-Host "  Removed $pkg" -ForegroundColor Green }
powershell -NoProfile -ExecutionPolicy Bypass -File "%PRESETSCRIPT%"
del "%PRESETSCRIPT%" >nul 2>&1
echo.
pause
goto DEBLOAT_MENU

:DO_PRESET_PRIVACY
cls
color !COL_OPS!
echo.
echo  =============================================
echo   Applying Preset: Privacy Pack (options 75-88)
echo  =============================================
echo.
echo   What am I about to do?
echo    * Disable Telemetry, Advertising ID, Tailored Experiences, Feedback
echo    * Disable Activity History, App Launch Tracking, Location Tracking
echo    * Disable Consumer Features, CEIP Tasks, Speech/Typing/Handwriting data
echo.
set "CONFIRM="
set /p "CONFIRM=  Type YES to continue or NO to cancel: "
if /i not "!CONFIRM!"=="YES" goto DEBLOAT_MENU
call :CREATE_RESTORE_POINT_SILENT
set "PRIVSCRIPT=%TEMP%\ytsh_preset_privacy_%RANDOM%%RANDOM%.ps1"
if exist "%PRIVSCRIPT%" del "%PRIVSCRIPT%" >nul 2>&1
>>"%PRIVSCRIPT%" echo try { $r='HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection'; if(-not(Test-Path $r)){New-Item -Path $r -Force^|Out-Null}; Set-ItemProperty -Path $r -Name 'AllowTelemetry' -Value 0 -Type DWord -Force; Set-ItemProperty -Path $r -Name 'DisableEnterpriseAuthProxy' -Value 1 -Type DWord -Force; Write-Host '  [SUCCESS] Diagnostic Data Disabled' -ForegroundColor Green } catch { Write-Host ('  [FAIL] DiagData: '+$_.Exception.Message) -ForegroundColor Red }
>>"%PRIVSCRIPT%" echo try { $r='HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\AdvertisingInfo'; if(-not(Test-Path $r)){New-Item -Path $r -Force^|Out-Null}; Set-ItemProperty -Path $r -Name 'Enabled' -Value 0 -Type DWord -Force; Write-Host '  [SUCCESS] Advertising ID Disabled' -ForegroundColor Green } catch { Write-Host ('  [FAIL] AdvID: '+$_.Exception.Message) -ForegroundColor Red }
>>"%PRIVSCRIPT%" echo try { $r='HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Privacy'; if(-not(Test-Path $r)){New-Item -Path $r -Force^|Out-Null}; Set-ItemProperty -Path $r -Name 'TailoredExperiencesWithDiagnosticDataEnabled' -Value 0 -Type DWord -Force; Write-Host '  [SUCCESS] Tailored Experiences Disabled' -ForegroundColor Green } catch { Write-Host ('  [FAIL] Tailored: '+$_.Exception.Message) -ForegroundColor Red }
>>"%PRIVSCRIPT%" echo try { $r='HKCU:\SOFTWARE\Microsoft\Siuf\Rules'; if(-not(Test-Path $r)){New-Item -Path $r -Force^|Out-Null}; Set-ItemProperty -Path $r -Name 'NumberOfSIUFInPeriod' -Value 0 -Type DWord -Force; Write-Host '  [SUCCESS] Feedback Notifications Disabled' -ForegroundColor Green } catch { Write-Host ('  [FAIL] Feedback: '+$_.Exception.Message) -ForegroundColor Red }
>>"%PRIVSCRIPT%" echo try { $r='HKLM:\SOFTWARE\Policies\Microsoft\Windows\System'; if(-not(Test-Path $r)){New-Item -Path $r -Force^|Out-Null}; Set-ItemProperty -Path $r -Name 'EnableActivityFeed' -Value 0 -Type DWord -Force; Set-ItemProperty -Path $r -Name 'PublishUserActivities' -Value 0 -Type DWord -Force; Set-ItemProperty -Path $r -Name 'UploadUserActivities' -Value 0 -Type DWord -Force; Write-Host '  [SUCCESS] Activity History Disabled' -ForegroundColor Green } catch { Write-Host ('  [FAIL] Activity: '+$_.Exception.Message) -ForegroundColor Red }
>>"%PRIVSCRIPT%" echo try { $r='HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Set-ItemProperty -Path $r -Name 'Start_TrackProgs' -Value 0 -Type DWord -Force; Write-Host '  [SUCCESS] App Launch Tracking Disabled' -ForegroundColor Green } catch { Write-Host ('  [FAIL] AppTrack: '+$_.Exception.Message) -ForegroundColor Red }
>>"%PRIVSCRIPT%" echo try { $r='HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Sensor\Overrides\{BFA794E4-F964-4FDB-90F6-51056BFE4B44}'; if(-not(Test-Path $r)){New-Item -Path $r -Force^|Out-Null}; Set-ItemProperty -Path $r -Name 'SensorPermissionState' -Value 0 -Type DWord -Force; $r2='HKLM:\SYSTEM\CurrentControlSet\Services\lfsvc\Service\Configuration'; if(-not(Test-Path $r2)){New-Item -Path $r2 -Force^|Out-Null}; Set-ItemProperty -Path $r2 -Name 'Status' -Value 0 -Type DWord -Force; Write-Host '  [SUCCESS] Location Tracking Disabled' -ForegroundColor Green } catch { Write-Host ('  [FAIL] Location: '+$_.Exception.Message) -ForegroundColor Red }
>>"%PRIVSCRIPT%" echo try { $r='HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppCompat'; if(-not(Test-Path $r)){New-Item -Path $r -Force^|Out-Null}; Set-ItemProperty -Path $r -Name 'AITEnable' -Value 0 -Type DWord -Force; Set-ItemProperty -Path $r -Name 'DisableInventory' -Value 1 -Type DWord -Force; Write-Host '  [SUCCESS] AppCompat Telemetry Disabled' -ForegroundColor Green } catch { Write-Host ('  [FAIL] AppCompat: '+$_.Exception.Message) -ForegroundColor Red }
>>"%PRIVSCRIPT%" echo try { $r='HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent'; if(-not(Test-Path $r)){New-Item -Path $r -Force^|Out-Null}; Set-ItemProperty -Path $r -Name 'DisableWindowsConsumerFeatures' -Value 1 -Type DWord -Force; Set-ItemProperty -Path $r -Name 'DisableSoftLanding' -Value 1 -Type DWord -Force; Set-ItemProperty -Path $r -Name 'DisableCloudOptimizedContent' -Value 1 -Type DWord -Force; Write-Host '  [SUCCESS] Consumer Features Disabled' -ForegroundColor Green } catch { Write-Host ('  [FAIL] Consumer: '+$_.Exception.Message) -ForegroundColor Red }
>>"%PRIVSCRIPT%" echo try { $r='HKCU:\SOFTWARE\Microsoft\Personalization\Settings'; if(-not(Test-Path $r)){New-Item -Path $r -Force^|Out-Null}; Set-ItemProperty -Path $r -Name 'AcceptedPrivacyPolicy' -Value 0 -Type DWord -Force; $r2='HKCU:\SOFTWARE\Microsoft\InputPersonalization'; if(-not(Test-Path $r2)){New-Item -Path $r2 -Force^|Out-Null}; Set-ItemProperty -Path $r2 -Name 'RestrictImplicitInkCollection' -Value 1 -Type DWord -Force; Set-ItemProperty -Path $r2 -Name 'RestrictImplicitTextCollection' -Value 1 -Type DWord -Force; $r3='HKCU:\SOFTWARE\Microsoft\InputPersonalization\TrainedDataStore'; if(-not(Test-Path $r3)){New-Item -Path $r3 -Force^|Out-Null}; Set-ItemProperty -Path $r3 -Name 'HarvestContacts' -Value 0 -Type DWord -Force; Write-Host '  [SUCCESS] Handwriting Data Disabled' -ForegroundColor Green } catch { Write-Host ('  [FAIL] Handwriting: '+$_.Exception.Message) -ForegroundColor Red }
>>"%PRIVSCRIPT%" echo try { $r='HKCU:\SOFTWARE\Microsoft\Input\TIPC'; if(-not(Test-Path $r)){New-Item -Path $r -Force^|Out-Null}; Set-ItemProperty -Path $r -Name 'Enabled' -Value 0 -Type DWord -Force; Write-Host '  [SUCCESS] Typing Insights Disabled' -ForegroundColor Green } catch { Write-Host ('  [FAIL] Typing: '+$_.Exception.Message) -ForegroundColor Red }
>>"%PRIVSCRIPT%" echo try { $r='HKCU:\SOFTWARE\Microsoft\Speech_OneCore\Settings\OnlineSpeechPrivacy'; if(-not(Test-Path $r)){New-Item -Path $r -Force^|Out-Null}; Set-ItemProperty -Path $r -Name 'HasAccepted' -Value 0 -Type DWord -Force; Write-Host '  [SUCCESS] Speech Personalization Disabled' -ForegroundColor Green } catch { Write-Host ('  [FAIL] Speech: '+$_.Exception.Message) -ForegroundColor Red }
>>"%PRIVSCRIPT%" echo try { $r='HKLM:\SOFTWARE\Microsoft\WcmSvc\wifinetworkmanager\config'; if(-not(Test-Path $r)){New-Item -Path $r -Force^|Out-Null}; Set-ItemProperty -Path $r -Name 'AutoConnectAllowedOEM' -Value 0 -Type DWord -Force; Write-Host '  [SUCCESS] Wi-Fi Sense Disabled' -ForegroundColor Green } catch { Write-Host ('  [FAIL] WiFiSense: '+$_.Exception.Message) -ForegroundColor Red }
powershell -NoProfile -ExecutionPolicy Bypass -File "%PRIVSCRIPT%"
del "%PRIVSCRIPT%" >nul 2>&1
schtasks /change /tn "\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser" /disable >nul 2>&1
schtasks /change /tn "\Microsoft\Windows\Application Experience\ProgramDataUpdater" /disable >nul 2>&1
schtasks /change /tn "\Microsoft\Windows\Customer Experience Improvement Program\Consolidator" /disable >nul 2>&1
schtasks /change /tn "\Microsoft\Windows\Customer Experience Improvement Program\UsbCeip" /disable >nul 2>&1
schtasks /change /tn "\Microsoft\Windows\Application Experience\StartupAppTask" /disable >nul 2>&1
schtasks /change /tn "\Microsoft\Windows\DiskDiagnostic\Microsoft-Windows-DiskDiagnosticDataCollector" /disable >nul 2>&1
powershell -NoProfile -Command "Write-Host '  [SUCCESS] All CEIP tasks disabled' -ForegroundColor Green"
echo.
echo  =============================================
echo   Privacy Pack applied.
echo  =============================================
echo.
pause
goto DEBLOAT_MENU

:DO_PRESET_BING
cls
color !COL_OPS!
echo.
echo  =============================================
echo   Applying Preset: Bing / News / Cortana
echo  =============================================
echo.
echo   What am I about to do?
echo    * Remove Bing News, Bing Weather, Bing Search, Microsoft Start, and Cortana
echo.
set "CONFIRM="
set /p "CONFIRM=  Type YES to continue or NO to cancel: "
if /i not "!CONFIRM!"=="YES" goto DEBLOAT_MENU
call :CREATE_RESTORE_POINT_SILENT
set "PRESETSCRIPT=%TEMP%\ytsh_preset.ps1"
if exist "%PRESETSCRIPT%" del "%PRESETSCRIPT%" >nul 2>&1
>>"%PRESETSCRIPT%" echo $pkgs = @('Microsoft.BingNews','Microsoft.BingWeather','Microsoft.BingSearch','Microsoft.MicrosoftStart','Microsoft.Cortana','Microsoft.549981C3F5F10','MicrosoftWindows.Client.WebExperience')
>>"%PRESETSCRIPT%" echo foreach ($pkg in $pkgs) { Get-AppxPackage -Name $pkg -AllUsers -ErrorAction SilentlyContinue ^| Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue; Write-Host "  Removed $pkg" -ForegroundColor Green }
>>"%PRESETSCRIPT%" echo if ($env:SYS_OS -match 'Windows 10') { Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Feeds' -Name 'ShellFeedsTaskbarViewMode' -Value 2 -Type DWord -Force -ErrorAction SilentlyContinue; Write-Host "  Disabled Win10 News & Interests" -ForegroundColor Green }
>>"%PRESETSCRIPT%" echo if ($env:SYS_OS -match 'Windows 11') { Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name 'TaskbarDa' -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue; Write-Host "  Disabled Win11 Widgets" -ForegroundColor Green }
powershell -NoProfile -ExecutionPolicy Bypass -File "%PRESETSCRIPT%"
del "%PRESETSCRIPT%" >nul 2>&1
echo.
echo  =============================================
echo   Bing / News / Cortana preset applied.
echo  =============================================
echo.
pause
goto DEBLOAT_MENU

:DO_PRESET_MEDIA
cls
color !COL_OPS!
echo.
echo  =============================================
echo   Applying Preset: Media and Music
echo  =============================================
echo.
echo   What am I about to do?
echo    * Remove Groove Music, Movies & TV, Sound Recorder, and Clipchamp
echo.
set "CONFIRM="
set /p "CONFIRM=  Type YES to continue or NO to cancel: "
if /i not "!CONFIRM!"=="YES" goto DEBLOAT_MENU
call :CREATE_RESTORE_POINT_SILENT
set "PRESETSCRIPT=%TEMP%\ytsh_preset.ps1"
if exist "%PRESETSCRIPT%" del "%PRESETSCRIPT%" >nul 2>&1
>>"%PRESETSCRIPT%" echo $pkgs = @('Microsoft.ZuneMusic','Microsoft.ZuneVideo','Microsoft.WindowsSoundRecorder','Clipchamp.Clipchamp')
>>"%PRESETSCRIPT%" echo foreach ($pkg in $pkgs) { Get-AppxPackage -Name $pkg -AllUsers -ErrorAction SilentlyContinue ^| Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue; Write-Host "  Removed $pkg" -ForegroundColor Green }
powershell -NoProfile -ExecutionPolicy Bypass -File "%PRESETSCRIPT%"
del "%PRESETSCRIPT%" >nul 2>&1
echo.
echo  =============================================
echo   Media and Music preset applied.
echo  =============================================
echo.
pause
goto DEBLOAT_MENU

:DO_PRESET_COMMS
cls
color !COL_OPS!
echo.
echo  =============================================
echo   Applying Preset: Communication Apps
echo  =============================================
echo.
echo   What am I about to do?
echo    * Remove Skype, Teams, Mail and Calendar, People, and Phone Link
echo.
set "CONFIRM="
set /p "CONFIRM=  Type YES to continue or NO to cancel: "
if /i not "!CONFIRM!"=="YES" goto DEBLOAT_MENU
call :CREATE_RESTORE_POINT_SILENT
set "PRESETSCRIPT=%TEMP%\ytsh_preset.ps1"
if exist "%PRESETSCRIPT%" del "%PRESETSCRIPT%" >nul 2>&1
>>"%PRESETSCRIPT%" echo $pkgs = @('Microsoft.SkypeApp','Microsoft.WindowsCommunicationsApps','Microsoft.Teams','Microsoft.People','Microsoft.YourPhone')
>>"%PRESETSCRIPT%" echo foreach ($pkg in $pkgs) { Get-AppxPackage -Name $pkg -AllUsers -ErrorAction SilentlyContinue ^| Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue; Write-Host "  Removed $pkg" -ForegroundColor Green }
powershell -NoProfile -ExecutionPolicy Bypass -File "%PRESETSCRIPT%"
del "%PRESETSCRIPT%" >nul 2>&1
echo.
echo  =============================================
echo   Communication Apps preset applied.
echo  =============================================
echo.
pause
goto DEBLOAT_MENU

:DO_PRESET_PERF
cls
color !COL_OPS!
echo.
echo  =============================================
echo   Applying Preset: Performance Pack
echo  =============================================
echo.
echo   What am I about to do?
echo    * Disable Global UWP Background Apps
echo    * Disable SysMain / Superfetch (if applicable)
echo    * Disable DiagTrack, WMPNetworkSvc, MapsBroker, RetailDemo, WerSvc
echo.
set "CONFIRM="
set /p "CONFIRM=  Type YES to continue or NO to cancel: "
if /i not "!CONFIRM!"=="YES" goto DEBLOAT_MENU
call :CREATE_RESTORE_POINT_SILENT
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications" /v GlobalUserDisabled /t REG_DWORD /d 1 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy" /v LetAppsRunInBackground /t REG_DWORD /d 2 /f >nul 2>&1
powershell -NoProfile -Command "Write-Host '  [SUCCESS] UWP Background Apps disabled.' -ForegroundColor Green"
if "!SYS_DISK_TYPE!"=="HDD" (
    if "!COLOR_THEME!"=="AMBER" (
        powershell -NoProfile -Command "Write-Host '  [WARNING] HDD detected - disabling SysMain on a HDD may SLOW your PC.' -ForegroundColor Red"
    ) else (
        powershell -NoProfile -Command "Write-Host '  [WARNING] HDD detected - disabling SysMain on a HDD may SLOW your PC.' -ForegroundColor Yellow"
    )
)
sc stop "SysMain" >nul 2>&1
sc config "SysMain" start= disabled >nul 2>&1
if !errorLevel! equ 0 (
    powershell -NoProfile -Command "Write-Host '  [SUCCESS] SysMain disabled.' -ForegroundColor Green"
) else (
    powershell -NoProfile -Command "Write-Host '  [FAIL] Could not disable SysMain.' -ForegroundColor Red"
)
set "DSVC=DiagTrack" & call :DO_SINGLE_SVC_SILENT
set "DSVC=WMPNetworkSvc" & call :DO_SINGLE_SVC_SILENT
set "DSVC=MapsBroker" & call :DO_SINGLE_SVC_SILENT
set "DSVC=RetailDemo" & call :DO_SINGLE_SVC_SILENT
set "DSVC=WerSvc" & call :DO_SINGLE_SVC_SILENT
echo.
echo  =============================================
echo   Performance Pack applied. Restart recommended.
echo  =============================================
echo.
pause
goto DEBLOAT_MENU

:DO_RAM_BGAPPS
cls
color !COL_OPS!
echo.
echo  =============================================
echo   Disabling Global UWP Background Apps
echo  =============================================
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications" /v GlobalUserDisabled /t REG_DWORD /d 1 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy" /v LetAppsRunInBackground /t REG_DWORD /d 2 /f >nul 2>&1
powershell -NoProfile -Command "Write-Host '  [SUCCESS] Background Apps globally disabled.' -ForegroundColor Green"
echo.
pause
goto DEBLOAT_MENU

:DO_SINGLE_APP
cls
color !COL_OPS!
echo.
echo  =============================================
echo   Removing: !DPKG!
echo  =============================================
echo.
call :CREATE_RESTORE_POINT_SILENT
set "RMSCRIPT=%TEMP%\ytsh_single_rm_%RANDOM%%RANDOM%.ps1"
(
    echo $pkg = '!DPKG!'
    echo $inst = Get-AppxPackage -Name $pkg -AllUsers -ErrorAction SilentlyContinue
    echo if ^($inst^) {
    echo     try {
    echo         Remove-AppxPackage -Package $inst.PackageFullName -AllUsers -ErrorAction Stop
    echo         $prov = Get-AppxProvisionedPackage -Online ^| Where-Object { $_.DisplayName -eq $pkg }
    echo         if ^($prov^) { Remove-AppxProvisionedPackage -Online -PackageName $prov.PackageName -ErrorAction SilentlyContinue ^| Out-Null }
    echo         Write-Host "  [SUCCESS] $pkg uninstalled." -ForegroundColor Green
    echo         Add-Content -Path '!LOGFILE!' -Value $pkg
    echo     } catch {
    echo         Write-Host ^("  [FAIL] " + $_.Exception.Message^) -ForegroundColor Red
    echo     }
    echo } else {
    echo     Write-Host "  [SKIP] $pkg was not installed." -ForegroundColor DarkGray
    echo }
) > "%RMSCRIPT%"
powershell -NoProfile -ExecutionPolicy Bypass -File "%RMSCRIPT%"
del "%RMSCRIPT%" >nul 2>&1
echo.
echo  Done. Press any key to return.
echo.
pause
goto DEBLOAT_MENU

:DO_XBOX_OVERLAY
cls
color !COL_OPS!
echo.
echo  =============================================
echo   Removing: Xbox Game Bar and Overlay
echo  =============================================
echo.
call :CREATE_RESTORE_POINT_SILENT
set "RMSCRIPT=%TEMP%\ytsh_xbox_rm_%RANDOM%%RANDOM%.ps1"
(
    echo $xboxPkgs = @^('Microsoft.XboxApp','Microsoft.XboxGameOverlay','Microsoft.XboxGamingOverlay','Microsoft.XboxIdentityProvider','Microsoft.XboxSpeechToTextOverlay'^)
    echo foreach ^($pkg in $xboxPkgs^) {
    echo     $inst = Get-AppxPackage -Name $pkg -AllUsers -ErrorAction SilentlyContinue
    echo     if ^($inst^) {
    echo         try {
    echo             Remove-AppxPackage -Package $inst.PackageFullName -AllUsers -ErrorAction Stop
    echo             $prov = Get-AppxProvisionedPackage -Online ^| Where-Object { $_.DisplayName -eq $pkg }
    echo             if ^($prov^) { Remove-AppxProvisionedPackage -Online -PackageName $prov.PackageName -ErrorAction SilentlyContinue ^| Out-Null }
    echo             Write-Host "  [SUCCESS] $pkg uninstalled." -ForegroundColor Green
    echo         } catch {
    echo             Write-Host ^("  [FAIL] $pkg : " + $_.Exception.Message^) -ForegroundColor Red
    echo         }
    echo     } else {
    echo         Write-Host "  [SKIP] $pkg not found." -ForegroundColor DarkGray
    echo     }
    echo }
) > "%RMSCRIPT%"
powershell -NoProfile -ExecutionPolicy Bypass -File "%RMSCRIPT%"
del "%RMSCRIPT%" >nul 2>&1
echo.
echo  Done. Press any key to return.
echo.
pause
goto DEBLOAT_MENU

:DO_SINGLE_STUB
cls
color !COL_OPS!
echo.
echo  =============================================
echo   Removing OEM stub: !DPKG!
echo  =============================================
echo.
powershell -NoProfile -Command "Write-Host '  [INFO] These vary by manufacturer and may not exist on your machine.' -ForegroundColor Yellow"
echo.
call :CREATE_RESTORE_POINT_SILENT
set "STUB_PATTERN="
if "!DPKG!"=="STUB_TIKTOK"     set "STUB_PATTERN=*TikTok*"
if "!DPKG!"=="STUB_DISNEY"     set "STUB_PATTERN=*Disney*"
if "!DPKG!"=="STUB_SPOTIFY"    set "STUB_PATTERN=*Spotify*"
if "!DPKG!"=="STUB_FACEBOOK"   set "STUB_PATTERN=*Facebook*"
if "!DPKG!"=="STUB_INSTAGRAM"  set "STUB_PATTERN=*Instagram*"
if "!DPKG!"=="STUB_NETFLIX"    set "STUB_PATTERN=*Netflix*"
if "!DPKG!"=="STUB_ROBLOX"     set "STUB_PATTERN=*Roblox*"
if "!DPKG!"=="STUB_CANDYCRUSH" set "STUB_PATTERN=*CandyCrush*"
if "!DPKG!"=="STUB_FARMVILLE"   set "STUB_PATTERN=*FarmVille*"
if "!DPKG!"=="STUB_BUBBLEWITCH" set "STUB_PATTERN=*BubbleWitch*"
if "!DPKG!"=="STUB_FARMHEROES"  set "STUB_PATTERN=*FarmHeroes*"
set "RMSCRIPT=%TEMP%\ytsh_stub_rm_%RANDOM%%RANDOM%.ps1"
(
    echo $pkgs = Get-AppxPackage -Name '!STUB_PATTERN!' -AllUsers -ErrorAction SilentlyContinue
    echo if ^($pkgs^) {
    echo     foreach ^($p in $pkgs^) {
    echo         try {
        echo             Remove-AppxPackage -Package $p.PackageFullName -AllUsers -ErrorAction Stop
    echo             Write-Host ^("  [SUCCESS] " + $p.Name + " uninstalled."^) -ForegroundColor Green
    echo         } catch {
    echo             Write-Host ^("  [FAIL] " + $p.Name^) -ForegroundColor Red
    echo         }
    echo     }
    echo } else {
    echo     Write-Host "  [SKIP] No packages matching !STUB_PATTERN! found." -ForegroundColor DarkGray
    echo }
) > "%RMSCRIPT%"
powershell -NoProfile -ExecutionPolicy Bypass -File "%RMSCRIPT%"
del "%RMSCRIPT%" >nul 2>&1
echo.
echo  Done. Press any key to return.
echo.
pause
goto DEBLOAT_MENU

:DO_BRAND_APP
cls
color !COL_OPS!
echo.
echo  =============================================
echo   Removing Brand Bloatware: !DPKG!
echo  =============================================
echo.
powershell -NoProfile -Command "Write-Host '  [INFO] Tries AppX removal first. If skipped, this may be a Win32 app - uninstall via Settings ^> Apps.' -ForegroundColor Yellow"
echo.
call :CREATE_RESTORE_POINT_SILENT
set "BRAND_PATTERN="
if "!DPKG!"=="BRAND_HP_JUMPSTART"      set "BRAND_PATTERN=*JumpStart*"
if "!DPKG!"=="BRAND_HP_SUPPORTASSIST"  set "BRAND_PATTERN=*HPSupportSolutions*"
if "!DPKG!"=="BRAND_HP_SMART"          set "BRAND_PATTERN=*HPPrinterControl*"
if "!DPKG!"=="BRAND_HP_QUICKDROP"      set "BRAND_PATTERN=*HPQuickDrop*"
if "!DPKG!"=="BRAND_HP_AUDIOSWITCH"    set "BRAND_PATTERN=*HPAudioSwitch*"
if "!DPKG!"=="BRAND_HP_TOUCHPOINT"     set "BRAND_PATTERN=*TouchpointAnalytics*"
if "!DPKG!"=="BRAND_DELL_SUPPORTASSIST" set "BRAND_PATTERN=*DellSupportAssist*"
if "!DPKG!"=="BRAND_DELL_DELIVERY"      set "BRAND_PATTERN=*DellDigitalDelivery*"
if "!DPKG!"=="BRAND_DELL_UPDATE"        set "BRAND_PATTERN=*DellUpdate*"
if "!DPKG!"=="BRAND_DELL_MOBILECON"     set "BRAND_PATTERN=*DellMobileConnect*"
if "!DPKG!"=="BRAND_DELL_MYDELL"        set "BRAND_PATTERN=*MyDell*"
if "!DPKG!"=="BRAND_DELL_CUSTCON"       set "BRAND_PATTERN=*DellCustomerConnect*"
if "!DPKG!"=="BRAND_LENOVO_VANTAGE"    set "BRAND_PATTERN=*LenovoVantage*"
if "!DPKG!"=="BRAND_LENOVO_SETTINGS"   set "BRAND_PATTERN=*LenovoSettings*"
if "!DPKG!"=="BRAND_LENOVO_COMPANION"  set "BRAND_PATTERN=*LenovoCompanion*"
if "!DPKG!"=="BRAND_LENOVO_WINZIP"     set "BRAND_PATTERN=*WinZip*"
if "!DPKG!"=="BRAND_ASUS_MYASUS"       set "BRAND_PATTERN=*MyASUS*"
if "!DPKG!"=="BRAND_ASUS_LIVEUPDATE"   set "BRAND_PATTERN=*ASUSUpdate*"
if "!DPKG!"=="BRAND_ACER_CARECENTER"   set "BRAND_PATTERN=*AcerCare*"
if "!DPKG!"=="BRAND_ACER_COLLECTION"   set "BRAND_PATTERN=*AcerCollection*"
if "!DPKG!"=="BRAND_ACER_PORTAL"       set "BRAND_PATTERN=*AcerPortal*"
if "!DPKG!"=="BRAND_MSI_CENTER"        set "BRAND_PATTERN=*MSIDragon*"
if "!DPKG!"=="BRAND_MSI_APPPLAYER"     set "BRAND_PATTERN=*MSIAppPlayer*"
if "!DPKG!"=="BRAND_SAMSUNG_SETTINGS"  set "BRAND_PATTERN=*SamsungSettings*"
if "!DPKG!"=="BRAND_SAMSUNG_NOTES"     set "BRAND_PATTERN=*SamsungNotes*"
if "!DPKG!"=="BRAND_SURFACE_APP"       set "BRAND_PATTERN=*SurfaceApp*"
if "!DPKG!"=="BRAND_SURFACE_HUB"       set "BRAND_PATTERN=*SurfaceHub*"
if "!DPKG!"=="BRAND_MCAFEE"            set "BRAND_PATTERN=*McAfee*"
if "!DPKG!"=="STUB_COPILOT"            set "BRAND_PATTERN=*Copilot*"
if not defined BRAND_PATTERN (
    powershell -NoProfile -Command "Write-Host '  [ERROR] Unknown brand package key. No action taken.' -ForegroundColor Red"
    echo.
    pause
    goto DEBLOAT_MENU
)
set "RMSCRIPT=%TEMP%\ytsh_brand_rm_%RANDOM%%RANDOM%.ps1"
(
    echo $pkgs = Get-AppxPackage -Name '!BRAND_PATTERN!' -AllUsers -ErrorAction SilentlyContinue
    echo if ^($pkgs^) {
    echo     foreach ^($p in $pkgs^) {
    echo         try {
    echo             Remove-AppxPackage -Package $p.PackageFullName -AllUsers -ErrorAction Stop
    echo             $prov = Get-AppxProvisionedPackage -Online ^| Where-Object { $_.DisplayName -like '!BRAND_PATTERN!' }
    echo             if ^($prov^) { Remove-AppxProvisionedPackage -Online -PackageName $prov.PackageName -ErrorAction SilentlyContinue ^| Out-Null }
    echo             Write-Host ^("  [SUCCESS] " + $p.Name + " uninstalled."^) -ForegroundColor Green
    echo         } catch {
    echo             Write-Host ^("  [FAIL] " + $p.Name + " - may be a Win32 app. Uninstall via Settings ^> Apps."^) -ForegroundColor Yellow
    echo         }
    echo     }
    echo } else {
    echo     Write-Host "  [SKIP] No AppX packages matched '!BRAND_PATTERN!'." -ForegroundColor DarkGray
    echo     Write-Host "  [INFO] This is likely a Win32 app. Go to Settings ^> Apps to remove it." -ForegroundColor DarkGray
    echo }
) > "%RMSCRIPT%"
powershell -NoProfile -ExecutionPolicy Bypass -File "%RMSCRIPT%"
del "%RMSCRIPT%" >nul 2>&1
echo.
echo  Done. Press any key to return.
echo.
pause
goto DEBLOAT_MENU

:DO_SINGLE_SVC
cls
color !COL_OPS!
echo.
if "!SAFE_MODE!"=="1" (
    color !COL_ERR!
    echo.
    powershell -NoProfile -Command "Write-Host '  [LOCKED] Service disabling is blocked in SAFE MODE.' -ForegroundColor Red"
    powershell -NoProfile -Command "Write-Host '  Disable Safe Mode in Settings ^(S ^> 7^) to access it.' -ForegroundColor Yellow"
    echo.
    pause
    goto DEBLOAT_MENU
)
echo  =============================================
echo   Disabling service: !DSVC!
echo  =============================================
echo.
if "!DSVC!"=="WSearch" (
    powershell -NoProfile -Command "Write-Host '  [WARNING] This will break Start Menu search.' -ForegroundColor Red"
    echo.
    set "CONFIRM="
    set /p "CONFIRM=  Type YES to continue or NO to cancel: "
    if /i not "!CONFIRM!"=="YES" goto DEBLOAT_MENU
)
if "!DSVC!"=="SysMain" (
    if "!SYS_DISK_TYPE!"=="HDD" (
        if "!COLOR_THEME!"=="AMBER" (
            powershell -NoProfile -Command "Write-Host '  [WARNING] HDD detected - Not recommended if you''re on an HDD. This may SLOW your PC.' -ForegroundColor Red"
        ) else (
            powershell -NoProfile -Command "Write-Host '  [WARNING] HDD detected - Not recommended if you''re on an HDD. This may SLOW your PC.' -ForegroundColor Yellow"
        )
        echo.
        set "CONFIRM="
        set /p "CONFIRM=  Type YES to continue or NO to cancel: "
        if /i not "!CONFIRM!"=="YES" goto DEBLOAT_MENU
    )
)
call :CREATE_RESTORE_POINT_SILENT
sc query "!DSVC!" >nul 2>&1
if !errorLevel! equ 0 (
    for /f "tokens=3" %%T in ('sc qc "!DSVC!" 2^>nul ^| findstr /i "START_TYPE"') do (
        >>"%SVCLOG%" echo !DSVC!=%%T
    )
    sc stop "!DSVC!" >nul 2>&1
    sc config "!DSVC!" start= disabled >nul 2>&1
    if !errorLevel! equ 0 (
        powershell -NoProfile -Command "Write-Host '  [SUCCESS] !DSVC! disabled.' -ForegroundColor Green"
    ) else (
        powershell -NoProfile -Command "Write-Host '  [FAIL] Could not disable !DSVC!.' -ForegroundColor Red"
    )
) else (
    powershell -NoProfile -Command "Write-Host '  [SKIP] Service !DSVC! does not exist.' -ForegroundColor DarkGray"
)
echo.
echo  Done. Press any key to return.
echo.
pause
goto DEBLOAT_MENU

:DO_SINGLE_SVC_SILENT
sc query "!DSVC!" >nul 2>&1
if !errorLevel! equ 0 (
    for /f "tokens=3" %%T in ('sc qc "!DSVC!" 2^>nul ^| findstr /i "START_TYPE"') do (
        >>"%SVCLOG%" echo !DSVC!=%%T
    )
    sc stop "!DSVC!" >nul 2>&1
    sc config "!DSVC!" start= disabled >nul 2>&1
    powershell -NoProfile -Command "Write-Host '  [SUCCESS] !DSVC! disabled.' -ForegroundColor Green"
)
exit /b 0

:DO_TEL_DIAGDATA
cls
color !COL_OPS!
echo.
echo  =============================================
echo   Disabling: Diagnostic Data Collection
echo  =============================================
echo.
set "TELSCRIPT=%TEMP%\ytsh_tel_dd_%RANDOM%%RANDOM%.ps1"
(
    echo try {
    echo     $r = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection'
    echo     if ^(-not ^(Test-Path $r^)^) { New-Item -Path $r -Force ^| Out-Null }
    echo     Set-ItemProperty -Path $r -Name 'AllowTelemetry' -Value 0 -Type DWord -Force
    echo     Set-ItemProperty -Path $r -Name 'DisableEnterpriseAuthProxy' -Value 1 -Type DWord -Force
    echo     Write-Host '  [SUCCESS] Diagnostic Data Collection Disabled.' -ForegroundColor Green
    echo } catch { Write-Host ^('  [FAIL] ' + $_.Exception.Message^) -ForegroundColor Red }
) > "%TELSCRIPT%"
powershell -NoProfile -ExecutionPolicy Bypass -File "%TELSCRIPT%"
del "%TELSCRIPT%" >nul 2>&1
echo.
echo  Done. Press any key to return.
echo.
pause
goto DEBLOAT_MENU

:DO_TEL_ADVID
cls
color !COL_OPS!
echo.
echo  =============================================
echo   Disabling: Advertising ID
echo  =============================================
echo.
set "TELSCRIPT=%TEMP%\ytsh_tel_ai_%RANDOM%%RANDOM%.ps1"
(
    echo try {
    echo     $r = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\AdvertisingInfo'
    echo     if ^(-not ^(Test-Path $r^)^) { New-Item -Path $r -Force ^| Out-Null }
    echo     Set-ItemProperty -Path $r -Name 'Enabled' -Value 0 -Type DWord -Force
    echo     Write-Host '  [SUCCESS] Advertising ID Disabled.' -ForegroundColor Green
    echo } catch { Write-Host ^('  [FAIL] ' + $_.Exception.Message^) -ForegroundColor Red }
) > "%TELSCRIPT%"
powershell -NoProfile -ExecutionPolicy Bypass -File "%TELSCRIPT%"
del "%TELSCRIPT%" >nul 2>&1
echo.
echo  Done. Press any key to return.
echo.
pause
goto DEBLOAT_MENU

:DO_TEL_TAILORED
cls
color !COL_OPS!
echo.
echo  =============================================
echo   Disabling: Tailored Experiences
echo  =============================================
echo.
set "TELSCRIPT=%TEMP%\ytsh_tel_te_%RANDOM%%RANDOM%.ps1"
(
    echo try {
    echo     $r = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Privacy'
    echo     if ^(-not ^(Test-Path $r^)^) { New-Item -Path $r -Force ^| Out-Null }
    echo     Set-ItemProperty -Path $r -Name 'TailoredExperiencesWithDiagnosticDataEnabled' -Value 0 -Type DWord -Force
    echo     Write-Host '  [SUCCESS] Tailored Experiences Disabled.' -ForegroundColor Green
    echo } catch { Write-Host ^('  [FAIL] ' + $_.Exception.Message^) -ForegroundColor Red }
) > "%TELSCRIPT%"
powershell -NoProfile -ExecutionPolicy Bypass -File "%TELSCRIPT%"
del "%TELSCRIPT%" >nul 2>&1
echo.
echo  Done. Press any key to return.
echo.
pause
goto DEBLOAT_MENU

:DO_TEL_FEEDBACK
cls
color !COL_OPS!
echo.
echo  =============================================
echo   Disabling: Feedback Notifications
echo  =============================================
echo.
set "TELSCRIPT=%TEMP%\ytsh_tel_fb_%RANDOM%%RANDOM%.ps1"
(
    echo try {
    echo     $r = 'HKCU:\SOFTWARE\Microsoft\Siuf\Rules'
    echo     if ^(-not ^(Test-Path $r^)^) { New-Item -Path $r -Force ^| Out-Null }
    echo     Set-ItemProperty -Path $r -Name 'NumberOfSIUFInPeriod' -Value 0 -Type DWord -Force
    echo     Write-Host '  [SUCCESS] Feedback Notifications Disabled.' -ForegroundColor Green
    echo } catch { Write-Host ^('  [FAIL] ' + $_.Exception.Message^) -ForegroundColor Red }
) > "%TELSCRIPT%"
powershell -NoProfile -ExecutionPolicy Bypass -File "%TELSCRIPT%"
del "%TELSCRIPT%" >nul 2>&1
echo.
echo  Done. Press any key to return.
echo.
pause
goto DEBLOAT_MENU

:DO_TEL_ACTIVITY
cls
color !COL_OPS!
echo.
echo  =============================================
echo   Disabling: Activity History / Timeline
echo  =============================================
echo.
set "TELSCRIPT=%TEMP%\ytsh_tel_ah_%RANDOM%%RANDOM%.ps1"
(
    echo try {
    echo     $r = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System'
    echo     if ^(-not ^(Test-Path $r^)^) { New-Item -Path $r -Force ^| Out-Null }
    echo     Set-ItemProperty -Path $r -Name 'EnableActivityFeed' -Value 0 -Type DWord -Force
    echo     Set-ItemProperty -Path $r -Name 'PublishUserActivities' -Value 0 -Type DWord -Force
    echo     Set-ItemProperty -Path $r -Name 'UploadUserActivities' -Value 0 -Type DWord -Force
    echo     Write-Host '  [SUCCESS] Activity History / Timeline Disabled.' -ForegroundColor Green
    echo } catch { Write-Host ^('  [FAIL] ' + $_.Exception.Message^) -ForegroundColor Red }
) > "%TELSCRIPT%"
powershell -NoProfile -ExecutionPolicy Bypass -File "%TELSCRIPT%"
del "%TELSCRIPT%" >nul 2>&1
echo.
echo  Done. Press any key to return.
echo.
pause
goto DEBLOAT_MENU

:DO_TEL_APPTRACK
cls
color !COL_OPS!
echo.
echo  =============================================
echo   Disabling: App Launch Tracking
echo  =============================================
echo.
set "TELSCRIPT=%TEMP%\ytsh_tel_at_%RANDOM%%RANDOM%.ps1"
(
    echo try {
    echo     $r = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
    echo     Set-ItemProperty -Path $r -Name 'Start_TrackProgs' -Value 0 -Type DWord -Force
    echo     Write-Host '  [SUCCESS] App Launch Tracking Disabled.' -ForegroundColor Green
    echo } catch { Write-Host ^('  [FAIL] ' + $_.Exception.Message^) -ForegroundColor Red }
) > "%TELSCRIPT%"
powershell -NoProfile -ExecutionPolicy Bypass -File "%TELSCRIPT%"
del "%TELSCRIPT%" >nul 2>&1
echo.
echo  Done. Press any key to return.
echo.
pause
goto DEBLOAT_MENU

:DO_TEL_LOCATION
cls
color !COL_OPS!
echo.
echo  =============================================
echo   Disabling: Location Tracking
echo  =============================================
echo.
set "TELSCRIPT=%TEMP%\ytsh_tel_loc_%RANDOM%%RANDOM%.ps1"
(
    echo try {
    echo     $r = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Sensor\Overrides\{BFA794E4-F964-4FDB-90F6-51056BFE4B44}'
    echo     if ^(-not ^(Test-Path $r^)^) { New-Item -Path $r -Force ^| Out-Null }
    echo     Set-ItemProperty -Path $r -Name 'SensorPermissionState' -Value 0 -Type DWord -Force
    echo     $r2 = 'HKLM:\SYSTEM\CurrentControlSet\Services\lfsvc\Service\Configuration'
    echo     if ^(-not ^(Test-Path $r2^)^) { New-Item -Path $r2 -Force ^| Out-Null }
    echo     Set-ItemProperty -Path $r2 -Name 'Status' -Value 0 -Type DWord -Force
    echo     Write-Host '  [SUCCESS] Location Tracking Disabled.' -ForegroundColor Green
    echo } catch { Write-Host ^('  [FAIL] ' + $_.Exception.Message^) -ForegroundColor Red }
) > "%TELSCRIPT%"
powershell -NoProfile -ExecutionPolicy Bypass -File "%TELSCRIPT%"
del "%TELSCRIPT%" >nul 2>&1
echo.
echo  Done. Press any key to return.
echo.
pause
goto DEBLOAT_MENU

:DO_TEL_APPCOMPAT
cls
color !COL_OPS!
echo.
echo  =============================================
echo   Disabling: AppCompat Telemetry
echo  =============================================
echo.
set "TELSCRIPT=%TEMP%\ytsh_tel_ac_%RANDOM%%RANDOM%.ps1"
(
    echo try {
    echo     $r = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppCompat'
    echo     if ^(-not ^(Test-Path $r^)^) { New-Item -Path $r -Force ^| Out-Null }
    echo     Set-ItemProperty -Path $r -Name 'AITEnable' -Value 0 -Type DWord -Force
    echo     Set-ItemProperty -Path $r -Name 'DisableInventory' -Value 1 -Type DWord -Force
    echo     Write-Host '  [SUCCESS] AppCompat Telemetry Disabled.' -ForegroundColor Green
    echo } catch { Write-Host ^('  [FAIL] ' + $_.Exception.Message^) -ForegroundColor Red }
) > "%TELSCRIPT%"
powershell -NoProfile -ExecutionPolicy Bypass -File "%TELSCRIPT%"
del "%TELSCRIPT%" >nul 2>&1
echo.
echo  Done. Press any key to return.
echo.
pause
goto DEBLOAT_MENU

:DO_TEL_CONSUMER
cls
color !COL_OPS!
echo.
echo  =============================================
echo   Disabling: Windows Consumer Features
echo  =============================================
echo.
set "TELSCRIPT=%TEMP%\ytsh_tel_cf_%RANDOM%%RANDOM%.ps1"
(
    echo try {
    echo     $r = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent'
    echo     if ^(-not ^(Test-Path $r^)^) { New-Item -Path $r -Force ^| Out-Null }
    echo     Set-ItemProperty -Path $r -Name 'DisableWindowsConsumerFeatures' -Value 1 -Type DWord -Force
    echo     Set-ItemProperty -Path $r -Name 'DisableSoftLanding' -Value 1 -Type DWord -Force
    echo     Set-ItemProperty -Path $r -Name 'DisableCloudOptimizedContent' -Value 1 -Type DWord -Force
    echo     Write-Host '  [SUCCESS] Windows Consumer Features Disabled.' -ForegroundColor Green
    echo } catch { Write-Host ^('  [FAIL] ' + $_.Exception.Message^) -ForegroundColor Red }
) > "%TELSCRIPT%"
powershell -NoProfile -ExecutionPolicy Bypass -File "%TELSCRIPT%"
del "%TELSCRIPT%" >nul 2>&1
echo.
echo  Done. Press any key to return.
echo.
pause
goto DEBLOAT_MENU

:DO_TEL_TASKS
cls
color !COL_OPS!
echo.
echo  =============================================
echo   Disabling: CEIP Scheduled Tasks
echo  =============================================
echo.
schtasks /change /tn "\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser" /disable >nul 2>&1
schtasks /change /tn "\Microsoft\Windows\Application Experience\ProgramDataUpdater" /disable >nul 2>&1
schtasks /change /tn "\Microsoft\Windows\Customer Experience Improvement Program\Consolidator" /disable >nul 2>&1
schtasks /change /tn "\Microsoft\Windows\Customer Experience Improvement Program\UsbCeip" /disable >nul 2>&1
schtasks /change /tn "\Microsoft\Windows\Application Experience\StartupAppTask" /disable >nul 2>&1
schtasks /change /tn "\Microsoft\Windows\DiskDiagnostic\Microsoft-Windows-DiskDiagnosticDataCollector" /disable >nul 2>&1
powershell -NoProfile -Command "Write-Host '  [SUCCESS] Customer Experience Improvement tasks disabled.' -ForegroundColor Green"
powershell -NoProfile -Command "Write-Host '  [SUCCESS] Application Experience tasks disabled.' -ForegroundColor Green"
powershell -NoProfile -Command "Write-Host '  [SUCCESS] Disk Diagnostic data collection disabled.' -ForegroundColor Green"
echo.
echo  Done. Press any key to return.
echo.
pause
goto DEBLOAT_MENU

:DO_TEL_HANDWRITING
cls
color !COL_OPS!
echo.
echo  =============================================
echo   Disabling: Handwriting Personalization Data
echo  =============================================
echo.
set "TELSCRIPT=%TEMP%\ytsh_tel_hw_%RANDOM%%RANDOM%.ps1"
(
    echo try {
    echo     $r = 'HKCU:\SOFTWARE\Microsoft\Personalization\Settings'
    echo     if ^(-not ^(Test-Path $r^)^) { New-Item -Path $r -Force ^| Out-Null }
    echo     Set-ItemProperty -Path $r -Name 'AcceptedPrivacyPolicy' -Value 0 -Type DWord -Force
    echo     $r2 = 'HKCU:\SOFTWARE\Microsoft\InputPersonalization'
    echo     if ^(-not ^(Test-Path $r2^)^) { New-Item -Path $r2 -Force ^| Out-Null }
    echo     Set-ItemProperty -Path $r2 -Name 'RestrictImplicitInkCollection' -Value 1 -Type DWord -Force
    echo     Set-ItemProperty -Path $r2 -Name 'RestrictImplicitTextCollection' -Value 1 -Type DWord -Force
    echo     $r3 = 'HKCU:\SOFTWARE\Microsoft\InputPersonalization\TrainedDataStore'
    echo     if ^(-not ^(Test-Path $r3^)^) { New-Item -Path $r3 -Force ^| Out-Null }
    echo     Set-ItemProperty -Path $r3 -Name 'HarvestContacts' -Value 0 -Type DWord -Force
    echo     Write-Host '  [SUCCESS] Handwriting Personalization Data Disabled.' -ForegroundColor Green
    echo } catch { Write-Host ^('  [FAIL] ' + $_.Exception.Message^) -ForegroundColor Red }
) > "%TELSCRIPT%"
powershell -NoProfile -ExecutionPolicy Bypass -File "%TELSCRIPT%"
del "%TELSCRIPT%" >nul 2>&1
echo.
echo  Done. Press any key to return.
echo.
pause
goto DEBLOAT_MENU

:DO_TEL_TYPING
cls
color !COL_OPS!
echo.
echo  =============================================
echo   Disabling: Typing Insights Data Collection
echo  =============================================
echo.
set "TELSCRIPT=%TEMP%\ytsh_tel_ti_%RANDOM%%RANDOM%.ps1"
(
    echo try {
    echo     $r = 'HKCU:\SOFTWARE\Microsoft\Input\TIPC'
    echo     if ^(-not ^(Test-Path $r^)^) { New-Item -Path $r -Force ^| Out-Null }
    echo     Set-ItemProperty -Path $r -Name 'Enabled' -Value 0 -Type DWord -Force
    echo     Write-Host '  [SUCCESS] Typing Insights Data Collection Disabled.' -ForegroundColor Green
    echo } catch { Write-Host ^('  [FAIL] ' + $_.Exception.Message^) -ForegroundColor Red }
) > "%TELSCRIPT%"
powershell -NoProfile -ExecutionPolicy Bypass -File "%TELSCRIPT%"
del "%TELSCRIPT%" >nul 2>&1
echo.
echo  Done. Press any key to return.
echo.
pause
goto DEBLOAT_MENU

:DO_TEL_SPEECH
cls
color !COL_OPS!
echo.
echo  =============================================
echo   Disabling: Speech Personalization
echo  =============================================
echo.
set "TELSCRIPT=%TEMP%\ytsh_tel_sp_%RANDOM%%RANDOM%.ps1"
(
    echo try {
    echo     $r = 'HKCU:\SOFTWARE\Microsoft\Speech_OneCore\Settings\OnlineSpeechPrivacy'
    echo     if ^(-not ^(Test-Path $r^)^) { New-Item -Path $r -Force ^| Out-Null }
    echo     Set-ItemProperty -Path $r -Name 'HasAccepted' -Value 0 -Type DWord -Force
    echo     Write-Host '  [SUCCESS] Speech Personalization Data Disabled.' -ForegroundColor Green
    echo } catch { Write-Host ^('  [FAIL] ' + $_.Exception.Message^) -ForegroundColor Red }
) > "%TELSCRIPT%"
powershell -NoProfile -ExecutionPolicy Bypass -File "%TELSCRIPT%"
del "%TELSCRIPT%" >nul 2>&1
echo.
echo  Done. Press any key to return.
echo.
pause
goto DEBLOAT_MENU

:DO_TEL_WIFISENSE
cls
color !COL_OPS!
echo.
echo  =============================================
echo   Disabling: Wi-Fi Sense
echo  =============================================
echo.
set "TELSCRIPT=%TEMP%\ytsh_tel_ws_%RANDOM%%RANDOM%.ps1"
(
    echo try {
    echo     $r = 'HKLM:\SOFTWARE\Microsoft\WcmSvc\wifinetworkmanager\config'
    echo     if ^(-not ^(Test-Path $r^)^) { New-Item -Path $r -Force ^| Out-Null }
    echo     Set-ItemProperty -Path $r -Name 'AutoConnectAllowedOEM' -Value 0 -Type DWord -Force
    echo     Write-Host '  [SUCCESS] Wi-Fi Sense Disabled.' -ForegroundColor Green
    echo } catch { Write-Host ^('  [FAIL] ' + $_.Exception.Message^) -ForegroundColor Red }
) > "%TELSCRIPT%"
powershell -NoProfile -ExecutionPolicy Bypass -File "%TELSCRIPT%"
del "%TELSCRIPT%" >nul 2>&1
echo.
echo  Done. Press any key to return.
echo.
pause
goto DEBLOAT_MENU

:PRESET_MODE_BLOCKED
color !COL_ERR!
echo.
powershell -NoProfile -Command "Write-Host '  [BLOCKED] Presets are only available in DEFAULT mode.' -ForegroundColor Red"
powershell -NoProfile -Command "Write-Host '  In !DEBLOAT_MODE! mode use A to Apply All (mode-safe).' -ForegroundColor Yellow"
echo.
pause
goto DEBLOAT_MENU

:DEBLOAT_ALL_MODEAWARE
if "!SAFE_MODE!"=="1" if "!DEBLOAT_MODE!"=="DEFAULT" goto DEBLOAT_ALL_SAFE
if "!DEBLOAT_MODE!"=="DEFAULT" goto DEBLOAT_ALL
if "!DEBLOAT_MODE!"=="NEWBIE"  goto DEBLOAT_ALL_NEWBIE
if "!DEBLOAT_MODE!"=="STUDENT" goto DEBLOAT_ALL_STUDENT
if "!DEBLOAT_MODE!"=="GAMER"   goto DEBLOAT_ALL_GAMER
goto DEBLOAT_ALL

:DEBLOAT_ALL_SAFE
cls
color !COL_OPS!
echo.
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '   APPLY ALL  [DEFAULT MODE + SAFE MODE]' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
echo.
echo   Safe Mode is ON. The following AGGRESSIVE items will be skipped:
powershell -NoProfile -Command "Write-Host '    - Cortana Search Stub ^(38^)' -ForegroundColor Yellow"
powershell -NoProfile -Command "Write-Host '    - WSearch service ^(61^)' -ForegroundColor Yellow"
if "!SYS_DISK_TYPE!"=="HDD" powershell -NoProfile -Command "Write-Host '    - SysMain disable ^(90^) - HDD detected, would slow your PC' -ForegroundColor Yellow"
echo.
echo   All SAFE and BALANCED items will still be applied.
echo   A System Restore Point will be created first. Save all work.
echo.
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
echo.
set "CONFIRM="
set /p "CONFIRM=  Type YES to continue or NO to cancel: "
if /i "!CONFIRM!"=="NO" goto DEBLOAT_MENU
if /i not "!CONFIRM!"=="YES" goto DEBLOAT_MENU
call :CREATE_RESTORE_POINT
if !errorLevel! neq 0 goto RESTORE_POINT_FAILED_FULL
call :DO_REMOVE_ALL_APPS_NEWBIE
call :DO_DISABLE_ALL_SERVICES_NEWBIE
call :DO_DISABLE_ALL_TELEMETRY
echo.
echo  =============================================
powershell -NoProfile -Command "Write-Host '   Safe Mode Debloat Complete. Restart recommended.' -ForegroundColor Green"
echo  =============================================
echo.
call :COUNTDOWN_RESTART
goto MAIN_MENU

:DEBLOAT_ALL_NEWBIE
cls
color !COL_OPS!
echo.
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '   APPLY ALL  [NEWBIE MODE - SAFE ONLY]' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
echo.
echo   Removes all SAFE-tagged apps and disables SAFE services only.
echo   Skipped: Xbox apps, OneDrive, Mail, Maps, Alarms, Sticky Notes,
echo            Cortana, Outlook, and all BALANCED/AGGRESSIVE items.
echo.
echo   A System Restore Point will be created first. Save all work.
echo.
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
echo.
set "CONFIRM="
set /p "CONFIRM=  Type YES to continue or NO to cancel: "
if /i "!CONFIRM!"=="NO" goto DEBLOAT_MENU
if /i not "!CONFIRM!"=="YES" goto DEBLOAT_MENU
call :CREATE_RESTORE_POINT
if !errorLevel! neq 0 goto RESTORE_POINT_FAILED_FULL
call :DO_REMOVE_ALL_APPS_NEWBIE
call :DO_DISABLE_ALL_SERVICES_NEWBIE
call :DO_DISABLE_ALL_TELEMETRY
echo.
echo  =============================================
powershell -NoProfile -Command "Write-Host '   Newbie Debloat Complete. Restart recommended.' -ForegroundColor Green"
echo  =============================================
echo.
call :COUNTDOWN_RESTART
goto MAIN_MENU

:DEBLOAT_ALL_STUDENT
cls
color !COL_OPS!
echo.
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '   APPLY ALL  [STUDENT MODE - SCHOOL SAFE]' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
echo.
echo   Removes all SAFE-tagged apps and disables SAFE services only.
powershell -NoProfile -Command "Write-Host '   PROTECTED (will NOT be removed):' -ForegroundColor Green"
powershell -NoProfile -Command "Write-Host '   Microsoft Teams  ^|  OneNote  ^|  Microsoft To Do' -ForegroundColor Green"
echo   Also skipped: Xbox, OneDrive, Mail, Maps, Alarms, Sticky Notes,
echo                 Cortana, Outlook, and all BALANCED/AGGRESSIVE items.
echo.
echo   A System Restore Point will be created first. Save all work.
echo.
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
echo.
set "CONFIRM="
set /p "CONFIRM=  Type YES to continue or NO to cancel: "
if /i "!CONFIRM!"=="NO" goto DEBLOAT_MENU
if /i not "!CONFIRM!"=="YES" goto DEBLOAT_MENU
call :CREATE_RESTORE_POINT
if !errorLevel! neq 0 goto RESTORE_POINT_FAILED_FULL
call :DO_REMOVE_ALL_APPS_STUDENT
call :DO_DISABLE_ALL_SERVICES_NEWBIE
call :DO_DISABLE_ALL_TELEMETRY
echo.
echo  =============================================
powershell -NoProfile -Command "Write-Host '   Student Debloat Complete. Restart recommended.' -ForegroundColor Green"
echo  =============================================
echo.
call :COUNTDOWN_RESTART
goto MAIN_MENU

:DEBLOAT_ALL_GAMER
cls
color !COL_OPS!
echo.
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '   APPLY ALL  [GAMER MODE - SAFE + XBOX PURGE]' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
echo.
echo   Removes SAFE apps + all Xbox/gaming bloat.
echo   Also disables SAFE services + Xbox services.
echo   Skipped: OneDrive, Mail, Maps, Alarms, Sticky Notes, Cortana,
echo            Outlook, and all BALANCED/AGGRESSIVE items.
echo.
echo   A System Restore Point will be created first. Save all work.
echo.
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
echo.
set "CONFIRM="
set /p "CONFIRM=  Type YES to continue or NO to cancel: "
if /i "!CONFIRM!"=="NO" goto DEBLOAT_MENU
if /i not "!CONFIRM!"=="YES" goto DEBLOAT_MENU
call :CREATE_RESTORE_POINT
if !errorLevel! neq 0 goto RESTORE_POINT_FAILED_FULL
call :DO_REMOVE_ALL_APPS_GAMER
call :DO_DISABLE_ALL_SERVICES_GAMER
call :DO_DISABLE_ALL_TELEMETRY
echo.
echo  =============================================
powershell -NoProfile -Command "Write-Host '   Gamer Debloat Complete. Restart recommended.' -ForegroundColor Green"
echo  =============================================
echo.
call :COUNTDOWN_RESTART
goto MAIN_MENU

:DEBLOAT_ALL
cls
color !COL_OPS!
echo.
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '   FULL DEBLOAT - ALL 90 OPTIONS' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
echo.
echo   What am I about to do?
echo    * Remove ALL pre-installed bloatware (Candy Crush, Xbox Apps, etc.)
echo    * Remove ALL OEM stubs (TikTok, Spotify, Netflix, etc.) if they exist
echo    * Disable ALL unnecessary background services (DiagTrack, RetailDemo, etc.)
echo    * Disable ALL telemetry, tracking, and diagnostic data collection
echo    * Disable Global UWP Background Apps and SysMain (if applicable)
echo.
echo   A System Restore Point will be created first.
echo   Your PC may need a restart after completion.
echo   Save all open work before continuing.
echo.
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
echo.
set "CONFIRM="
set /p "CONFIRM=  Type YES to continue, PREVIEW for a dry-run, or NO to cancel: "

if /i "!CONFIRM!"=="PREVIEW" goto PREVIEW_DEBLOAT

if /i "!CONFIRM!"=="NO" (
    echo.
    powershell -NoProfile -Command "Write-Host '  Cancelled. Returning to menu.' -ForegroundColor Red"
    pause
    goto DEBLOAT_MENU
)
if /i not "!CONFIRM!"=="YES" (
    echo.
    powershell -NoProfile -Command "Write-Host '  [!] Unrecognized input. Returning to menu.' -ForegroundColor Red"
    pause
    goto DEBLOAT_MENU
)
call :CREATE_RESTORE_POINT
if !errorLevel! neq 0 goto RESTORE_POINT_FAILED_FULL
call :DO_REMOVE_ALL_APPS
call :DO_DISABLE_ALL_SERVICES
call :DO_DISABLE_ALL_TELEMETRY
echo.
echo  =============================================
powershell -NoProfile -Command "Write-Host '   Full Debloat Complete.' -ForegroundColor Green"
echo   Logs saved next to this script. Restart recommended.
echo  =============================================
echo.
call :COUNTDOWN_RESTART
goto MAIN_MENU
:PREVIEW_DEBLOAT
cls
color !COL_OPS!
set "PREVIEW_TXT=%TEMP%\ytsh_debloat_preview.txt"

echo ============================================ > "%PREVIEW_TXT%"
echo   YTSH DEBLOAT UTILITY - DRY RUN PREVIEW    >> "%PREVIEW_TXT%"
echo ============================================ >> "%PREVIEW_TXT%"
echo. >> "%PREVIEW_TXT%"
echo [APPS TO BE REMOVED] >> "%PREVIEW_TXT%"
echo Microsoft.549981C3F5F10 (Cortana) >> "%PREVIEW_TXT%"
echo Microsoft.BingNews >> "%PREVIEW_TXT%"
echo Microsoft.BingWeather >> "%PREVIEW_TXT%"
echo Microsoft.BingSearch >> "%PREVIEW_TXT%"
echo Microsoft.GamingApp >> "%PREVIEW_TXT%"
echo Microsoft.GetHelp >> "%PREVIEW_TXT%"
echo Microsoft.Getstarted >> "%PREVIEW_TXT%"
echo Microsoft.MicrosoftOfficeHub >> "%PREVIEW_TXT%"
echo Microsoft.MicrosoftSolitaireCollection >> "%PREVIEW_TXT%"
echo Microsoft.MixedReality.Portal >> "%PREVIEW_TXT%"
echo Microsoft.People >> "%PREVIEW_TXT%"
echo Microsoft.PowerAutomateDesktop >> "%PREVIEW_TXT%"
echo Microsoft.SkypeApp >> "%PREVIEW_TXT%"
echo Microsoft.Todos >> "%PREVIEW_TXT%"
echo Microsoft.WindowsAlarms >> "%PREVIEW_TXT%"
echo Microsoft.WindowsCommunicationsApps >> "%PREVIEW_TXT%"
echo Microsoft.WindowsFeedbackHub >> "%PREVIEW_TXT%"
echo Microsoft.WindowsMaps >> "%PREVIEW_TXT%"
echo Microsoft.WindowsSoundRecorder >> "%PREVIEW_TXT%"
echo Microsoft.XboxApp >> "%PREVIEW_TXT%"
echo Microsoft.XboxGameOverlay >> "%PREVIEW_TXT%"
echo Microsoft.XboxGamingOverlay >> "%PREVIEW_TXT%"
echo Microsoft.XboxIdentityProvider >> "%PREVIEW_TXT%"
echo Microsoft.XboxSpeechToTextOverlay >> "%PREVIEW_TXT%"
echo Microsoft.YourPhone >> "%PREVIEW_TXT%"
echo Microsoft.ZuneMusic >> "%PREVIEW_TXT%"
echo Microsoft.ZuneVideo >> "%PREVIEW_TXT%"
echo Clipchamp.Clipchamp >> "%PREVIEW_TXT%"
echo MicrosoftTeams >> "%PREVIEW_TXT%"
echo Microsoft.OutlookForWindows >> "%PREVIEW_TXT%"
echo Microsoft.Microsoft3DViewer >> "%PREVIEW_TXT%"
echo Microsoft.Print3D >> "%PREVIEW_TXT%"
echo Microsoft.3DBuilder >> "%PREVIEW_TXT%"
echo Microsoft.MicrosoftStickyNotes >> "%PREVIEW_TXT%"
echo Microsoft.OneDriveSync >> "%PREVIEW_TXT%"
echo Microsoft.Cortana >> "%PREVIEW_TXT%"
echo Microsoft.WindowsFeedback >> "%PREVIEW_TXT%"
echo Microsoft.Office.OneNote >> "%PREVIEW_TXT%"
echo Microsoft.OneConnect >> "%PREVIEW_TXT%"
echo Microsoft.Wallet >> "%PREVIEW_TXT%"
echo Microsoft.MicrosoftStart >> "%PREVIEW_TXT%"
echo MicrosoftWindows.Client.WebExperience >> "%PREVIEW_TXT%"
echo Microsoft.Messaging >> "%PREVIEW_TXT%"
echo Microsoft.CommsPhone >> "%PREVIEW_TXT%"
echo Microsoft.NetworkSpeedTest >> "%PREVIEW_TXT%"
echo. >> "%PREVIEW_TXT%"
echo [OEM STUBS TO BE REMOVED (If found)] >> "%PREVIEW_TXT%"
echo *Disney*, *TikTok*, *Instagram*, *Facebook*, *Twitter*, *Spotify*, *PrimeVideo*, *AmazonVideo*, *Dolby*, *LinkedInforWindows*, *Netflix*, *Hulu*, *PandoraMediaInc*, *iHeartRadio*, *CandyCrush*, *FarmVille*, *Roblox*, *EclipseManager*, *ActiproSoftwareLLC*, *AdobeSystemsIncorporated*, *Duolingo*, *EvernoteWindows* >> "%PREVIEW_TXT%"
echo. >> "%PREVIEW_TXT%"
echo [SERVICES TO BE DISABLED] >> "%PREVIEW_TXT%"
echo DiagTrack (Diagnostic Tracking) >> "%PREVIEW_TXT%"
echo WMPNetworkSvc (Windows Media Player Network Sharing) >> "%PREVIEW_TXT%"
echo RemoteRegistry >> "%PREVIEW_TXT%"
echo Fax >> "%PREVIEW_TXT%"
echo WerSvc (Windows Error Reporting) >> "%PREVIEW_TXT%"
echo MapsBroker >> "%PREVIEW_TXT%"
echo RetailDemo >> "%PREVIEW_TXT%"
echo XblAuthManager, XblGameSave, XboxNetApiSvc, XboxGipSvc (Xbox Services) >> "%PREVIEW_TXT%"
echo wisvc (Windows Insider) >> "%PREVIEW_TXT%"
echo WSearch (Windows Search) >> "%PREVIEW_TXT%"
echo lfsvc (Geolocation) >> "%PREVIEW_TXT%"
echo SharedAccess (ICS) >> "%PREVIEW_TXT%"
echo TrkWks (Distributed Link Tracking) >> "%PREVIEW_TXT%"
echo WbioSrvc (Biometric) >> "%PREVIEW_TXT%"
echo icssvc (Mobile Hotspot) >> "%PREVIEW_TXT%"
echo PhoneSvc, SmsRouter >> "%PREVIEW_TXT%"
echo TabletInputService >> "%PREVIEW_TXT%"
echo WpcMonSvc (Parental Controls) >> "%PREVIEW_TXT%"
echo PrintNotify >> "%PREVIEW_TXT%"
echo PcaSvc (Program Compatibility) >> "%PREVIEW_TXT%"
echo HomeGroupListener, HomeGroupProvider >> "%PREVIEW_TXT%"
echo. >> "%PREVIEW_TXT%"
echo [REGISTRY KEYS TO BE MODIFIED] >> "%PREVIEW_TXT%"
echo HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection\AllowTelemetry = 0 >> "%PREVIEW_TXT%"
echo HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\AdvertisingInfo\Enabled = 0 >> "%PREVIEW_TXT%"
echo HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Privacy\TailoredExperiencesWithDiagnosticDataEnabled = 0 >> "%PREVIEW_TXT%"
echo HKCU\SOFTWARE\Microsoft\Siuf\Rules\NumberOfSIUFInPeriod = 0 >> "%PREVIEW_TXT%"
echo HKLM\SOFTWARE\Policies\Microsoft\Windows\System\EnableActivityFeed = 0 >> "%PREVIEW_TXT%"
echo HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced\Start_TrackProgs = 0 >> "%PREVIEW_TXT%"
echo HKLM\SOFTWARE\Policies\Microsoft\Windows\AppCompat\AITEnable = 0 >> "%PREVIEW_TXT%"
echo HKLM\SOFTWARE\Policies\Microsoft\Windows\CloudContent\DisableWindowsConsumerFeatures = 1 >> "%PREVIEW_TXT%"
echo HKCU\SOFTWARE\Microsoft\Personalization\Settings\AcceptedPrivacyPolicy = 0 >> "%PREVIEW_TXT%"
echo HKCU\SOFTWARE\Microsoft\Input\TIPC\Enabled = 0 >> "%PREVIEW_TXT%"
echo HKCU\SOFTWARE\Microsoft\Speech_OneCore\Settings\OnlineSpeechPrivacy\HasAccepted = 0 >> "%PREVIEW_TXT%"
echo HKLM\SOFTWARE\Microsoft\WcmSvc\wifinetworkmanager\config\AutoConnectAllowedOEM = 0 >> "%PREVIEW_TXT%"
echo HKCU\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications\GlobalUserDisabled = 1 >> "%PREVIEW_TXT%"
echo. >> "%PREVIEW_TXT%"
echo [SCHEDULED TASKS TO BE DISABLED] >> "%PREVIEW_TXT%"
echo \Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser >> "%PREVIEW_TXT%"
echo \Microsoft\Windows\Customer Experience Improvement Program\Consolidator >> "%PREVIEW_TXT%"
echo (And 4 other related CEIP/DiskDiagnostic tasks) >> "%PREVIEW_TXT%"
echo ============================================ >> "%PREVIEW_TXT%"

start notepad "%PREVIEW_TXT%"

powershell -NoProfile -Command "Write-Host '  [INFO] Opened Dry-Run Preview in Notepad.' -ForegroundColor Cyan"
echo.
pause
goto DEBLOAT_ALL

:REVERT_MENU
cls
color !COL_OPS!
echo.
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '    REVERT OPTIONS' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
echo.
powershell -NoProfile -Command "Write-Host '   --- BLOATWARE APPS ---' -ForegroundColor !COL_HDR_PS!"
echo    01  Candy Crush Saga
echo    02  Microsoft Solitaire Collection
echo    03  Bing News
echo    04  Bing Weather
echo    05  Bing Search
echo    06  Xbox App
echo    07  Xbox Game Bar ^& Overlay
echo    08  Xbox Identity Provider
echo    09  Xbox Speech-To-Text Overlay
echo    10  Skype
echo    11  Microsoft Teams (personal)
echo    12  Clipchamp Video Editor
echo    13  Mail and Calendar
echo    14  People App
echo    15  Windows Maps
echo    16  Windows Alarms ^& Clock
echo    17  Mixed Reality Portal
echo    18  3D Viewer
echo    19  Print 3D
echo    20  3D Builder
echo    21  Feedback Hub
echo    22  Get Help
echo    23  Get Started / Tips
echo    24  Power Automate Desktop
echo    25  Microsoft To Do
echo    26  Sticky Notes
echo    27  Office Hub
echo    28  OneDrive Sync Stub
echo    29  Sound Recorder
echo    30  Groove Music
echo    31  Movies ^& TV
echo    32  Your Phone / Phone Link
echo    33  Cortana App
echo    34  OneNote (bundled)
echo    35  Microsoft Wallet
echo    36  OneConnect
echo    37  Outlook for Windows
echo    38  Cortana Search Integration
echo    39  Microsoft Start
echo    93  Windows Camera
echo    94  Microsoft Whiteboard
echo    95  Web Media Extensions
echo    96  HEVC Video Extension
echo    97  VP9 Video Extensions
if "!_WIN11!"=="1" echo    98  Windows Widgets ^& News (Win11)
if "!_WIN11!"=="1" echo    99  Windows Copilot Sidebar (Win11 23H2+)
if "!_WIN10!"=="1" echo    98  Xbox Console Companion (Win10)
echo.
powershell -NoProfile -Command "Write-Host '   --- BRAND-SPECIFIC BLOATS [!SYS_BRAND!] ---' -ForegroundColor !COL_HDR_PS!"
if "!SYS_BRAND!"=="HP" (
    echo    H1  HP JumpStart
    echo    H2  HP Support Assistant
    echo    H3  HP Smart
    echo    H4  HP Quick Drop
    echo    H5  HP Audio Switch
    echo    H6  HP Touchpoint Analytics
)
if "!SYS_BRAND!"=="Dell" (
    echo    D1  Dell SupportAssist
    echo    D2  Dell Digital Delivery
    echo    D3  Dell Update
    if "!SYS_FORM!"=="LAPTOP" (
        echo    D4  Dell Mobile Connect
    )
    echo    D5  MyDell
    echo    D6  Dell Customer Connect
)
if "!SYS_BRAND!"=="Lenovo" (
    echo    L1  Lenovo Vantage
    echo    L2  Lenovo Now / Settings App
    echo    L3  Lenovo Companion
    echo    L4  WinZip
    echo    L5  McAfee
)
if "!SYS_BRAND!"=="ASUS" (
    if "!SYS_FORM!"=="LAPTOP" (
        echo    AS1  MyASUS
    )
    echo    AS2  McAfee
    echo    AS3  ASUS Live Update
)
if "!SYS_BRAND!"=="Acer" (
    echo    AC1  Acer Care Center
    echo    AC2  McAfee
    echo    AC3  Acer Collection
    echo    AC4  Acer Portal
)
if "!SYS_BRAND!"=="MSI" (
    echo    MS1  MSI Center / Dragon Center
    echo    MS2  McAfee
    echo    MS3  MSI App Player
)
if "!SYS_BRAND!"=="Samsung" (
    if "!SYS_FORM!"=="LAPTOP" (
        echo    SA1  Samsung Settings
    )
    echo    SA2  McAfee
    echo    SA3  Samsung Notes
)
if "!SYS_BRAND!"=="Microsoft" (
    if "!SYS_FORM!"=="LAPTOP" (
        echo    SU1  Surface App
        echo    SU2  Surface Hub
    )
)
echo.
powershell -NoProfile -Command "Write-Host '   --- SERVICES ---' -ForegroundColor !COL_HDR_PS!"
echo    49  DiagTrack
echo    50  WMPNetworkSvc
echo    51  RemoteRegistry
echo    52  Fax
echo    53  WerSvc
echo    54  MapsBroker
echo    55  RetailDemo
echo    56  XblAuthManager
echo    57  XblGameSave
echo    58  XboxNetApiSvc
echo    59  XboxGipSvc
echo    60  wisvc
echo    61  WSearch
echo    62  lfsvc
echo    63  SharedAccess
echo    64  TrkWks
echo    65  WbioSrvc
echo    66  icssvc
echo    67  PhoneSvc
echo    68  SmsRouter
echo    69  TabletInputService
echo    70  WpcMonSvc
echo    71  PrintNotify
echo    72  PcaSvc
echo    73  HomeGroupListener
echo    74  HomeGroupProvider
echo.
powershell -NoProfile -Command "Write-Host '   --- TELEMETRY & PRIVACY ---' -ForegroundColor !COL_HDR_PS!"
echo    75  Diagnostic Data Collection
echo    76  Advertising ID
echo    77  Tailored Experiences
echo    78  Feedback Notifications
echo    79  Activity History / Timeline
echo    80  App Launch Tracking
echo    81  Location Tracking
echo    82  AppCompat Telemetry
echo    83  Windows Consumer Features
echo    84  CEIP Scheduled Tasks
echo    85  Handwriting Personalization
echo    86  Typing Insights
echo    87  Speech Personalization
echo    88  Wi-Fi Sense
echo    89  Enable UWP Background Apps
echo    90  Enable SysMain / Superfetch
echo.
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
echo.
powershell -NoProfile -Command "Write-Host '   --- PRESETS ---' -ForegroundColor !COL_HDR_PS!"
echo    P1  Microsoft Games
echo    P2  School / Work Bloat
echo    P3  3D and Mixed Reality
echo    P4  Privacy Pack
echo    P5  Bing / News / Cortana
echo    P6  Media and Music
echo    P7  Communication Apps
echo    P8  Performance Pack
echo.
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
echo.
powershell -NoProfile -Command "Write-Host '   A   REVERT ALL' -ForegroundColor Yellow"
echo.
echo     B  ^>  Back to main menu
echo.
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
echo.
set "RCHOICE="
set /p "RCHOICE=  Enter option number (or A for ALL, P1-P8 for Presets): "

if /i "!RCHOICE!"=="B" goto MAIN_MENU
if /i "!RCHOICE!"=="A" goto REVERT_ALL
if /i "!RCHOICE!"=="P1" goto REVERT_PRESET_GAMES
if /i "!RCHOICE!"=="P2" goto REVERT_PRESET_SCHOOL
if /i "!RCHOICE!"=="P3" goto REVERT_PRESET_3D
if /i "!RCHOICE!"=="P4" goto REVERT_PRESET_PRIVACY
if /i "!RCHOICE!"=="P5" goto REVERT_PRESET_BING
if /i "!RCHOICE!"=="P6" goto REVERT_PRESET_MEDIA
if /i "!RCHOICE!"=="P7" goto REVERT_PRESET_COMMS
if /i "!RCHOICE!"=="P8" goto REVERT_PRESET_PERF
if "!RCHOICE!"=="89" goto REVERT_RAM_BGAPPS
if "!RCHOICE!"=="90" set "RSVC=SysMain" & goto REVERT_SINGLE_SVC

if "!RCHOICE!"=="01" set "RPKG=Microsoft.MicrosoftSolitaireCollection" & goto REVERT_SINGLE_APP
if "!RCHOICE!"=="1"  set "RPKG=Microsoft.MicrosoftSolitaireCollection" & goto REVERT_SINGLE_APP
if "!RCHOICE!"=="02" set "RPKG=Microsoft.MicrosoftSolitaireCollection" & goto REVERT_SINGLE_APP
if "!RCHOICE!"=="2"  set "RPKG=Microsoft.MicrosoftSolitaireCollection" & goto REVERT_SINGLE_APP
if "!RCHOICE!"=="03" set "RPKG=Microsoft.BingNews" & goto REVERT_SINGLE_APP
if "!RCHOICE!"=="3"  set "RPKG=Microsoft.BingNews" & goto REVERT_SINGLE_APP
if "!RCHOICE!"=="04" set "RPKG=Microsoft.BingWeather" & goto REVERT_SINGLE_APP
if "!RCHOICE!"=="4"  set "RPKG=Microsoft.BingWeather" & goto REVERT_SINGLE_APP
if "!RCHOICE!"=="05" set "RPKG=Microsoft.BingSearch" & goto REVERT_SINGLE_APP
if "!RCHOICE!"=="5"  set "RPKG=Microsoft.BingSearch" & goto REVERT_SINGLE_APP
if "!RCHOICE!"=="06" set "RPKG=Microsoft.GamingApp" & goto REVERT_SINGLE_APP
if "!RCHOICE!"=="6"  set "RPKG=Microsoft.GamingApp" & goto REVERT_SINGLE_APP
if "!RCHOICE!"=="07" set "RPKG=XBOX_OVERLAY_R" & goto REVERT_XBOX_OVERLAY
if "!RCHOICE!"=="7"  set "RPKG=XBOX_OVERLAY_R" & goto REVERT_XBOX_OVERLAY
if "!RCHOICE!"=="08" set "RPKG=Microsoft.XboxIdentityProvider" & goto REVERT_SINGLE_APP
if "!RCHOICE!"=="8"  set "RPKG=Microsoft.XboxIdentityProvider" & goto REVERT_SINGLE_APP
if "!RCHOICE!"=="09" set "RPKG=Microsoft.XboxSpeechToTextOverlay" & goto REVERT_SINGLE_APP
if "!RCHOICE!"=="9"  set "RPKG=Microsoft.XboxSpeechToTextOverlay" & goto REVERT_SINGLE_APP
if "!RCHOICE!"=="10" set "RPKG=Microsoft.SkypeApp" & goto REVERT_SINGLE_APP
if "!RCHOICE!"=="11" set "RPKG=MicrosoftTeams" & goto REVERT_SINGLE_APP
if "!RCHOICE!"=="12" set "RPKG=Clipchamp.Clipchamp" & goto REVERT_SINGLE_APP
if "!RCHOICE!"=="13" set "RPKG=Microsoft.WindowsCommunicationsApps" & goto REVERT_SINGLE_APP
if "!RCHOICE!"=="14" set "RPKG=Microsoft.People" & goto REVERT_SINGLE_APP
if "!RCHOICE!"=="15" set "RPKG=Microsoft.WindowsMaps" & goto REVERT_SINGLE_APP
if "!RCHOICE!"=="16" set "RPKG=Microsoft.WindowsAlarms" & goto REVERT_SINGLE_APP
if "!RCHOICE!"=="17" set "RPKG=Microsoft.MixedReality.Portal" & goto REVERT_SINGLE_APP
if "!RCHOICE!"=="18" set "RPKG=Microsoft.Microsoft3DViewer" & goto REVERT_SINGLE_APP
if "!RCHOICE!"=="19" set "RPKG=Microsoft.Print3D" & goto REVERT_SINGLE_APP
if "!RCHOICE!"=="20" set "RPKG=Microsoft.3DBuilder" & goto REVERT_SINGLE_APP
if "!RCHOICE!"=="21" set "RPKG=Microsoft.WindowsFeedbackHub" & goto REVERT_SINGLE_APP
if "!RCHOICE!"=="22" set "RPKG=Microsoft.GetHelp" & goto REVERT_SINGLE_APP
if "!RCHOICE!"=="23" set "RPKG=Microsoft.Getstarted" & goto REVERT_SINGLE_APP
if "!RCHOICE!"=="24" set "RPKG=Microsoft.PowerAutomateDesktop" & goto REVERT_SINGLE_APP
if "!RCHOICE!"=="25" set "RPKG=Microsoft.Todos" & goto REVERT_SINGLE_APP
if "!RCHOICE!"=="26" set "RPKG=Microsoft.MicrosoftStickyNotes" & goto REVERT_SINGLE_APP
if "!RCHOICE!"=="27" set "RPKG=Microsoft.MicrosoftOfficeHub" & goto REVERT_SINGLE_APP
if "!RCHOICE!"=="28" set "RPKG=Microsoft.OneDriveSync" & goto REVERT_SINGLE_APP
if "!RCHOICE!"=="29" set "RPKG=Microsoft.WindowsSoundRecorder" & goto REVERT_SINGLE_APP
if "!RCHOICE!"=="30" set "RPKG=Microsoft.ZuneMusic" & goto REVERT_SINGLE_APP
if "!RCHOICE!"=="31" set "RPKG=Microsoft.ZuneVideo" & goto REVERT_SINGLE_APP
if "!RCHOICE!"=="32" set "RPKG=Microsoft.YourPhone" & goto REVERT_SINGLE_APP
if "!RCHOICE!"=="33" set "RPKG=Microsoft.Cortana" & goto REVERT_SINGLE_APP
if "!RCHOICE!"=="34" set "RPKG=Microsoft.Office.OneNote" & goto REVERT_SINGLE_APP
if "!RCHOICE!"=="35" set "RPKG=Microsoft.Wallet" & goto REVERT_SINGLE_APP
if "!RCHOICE!"=="36" set "RPKG=Microsoft.OneConnect" & goto REVERT_SINGLE_APP
if "!RCHOICE!"=="37" set "RPKG=Microsoft.OutlookForWindows" & goto REVERT_SINGLE_APP
if "!RCHOICE!"=="38" set "RPKG=Microsoft.549981C3F5F10" & goto REVERT_SINGLE_APP
if "!RCHOICE!"=="93" set "RPKG=Microsoft.WindowsCamera" & goto REVERT_SINGLE_APP
if "!RCHOICE!"=="94" set "RPKG=Microsoft.Whiteboard" & goto REVERT_SINGLE_APP
if "!RCHOICE!"=="95" set "RPKG=Microsoft.WebMediaExtensions" & goto REVERT_SINGLE_APP
if "!RCHOICE!"=="96" set "RPKG=Microsoft.HEVCVideoExtension" & goto REVERT_SINGLE_APP
if "!RCHOICE!"=="97" set "RPKG=Microsoft.VP9VideoExtensions" & goto REVERT_SINGLE_APP
if "!RCHOICE!"=="98" (
    if "!_WIN11!"=="1" set "RPKG=MicrosoftWindows.Client.WebExperience" & goto REVERT_SINGLE_APP
    if "!_WIN10!"=="1" set "RPKG=Microsoft.XboxApp" & goto REVERT_SINGLE_APP
)
if "!RCHOICE!"=="99" set "RPKG=Microsoft.Copilot" & goto REVERT_SINGLE_APP
if /i "!RCHOICE!"=="H1" set "RPKG=AD2F1837.HPJumpStarts" & goto REVERT_SINGLE_APP
if /i "!RCHOICE!"=="H2" set "RPKG=AD2F1837.HPSupportAssistant" & goto REVERT_SINGLE_APP
if /i "!RCHOICE!"=="H3" set "RPKG=AD2F1837.HPPrinterControl" & goto REVERT_SINGLE_APP
if /i "!RCHOICE!"=="H4" set "RPKG=AD2F1837.HPQuickDrop" & goto REVERT_SINGLE_APP
if /i "!RCHOICE!"=="H5" set "RPKG=AD2F1837.HPAudioSwitch" & goto REVERT_SINGLE_APP
if /i "!RCHOICE!"=="H6" set "RPKG=AD2F1837.HPTouchpointAnalytics" & goto REVERT_SINGLE_APP
if /i "!RCHOICE!"=="D1" set "RPKG=DellInc.DellSupportAssistforPCs" & goto REVERT_SINGLE_APP
if /i "!RCHOICE!"=="D2" set "RPKG=DellInc.DellDigitalDelivery" & goto REVERT_SINGLE_APP
if /i "!RCHOICE!"=="D3" set "RPKG=DellInc.DellUpdate" & goto REVERT_SINGLE_APP
if /i "!RCHOICE!"=="D4" set "RPKG=ScreenovateTechnologies.DellMobileConnect" & goto REVERT_SINGLE_APP
if /i "!RCHOICE!"=="D5" set "RPKG=DellInc.MyDell" & goto REVERT_SINGLE_APP
if /i "!RCHOICE!"=="D6" set "RPKG=DellInc.DellCustomerConnect" & goto REVERT_SINGLE_APP
if /i "!RCHOICE!"=="L1" set "RPKG=E046963F.LenovoCompanion" & goto REVERT_SINGLE_APP
if /i "!RCHOICE!"=="L2" set "RPKG=E046963F.LenovoSettings" & goto REVERT_SINGLE_APP
if /i "!RCHOICE!"=="L3" set "RPKG=E046963F.LenovoCompanion" & goto REVERT_SINGLE_APP
if /i "!RCHOICE!"=="L4" set "RPKG=WinZipComputing.WinZipUniversal" & goto REVERT_SINGLE_APP
if /i "!RCHOICE!"=="L5" set "RPKG=McAfee.McAfeePersonalSecurity" & goto REVERT_SINGLE_APP
if /i "!RCHOICE!"=="AS1" set "RPKG=B9ECED6F.MyASUS" & goto REVERT_SINGLE_APP
if /i "!RCHOICE!"=="AS2" set "RPKG=McAfee.McAfeePersonalSecurity" & goto REVERT_SINGLE_APP
if /i "!RCHOICE!"=="AS3" set "RPKG=B9ECED6F.ASUSLiveUpdate" & goto REVERT_SINGLE_APP
if /i "!RCHOICE!"=="AC1" set "RPKG=AcerInc.AcerCareCenter" & goto REVERT_SINGLE_APP
if /i "!RCHOICE!"=="AC2" set "RPKG=McAfee.McAfeePersonalSecurity" & goto REVERT_SINGLE_APP
if /i "!RCHOICE!"=="AC3" set "RPKG=AcerInc.AcerCollection" & goto REVERT_SINGLE_APP
if /i "!RCHOICE!"=="AC4" set "RPKG=AcerInc.AcerPortal" & goto REVERT_SINGLE_APP
if /i "!RCHOICE!"=="MS1" set "RPKG=9426MICRO-STARINTERNATION.DragonCenter" & goto REVERT_SINGLE_APP
if /i "!RCHOICE!"=="MS2" set "RPKG=McAfee.McAfeePersonalSecurity" & goto REVERT_SINGLE_APP
if /i "!RCHOICE!"=="MS3" set "RPKG=MSIAppPlayer" & goto REVERT_SINGLE_APP
if /i "!RCHOICE!"=="SA1" set "RPKG=SAMSUNGELECTRONICSCO.LTD.SamsungSettings" & goto REVERT_SINGLE_APP
if /i "!RCHOICE!"=="SA2" set "RPKG=McAfee.McAfeePersonalSecurity" & goto REVERT_SINGLE_APP
if /i "!RCHOICE!"=="SA3" set "RPKG=SAMSUNGELECTRONICSCO.LTD.SamsungNotes" & goto REVERT_SINGLE_APP
if /i "!RCHOICE!"=="SU1" set "RPKG=Microsoft.SurfaceHub" & goto REVERT_SINGLE_APP
if /i "!RCHOICE!"=="SU2" set "RPKG=Microsoft.SurfaceHub" & goto REVERT_SINGLE_APP
if "!RCHOICE!"=="49" set "RSVC=DiagTrack" & goto REVERT_SINGLE_SVC
if "!RCHOICE!"=="50" set "RSVC=WMPNetworkSvc" & goto REVERT_SINGLE_SVC
if "!RCHOICE!"=="51" set "RSVC=RemoteRegistry" & goto REVERT_SINGLE_SVC
if "!RCHOICE!"=="52" set "RSVC=Fax" & goto REVERT_SINGLE_SVC
if "!RCHOICE!"=="53" set "RSVC=WerSvc" & goto REVERT_SINGLE_SVC
if "!RCHOICE!"=="54" set "RSVC=MapsBroker" & goto REVERT_SINGLE_SVC
if "!RCHOICE!"=="55" set "RSVC=RetailDemo" & goto REVERT_SINGLE_SVC
if "!RCHOICE!"=="56" set "RSVC=XblAuthManager" & goto REVERT_SINGLE_SVC
if "!RCHOICE!"=="57" set "RSVC=XblGameSave" & goto REVERT_SINGLE_SVC
if "!RCHOICE!"=="58" set "RSVC=XboxNetApiSvc" & goto REVERT_SINGLE_SVC
if "!RCHOICE!"=="59" set "RSVC=XboxGipSvc" & goto REVERT_SINGLE_SVC
if "!RCHOICE!"=="60" set "RSVC=wisvc" & goto REVERT_SINGLE_SVC
if "!RCHOICE!"=="61" set "RSVC=WSearch" & goto REVERT_SINGLE_SVC
if "!RCHOICE!"=="62" set "RSVC=lfsvc" & goto REVERT_SINGLE_SVC
if "!RCHOICE!"=="63" set "RSVC=SharedAccess" & goto REVERT_SINGLE_SVC
if "!RCHOICE!"=="64" set "RSVC=TrkWks" & goto REVERT_SINGLE_SVC
if "!RCHOICE!"=="65" set "RSVC=WbioSrvc" & goto REVERT_SINGLE_SVC
if "!RCHOICE!"=="66" set "RSVC=icssvc" & goto REVERT_SINGLE_SVC
if "!RCHOICE!"=="67" set "RSVC=PhoneSvc" & goto REVERT_SINGLE_SVC
if "!RCHOICE!"=="68" set "RSVC=SmsRouter" & goto REVERT_SINGLE_SVC
if "!RCHOICE!"=="69" set "RSVC=TabletInputService" & goto REVERT_SINGLE_SVC
if "!RCHOICE!"=="70" set "RSVC=WpcMonSvc" & goto REVERT_SINGLE_SVC
if "!RCHOICE!"=="71" set "RSVC=PrintNotify" & goto REVERT_SINGLE_SVC
if "!RCHOICE!"=="72" set "RSVC=PcaSvc" & goto REVERT_SINGLE_SVC
if "!RCHOICE!"=="73" set "RSVC=HomeGroupListener" & goto REVERT_SINGLE_SVC
if "!RCHOICE!"=="74" set "RSVC=HomeGroupProvider" & goto REVERT_SINGLE_SVC
if "!RCHOICE!"=="75" goto REVERT_TEL_DIAGDATA
if "!RCHOICE!"=="76" goto REVERT_TEL_ADVID
if "!RCHOICE!"=="77" goto REVERT_TEL_TAILORED
if "!RCHOICE!"=="78" goto REVERT_TEL_FEEDBACK
if "!RCHOICE!"=="79" goto REVERT_TEL_ACTIVITY
if "!RCHOICE!"=="80" goto REVERT_TEL_APPTRACK
if "!RCHOICE!"=="81" goto REVERT_TEL_LOCATION
if "!RCHOICE!"=="82" goto REVERT_TEL_APPCOMPAT
if "!RCHOICE!"=="83" goto REVERT_TEL_CONSUMER
if "!RCHOICE!"=="84" goto REVERT_TEL_TASKS
if "!RCHOICE!"=="85" goto REVERT_TEL_HANDWRITING
if "!RCHOICE!"=="86" goto REVERT_TEL_TYPING
if "!RCHOICE!"=="87" goto REVERT_TEL_SPEECH
if "!RCHOICE!"=="88" goto REVERT_TEL_WIFISENSE

powershell -NoProfile -Command "Write-Host '  [!] Invalid option.' -ForegroundColor Red"
echo.
pause
goto REVERT_MENU

:REVERT_PRESET_GAMES
cls
color !COL_OPS!
echo.
echo  =============================================
echo   Restoring Preset: Microsoft Games
echo  =============================================
set "PKGS=Microsoft.MicrosoftSolitaireCollection Microsoft.GamingApp Microsoft.XboxApp Microsoft.XboxGamingOverlay Microsoft.XboxIdentityProvider"
for %%i in (%PKGS%) do (
    winget install --id "%%i" --source msstore --silent --accept-package-agreements --accept-source-agreements >nul 2>&1
    if !errorLevel! equ 0 (
        powershell -NoProfile -Command "Write-Host '  [SUCCESS] %%i restored.' -ForegroundColor Green"
    ) else (
        powershell -NoProfile -Command "Write-Host '  [FAIL] %%i - try Microsoft Store manually.' -ForegroundColor Red"
    )
)
echo.
pause
goto REVERT_MENU

:REVERT_PRESET_SCHOOL
cls
color !COL_OPS!
echo.
echo  =============================================
echo   Restoring Preset: School / Work Bloat
echo  =============================================
set "PKGS=MicrosoftTeams Microsoft.Office.OneNote Microsoft.MicrosoftOfficeHub Microsoft.Todos"
for %%i in (%PKGS%) do (
    winget install --id "%%i" --source msstore --silent --accept-package-agreements --accept-source-agreements >nul 2>&1
    if !errorLevel! equ 0 (
        powershell -NoProfile -Command "Write-Host '  [SUCCESS] %%i restored.' -ForegroundColor Green"
    ) else (
        powershell -NoProfile -Command "Write-Host '  [FAIL] %%i - try Microsoft Store manually.' -ForegroundColor Red"
    )
)
echo.
pause
goto REVERT_MENU

:REVERT_PRESET_3D
cls
color !COL_OPS!
echo.
echo  =============================================
echo   Restoring Preset: 3D and Mixed Reality
echo  =============================================
set "PKGS=Microsoft.Microsoft3DViewer Microsoft.Print3D Microsoft.3DBuilder Microsoft.MixedReality.Portal"
for %%i in (%PKGS%) do (
    winget install --id "%%i" --source msstore --silent --accept-package-agreements --accept-source-agreements >nul 2>&1
    if !errorLevel! equ 0 (
        powershell -NoProfile -Command "Write-Host '  [SUCCESS] %%i restored.' -ForegroundColor Green"
    ) else (
        powershell -NoProfile -Command "Write-Host '  [FAIL] %%i - try Microsoft Store manually.' -ForegroundColor Red"
    )
)
echo.
pause
goto REVERT_MENU

:REVERT_PRESET_PRIVACY
cls
color !COL_OPS!
echo.
echo  =============================================
echo   Restoring Preset: Privacy Pack
echo  =============================================
set "RPRIVSCRIPT=%TEMP%\ytsh_revert_privacy_%RANDOM%%RANDOM%.ps1"
if exist "%RPRIVSCRIPT%" del "%RPRIVSCRIPT%" >nul 2>&1
>>"%RPRIVSCRIPT%" echo try { $r='HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection'; Remove-ItemProperty -Path $r -Name 'AllowTelemetry' -ErrorAction SilentlyContinue; Remove-ItemProperty -Path $r -Name 'DisableEnterpriseAuthProxy' -ErrorAction SilentlyContinue; Write-Host '  [SUCCESS] Diagnostic Data Restored' -ForegroundColor Green } catch { Write-Host ('  [FAIL] DiagData: '+$_.Exception.Message) -ForegroundColor Red }
>>"%RPRIVSCRIPT%" echo try { $r='HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\AdvertisingInfo'; Set-ItemProperty -Path $r -Name 'Enabled' -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue; Write-Host '  [SUCCESS] Advertising ID Restored' -ForegroundColor Green } catch { Write-Host ('  [FAIL] AdvID: '+$_.Exception.Message) -ForegroundColor Red }
>>"%RPRIVSCRIPT%" echo try { $r='HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Privacy'; Set-ItemProperty -Path $r -Name 'TailoredExperiencesWithDiagnosticDataEnabled' -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue; Write-Host '  [SUCCESS] Tailored Experiences Restored' -ForegroundColor Green } catch { Write-Host ('  [FAIL] Tailored: '+$_.Exception.Message) -ForegroundColor Red }
>>"%RPRIVSCRIPT%" echo try { $r='HKCU:\SOFTWARE\Microsoft\Siuf\Rules'; Remove-ItemProperty -Path $r -Name 'NumberOfSIUFInPeriod' -ErrorAction SilentlyContinue; Write-Host '  [SUCCESS] Feedback Notifications Restored' -ForegroundColor Green } catch { Write-Host ('  [FAIL] Feedback: '+$_.Exception.Message) -ForegroundColor Red }
>>"%RPRIVSCRIPT%" echo try { $r='HKLM:\SOFTWARE\Policies\Microsoft\Windows\System'; Set-ItemProperty -Path $r -Name 'EnableActivityFeed' -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue; Set-ItemProperty -Path $r -Name 'PublishUserActivities' -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue; Set-ItemProperty -Path $r -Name 'UploadUserActivities' -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue; Write-Host '  [SUCCESS] Activity History Restored' -ForegroundColor Green } catch { Write-Host ('  [FAIL] Activity: '+$_.Exception.Message) -ForegroundColor Red }
>>"%RPRIVSCRIPT%" echo try { $r='HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Set-ItemProperty -Path $r -Name 'Start_TrackProgs' -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue; Write-Host '  [SUCCESS] App Launch Tracking Restored' -ForegroundColor Green } catch { Write-Host ('  [FAIL] AppTrack: '+$_.Exception.Message) -ForegroundColor Red }
>>"%RPRIVSCRIPT%" echo try { $r='HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Sensor\Overrides\{BFA794E4-F964-4FDB-90F6-51056BFE4B44}'; Set-ItemProperty -Path $r -Name 'SensorPermissionState' -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue; $r2='HKLM:\SYSTEM\CurrentControlSet\Services\lfsvc\Service\Configuration'; Set-ItemProperty -Path $r2 -Name 'Status' -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue; Write-Host '  [SUCCESS] Location Tracking Restored' -ForegroundColor Green } catch { Write-Host ('  [FAIL] Location: '+$_.Exception.Message) -ForegroundColor Red }
>>"%RPRIVSCRIPT%" echo try { $r='HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppCompat'; Remove-ItemProperty -Path $r -Name 'AITEnable' -ErrorAction SilentlyContinue; Remove-ItemProperty -Path $r -Name 'DisableInventory' -ErrorAction SilentlyContinue; Write-Host '  [SUCCESS] AppCompat Telemetry Restored' -ForegroundColor Green } catch { Write-Host ('  [FAIL] AppCompat: '+$_.Exception.Message) -ForegroundColor Red }
>>"%RPRIVSCRIPT%" echo try { $r='HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent'; Remove-ItemProperty -Path $r -Name 'DisableWindowsConsumerFeatures' -ErrorAction SilentlyContinue; Remove-ItemProperty -Path $r -Name 'DisableSoftLanding' -ErrorAction SilentlyContinue; Remove-ItemProperty -Path $r -Name 'DisableCloudOptimizedContent' -ErrorAction SilentlyContinue; Write-Host '  [SUCCESS] Consumer Features Restored' -ForegroundColor Green } catch { Write-Host ('  [FAIL] Consumer: '+$_.Exception.Message) -ForegroundColor Red }
>>"%RPRIVSCRIPT%" echo try { $r='HKCU:\SOFTWARE\Microsoft\Personalization\Settings'; Set-ItemProperty -Path $r -Name 'AcceptedPrivacyPolicy' -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue; $r2='HKCU:\SOFTWARE\Microsoft\InputPersonalization'; Set-ItemProperty -Path $r2 -Name 'RestrictImplicitInkCollection' -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue; Set-ItemProperty -Path $r2 -Name 'RestrictImplicitTextCollection' -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue; $r3='HKCU:\SOFTWARE\Microsoft\InputPersonalization\TrainedDataStore'; Set-ItemProperty -Path $r3 -Name 'HarvestContacts' -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue; Write-Host '  [SUCCESS] Handwriting Data Restored' -ForegroundColor Green } catch { Write-Host ('  [FAIL] Handwriting: '+$_.Exception.Message) -ForegroundColor Red }
>>"%RPRIVSCRIPT%" echo try { $r='HKCU:\SOFTWARE\Microsoft\Input\TIPC'; Set-ItemProperty -Path $r -Name 'Enabled' -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue; Write-Host '  [SUCCESS] Typing Insights Restored' -ForegroundColor Green } catch { Write-Host ('  [FAIL] Typing: '+$_.Exception.Message) -ForegroundColor Red }
>>"%RPRIVSCRIPT%" echo try { $r='HKCU:\SOFTWARE\Microsoft\Speech_OneCore\Settings\OnlineSpeechPrivacy'; Set-ItemProperty -Path $r -Name 'HasAccepted' -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue; Write-Host '  [SUCCESS] Speech Personalization Restored' -ForegroundColor Green } catch { Write-Host ('  [FAIL] Speech: '+$_.Exception.Message) -ForegroundColor Red }
>>"%RPRIVSCRIPT%" echo try { $r='HKLM:\SOFTWARE\Microsoft\WcmSvc\wifinetworkmanager\config'; Set-ItemProperty -Path $r -Name 'AutoConnectAllowedOEM' -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue; Write-Host '  [SUCCESS] Wi-Fi Sense Restored' -ForegroundColor Green } catch { Write-Host ('  [FAIL] WiFiSense: '+$_.Exception.Message) -ForegroundColor Red }
powershell -NoProfile -ExecutionPolicy Bypass -File "%RPRIVSCRIPT%"
del "%RPRIVSCRIPT%" >nul 2>&1
schtasks /change /tn "\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser" /enable >nul 2>&1
schtasks /change /tn "\Microsoft\Windows\Application Experience\ProgramDataUpdater" /enable >nul 2>&1
schtasks /change /tn "\Microsoft\Windows\Customer Experience Improvement Program\Consolidator" /enable >nul 2>&1
schtasks /change /tn "\Microsoft\Windows\Customer Experience Improvement Program\UsbCeip" /enable >nul 2>&1
schtasks /change /tn "\Microsoft\Windows\Application Experience\StartupAppTask" /enable >nul 2>&1
schtasks /change /tn "\Microsoft\Windows\DiskDiagnostic\Microsoft-Windows-DiskDiagnosticDataCollector" /enable >nul 2>&1
powershell -NoProfile -Command "Write-Host '  [SUCCESS] All CEIP tasks re-enabled' -ForegroundColor Green"
echo.
echo  =============================================
echo   Privacy Pack restored.
echo  =============================================
echo.
pause
goto REVERT_MENU

:REVERT_PRESET_BING
cls
color !COL_OPS!
echo.
echo  =============================================
echo   Restoring Preset: Bing / News / Cortana
echo  =============================================
for %%i in (Microsoft.BingNews Microsoft.BingWeather Microsoft.BingSearch Microsoft.MicrosoftStart Microsoft.Cortana Microsoft.549981C3F5F10 MicrosoftWindows.Client.WebExperience) do (
    winget install --id "%%i" --source msstore --silent --accept-package-agreements --accept-source-agreements >nul 2>&1
    if !errorLevel! equ 0 (
        powershell -NoProfile -Command "Write-Host '  [SUCCESS] %%i restored.' -ForegroundColor Green"
    ) else (
        powershell -NoProfile -Command "Write-Host '  [FAIL] %%i - try Microsoft Store manually.' -ForegroundColor Red"
    )
)
set "RPRESETSCRIPT=%TEMP%\ytsh_revert_preset_%RANDOM%%RANDOM%.ps1"
(
    echo if ($env:SYS_OS -match 'Windows 10') { Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Feeds' -Name 'ShellFeedsTaskbarViewMode' -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue; Write-Host "  Restored Win10 News & Interests" -ForegroundColor Green }
    echo if ($env:SYS_OS -match 'Windows 11') { Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name 'TaskbarDa' -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue; Write-Host "  Restored Win11 Widgets" -ForegroundColor Green }
) > "%RPRESETSCRIPT%"
powershell -NoProfile -ExecutionPolicy Bypass -File "%RPRESETSCRIPT%"
del "%RPRESETSCRIPT%" >nul 2>&1
echo.
pause
goto REVERT_MENU

:REVERT_PRESET_MEDIA
cls
color !COL_OPS!
echo.
echo  =============================================
echo   Restoring Preset: Media and Music
echo  =============================================
for %%i in (Microsoft.ZuneMusic Microsoft.ZuneVideo Microsoft.WindowsSoundRecorder Clipchamp.Clipchamp) do (
    winget install --id "%%i" --source msstore --silent --accept-package-agreements --accept-source-agreements >nul 2>&1
    if !errorLevel! equ 0 (
        powershell -NoProfile -Command "Write-Host '  [SUCCESS] %%i restored.' -ForegroundColor Green"
    ) else (
        powershell -NoProfile -Command "Write-Host '  [FAIL] %%i - try Microsoft Store manually.' -ForegroundColor Red"
    )
)
echo.
pause
goto REVERT_MENU

:REVERT_PRESET_COMMS
cls
color !COL_OPS!
echo.
echo  =============================================
echo   Restoring Preset: Communication Apps
echo  =============================================
for %%i in (Microsoft.SkypeApp MicrosoftTeams Microsoft.WindowsCommunicationsApps Microsoft.People Microsoft.YourPhone) do (
    winget install --id "%%i" --source msstore --silent --accept-package-agreements --accept-source-agreements >nul 2>&1
    if !errorLevel! equ 0 (
        powershell -NoProfile -Command "Write-Host '  [SUCCESS] %%i restored.' -ForegroundColor Green"
    ) else (
        powershell -NoProfile -Command "Write-Host '  [FAIL] %%i - try Microsoft Store manually.' -ForegroundColor Red"
    )
)
echo.
pause
goto REVERT_MENU

:REVERT_PRESET_PERF
cls
color !COL_OPS!
echo.
echo  =============================================
echo   Restoring Preset: Performance Pack
echo  =============================================
reg delete "HKCU\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications" /v GlobalUserDisabled /f >nul 2>&1
reg delete "HKLM\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy" /v LetAppsRunInBackground /f >nul 2>&1
powershell -NoProfile -Command "Write-Host '  [SUCCESS] UWP Background Apps restored.' -ForegroundColor Green"
sc config "SysMain" start= auto >nul 2>&1
sc start "SysMain" >nul 2>&1
powershell -NoProfile -Command "Write-Host '  [SUCCESS] SysMain re-enabled.' -ForegroundColor Green"
for %%s in (DiagTrack WMPNetworkSvc MapsBroker RetailDemo WerSvc) do (
    sc config "%%s" start= demand >nul 2>&1
    sc start "%%s" >nul 2>&1
    powershell -NoProfile -Command "Write-Host '  [SUCCESS] %%s restored to Manual.' -ForegroundColor Green"
)
echo.
pause
goto REVERT_MENU

:REVERT_RAM_BGAPPS
cls
color !COL_OPS!
echo.
echo  =============================================
echo   Restoring Global UWP Background Apps
echo  =============================================
reg delete "HKCU\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications" /v GlobalUserDisabled /f >nul 2>&1
reg delete "HKLM\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy" /v LetAppsRunInBackground /f >nul 2>&1
powershell -NoProfile -Command "Write-Host '  [SUCCESS] Background Apps restored to default behavior.' -ForegroundColor Green"
echo.
pause
goto REVERT_MENU

:REVERT_SINGLE_APP
cls
color !COL_OPS!
echo.
echo  =============================================
echo   Restoring: !RPKG!
echo  =============================================
echo.
winget --version >nul 2>&1
if !errorLevel! equ 0 (
    winget install --id "!RPKG!" --source msstore --silent --accept-package-agreements --accept-source-agreements >nul 2>&1
    if !errorLevel! equ 0 (
        powershell -NoProfile -Command "Write-Host '  [SUCCESS] !RPKG! restored.' -ForegroundColor Green"
    ) else (
        powershell -NoProfile -Command "Write-Host '  [FAIL] winget could not install !RPKG!. Try Microsoft Store manually.' -ForegroundColor Red"
    )
) else (
    powershell -NoProfile -Command "Write-Host '  [WARN] winget not available. Search Microsoft Store manually.' -ForegroundColor DarkGray"
)
echo.
echo  Done. Press any key to return.
echo.
pause
goto REVERT_MENU

:REVERT_XBOX_OVERLAY
cls
color !COL_OPS!
echo.
echo  =============================================
echo   Restoring: Xbox Game Bar and Overlay
echo  =============================================
echo.
winget --version >nul 2>&1
if !errorLevel! equ 0 (
    winget install --id Microsoft.XboxGamingOverlay --source msstore --silent --accept-package-agreements --accept-source-agreements >nul 2>&1
    if !errorLevel! equ 0 (
        powershell -NoProfile -Command "Write-Host '  [SUCCESS] Xbox Gaming Overlay restored.' -ForegroundColor Green"
    ) else (
        powershell -NoProfile -Command "Write-Host '  [FAIL] Try reinstalling Xbox Game Bar from the Microsoft Store.' -ForegroundColor Red"
    )
) else (
    powershell -NoProfile -Command "Write-Host '  [WARN] winget not available. Use Microsoft Store manually.' -ForegroundColor DarkGray"
)
echo.
echo  Done. Press any key to return.
echo.
pause
goto REVERT_MENU

:REVERT_SINGLE_SVC
cls
color !COL_OPS!
echo.
echo  =============================================
echo   Restoring service: !RSVC!
echo  =============================================
echo.
if exist "%SVCLOG%" (
    set "FOUND_TYPE="
    for /f "usebackq tokens=1,2 delims==" %%A in ("%SVCLOG%") do (
        if "%%A"=="!RSVC!" set "FOUND_TYPE=%%B"
    )
    if defined FOUND_TYPE (
        if "!FOUND_TYPE!"=="2" (
            sc config "!RSVC!" start= auto >nul 2>&1
            sc start "!RSVC!" >nul 2>&1
            powershell -NoProfile -Command "Write-Host '  [SUCCESS] !RSVC! set to Automatic and started.' -ForegroundColor Green"
        )
        if "!FOUND_TYPE!"=="3" (
            sc config "!RSVC!" start= demand >nul 2>&1
            powershell -NoProfile -Command "Write-Host '  [SUCCESS] !RSVC! set to Manual.' -ForegroundColor Green"
        )
        if "!FOUND_TYPE!"=="4" (
            sc config "!RSVC!" start= disabled >nul 2>&1
            powershell -NoProfile -Command "Write-Host '  [SUCCESS] !RSVC! remains Disabled (was already disabled before).' -ForegroundColor Green"
        )
    ) else (
        powershell -NoProfile -Command "Write-Host '  [NOT IN LOG] !RSVC! was not in the service disable log. Setting to Manual.' -ForegroundColor DarkGray"
        sc config "!RSVC!" start= demand >nul 2>&1
        sc start "!RSVC!" >nul 2>&1
        powershell -NoProfile -Command "Write-Host '  [SUCCESS] !RSVC! restored to Manual start.' -ForegroundColor Green"
    )
) else (
    powershell -NoProfile -Command "Write-Host '  [NO LOG] Log not found. Restoring !RSVC! to Manual (safe default).' -ForegroundColor DarkGray"
    sc config "!RSVC!" start= demand >nul 2>&1
    sc start "!RSVC!" >nul 2>&1
    powershell -NoProfile -Command "Write-Host '  [SUCCESS] !RSVC! set to Manual.' -ForegroundColor Green"
)
echo.
echo  Done. Press any key to return.
echo.
pause
goto REVERT_MENU

:REVERT_TEL_DIAGDATA
cls
color !COL_OPS!
echo.
echo  =============================================
echo   Restoring: Diagnostic Data Collection
echo  =============================================
echo.
set "RTELSCRIPT=%TEMP%\ytsh_rtel_dd_%RANDOM%%RANDOM%.ps1"
(
    echo try {
        $r = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection'
    echo     Remove-ItemProperty -Path $r -Name 'AllowTelemetry' -ErrorAction SilentlyContinue
    echo     Remove-ItemProperty -Path $r -Name 'DisableEnterpriseAuthProxy' -ErrorAction SilentlyContinue
    echo     Write-Host '  [SUCCESS] Diagnostic Data Collection Restored.' -ForegroundColor Green
    echo } catch { Write-Host ^('  [FAIL] ' + $_.Exception.Message^) -ForegroundColor Red }
) > "%RTELSCRIPT%"
powershell -NoProfile -ExecutionPolicy Bypass -File "%RTELSCRIPT%"
del "%RTELSCRIPT%" >nul 2>&1
echo.
echo  Done. Press any key to return.
echo.
pause
goto REVERT_MENU

:REVERT_TEL_ADVID
cls
color !COL_OPS!
echo.
echo  =============================================
echo   Restoring: Advertising ID
echo  =============================================
echo.
set "RTELSCRIPT=%TEMP%\ytsh_rtel_ai_%RANDOM%%RANDOM%.ps1"
(
    echo try {
    echo     $r = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\AdvertisingInfo'
    echo     Set-ItemProperty -Path $r -Name 'Enabled' -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
    echo     Write-Host '  [SUCCESS] Advertising ID Restored.' -ForegroundColor Green
    echo } catch { Write-Host ^('  [FAIL] ' + $_.Exception.Message^) -ForegroundColor Red }
) > "%RTELSCRIPT%"
powershell -NoProfile -ExecutionPolicy Bypass -File "%RTELSCRIPT%"
del "%RTELSCRIPT%" >nul 2>&1
echo.
echo  Done. Press any key to return.
echo.
pause
goto REVERT_MENU

:REVERT_TEL_TAILORED
cls
color !COL_OPS!
echo.
echo  =============================================
echo   Restoring: Tailored Experiences
echo  =============================================
echo.
set "RTELSCRIPT=%TEMP%\ytsh_rtel_te_%RANDOM%%RANDOM%.ps1"
(
    echo try {
    echo     $r = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Privacy'
    echo     Set-ItemProperty -Path $r -Name 'TailoredExperiencesWithDiagnosticDataEnabled' -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
    echo     Write-Host '  [SUCCESS] Tailored Experiences Restored.' -ForegroundColor Green
    echo } catch { Write-Host ^('  [FAIL] ' + $_.Exception.Message^) -ForegroundColor Red }
) > "%RTELSCRIPT%"
powershell -NoProfile -ExecutionPolicy Bypass -File "%RTELSCRIPT%"
del "%RTELSCRIPT%" >nul 2>&1
echo.
echo  Done. Press any key to return.
echo.
pause
goto REVERT_MENU

:REVERT_TEL_FEEDBACK
cls
color !COL_OPS!
echo.
echo  =============================================
echo   Restoring: Feedback Notifications
echo  =============================================
echo.
set "RTELSCRIPT=%TEMP%\ytsh_rtel_fb_%RANDOM%%RANDOM%.ps1"
(
    echo try {
    echo     $r = 'HKCU:\SOFTWARE\Microsoft\Siuf\Rules'
    echo     Remove-ItemProperty -Path $r -Name 'NumberOfSIUFInPeriod' -ErrorAction SilentlyContinue
    echo     Write-Host '  [SUCCESS] Feedback Notifications Restored.' -ForegroundColor Green
    echo } catch { Write-Host ^('  [FAIL] ' + $_.Exception.Message^) -ForegroundColor Red }
) > "%RTELSCRIPT%"
powershell -NoProfile -ExecutionPolicy Bypass -File "%RTELSCRIPT%"
del "%RTELSCRIPT%" >nul 2>&1
echo.
echo  Done. Press any key to return.
echo.
pause
goto REVERT_MENU

:REVERT_TEL_ACTIVITY
cls
color !COL_OPS!
echo.
echo  =============================================
echo   Restoring: Activity History / Timeline
echo  =============================================
echo.
set "RTELSCRIPT=%TEMP%\ytsh_rtel_ah_%RANDOM%%RANDOM%.ps1"
(
    echo try {
    echo     $r = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System'
    echo     Set-ItemProperty -Path $r -Name 'EnableActivityFeed' -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
    echo     Set-ItemProperty -Path $r -Name 'PublishUserActivities' -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
    echo     Set-ItemProperty -Path $r -Name 'UploadUserActivities' -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
    echo     Write-Host '  [SUCCESS] Activity History / Timeline Restored.' -ForegroundColor Green
     echo } catch { Write-Host ^('  [FAIL] ' + $_.Exception.Message^) -ForegroundColor Red }
) > "%RTELSCRIPT%"
powershell -NoProfile -ExecutionPolicy Bypass -File "%RTELSCRIPT%"
del "%RTELSCRIPT%" >nul 2>&1
echo.
echo  Done. Press any key to return.
echo.
pause
goto REVERT_MENU

:REVERT_TEL_APPTRACK
cls
color !COL_OPS!
echo.
echo  =============================================
echo   Restoring: App Launch Tracking
echo  =============================================
echo.
set "RTELSCRIPT=%TEMP%\ytsh_rtel_at_%RANDOM%%RANDOM%.ps1"
(
    echo try {
    echo     $r = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
    echo     Set-ItemProperty -Path $r -Name 'Start_TrackProgs' -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
    echo     Write-Host '  [SUCCESS] App Launch Tracking Restored.' -ForegroundColor Green
    echo } catch { Write-Host ^('  [FAIL] ' + $_.Exception.Message^) -ForegroundColor Red }
) > "%RTELSCRIPT%"
powershell -NoProfile -ExecutionPolicy Bypass -File "%RTELSCRIPT%"
del "%RTELSCRIPT%" >nul 2>&1
echo.
echo  Done. Press any key to return.
echo.
pause
goto REVERT_MENU

:REVERT_TEL_LOCATION
cls
color !COL_OPS!
echo.
echo  =============================================
echo   Restoring: Location Tracking
echo  =============================================
echo.
set "RTELSCRIPT=%TEMP%\ytsh_rtel_loc_%RANDOM%%RANDOM%.ps1"
(
    echo try {
    echo     $r = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Sensor\Overrides\{BFA794E4-F964-4FDB-90F6-51056BFE4B44}'
    echo     Set-ItemProperty -Path $r -Name 'SensorPermissionState' -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
    echo     $r2 = 'HKLM:\SYSTEM\CurrentControlSet\Services\lfsvc\Service\Configuration'
    echo     Set-ItemProperty -Path $r2 -Name 'Status' -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
    echo     Write-Host '  [SUCCESS] Location Tracking Restored.' -ForegroundColor Green
    echo } catch { Write-Host ^('  [FAIL] ' + $_.Exception.Message^) -ForegroundColor Red }
) > "%RTELSCRIPT%"
powershell -NoProfile -ExecutionPolicy Bypass -File "%RTELSCRIPT%"
del "%RTELSCRIPT%" >nul 2>&1
echo.
echo  Done. Press any key to return.
echo.
pause
goto REVERT_MENU

:REVERT_TEL_APPCOMPAT
cls
color !COL_OPS!
echo.
echo  =============================================
echo   Restoring: AppCompat Telemetry
echo  =============================================
echo.
set "RTELSCRIPT=%TEMP%\ytsh_rtel_ac_%RANDOM%%RANDOM%.ps1"
(
    echo try {
    echo     $r = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppCompat'
    echo     Remove-ItemProperty -Path $r -Name 'AITEnable' -ErrorAction SilentlyContinue
    echo     Remove-ItemProperty -Path $r -Name 'DisableInventory' -ErrorAction SilentlyContinue
    echo     Write-Host '  [SUCCESS] AppCompat Telemetry Restored.' -ForegroundColor Green
    echo } catch { Write-Host ^('  [FAIL] ' + $_.Exception.Message^) -ForegroundColor Red }
) > "%RTELSCRIPT%"
powershell -NoProfile -ExecutionPolicy Bypass -File "%RTELSCRIPT%"
del "%RTELSCRIPT%" >nul 2>&1
echo.
echo  Done. Press any key to return.
echo.
pause
goto REVERT_MENU

:REVERT_TEL_CONSUMER
cls
color !COL_OPS!
echo.
echo  =============================================
echo   Restoring: Windows Consumer Features
echo  =============================================
echo.
set "RTELSCRIPT=%TEMP%\ytsh_rtel_cf_%RANDOM%%RANDOM%.ps1"
(
    echo try {
    echo     $r = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent'
    echo     Remove-ItemProperty -Path $r -Name 'DisableWindowsConsumerFeatures' -ErrorAction SilentlyContinue
    echo     Remove-ItemProperty -Path $r -Name 'DisableSoftLanding' -ErrorAction SilentlyContinue
    echo     Remove-ItemProperty -Path $r -Name 'DisableCloudOptimizedContent' -ErrorAction SilentlyContinue
    echo     Write-Host '  [SUCCESS] Windows Consumer Features Restored.' -ForegroundColor Green
    echo } catch { Write-Host ^('  [FAIL] ' + $_.Exception.Message^) -ForegroundColor Red }
) > "%RTELSCRIPT%"
powershell -NoProfile -ExecutionPolicy Bypass -File "%RTELSCRIPT%"
del "%RTELSCRIPT%" >nul 2>&1
echo.
echo  Done. Press any key to return.
echo.
pause
goto REVERT_MENU

:REVERT_TEL_TASKS
cls
color !COL_OPS!
echo.
echo  =============================================
echo   Restoring: CEIP Scheduled Tasks
echo  =============================================
echo.
schtasks /change /tn "\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser" /enable >nul 2>&1
schtasks /change /tn "\Microsoft\Windows\Application Experience\ProgramDataUpdater" /enable >nul 2>&1
schtasks /change /tn "\Microsoft\Windows\Customer Experience Improvement Program\Consolidator" /enable >nul 2>&1
schtasks /change /tn "\Microsoft\Windows\Customer Experience Improvement Program\UsbCeip" /enable >nul 2>&1
schtasks /change /tn "\Microsoft\Windows\Application Experience\StartupAppTask" /enable >nul 2>&1
schtasks /change /tn "\Microsoft\Windows\DiskDiagnostic\Microsoft-Windows-DiskDiagnosticDataCollector" /enable >nul 2>&1
powershell -NoProfile -Command "Write-Host '  [SUCCESS] CEIP and related tasks re-enabled.' -ForegroundColor Green"
echo.
echo  Done. Press any key to return.
echo.
pause
goto REVERT_MENU

:REVERT_TEL_HANDWRITING
cls
color !COL_OPS!
echo.
echo  =============================================
echo   Restoring: Handwriting Personalization
echo  =============================================
echo.
set "RTELSCRIPT=%TEMP%\ytsh_rtel_hw_%RANDOM%%RANDOM%.ps1"
(
    echo try {
    echo     $r = 'HKCU:\SOFTWARE\Microsoft\Personalization\Settings'
    echo     Set-ItemProperty -Path $r -Name 'AcceptedPrivacyPolicy' -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
    echo     $r2 = 'HKCU:\SOFTWARE\Microsoft\InputPersonalization'
    echo     Set-ItemProperty -Path $r2 -Name 'RestrictImplicitInkCollection' -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
    echo     Set-ItemProperty -Path $r2 -Name 'RestrictImplicitTextCollection' -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
    echo     $r3 = 'HKCU:\SOFTWARE\Microsoft\InputPersonalization\TrainedDataStore'
    echo     Set-ItemProperty -Path $r3 -Name 'HarvestContacts' -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
    echo     Write-Host '  [SUCCESS] Handwriting Personalization Data Restored.' -ForegroundColor Green
    echo } catch { Write-Host ^('  [FAIL] ' + $_.Exception.Message^) -ForegroundColor Red }
) > "%RTELSCRIPT%"
powershell -NoProfile -ExecutionPolicy Bypass -File "%RTELSCRIPT%"
del "%RTELSCRIPT%" >nul 2>&1
echo.
echo  Done. Press any key to return.
echo.
pause
goto REVERT_MENU

:REVERT_TEL_TYPING
cls
color !COL_OPS!
echo.
echo  =============================================
echo   Restoring: Typing Insights
echo  =============================================
echo.
set "RTELSCRIPT=%TEMP%\ytsh_rtel_ti_%RANDOM%%RANDOM%.ps1"
(
    echo try {
    echo     $r = 'HKCU:\SOFTWARE\Microsoft\Input\TIPC'
    echo     Set-ItemProperty -Path $r -Name 'Enabled' -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
    echo     Write-Host '  [SUCCESS] Typing Insights Data Collection Restored.' -ForegroundColor Green
    echo } catch { Write-Host ^('  [FAIL] ' + $_.Exception.Message^) -ForegroundColor Red }
) > "%RTELSCRIPT%"
powershell -NoProfile -ExecutionPolicy Bypass -File "%RTELSCRIPT%"
del "%RTELSCRIPT%" >nul 2>&1
echo.
echo  Done. Press any key to return.
echo.
pause
goto REVERT_MENU

:REVERT_TEL_SPEECH
cls
color !COL_OPS!
echo.
echo  =============================================
echo   Restoring: Speech Personalization
echo  =============================================
echo.
set "RTELSCRIPT=%TEMP%\ytsh_rtel_sp_%RANDOM%%RANDOM%.ps1"
(
    echo try {
    echo     $r = 'HKCU:\SOFTWARE\Microsoft\Speech_OneCore\Settings\OnlineSpeechPrivacy'
    echo     Set-ItemProperty -Path $r -Name 'HasAccepted' -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
    echo     Write-Host '  [SUCCESS] Speech Personalization Data Restored.' -ForegroundColor Green
    echo } catch { Write-Host ^('  [FAIL] ' + $_.Exception.Message^) -ForegroundColor Red }
) > "%RTELSCRIPT%"
powershell -NoProfile -ExecutionPolicy Bypass -File "%RTELSCRIPT%"
del "%RTELSCRIPT%" >nul 2>&1
echo.
echo  Done. Press any key to return.
echo.
pause
goto REVERT_MENU

:REVERT_TEL_WIFISENSE
cls
color !COL_OPS!
echo.
echo  =============================================
echo   Restoring: Wi-Fi Sense
echo  =============================================
echo.
set "RTELSCRIPT=%TEMP%\ytsh_rtel_ws_%RANDOM%%RANDOM%.ps1"
(
    echo try {
    echo     $r = 'HKLM:\SOFTWARE\Microsoft\WcmSvc\wifinetworkmanager\config'
    echo     Set-ItemProperty -Path $r -Name 'AutoConnectAllowedOEM' -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
    echo     Write-Host '  [SUCCESS] Wi-Fi Sense Restored.' -ForegroundColor Green
    echo } catch { Write-Host ^('  [FAIL] ' + $_.Exception.Message^) -ForegroundColor Red }
) > "%RTELSCRIPT%"
powershell -NoProfile -ExecutionPolicy Bypass -File "%RTELSCRIPT%"
del "%RTELSCRIPT%" >nul 2>&1
echo.
echo  Done. Press any key to return.
echo.
pause
goto REVERT_MENU

:REVERT_ALL
cls
color !COL_OPS!
echo.
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '   FULL REVERT - Restore Everything' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
echo.
echo   This will attempt to restore all apps,
echo   services, and telemetry settings to their
echo   default Windows state.
echo.
echo   App restoration requires winget or you will
echo   need to reinstall from the Microsoft Store.
echo.
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
echo.
set "CONFIRM="
set /p "CONFIRM=  Type YES to continue or NO to cancel: "
if /i "!CONFIRM!"=="NO" (
    echo.
    powershell -NoProfile -Command "Write-Host '  Cancelled.' -ForegroundColor Red"
    pause
    goto REVERT_MENU
)
if /i not "!CONFIRM!"=="YES" (
    echo.
    powershell -NoProfile -Command "Write-Host '  [!] Unrecognized input.' -ForegroundColor Red"
    pause
    goto REVERT_MENU
)
if exist "%LOGFILE%" call :DO_RESTORE_APPS
if exist "%SVCLOG%" call :DO_RESTORE_SERVICES
call :DO_RESTORE_ALL_TELEMETRY
echo.
echo  =============================================
powershell -NoProfile -Command "Write-Host '   Full Revert Complete.' -ForegroundColor Green"
echo  =============================================
echo.
call :COUNTDOWN_RESTART
goto MAIN_MENU

:HEALTH_CHECK
cls
color !COL_OPS!
echo.
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '    SYSTEM HEALTH CHECK' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
echo.
set "HLTSCRIPT=%TEMP%\ytsh_health_%RANDOM%%RANDOM%.ps1"
(
    echo $outStatus = 'HEALTHY'
    echo Write-Host '  [1/6] Checking Disk SMART Health...' -ForegroundColor Cyan
    echo $disk = Get-CimInstance -ClassName MSStorageDriver_FailurePredictStatus -Namespace root\wmi -ErrorAction SilentlyContinue
    echo if ^($disk -and $disk.PredictFailure^) { Write-Host '  [CRITICAL] Disk failure predicted!' -ForegroundColor Red; $outStatus = 'COMPONENT PROBLEM' } else { Write-Host '  [OK] Disks are reporting healthy.' -ForegroundColor Green }
    
    echo Write-Host '  [2/6] Checking Windows Update Status...' -ForegroundColor Cyan
    echo $wu = New-Object -ComObject Microsoft.Update.Session
    echo try { $result = $wu.CreateUpdateSearcher^(^).Search^("IsInstalled=0 and Type='Software'"^) } catch { $result = $null }
    echo if ^($result -and $result.Updates.Count -gt 0^) { Write-Host ^("  [INFO] " + $result.Updates.Count + " Updates Pending."^) -ForegroundColor Yellow; if ^($outStatus -eq 'HEALTHY'^) { $outStatus = 'OUTDATED' } } else { Write-Host '  [OK] OS is up to date.' -ForegroundColor Green }
    
    echo Write-Host '  [3/6] Checking RAM Integrity...' -ForegroundColor Cyan
    echo $mem = Get-CimInstance Win32_PhysicalMemory -ErrorAction SilentlyContinue
    echo if ^($mem^) { Write-Host '  [OK] Memory modules responding.' -ForegroundColor Green } else { Write-Host '  [WARN] RAM check failed.' -ForegroundColor Red; $outStatus = 'COMPONENT PROBLEM' }
    
    echo Write-Host '  [4/6] Checking GPU Hardware Status...' -ForegroundColor Cyan
    echo $gpu = Get-CimInstance Win32_VideoController ^| Where-Object { $_.ConfigManagerErrorCode -ne 0 }
    echo if ^($gpu^) { Write-Host '  [CRITICAL] GPU reporting errors!' -ForegroundColor Red; $outStatus = 'COMPONENT PROBLEM' } else { Write-Host '  [OK] GPU hardware is functional.' -ForegroundColor Green }
    
    echo Write-Host '  [5/6] Checking Motherboard ^& CPU Temps...' -ForegroundColor Cyan
    echo $mobo = Get-CimInstance Win32_BaseBoard ^| Where-Object { $_.Status -ne 'OK' }
    echo if ^($mobo^) { Write-Host '  [WARN] Motherboard reporting issues.' -ForegroundColor Red; $outStatus = 'COMPONENT PROBLEM' } else { Write-Host '  [OK] Motherboard status OK.' -ForegroundColor Green }
    
    echo Write-Host '  [6/6] Checking for Outdated Drivers...' -ForegroundColor Cyan
    echo $badDrivers = Get-CimInstance Win32_PnPEntity -ErrorAction SilentlyContinue ^| Where-Object { $_.ConfigManagerErrorCode -ne 0 -and $_.ConfigManagerErrorCode -ne $null }
    echo if ^($badDrivers^) {
    echo     Write-Host ^("  [WARN] " + $badDrivers.Count + " device(s) with driver issues:"^) -ForegroundColor Yellow
    echo     foreach ^($d in $badDrivers^) { Write-Host ^("    - " + $d.Name + " (Code " + $d.ConfigManagerErrorCode + ")"^) -ForegroundColor Yellow }
    echo     if ^($outStatus -eq 'HEALTHY'^) { $outStatus = 'OUTDATED' }
    echo } else { Write-Host '  [OK] No driver errors detected.' -ForegroundColor Green }
    
    echo $outStatus ^| Out-File "$env:TEMP\ytsh_health_status.txt" -Encoding ascii
) > "%HLTSCRIPT%"
powershell -NoProfile -ExecutionPolicy Bypass -File "%HLTSCRIPT%"
del "%HLTSCRIPT%" >nul 2>&1
echo.
echo  Health analysis complete. Status saved to Main Menu.
echo.
pause
goto MAIN_MENU

:CHECK_STATUS
cls
color !COL_OPS!
echo.
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '     System Debloat Status Report' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
echo.
set "STATUS_SCRIPT=%TEMP%\ytsh_status_%RANDOM%%RANDOM%.ps1"
if exist "%STATUS_SCRIPT%" del "%STATUS_SCRIPT%" >nul 2>&1

>>"%STATUS_SCRIPT%" echo $appList = @^(
>>"%STATUS_SCRIPT%" echo     @{Name='Microsoft.549981C3F5F10'; Label='Cortana Search'},
>>"%STATUS_SCRIPT%" echo     @{Name='Microsoft.BingNews'; Label='Bing News'},
>>"%STATUS_SCRIPT%" echo     @{Name='Microsoft.BingWeather'; Label='Bing Weather'},
>>"%STATUS_SCRIPT%" echo     @{Name='Microsoft.BingSearch'; Label='Bing Search'},
>>"%STATUS_SCRIPT%" echo     @{Name='Microsoft.GamingApp'; Label='Xbox App'},
>>"%STATUS_SCRIPT%" echo     @{Name='Microsoft.XboxGameOverlay'; Label='Xbox Game Overlay'},
>>"%STATUS_SCRIPT%" echo     @{Name='Microsoft.XboxGamingOverlay'; Label='Xbox Gaming Overlay'},
>>"%STATUS_SCRIPT%" echo     @{Name='Microsoft.XboxIdentityProvider'; Label='Xbox Identity Provider'},
>>"%STATUS_SCRIPT%" echo     @{Name='Microsoft.XboxSpeechToTextOverlay'; Label='Xbox Speech Overlay'},
>>"%STATUS_SCRIPT%" echo     @{Name='Microsoft.SkypeApp'; Label='Skype'},
>>"%STATUS_SCRIPT%" echo     @{Name='MicrosoftTeams'; Label='Teams (personal)'},
>>"%STATUS_SCRIPT%" echo     @{Name='Clipchamp.Clipchamp'; Label='Clipchamp'},
>>"%STATUS_SCRIPT%" echo     @{Name='Microsoft.WindowsCommunicationsApps'; Label='Mail and Calendar'},
>>"%STATUS_SCRIPT%" echo     @{Name='Microsoft.People'; Label='People'},
>>"%STATUS_SCRIPT%" echo     @{Name='Microsoft.WindowsMaps'; Label='Windows Maps'},
>>"%STATUS_SCRIPT%" echo     @{Name='Microsoft.WindowsAlarms'; Label='Alarms and Clock'},
>>"%STATUS_SCRIPT%" echo     @{Name='Microsoft.MixedReality.Portal'; Label='Mixed Reality Portal'},
>>"%STATUS_SCRIPT%" echo     @{Name='Microsoft.Microsoft3DViewer'; Label='3D Viewer'},
>>"%STATUS_SCRIPT%" echo     @{Name='Microsoft.Print3D'; Label='Print 3D'},
>>"%STATUS_SCRIPT%" echo     @{Name='Microsoft.3DBuilder'; Label='3D Builder'},
>>"%STATUS_SCRIPT%" echo     @{Name='Microsoft.WindowsFeedbackHub'; Label='Feedback Hub'},
>>"%STATUS_SCRIPT%" echo     @{Name='Microsoft.GetHelp'; Label='Get Help'},
>>"%STATUS_SCRIPT%" echo     @{Name='Microsoft.Getstarted'; Label='Get Started / Tips'},
>>"%STATUS_SCRIPT%" echo     @{Name='Microsoft.PowerAutomateDesktop'; Label='Power Automate Desktop'},
>>"%STATUS_SCRIPT%" echo     @{Name='Microsoft.Todos'; Label='Microsoft To Do'},
>>"%STATUS_SCRIPT%" echo     @{Name='Microsoft.MicrosoftStickyNotes'; Label='Sticky Notes'},
>>"%STATUS_SCRIPT%" echo     @{Name='Microsoft.MicrosoftOfficeHub'; Label='Office Hub'},
>>"%STATUS_SCRIPT%" echo     @{Name='Microsoft.OneDriveSync'; Label='OneDrive Sync Stub'},
>>"%STATUS_SCRIPT%" echo     @{Name='Microsoft.WindowsSoundRecorder'; Label='Sound Recorder'},
>>"%STATUS_SCRIPT%" echo     @{Name='Microsoft.ZuneMusic'; Label='Groove Music'},
>>"%STATUS_SCRIPT%" echo     @{Name='Microsoft.ZuneVideo'; Label='Movies and TV'},
>>"%STATUS_SCRIPT%" echo     @{Name='Microsoft.YourPhone'; Label='Phone Link'},
>>"%STATUS_SCRIPT%" echo     @{Name='Microsoft.Cortana'; Label='Cortana App'},
>>"%STATUS_SCRIPT%" echo     @{Name='Microsoft.Office.OneNote'; Label='OneNote (bundled)'},
>>"%STATUS_SCRIPT%" echo     @{Name='Microsoft.Wallet'; Label='Microsoft Wallet'},
>>"%STATUS_SCRIPT%" echo     @{Name='Microsoft.OneConnect'; Label='OneConnect'},
>>"%STATUS_SCRIPT%" echo     @{Name='Microsoft.OutlookForWindows'; Label='Outlook for Windows'},
>>"%STATUS_SCRIPT%" echo     @{Name='Microsoft.MicrosoftSolitaireCollection'; Label='Solitaire Collection'},
>>"%STATUS_SCRIPT%" echo     @{Name='Microsoft.MicrosoftStart'; Label='Microsoft Start'},
>>"%STATUS_SCRIPT%" echo     @{Name='MicrosoftWindows.Client.WebExperience'; Label='Windows Widgets'},
>>"%STATUS_SCRIPT%" echo     @{Name='Microsoft.Messaging'; Label='Windows Messaging'},
>>"%STATUS_SCRIPT%" echo     @{Name='Microsoft.NetworkSpeedTest'; Label='Network Speed Test'},
>>"%STATUS_SCRIPT%" echo     @{Name='Microsoft.CommsPhone'; Label='CommsPhone'},
>>"%STATUS_SCRIPT%" echo     @{Name='Microsoft.WindowsCamera'; Label='Windows Camera'},
>>"%STATUS_SCRIPT%" echo     @{Name='Microsoft.Whiteboard'; Label='Microsoft Whiteboard'},
>>"%STATUS_SCRIPT%" echo     @{Name='Microsoft.WebMediaExtensions'; Label='Web Media Extensions'},
>>"%STATUS_SCRIPT%" echo     @{Name='Microsoft.HEVCVideoExtension'; Label='HEVC Video Extension'},
>>"%STATUS_SCRIPT%" echo     @{Name='Microsoft.VP9VideoExtensions'; Label='VP9 Video Extensions'},
>>"%STATUS_SCRIPT%" echo     @{Name='MicrosoftWindows.Client.WebExperience'; Label='Windows Widgets (Win11)'},
>>"%STATUS_SCRIPT%" echo     @{Name='Microsoft.XboxApp'; Label='Xbox Console Companion (Win10)'}
>>"%STATUS_SCRIPT%" echo ^)
>>"%STATUS_SCRIPT%" echo Write-Host ""
>>"%STATUS_SCRIPT%" echo Write-Host "  === BLOATWARE APPS ===" -ForegroundColor !COL_HDR_PS!
>>"%STATUS_SCRIPT%" echo Write-Host ""
>>"%STATUS_SCRIPT%" echo foreach ^($app in $appList^) {
>>"%STATUS_SCRIPT%" echo     $inst = Get-AppxPackage -Name $app.Name -AllUsers -ErrorAction SilentlyContinue
>>"%STATUS_SCRIPT%" echo     Write-Host ^("  " + $app.Label.PadRight^(30^) + ": "^) -ForegroundColor White -NoNewline
>>"%STATUS_SCRIPT%" echo     if ^($inst^) {
>>"%STATUS_SCRIPT%" echo         Write-Host "INSTALLED (BLOAT)" -ForegroundColor Red
>>"%STATUS_SCRIPT%" echo     } else {
>>"%STATUS_SCRIPT%" echo         Write-Host "CLEAN (UNINSTALLED)" -ForegroundColor Green
>>"%STATUS_SCRIPT%" echo     }
>>"%STATUS_SCRIPT%" echo }
>>"%STATUS_SCRIPT%" echo $stubs = @^(
>>"%STATUS_SCRIPT%" echo     @{Pattern='*CandyCrush*'; Label='Candy Crush'},
>>"%STATUS_SCRIPT%" echo     @{Pattern='*TikTok*'; Label='TikTok'},
>>"%STATUS_SCRIPT%" echo     @{Pattern='*Disney*'; Label='Disney+'},
>>"%STATUS_SCRIPT%" echo     @{Pattern='*Spotify*'; Label='Spotify'},
>>"%STATUS_SCRIPT%" echo     @{Pattern='*Facebook*'; Label='Facebook'},
>>"%STATUS_SCRIPT%" echo     @{Pattern='*Instagram*'; Label='Instagram'},
>>"%STATUS_SCRIPT%" echo     @{Pattern='*Netflix*'; Label='Netflix'},
>>"%STATUS_SCRIPT%" echo     @{Pattern='*Roblox*'; Label='Roblox'},
>>"%STATUS_SCRIPT%" echo     @{Pattern='*FarmVille*'; Label='FarmVille'},
>>"%STATUS_SCRIPT%" echo     @{Pattern='*BubbleWitch*'; Label='Bubble Witch 3 Saga'},
>>"%STATUS_SCRIPT%" echo     @{Pattern='*FarmHeroes*'; Label='Farm Heroes Saga'},
>>"%STATUS_SCRIPT%" echo     @{Pattern='*McAfee*'; Label='McAfee (OEM Trial)'}
>>"%STATUS_SCRIPT%" echo ^)
>>"%STATUS_SCRIPT%" echo Write-Host ""
>>"%STATUS_SCRIPT%" echo Write-Host "  === OEM STUBS ===" -ForegroundColor !COL_HDR_PS!
>>"%STATUS_SCRIPT%" echo Write-Host ""
>>"%STATUS_SCRIPT%" echo foreach ^($stub in $stubs^) {
>>"%STATUS_SCRIPT%" echo     $inst = Get-AppxPackage -Name $stub.Pattern -AllUsers -ErrorAction SilentlyContinue
>>"%STATUS_SCRIPT%" echo     Write-Host ^("  " + $stub.Label.PadRight^(30^) + ": "^) -ForegroundColor White -NoNewline
>>"%STATUS_SCRIPT%" echo     if ^($inst^) {
>>"%STATUS_SCRIPT%" echo         Write-Host "INSTALLED (BLOAT)" -ForegroundColor Red
>>"%STATUS_SCRIPT%" echo     } else {
>>"%STATUS_SCRIPT%" echo         Write-Host "CLEAN (UNINSTALLED)" -ForegroundColor Green
>>"%STATUS_SCRIPT%" echo     }
>>"%STATUS_SCRIPT%" echo }
>>"%STATUS_SCRIPT%" echo $svcs = @^(
>>"%STATUS_SCRIPT%" echo     @{Name='DiagTrack'; Label='DiagTrack (Telemetry)'},
>>"%STATUS_SCRIPT%" echo     @{Name='WMPNetworkSvc'; Label='WMPNetworkSvc'},
>>"%STATUS_SCRIPT%" echo     @{Name='RemoteRegistry'; Label='RemoteRegistry'},
>>"%STATUS_SCRIPT%" echo     @{Name='Fax'; Label='Fax'},
>>"%STATUS_SCRIPT%" echo     @{Name='WerSvc'; Label='WerSvc (Error Reporting)'},
>>"%STATUS_SCRIPT%" echo     @{Name='MapsBroker'; Label='MapsBroker'},
>>"%STATUS_SCRIPT%" echo     @{Name='RetailDemo'; Label='RetailDemo'},
>>"%STATUS_SCRIPT%" echo     @{Name='XblAuthManager'; Label='XblAuthManager'},
>>"%STATUS_SCRIPT%" echo     @{Name='XblGameSave'; Label='XblGameSave'},
>>"%STATUS_SCRIPT%" echo     @{Name='XboxNetApiSvc'; Label='XboxNetApiSvc'},
>>"%STATUS_SCRIPT%" echo     @{Name='XboxGipSvc'; Label='XboxGipSvc'},
>>"%STATUS_SCRIPT%" echo     @{Name='wisvc'; Label='wisvc (Insider)'},
>>"%STATUS_SCRIPT%" echo     @{Name='WSearch'; Label='WSearch (Indexer)'},
>>"%STATUS_SCRIPT%" echo     @{Name='lfsvc'; Label='lfsvc (Geolocation)'},
>>"%STATUS_SCRIPT%" echo     @{Name='SharedAccess'; Label='SharedAccess (ICS)'},
>>"%STATUS_SCRIPT%" echo     @{Name='TrkWks'; Label='TrkWks (Link Tracking)'},
>>"%STATUS_SCRIPT%" echo     @{Name='WbioSrvc'; Label='WbioSrvc (Biometrics)'},
>>"%STATUS_SCRIPT%" echo     @{Name='icssvc'; Label='icssvc (Hotspot)'},
>>"%STATUS_SCRIPT%" echo     @{Name='PhoneSvc'; Label='PhoneSvc'},
>>"%STATUS_SCRIPT%" echo     @{Name='SmsRouter'; Label='SmsRouter'},
>>"%STATUS_SCRIPT%" echo     @{Name='TabletInputService'; Label='TabletInputService'},
>>"%STATUS_SCRIPT%" echo     @{Name='WpcMonSvc'; Label='WpcMonSvc (Parental)'},
>>"%STATUS_SCRIPT%" echo     @{Name='PrintNotify'; Label='PrintNotify'},
>>"%STATUS_SCRIPT%" echo     @{Name='PcaSvc'; Label='PcaSvc (Compat)'},
>>"%STATUS_SCRIPT%" echo     @{Name='HomeGroupListener'; Label='HomeGroupListener'},
>>"%STATUS_SCRIPT%" echo     @{Name='HomeGroupProvider'; Label='HomeGroupProvider'}
>>"%STATUS_SCRIPT%" echo ^)
>>"%STATUS_SCRIPT%" echo Write-Host ""
>>"%STATUS_SCRIPT%" echo Write-Host "  === SERVICES ===" -ForegroundColor !COL_HDR_PS!
>>"%STATUS_SCRIPT%" echo Write-Host ""
>>"%STATUS_SCRIPT%" echo foreach ^($s in $svcs^) {
>>"%STATUS_SCRIPT%" echo     $svc = Get-Service -Name $s.Name -ErrorAction SilentlyContinue
>>"%STATUS_SCRIPT%" echo     Write-Host ^("  " + $s.Label.PadRight^(30^) + ": "^) -ForegroundColor White -NoNewline
>>"%STATUS_SCRIPT%" echo     if ^($svc^) {
>>"%STATUS_SCRIPT%" echo         if ^($svc.StartType -eq 'Disabled'^) {
>>"%STATUS_SCRIPT%" echo             Write-Host "DISABLED" -ForegroundColor Green
>>"%STATUS_SCRIPT%" echo         } else {
>>"%STATUS_SCRIPT%" echo             Write-Host ^("ACTIVE [" + $svc.StartType + "]"^) -ForegroundColor Red
>>"%STATUS_SCRIPT%" echo         }
>>"%STATUS_SCRIPT%" echo     } else {
>>"%STATUS_SCRIPT%" echo         Write-Host "NOT FOUND" -ForegroundColor DarkGray
>>"%STATUS_SCRIPT%" echo     }
>>"%STATUS_SCRIPT%" echo }
>>"%STATUS_SCRIPT%" echo Write-Host ""
>>"%STATUS_SCRIPT%" echo Write-Host "  === TELEMETRY REGISTRY ===" -ForegroundColor !COL_HDR_PS!
>>"%STATUS_SCRIPT%" echo Write-Host ""
>>"%STATUS_SCRIPT%" echo $checks = @^(
>>"%STATUS_SCRIPT%" echo     @{Path='HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection'; Name='AllowTelemetry'; Val=0; Label='Diagnostic Data Collection'},
>>"%STATUS_SCRIPT%" echo     @{Path='HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\AdvertisingInfo'; Name='Enabled'; Val=0; Label='Advertising ID'},
>>"%STATUS_SCRIPT%" echo     @{Path='HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Privacy'; Name='TailoredExperiencesWithDiagnosticDataEnabled'; Val=0; Label='Tailored Experiences'},
>>"%STATUS_SCRIPT%" echo     @{Path='HKCU:\SOFTWARE\Microsoft\Siuf\Rules'; Name='NumberOfSIUFInPeriod'; Val=0; Label='Feedback Notifications'},
>>"%STATUS_SCRIPT%" echo     @{Path='HKLM:\SOFTWARE\Policies\Microsoft\Windows\System'; Name='EnableActivityFeed'; Val=0; Label='Activity History Feed'},
>>"%STATUS_SCRIPT%" echo     @{Path='HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name='Start_TrackProgs'; Val=0; Label='App Launch Tracking'},
>>"%STATUS_SCRIPT%" echo     @{Path='HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppCompat'; Name='AITEnable'; Val=0; Label='AppCompat Telemetry'},
>>"%STATUS_SCRIPT%" echo     @{Path='HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent'; Name='DisableWindowsConsumerFeatures'; Val=1; Label='Consumer Features Blocked'},
>>"%STATUS_SCRIPT%" echo     @{Path='HKCU:\SOFTWARE\Microsoft\InputPersonalization'; Name='RestrictImplicitInkCollection'; Val=1; Label='Handwriting Data Restricted'},
>>"%STATUS_SCRIPT%" echo     @{Path='HKCU:\SOFTWARE\Microsoft\Input\TIPC'; Name='Enabled'; Val=0; Label='Typing Insights Disabled'},
>>"%STATUS_SCRIPT%" echo     @{Path='HKCU:\SOFTWARE\Microsoft\Speech_OneCore\Settings\OnlineSpeechPrivacy'; Name='HasAccepted'; Val=0; Label='Speech Data Disabled'},
>>"%STATUS_SCRIPT%" echo     @{Path='HKLM:\SOFTWARE\Microsoft\WcmSvc\wifinetworkmanager\config'; Name='AutoConnectAllowedOEM'; Val=0; Label='Wi-Fi Sense Disabled'}
>>"%STATUS_SCRIPT%" echo ^)
>>"%STATUS_SCRIPT%" echo foreach ^($c in $checks^) {
>>"%STATUS_SCRIPT%" echo     Write-Host ^("  " + $c.Label.PadRight^(30^) + ": "^) -ForegroundColor White -NoNewline
>>"%STATUS_SCRIPT%" echo     $prop = Get-ItemProperty -Path $c.Path -Name $c.Name -ErrorAction SilentlyContinue
>>"%STATUS_SCRIPT%" echo     if ^($prop -and $prop.^($c.Name^) -eq $c.Val^) {
>>"%STATUS_SCRIPT%" echo         Write-Host "DISABLED / BLOCKED" -ForegroundColor Green
>>"%STATUS_SCRIPT%" echo     } else {
>>"%STATUS_SCRIPT%" echo         Write-Host "ACTIVE / DEFAULT" -ForegroundColor Red
>>"%STATUS_SCRIPT%" echo     }
>>"%STATUS_SCRIPT%" echo }
>>"%STATUS_SCRIPT%" echo Write-Host ""

>>"%STATUS_SCRIPT%" echo Write-Host ""
if "!SYS_BRAND!"=="HP" (
    >>"%STATUS_SCRIPT%" echo Write-Host "  === HP BRAND BLOATWARE ===" -ForegroundColor !COL_HDR_PS!
    >>"%STATUS_SCRIPT%" echo Write-Host ""
    >>"%STATUS_SCRIPT%" echo $brandPkgs = @^(^)
    >>"%STATUS_SCRIPT%" echo $brandPkgs += @{Pattern='*JumpStart*';Label='HP JumpStart'}
    >>"%STATUS_SCRIPT%" echo $brandPkgs += @{Pattern='*HPSupportSolutions*';Label='HP Support Assistant'}
    >>"%STATUS_SCRIPT%" echo $brandPkgs += @{Pattern='*HPPrinterControl*';Label='HP Smart'}
    >>"%STATUS_SCRIPT%" echo $brandPkgs += @{Pattern='*HPQuickDrop*';Label='HP Quick Drop'}
    >>"%STATUS_SCRIPT%" echo $brandPkgs += @{Pattern='*HPAudioSwitch*';Label='HP Audio Switch'}
    >>"%STATUS_SCRIPT%" echo $brandPkgs += @{Pattern='*TouchpointAnalytics*';Label='HP Touchpoint Analytics'}
    >>"%STATUS_SCRIPT%" echo foreach ^($b in $brandPkgs^) { $i=Get-AppxPackage -Name $b.Pattern -AllUsers -ErrorAction SilentlyContinue; Write-Host ^("  "+$b.Label.PadRight^(30^)+": "^) -ForegroundColor White -NoNewline; if ^($i^) { Write-Host "INSTALLED (BLOAT)" -ForegroundColor Red } else { Write-Host "CLEAN / NOT FOUND" -ForegroundColor Green } }
)
if "!SYS_BRAND!"=="Dell" (
    >>"%STATUS_SCRIPT%" echo Write-Host "  === DELL BRAND BLOATWARE ===" -ForegroundColor !COL_HDR_PS!
    >>"%STATUS_SCRIPT%" echo Write-Host ""
    >>"%STATUS_SCRIPT%" echo $brandPkgs = @^(^)
    >>"%STATUS_SCRIPT%" echo $brandPkgs += @{Pattern='*DellSupportAssist*';Label='Dell SupportAssist'}
    >>"%STATUS_SCRIPT%" echo $brandPkgs += @{Pattern='*DellDigitalDelivery*';Label='Dell Digital Delivery'}
    >>"%STATUS_SCRIPT%" echo $brandPkgs += @{Pattern='*DellUpdate*';Label='Dell Update'}
    if "!SYS_FORM!"=="LAPTOP" (
        >>"%STATUS_SCRIPT%" echo $brandPkgs += @{Pattern='*DellMobileConnect*';Label='Dell Mobile Connect'}
    )
    >>"%STATUS_SCRIPT%" echo $brandPkgs += @{Pattern='*MyDell*';Label='MyDell'}
    >>"%STATUS_SCRIPT%" echo $brandPkgs += @{Pattern='*DellCustomerConnect*';Label='Dell Customer Connect'}
    >>"%STATUS_SCRIPT%" echo foreach ^($b in $brandPkgs^) { $i=Get-AppxPackage -Name $b.Pattern -AllUsers -ErrorAction SilentlyContinue; Write-Host ^("  "+$b.Label.PadRight^(30^)+": "^) -ForegroundColor White -NoNewline; if ^($i^) { Write-Host "INSTALLED (BLOAT)" -ForegroundColor Red } else { Write-Host "CLEAN / NOT FOUND" -ForegroundColor Green } }
)
if "!SYS_BRAND!"=="Lenovo" (
    >>"%STATUS_SCRIPT%" echo Write-Host "  === LENOVO BRAND BLOATWARE ===" -ForegroundColor !COL_HDR_PS!
    >>"%STATUS_SCRIPT%" echo Write-Host ""
    >>"%STATUS_SCRIPT%" echo $brandPkgs = @^(^)
    >>"%STATUS_SCRIPT%" echo $brandPkgs += @{Pattern='*LenovoVantage*';Label='Lenovo Vantage'}
    >>"%STATUS_SCRIPT%" echo $brandPkgs += @{Pattern='*LenovoSettings*';Label='Lenovo Settings App'}
    >>"%STATUS_SCRIPT%" echo $brandPkgs += @{Pattern='*LenovoCompanion*';Label='Lenovo Companion'}
    >>"%STATUS_SCRIPT%" echo $brandPkgs += @{Pattern='*WinZip*';Label='WinZip ^(Lenovo bundle^)'}
    >>"%STATUS_SCRIPT%" echo $brandPkgs += @{Pattern='*McAfee*';Label='McAfee ^(Lenovo bundle^)'}
    >>"%STATUS_SCRIPT%" echo foreach ^($b in $brandPkgs^) { $i=Get-AppxPackage -Name $b.Pattern -AllUsers -ErrorAction SilentlyContinue; Write-Host ^("  "+$b.Label.PadRight^(30^)+": "^) -ForegroundColor White -NoNewline; if ^($i^) { Write-Host "INSTALLED (BLOAT)" -ForegroundColor Red } else { Write-Host "CLEAN / NOT FOUND" -ForegroundColor Green } }
)
if "!SYS_BRAND!"=="ASUS" (
    >>"%STATUS_SCRIPT%" echo Write-Host "  === ASUS BRAND BLOATWARE ===" -ForegroundColor !COL_HDR_PS!
    >>"%STATUS_SCRIPT%" echo Write-Host ""
    >>"%STATUS_SCRIPT%" echo $brandPkgs = @^(^)
    if "!SYS_FORM!"=="LAPTOP" (
        >>"%STATUS_SCRIPT%" echo $brandPkgs += @{Pattern='*MyASUS*';Label='MyASUS'}
    )
    >>"%STATUS_SCRIPT%" echo $brandPkgs += @{Pattern='*McAfee*';Label='McAfee ^(ASUS bundle^)'}
    >>"%STATUS_SCRIPT%" echo $brandPkgs += @{Pattern='*ASUSUpdate*';Label='ASUS Live Update'}
    >>"%STATUS_SCRIPT%" echo foreach ^($b in $brandPkgs^) { $i=Get-AppxPackage -Name $b.Pattern -AllUsers -ErrorAction SilentlyContinue; Write-Host ^("  "+$b.Label.PadRight^(30^)+": "^) -ForegroundColor White -NoNewline; if ^($i^) { Write-Host "INSTALLED (BLOAT)" -ForegroundColor Red } else { Write-Host "CLEAN / NOT FOUND" -ForegroundColor Green } }
)
if "!SYS_BRAND!"=="Acer" (
    >>"%STATUS_SCRIPT%" echo Write-Host "  === ACER BRAND BLOATWARE ===" -ForegroundColor !COL_HDR_PS!
    >>"%STATUS_SCRIPT%" echo Write-Host ""
    >>"%STATUS_SCRIPT%" echo $brandPkgs = @^(^)
    >>"%STATUS_SCRIPT%" echo $brandPkgs += @{Pattern='*AcerCare*';Label='Acer Care Center'}
    >>"%STATUS_SCRIPT%" echo $brandPkgs += @{Pattern='*McAfee*';Label='McAfee ^(Acer bundle^)'}
    >>"%STATUS_SCRIPT%" echo $brandPkgs += @{Pattern='*AcerCollection*';Label='Acer Collection'}
    >>"%STATUS_SCRIPT%" echo $brandPkgs += @{Pattern='*AcerPortal*';Label='Acer Portal'}
    >>"%STATUS_SCRIPT%" echo foreach ^($b in $brandPkgs^) { $i=Get-AppxPackage -Name $b.Pattern -AllUsers -ErrorAction SilentlyContinue; Write-Host ^("  "+$b.Label.PadRight^(30^)+": "^) -ForegroundColor White -NoNewline; if ^($i^) { Write-Host "INSTALLED (BLOAT)" -ForegroundColor Red } else { Write-Host "CLEAN / NOT FOUND" -ForegroundColor Green } }
)
if "!SYS_BRAND!"=="MSI" (
    >>"%STATUS_SCRIPT%" echo Write-Host "  === MSI BRAND BLOATWARE ===" -ForegroundColor !COL_HDR_PS!
    >>"%STATUS_SCRIPT%" echo Write-Host ""
    >>"%STATUS_SCRIPT%" echo $brandPkgs = @^(^)
    >>"%STATUS_SCRIPT%" echo $brandPkgs += @{Pattern='*MSIDragon*';Label='MSI Center/Dragon Center'}
    >>"%STATUS_SCRIPT%" echo $brandPkgs += @{Pattern='*McAfee*';Label='McAfee ^(MSI bundle^)'}
    >>"%STATUS_SCRIPT%" echo $brandPkgs += @{Pattern='*MSIAppPlayer*';Label='MSI App Player'}
    >>"%STATUS_SCRIPT%" echo foreach ^($b in $brandPkgs^) { $i=Get-AppxPackage -Name $b.Pattern -AllUsers -ErrorAction SilentlyContinue; Write-Host ^("  "+$b.Label.PadRight^(30^)+": "^) -ForegroundColor White -NoNewline; if ^($i^) { Write-Host "INSTALLED (BLOAT)" -ForegroundColor Red } else { Write-Host "CLEAN / NOT FOUND" -ForegroundColor Green } }
)
if "!SYS_BRAND!"=="Samsung" (
    >>"%STATUS_SCRIPT%" echo Write-Host "  === SAMSUNG BRAND BLOATWARE ===" -ForegroundColor !COL_HDR_PS!
    >>"%STATUS_SCRIPT%" echo Write-Host ""
    >>"%STATUS_SCRIPT%" echo $brandPkgs = @^(^)
    if "!SYS_FORM!"=="LAPTOP" (
        >>"%STATUS_SCRIPT%" echo $brandPkgs += @{Pattern='*SamsungSettings*';Label='Samsung Settings'}
    )
    >>"%STATUS_SCRIPT%" echo $brandPkgs += @{Pattern='*McAfee*';Label='McAfee ^(Samsung bundle^)'}
    >>"%STATUS_SCRIPT%" echo $brandPkgs += @{Pattern='*SamsungNotes*';Label='Samsung Notes'}
    >>"%STATUS_SCRIPT%" echo foreach ^($b in $brandPkgs^) { $i=Get-AppxPackage -Name $b.Pattern -AllUsers -ErrorAction SilentlyContinue; Write-Host ^("  "+$b.Label.PadRight^(30^)+": "^) -ForegroundColor White -NoNewline; if ^($i^) { Write-Host "INSTALLED (BLOAT)" -ForegroundColor Red } else { Write-Host "CLEAN / NOT FOUND" -ForegroundColor Green } }
)
if "!SYS_BRAND!"=="Microsoft" (
    if "!SYS_FORM!"=="LAPTOP" (
        >>"%STATUS_SCRIPT%" echo Write-Host "  === SURFACE BRAND BLOATWARE ===" -ForegroundColor !COL_HDR_PS!
        >>"%STATUS_SCRIPT%" echo Write-Host ""
        >>"%STATUS_SCRIPT%" echo $brandPkgs = @^(^)
        >>"%STATUS_SCRIPT%" echo $brandPkgs += @{Pattern='*SurfaceApp*';Label='Surface App'}
        >>"%STATUS_SCRIPT%" echo $brandPkgs += @{Pattern='*SurfaceHub*';Label='Surface Hub'}
        >>"%STATUS_SCRIPT%" echo foreach ^($b in $brandPkgs^) { $i=Get-AppxPackage -Name $b.Pattern -AllUsers -ErrorAction SilentlyContinue; Write-Host ^("  "+$b.Label.PadRight^(30^)+": "^) -ForegroundColor White -NoNewline; if ^($i^) { Write-Host "INSTALLED (BLOAT)" -ForegroundColor Red } else { Write-Host "CLEAN / NOT FOUND" -ForegroundColor Green } }
    )
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%STATUS_SCRIPT%"
del "%STATUS_SCRIPT%" >nul 2>&1
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
echo.
pause
goto MAIN_MENU

:USAGE_DASHBOARD
cls
color !COL_HDR!
echo.
echo  =============================================
echo    --- USAGE --- System Resource Dashboard
echo  =============================================
echo.
set "USAGE_SCRIPT=%TEMP%\ytsh_usage_%RANDOM%%RANDOM%.ps1"
if exist "%USAGE_SCRIPT%" del "%USAGE_SCRIPT%" >nul 2>&1
(
    echo Write-Host ""
    echo Write-Host "  === DISK USAGE ===" -ForegroundColor Cyan
    echo Write-Host ""
    echo $drives = Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue
    echo foreach ^($d in $drives^) {
    echo     if ^($d.Used -ne $null -and ^($d.Used + $d.Free^) -gt 0^) {
    echo         $total = $d.Used + $d.Free
    echo         $usedGB = [math]::Round^($d.Used / 1GB, 2^)
    echo         $freeGB = [math]::Round^($d.Free / 1GB, 2^)
    echo         $totalGB = [math]::Round^($total / 1GB, 2^)
    echo         $pct = [math]::Round^($d.Used / $total * 100, 1^)
    echo         $bar = "#" * [math]::Floor^($pct / 5^) + "-" * ^(20 - [math]::Floor^($pct / 5^)^)
    echo         $col = if ^($pct -gt 85^) { 'Red' } elseif ^($pct -gt 60^) { 'Yellow' } else { 'Green' }
    echo         Write-Host ^("  Drive " + $d.Name + ":  [" + $bar + "] " + $pct + "%%  (" + $usedGB + " GB used / " + $totalGB + " GB total, " + $freeGB + " GB free)"^) -ForegroundColor $col
    echo     }
    echo }
    echo Write-Host ""
    echo Write-Host "  === RAM USAGE ===" -ForegroundColor Cyan
    echo Write-Host ""
    echo $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
    echo $totalRamMB = [math]::Round^($os.TotalVisibleMemorySize / 1024, 0^)
    echo $freeRamMB  = [math]::Round^($os.FreePhysicalMemory / 1024, 0^)
    echo $usedRamMB  = $totalRamMB - $freeRamMB
    echo $ramPct     = [math]::Round^($usedRamMB / $totalRamMB * 100, 1^)
    echo $ramBar     = "#" * [math]::Floor^($ramPct / 5^) + "-" * ^(20 - [math]::Floor^($ramPct / 5^)^)
    echo $ramCol     = if ^($ramPct -gt 85^) { 'Red' } elseif ^($ramPct -gt 60^) { 'Yellow' } else { 'Green' }
    echo $totalRamGB = [math]::Round^($totalRamMB / 1024, 1^)
    echo $usedRamGB  = [math]::Round^($usedRamMB / 1024, 2^)
    echo $freeRamGB  = [math]::Round^($freeRamMB / 1024, 2^)
    echo Write-Host ^("  RAM:      [" + $ramBar + "] " + $ramPct + "%%  (" + $usedRamGB + " GB used / " + $totalRamGB + " GB total)"^) -ForegroundColor $ramCol
    echo Write-Host ^("  Free RAM: " + $freeRamGB + " GB available"^) -ForegroundColor DarkGray
    echo $ramSavePath = "$env:TEMP\ytsh_ram_before.txt"
    echo if ^(-not ^(Test-Path $ramSavePath^)^) {
    echo     $ramPct ^| Set-Content $ramSavePath
    echo     Write-Host "  [INFO] Baseline RAM %% saved. Run Disk Cleanup to compare." -ForegroundColor DarkGray
    echo } else {
    echo     $prev = [double]^(Get-Content $ramSavePath^)
    echo     $diff = [math]::Round^($prev - $ramPct, 1^)
    echo     if ^($diff -gt 0^) {
    echo         Write-Host ^("  Your OS uses " + $diff + "%% LESS RAM than before cleaning."^) -ForegroundColor Green
    echo     } elseif ^($diff -lt 0^) {
    echo         Write-Host ^("  RAM usage is " + [math]::Abs^($diff^) + "%% HIGHER than baseline."^) -ForegroundColor Yellow
    echo     } else {
    echo         Write-Host "  RAM usage unchanged since last baseline." -ForegroundColor DarkGray
    echo     }
    echo }
    echo Write-Host ""
) >> "%USAGE_SCRIPT%"
(
    echo Write-Host "  === CPU / GPU TEMPERATURES ^& HEALTH ===" -ForegroundColor Cyan
    echo Write-Host ""
    echo $cpuObj    = Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue ^| Select-Object -First 1
    echo $cpuVendor = if ^($cpuObj^) { $cpuObj.Manufacturer } else { '' }
    echo $cpuTempC  = $null
    echo $cpuSource = ''
    echo try {
    echo     $r = Get-WmiObject -Namespace root\OpenHardwareMonitor -Class Sensor -ErrorAction Stop ^| Where-Object { $_.SensorType -eq 'Temperature' -and $_.Name -match 'CPU' } ^| Sort-Object Value -Descending ^| Select-Object -First 1
    echo     if ^($r^) { $cpuTempC = [math]::Round^($r.Value, 1^); $cpuSource = 'OpenHardwareMonitor' }
    echo } catch {}
    echo if ^($cpuTempC -eq $null^) {
    echo     try {
    echo         $r = Get-WmiObject -Namespace root\LibreHardwareMonitor -Class Sensor -ErrorAction Stop ^| Where-Object { $_.SensorType -eq 'Temperature' -and $_.Name -match 'CPU' } ^| Sort-Object Value -Descending ^| Select-Object -First 1
    echo         if ^($r^) { $cpuTempC = [math]::Round^($r.Value, 1^); $cpuSource = 'LibreHardwareMonitor' }
    echo     } catch {}
    echo }
    echo if ^($cpuTempC -eq $null^) {
    echo     try {
    echo         $tz = Get-WmiObject -Namespace root\wmi -Class MSAcpi_ThermalZoneTemperature -ErrorAction Stop
    echo         if ^($tz^) { $cpuTempC = ^($tz ^| ForEach-Object { [math]::Round^($_.CurrentTemperature / 10 - 273.15, 1^) } ^| Measure-Object -Maximum^).Maximum; $cpuSource = 'WMI' }
    echo     } catch {}
    echo }
    echo if ^($cpuTempC -eq $null^) {
    echo     try {
    echo         $sample = ^(Get-Counter '\Thermal Zone Information^(*^)\Temperature' -ErrorAction Stop^).CounterSamples ^| Where-Object { $_.CookedValue -gt 0 }
    echo         $maxK   = ^($sample ^| Measure-Object CookedValue -Maximum^).Maximum
    echo         if ^($maxK -gt 273^) { $cpuTempC = [math]::Round^($maxK - 273.15, 1^); $cpuSource = 'PerfCounter' }
    echo     } catch {}
    echo }
    echo if ^($cpuTempC -ne $null^) {
    echo     $tcol    = if ^($cpuTempC -gt 90^) { 'Red' } elseif ^($cpuTempC -gt 75^) { 'Yellow' } else { 'Green' }
    echo     $thealth = if ^($cpuTempC -gt 90^) { 'CRITICAL - check cooling!' } elseif ^($cpuTempC -gt 75^) { 'Warm - monitor closely' } else { 'Good' }
    echo     Write-Host ^("  CPU Temp : " + $cpuTempC + " C  [" + $thealth + "]  via " + $cpuSource^) -ForegroundColor $tcol
    echo } else {
    echo     Write-Host "  CPU Temp : Not readable natively." -ForegroundColor DarkGray
    echo     if ^($cpuVendor -match 'AMD'^)    { Write-Host "             AMD Ryzen: run LibreHardwareMonitor first (free, no install)." -ForegroundColor DarkGray }
    echo     elseif ^($cpuVendor -match 'Intel'^) { Write-Host "             Intel: run OpenHardwareMonitor first." -ForegroundColor DarkGray }
    echo     else { Write-Host "             Run LibreHardwareMonitor or HWiNFO64." -ForegroundColor DarkGray }
    echo }
    echo if ^($cpuObj^) {
    echo     $load = $cpuObj.LoadPercentage
    echo     $lcol = if ^($load -gt 90^) { 'Red' } elseif ^($load -gt 70^) { 'Yellow' } else { 'Green' }
    echo     Write-Host ^("  CPU Load : " + $load + "%%"^) -ForegroundColor $lcol
    echo }
    echo Write-Host ""
    echo $gpus = Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue ^| Where-Object { $_.Name -notmatch 'Basic Display' -and $_.Name -notmatch 'Remote' }
    echo $gpuUtilRaw = $null
    echo try {
    echo     $gpuUtilRaw = ^(Get-Counter '\GPU Engine^(*engtype_3D^)\Utilization Percentage' -ErrorAction Stop^).CounterSamples ^| Where-Object { $_.InstanceName -match 'engtype_3D' }
    echo } catch {}
    echo foreach ^($gpuCtrl in $gpus^) {
    echo     $gName   = $gpuCtrl.Name.Trim^(^)
    echo     $isNV    = $gName -match 'NVIDIA^|GeForce^|Quadro^|RTX^|GTX'
    echo     $isAMD   = $gName -match 'AMD^|Radeon'
    echo     $isIntel = $gName -match 'Intel.*Graphics^|UHD^|Iris^|Arc'
    echo     $drvOk   = ^($gpuCtrl.ConfigManagerErrorCode -eq 0^)
    echo     $drvTxt  = if ^($drvOk^) { '[Driver OK]' } else { '[Driver Error ' + $gpuCtrl.ConfigManagerErrorCode + ']' }
    echo     $drvCol  = if ^($drvOk^) { 'Green' } else { 'Red' }
    echo     Write-Host ^("  GPU      : " + $gName + "  " + $drvTxt^) -ForegroundColor $drvCol
    echo     $gTempC = $null; $gUtil = $null; $gMemU = $null; $gMemT = $null; $gSource = ''
    echo     if ^($isNV^) {
    echo         $nsmi = ^(Get-Command nvidia-smi -ErrorAction SilentlyContinue^).Source
    echo         if ^($nsmi^) {
    echo             try {
    echo                 $raw = ^(^& $nsmi --query-gpu=temperature.gpu,utilization.gpu,memory.used,memory.total --format=csv,noheader,nounits 2^>$null^)
    echo                 if ^($raw^) { $v = $raw -split ','; $gTempC = [int]$v[0].Trim^(^); $gUtil = $v[1].Trim^(^); $gMemU = $v[2].Trim^(^); $gMemT = $v[3].Trim^(^); $gSource = 'nvidia-smi' }
    echo             } catch {}
    echo         }
    echo     }
    echo     if ^($gTempC -eq $null^) {
    echo         foreach ^($ns in @^('root\OpenHardwareMonitor','root\LibreHardwareMonitor'^)^) {
    echo             try {
    echo                 $r = Get-WmiObject -Namespace $ns -Class Sensor -ErrorAction Stop ^| Where-Object { $_.SensorType -eq 'Temperature' -and $_.Name -match 'GPU' } ^| Sort-Object Value -Descending ^| Select-Object -First 1
    echo                 if ^($r^) { $gTempC = [math]::Round^($r.Value, 1^); $gSource = if ^($ns -like '*Libre*'^) { 'LHM' } else { 'OHM' }; break }
    echo             } catch {}
    echo         }
    echo     }
    echo     if ^($gTempC -ne $null^) {
    echo         $gcol    = if ^($gTempC -gt 85^) { 'Red' } elseif ^($gTempC -gt 70^) { 'Yellow' } else { 'Green' }
    echo         $ghealth = if ^($gTempC -gt 85^) { 'HOT - check airflow!' } elseif ^($gTempC -gt 70^) { 'Warm' } else { 'Good' }
    echo         Write-Host ^("  GPU Temp : " + $gTempC + " C  [" + $ghealth + "]  via " + $gSource^) -ForegroundColor $gcol
    echo     } else {
    echo         if ^($isNV^)       { Write-Host "  GPU Temp : nvidia-smi not found. Ensure NVIDIA drivers are installed." -ForegroundColor DarkGray }
    echo         elseif ^($isAMD^)   { Write-Host "  GPU Temp : Not available natively on AMD Radeon - Windows exposes no GPU temp API for Radeon cards. Run LibreHardwareMonitor first." -ForegroundColor DarkGray }
    echo         elseif ^($isIntel^) { Write-Host "  GPU Temp : Not available natively on Intel iGPU/Arc. Run LibreHardwareMonitor first." -ForegroundColor DarkGray }
    echo         else { Write-Host "  GPU Temp : Not available." -ForegroundColor DarkGray }
    echo     }
    echo     $luid = $gpuCtrl.PNPDeviceID
    echo     $util3D = $null
    echo     if ^($gpuUtilRaw^) {
    echo         $match  = $gpuUtilRaw ^| Where-Object { $_.InstanceName -match 'luid' } ^| Measure-Object CookedValue -Sum
    echo         if ^($match.Count -gt 0^) { $util3D = [math]::Round^($match.Sum, 1^) }
    echo         if ^($util3D -eq $null^) { $util3D = [math]::Round^(^($gpuUtilRaw ^| Measure-Object CookedValue -Sum^).Sum, 1^) }
    echo     }
    echo     if ^($util3D -ne $null^) {
    echo         $ucol = if ^($util3D -gt 90^) { 'Red' } elseif ^($util3D -gt 70^) { 'Yellow' } else { 'Green' }
    echo         Write-Host ^("  GPU Load : " + $util3D + "%% ^(3D^)"^) -ForegroundColor $ucol
    echo     }
    echo }
    echo Write-Host ""
) >> "%USAGE_SCRIPT%"
(
    echo $bat = Get-WmiObject Win32_Battery
    echo if ^($bat^) {
    echo     Write-Host "  === BATTERY HEALTH ===" -ForegroundColor Cyan
    echo     Write-Host ""
    echo     $charge = $bat.EstimatedChargeRemaining
    echo     $bstat  = if ^($bat.BatteryStatus -eq 1^) { 'Discharging' } elseif ^($bat.BatteryStatus -eq 2^) { 'On AC ^(not charging^)' } elseif ^($bat.BatteryStatus -eq 6^) { 'Charging' } else { 'Status ' + $bat.BatteryStatus }
    echo     $chcol  = if ^($charge -lt 15^) { 'Red' } elseif ^($charge -lt 30^) { 'Yellow' } else { 'Green' }
    echo     Write-Host ^("  Charge   : " + $charge + "%%  (" + $bstat + ")"^) -ForegroundColor $chcol
    echo     try {
    echo         $bStatic = Get-WmiObject -Namespace root\wmi -Class BatteryStaticData    -ErrorAction Stop ^| Select-Object -First 1
    echo         $bFull   = Get-WmiObject -Namespace root\wmi -Class BatteryFullChargedCapacity -ErrorAction Stop ^| Select-Object -First 1
    echo         if ^($bStatic -and $bFull -and $bStatic.DesignedCapacity -gt 0^) {
    echo             $design  = $bStatic.DesignedCapacity
    echo             $full    = $bFull.FullChargedCapacity
    echo             $health  = [math]::Round^($full / $design * 100, 1^)
    echo             $wear    = [math]::Round^(^($design - $full^) / $design * 100, 1^)
    echo             $hcol    = if ^($health -lt 50^) { 'Red' } elseif ^($health -lt 75^) { 'Yellow' } else { 'Green' }
    echo             $grade   = if ^($health -ge 80^) { 'Good' } elseif ^($health -ge 60^) { 'Degraded' } elseif ^($health -ge 40^) { 'Poor - consider replacing' } else { 'Critical - replace battery' }
    echo             Write-Host ^("  Capacity : " + $full + " mWh / " + $design + " mWh (design)"^) -ForegroundColor $hcol
    echo             Write-Host ^("  Health   : " + $health + "%%  ^|  Wear: " + $wear + "%%"^) -ForegroundColor $hcol
    echo             Write-Host ^("  Grade    : " + $grade^) -ForegroundColor $hcol
    echo         }
    echo     } catch { Write-Host "  Capacity : Detailed battery data unavailable via WMI." -ForegroundColor DarkGray }
    echo     Write-Host ""
    echo }
    echo Write-Host "  === STARTUP PROGRAMS ===" -ForegroundColor Cyan
    echo Write-Host ""
    echo $startupPaths = @^('HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run', 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run'^)
    echo $startupItems = @^(^)
    echo foreach ^($path in $startupPaths^) {
    echo     $entries = Get-ItemProperty -Path $path -ErrorAction SilentlyContinue
    echo     if ^($entries^) {
    echo         $entries.PSObject.Properties ^| Where-Object { $_.Name -notmatch '^PS' } ^| ForEach-Object {
    echo             $startupItems += [PSCustomObject]@{ Name = $_.Name; Value = $_.Value; Source = $path.Replace^('HKCU:\','HKCU\'^).Replace^('HKLM:\','HKLM\'^) }
    echo         }
    echo     }
    echo }
    echo if ^($startupItems.Count -eq 0^) {
    echo     Write-Host "  No startup registry entries found." -ForegroundColor DarkGray
    echo } else {
    echo     Write-Host ^("  " + $startupItems.Count + " startup program(s) found:"^) -ForegroundColor White
    echo     foreach ^($item in $startupItems^) {
    echo         $shortVal = if ^($item.Value.Length -gt 55^) { $item.Value.Substring^(0,55^) + "..." } else { $item.Value }
    echo         Write-Host ^("  [+] " + $item.Name.PadRight^(25^) + $shortVal^) -ForegroundColor Yellow
    echo     }
    echo }
    echo Write-Host ""
    echo Write-Host "  === ACTIVE NETWORK ADAPTERS ===" -ForegroundColor Cyan
    echo Write-Host ""
    echo $adapters = Get-NetAdapter -ErrorAction SilentlyContinue ^| Where-Object { $_.Status -eq 'Up' }
    echo if ^($adapters^) {
    echo     foreach ^($a in $adapters^) {
    echo         $dns = ^(Get-DnsClientServerAddress -InterfaceIndex $a.InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue^).ServerAddresses -join ', '
    echo         $ip  = ^(Get-NetIPAddress -InterfaceIndex $a.InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue^).IPAddress
    echo         if ^(-not $dns^) { $dns = 'Auto/DHCP' }
    echo         if ^(-not $ip^)  { $ip  = 'N/A' }
    echo         Write-Host ^("  [ACTIVE] " + $a.Name.PadRight^(22^) + " IP: " + $ip.PadRight^(17^) + " DNS: " + $dns^) -ForegroundColor Green
    echo     }
    echo } else {
    echo     Write-Host "  No active adapters found." -ForegroundColor DarkGray
    echo }
    echo $inactive = Get-NetAdapter -ErrorAction SilentlyContinue ^| Where-Object { $_.Status -ne 'Up' }
    echo foreach ^($a in $inactive^) {
    echo     Write-Host ^("  [----]   " + $a.Name.PadRight^(22^) + " Status: " + $a.Status^) -ForegroundColor DarkGray
    echo }
    echo Write-Host ""
    echo Write-Host "  =============================================" -ForegroundColor DarkGray
    echo Write-Host "  TIP: Run Disk Cleanup ^(option 4^) then return" -ForegroundColor DarkGray
    echo Write-Host "  here to see your RAM savings percentage." -ForegroundColor DarkGray
    echo Write-Host "  =============================================" -ForegroundColor DarkGray
    echo Write-Host ""
) >> "%USAGE_SCRIPT%"
powershell -NoProfile -ExecutionPolicy Bypass -File "%USAGE_SCRIPT%"
del "%USAGE_SCRIPT%" >nul 2>&1
echo  =============================================
echo.
set "UCHOICE="
set /p "UCHOICE=  Press R to reset RAM baseline, or any key to return: "
if /i "!UCHOICE!"=="R" (
    del "%TEMP%\ytsh_ram_before.txt" >nul 2>&1
    powershell -NoProfile -Command "Write-Host '  [OK] RAM baseline reset.' -ForegroundColor Cyan"
    echo.
    pause
)
goto MAIN_MENU

:INFO_SCREEN
cls
color !COL_OPS!
echo.
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '     YTSH Debloat Utility v1.0 - Information' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
echo.
powershell -NoProfile -Command "Write-Host '  [BLOATWARE APPS TARGETED]' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '  -------------------------------------------' -ForegroundColor !COL_HDR_PS!"
echo   01  Candy Crush Saga           (game)
echo   02  Solitaire Collection       (game)
echo   03  Bing News                  (news feed)
echo   04  Bing Weather               (weather app)
echo   05  Bing Search integration    (search stub)
echo   06  Xbox App                   (gaming hub)
echo   07  Xbox Game Bar + Overlay    (overlay)
echo   08  Xbox Identity Provider     (auth stub)
echo   09  Xbox Speech Overlay        (voice stub)
echo   10  Skype                      (messaging)
echo   11  Teams personal             (stub)
echo   12  Clipchamp                  (video editor)
echo   13  Mail and Calendar          (email app)
echo   14  People                     (contacts)
echo   15  Windows Maps               (maps)
echo   16  Alarms and Clock           (alarm)
echo   17  Mixed Reality Portal       (VR stub)
echo   18  3D Viewer                  (3D viewer)
echo   19  Print 3D                   (3D print)
echo   20  3D Builder                 (3D model)
echo   21  Feedback Hub               (MS feedback)
echo   22  Get Help                   (support app)
echo   23  Get Started / Tips         (tutorial)
echo   24  Power Automate Desktop     (automation)
echo   25  Microsoft To Do            (task list)
echo   26  Sticky Notes               (notes)
echo   27  Office Hub (My Office)     (MS Office ad)
echo   28  OneDrive Sync Stub         (cloud sync)
echo   29  Sound Recorder             (audio)
echo   30  Groove Music               (music player)
echo   31  Movies and TV              (video player)
echo   32  Phone Link / Your Phone    (phone sync)
echo   33  Cortana App                (AI assistant)
echo   34  OneNote bundled            (notes)
echo   35  Microsoft Wallet           (payments)
echo   36  OneConnect / Mobile Plans  (carrier stub)
echo   37  Outlook for Windows        (new email)
echo   38  Cortana Search             (search AI)
echo   39  Microsoft Start / MSN      (news)
echo   40-48  OEM stubs: TikTok, Disney+, Spotify,
echo           Facebook, Instagram, Netflix, Roblox,
echo           CandyCrush Friends, FarmVille
echo.
powershell -NoProfile -Command "Write-Host '  [SERVICES DISABLED]' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '  -------------------------------------------' -ForegroundColor !COL_HDR_PS!"
echo   DiagTrack, WMPNetworkSvc, RemoteRegistry
echo   Fax, WerSvc, MapsBroker, RetailDemo
echo   XblAuthManager, XblGameSave, XboxNetApiSvc
echo   XboxGipSvc, wisvc, WSearch, lfsvc
echo   SharedAccess, TrkWks, WbioSrvc, icssvc
echo   PhoneSvc, SmsRouter, TabletInputService
echo   WpcMonSvc, PrintNotify, PcaSvc
echo   HomeGroupListener, HomeGroupProvider
echo.
powershell -NoProfile -Command "Write-Host '  [TELEMETRY BLOCKED]' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '  -------------------------------------------' -ForegroundColor !COL_HDR_PS!"
echo   Diagnostic data, Advertising ID
echo   Tailored experiences, Feedback notifications
echo   Activity History, App launch tracking
echo   Location tracking, AppCompat telemetry
echo   Consumer Features, CEIP tasks
echo   Handwriting data, Typing insights
echo   Speech personalization, Wi-Fi Sense
echo.
powershell -NoProfile -Command "Write-Host '  [NEVER TOUCHED - ALWAYS SAFE]' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '  -------------------------------------------' -ForegroundColor !COL_HDR_PS!"
echo   Microsoft Store, Windows Security, Edge
echo   Start Menu, File Explorer, Taskbar
echo   Notepad, Calculator, Snipping Tool, Paint
echo   .NET, VC++ Runtimes, DirectX, all drivers
echo   Any service critical to Windows booting
echo.
powershell -NoProfile -Command "Write-Host '  [WARNINGS]' -ForegroundColor Yellow"
powershell -NoProfile -Command "Write-Host '  -------------------------------------------' -ForegroundColor Yellow"
echo   ! Restore Point created before all changes.
echo   ! WSearch disable = slower File Explorer
echo     search results (no indexing).
echo   ! Mail removal may affect taskbar calendar
echo     flyout (cosmetic issue only).
echo   ! Some apps may reinstall via Windows Update.
echo   ! OEM stubs (40-48) only removed if present.
echo.
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
echo.
pause
goto MAIN_MENU

:DO_REMOVE_ALL_APPS_NEWBIE
echo.
color !COL_OPS!
echo  =============================================
echo   Removing SAFE apps (Newbie mode)...
echo  =============================================
echo.
set "RMSCRIPT=%TEMP%\ytsh_remove_newbie_%RANDOM%%RANDOM%.ps1"
(
    echo $packages = @^(
    echo     'Microsoft.MicrosoftSolitaireCollection',
    echo     'Microsoft.BingNews',
    echo     'Microsoft.BingWeather',
    echo     'Microsoft.SkypeApp',
    echo     'MicrosoftTeams',
    echo     'Clipchamp.Clipchamp',
    echo     'Microsoft.People',
    echo     'Microsoft.MixedReality.Portal',
    echo     'Microsoft.Microsoft3DViewer',
    echo     'Microsoft.Print3D',
    echo     'Microsoft.3DBuilder',
    echo     'Microsoft.WindowsFeedbackHub',
    echo     'Microsoft.GetHelp',
    echo     'Microsoft.Getstarted',
    echo     'Microsoft.PowerAutomateDesktop',
    echo     'Microsoft.Todos',
    echo     'Microsoft.MicrosoftOfficeHub',
    echo     'Microsoft.ZuneMusic',
    echo     'Microsoft.ZuneVideo',
    echo     'Microsoft.Office.OneNote',
    echo     'Microsoft.Wallet',
    echo     'Microsoft.OneConnect',
    echo     'Microsoft.MicrosoftStart',
    echo     'MicrosoftWindows.Client.WebExperience',
    echo     'Microsoft.Messaging',
    echo     'Microsoft.CommsPhone',
    echo     'Microsoft.NetworkSpeedTest'
    echo ^)
    echo foreach ^($pkg in $packages^) {
    echo     try {
    echo         $inst = Get-AppxPackage -Name $pkg -AllUsers -ErrorAction SilentlyContinue
    echo         if ^($inst^) {
    echo             Remove-AppxPackage -Package $inst.PackageFullName -AllUsers -ErrorAction Stop
    echo             $prov = Get-AppxProvisionedPackage -Online ^| Where-Object { $_.DisplayName -eq $pkg }
    echo             if ^($prov^) { Remove-AppxProvisionedPackage -Online -PackageName $prov.PackageName -ErrorAction SilentlyContinue ^| Out-Null }
    echo             Write-Host ^('  [SUCCESS] ' + $pkg^) -ForegroundColor Green
    echo         } else {
    echo             Write-Host ^('  [SKIP] ' + $pkg^) -ForegroundColor DarkGray
    echo         }
    echo     } catch {
    echo         Write-Host ^('  [FAIL] ' + $pkg + ': ' + $_.Exception.Message^) -ForegroundColor Red
    echo     }
    echo }
) > "%RMSCRIPT%"
if "!SKIP_OEM!"=="0" (
    (
        echo $stubs = @^('*Disney*','*TikTok*','*Instagram*','*Facebook*','*Twitter*','*Spotify*','*PrimeVideo*','*AmazonVideo*','*Netflix*','*Hulu*','*CandyCrush*','*FarmVille*','*Roblox*'^)
        echo foreach ^($pattern in $stubs^) {
        echo     $pkgs = Get-AppxPackage -Name $pattern -AllUsers -ErrorAction SilentlyContinue
        echo     foreach ^($p in $pkgs^) {
        echo         try {
        echo             Remove-AppxPackage -Package $p.PackageFullName -AllUsers -ErrorAction Stop
        echo             Write-Host ^('  [SUCCESS STUB] ' + $p.Name^) -ForegroundColor Green
        echo         } catch {
        echo             Write-Host ^('  [FAIL STUB] ' + $p.Name^) -ForegroundColor Red
        echo         }
        echo     }
        echo }
    ) >> "%RMSCRIPT%"
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%RMSCRIPT%"
del "%RMSCRIPT%" >nul 2>&1
echo.
exit /b 0

:DO_REMOVE_ALL_APPS_STUDENT
echo.
color !COL_OPS!
echo  =============================================
echo   Removing SAFE apps (Student mode - school apps protected)...
echo  =============================================
echo.
set "RMSCRIPT=%TEMP%\ytsh_remove_student_%RANDOM%%RANDOM%.ps1"
(
    echo $packages = @^(
    echo     'Microsoft.MicrosoftSolitaireCollection',
    echo     'Microsoft.BingNews',
    echo     'Microsoft.BingWeather',
    echo     'Microsoft.SkypeApp',
    echo     'Clipchamp.Clipchamp',
    echo     'Microsoft.People',
    echo     'Microsoft.MixedReality.Portal',
    echo     'Microsoft.Microsoft3DViewer',
    echo     'Microsoft.Print3D',
    echo     'Microsoft.3DBuilder',
    echo     'Microsoft.WindowsFeedbackHub',
    echo     'Microsoft.GetHelp',
    echo     'Microsoft.Getstarted',
    echo     'Microsoft.PowerAutomateDesktop',
    echo     'Microsoft.MicrosoftOfficeHub',
    echo     'Microsoft.ZuneMusic',
    echo     'Microsoft.ZuneVideo',
    echo     'Microsoft.Wallet',
    echo     'Microsoft.OneConnect',
    echo     'Microsoft.MicrosoftStart',
    echo     'MicrosoftWindows.Client.WebExperience',
    echo     'Microsoft.Messaging',
    echo     'Microsoft.CommsPhone',
    echo     'Microsoft.NetworkSpeedTest'
    echo ^)
    echo foreach ^($pkg in $packages^) {
    echo     try {
    echo         $inst = Get-AppxPackage -Name $pkg -AllUsers -ErrorAction SilentlyContinue
    echo         if ^($inst^) {
    echo             Remove-AppxPackage -Package $inst.PackageFullName -AllUsers -ErrorAction Stop
    echo             $prov = Get-AppxProvisionedPackage -Online ^| Where-Object { $_.DisplayName -eq $pkg }
    echo             if ^($prov^) { Remove-AppxProvisionedPackage -Online -PackageName $prov.PackageName -ErrorAction SilentlyContinue ^| Out-Null }
    echo             Write-Host ^('  [SUCCESS] ' + $pkg^) -ForegroundColor Green
    echo         } else {
    echo             Write-Host ^('  [SKIP] ' + $pkg^) -ForegroundColor DarkGray
    echo         }
    echo     } catch {
    echo         Write-Host ^('  [FAIL] ' + $pkg + ': ' + $_.Exception.Message^) -ForegroundColor Red
    echo     }
    echo }
    echo Write-Host '  [PROTECTED] MicrosoftTeams - skipped ^(Student mode^)' -ForegroundColor Cyan
    echo Write-Host '  [PROTECTED] Microsoft.Todos - skipped ^(Student mode^)' -ForegroundColor Cyan
    echo Write-Host '  [PROTECTED] Microsoft.Office.OneNote - skipped ^(Student mode^)' -ForegroundColor Cyan
) > "%RMSCRIPT%"
if "!SKIP_OEM!"=="0" (
    (
        echo $stubs = @^('*Disney*','*TikTok*','*Instagram*','*Facebook*','*Twitter*','*Spotify*','*PrimeVideo*','*AmazonVideo*','*Netflix*','*Hulu*','*CandyCrush*','*FarmVille*','*Roblox*'^)
        echo foreach ^($pattern in $stubs^) {
        echo     $pkgs = Get-AppxPackage -Name $pattern -AllUsers -ErrorAction SilentlyContinue
        echo     foreach ^($p in $pkgs^) {
        echo         try {
        echo             Remove-AppxPackage -Package $p.PackageFullName -AllUsers -ErrorAction Stop
        echo             Write-Host ^('  [SUCCESS STUB] ' + $p.Name^) -ForegroundColor Green
        echo         } catch {
        echo             Write-Host ^('  [FAIL STUB] ' + $p.Name^) -ForegroundColor Red
        echo         }
        echo     }
        echo }
    ) >> "%RMSCRIPT%"
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%RMSCRIPT%"
del "%RMSCRIPT%" >nul 2>&1
echo.
exit /b 0

:DO_REMOVE_ALL_APPS_GAMER
echo.
color !COL_OPS!
echo  =============================================
echo   Removing SAFE + Xbox apps (Gamer mode)...
echo  =============================================
echo.
set "RMSCRIPT=%TEMP%\ytsh_remove_gamer_%RANDOM%%RANDOM%.ps1"
(
    echo $packages = @^(
    echo     'Microsoft.MicrosoftSolitaireCollection',
    echo     'Microsoft.BingNews',
    echo     'Microsoft.BingWeather',
    echo     'Microsoft.GamingApp',
    echo     'Microsoft.XboxApp',
    echo     'Microsoft.XboxGameOverlay',
    echo     'Microsoft.XboxGamingOverlay',
    echo     'Microsoft.XboxIdentityProvider',
    echo     'Microsoft.XboxSpeechToTextOverlay',
    echo     'Microsoft.SkypeApp',
    echo     'MicrosoftTeams',
    echo     'Clipchamp.Clipchamp',
    echo     'Microsoft.People',
    echo     'Microsoft.MixedReality.Portal',
    echo     'Microsoft.Microsoft3DViewer',
    echo     'Microsoft.Print3D',
    echo     'Microsoft.3DBuilder',
    echo     'Microsoft.WindowsFeedbackHub',
    echo     'Microsoft.GetHelp',
    echo     'Microsoft.Getstarted',
    echo     'Microsoft.PowerAutomateDesktop',
    echo     'Microsoft.Todos',
    echo     'Microsoft.MicrosoftOfficeHub',
    echo     'Microsoft.ZuneMusic',
    echo     'Microsoft.ZuneVideo',
    echo     'Microsoft.Office.OneNote',
    echo     'Microsoft.Wallet',
    echo     'Microsoft.OneConnect',
    echo     'Microsoft.MicrosoftStart',
    echo     'MicrosoftWindows.Client.WebExperience',
    echo     'Microsoft.Messaging',
    echo     'Microsoft.CommsPhone',
    echo     'Microsoft.NetworkSpeedTest'
    echo ^)
    echo foreach ^($pkg in $packages^) {
    echo     try {
    echo         $inst = Get-AppxPackage -Name $pkg -AllUsers -ErrorAction SilentlyContinue
    echo         if ^($inst^) {
    echo             Remove-AppxPackage -Package $inst.PackageFullName -AllUsers -ErrorAction Stop
    echo             $prov = Get-AppxProvisionedPackage -Online ^| Where-Object { $_.DisplayName -eq $pkg }
    echo             if ^($prov^) { Remove-AppxProvisionedPackage -Online -PackageName $prov.PackageName -ErrorAction SilentlyContinue ^| Out-Null }
    echo             Write-Host ^('  [SUCCESS] ' + $pkg^) -ForegroundColor Green
    echo         } else {
    echo             Write-Host ^('  [SKIP] ' + $pkg^) -ForegroundColor DarkGray
    echo         }
    echo     } catch {
    echo         Write-Host ^('  [FAIL] ' + $pkg + ': ' + $_.Exception.Message^) -ForegroundColor Red
    echo     }
    echo }
) > "%RMSCRIPT%"
if "!SKIP_OEM!"=="0" (
    (
        echo $stubs = @^('*Disney*','*TikTok*','*Instagram*','*Facebook*','*Twitter*','*Spotify*','*PrimeVideo*','*AmazonVideo*','*Netflix*','*Hulu*','*CandyCrush*','*FarmVille*','*Roblox*'^)
        echo foreach ^($pattern in $stubs^) {
        echo     $pkgs = Get-AppxPackage -Name $pattern -AllUsers -ErrorAction SilentlyContinue
        echo     foreach ^($p in $pkgs^) {
        echo         try {
        echo             Remove-AppxPackage -Package $p.PackageFullName -AllUsers -ErrorAction Stop
        echo             Write-Host ^('  [SUCCESS STUB] ' + $p.Name^) -ForegroundColor Green
        echo         } catch {
        echo             Write-Host ^('  [FAIL STUB] ' + $p.Name^) -ForegroundColor Red
        echo         }
        echo     }
        echo }
    ) >> "%RMSCRIPT%"
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%RMSCRIPT%"
del "%RMSCRIPT%" >nul 2>&1
echo.
exit /b 0

:DO_DISABLE_ALL_SERVICES_NEWBIE
echo.
color !COL_OPS!
echo  =============================================
echo   Disabling SAFE services (Newbie/Student mode)...
echo  =============================================
echo.
>>"%SVCLOG%" echo Service Disable Log (Newbie/Student) - %date% %time%
>>"%SVCLOG%" echo ============================================
set "SVCSCRIPT=%TEMP%\ytsh_disable_svcs_newbie_%RANDOM%%RANDOM%.ps1"
(
    echo $svcs = @^('DiagTrack','WMPNetworkSvc','RemoteRegistry','Fax','MapsBroker','RetailDemo','wisvc','TrkWks','PhoneSvc','SmsRouter','WpcMonSvc','HomeGroupListener','HomeGroupProvider'^)
    echo foreach ^($svc in $svcs^) {
    echo     try {
    echo         $s = Get-Service -Name $svc -ErrorAction SilentlyContinue
    echo         if ^($s^) {
    echo             $startMode = $s.StartType
    echo             $num = 3
    echo             if ^($startMode -eq 'Automatic'^) { $num = 2 }
    echo             if ^($startMode -eq 'Manual'^) { $num = 3 }
    echo             if ^($startMode -eq 'Disabled'^) { $num = 4 }
    echo             Add-Content -Path '!SVCLOG!' -Value ^($svc + "=" + $num^)
    echo             Set-Service -Name $svc -StartupType Disabled -ErrorAction Stop
    echo             Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue
    echo             Write-Host ^('  [SUCCESS] ' + $svc + ' disabled.'^) -ForegroundColor Green
    echo         } else {
    echo             Write-Host ^('  [SKIP] ' + $svc + ' not found.'^) -ForegroundColor DarkGray
    echo         }
    echo     } catch {
    echo         Write-Host ^('  [FAIL] ' + $svc^) -ForegroundColor Red
    echo     }
    echo }
) > "%SVCSCRIPT%"
powershell -NoProfile -ExecutionPolicy Bypass -File "%SVCSCRIPT%"
del "%SVCSCRIPT%" >nul 2>&1
echo.
exit /b 0

:DO_DISABLE_ALL_SERVICES_GAMER
echo.
color !COL_OPS!
echo  =============================================
echo   Disabling SAFE + Xbox services (Gamer mode)...
echo  =============================================
echo.
>>"%SVCLOG%" echo Service Disable Log (Gamer) - %date% %time%
>>"%SVCLOG%" echo ============================================
set "SVCSCRIPT=%TEMP%\ytsh_disable_svcs_gamer_%RANDOM%%RANDOM%.ps1"
(
    echo $svcs = @^('DiagTrack','WMPNetworkSvc','RemoteRegistry','Fax','MapsBroker','RetailDemo','XblAuthManager','XblGameSave','XboxNetApiSvc','XboxGipSvc','wisvc','TrkWks','PhoneSvc','SmsRouter','WpcMonSvc','HomeGroupListener','HomeGroupProvider'^)
    echo foreach ^($svc in $svcs^) {
    echo     try {
    echo         $s = Get-Service -Name $svc -ErrorAction SilentlyContinue
    echo         if ^($s^) {
    echo             $startMode = $s.StartType
    echo             $num = 3
    echo             if ^($startMode -eq 'Automatic'^) { $num = 2 }
    echo             if ^($startMode -eq 'Manual'^) { $num = 3 }
    echo             if ^($startMode -eq 'Disabled'^) { $num = 4 }
    echo             Add-Content -Path '!SVCLOG!' -Value ^($svc + "=" + $num^)
    echo             Set-Service -Name $svc -StartupType Disabled -ErrorAction Stop
    echo             Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue
    echo             Write-Host ^('  [SUCCESS] ' + $svc + ' disabled.'^) -ForegroundColor Green
    echo         } else {
    echo             Write-Host ^('  [SKIP] ' + $svc + ' not found.'^) -ForegroundColor DarkGray
    echo         }
    echo     } catch {
    echo         Write-Host ^('  [FAIL] ' + $svc^) -ForegroundColor Red
    echo     }
    echo }
) > "%SVCSCRIPT%"
powershell -NoProfile -ExecutionPolicy Bypass -File "%SVCSCRIPT%"
del "%SVCSCRIPT%" >nul 2>&1
echo.
exit /b 0

:DO_REMOVE_ALL_APPS
echo.
>>"%LOGFILE%" echo Debloat App Removal Log - %date% %time%
>>"%LOGFILE%" echo ============================================
set "RMSCRIPT=%TEMP%\ytsh_remove_all_%RANDOM%%RANDOM%.ps1"
(
    echo $packages = @^(
    echo     'Microsoft.549981C3F5F10',
    echo     'Microsoft.BingNews',
    echo     'Microsoft.BingWeather',
    echo     'Microsoft.BingSearch',
    echo     'Microsoft.GamingApp',
    echo     'Microsoft.GetHelp',
    echo     'Microsoft.Getstarted',
    echo     'Microsoft.MicrosoftOfficeHub',
    echo     'Microsoft.MicrosoftSolitaireCollection',
    echo     'Microsoft.MixedReality.Portal',
    echo     'Microsoft.People',
    echo     'Microsoft.PowerAutomateDesktop',
    echo     'Microsoft.SkypeApp',
    echo     'Microsoft.Todos',
    echo     'Microsoft.WindowsAlarms',
    echo     'Microsoft.WindowsCommunicationsApps',
    echo     'Microsoft.WindowsFeedbackHub',
    echo     'Microsoft.WindowsMaps',
    echo     'Microsoft.WindowsSoundRecorder',
    echo     'Microsoft.XboxApp',
    echo     'Microsoft.XboxGameOverlay',
    echo     'Microsoft.XboxGamingOverlay',
    echo     'Microsoft.XboxIdentityProvider',
    echo     'Microsoft.XboxSpeechToTextOverlay',
    echo     'Microsoft.YourPhone',
    echo     'Microsoft.ZuneMusic',
    echo     'Microsoft.ZuneVideo',
    echo     'Clipchamp.Clipchamp',
    echo     'MicrosoftTeams',
    echo     'Microsoft.OutlookForWindows',
    echo     'Microsoft.Microsoft3DViewer',
    echo     'Microsoft.Print3D',
    echo     'Microsoft.3DBuilder',
    echo     'Microsoft.MicrosoftStickyNotes',
    echo     'Microsoft.OneDriveSync',
    echo     'Microsoft.Cortana',
    echo     'Microsoft.WindowsFeedback',
    echo     'Microsoft.Office.OneNote',
    echo     'Microsoft.OneConnect',
    echo     'Microsoft.Wallet',
    echo     'Microsoft.MicrosoftStart',
    echo     'MicrosoftWindows.Client.WebExperience',
    echo     'Microsoft.Messaging',
    echo     'Microsoft.CommsPhone',
    echo     'Microsoft.NetworkSpeedTest'
    echo ^)
    echo foreach ^($pkg in $packages^) {
    echo     try {
    echo         $inst = Get-AppxPackage -Name $pkg -AllUsers -ErrorAction SilentlyContinue
    echo         if ^($inst^) {
    echo             Remove-AppxPackage -Package $inst.PackageFullName -AllUsers -ErrorAction Stop
    echo             $prov = Get-AppxProvisionedPackage -Online ^| Where-Object { $_.DisplayName -eq $pkg }
    echo             if ^($prov^) { Remove-AppxProvisionedPackage -Online -PackageName $prov.PackageName -ErrorAction SilentlyContinue ^| Out-Null }
    echo             Write-Host ^('  [SUCCESS] ' + $pkg^) -ForegroundColor Green
    echo         } else {
    echo             Write-Host ^('  [SKIP] ' + $pkg^) -ForegroundColor DarkGray
    echo         }
    echo     } catch {
    echo         Write-Host ^('  [FAIL] ' + $pkg + ': ' + $_.Exception.Message^) -ForegroundColor Red
    echo     }
    echo }
) > "%RMSCRIPT%"
if "!SKIP_OEM!"=="0" (
    (
        echo $stubs = @^(
        echo     '*Disney*','*TikTok*','*Instagram*','*Facebook*','*Twitter*',
        echo     '*Spotify*','*PrimeVideo*','*AmazonVideo*','*Dolby*',
        echo     '*LinkedInforWindows*','*Netflix*','*Hulu*','*PandoraMediaInc*',
        echo     '*iHeartRadio*','*CandyCrush*','*FarmVille*','*Roblox*',
        echo     '*EclipseManager*','*ActiproSoftwareLLC*','*AdobeSystemsIncorporated*',
        echo     '*Duolingo*','*EvernoteWindows*'
        echo ^)
        echo foreach ^($pattern in $stubs^) {
        echo     $pkgs = Get-AppxPackage -Name $pattern -AllUsers -ErrorAction SilentlyContinue
        echo     foreach ^($p in $pkgs^) {
        echo         try {
        echo             Remove-AppxPackage -Package $p.PackageFullName -AllUsers -ErrorAction Stop
        echo             Write-Host ^('  [SUCCESS STUB] ' + $p.Name^) -ForegroundColor Green
        echo         } catch {
        echo             Write-Host ^('  [FAIL STUB] ' + $p.Name^) -ForegroundColor Red
        echo         }
        echo     }
        echo }
    ) >> "%RMSCRIPT%"
) else (
    powershell -NoProfile -Command "Write-Host '  [SKIP] OEM stubs excluded per Settings.' -ForegroundColor DarkGray"
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%RMSCRIPT%"
del "%RMSCRIPT%" >nul 2>&1
echo.
exit /b 0

:DO_DISABLE_ALL_SERVICES
echo.
color !COL_OPS!
echo  =============================================
echo   Disabling all unnecessary services...
echo  =============================================
echo.
>>"%SVCLOG%" echo Service Disable Log - %date% %time%
>>"%SVCLOG%" echo ============================================
set "SVCSCRIPT=%TEMP%\ytsh_disable_svcs_%RANDOM%%RANDOM%.ps1"
(
    echo $svcs = @^('DiagTrack','WMPNetworkSvc','RemoteRegistry','Fax','WerSvc','MapsBroker','RetailDemo','XblAuthManager','XblGameSave','XboxNetApiSvc','XboxGipSvc','wisvc','WSearch','lfsvc','SharedAccess','TrkWks','WbioSrvc','icssvc','PhoneSvc','SmsRouter','TabletInputService','WpcMonSvc','PrintNotify','PcaSvc','HomeGroupListener','HomeGroupProvider'^)
    echo foreach ^($s in $svcs^) {
    echo     $svc = Get-Service -Name $s -ErrorAction SilentlyContinue
    echo     if ^($svc^) {
    echo         $startMode = $svc.StartType
    echo         $num = 3
    echo         if ^($startMode -eq 'Automatic'^) { $num = 2 }
    echo         if ^($startMode -eq 'Manual'^) { $num = 3 }
    echo         if ^($startMode -eq 'Disabled'^) { $num = 4 }
    echo         Add-Content -Path '!SVCLOG!' -Value ^($s + "=" + $num^)
    echo         try {
    echo             Set-Service -Name $s -StartupType Disabled -ErrorAction Stop
    echo             Stop-Service -Name $s -Force -ErrorAction SilentlyContinue
    echo             Write-Host ^("  [SUCCESS] " + $s + " disabled"^) -ForegroundColor Green
    echo         } catch {
    echo             Write-Host ^("  [FAIL] " + $s + ": " + $_.Exception.Message^) -ForegroundColor Red
    echo         }
    echo     } else {
    echo         Write-Host ^("  [SKIP] " + $s + " not found"^) -ForegroundColor DarkGray
    echo     }
    echo }
) > "%SVCSCRIPT%"
powershell -NoProfile -ExecutionPolicy Bypass -File "%SVCSCRIPT%"
del "%SVCSCRIPT%" >nul 2>&1
echo.
exit /b 0

:DO_DISABLE_ALL_TELEMETRY
echo.
color !COL_OPS!
echo  =============================================
echo   Disabling all telemetry and privacy keys...
echo  =============================================
echo.
>>"%REGLOG%" echo Registry Change Log - %date% %time%
>>"%REGLOG%" echo ============================================
if not exist "!REGPOINTS_DIR!" mkdir "!REGPOINTS_DIR!"
reg export "HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection" "!REGPOINTS_DIR!\telemetry_backup.reg" /y >nul 2>&1
reg export "HKLM\SOFTWARE\Policies\Microsoft\Windows\CloudContent" "!REGPOINTS_DIR!\telemetry_backup_cc.reg" /y >nul 2>&1
set "TELSCRIPT=%TEMP%\ytsh_telemetry_all_%RANDOM%%RANDOM%.ps1"
(
    echo try { $r = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection'; if ^(-not ^(Test-Path $r^)^) { New-Item -Path $r -Force ^| Out-Null }; Set-ItemProperty -Path $r -Name 'AllowTelemetry' -Value 0 -Type DWord -Force; Set-ItemProperty -Path $r -Name 'DisableEnterpriseAuthProxy' -Value 1 -Type DWord -Force; Write-Host '  [SUCCESS] Diagnostic Data Collection Disabled' -ForegroundColor Green } catch { Write-Host ^('  [FAIL] DiagData: ' + $_.Exception.Message^) -ForegroundColor Red }
    echo try { $r = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\AdvertisingInfo'; if ^(-not ^(Test-Path $r^)^) { New-Item -Path $r -Force ^| Out-Null }; Set-ItemProperty -Path $r -Name 'Enabled' -Value 0 -Type DWord -Force; Write-Host '  [SUCCESS] Advertising ID Disabled' -ForegroundColor Green } catch { Write-Host ^('  [FAIL] AdvID: ' + $_.Exception.Message^) -ForegroundColor Red }
    echo try { $r = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Privacy'; if ^(-not ^(Test-Path $r^)^) { New-Item -Path $r -Force ^| Out-Null }; Set-ItemProperty -Path $r -Name 'TailoredExperiencesWithDiagnosticDataEnabled' -Value 0 -Type DWord -Force; Write-Host '  [SUCCESS] Tailored Experiences Disabled' -ForegroundColor Green } catch { Write-Host ^('  [FAIL] Tailored: ' + $_.Exception.Message^) -ForegroundColor Red }
    echo try { $r = 'HKCU:\SOFTWARE\Microsoft\Siuf\Rules'; if ^(-not ^(Test-Path $r^)^) { New-Item -Path $r -Force ^| Out-Null }; Set-ItemProperty -Path $r -Name 'NumberOfSIUFInPeriod' -Value 0 -Type DWord -Force; Write-Host '  [SUCCESS] Feedback Notifications Disabled' -ForegroundColor Green } catch { Write-Host ^('  [FAIL] Feedback: ' + $_.Exception.Message^) -ForegroundColor Red }
    echo try { $r = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System'; if ^(-not ^(Test-Path $r^)^) { New-Item -Path $r -Force ^| Out-Null }; Set-ItemProperty -Path $r -Name 'EnableActivityFeed' -Value 0 -Type DWord -Force; Set-ItemProperty -Path $r -Name 'PublishUserActivities' -Value 0 -Type DWord -Force; Set-ItemProperty -Path $r -Name 'UploadUserActivities' -Value 0 -Type DWord -Force; Write-Host '  [SUCCESS] Activity History / Timeline Disabled' -ForegroundColor Green } catch { Write-Host ^('  [FAIL] Activity: ' + $_.Exception.Message^) -ForegroundColor Red }
    echo try { $r = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Set-ItemProperty -Path $r -Name 'Start_TrackProgs' -Value 0 -Type DWord -Force; Write-Host '  [SUCCESS] App Launch Tracking Disabled' -ForegroundColor Green } catch { Write-Host ^('  [FAIL] AppTrack: ' + $_.Exception.Message^) -ForegroundColor Red }
    echo try { $r = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Sensor\Overrides\{BFA794E4-F964-4FDB-90F6-51056BFE4B44}'; if ^(-not ^(Test-Path $r^)^) { New-Item -Path $r -Force ^| Out-Null }; Set-ItemProperty -Path $r -Name 'SensorPermissionState' -Value 0 -Type DWord -Force; $r2 = 'HKLM:\SYSTEM\CurrentControlSet\Services\lfsvc\Service\Configuration'; if ^(-not ^(Test-Path $r2^)^) { New-Item -Path $r2 -Force ^| Out-Null }; Set-ItemProperty -Path $r2 -Name 'Status' -Value 0 -Type DWord -Force; Write-Host '  [SUCCESS] Location Tracking Disabled' -ForegroundColor Green } catch { Write-Host ^('  [FAIL] Location: ' + $_.Exception.Message^) -ForegroundColor Red }
    echo try { $r = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppCompat'; if ^(-not ^(Test-Path $r^)^) { New-Item -Path $r -Force ^| Out-Null }; Set-ItemProperty -Path $r -Name 'AITEnable' -Value 0 -Type DWord -Force; Set-ItemProperty -Path $r -Name 'DisableInventory' -Value 1 -Type DWord -Force; Write-Host '  [SUCCESS] AppCompat Telemetry Disabled' -ForegroundColor Green } catch { Write-Host ^('  [FAIL] AppCompat: ' + $_.Exception.Message^) -ForegroundColor Red }
    echo try { $r = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent'; if ^(-not ^(Test-Path $r^)^) { New-Item -Path $r -Force ^| Out-Null }; Set-ItemProperty -Path $r -Name 'DisableWindowsConsumerFeatures' -Value 1 -Type DWord -Force; Set-ItemProperty -Path $r -Name 'DisableSoftLanding' -Value 1 -Type DWord -Force; Set-ItemProperty -Path $r -Name 'DisableCloudOptimizedContent' -Value 1 -Type DWord -Force; Write-Host '  [SUCCESS] Windows Consumer Features Disabled' -ForegroundColor Green } catch { Write-Host ^('  [FAIL] Consumer: ' + $_.Exception.Message^) -ForegroundColor Red }
    echo try { $r = 'HKCU:\SOFTWARE\Microsoft\Personalization\Settings'; if ^(-not ^(Test-Path $r^)^) { New-Item -Path $r -Force ^| Out-Null }; Set-ItemProperty -Path $r -Name 'AcceptedPrivacyPolicy' -Value 0 -Type DWord -Force; $r2 = 'HKCU:\SOFTWARE\Microsoft\InputPersonalization'; if ^(-not ^(Test-Path $r2^)^) { New-Item -Path $r2 -Force ^| Out-Null }; Set-ItemProperty -Path $r2 -Name 'RestrictImplicitInkCollection' -Value 1 -Type DWord -Force; Set-ItemProperty -Path $r2 -Name 'RestrictImplicitTextCollection' -Value 1 -Type DWord -Force; $r3 = 'HKCU:\SOFTWARE\Microsoft\InputPersonalization\TrainedDataStore'; if ^(-not ^(Test-Path $r3^)^) { New-Item -Path $r3 -Force ^| Out-Null }; Set-ItemProperty -Path $r3 -Name 'HarvestContacts' -Value 0 -Type DWord -Force; Write-Host '  [SUCCESS] Handwriting Personalization Disabled' -ForegroundColor Green } catch { Write-Host ^('  [FAIL] Handwriting: ' + $_.Exception.Message^) -ForegroundColor Red }
    echo try { $r = 'HKCU:\SOFTWARE\Microsoft\Input\TIPC'; if ^(-not ^(Test-Path $r^)^) { New-Item -Path $r -Force ^| Out-Null }; Set-ItemProperty -Path $r -Name 'Enabled' -Value 0 -Type DWord -Force; Write-Host '  [SUCCESS] Typing Insights Disabled' -ForegroundColor Green } catch { Write-Host ^('  [FAIL] Typing: ' + $_.Exception.Message^) -ForegroundColor Red }
    echo try { $r = 'HKCU:\SOFTWARE\Microsoft\Speech_OneCore\Settings\OnlineSpeechPrivacy'; if ^(-not ^(Test-Path $r^)^) { New-Item -Path $r -Force ^| Out-Null }; Set-ItemProperty -Path $r -Name 'HasAccepted' -Value 0 -Type DWord -Force; Write-Host '  [SUCCESS] Speech Personalization Disabled' -ForegroundColor Green } catch { Write-Host ^('  [FAIL] Speech: ' + $_.Exception.Message^) -ForegroundColor Red }
echo try { $r = 'HKLM:\SOFTWARE\Microsoft\WcmSvc\wifinetworkmanager\config'; if ^(-not ^(Test-Path $r^)^) { New-Item -Path $r -Force ^| Out-Null }; Set-ItemProperty -Path $r -Name 'AutoConnectAllowedOEM' -Value 0 -Type DWord -Force; Write-Host '  [SUCCESS] Wi-Fi Sense Disabled' -ForegroundColor Green } catch { Write-Host ^('  [FAIL] WiFiSense: ' + $_.Exception.Message^) -ForegroundColor Red }
    echo if ^($env:SYS_OS -match 'Windows 10'^) { Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Feeds' -Name 'ShellFeedsTaskbarViewMode' -Value 2 -Type DWord -Force -ErrorAction SilentlyContinue }
    echo if ^($env:SYS_OS -match 'Windows 11'^) { Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name 'TaskbarDa' -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue }
) > "%TELSCRIPT%"
powershell -NoProfile -ExecutionPolicy Bypass -File "%TELSCRIPT%"
del "%TELSCRIPT%" >nul 2>&1
schtasks /change /tn "\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser" /disable >nul 2>&1
schtasks /change /tn "\Microsoft\Windows\Application Experience\ProgramDataUpdater" /disable >nul 2>&1
schtasks /change /tn "\Microsoft\Windows\Customer Experience Improvement Program\Consolidator" /disable >nul 2>&1
schtasks /change /tn "\Microsoft\Windows\Customer Experience Improvement Program\UsbCeip" /disable >nul 2>&1
schtasks /change /tn "\Microsoft\Windows\Application Experience\StartupAppTask" /disable >nul 2>&1
schtasks /change /tn "\Microsoft\Windows\DiskDiagnostic\Microsoft-Windows-DiskDiagnosticDataCollector" /disable >nul 2>&1
powershell -NoProfile -Command "Write-Host '  [SUCCESS] All telemetry scheduled tasks disabled' -ForegroundColor Green"
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications" /v GlobalUserDisabled /t REG_DWORD /d 1 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy" /v LetAppsRunInBackground /t REG_DWORD /d 2 /f >nul 2>&1
powershell -NoProfile -Command "Write-Host '  [SUCCESS] Option 89: UWP Background Apps globally disabled.' -ForegroundColor Green"
if "!SAFE_MODE!"=="1" (
    if "!SYS_DISK_TYPE!"=="HDD" (
        powershell -NoProfile -Command "Write-Host '  [SKIP] Option 90: SysMain skipped by Safe Mode on HDD.' -ForegroundColor DarkGray"
    ) else (
        sc stop "SysMain" >nul 2>&1
        sc config "SysMain" start= disabled >nul 2>&1
        powershell -NoProfile -Command "Write-Host '  [SUCCESS] Option 90: SysMain / Superfetch disabled.' -ForegroundColor Green"
    )
) else (
    sc stop "SysMain" >nul 2>&1
    sc config "SysMain" start= disabled >nul 2>&1
    powershell -NoProfile -Command "Write-Host '  [SUCCESS] Option 90: SysMain / Superfetch disabled.' -ForegroundColor Green"
)
echo.
exit /b 0

:DO_RESTORE_APPS
echo.
color !COL_OPS!
echo  =============================================
echo   Restoring removed apps via winget...
echo  =============================================
echo.
winget --version >nul 2>&1
if !errorLevel! equ 0 (
    set "WINGET_OK=1"
    powershell -NoProfile -Command "Write-Host '  [OK] winget is available.' -ForegroundColor Green"
) else (
    set "WINGET_OK=0"
    powershell -NoProfile -Command "Write-Host '  [WARN] winget not available. Skipping winget installs.' -ForegroundColor Red"
)
echo.
for /f "usebackq skip=2 tokens=*" %%L in ("%LOGFILE%") do (
    set "PKG=%%L"
    if not "!PKG!"=="" (
        echo !PKG! | findstr /r "^[A-Za-z0-9._-][A-Za-z0-9._-]*$" >nul 2>&1
        if !errorLevel! equ 0 (
            if "!WINGET_OK!"=="1" (
                winget install --id "!PKG!" --source msstore --silent --accept-package-agreements --accept-source-agreements >nul 2>&1
                if !errorLevel! equ 0 (
                    powershell -NoProfile -Command "Write-Host '  [SUCCESS] !PKG! restored' -ForegroundColor Green"
                ) else (
                    powershell -NoProfile -Command "Write-Host '  [FAIL] !PKG! - try Microsoft Store manually.' -ForegroundColor Red"
                )
            ) else (
                powershell -NoProfile -Command "Write-Host '  [SKIP - no winget] !PKG!' -ForegroundColor DarkGray"
            )
        ) else (
            powershell -NoProfile -Command "Write-Host '  [SKIP - invalid entry] !PKG!' -ForegroundColor DarkGray"
        )
    )
)
echo.
exit /b 0

:DO_RESTORE_SERVICES
echo.
color !COL_OPS!
echo  =============================================
echo   Restoring disabled services...
echo  =============================================
echo.
set "RSVCSCRIPT=%TEMP%\ytsh_restore_svcs_%RANDOM%%RANDOM%.ps1"
(
    echo foreach ^($line in Get-Content '!SVCLOG!' -ErrorAction SilentlyContinue^) {
    echo     if ^($line -match '='^) {
    echo         $parts = $line.Split^('='^)
    echo         $s = $parts[0]
    echo         $typeNum = $parts[1]
    echo         $startType = 'Manual'
    echo         if ^($typeNum -eq '2'^) { $startType = 'Automatic' }
    echo         if ^($typeNum -eq '4'^) { $startType = 'Disabled' }
    echo         try {
    echo             Set-Service -Name $s -StartupType $startType -ErrorAction Stop
    echo             if ^($startType -eq 'Automatic'^) { Start-Service -Name $s -ErrorAction SilentlyContinue }
    echo             Write-Host ^("  [SUCCESS] " + $s + " restored to " + $startType^) -ForegroundColor Green
    echo         } catch {
    echo             Write-Host ^("  [FAIL] " + $s^) -ForegroundColor Red
    echo         }
    echo     }
    echo }
) > "%RSVCSCRIPT%"
powershell -NoProfile -ExecutionPolicy Bypass -File "%RSVCSCRIPT%"
del "%RSVCSCRIPT%" >nul 2>&1
echo.
exit /b 0

:DO_RESTORE_ALL_TELEMETRY
echo.
color !COL_OPS!
echo  =============================================
echo   Restoring all telemetry settings...
echo  =============================================
echo.
if exist "!REGPOINTS_DIR!\telemetry_backup.reg" (
    reg import "!REGPOINTS_DIR!\telemetry_backup.reg" >nul 2>&1
    powershell -NoProfile -Command "Write-Host '  [SUCCESS] DataCollection registry backup restored.' -ForegroundColor Green"
)
if exist "!REGPOINTS_DIR!\telemetry_backup_cc.reg" (
    reg import "!REGPOINTS_DIR!\telemetry_backup_cc.reg" >nul 2>&1
    powershell -NoProfile -Command "Write-Host '  [SUCCESS] CloudContent registry backup restored.' -ForegroundColor Green"
)
set "REVSCRIPT=%TEMP%\ytsh_revert_all_tel_%RANDOM%%RANDOM%.ps1"
(
    echo try {
    echo     Remove-ItemProperty -Path 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\AdvertisingInfo' -Name 'Enabled' -ErrorAction SilentlyContinue
    echo     Remove-ItemProperty -Path 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Privacy' -Name 'TailoredExperiencesWithDiagnosticDataEnabled' -ErrorAction SilentlyContinue
    echo     Remove-ItemProperty -Path 'HKCU:\SOFTWARE\Microsoft\Siuf\Rules' -Name 'NumberOfSIUFInPeriod' -ErrorAction SilentlyContinue
    echo     Set-ItemProperty -Path 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name 'Start_TrackProgs' -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
    echo     Set-ItemProperty -Path 'HKCU:\SOFTWARE\Microsoft\InputPersonalization' -Name 'RestrictImplicitInkCollection' -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
    echo     Set-ItemProperty -Path 'HKCU:\SOFTWARE\Microsoft\InputPersonalization' -Name 'RestrictImplicitTextCollection' -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
    echo     Set-ItemProperty -Path 'HKCU:\SOFTWARE\Microsoft\Input\TIPC' -Name 'Enabled' -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
    echo     Set-ItemProperty -Path 'HKCU:\SOFTWARE\Microsoft\Speech_OneCore\Settings\OnlineSpeechPrivacy' -Name 'HasAccepted' -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
    echo     Set-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\WcmSvc\wifinetworkmanager\config' -Name 'AutoConnectAllowedOEM' -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
    echo     if ^($env:SYS_OS -match 'Windows 10'^) { Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Feeds' -Name 'ShellFeedsTaskbarViewMode' -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue }
    echo     if ^($env:SYS_OS -match 'Windows 11'^) { Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name 'TaskbarDa' -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue }
    echo     Write-Host '  [SUCCESS] All user-level telemetry keys reverted.' -ForegroundColor Green
    echo } catch {
    echo     Write-Host ^('  [FAIL] Telemetry revert: ' + $_.Exception.Message^) -ForegroundColor Red
    echo }
) > "%REVSCRIPT%"
powershell -NoProfile -ExecutionPolicy Bypass -File "%REVSCRIPT%"
del "%REVSCRIPT%" >nul 2>&1
schtasks /change /tn "\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser" /enable >nul 2>&1
schtasks /change /tn "\Microsoft\Windows\Application Experience\ProgramDataUpdater" /enable >nul 2>&1
schtasks /change /tn "\Microsoft\Windows\Customer Experience Improvement Program\Consolidator" /enable >nul 2>&1
schtasks /change /tn "\Microsoft\Windows\Customer Experience Improvement Program\UsbCeip" /enable >nul 2>&1
schtasks /change /tn "\Microsoft\Windows\Application Experience\StartupAppTask" /enable >nul 2>&1
schtasks /change /tn "\Microsoft\Windows\DiskDiagnostic\Microsoft-Windows-DiskDiagnosticDataCollector" /enable >nul 2>&1
powershell -NoProfile -Command "Write-Host '  [SUCCESS] All telemetry scheduled tasks re-enabled.' -ForegroundColor Green"
reg delete "HKCU\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications" /v GlobalUserDisabled /f >nul 2>&1
reg delete "HKLM\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy" /v LetAppsRunInBackground /f >nul 2>&1
powershell -NoProfile -Command "Write-Host '  [SUCCESS] UWP Background Apps restored to default.' -ForegroundColor Green"
sc config "SysMain" start= auto >nul 2>&1
sc start "SysMain" >nul 2>&1
powershell -NoProfile -Command "Write-Host '  [SUCCESS] SysMain / Superfetch re-enabled.' -ForegroundColor Green"
echo.
exit /b 0

:CREATE_RESTORE_POINT
echo.
color !COL_OPS!
echo  Creating System Restore Point...
set "RPSCRIPT=%TEMP%\ytsh_create_rp_%RANDOM%%RANDOM%.ps1"
(
    echo Enable-ComputerRestore -Drive 'C:\' -ErrorAction SilentlyContinue
    echo try {
    echo     Checkpoint-Computer -Description 'Before YTSH Debloat Utility v1.0' -RestorePointType 'MODIFY_SETTINGS' -ErrorAction Stop
    echo     Write-Host '  [SUCCESS] Restore point created successfully.' -ForegroundColor Green
    echo } catch {
    echo     Write-Host ^('  [WARN] Restore point failed: ' + $_.Exception.Message^) -ForegroundColor Red
    echo     exit 1
    echo }
) > "%RPSCRIPT%"
powershell -NoProfile -ExecutionPolicy Bypass -File "%RPSCRIPT%"
set "RPERR=!errorLevel!"
del "%RPSCRIPT%" >nul 2>&1
exit /b !RPERR!

:CREATE_RESTORE_POINT_SILENT
set "RPSCRIPT=%TEMP%\ytsh_create_rp_s_%RANDOM%%RANDOM%.ps1"
(
    echo Enable-ComputerRestore -Drive 'C:\' -ErrorAction SilentlyContinue
    echo try { Checkpoint-Computer -Description 'Before YTSH Debloat v1.0 Single Op' -RestorePointType 'MODIFY_SETTINGS' -ErrorAction Stop } catch {}
) > "%RPSCRIPT%"
powershell -NoProfile -ExecutionPolicy Bypass -File "%RPSCRIPT%" >nul 2>&1
del "%RPSCRIPT%" >nul 2>&1
exit /b 0

:RESTORE_POINT_FAILED_FULL
cls
color !COL_OPS!
echo.
echo  =============================================
powershell -NoProfile -Command "Write-Host '   [WARN] Restore Point Could Not Be Created' -ForegroundColor Red"
echo  =============================================
echo.
echo   Windows limits restore point frequency.
echo   One may have been created in the last 24hrs.
echo   Check: Control Panel > Recovery > System Restore
echo.
echo  =============================================
echo.
set "RISKY="
set /p "RISKY=  Continue WITHOUT a restore point? Type YES: "
if /i not "!RISKY!"=="YES" (
    echo.
    powershell -NoProfile -Command "Write-Host '  Aborting. No changes were made.' -ForegroundColor Red"
    pause
    goto MAIN_MENU
)
call :DO_REMOVE_ALL_APPS
call :DO_DISABLE_ALL_SERVICES
call :DO_DISABLE_ALL_TELEMETRY
echo.
echo  =============================================
powershell -NoProfile -Command "Write-Host '   Full Debloat Complete.' -ForegroundColor Green"
echo  =============================================
echo.
call :COUNTDOWN_RESTART
goto MAIN_MENU

:COUNTDOWN_RESTART
echo.
color !COL_OPS!
echo  =============================================
if "!AUTORESTART!"=="0" (
    powershell -NoProfile -Command "Write-Host '   Auto-Restart is OFF. Please restart manually when ready.' -ForegroundColor DarkGray"
    echo  =============================================
    echo.
    pause
    exit /b 0
)
powershell -NoProfile -Command "Write-Host '   Your PC will restart in 15 seconds.' -ForegroundColor Yellow"
echo   Press CTRL+C to cancel the restart.
echo  =============================================
echo.
for /l %%i in (15,-1,1) do (
    set /p "=  Restarting in %%i seconds...   " <nul
    echo.
    timeout /t 1 /nobreak >nul
)
shutdown /r /t 5 /c "YTSH Debloat Utility v1.0: Applying changes."
exit /b 0

:SETTINGS_MENU
cls
color !COL_OPS!
echo.
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '    SETTINGS' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
echo.
set "DISP_AR=ON"
if "!AUTORESTART!"=="0" set "DISP_AR=OFF"
set "DISP_OEM=INCLUDED"
if "!SKIP_OEM!"=="1" set "DISP_OEM=SKIPPED"
set "DISP_SM=ON"
if "!SAFE_MODE!"=="0" set "DISP_SM=OFF"
echo   [1]  Registry Points Location
echo        !REGPOINTS_DIR!
echo.
echo   [2]  Log Files Location
echo        !LOGDIR!
echo.
echo   [3]  Auto-Restart after Full Debloat    :  !DISP_AR!
echo   [4]  Skip OEM Stubs in Full Debloat     :  !DISP_OEM!
echo.
echo   [5]  Color Theme  :  !COLOR_THEME!
echo        DEFAULT ^| MATRIX ^| AMBER ^| OCEAN ^| BLOOD ^| VIOLET ^| ARCTIC ^| GOLD ^| MIDNIGHT
echo.
echo   [6]  Reset Debloat Mode to Default (Unlocks 'M' Menu)
echo.
echo   [7]  Safe Mode                          :  !DISP_SM!
echo.
echo   B  ^>  Back to main menu
echo.
echo  =============================================
echo.
set "SCHOICE="
set /p "SCHOICE=  Select an option [1-7, B]: "

if /i "!SCHOICE!"=="B" goto MAIN_MENU
if "!SCHOICE!"=="1" goto SETTINGS_REGPOINTS
if "!SCHOICE!"=="2" goto SETTINGS_LOGDIR
if "!SCHOICE!"=="3" goto SETTINGS_AUTORESTART
if "!SCHOICE!"=="4" goto SETTINGS_SKIPOEM
if "!SCHOICE!"=="5" goto SETTINGS_THEME
if "!SCHOICE!"=="6" goto SETTINGS_RESETMODE
if "!SCHOICE!"=="7" goto SETTINGS_SAFEMODE

color !COL_ERR!
echo.
echo  [!] Invalid choice.
echo.
pause
goto SETTINGS_MENU

:SETTINGS_SAFEMODE
cls
color !COL_OPS!
echo.
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '    SAFE MODE' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
echo.
if "!SAFE_MODE!"=="1" goto :SM_IS_ON

:: --- Safe Mode is OFF ---
powershell -NoProfile -Command "Write-Host '  Safe Mode is currently: OFF' -ForegroundColor Red"
echo.
echo   Safe Mode is disabled. All menus are fully accessible:
echo   Gaming/FPS Boost, Network Optimizations, Windows Tweaks,
echo   individual service disabling, and AGGRESSIVE debloat options.
echo.
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
echo.
echo   1  ^>  Re-enable Safe Mode
echo   B  ^>  Back
echo.
set "SMCHOICE="
set /p "SMCHOICE=  Select: "
if "!SMCHOICE!"=="1" (
    set "SAFE_MODE=1"
    call :SAVE_CONFIG
    reg delete "HKLM\System\CurrentControlSet\Control\Power\PowerThrottling" /v PowerThrottlingOff /f >nul 2>&1
    reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" /v NetworkThrottlingIndex /t REG_DWORD /d 10 /f >nul 2>&1
    reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" /v SystemResponsiveness /t REG_DWORD /d 20 /f >nul 2>&1
    reg add "HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" /v HwSchMode /t REG_DWORD /d 1 /f >nul 2>&1
    powershell -NoProfile -Command "Write-Host '  [SUCCESS] Safe Mode is now ON. Aggressive settings reverted.' -ForegroundColor Green"
    echo.
    pause
)
goto SETTINGS_MENU

:SM_IS_ON
:: --- Safe Mode is ON ---
powershell -NoProfile -Command "Write-Host '  Safe Mode is currently: ON' -ForegroundColor Green"
echo.
echo   Safe Mode protects you by:
echo    - Locking the Gaming and FPS Boost menu entirely.
echo    - Locking the Network Optimizations menu (HKLM writes).
echo    - Locking the Windows Tweaks menu (system-level changes).
echo    - Blocking individual service disabling from the Debloat menu.
echo    - Hiding and blocking AGGRESSIVE-tier debloat options.
echo    - Using safe-only paths when Apply All is run.
echo    - Skipping SysMain disable if a traditional HDD is detected.
echo    - Reverting aggressive settings (power throttling, network) on re-enable.
echo.
powershell -NoProfile -Command "Write-Host '  It is strongly recommended to keep Safe Mode ON.' -ForegroundColor Yellow"
echo.
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
echo.
echo   To disable Safe Mode, type YES below and press ENTER.
echo   To go back, leave blank and press ENTER.
echo.
set "SMCHOICE="
set /p "SMCHOICE=  Type YES to disable Safe Mode: "
if /i "!SMCHOICE!"=="YES" (
    set "SAFE_MODE=0"
    call :SAVE_CONFIG
    powershell -NoProfile -Command "Write-Host '  [DONE] Safe Mode is now OFF. AGGRESSIVE options are accessible.' -ForegroundColor Red"
    echo.
    pause
)
goto SETTINGS_MENU

:SETTINGS_REGPOINTS
cls
color !COL_OPS!
echo.
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '    Registry Points Location' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
echo.
echo   Current: !REGPOINTS_DIR!
echo.
echo   1  ^>  Script Folder  (next to the .bat file)
echo   2  ^>  Desktop
echo   3  ^>  Documents
echo   B  ^>  Back
echo.
echo  =============================================
echo.
set "SCHOICE="
set /p "SCHOICE=  Select: "
if /i "!SCHOICE!"=="B" goto SETTINGS_MENU
if "!SCHOICE!"=="1" (
    set "REGPOINTS_DIR=%~dp0YTSH REGISTRY POINTS"
    call :SAVE_CONFIG
    powershell -NoProfile -Command "Write-Host '  [SUCCESS] Registry Points location set to Script Folder.' -ForegroundColor Green"
    echo.
    pause
    goto SETTINGS_MENU
)
if "!SCHOICE!"=="2" (
    set "REGPOINTS_DIR=%USERPROFILE%\Desktop\YTSH REGISTRY POINTS"
    call :SAVE_CONFIG
    powershell -NoProfile -Command "Write-Host '  [SUCCESS] Registry Points location set to Desktop.' -ForegroundColor Green"
    echo.
    pause
    goto SETTINGS_MENU
)
if "!SCHOICE!"=="3" (
    for /f "tokens=*" %%D in ('powershell -NoProfile -Command "[Environment]::GetFolderPath(\"MyDocuments\")"') do set "DOCS_PATH=%%D"
    set "REGPOINTS_DIR=!DOCS_PATH!\YTSH REGISTRY POINTS"
    call :SAVE_CONFIG
    powershell -NoProfile -Command "Write-Host '  [SUCCESS] Registry Points location set to Documents.' -ForegroundColor Green"
    echo.
    pause
    goto SETTINGS_MENU
)
color !COL_ERR!
echo.
echo  [!] Invalid choice.
echo.
pause
goto SETTINGS_REGPOINTS

:SETTINGS_LOGDIR
cls
color !COL_OPS!
echo.
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '    Log Files Location' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
echo.
echo   Current: !LOGDIR!
echo.
echo   1  ^>  Next to script file
echo   2  ^>  Same as Registry Points folder
echo   B  ^>  Back
echo.
echo  =============================================
echo.
set "SCHOICE="
set /p "SCHOICE=  Select: "
if /i "!SCHOICE!"=="B" goto SETTINGS_MENU
if "!SCHOICE!"=="1" (
    set "_SDIR=%SCRIPTDIR:~0,-1%"
    set "LOGDIR=!_SDIR!"
    set "LOGFILE=!LOGDIR!\removed_apps.txt"
    set "SVCLOG=!LOGDIR!\disabled_services.txt"
    set "REGLOG=!LOGDIR!\registry_changes.txt"
    set "ERRLOG=!LOGDIR!\error_log.txt"
    call :SAVE_CONFIG
    powershell -NoProfile -Command "Write-Host '  [SUCCESS] Logs will be saved next to the script.' -ForegroundColor Green"
    echo.
    pause
    goto SETTINGS_MENU
)
if "!SCHOICE!"=="2" (
    set "LOGDIR=!REGPOINTS_DIR!"
    set "LOGFILE=!LOGDIR!\removed_apps.txt"
    set "SVCLOG=!LOGDIR!\disabled_services.txt"
    set "REGLOG=!LOGDIR!\registry_changes.txt"
    set "ERRLOG=!LOGDIR!\error_log.txt"
    if not exist "!LOGDIR!" mkdir "!LOGDIR!" >nul 2>&1
    call :SAVE_CONFIG
    powershell -NoProfile -Command "Write-Host '  [SUCCESS] Logs will be saved in the Registry Points folder.' -ForegroundColor Green"
    echo.
    pause
    goto SETTINGS_MENU
)
color !COL_ERR!
echo.
echo  [!] Invalid choice.
echo.
pause
goto SETTINGS_LOGDIR

:SETTINGS_AUTORESTART
if "!AUTORESTART!"=="1" (
    set "AUTORESTART=0"
    call :SAVE_CONFIG
    powershell -NoProfile -Command "Write-Host '  [SUCCESS] Auto-Restart is now OFF.' -ForegroundColor Green"
) else (
    set "AUTORESTART=1"
    call :SAVE_CONFIG
    powershell -NoProfile -Command "Write-Host '  [SUCCESS] Auto-Restart is now ON.' -ForegroundColor Green"
)
echo.
pause
goto SETTINGS_MENU

:SETTINGS_SKIPOEM
if "!SKIP_OEM!"=="1" (
    set "SKIP_OEM=0"
    call :SAVE_CONFIG
    powershell -NoProfile -Command "Write-Host '  [SUCCESS] OEM Stubs will be INCLUDED in Full Debloat.' -ForegroundColor Green"
) else (
    set "SKIP_OEM=1"
    call :SAVE_CONFIG
    powershell -NoProfile -Command "Write-Host '  [SUCCESS] OEM Stubs will be SKIPPED in Full Debloat.' -ForegroundColor Green"
)
echo.
pause
goto SETTINGS_MENU

:SETTINGS_THEME
cls
color !COL_OPS!
echo.
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '    Color Theme' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
echo.
echo   Current: !COLOR_THEME!
echo.
echo   1  ^>  DEFAULT  ^|  Cyan headers    White operations
echo   2  ^>  MATRIX   ^|  Green throughout
echo   3  ^>  AMBER    ^|  Yellow throughout
echo   4  ^>  OCEAN    ^|  Magenta headers  Cyan operations
echo   5  ^>  BLOOD    ^|  Red headers      Yellow operations
echo   6  ^>  VIOLET   ^|  Purple throughout
echo   7  ^>  ARCTIC   ^|  White headers    Cyan operations
echo   8  ^>  GOLD     ^|  Dark gold headers Yellow operations
echo   9  ^>  MIDNIGHT ^|  Blue throughout
echo.
echo   B  ^>  Back
echo.
echo  =============================================
echo.
set "SCHOICE="
set /p "SCHOICE=  Select: "
if /i "!SCHOICE!"=="B" goto SETTINGS_MENU
if "!SCHOICE!"=="1" set "COLOR_THEME=DEFAULT"
if "!SCHOICE!"=="2" set "COLOR_THEME=MATRIX"
if "!SCHOICE!"=="3" set "COLOR_THEME=AMBER"
if "!SCHOICE!"=="4" set "COLOR_THEME=OCEAN"
if "!SCHOICE!"=="5" set "COLOR_THEME=BLOOD"
if "!SCHOICE!"=="6" set "COLOR_THEME=VIOLET"
if "!SCHOICE!"=="7" set "COLOR_THEME=ARCTIC"
if "!SCHOICE!"=="8" set "COLOR_THEME=GOLD"
if "!SCHOICE!"=="9" set "COLOR_THEME=MIDNIGHT"
if "!SCHOICE!"=="1" goto SETTINGS_THEME_APPLY
if "!SCHOICE!"=="2" goto SETTINGS_THEME_APPLY
if "!SCHOICE!"=="3" goto SETTINGS_THEME_APPLY
if "!SCHOICE!"=="4" goto SETTINGS_THEME_APPLY
if "!SCHOICE!"=="5" goto SETTINGS_THEME_APPLY
if "!SCHOICE!"=="6" goto SETTINGS_THEME_APPLY
if "!SCHOICE!"=="7" goto SETTINGS_THEME_APPLY
if "!SCHOICE!"=="8" goto SETTINGS_THEME_APPLY
if "!SCHOICE!"=="9" goto SETTINGS_THEME_APPLY
color !COL_ERR!
echo.
echo  [!] Invalid choice.
echo.
pause
goto SETTINGS_THEME

:SETTINGS_THEME_APPLY
call :APPLY_COLOR_THEME
call :SAVE_CONFIG
color !COL_OPS!
powershell -NoProfile -Command "Write-Host '  [SUCCESS] Theme applied. All menus will update immediately.' -ForegroundColor Green"
echo.
pause
goto SETTINGS_MENU

:APPLY_COLOR_THEME
set "COL_HDR=0B"
set "COL_OPS=0F"
set "COL_ERR=0C"
set "COL_HDR_PS=Cyan"
set "COL_OPS_PS=White"

if "!COLOR_THEME!"=="MATRIX" (
    set "COL_HDR=0A"
    set "COL_OPS=0A"
    set "COL_ERR=0C"
    set "COL_HDR_PS=White"
    set "COL_OPS_PS=Green"
)
if "!COLOR_THEME!"=="AMBER" (
    set "COL_HDR=0E"
    set "COL_OPS=0E"
    set "COL_ERR=0C"
    set "COL_HDR_PS=Yellow"
    set "COL_OPS_PS=White"
)
if "!COLOR_THEME!"=="OCEAN" (
    set "COL_HDR=0B"
    set "COL_OPS=0B"
    set "COL_ERR=0C"
    set "COL_HDR_PS=Magenta"
    set "COL_OPS_PS=Cyan"
)
if "!COLOR_THEME!"=="BLOOD" (
    set "COL_HDR=0C"
    set "COL_OPS=0C"
    set "COL_ERR=0E"
    set "COL_HDR_PS=Red"
    set "COL_OPS_PS=Yellow"
)
if "!COLOR_THEME!"=="VIOLET" (
    set "COL_HDR=0D"
    set "COL_OPS=0D"
    set "COL_ERR=0C"
    set "COL_HDR_PS=Magenta"
    set "COL_OPS_PS=White"
)
if "!COLOR_THEME!"=="ARCTIC" (
    set "COL_HDR=0F"
    set "COL_OPS=0B"
    set "COL_ERR=0C"
    set "COL_HDR_PS=White"
    set "COL_OPS_PS=Cyan"
)
if "!COLOR_THEME!"=="GOLD" (
    set "COL_HDR=06"
    set "COL_OPS=0E"
    set "COL_ERR=0C"
    set "COL_HDR_PS=DarkYellow"
    set "COL_OPS_PS=Yellow"
)
if "!COLOR_THEME!"=="MIDNIGHT" (
    set "COL_HDR=09"
    set "COL_OPS=09"
    set "COL_ERR=0C"
    set "COL_HDR_PS=Blue"
    set "COL_OPS_PS=Cyan"
)
exit /b 0

:SETTINGS_RESETMODE
set "DEBLOAT_MODE=DEFAULT"
call :SAVE_CONFIG
powershell -NoProfile -Command "Write-Host '  [SUCCESS] Debloat Mode reset to DEFAULT. The Mode menu is unlocked.' -ForegroundColor Green"
echo.
pause
goto SETTINGS_MENU

:SAVE_CONFIG
(
    echo REGPOINTS_DIR=!REGPOINTS_DIR!
    echo LOGDIR=!LOGDIR!
    echo AUTORESTART=!AUTORESTART!
    echo SKIP_OEM=!SKIP_OEM!
    echo COLOR_THEME=!COLOR_THEME!
    echo HIDE_WELCOME=!HIDE_WELCOME!
    echo SAFE_MODE=!SAFE_MODE!
    echo DEBLOAT_MODE=!DEBLOAT_MODE!
)>"%YTSH_CONFIG%"
exit /b 0

:SHOW_SMART_DETAILS
set "SMARTSCRIPT=%TEMP%\ytsh_smart_%RANDOM%%RANDOM%.ps1"
(
    echo Write-Host ""
    echo Write-Host "  === DISK SMART HEALTH DETAILS ===" -ForegroundColor Cyan
    echo Write-Host ""
    echo try {
    echo     $disks = Get-PhysicalDisk -ErrorAction Stop
    echo     foreach ^($d in $disks^) {
    echo         $col = if ^($d.HealthStatus -eq 'Healthy'^) { 'Green' } elseif ^($d.HealthStatus -eq 'Warning'^) { 'Yellow' } else { 'Red' }
    echo         Write-Host ^("  [" + $d.DeviceId + "] " + $d.FriendlyName.PadRight^(35^) + "  Health: " + $d.HealthStatus + "  (" + $d.MediaType + ", " + [math]::Round^($d.Size/1GB,0^) + " GB)"^) -ForegroundColor $col
    echo         $rel = Get-StorageReliabilityCounter -PhysicalDisk $d -ErrorAction SilentlyContinue
    echo         if ^($rel^) {
    echo             if ^($rel.ReadErrorsTotal  -gt 0^) { Write-Host ^("    Read Errors:  " + $rel.ReadErrorsTotal^)  -ForegroundColor Yellow }
    echo             if ^($rel.WriteErrorsTotal -gt 0^) { Write-Host ^("    Write Errors: " + $rel.WriteErrorsTotal^) -ForegroundColor Yellow }
    echo             if ^($rel.Temperature      -gt 0^) { $tc = if^($rel.Temperature -gt 55^){'Red'}elseif^($rel.Temperature -gt 45^){'Yellow'}else{'Green'}; Write-Host ^("    Temperature:  " + $rel.Temperature + " C"^) -ForegroundColor $tc }
    echo             if ^($rel.Wear             -gt 0^) { Write-Host ^("    Wear Level:   " + $rel.Wear + "%%"^) -ForegroundColor DarkGray }
    echo         }
    echo     }
    echo } catch {
    echo     $wmiDisks = Get-WmiObject -Class MSStorageDriver_FailurePredictStatus -Namespace root\wmi -ErrorAction SilentlyContinue
    echo     if ^($wmiDisks^) {
    echo         foreach ^($d in $wmiDisks^) {
    echo             $col = if ^($d.PredictFailure^) { 'Red' } else { 'Green' }
    echo             Write-Host ^("  " + $d.InstanceName + ": " + $^(if^($d.PredictFailure^){'FAILURE PREDICTED'}else{'Healthy'}^)^) -ForegroundColor $col
    echo         }
    echo     } else { Write-Host "  SMART data not accessible on this system." -ForegroundColor DarkGray }
    echo }
    echo Write-Host ""
) > "%SMARTSCRIPT%"
powershell -NoProfile -ExecutionPolicy Bypass -File "%SMARTSCRIPT%"
del "%SMARTSCRIPT%" >nul 2>&1
exit /b 0

:TWEAKS_MENU
cls
color !COL_OPS!
echo.
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '    WINDOWS TWEAKS' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
echo.
echo   1  ^>  Visual Effects Optimizer (Disable animations/shadows for speed)
echo   2  ^>  Virtual Memory / Pagefile (Auto-set based on RAM)
echo   3  ^>  Windows Update Control (Pause/Metered/Defer)
echo   4  ^>  Power Plan Manager (Switch Balanced/High Performance/Saver)
echo   5  ^>  DNS Benchmark ^& Optimizer (Find the fastest DNS)
echo.
echo   B  ^>  Back to main menu
echo.
set "TWCHOICE="
set /p "TWCHOICE=  Select: "

if /i "!TWCHOICE!"=="B" goto MAIN_MENU
if "!TWCHOICE!"=="1" goto TW_OPT_1
if "!TWCHOICE!"=="2" goto TW_OPT_2
if "!TWCHOICE!"=="3" goto TW_OPT_3
if "!TWCHOICE!"=="4" goto TW_OPT_4
if "!TWCHOICE!"=="5" goto TW_OPT_5
goto TWEAKS_MENU
:TW_OPT_1
call :TWEAK_VISUALS & goto TWEAKS_MENU
:TW_OPT_2
call :TWEAK_PAGEFILE & goto TWEAKS_MENU
:TW_OPT_3
call :TWEAK_WU_CONTROL & goto TWEAKS_MENU
:TW_OPT_4
call :TWEAK_POWER_PLANS & goto TWEAKS_MENU
:TW_OPT_5
call :TWEAK_DNS_BENCH & goto TWEAKS_MENU
goto TWEAKS_MENU

:TWEAK_VISUALS
echo.
powershell -NoProfile -Command "Write-Host '  Optimizing Visual Effects for Performance...' -ForegroundColor Cyan"
:: Set "Adjust for best performance"
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects" /v VisualFXSetting /t REG_DWORD /d 2 /f >nul 2>&1
:: Individual registry flags for animations and shadows
reg add "HKCU\Control Panel\Desktop" /v UserPreferencesMask /t REG_BINARY /d 9012038010000000 /f >nul 2>&1
reg add "HKCU\Control Panel\Desktop\WindowMetrics" /v MinAnimate /t REG_SZ /d 0 /f >nul 2>&1
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v ListviewAlphaSelect /t REG_DWORD /d 0 /f >nul 2>&1
powershell -NoProfile -Command "Write-Host '  [SUCCESS] Animations and shadows disabled.' -ForegroundColor Green"
pause
exit /b 0

:TWEAK_PAGEFILE
echo.
powershell -NoProfile -Command "Write-Host '  Setting Pagefile size based on !SYS_RAM!...' -ForegroundColor Cyan"
set "RAM_VAL=!SYS_RAM: GB=!"
if !RAM_VAL! LSS 8 (
    set /a PF_SIZE=!RAM_VAL! * 1024 * 15 / 10
) else (
    set "PF_SIZE=4096"
)
powershell -NoProfile -ExecutionPolicy Bypass -Command "$cs=Get-WmiObject Win32_ComputerSystem; $cs.AutomaticManagedPagefile=$false; $cs.Put()|Out-Null; $pf=Get-WmiObject -Query 'Select * From Win32_PageFileSetting' -ErrorAction SilentlyContinue; if(-not $pf){Set-WmiInstance -Class Win32_PageFileSetting -Arguments @{Name='C:\pagefile.sys';InitialSize=%PF_SIZE%;MaximumSize=%PF_SIZE%}|Out-Null}else{$pf.InitialSize=%PF_SIZE%;$pf.MaximumSize=%PF_SIZE%;$pf.Put()|Out-Null}"
powershell -NoProfile -Command "Write-Host '  [SUCCESS] Pagefile set to %PF_SIZE% MB.' -ForegroundColor Green"
pause
exit /b 0

:TWEAK_WU_CONTROL
cls
echo.
echo   Windows Update Control:
echo   1 ^> Pause Updates for 5 weeks
echo   2 ^> Set connection to Metered (Stops auto-downloads)
echo   3 ^> Restore default settings
echo.
set /p "WUC=Select: "
if "!WUC!"=="1" (
    reg add "HKLM\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings" /v PauseUpdatesExpiryTime /t REG_SZ /d "2040-01-01T12:00:00Z" /f >nul 2>&1
    powershell -NoProfile -Command "Write-Host '  [SUCCESS] Updates paused until 2040.' -ForegroundColor Green"
    pause & exit /b 0
)
if "!WUC!"=="2" (
    powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-NetAdapter | Where-Object {$_.Status -eq 'Up'} | ForEach-Object { try { Set-NetConnectionProfile -InterfaceAlias $_.Name -NetworkCategory Public -ErrorAction SilentlyContinue; Write-Host ('  [SUCCESS] Metered: ' + $_.Name) -ForegroundColor Green } catch { Write-Host ('  [WARN] Could not set: ' + $_.Name) -ForegroundColor Yellow } }"
    pause & exit /b 0
)
if "!WUC!"=="3" (
    reg delete "HKLM\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings" /v PauseUpdatesExpiryTime /f >nul 2>&1
    powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-NetAdapter | Where-Object {$_.Status -eq 'Up'} | ForEach-Object { Set-NetConnectionProfile -InterfaceAlias $_.Name -NetworkCategory Private -ErrorAction SilentlyContinue }"
    powershell -NoProfile -Command "Write-Host '  [SUCCESS] Update settings restored to defaults.' -ForegroundColor Green"
    pause & exit /b 0
)
powershell -NoProfile -Command "Write-Host '  [!] Invalid choice.' -ForegroundColor Red"
pause
exit /b 0

:TWEAK_POWER_PLANS
cls
echo.
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '    POWER PLAN MANAGER' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
echo.
echo   1  ^>  Balanced (Default)
echo   2  ^>  High Performance
echo   3  ^>  Power Saver
echo   B  ^>  Back
echo.
set "PPCHOICE="
set /p "PPCHOICE=  Select: "
if /i "!PPCHOICE!"=="B" exit /b 0
if "!PPCHOICE!"=="1" (
    powercfg -s 381b4222-f694-41f0-9685-ff5bb260df2e >nul 2>&1
    powershell -NoProfile -Command "Write-Host '  [SUCCESS] Balanced power plan active.' -ForegroundColor Green"
    pause & exit /b 0
)
if "!PPCHOICE!"=="2" (
    if "!SYS_FORM!"=="LAPTOP" powershell -NoProfile -Command "Write-Host '  [WARN] High Performance on a laptop may cause overheating/battery drain.' -ForegroundColor Yellow"
    powercfg -s 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c >nul 2>&1
    if !errorLevel! equ 0 (
        powershell -NoProfile -Command "Write-Host '  [SUCCESS] High Performance plan active.' -ForegroundColor Green"
    ) else (
        powershell -NoProfile -Command "Write-Host '  [FAIL] Could not apply High Performance plan.' -ForegroundColor Red"
    )
    pause & exit /b 0
)
if "!PPCHOICE!"=="3" (
    powercfg -s a1841308-3541-4fab-bc81-f71556f20b4a >nul 2>&1
    powershell -NoProfile -Command "Write-Host '  [SUCCESS] Power Saver plan active.' -ForegroundColor Green"
    pause & exit /b 0
)
powershell -NoProfile -Command "Write-Host '  [!] Invalid choice.' -ForegroundColor Red"
pause
exit /b 0

:TWEAK_DNS_BENCH
cls
echo.
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '    DNS BENCHMARK ^& CHANGER' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
echo.
echo   Select a DNS provider to apply system-wide:
echo.
echo   1  ^>  Google        (8.8.8.8 / 8.8.4.4)
echo   2  ^>  Cloudflare    (1.1.1.1 / 1.0.0.1)
echo   3  ^>  Quad9         (9.9.9.9 / 149.112.112.112)
echo   4  ^>  OpenDNS       (208.67.222.222 / 208.67.220.220)
echo   5  ^>  Restore automatic (DHCP)
echo   B  ^>  Back
echo.
set "DNSCHOICE="
set /p "DNSCHOICE=  Select: "
if /i "!DNSCHOICE!"=="B" exit /b 0
if "!DNSCHOICE!"=="1" set "DNS1=8.8.8.8"       & set "DNS2=8.8.4.4"
if "!DNSCHOICE!"=="2" set "DNS1=1.1.1.1"       & set "DNS2=1.0.0.1"
if "!DNSCHOICE!"=="3" set "DNS1=9.9.9.9"       & set "DNS2=149.112.112.112"
if "!DNSCHOICE!"=="4" set "DNS1=208.67.222.222" & set "DNS2=208.67.220.220"
if "!DNSCHOICE!"=="5" (
    powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-NetAdapter | Where-Object {$_.Status -eq 'Up'} | ForEach-Object { Set-DnsClientServerAddress -InterfaceAlias $_.Name -ResetServerAddresses; Write-Host ('  [OK] ' + $_.Name + ' reset to DHCP DNS') -ForegroundColor Green }"
    pause & exit /b 0
)
if not defined DNS1 (
    powershell -NoProfile -Command "Write-Host '  [!] Invalid choice.' -ForegroundColor Red"
    pause & exit /b 0
)
powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-NetAdapter | Where-Object {$_.Status -eq 'Up'} | ForEach-Object { Set-DnsClientServerAddress -InterfaceAlias $_.Name -ServerAddresses ('!DNS1!','!DNS2!'); Write-Host ('  [SUCCESS] ' + $_.Name + ' -> !DNS1! / !DNS2!') -ForegroundColor Green }"
pause
exit /b 0

:DO_TWEAK_PAGEFILE
cls
color !COL_OPS!
echo.
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '    VIRTUAL MEMORY / PAGEFILE' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
echo.
powershell -NoProfile -Command "$r=[math]::Round((Get-CimInstance Win32_OperatingSystem).TotalVisibleMemorySize/1MB,0); Write-Host ('  Installed RAM: ' + $r + ' GB') -ForegroundColor Cyan"
echo.
echo   1  ^>  System managed (Recommended)
echo   2  ^>  Custom: 1.5x RAM initial, 3x RAM max
echo   3  ^>  Disable pagefile (Only if 16+ GB RAM)
echo   B  ^>  Back
echo.
set "PGCHOICE="
set /p "PGCHOICE=  Select: "
if /i "!PGCHOICE!"=="B" exit /b 0
if "!PGCHOICE!"=="1" (
    powershell -NoProfile -ExecutionPolicy Bypass -Command "$cs=Get-WmiObject Win32_ComputerSystem; $cs.AutomaticManagedPagefile=$true; $cs.Put()|Out-Null; Write-Host '  [SUCCESS] Pagefile set to system managed.' -ForegroundColor Green"
    exit /b 0
)
if "!PGCHOICE!"=="2" (
    powershell -NoProfile -ExecutionPolicy Bypass -Command "$mb=[math]::Round((Get-CimInstance Win32_OperatingSystem).TotalVisibleMemorySize/1024,0); $init=[math]::Round($mb*1.5,0); $max=[math]::Round($mb*3,0); $cs=Get-WmiObject Win32_ComputerSystem; $cs.AutomaticManagedPagefile=$false; $cs.Put()|Out-Null; $pf=Get-WmiObject -Query 'Select * From Win32_PageFileSetting' -ErrorAction SilentlyContinue; if(-not $pf){Set-WmiInstance -Class Win32_PageFileSetting -Arguments @{Name='C:\pagefile.sys';InitialSize=$init;MaximumSize=$max}|Out-Null}else{$pf.InitialSize=$init;$pf.MaximumSize=$max;$pf.Put()|Out-Null}; Write-Host ('  [SUCCESS] Pagefile: initial='+$init+' MB, max='+$max+' MB. Restart required.') -ForegroundColor Green"
    exit /b 0
)
if "!PGCHOICE!"=="3" (
    powershell -NoProfile -Command "Write-Host '  [WARN] Disabling pagefile can cause crashes if RAM fills up.' -ForegroundColor Yellow"
    set "PGCONF="
    set /p "PGCONF=  Type CONFIRM to proceed: "
    if /i "!PGCONF!"=="CONFIRM" (
        powershell -NoProfile -ExecutionPolicy Bypass -Command "$cs=Get-WmiObject Win32_ComputerSystem; $cs.AutomaticManagedPagefile=$false; $cs.Put()|Out-Null; $pf=Get-WmiObject -Query 'Select * From Win32_PageFileSetting' -ErrorAction SilentlyContinue; if($pf){$pf.Delete()}; Write-Host '  [SUCCESS] Pagefile disabled. Restart required.' -ForegroundColor Green"
    ) else (
        powershell -NoProfile -Command "Write-Host '  [SKIP] Cancelled.' -ForegroundColor DarkGray"
    )
    exit /b 0
)
powershell -NoProfile -Command "Write-Host '  [!] Invalid choice.' -ForegroundColor Red"
exit /b 0

:DO_TWEAK_WUPDATE
cls
color !COL_OPS!
echo.
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '    WINDOWS UPDATE SETTINGS' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
echo.
echo   1  ^>  Pause updates for 7 days
echo   2  ^>  Defer feature updates by 365 days
echo   3  ^>  Mark active network as Metered (blocks auto-downloads)
echo   4  ^>  Re-enable automatic updates (reset all)
echo   B  ^>  Back
echo.
set "WUCHOICE="
set /p "WUCHOICE=  Select: "
if /i "!WUCHOICE!"=="B" exit /b 0
if "!WUCHOICE!"=="1" (
    powershell -NoProfile -ExecutionPolicy Bypass -Command "$r='HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings'; if(-not(Test-Path $r)){New-Item $r -Force|Out-Null}; $end=(Get-Date).AddDays(7).ToString('yyyy-MM-ddTHH:mm:ssZ'); $now=(Get-Date).ToString('yyyy-MM-ddTHH:mm:ssZ'); Set-ItemProperty $r PauseFeatureUpdatesStartTime $now -Force; Set-ItemProperty $r PauseFeatureUpdatesEndTime $end -Force; Set-ItemProperty $r PauseQualityUpdatesStartTime $now -Force; Set-ItemProperty $r PauseQualityUpdatesEndTime $end -Force; Write-Host '  [SUCCESS] Updates paused for 7 days.' -ForegroundColor Green"
    exit /b 0
)
if "!WUCHOICE!"=="2" (
    reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" /v DeferFeatureUpdates /t REG_DWORD /d 1 /f >nul 2>&1
    reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" /v DeferFeatureUpdatesPeriodInDays /t REG_DWORD /d 365 /f >nul 2>&1
    powershell -NoProfile -Command "Write-Host '  [SUCCESS] Feature updates deferred by 365 days.' -ForegroundColor Green"
    exit /b 0
)
if "!WUCHOICE!"=="3" (
    powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-NetAdapter|Where-Object{$_.Status -eq 'Up'}|ForEach-Object{try{Set-NetConnectionProfile -InterfaceAlias $_.Name -NetworkCategory Public -ErrorAction SilentlyContinue; Write-Host ('  [SUCCESS] Metered: '+$_.Name) -ForegroundColor Green}catch{Write-Host ('  [WARN] '+$_.Name) -ForegroundColor Yellow}}"
    exit /b 0
)
if "!WUCHOICE!"=="4" (
    reg delete "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" /v DeferFeatureUpdates /f >nul 2>&1
    reg delete "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" /v DeferFeatureUpdatesPeriodInDays /f >nul 2>&1
    powershell -NoProfile -ExecutionPolicy Bypass -Command "$r='HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings'; 'PauseFeatureUpdatesEndTime','PauseQualityUpdatesEndTime'|ForEach-Object{Remove-ItemProperty $r -Name $_ -ErrorAction SilentlyContinue}; Write-Host '  [SUCCESS] Automatic updates restored.' -ForegroundColor Green"
    exit /b 0
)
powershell -NoProfile -Command "Write-Host '  [!] Invalid choice.' -ForegroundColor Red"
exit /b 0

:SECURITY_MENU
cls
color !COL_OPS!
echo.
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '    SECURITY TOOLS' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
echo.
echo   1  ^>  Firewall Status Check
echo   2  ^>  Check for Suspicious Startup Entries
echo   3  ^>  Disable SMB1 Protocol (legacy, security risk)
echo   4  ^>  Manage Startup Programs (Enable/Disable)
echo   5  ^>  Restore Point Manager (View existing points, launch System Restore)
echo   6  ^>  Driver Check (Scan for unsigned or outdated drivers)
echo.
echo   B  ^>  Back to main menu
echo.
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
echo.
set "SECCHOICE="
set /p "SECCHOICE=  Select an option: "
if /i "!SECCHOICE!"=="B" goto MAIN_MENU
if "!SECCHOICE!"=="1" goto SEC_OPT_1
if "!SECCHOICE!"=="2" goto SEC_OPT_2
if "!SECCHOICE!"=="3" goto SEC_OPT_3
if "!SECCHOICE!"=="4" goto SEC_OPT_4
if "!SECCHOICE!"=="5" goto SEC_OPT_5
if "!SECCHOICE!"=="6" goto SEC_OPT_6
goto SECURITY_MENU

:SEC_OPT_1
echo.
call :DO_SEC_FIREWALL
echo.
pause
goto SECURITY_MENU
:SEC_OPT_2
echo.
call :DO_SEC_STARTUP
echo.
pause
goto SECURITY_MENU
:SEC_OPT_3
echo.
call :DO_SEC_SMB1
echo.
pause
goto SECURITY_MENU
:SEC_OPT_4
echo.
call :MANAGE_STARTUP
goto SECURITY_MENU
:SEC_OPT_5
echo.
call :RESTORE_POINT_MANAGER
echo.
pause
goto SECURITY_MENU
:SEC_OPT_6
echo.
call :DRIVER_CHECK
echo.
pause
goto SECURITY_MENU

:MANAGE_STARTUP
cls
powershell -NoProfile -Command "Write-Host '  Current Startup Programs:' -ForegroundColor !COL_HDR_PS!"
echo.
powershell -NoProfile -Command "Get-CimInstance Win32_StartupCommand | Select-Object Name, Command, Location | Out-Host"
echo.
echo   To disable a program, use Task Manager (Ctrl+Shift+Esc) > Startup tab.
echo   This script provides a direct shortcut:
echo.
pause
taskmgr
exit /b 0

:DO_SEC_FIREWALL
set "FWSCRIPT=%TEMP%\ytsh_firewall_%RANDOM%%RANDOM%.ps1"
(
    echo $profiles = Get-NetFirewallProfile -ErrorAction SilentlyContinue
    echo Write-Host '  --- Windows Firewall Status ---' -ForegroundColor Cyan
    echo foreach ^($p in $profiles^) {
    echo     $col   = if ^($p.Enabled^) { 'Green' } else { 'Red' }
    echo     $state = if ^($p.Enabled^) { 'ENABLED' } else { 'DISABLED !!!' }
    echo     Write-Host ^("  " + $p.Name.PadRight^(12^) + ": " + $state^) -ForegroundColor $col
    echo }
    echo $anyOff = $profiles ^| Where-Object { -not $_.Enabled }
    echo if ^($anyOff^) { Write-Host '  [WARN] One or more firewall profiles are DISABLED.' -ForegroundColor Red }
    echo else            { Write-Host '  [OK] All firewall profiles are active.' -ForegroundColor Green }
) > "%FWSCRIPT%"
powershell -NoProfile -ExecutionPolicy Bypass -File "%FWSCRIPT%"
del "%FWSCRIPT%" >nul 2>&1
exit /b 0

:DO_SEC_STARTUP
set "SECSTARTSCRIPT=%TEMP%\ytsh_sec_startup_%RANDOM%%RANDOM%.ps1"
(
    echo $keywords = @^('temp','appdata\roaming','downloads','public','tmp','.vbs','.ps1','.cmd','.scr','.pif'^)
    echo $paths = @^('HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run','HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run','HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run'^)
    echo Write-Host '  --- Startup Entry Scan ---' -ForegroundColor Cyan
    echo Write-Host ''
    echo $flagged = 0
    echo foreach ^($path in $paths^) {
    echo     $entries = Get-ItemProperty -Path $path -ErrorAction SilentlyContinue
    echo     if ^($entries^) {
    echo         $entries.PSObject.Properties ^| Where-Object { $_.Name -notmatch '^PS' } ^| ForEach-Object {
    echo             $val = $_.Value.ToLower^(^)
    echo             $sus = $false
    echo             foreach ^($kw in $keywords^) { if ^($val -like "*$kw*"^) { $sus = $true; break } }
    echo             if ^($sus^) { Write-Host ^("  [SUSPICIOUS] " + $_.Name + " -> " + $_.Value^) -ForegroundColor Red; $flagged++ }
    echo             else        { Write-Host ^("  [OK]         " + $_.Name + " -> " + $_.Value^) -ForegroundColor Green }
    echo         }
    echo     }
    echo }
    echo if ^($flagged -eq 0^) { Write-Host '  No suspicious entries detected.' -ForegroundColor Green }
    echo else { Write-Host ^("  " + $flagged + " suspicious entry/entries found. Review manually."^) -ForegroundColor Yellow }
) > "%SECSTARTSCRIPT%"
powershell -NoProfile -ExecutionPolicy Bypass -File "%SECSTARTSCRIPT%"
del "%SECSTARTSCRIPT%" >nul 2>&1
exit /b 0

:DO_SEC_SMB1
powershell -NoProfile -ExecutionPolicy Bypass -Command "$f=Get-WindowsOptionalFeature -Online -FeatureName SMB1Protocol -ErrorAction SilentlyContinue; if(-not $f){Write-Host '  [INFO] SMB1Protocol not found (already removed).' -ForegroundColor DarkGray}elseif($f.State -eq 'Disabled'){Write-Host '  [OK] SMB1 is already DISABLED.' -ForegroundColor Green}else{Write-Host '  Disabling SMB1...' -ForegroundColor Yellow; Disable-WindowsOptionalFeature -Online -FeatureName SMB1Protocol -NoRestart -ErrorAction SilentlyContinue|Out-Null; Write-Host '  [SUCCESS] SMB1 disabled. Restart required.' -ForegroundColor Green}"
exit /b 0

:ACTIVATE_WINDOWS
cls
color !COL_OPS!
echo.
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '    ACTIVATE WINDOWS (HWID METHOD)' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
echo.
echo   Uses the HWID digital license method - the same method Windows uses when
echo   upgrading from a previously activated copy. Ties a license to your hardware.
echo   No product key needed. Tool: Microsoft Activation Scripts (massgrave.dev)
echo.
powershell -NoProfile -Command "Write-Host '  Current activation status:' -ForegroundColor Cyan"
cscript //NoLogo "%SystemRoot%\system32\slmgr.vbs" /xpr 2>nul
echo.
echo   P  ^>  Proceed with HWID Activation
echo   B  ^>  Back to main menu
echo.
set "ACHOICE="
set /p "ACHOICE=  Select: "
if /i "!ACHOICE!"=="B" goto MAIN_MENU
if /i "!ACHOICE!"=="P" (
    echo.
    powershell -NoProfile -Command "Write-Host '  Connecting to activation service...' -ForegroundColor Cyan"
    powershell -NoProfile -ExecutionPolicy Bypass -Command "irm https://get.activated.win | iex"
    echo.
    pause
    goto MAIN_MENU
)
color !COL_ERR!
echo.
echo  [!] Invalid choice.
echo.
pause
goto ACTIVATE_WINDOWS

:INSTALL_SOFTWARE
cls
color !COL_OPS!
echo.
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '    INSTALL SOFTWARE (via winget)' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
echo.
powershell -NoProfile -Command "Write-Host '  Checking for winget...' -ForegroundColor Cyan"
winget --version >nul 2>&1
if !errorLevel! neq 0 (
    powershell -NoProfile -Command "Write-Host '  [FAIL] winget not found. Install App Installer from the Microsoft Store first.' -ForegroundColor Red"
    echo.
    pause
    goto MAIN_MENU
)
powershell -NoProfile -Command "Write-Host '  [OK] winget detected.' -ForegroundColor Green"
echo.
echo   Type a number, multiple numbers separated by commas (e.g. 1,3,5), or A for all.
echo.
echo    1 ^>   VLC Media Player
echo    2 ^>   7-Zip
echo    3 ^>   Mozilla Firefox
echo    4 ^>   Google Chrome
echo    5 ^>   Notepad++
echo    6 ^>   WinRAR
echo    7 ^>   LibreOffice
echo    8 ^>   OBS Studio
echo    9 ^>   Discord
echo   10 ^>   Steam
echo   11 ^>   Visual Studio Code
echo   12^ >   Audacity
echo   13 ^>   qBittorrent
echo   14 ^>   ShareX (screenshots)
echo   15 ^>   Bitwarden (passwords)
echo   16 ^>   Brave Browser
echo   17 ^>   Spotify
echo   18 ^>   Zoom
echo   19 ^>   Python 3
echo.
powershell -NoProfile -Command "Write-Host '   A  ^>  Install ALL listed' -ForegroundColor Yellow"
echo   B  ^>  Back to main menu
echo.
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
echo.
set "WGCHOICE="
set /p "WGCHOICE=  Enter selection: "
if /i "!WGCHOICE!"=="B" goto MAIN_MENU
if /i "!WGCHOICE!"=="A" (
    for %%p in (VideoLAN.VLC 7zip.7zip Mozilla.Firefox Google.Chrome Notepad++.Notepad++ RARLab.WinRAR TheDocumentFoundation.LibreOffice OBSProject.OBSStudio Discord.Discord Valve.Steam Microsoft.VisualStudioCode Audacity.Audacity qBittorrent.qBittorrent ShareX.ShareX Bitwarden.Bitwarden Brave.Brave Spotify.Spotify Zoom.Zoom Python.Python.3) do call :WINGET_INSTALL %%p
    echo.
    powershell -NoProfile -Command "Write-Host '  All installs complete.' -ForegroundColor Green"
    echo.
    pause
    goto MAIN_MENU
)
for %%i in (!WGCHOICE!) do (
    set "_I=%%i"
    if "!_I!"=="1"  call :WINGET_INSTALL VideoLAN.VLC
    if "!_I!"=="2"  call :WINGET_INSTALL 7zip.7zip
    if "!_I!"=="3"  call :WINGET_INSTALL Mozilla.Firefox
    if "!_I!"=="4"  call :WINGET_INSTALL Google.Chrome
    if "!_I!"=="5"  call :WINGET_INSTALL Notepad++.Notepad++
    if "!_I!"=="6"  call :WINGET_INSTALL RARLab.WinRAR
    if "!_I!"=="7"  call :WINGET_INSTALL TheDocumentFoundation.LibreOffice
    if "!_I!"=="8"  call :WINGET_INSTALL OBSProject.OBSStudio
    if "!_I!"=="9"  call :WINGET_INSTALL Discord.Discord
    if "!_I!"=="10" call :WINGET_INSTALL Valve.Steam
    if "!_I!"=="11" call :WINGET_INSTALL Microsoft.VisualStudioCode
    if "!_I!"=="12" call :WINGET_INSTALL Audacity.Audacity
    if "!_I!"=="13" call :WINGET_INSTALL qBittorrent.qBittorrent
    if "!_I!"=="14" call :WINGET_INSTALL ShareX.ShareX
    if "!_I!"=="15" call :WINGET_INSTALL Bitwarden.Bitwarden
    if "!_I!"=="16" call :WINGET_INSTALL Brave.Brave
    if "!_I!"=="17" call :WINGET_INSTALL Spotify.Spotify
    if "!_I!"=="18" call :WINGET_INSTALL Zoom.Zoom
    if "!_I!"=="19" call :WINGET_INSTALL Python.Python.3
)
echo.
powershell -NoProfile -Command "Write-Host '  Install(s) complete.' -ForegroundColor Green"
echo.
pause
goto INSTALL_SOFTWARE

:WINGET_INSTALL
powershell -NoProfile -Command "Write-Host ('  Installing %~1 ...') -ForegroundColor Cyan"
winget install --id %~1 -e --silent --accept-source-agreements --accept-package-agreements
if !errorLevel! equ 0 (
    powershell -NoProfile -Command "Write-Host ('  [SUCCESS] %~1') -ForegroundColor Green"
) else (
    powershell -NoProfile -Command "Write-Host ('  [SKIP] %~1 - already installed or unavailable.') -ForegroundColor Yellow"
)
exit /b 0

:CLEANUP_PREVIEW
cls
echo.
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '    DISK CLEANUP SPACE PREVIEW' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
echo.
powershell -NoProfile -Command "Write-Host '  Scanning... please wait.' -ForegroundColor DarkGray"
echo.
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "$paths = @(" ^
    "  @{Label='Temp Files         '; Path=$env:TEMP}," ^
    "  @{Label='Prefetch           '; Path='C:\Windows\Prefetch'}," ^
    "  @{Label='WU Cache           '; Path='C:\Windows\SoftwareDistribution\Download'}," ^
    "  @{Label='Delivery Opt Cache '; Path='C:\Windows\ServiceProfiles\NetworkService\AppData\Local\Microsoft\Windows\DeliveryOptimization\Cache'}," ^
    "  @{Label='Error Reports      '; Path='C:\ProgramData\Microsoft\Windows\WER'}," ^
    "  @{Label='Thumbnail Cache    '; Path=$env:LOCALAPPDATA+'\Microsoft\Windows\Explorer'}," ^
    "  @{Label='Memory Dumps       '; Path='C:\Windows'}" ^
    ");" ^
    "$total = 0;" ^
    "foreach ($p in $paths) {" ^
    "  $size = 0;" ^
    "  if (Test-Path $p.Path) {" ^
    "    if ($p.Label -like '*Thumbnail*') {" ^
    "      $size = (Get-ChildItem $p.Path -Filter 'thumbcache_*.db' -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum" ^
    "    } elseif ($p.Label -like '*Dump*') {" ^
    "      $size = (Get-ChildItem $p.Path -Filter '*.dmp' -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum" ^
    "    } else {" ^
    "      $size = (Get-ChildItem $p.Path -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum" ^
    "    }" ^
    "  };" ^
    "  $size = if ($size) {$size} else {0};" ^
    "  $total += $size;" ^
    "  $mb = [math]::Round($size/1MB,1);" ^
    "  $col = if ($mb -gt 500){'Red'} elseif ($mb -gt 50){'Yellow'} else {'DarkGray'};" ^
    "  Write-Host ('  ' + $p.Label + ' : ' + $mb + ' MB') -ForegroundColor $col" ^
    "};" ^
    "Write-Host '';" ^
    "Write-Host ('  Estimated total freeable: ' + [math]::Round($total/1MB,1) + ' MB  (' + [math]::Round($total/1GB,2) + ' GB)') -ForegroundColor Green"
echo.
powershell -NoProfile -Command "Write-Host '  [NOTE] Windows.old is not included above - can be several GB.' -ForegroundColor Yellow"
exit /b 0

:RESTORE_POINT_MANAGER
cls
echo.
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '    RESTORE POINT MANAGER' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
echo.
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "$rps = Get-ComputerRestorePoint -ErrorAction SilentlyContinue;" ^
    "if (-not $rps) { Write-Host '  No restore points found on this machine.' -ForegroundColor Yellow } else {" ^
    "  Write-Host '  --- Existing Restore Points ---' -ForegroundColor Cyan;" ^
    "  Write-Host '';" ^
    "  $rps | Sort-Object SequenceNumber | ForEach-Object {" ^
    "    $t = $_.ConvertToDateTime($_.CreationTime);" ^
    "    Write-Host ('  [' + $_.SequenceNumber.ToString().PadLeft(3) + ']  ' + $t.ToString('yyyy-MM-dd  HH:mm')  + '   ' + $_.Description) -ForegroundColor White" ^
    "  };" ^
    "  Write-Host ''" ^
    "}"
echo.
echo   L  ^>  Launch System Restore wizard (choose a point to roll back to)
echo   B  ^>  Back
echo.
set "RPMCHOICE="
set /p "RPMCHOICE=  Select: "
if /i "!RPMCHOICE!"=="L" (
    powershell -NoProfile -Command "Write-Host '  Launching System Restore...' -ForegroundColor Cyan"
    start rstrui.exe
)
exit /b 0

:DRIVER_CHECK
cls
echo.
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '    DRIVER CHECK' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
echo.
powershell -NoProfile -Command "Write-Host '  Scanning drivers... please wait.' -ForegroundColor DarkGray"
echo.
set "DRVSCRIPT=%TEMP%\ytsh_drivers_%RANDOM%%RANDOM%.ps1"
(
    echo $drivers = Get-WindowsDriver -Online -ErrorAction SilentlyContinue
    echo if ^(-not $drivers^) { Write-Host '  Could not retrieve driver list.' -ForegroundColor Red; exit }
    echo $unsigned = $drivers ^| Where-Object { $_.Driver -ne $null -and -not $_.IsSigned }
    echo $thirdParty = $drivers ^| Where-Object { $_.ProviderName -ne 'Microsoft' -and $_.Driver -ne $null }
    echo $cutoff = ^(Get-Date^).AddYears^(-2^)
    echo $old = $thirdParty ^| Where-Object { try { [datetime]$_.Date -lt $cutoff } catch { $false } }
    echo Write-Host '  --- UNSIGNED DRIVERS ---' -ForegroundColor Red
    echo if ^($unsigned^) {
    echo     $unsigned ^| ForEach-Object { Write-Host ^('  [UNSIGNED] ' + $_.OriginalFileName + '  Provider: ' + $_.ProviderName^) -ForegroundColor Red }
    echo } else { Write-Host '  None found. Good.' -ForegroundColor Green }
    echo Write-Host ''
    echo Write-Host '  --- THIRD-PARTY DRIVERS OLDER THAN 2 YEARS ---' -ForegroundColor Yellow
    echo if ^($old^) {
    echo     $old ^| ForEach-Object { Write-Host ^('  [OLD] ' + $_.OriginalFileName + '  Provider: ' + $_.ProviderName + '  Date: ' + $_.Date^) -ForegroundColor Yellow }
    echo } else { Write-Host '  None found.' -ForegroundColor Green }
    echo Write-Host ''
    echo $tc = ^($drivers ^| Where-Object { $_.Driver -ne $null }^).Count
    echo $tp = $thirdParty.Count
    echo Write-Host ^('  Total drivers scanned : ' + $tc^) -ForegroundColor Cyan
    echo Write-Host ^('  Third-party drivers   : ' + $tp^) -ForegroundColor Cyan
    echo $col1 = if^($unsigned.Count -gt 0^){'Red'}else{'Green'}
    echo Write-Host ^('  Unsigned              : ' + $unsigned.Count^) -ForegroundColor $col1
    echo $col2 = if^($old.Count -gt 0^){'Yellow'}else{'Green'}
    echo Write-Host ^('  Potentially outdated  : ' + $old.Count^) -ForegroundColor $col2
) > "%DRVSCRIPT%"
powershell -NoProfile -ExecutionPolicy Bypass -File "%DRVSCRIPT%"
del "%DRVSCRIPT%" >nul 2>&1
exit /b 0

:EXPORT_REPORT
cls
color !COL_OPS!
echo.
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '    EXPORT REPORT' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
echo.
for /f %%D in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd"') do set "DATESTR=%%D"
set "RPTFILE=!LOGDIR!\YTSH_Report_!DATESTR!.txt"
set "RPTFILE=!RPTFILE: =_!"
powershell -NoProfile -Command "Write-Host '  Building report...' -ForegroundColor Cyan"
set "RPSCRIPT=%TEMP%\ytsh_report_%RANDOM%%RANDOM%.ps1"
set "YTSH_LOGFILE=!LOGFILE!"
set "YTSH_SVCLOG=!SVCLOG!"
set "YTSH_REGLOG=!REGLOG!"
set "YTSH_ERRLOG=!ERRLOG!"

if exist "%RPSCRIPT%" del "%RPSCRIPT%" >nul 2>&1

(
echo $out = @^(^)
echo $out += '============================================='
echo $out += '  YTSH Tech Utility - Machine Report'
echo $out += '  Generated: ' + ^(Get-Date -Format 'yyyy-MM-dd HH:mm:ss'^)
echo $out += '============================================='
echo $out += ''
echo $out += '--- SYSTEM INFO ---'
echo $os  = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
echo $cpu = Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue ^| Select-Object -First 1
echo $gpu = Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue ^| Select-Object -First 1
echo $out += 'OS   : ' + $os.Caption
echo $out += 'CPU  : ' + $^(if ^($cpu^) { $cpu.Name.Trim^(^) } else { 'Unknown' }^)
echo $out += 'RAM  : ' + [math]::Round^($os.TotalVisibleMemorySize/1MB,0^) + ' GB'
echo $out += 'GPU  : ' + $^(if ^($gpu^) { $gpu.Name.Trim^(^) } else { 'Unknown' }^)
echo $out += 'Disk : ' + ^([math]::Round^(^(Get-PSDrive C^).Used/1GB,1^)^) + ' GB used / ' + ^([math]::Round^(^(^(Get-PSDrive C^).Used+^(Get-PSDrive C^).Free^)/1GB,1^)^) + ' GB total'
echo $out += ''
echo $out += '--- ACTIVE POWER PLAN ---'
echo $pp = powercfg /getactivescheme 2^>$null
echo $out += $^(if^($pp^){$pp}else{'Unknown'}^)
echo $out += ''
echo $out += '--- DNS SERVERS ---'
echo Get-DnsClientServerAddress -ErrorAction SilentlyContinue ^| Where-Object {$_.ServerAddresses.Count -gt 0} ^| ForEach-Object { $out += ^($_.InterfaceAlias + ': ' + ^($_.ServerAddresses -join ', '^)^) }
echo $out += ''
echo $out += '--- INSTALLED WINGET APPS ^(user-installed^) ---'
echo try {
echo     $wg = winget list 2^>$null
echo     $capture = $false
echo     $prev = ''
echo     foreach ^($line in $wg^) {
echo         if ^($line -match '^^---'^) {
echo             $capture = $true
echo             $out += $prev
echo             $out += $line
echo         } elseif ^($capture -and $line.Trim^(^) -ne ''^) {
echo             $out += $line
echo         } else {
echo             $prev = $line
echo         }
echo     }
echo } catch {
echo     $out += 'winget not available'
echo }
echo $out += ''
echo $out += '--- REMOVED APPS LOG ---'
echo $lf = $env:YTSH_LOGFILE
echo if ^(Test-Path $lf^) { Get-Content $lf ^| ForEach-Object { $out += $_ } } else { $out += 'No removal log found.' }
echo $out += ''
echo $out += '--- DISABLED SERVICES LOG ---'
echo $sf = $env:YTSH_SVCLOG
echo if ^(Test-Path $sf^) { Get-Content $sf ^| ForEach-Object { $out += $_ } } else { $out += 'No service log found.' }
echo $out += ''
echo $out += '--- REGISTRY CHANGES LOG ---'
echo $rf = $env:YTSH_REGLOG
echo if ^(Test-Path $rf^) { Get-Content $rf ^| ForEach-Object { $out += $_ } } else { $out += 'No registry change log found.' }
echo $out += ''
echo $out += '--- ERROR LOG ---'
echo $ef = $env:YTSH_ERRLOG
echo if ^(Test-Path $ef^) { Get-Content $ef ^| ForEach-Object { $out += $_ } } else { $out += 'No errors logged.' }
echo $out += ''
echo $out += '============================================='
echo $out += '  End of Report'
echo $out += '============================================='
echo $out ^| Set-Content -Path '!RPTFILE!' -Encoding UTF8
echo Write-Host ^('  [SUCCESS] Report saved to: !RPTFILE!'^) -ForegroundColor Green
) > "%RPSCRIPT%"

powershell -NoProfile -ExecutionPolicy Bypass -File "%RPSCRIPT%"
del "%RPSCRIPT%" >nul 2>&1
echo.
pause
goto MAIN_MENU

:EXIT_SCRIPT
del /q /f "%TEMP%\ytsh_*.ps1" >nul 2>&1
cls
color !COL_OPS!
echo.
echo  =============================================
powershell -NoProfile -Command "Write-Host '   Goodbye. No unsaved changes were made.' -ForegroundColor Green"
echo   - YTSH's Tech Utility v1.0
echo  =============================================
echo.
pause
exit /b 0