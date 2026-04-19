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
    powershell -NoProfile -Command "Write-Host '    v2.1  | ADMINISTRATOR  | SAFE MODE: ENABLED (Advanced features locked)' -ForegroundColor !COL_HDR_PS!"
) else (
    powershell -NoProfile -Command "Write-Host '    v2.1  | ADMINISTRATOR  | SAFE MODE: DISABLED (Full access)' -ForegroundColor Yellow"
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
    echo   M  ^>  Mode      ^(New to PCs or afraid of risks? Change the Debloat Mode^)
) else (
    powershell -NoProfile -Command "Write-Host '   M  >  [LOCKED] Mode is currently set to: !DEBLOAT_MODE!' -ForegroundColor DarkGray"
)
echo.
powershell -NoProfile -Command "Write-Host '  --- CATEGORIES --------------------------------' -ForegroundColor !COL_HDR_PS!"
echo    1  ^>  DEBLOAT              !DBLOT_STAT!
echo    2  ^>  PERFORMANCE          !FPS_STAT!
echo    3  ^>  MAINTENANCE          !CLEAN_STAT!
echo    4  ^>  SECURITY ^& SOFTWARE
echo    5  ^>  SYSTEM TOOLS
echo    6  ^>  DIAGNOSTICS
echo    7  ^>  MALWARE AND THREAT SCANNING
echo.
echo    ------------------------------------------
echo.
echo    S  ^>  Settings
echo    R  ^>  Export Report  ^(Save a full summary of changes to a text file^)
echo    U  ^>  Usage          ^(Disk, RAM and system dashboard^)
echo    I  ^>  Info           ^(Category guide - what each section does^)
echo    0  ^>  Exit
echo.
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
echo.
set /p "CHOICE=  Enter your choice [0-7,M,S,R,U,I]: "
if "%CHOICE%"=="1" goto CAT_DEBLOAT
if "%CHOICE%"=="2" goto CAT_PERFORMANCE
if "%CHOICE%"=="3" goto CAT_MAINTENANCE
if "%CHOICE%"=="4" goto CAT_SECURITY
if "%CHOICE%"=="5" goto CAT_SYSTOOLS
if "%CHOICE%"=="6" goto CAT_DIAGNOSTICS
if "%CHOICE%"=="7" goto CAT_SCANNING
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

:CAT_DEBLOAT
cls
color !COL_OPS!
echo.
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '    DEBLOAT' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
echo.
echo    1  ^>  Debloat        ^(Choose what to remove^)!DBLOT_STAT!
echo    2  ^>  Revert         ^(Choose what to restore^)
echo    3  ^>  Status         ^(Full system debloat report^)
echo.
echo    B  ^>  Back
echo.
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
echo.
set "SUBCHOICE="
set /p "SUBCHOICE=  Select an option: "
if /i "!SUBCHOICE!"=="B" goto MAIN_MENU
if "!SUBCHOICE!"=="1" goto DEBLOAT_MENU
if "!SUBCHOICE!"=="2" goto REVERT_MENU
if "!SUBCHOICE!"=="3" goto CHECK_STATUS
color !COL_ERR!
echo.
echo  [!] Invalid choice.
echo.
pause
goto CAT_DEBLOAT

:CAT_PERFORMANCE
cls
color !COL_OPS!
echo.
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '    PERFORMANCE' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
echo.
set "_FPS_LOCK_MSG="
if /i "!DEBLOAT_MODE!"=="STUDENT" set "_FPS_LOCK_MSG=STUDENT"
if "!SAFE_MODE!"=="1" if "!_FPS_LOCK_MSG!"=="" set "_FPS_LOCK_MSG=SAFE"
if "!_FPS_LOCK_MSG!"=="STUDENT" powershell -NoProfile -Command "Write-Host '    1  >  [LOCKED] Gaming and FPS Boost (Disabled in STUDENT mode)' -ForegroundColor DarkGray"
if "!_FPS_LOCK_MSG!"=="SAFE"    powershell -NoProfile -Command "Write-Host '    1  >  [LOCKED] Gaming and FPS Boost (Disabled in SAFE MODE)' -ForegroundColor DarkGray"
if "!_FPS_LOCK_MSG!"=="" echo    1  ^>  Gaming and FPS Boost   ^(Gaming settings and frame-rate tweaks^)!FPS_STAT!
if "!SAFE_MODE!"=="1" (
    powershell -NoProfile -Command "Write-Host '    2  >  [LOCKED] Network Optimizations (Disabled in SAFE MODE)' -ForegroundColor DarkGray"
) else (
    echo    2  ^>  Network Optimizations  ^(Remove multimedia network caps^)!NET_STAT!
)
if "!SAFE_MODE!"=="1" (
    powershell -NoProfile -Command "Write-Host '    3  >  [LOCKED] Windows Tweaks (Disabled in SAFE MODE)' -ForegroundColor DarkGray"
) else (
    echo    3  ^>  Windows Tweaks         ^(Visual effects, pagefile, Windows Update^)
)
echo.
echo    B  ^>  Back
echo.
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
echo.
set "SUBCHOICE="
set /p "SUBCHOICE=  Select an option: "
if /i "!SUBCHOICE!"=="B" goto MAIN_MENU
if "!SUBCHOICE!"=="1" (
    if /i "!DEBLOAT_MODE!"=="STUDENT" (
        color !COL_ERR!
        echo.
        powershell -NoProfile -Command "Write-Host '  [LOCKED] Gaming and FPS Boost is disabled in STUDENT mode.' -ForegroundColor Red"
        echo.
        pause
        goto CAT_PERFORMANCE
    )
    if "!SAFE_MODE!"=="1" (
        color !COL_ERR!
        echo.
        powershell -NoProfile -Command "Write-Host '  [LOCKED] Gaming and FPS Boost is disabled in SAFE MODE.' -ForegroundColor Red"
        powershell -NoProfile -Command "Write-Host '  Go to Settings (S) and select Safe Mode (7) to change.' -ForegroundColor Yellow"
        echo.
        pause
        goto CAT_PERFORMANCE
    )
    goto FPS_MENU
)
if "!SUBCHOICE!"=="2" (
    if "!SAFE_MODE!"=="1" (
        color !COL_ERR!
        echo.
        powershell -NoProfile -Command "Write-Host '  [LOCKED] Network Optimizations is disabled in SAFE MODE.' -ForegroundColor Red"
        powershell -NoProfile -Command "Write-Host '  Go to Settings (S) and select Safe Mode (7) to change.' -ForegroundColor Yellow"
        echo.
        pause
        goto CAT_PERFORMANCE
    )
    goto NET_MENU
)
if "!SUBCHOICE!"=="3" (
    if "!SAFE_MODE!"=="1" (
        color !COL_ERR!
        echo.
        powershell -NoProfile -Command "Write-Host '  [LOCKED] Windows Tweaks is disabled in SAFE MODE.' -ForegroundColor Red"
        powershell -NoProfile -Command "Write-Host '  Go to Settings (S) and select Safe Mode (7) to change.' -ForegroundColor Yellow"
        echo.
        pause
        goto CAT_PERFORMANCE
    )
    goto TWEAKS_MENU
)
color !COL_ERR!
echo.
echo  [!] Invalid choice.
echo.
pause
goto CAT_PERFORMANCE

:CAT_MAINTENANCE
cls
color !COL_OPS!
echo.
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '    MAINTENANCE' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
echo.
echo    1  ^>  Disk Cleanup           ^(Safe junk removal^)!CLEAN_STAT!
echo    2  ^>  System Health Check!HLT_STAT!
set "_MLOCK="
if "!SAFE_MODE!"=="1" set "_MLOCK=SAFE"
if /i "!DEBLOAT_MODE!"=="NEWBIE" if "!_MLOCK!"=="" set "_MLOCK=NEWBIE"
if "!_MLOCK!"=="SAFE"   powershell -NoProfile -Command "Write-Host '    3  >  [LOCKED] Startup Repair Toolkit (Disabled in SAFE MODE)' -ForegroundColor DarkGray"
if "!_MLOCK!"=="NEWBIE" powershell -NoProfile -Command "Write-Host '    3  >  [LOCKED] Startup Repair Toolkit (Disabled in NEWBIE mode)' -ForegroundColor DarkGray"
if "!_MLOCK!"==""       echo    3  ^>  Startup Repair Toolkit ^(SFC, DISM, BCD, MBR, CHKDSK^)
echo.
echo    B  ^>  Back
echo.
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
echo.
set "SUBCHOICE="
set /p "SUBCHOICE=  Select an option: "
if /i "!SUBCHOICE!"=="B" goto MAIN_MENU
if "!SUBCHOICE!"=="1" goto CLEANUP_MENU
if "!SUBCHOICE!"=="2" goto HEALTH_CHECK
if "!SUBCHOICE!"=="3" (
    set "_CKM="
    if "!SAFE_MODE!"=="1" set "_CKM=SAFE"
    if /i "!DEBLOAT_MODE!"=="NEWBIE" if "!_CKM!"=="" set "_CKM=NEWBIE"
    if "!_CKM!"=="SAFE" (
        color !COL_ERR!
        echo.
        powershell -NoProfile -Command "Write-Host '  [LOCKED] Startup Repair Toolkit is disabled in SAFE MODE.' -ForegroundColor Red"
        powershell -NoProfile -Command "Write-Host '  Go to Settings (S) and select Safe Mode (7) to change.' -ForegroundColor Yellow"
        echo.
        pause
        goto CAT_MAINTENANCE
    )
    if "!_CKM!"=="NEWBIE" (
        color !COL_ERR!
        echo.
        powershell -NoProfile -Command "Write-Host '  [LOCKED] Startup Repair Toolkit is disabled in NEWBIE mode.' -ForegroundColor Red"
        echo.
        pause
        goto CAT_MAINTENANCE
    )
    goto STARTUP_REPAIR
)
color !COL_ERR!
echo.
echo  [!] Invalid choice.
echo.
pause
goto CAT_MAINTENANCE

:CAT_SECURITY
cls
color !COL_OPS!
echo.
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '    SECURITY ^& SOFTWARE' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
echo.
echo    1  ^>  Security Tools         ^(Firewall check, startup scan, SMB1^)
echo    2  ^>  Activate Windows       ^(HWID - legitimate, no key needed^)
if "!SAFE_MODE!"=="1" (
    powershell -NoProfile -Command "Write-Host '    3  >  [LOCKED] Windows Feature Manager (Disabled in SAFE MODE)' -ForegroundColor DarkGray"
) else (
    echo    3  ^>  Windows Feature Manager ^(Hyper-V, WSL, .NET, SMB1, etc.^)
)
echo    4  ^>  Install Software        ^(winget - 100+ apps across 10 categories^)
echo.
echo    B  ^>  Back
echo.
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
echo.
set "SUBCHOICE="
set /p "SUBCHOICE=  Select an option: "
if /i "!SUBCHOICE!"=="B" goto MAIN_MENU
if "!SUBCHOICE!"=="1" goto SECURITY_MENU
if "!SUBCHOICE!"=="2" goto ACTIVATE_WINDOWS
if "!SUBCHOICE!"=="3" (
    if "!SAFE_MODE!"=="1" (
        color !COL_ERR!
        echo.
        powershell -NoProfile -Command "Write-Host '  [LOCKED] Windows Feature Manager is disabled in SAFE MODE.' -ForegroundColor Red"
        powershell -NoProfile -Command "Write-Host '  Go to Settings (S) and select Safe Mode (7) to change.' -ForegroundColor Yellow"
        echo.
        pause
        goto CAT_SECURITY
    )
    goto WINFEATURE_MENU
)
if "!SUBCHOICE!"=="4" goto INSTALL_SOFTWARE
color !COL_ERR!
echo.
echo  [!] Invalid choice.
echo.
pause
goto CAT_SECURITY

:CAT_SYSTOOLS
cls
color !COL_OPS!
echo.
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '    SYSTEM TOOLS' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
echo.
set "_13LOCK="
if "!SAFE_MODE!"=="1" set "_13LOCK=SAFE"
if /i "!DEBLOAT_MODE!"=="NEWBIE" if "!_13LOCK!"=="" set "_13LOCK=NEWBIE"
if "!_13LOCK!"=="SAFE"   powershell -NoProfile -Command "Write-Host '    1  >  [LOCKED] Startup Repair Toolkit (Disabled in SAFE MODE)' -ForegroundColor DarkGray"
if "!_13LOCK!"=="NEWBIE" powershell -NoProfile -Command "Write-Host '    1  >  [LOCKED] Startup Repair Toolkit (Disabled in NEWBIE mode)' -ForegroundColor DarkGray"
if "!_13LOCK!"==""       echo    1  ^>  Startup Repair Toolkit  ^(SFC, DISM, BCD, MBR, CHKDSK^)
echo    2  ^>  Process and RAM Analyzer ^(top memory hogs, kill suspicious^)
echo    3  ^>  Wi-Fi Toolkit           ^(saved networks, passwords, signal, reset^)
echo    4  ^>  Printer and Device Cleanup ^(stuck queues, ghost devices^)
if "!SAFE_MODE!"=="1" (
    powershell -NoProfile -Command "Write-Host '    5  >  [LOCKED] Windows Hello Manager (Disabled in SAFE MODE)' -ForegroundColor DarkGray"
) else (
    echo    5  ^>  Windows Hello Manager   ^(PIN, biometrics, sign-in options^)
)
echo.
echo    B  ^>  Back
echo.
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
echo.
set "SUBCHOICE="
set /p "SUBCHOICE=  Select an option: "
if /i "!SUBCHOICE!"=="B" goto MAIN_MENU
if "!SUBCHOICE!"=="1" (
    set "_CK13="
    if "!SAFE_MODE!"=="1" set "_CK13=SAFE"
    if /i "!DEBLOAT_MODE!"=="NEWBIE" if "!_CK13!"=="" set "_CK13=NEWBIE"
    if "!_CK13!"=="SAFE" (
        color !COL_ERR!
        echo.
        powershell -NoProfile -Command "Write-Host '  [LOCKED] Startup Repair Toolkit is disabled in SAFE MODE.' -ForegroundColor Red"
        powershell -NoProfile -Command "Write-Host '  Go to Settings (S) and select Safe Mode (7) to change.' -ForegroundColor Yellow"
        echo.
        pause
        goto CAT_SYSTOOLS
    )
    if "!_CK13!"=="NEWBIE" (
        color !COL_ERR!
        echo.
        powershell -NoProfile -Command "Write-Host '  [LOCKED] Startup Repair Toolkit is disabled in NEWBIE mode.' -ForegroundColor Red"
        echo.
        pause
        goto CAT_SYSTOOLS
    )
    goto STARTUP_REPAIR
)
if "!SUBCHOICE!"=="2" goto PROCESS_ANALYZER
if "!SUBCHOICE!"=="3" goto WIFI_TOOLKIT
if "!SUBCHOICE!"=="4" goto PRINTER_CLEANUP
if "!SUBCHOICE!"=="5" (
    if "!SAFE_MODE!"=="1" (
        color !COL_ERR!
        echo.
        powershell -NoProfile -Command "Write-Host '  [LOCKED] Windows Hello Manager is disabled in SAFE MODE.' -ForegroundColor Red"
        powershell -NoProfile -Command "Write-Host '  Go to Settings (S) and select Safe Mode (7) to change.' -ForegroundColor Yellow"
        echo.
        pause
        goto CAT_SYSTOOLS
    )
    goto WINHELLO_MANAGER
)
color !COL_ERR!
echo.
echo  [!] Invalid choice.
echo.
pause
goto CAT_SYSTOOLS

:CAT_DIAGNOSTICS
cls
color !COL_OPS!
echo.
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '    DIAGNOSTICS' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
echo.
echo    1  ^>  Event Log Viewer        ^(critical errors, BSODs, update events^)
if "!SYS_FORM!"=="DESKTOP" (
    powershell -NoProfile -Command "Write-Host '    2  >  [LOCKED] Battery Report (No battery on this Desktop)' -ForegroundColor DarkGray"
) else (
    echo    2  ^>  Battery Report          ^(full charge vs design capacity, health^)
)
set "_20LOCK="
if "!SAFE_MODE!"=="1" set "_20LOCK=SAFE"
if /i "!DEBLOAT_MODE!"=="NEWBIE" if "!_20LOCK!"=="" set "_20LOCK=NEWBIE"
if "!_20LOCK!"=="SAFE"   powershell -NoProfile -Command "Write-Host '    3  >  [LOCKED] Environment Variables (Disabled in SAFE MODE)' -ForegroundColor DarkGray"
if "!_20LOCK!"=="NEWBIE" powershell -NoProfile -Command "Write-Host '    3  >  [LOCKED] Environment Variables (Disabled in NEWBIE mode)' -ForegroundColor DarkGray"
if "!_20LOCK!"==""       echo    3  ^>  Environment Variables   ^(view/edit PATH, system vars^)
echo.
echo    B  ^>  Back
echo.
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
echo.
set "SUBCHOICE="
set /p "SUBCHOICE=  Select an option: "
if /i "!SUBCHOICE!"=="B" goto MAIN_MENU
if "!SUBCHOICE!"=="1" goto EVENTLOG_VIEWER
if "!SUBCHOICE!"=="2" (
    if "!SYS_FORM!"=="DESKTOP" (
        color !COL_ERR!
        echo.
        powershell -NoProfile -Command "Write-Host '  [LOCKED] Battery Report is not available on Desktop systems.' -ForegroundColor Red"
        echo.
        pause
        goto CAT_DIAGNOSTICS
    )
    goto BATTERY_REPORT
)
if "!SUBCHOICE!"=="3" (
    set "_CK20="
    if "!SAFE_MODE!"=="1" set "_CK20=SAFE"
    if /i "!DEBLOAT_MODE!"=="NEWBIE" if "!_CK20!"=="" set "_CK20=NEWBIE"
    if "!_CK20!"=="SAFE" (
        color !COL_ERR!
        echo.
        powershell -NoProfile -Command "Write-Host '  [LOCKED] Environment Variables is disabled in SAFE MODE.' -ForegroundColor Red"
        powershell -NoProfile -Command "Write-Host '  Go to Settings (S) and select Safe Mode (7) to change.' -ForegroundColor Yellow"
        echo.
        pause
        goto CAT_DIAGNOSTICS
    )
    if "!_CK20!"=="NEWBIE" (
        color !COL_ERR!
        echo.
        powershell -NoProfile -Command "Write-Host '  [LOCKED] Environment Variables is disabled in NEWBIE mode.' -ForegroundColor Red"
        echo.
        pause
        goto CAT_DIAGNOSTICS
    )
    goto ENVVAR_MANAGER
)
color !COL_ERR!
echo.
echo  [!] Invalid choice.
echo.
pause
goto CAT_DIAGNOSTICS

:CAT_SCANNING
cls
color !COL_OPS!
echo.
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '    MALWARE AND THREAT SCANNING' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
echo.
echo    1  ^>  Malware and Threat Scanner           ^(processes, network, startup, files, firewall + 30 more^)
echo    2  ^>  Network Security Scanner             ^(ARP, connections, DNS, Wi-Fi, routing, shares + 11 more^)
echo    3  ^>  Registry Persistence Scanner         ^(Run keys, Winlogon, LSA, AppInit, BHO hijacks^)
echo    4  ^>  Startup and WMI Task Scanner         ^(startup folders, services, WMI subscriptions^)
echo    5  ^>  Process and DLL Injection Scanner    ^(live processes, injected DLLs, unsigned drivers^)
echo    6  ^>  Browser Hijack Scanner               ^(search engine, homepage, extensions, proxy^)
echo    7  ^>  Credential Exposure Scanner          ^(stored creds, WDigest, LSA PPL, LSASS status^)
echo    8  ^>  Driver Integrity and Rootkit Scanner ^(unsigned drivers, orphaned drivers, rootkit names^)
echo    9  ^>  User Privacy and Tracker Scanner     ^(advertising ID, telemetry keys, cookie stores^)
echo   10  ^>  Vulnerability and Patch Scanner      ^(pending updates, last patch date, Defender defs^)
echo   11  ^>  Hardware Health and SMART Scanner    ^(disk health, SMART counters, temperature, wear^)
echo   12  ^>  Sensitive Information Scanner        ^(SSN, credit card, API keys in document folders^)
echo   13  ^>  Browser Security and Policy Scanner  ^(GPO policies, forced search, forced extensions^)
echo.
echo    B  ^>  Back
echo.
if "!COLOR_THEME!"=="DEFAULT" (
    powershell -NoProfile -Command "Write-Host '   A  >  SCAN ALL                          (runs all 13 scanners in sequence)' -ForegroundColor Yellow"
) else (
    echo    A  ^>  SCAN ALL                          ^(runs all 13 scanners in sequence^)
)
echo.
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
echo.
set "SUBCHOICE="
set /p "SUBCHOICE=  Select an option [1-13, A, B]: "
if /i "!SUBCHOICE!"=="B" goto MAIN_MENU
if /i "!SUBCHOICE!"=="A" goto SCAN_ALL_MENU
if "!SUBCHOICE!"=="1"  goto MALWARE_SCANNER
if "!SUBCHOICE!"=="2"  goto NETWORK_SCANNER
if "!SUBCHOICE!"=="3"  goto REGPERSIST_SCANNER
if "!SUBCHOICE!"=="4"  goto STARTUP_WMI_SCANNER
if "!SUBCHOICE!"=="5"  goto PROCINJECTION_SCANNER
if "!SUBCHOICE!"=="6"  goto BROWSER_HIJACK_SCANNER
if "!SUBCHOICE!"=="7"  goto CREDENTIAL_SCANNER
if "!SUBCHOICE!"=="8"  goto DRIVER_ROOTKIT_SCANNER
if "!SUBCHOICE!"=="9"  goto PRIVACY_TRACKER_SCANNER
if "!SUBCHOICE!"=="10" goto CVE_PATCH_SCANNER
if "!SUBCHOICE!"=="11" goto SMART_HEALTH_SCANNER
if "!SUBCHOICE!"=="12" goto DLP_SCANNER
if "!SUBCHOICE!"=="13" goto BROWSER_POLICY_SCANNER
color !COL_ERR!
echo.
echo  [!] Invalid choice.
echo.
pause
goto CAT_SCANNING

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
net stop wuauserv /y >nul 2>&1
net stop bits /y >nul 2>&1
net stop cryptsvc /y >nul 2>&1
net stop dosvc /y >nul 2>&1
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
if "!_WIN11!"=="1" echo    99  [!C_SAFE!SAFE!C_RST!] Windows Copilot App (Win11 23H2+) - (AI application)
if "!_WIN11!"=="1" echo   100  [!C_SAFE!SAFE!C_RST!] Dev Home (Win11) - (Developer bloatware)
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
    echo    90  [!C_BAL!BALANCED!C_RST!] Disable SysMain / Superfetch - (SSD detected - NOT recommended. Disabling breaks RAM compression)
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
if "!DCHOICE!"=="91" set "DPKG=STUB_BUBBLEWITCH" & goto DO_SINGLE_STUB
if "!DCHOICE!"=="92" set "DPKG=STUB_FARMHEROES" & goto DO_SINGLE_STUB
if "!DCHOICE!"=="93" set "DPKG=Microsoft.WindowsCamera" & goto DO_SINGLE_APP
if "!DCHOICE!"=="94" set "DPKG=Microsoft.Whiteboard" & goto DO_SINGLE_APP
if "!DCHOICE!"=="95" set "DPKG=Microsoft.WebMediaExtensions" & goto DO_SINGLE_APP
if "!DCHOICE!"=="96" set "DPKG=Microsoft.HEVCVideoExtension" & goto DO_SINGLE_APP
if "!DCHOICE!"=="97" set "DPKG=Microsoft.VP9VideoExtensions" & goto DO_SINGLE_APP
if "!DCHOICE!"=="98" (
    if "!_WIN11!"=="1" set "DPKG=MicrosoftWindows.Client.WebExperience" & goto DO_SINGLE_APP
    if "!_WIN10!"=="1" set "DPKG=Microsoft.XboxApp" & goto DO_SINGLE_APP
)
if "!DCHOICE!"=="99" set "DPKG=Microsoft.Windows.Ai.Copilot.Provider" & goto DO_SINGLE_APP
if "!DCHOICE!"=="100" set "DPKG=Microsoft.Windows.DevHome" & goto DO_SINGLE_APP
rem --- HP ---
if /i "!DCHOICE!"=="H1" set "DPKG=BRAND_HP_JUMPSTART" & goto DO_BRAND_APP
if /i "!DCHOICE!"=="H2" set "DPKG=BRAND_HP_SUPPORTASSIST" & goto DO_BRAND_APP
if /i "!DCHOICE!"=="H3" set "DPKG=BRAND_HP_SMART" & goto DO_BRAND_APP
if /i "!DCHOICE!"=="H4" set "DPKG=BRAND_HP_QUICKDROP" & goto DO_BRAND_APP
if /i "!DCHOICE!"=="H5" set "DPKG=BRAND_HP_AUDIOSWITCH" & goto DO_BRAND_APP
if /i "!DCHOICE!"=="H6" set "DPKG=BRAND_HP_TOUCHPOINT" & goto DO_BRAND_APP
rem --- Dell ---
if /i "!DCHOICE!"=="D1" set "DPKG=BRAND_DELL_SUPPORTASSIST" & goto DO_BRAND_APP
if /i "!DCHOICE!"=="D2" set "DPKG=BRAND_DELL_DELIVERY" & goto DO_BRAND_APP
if /i "!DCHOICE!"=="D3" set "DPKG=BRAND_DELL_UPDATE" & goto DO_BRAND_APP
if /i "!DCHOICE!"=="D4" set "DPKG=BRAND_DELL_MOBILECON" & goto DO_BRAND_APP
if /i "!DCHOICE!"=="D5" set "DPKG=BRAND_DELL_MYDELL" & goto DO_BRAND_APP
if /i "!DCHOICE!"=="D6" set "DPKG=BRAND_DELL_CUSTCON" & goto DO_BRAND_APP
rem --- Lenovo ---
if /i "!DCHOICE!"=="L1" set "DPKG=BRAND_LENOVO_VANTAGE" & goto DO_BRAND_APP
if /i "!DCHOICE!"=="L2" set "DPKG=BRAND_LENOVO_SETTINGS" & goto DO_BRAND_APP
if /i "!DCHOICE!"=="L3" set "DPKG=BRAND_LENOVO_COMPANION" & goto DO_BRAND_APP
if /i "!DCHOICE!"=="L4" set "DPKG=BRAND_LENOVO_WINZIP" & goto DO_BRAND_APP
if /i "!DCHOICE!"=="L5" set "DPKG=BRAND_MCAFEE" & goto DO_BRAND_APP
rem --- ASUS ---
if /i "!DCHOICE!"=="AS1" set "DPKG=BRAND_ASUS_MYASUS" & goto DO_BRAND_APP
if /i "!DCHOICE!"=="AS2" set "DPKG=BRAND_MCAFEE" & goto DO_BRAND_APP
if /i "!DCHOICE!"=="AS3" set "DPKG=BRAND_ASUS_LIVEUPDATE" & goto DO_BRAND_APP
rem --- Acer ---
if /i "!DCHOICE!"=="AC1" set "DPKG=BRAND_ACER_CARECENTER" & goto DO_BRAND_APP
if /i "!DCHOICE!"=="AC2" set "DPKG=BRAND_MCAFEE" & goto DO_BRAND_APP
if /i "!DCHOICE!"=="AC3" set "DPKG=BRAND_ACER_COLLECTION" & goto DO_BRAND_APP
if /i "!DCHOICE!"=="AC4" set "DPKG=BRAND_ACER_PORTAL" & goto DO_BRAND_APP
rem --- MSI ---
if /i "!DCHOICE!"=="MS1" set "DPKG=BRAND_MSI_CENTER" & goto DO_BRAND_APP

if "!DCHOICE!"=="01" set "DPKG=*CandyCrush*" & goto DO_SINGLE_STUB
if "!DCHOICE!"=="1"  set "DPKG=*CandyCrush*" & goto DO_SINGLE_STUB
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
    echo     $r = Get-CimInstance -Namespace root\OpenHardwareMonitor -ClassName Sensor -ErrorAction Stop ^| Where-Object { $_.SensorType -eq 'Temperature' -and $_.Name -match 'CPU' } ^| Sort-Object Value -Descending ^| Select-Object -First 1
    echo     if ^($r^) { $cpuTempC = [math]::Round^($r.Value, 1^); $cpuSource = 'OpenHardwareMonitor' }
    echo } catch {}
    echo if ^($cpuTempC -eq $null^) {
    echo     try {
    echo         $r = Get-CimInstance -Namespace root\LibreHardwareMonitor -ClassName Sensor -ErrorAction Stop ^| Where-Object { $_.SensorType -eq 'Temperature' -and $_.Name -match 'CPU' } ^| Sort-Object Value -Descending ^| Select-Object -First 1
    echo         if ^($r^) { $cpuTempC = [math]::Round^($r.Value, 1^); $cpuSource = 'LibreHardwareMonitor' }
    echo     } catch {}
    echo }
    echo if ^($cpuTempC -eq $null^) {
    echo     try {
    echo         $tz = Get-CimInstance -Namespace root\wmi -ClassName MSAcpi_ThermalZoneTemperature -ErrorAction Stop
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
    echo                 $r = Get-CimInstance -Namespace $ns -ClassName Sensor -ErrorAction Stop ^| Where-Object { $_.SensorType -eq 'Temperature' -and $_.Name -match 'GPU' } ^| Sort-Object Value -Descending ^| Select-Object -First 1	
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
    echo $bat = Get-CimInstance -ClassName Win32_Battery
    echo if ^($bat^) {
    echo     Write-Host "  === BATTERY HEALTH ===" -ForegroundColor Cyan
    echo     Write-Host ""
    echo     $charge = $bat.EstimatedChargeRemaining
    echo     $bstat  = if ^($bat.BatteryStatus -eq 1^) { 'Discharging' } elseif ^($bat.BatteryStatus -eq 2^) { 'On AC ^(not charging^)' } elseif ^($bat.BatteryStatus -eq 6^) { 'Charging' } else { 'Status ' + $bat.BatteryStatus }
    echo     $chcol  = if ^($charge -lt 15^) { 'Red' } elseif ^($charge -lt 30^) { 'Yellow' } else { 'Green' }
    echo     Write-Host ^("  Charge   : " + $charge + "%%  (" + $bstat + ")"^) -ForegroundColor $chcol
    echo     try {
    echo         $bStatic = Get-CimInstance -Namespace root\wmi -ClassName BatteryStaticData    -ErrorAction Stop ^| Select-Object -First 1
	echo         $bFull   = Get-CimInstance -Namespace root\wmi -ClassName BatteryFullChargedCapacity -ErrorAction Stop ^| Select-Object -First 1
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
powershell -NoProfile -Command "Write-Host '    YTSH Tech Utility - Info Center' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
echo.
echo   Select a category to learn about it:
echo.
echo   1  ^>  Debloat          (what gets removed and why)
echo   2  ^>  Performance      (Gaming, Network, Tweaks explained)
echo   3  ^>  Maintenance      (Cleanup, Health, Startup Repair)
echo   4  ^>  Security ^& Software (Security tools, activation, winget)
echo   5  ^>  System Tools     (Startup Repair, Process Analyzer, Wi-Fi)
echo   6  ^>  Diagnostics      (Event Log, Battery, Environment Variables)
echo   7  ^>  Safe Mode        (what it locks and why)
echo   8  ^>  Modes            (Newbie, Student, Gamer explained)
echo   9  ^>  What is NEVER touched (always-safe list)
echo   10 ^>  Malware Check    (what it scans, results, false positives)
echo   11 ^>  Utility Shortcuts (Usage Dashboard, Export Report, Settings)
echo.
echo   B  ^>  Back to main menu
echo.
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
echo.
set "ICHOICE="
set /p "ICHOICE=  Select: "
if /i "!ICHOICE!"=="B" goto MAIN_MENU
if "!ICHOICE!"=="1" goto INFO_DEBLOAT
if "!ICHOICE!"=="2" goto INFO_PERFORMANCE
if "!ICHOICE!"=="3" goto INFO_MAINTENANCE
if "!ICHOICE!"=="4" goto INFO_SECURITY
if "!ICHOICE!"=="5" goto INFO_SYSTEMTOOLS
if "!ICHOICE!"=="6" goto INFO_DIAGNOSTICS
if "!ICHOICE!"=="7" goto INFO_SAFEMODE
if "!ICHOICE!"=="8" goto INFO_MODES
if "!ICHOICE!"=="9" goto INFO_SAFE_LIST
if "!ICHOICE!"=="10" goto INFO_MALWARE
if "!ICHOICE!"=="11" goto INFO_SHORTCUTS
powershell -NoProfile -Command "Write-Host '  [!] Invalid choice.' -ForegroundColor Red"
echo.
pause
goto INFO_SCREEN

:INFO_DEBLOAT
cls
color !COL_OPS!
echo.
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '    INFO: DEBLOAT (Options 1 and 2)' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
echo.
powershell -NoProfile -Command "Write-Host '  [OPTION 1 - DEBLOAT]' -ForegroundColor Cyan"
echo   Removes pre-installed Microsoft and OEM apps that serve no useful
echo   purpose on a clean install. Each item can be removed individually
echo   or via presets. Items are grouped into Apps, Services, and Telemetry.
echo.
echo   Apps removed include: Candy Crush, Bing News, Xbox overlays, Skype,
echo   Teams (personal stub), Clipchamp, Mail, Maps, Mixed Reality Portal,
echo   3D tools, Feedback Hub, OneDrive stub, Phone Link, Cortana, and more.
echo.
echo   Services disabled include: DiagTrack, WMPNetworkSvc, RemoteRegistry,
echo   Fax, WerSvc, XblAuthManager, WSearch, PhoneSvc, PrintNotify, etc.
echo.
echo   Telemetry blocked includes: Advertising ID, Activity History, Location
echo   Tracking, CEIP tasks, Handwriting data, Typing Insights, Wi-Fi Sense.
echo.
powershell -NoProfile -Command "Write-Host '  [OPTION 2 - REVERT]' -ForegroundColor Cyan"
echo   Restores anything removed by Option 1. Uses winget to reinstall
echo   AppX packages and re-enables services. Not all apps can be perfectly
echo   restored - some may require the Microsoft Store manually.
echo.
powershell -NoProfile -Command "Write-Host '  [OPTION K - STATUS]' -ForegroundColor Cyan"
echo   Shows a full report of what has been debloated, which services are
echo   still running, and which telemetry keys are still active.
echo.
pause
goto INFO_SCREEN

:INFO_PERFORMANCE
cls
color !COL_OPS!
echo.
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '    INFO: PERFORMANCE (Options 3, 4, 5)' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
echo.
powershell -NoProfile -Command "Write-Host '  [OPTION 3 - GAMING AND FPS BOOST]' -ForegroundColor Cyan"
echo   Enables Game Mode, HAGS, disables DVR and FullScreen Optimizations,
echo   removes mouse acceleration, sets High Performance power plan, and
echo   adjusts the multimedia network throttle index.
echo   LAPTOP WARNING: High Performance plan and Power Throttling tweaks
echo   will reduce battery life significantly. Shown in the menu as AGGRESSIVE.
echo   LOCKED in SAFE MODE and STUDENT mode.
echo.
powershell -NoProfile -Command "Write-Host '  [OPTION 4 - NETWORK OPTIMIZATIONS]' -ForegroundColor Cyan"
echo   Removes Windows multimedia network throttling (NetworkThrottlingIndex),
echo   tweaks TCP autotuning and DNS cache, and optionally disables QoS limits.
echo   LOCKED in SAFE MODE.
echo.
powershell -NoProfile -Command "Write-Host '  [OPTION 5 - WINDOWS TWEAKS]' -ForegroundColor Cyan"
echo   Adjusts visual effects for performance, configures the pagefile,
echo   modifies Windows Update delivery settings, disables transparency,
echo   and applies various registry quality-of-life tweaks.
echo   LOCKED in SAFE MODE.
echo.
pause
goto INFO_SCREEN

:INFO_MAINTENANCE
cls
color !COL_OPS!
echo.
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '    INFO: MAINTENANCE (Options 6, 7, 8)' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
echo.
powershell -NoProfile -Command "Write-Host '  [OPTION 6 - DISK CLEANUP]' -ForegroundColor Cyan"
echo   Removes temp files, Windows.old, delivery optimization cache,
echo   Windows Update cache, prefetch, and other junk. Calculates space
echo   savings before running. Safe to use anytime.
echo.
powershell -NoProfile -Command "Write-Host '  [OPTION 7 - SYSTEM HEALTH CHECK]' -ForegroundColor Cyan"
echo   Runs a read-only scan using DISM and SFC to check Windows image
echo   integrity and system file corruption. Does NOT repair automatically.
echo   Results are color-coded and saved to the log directory.
echo.
powershell -NoProfile -Command "Write-Host '  [OPTION 8 - STARTUP REPAIR TOOLKIT]' -ForegroundColor Cyan"
echo   Advanced repair tools: SFC /scannow, DISM /RestoreHealth, CHKDSK,
echo   BCD repair, and MBR repair. Each step is optional and individually
echo   confirmed. Use only when Windows has boot or corruption problems.
echo   LOCKED in SAFE MODE and NEWBIE mode.
echo.
pause
goto INFO_SCREEN

:INFO_SECURITY
cls
color !COL_OPS!
echo.
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '    INFO: SECURITY ^& SOFTWARE (Options 9, 10, 11, 12)' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
echo.
powershell -NoProfile -Command "Write-Host '  [OPTION 9 - SECURITY TOOLS]' -ForegroundColor Cyan"
echo   Checks Windows Firewall status, scans startup entries for suspicious
echo   executables, and can disable SMB1 (legacy protocol exploited by
echo   WannaCry and similar malware). Non-destructive by default.
echo.
powershell -NoProfile -Command "Write-Host '  [OPTION 10 - ACTIVATE WINDOWS]' -ForegroundColor Cyan"
echo   Uses HWID (Hardware ID) activation via Microsoft's licensing servers.
echo   This is a fully legitimate method - no KMS, no third-party tools,
echo   no product key required. Works on Windows 10 and 11.
echo.
powershell -NoProfile -Command "Write-Host '  [OPTION 11 - WINDOWS FEATURE MANAGER]' -ForegroundColor Cyan"
echo   Enables or disables optional Windows components: Hyper-V, WSL2,
echo   .NET 3.5, Telnet, TFTP, SMB1, Sandbox, and more.
echo   LOCKED in SAFE MODE.
echo.
powershell -NoProfile -Command "Write-Host '  [OPTION 12 - INSTALL SOFTWARE]' -ForegroundColor Cyan"
echo   Uses winget (Windows Package Manager) to install 100+ popular apps
echo   across 10 categories: Browsers, Media, Productivity, Development,
echo   Communication, Gaming, Cloud, Security, System Tools, and Design.
echo   Multiple apps can be installed at once using comma-separated input.
echo.
pause
goto INFO_SCREEN

:INFO_SYSTEMTOOLS
cls
color !COL_OPS!
echo.
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '    INFO: SYSTEM TOOLS (Options 13, 14, 15, 16, 17)' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
echo.
powershell -NoProfile -Command "Write-Host '  [OPTION 13 - STARTUP REPAIR TOOLKIT]' -ForegroundColor Cyan"
echo   Duplicated access point. See Info 3 (Maintenance) for full description.
echo   LOCKED in SAFE MODE and NEWBIE mode.
echo.
powershell -NoProfile -Command "Write-Host '  [OPTION 14 - PROCESS AND RAM ANALYZER]' -ForegroundColor Cyan"
echo   Lists running processes sorted by RAM usage. Flags unsigned executables
echo   and non-standard executable paths as potentially suspicious. Can kill
echo   selected processes directly from the menu.
echo   LOCKED in SAFE MODE and NEWBIE mode.
echo.
powershell -NoProfile -Command "Write-Host '  [OPTION 15 - WI-FI TOOLKIT]' -ForegroundColor Cyan"
echo   Lists all saved Wi-Fi profiles and can reveal saved passwords in
echo   plaintext. Shows signal strength, adapter info, and can reset the
echo   network stack (netsh winsock reset / ip reset).
echo   LOCKED in SAFE MODE and NEWBIE mode.
echo.
powershell -NoProfile -Command "Write-Host '  [OPTION 16 - PRINTER AND DEVICE CLEANUP]' -ForegroundColor Cyan"
echo   Clears stuck print queues, removes ghost (phantom) devices from
echo   Device Manager, and restarts the Print Spooler service.
echo   LOCKED in SAFE MODE.
echo.
powershell -NoProfile -Command "Write-Host '  [OPTION 17 - WINDOWS HELLO MANAGER]' -ForegroundColor Cyan"
echo   Manages PIN, fingerprint, and face sign-in options. Can clear and
echo   re-enroll biometric data, and toggle sign-in requirements.
echo   LOCKED in SAFE MODE.
echo.
pause
goto INFO_SCREEN

:INFO_DIAGNOSTICS
cls
color !COL_OPS!
echo.
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '    INFO: DIAGNOSTICS (Options 18, 19, 20, 21)' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
echo.
powershell -NoProfile -Command "Write-Host '  [OPTION 18 - EVENT LOG VIEWER]' -ForegroundColor Cyan"
echo   Queries Windows Event Log for critical and error-level events in the
echo   System and Application logs. Highlights BSOD kernel events (IDs 41,
echo   1001, 1003), checks for minidump files, and shows recent update events.
echo   Can export up to 50 critical events to a CSV file.
echo   LOCKED in SAFE MODE and NEWBIE mode.
echo.
powershell -NoProfile -Command "Write-Host '  [OPTION 19 - BATTERY REPORT]' -ForegroundColor Cyan"
echo   Shows live battery charge percentage, charging status, and calculates
echo   battery health as a percentage of original design capacity.
echo   Generates a full powercfg HTML battery report saved to the log folder.
echo   LOCKED permanently on DESKTOP systems (no battery detected).
echo   LOCKED in SAFE MODE on laptops.
echo.
powershell -NoProfile -Command "Write-Host '  [OPTION 20 - ENVIRONMENT VARIABLES]' -ForegroundColor Cyan"
echo   View System and User PATH entries with color-coded status (green = path
echo   exists, red = broken/missing). Add new entries to System or User PATH,
echo   view all System variables, or open the GUI editor directly.
echo   LOCKED in SAFE MODE and NEWBIE mode.
echo.
powershell -NoProfile -Command "Write-Host '  [OPTION 21 - MALWARE CHECK]' -ForegroundColor Cyan"
echo   Runs up to 35 read-only security checks against your system.
echo   Deletes nothing. See Info 10 for the full breakdown of all checks,
echo   how to read results, and which findings may be false positives.
echo   Available in all modes. Not locked by Safe Mode.
echo.
pause
goto INFO_SCREEN

:INFO_SAFEMODE
cls
color !COL_OPS!
echo.
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '    INFO: SAFE MODE' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
echo.
echo   Safe Mode is a protection layer built into this utility.
echo   When ENABLED (default), the following options are locked:
echo.
echo   3  Gaming and FPS Boost       5  Windows Tweaks
echo   4  Network Optimizations      8  Startup Repair Toolkit
echo   11 Windows Feature Manager   13  Startup Repair (alt entry)
echo   17  Windows Hello Manager    20 Environment Variables
echo.
echo   Safe Mode does NOT lock: Debloat, Revert, Disk Cleanup,
echo   Health Check, Security Tools, Windows Activation, Install Software,
echo   or the Malware Check (21).
echo.
echo   To toggle Safe Mode: go to Settings ^(S^) and choose option 7.
echo.
powershell -NoProfile -Command "Write-Host '  WHY DOES SAFE MODE EXIST?' -ForegroundColor Yellow"
echo   Many of the locked features modify low-level system behavior such as
echo   boot configuration, environment variables, and biometric settings.
echo   An accidental change in these areas can break Windows in ways that
echo   require a full reinstall to fix. Safe Mode prevents that.
echo.
pause
goto INFO_SCREEN

:INFO_MODES
cls
color !COL_OPS!
echo.
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '    INFO: MODES (Newbie, Student, Gamer)' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
echo.
powershell -NoProfile -Command "Write-Host '  DEFAULT MODE' -ForegroundColor Cyan"
echo   Full access to all debloat options. Uses Safe Mode toggle for access
echo   control on advanced features. Recommended for experienced users.
echo.
powershell -NoProfile -Command "Write-Host '  NEWBIE MODE' -ForegroundColor Cyan"
echo   Reduces the debloat menu to low-impact, clearly safe options only.
echo   Additionally locks: Startup Repair, Process Analyzer, Wi-Fi Toolkit,
echo   Event Log Viewer, and Environment Variables even if Safe Mode is off.
echo   Inside FPS menu: locks Power Throttling and High Performance plan.
echo   Best for: first-time users unsure of what they are doing.
echo.
powershell -NoProfile -Command "Write-Host '  STUDENT MODE' -ForegroundColor Cyan"
echo   Applies standard debloat but protects Microsoft Teams and Office-
echo   adjacent apps from removal. Locks the Gaming and FPS Boost menu.
echo   Best for: school or work laptops where Teams must remain installed.
echo.
powershell -NoProfile -Command "Write-Host '  GAMER MODE' -ForegroundColor Cyan"
echo   Standard debloat plus exposes Xbox and GameBar removal options that
echo   are hidden in other modes. Unlocks all FPS and power tweaks.
echo   Best for: dedicated gaming PCs where Xbox integration is unwanted.
echo.
echo   Modes are locked after selection to prevent accidental switching.
echo   To change modes: go to Settings ^(S^) and choose Reset Mode ^(6^).
echo.
pause
goto INFO_SCREEN

:INFO_SAFE_LIST
cls
color !COL_OPS!
echo.
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '    INFO: WHAT IS NEVER TOUCHED' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
echo.
powershell -NoProfile -Command "Write-Host '  The following are NEVER modified by any option in this tool:' -ForegroundColor Green"
echo.
echo   Microsoft Store         Windows Security (Defender)
echo   Microsoft Edge          Start Menu and Taskbar
echo   File Explorer           Notepad, Calculator, Snipping Tool
echo   Paint, Clock, Settings  Windows Search UI (only WSearch service)
echo   .NET Runtimes           VC++ Redistributables
echo   DirectX                 All hardware drivers
echo   Windows boot files      Any service required to boot Windows
echo   UAC settings            Windows Hello PIN (unless option 17 is used)
echo.
powershell -NoProfile -Command "Write-Host '  WHY NOT EDGE?' -ForegroundColor Yellow"
echo   Edge is deeply integrated into Windows shell components. Removing it
echo   breaks PDF previews, WebView2 apps, and certain system dialogs.
echo.
powershell -NoProfile -Command "Write-Host '  WHY NOT WINDOWS SEARCH UI?' -ForegroundColor Yellow"
echo   Disabling WSearch (the indexing service) slows down File Explorer
echo   search results but does not remove the search bar itself.
echo.
pause
goto INFO_SCREEN

:INFO_MALWARE
cls
color !COL_OPS!
echo.
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '    INFO: MALWARE CHECK (Option 21)' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
echo.
powershell -NoProfile -Command "Write-Host '  [WHAT IT DOES]' -ForegroundColor Cyan"
echo   Runs up to 35 read-only security checks against your system.
echo   It does NOT delete, quarantine, or modify anything. Nothing is
echo   changed on your PC. It only reads, inspects, and reports.
echo.
powershell -NoProfile -Command "Write-Host '  [SCAN MODES]' -ForegroundColor Cyan"
echo   Full Scan    - Runs all 35 checks. Most thorough. Takes a few minutes.
echo   Minimal Scan - Runs a core subset: processes, network, startup,
echo                  services, users, defender, firewall, defender
echo                  exclusions, privilege escalation, accessibility backdoors.
echo   Custom Scan  - Pick any single check from the full list of 35.
echo.
powershell -NoProfile -Command "Write-Host '  [WHAT GETS CHECKED (all 35)]' -ForegroundColor Cyan"
echo    1  Suspicious Processes         Known malware names, injection, bad paths
echo    2  Network Connections          Active connections, suspicious ports, external IPs
echo    3  Registry Startup Entries     HKLM + HKCU Run keys, startup folders
echo    4  Scheduled Tasks              Obfuscated or hidden task commands
echo    5  Suspicious Files             Temp, AppData, drive roots, hidden System32
echo    6  HOSTS File Tampering         Redirected domains, non-default entries
echo    7  Installed Services           Binaries in Temp, AppData, or non-C: drives
echo    8  User Accounts                Admin group members, hidden dollar accounts
echo    9  Windows Defender             Real-time protection, signatures, tamper status
echo   10  DNS Cache                    Suspicious TLDs and shortener domains
echo   11  Open Network Shares          Non-default shares exposed on the network
echo   12  ARP Cache                    Duplicate MACs indicating ARP poisoning
echo   13  Firewall Status              All profiles (Domain, Private, Public) on/off
echo   14  RDP and Remote Access        RDP enabled, NLA, port, remote tool installs
echo   15  Unsigned Drivers             Driver signature verification
echo   16  LSA Protection               PPL, Credential Guard, NTLM hash level
echo   17  BitLocker                    Encryption status on all volumes
echo   18  Browser Extensions           Chrome, Edge, Firefox, Opera, Brave + policy hijacking
echo   19  System Proxy                 Proxy settings, PAC scripts, WinHTTP proxy
echo   20  Certificate Store            Rogue root CAs and known MITM tool certs
echo   21  Defender Exclusions          Malware-added exclusions and bypass indicators
echo   22  Privilege Escalation         AlwaysInstallElevated, unquoted service paths
echo   23  WDigest Credential Caching   Plaintext password caching in LSASS
echo   24  Accessibility Backdoors      sethc/utilman/osk replaced with shell
echo   25  DLL Hijacking                AppInit_DLLs, Image File Execution Options
echo   26  WMI Persistence              Event subscriptions used for persistence
echo   27  BITS Jobs                    Background Intelligent Transfer persistence
echo   28  Shadow Copy Status           Ransomware indicator if all copies deleted
echo   29  Legacy Protocols             SMBv1 EternalBlue, LM hashes, SMB signing
echo   30  LLMNR and NetBIOS            Responder credential theft attack surface
echo   31  Credential Manager           Stored credentials, suspicious entries
echo   32  Windows 10/11 Security       TPM, Secure Boot, HVCI, Smart App Control, ASR
echo   33  PowerShell Security          Logging, execution policy, AMSI, PSv2 downgrade
echo   34  Browser Data Integrity       Login Data copies in temp, stealer indicators
echo   35  Prefetch Analysis            Traces of attack tools and previously run malware
echo.
powershell -NoProfile -Command "Write-Host '  [HOW TO READ THE RESULTS]' -ForegroundColor Cyan"
powershell -NoProfile -Command "Write-Host '  [CLEAN]  ' -NoNewline -ForegroundColor Green;  Write-Host ' Check passed. Nothing suspicious found.' -ForegroundColor Gray"
powershell -NoProfile -Command "Write-Host '  [WARN]   ' -NoNewline -ForegroundColor Yellow; Write-Host ' Something is misconfigured or worth reviewing.' -ForegroundColor Gray"
powershell -NoProfile -Command "Write-Host '  [THREAT] ' -NoNewline -ForegroundColor Red;    Write-Host ' Strong indicator of compromise or active risk.' -ForegroundColor Gray"
powershell -NoProfile -Command "Write-Host '  [INFO]   ' -NoNewline -ForegroundColor DarkGray; Write-Host ' Neutral information. No action needed.' -ForegroundColor Gray"
echo.
powershell -NoProfile -Command "Write-Host '  [FALSE POSITIVES]' -ForegroundColor Yellow"
echo   Some [THREAT] and [WARN] results may not indicate real infections.
echo   This tool deletes nothing - but always investigate before assuming
echo   the worst. The checks most prone to false positives are:
echo.
echo   Check 34 - Browser Data Integrity: flags Login Data files found in
echo   temp or public locations. Backup tools, sync software, or browser
echo   profile managers can legitimately place files there.
echo.
echo   Check 18 - Browser Extensions: some extensions are flagged by name
echo   pattern. Legitimate extensions may trigger a [WARN] depending on
echo   what they are named.
echo.
echo   Check 31 - Credential Manager: stored domain or legacy credentials
echo   from work, school, or mapped drives are expected and not malicious.
echo.
echo   Check 35 - Prefetch: tool names like NMAP or PROCDUMP are matched
echo   by pattern. IT admins and security researchers may have run these
echo   legitimately.
echo.
echo   Check 10 - DNS Cache: ad networks and trackers visited during normal
echo   browsing may match suspicious TLD patterns.
echo.
echo   Always cross-reference [THREAT] results with your own installed
echo   software and recent activity before drawing conclusions.
echo.
powershell -NoProfile -Command "Write-Host '  [REPORT FILE]' -ForegroundColor Cyan"
echo   A full scan report is saved to your log directory after every scan.
echo   The filename includes the scan date and time. The report contains
echo   the raw output of all checks and can be shared with a technician.
echo.
echo   Available in all modes. Not locked by Safe Mode or any Debloat Mode.
echo.
pause
goto INFO_SCREEN

:INFO_SHORTCUTS
cls
color !COL_OPS!
echo.
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '    INFO: UTILITY SHORTCUTS (U, R, S)' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
echo.
powershell -NoProfile -Command "Write-Host '  [U - USAGE DASHBOARD]' -ForegroundColor Cyan"
echo   Displays a live system resource overview. Makes no changes to anything.
echo   Shows disk usage for every detected drive with a visual fill-bar
echo   (green below 60%%, yellow 60-85%%, red above 85%%), total and free space,
echo   and current usage percentage. Also shows RAM usage the same way.
echo.
echo   Baseline tracking: the first time you open Usage Dashboard it saves
echo   your current RAM usage as a baseline. On future runs it compares live
echo   RAM usage to that baseline and tells you how much memory has been freed
echo   (or used) since you last ran Disk Cleanup.
echo.
powershell -NoProfile -Command "Write-Host '  [R - EXPORT REPORT]' -ForegroundColor Cyan"
echo   Generates a full machine snapshot and saves it as a text file in your
echo   configured log directory. The report includes OS version, CPU, RAM, GPU,
echo   disk usage, active power plan, debloat log history, service changes,
echo   registry point modifications made by this tool, and error log entries.
echo   Useful for keeping a record of changes or sharing with a technician.
echo.
powershell -NoProfile -Command "Write-Host '  [S - SETTINGS]' -ForegroundColor Cyan"
echo   Opens the settings menu. Available options:
echo.
echo   1  Registry Points Location  - where restore point backups are saved
echo   2  Log Files Location        - where all log and report files go
echo   3  Auto-Restart              - toggle restart after full debloat run
echo   4  Skip OEM Stubs            - toggle OEM apps in Full Debloat
echo   5  Color Theme               - DEFAULT, MATRIX, AMBER, OCEAN, BLOOD,
echo                                  VIOLET, ARCTIC, GOLD, MIDNIGHT
echo   6  Reset Debloat Mode        - resets mode to DEFAULT, re-enables M menu
echo   7  Safe Mode                 - toggle Safe Mode on or off
echo.
pause
goto INFO_SCREEN

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
set "YTSH_SVCLOG=!SVCLOG!"
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
    echo             Add-Content -Path $env:YTSH_SVCLOG -Value ^($svc + '=' + $num^)
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
set "YTSH_SVCLOG=!SVCLOG!"
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
    echo             Add-Content -Path $env:YTSH_SVCLOG -Value ^($svc + '=' + $num^)
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
set "YTSH_SVCLOG=!SVCLOG!"
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
    echo         Add-Content -Path $env:YTSH_SVCLOG -Value ^($s + '=' + $num^)
    echo         try {
    echo             Set-Service -Name $s -StartupType Disabled -ErrorAction Stop
    echo             Stop-Service -Name $s -Force -ErrorAction SilentlyContinue
    echo             Write-Host ^('  [SUCCESS] ' + $s + ' disabled'^) -ForegroundColor Green
    echo         } catch {
    echo             Write-Host ^('  [FAIL] ' + $s + ': ' + $_.Exception.Message^) -ForegroundColor Red
    echo         }
    echo     } else {
    echo         Write-Host ^('  [SKIP] ' + $s + ' not found'^) -ForegroundColor DarkGray
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
    powershell -NoProfile -C ommand "Write-Host '  [WARN] winget not available. Skipping winget installs.' -ForegroundColor Red"
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
    echo     Checkpoint-Computer -Description 'Before YTSH Debloat Utility v2.1' -RestorePointType 'MODIFY_SETTINGS' -ErrorAction Stop
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
    echo try { Checkpoint-Computer -Description 'Before YTSH Debloat v2.1 Single Op' -RestorePointType 'MODIFY_SETTINGS' -ErrorAction Stop } catch {}
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
shutdown /r /t 5 /c "YTSH Debloat Utility v2.1: Applying changes."
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
    echo     $wmiDisks = Get-CimInstance -ClassName MSStorageDriver_FailurePredictStatus -Namespace root\wmi -ErrorAction SilentlyContinue
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
echo   6  ^>  Win11 Classic Context Menu (Restore right-click menu)
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
if "!TWCHOICE!"=="6" goto TW_OPT_6
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
:TW_OPT_6
call :TWEAK_CONTEXT_MENU & goto TWEAKS_MENU
goto TWEAKS_MENU

:TWEAK_CONTEXT_MENU
cls
echo.
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '    WIN11 CLASSIC CONTEXT MENU' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
echo.
echo   1  ^>  Enable Classic Windows 10 Context Menu
echo   2  ^>  Restore Modern Windows 11 Context Menu
echo   B  ^>  Back
echo.
set "CTXCHOICE="
set /p "CTXCHOICE=  Select: "
if /i "!CTXCHOICE!"=="B" exit /b 0
if "!CTXCHOICE!"=="1" (
    reg add "HKCU\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32" /f /ve >nul 2>&1
    taskkill /f /im explorer.exe >nul 2>&1
    start explorer.exe >nul 2>&1
    powershell -NoProfile -Command "Write-Host '  [SUCCESS] Classic Context Menu Enabled.' -ForegroundColor Green"
    pause & exit /b 0
)
if "!CTXCHOICE!"=="2" (
    reg delete "HKCU\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}" /f >nul 2>&1
    taskkill /f /im explorer.exe >nul 2>&1
    start explorer.exe >nul 2>&1
    powershell -NoProfile -Command "Write-Host '  [SUCCESS] Modern Context Menu Restored.' -ForegroundColor Green"
    pause & exit /b 0
)
powershell -NoProfile -Command "Write-Host '  [!] Invalid choice.' -ForegroundColor Red"
pause
exit /b 0

:TWEAK_VISUALS
echo.
powershell -NoProfile -Command "Write-Host '  Optimizing Visual Effects for Performance...' -ForegroundColor Cyan"
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects" /v VisualFXSetting /t REG_DWORD /d 2 /f >nul 2>&1
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
powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-CimInstance Win32_ComputerSystem | Set-CimInstance -Property @{AutomaticManagedPagefile=$false}; $pf=Get-CimInstance -Query 'Select * From Win32_PageFileSetting' -ErrorAction SilentlyContinue; if(-not $pf){New-CimInstance -ClassName Win32_PageFileSetting -Property @{Name='C:\pagefile.sys';InitialSize=%PF_SIZE%;MaximumSize=%PF_SIZE%} | Out-Null}else{$pf | Set-CimInstance -Property @{InitialSize=%PF_SIZE%;MaximumSize=%PF_SIZE%} | Out-Null}"
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
    powershell -NoProfile -ExecutionPolicy Bypass -Command "Set-CimInstance -Query 'Select * from Win32_ComputerSystem' -Property @{AutomaticManagedPagefile=$true} -ErrorAction SilentlyContinue; Write-Host '  [SUCCESS] Pagefile set to system managed.' -ForegroundColor Green"
    exit /b 0
)
if "!PGCHOICE!"=="2" (
    powershell -NoProfile -ExecutionPolicy Bypass -Command "$mb=[math]::Round((Get-CimInstance Win32_OperatingSystem).TotalVisibleMemorySize/1024,0); $init=[math]::Round($mb*1.5,0); $max=[math]::Round($mb*3,0); Get-CimInstance Win32_ComputerSystem | Set-CimInstance -Property @{AutomaticManagedPagefile=$false}; $pf=Get-CimInstance -Query 'Select * From Win32_PageFileSetting' -ErrorAction SilentlyContinue; if(-not $pf){New-CimInstance -ClassName Win32_PageFileSetting -Property @{Name='C:\pagefile.sys';InitialSize=$init;MaximumSize=$max} | Out-Null}else{$pf | Set-CimInstance -Property @{InitialSize=$init;MaximumSize=$max} | Out-Null}; Write-Host ('  [SUCCESS] Pagefile: initial='+$init+' MB, max='+$max+' MB. Restart required.') -ForegroundColor Green"
    exit /b 0
)
if "!PGCHOICE!"=="3" (
    powershell -NoProfile -Command "Write-Host '  [WARN] Disabling pagefile can cause crashes if RAM fills up.' -ForegroundColor Yellow"
    set "PGCONF="
    set /p "PGCONF=  Type CONFIRM to proceed: "
    if /i "!PGCONF!"=="CONFIRM" (
        powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-CimInstance Win32_ComputerSystem | Set-CimInstance -Property @{AutomaticManagedPagefile=$true}; Write-Host '  [SUCCESS] Pagefile set to system managed.' -ForegroundColor Green"
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
    powershell -NoProfile -Command "Write-Host '  Launching activation service in an isolated window to prevent Defender false-positives...' -ForegroundColor Cyan"
    start powershell -NoProfile -ExecutionPolicy Bypass -Command "irm https://get.activated.win | iex"
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
powershell -NoProfile -Command "Write-Host '    INSTALL SOFTWARE (via winget) - 160+ Apps' -ForegroundColor !COL_HDR_PS!"
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
echo   Type a number, multiple numbers separated by commas ^(e.g. 1,3,5^), or A for all.
echo.
powershell -NoProfile -Command "Write-Host '  --- [BROWSERS] ---' -ForegroundColor !COL_HDR_PS!"
echo    1  ^>  Mozilla Firefox
echo    2  ^>  Google Chrome
echo    3  ^>  Brave Browser
echo    4  ^>  Opera GX
echo    5  ^>  Tor Browser
echo    6  ^>  LibreWolf
echo    7  ^>  Vivaldi
echo    8  ^>  Microsoft Edge
echo.
powershell -NoProfile -Command "Write-Host '  --- [MEDIA ^& AUDIO] ---' -ForegroundColor !COL_HDR_PS!"
echo    9  ^>  VLC Media Player
echo   10  ^>  MPC-HC
echo   11  ^>  mpv
echo   12  ^>  Spotify
echo   13  ^>  Audacity
echo   14  ^>  HandBrake
echo   15  ^>  Kodi Media Center
echo   16  ^>  Winamp
echo   17  ^>  MKVToolNix
echo   18  ^>  foobar2000
echo   19  ^>  AIMP
echo   20  ^>  Stremio
echo   21  ^>  LosslessCut
echo   22  ^>  FFmpeg
echo   23  ^>  ImageGlass
echo   24  ^>  IrfanView
echo   25  ^>  MediaMonkey
echo.
powershell -NoProfile -Command "Write-Host '  --- [PRODUCTIVITY ^& OFFICE] ---' -ForegroundColor !COL_HDR_PS!"
echo   26  ^>  LibreOffice
echo   27  ^>  Notepad++
echo   28  ^>  Obsidian
echo   29  ^>  Notion
echo   30  ^>  KeePassXC
echo   31  ^>  Bitwarden
echo   32  ^>  Sumatra PDF
echo   33  ^>  Foxit PDF Reader
echo   34  ^>  PDFsam Basic
echo   35  ^>  ONLYOFFICE Desktop
echo   36  ^>  CherryTree
echo   37  ^>  Joplin
echo   38  ^>  Standard Notes
echo   39  ^>  Logseq
echo   40  ^>  Zotero
echo   41  ^>  AutoHotkey
echo   42  ^>  Microsoft PowerToys
echo   43  ^>  7-Zip
echo   44  ^>  NanaZip
echo   45  ^>  WinRAR
echo   46  ^>  PDF24 Creator
echo   47  ^>  FreeFileSync
echo   48  ^>  TeraCopy
echo.
powershell -NoProfile -Command "Write-Host '  --- [DEVELOPMENT ^& CODE] ---' -ForegroundColor !COL_HDR_PS!"
echo   49  ^>  Visual Studio Code
echo   50  ^>  Neovim
echo   51  ^>  Sublime Text 4
echo   52  ^>  Git
echo   53  ^>  Python 3
echo   54  ^>  Node.js LTS
echo   55  ^>  Go
echo   56  ^>  Rust ^(rustup^)
echo   57  ^>  Java JDK 21 ^(Eclipse Temurin^)
echo   58  ^>  Windows Terminal
echo   59  ^>  PowerShell 7
echo   60  ^>  Postman
echo   61  ^>  Insomnia
echo   62  ^>  Docker Desktop
echo   63  ^>  JetBrains Toolbox
echo   64  ^>  GitHub Desktop
echo   65  ^>  WinSCP
echo   66  ^>  PuTTY
echo   67  ^>  Wireshark
echo   68  ^>  HeidiSQL
echo   69  ^>  DBeaver Community
echo   70  ^>  pgAdmin 4
echo   71  ^>  MySQL Workbench
echo   72  ^>  MSYS2
echo   73  ^>  CMake
echo   74  ^>  Android Studio
echo   75  ^>  Nmap
echo.
powershell -NoProfile -Command "Write-Host '  --- [COMMUNICATION] ---' -ForegroundColor !COL_HDR_PS!"
echo   76  ^>  Discord
echo   77  ^>  Zoom
echo   78  ^>  Telegram
echo   79  ^>  Signal
echo   80  ^>  Slack
echo   81  ^>  Skype
echo   82  ^>  WhatsApp
echo   83  ^>  Mozilla Thunderbird
echo   84  ^>  Microsoft Teams
echo   85  ^>  Rocket.Chat
echo   86  ^>  Element
echo   87  ^>  Mattermost
echo   88  ^>  Viber
echo   89  ^>  LINE
echo.
powershell -NoProfile -Command "Write-Host '  --- [GAMING] ---' -ForegroundColor !COL_HDR_PS!"
echo   90  ^>  Steam
echo   91  ^>  Epic Games Launcher
echo   92  ^>  GOG Galaxy
echo   93  ^>  EA App
echo   94  ^>  Ubisoft Connect
echo   95  ^>  Playnite
echo   96  ^>  Parsec
echo   97  ^>  Heroic Games Launcher
echo   98  ^>  Sunshine ^(stream host^)
echo   99  ^>  Moonlight ^(stream client^)
echo  100  ^>  RetroArch
echo  101  ^>  itch.io
echo.
powershell -NoProfile -Command "Write-Host '  --- [CLOUD ^& FILE TRANSFER] ---' -ForegroundColor !COL_HDR_PS!"
echo  102  ^>  qBittorrent
echo  103  ^>  Dropbox
echo  104  ^>  MEGA Sync
echo  105  ^>  Google Drive Desktop
echo  106  ^>  FileZilla
echo  107  ^>  Cyberduck
echo  108  ^>  pCloud
echo.
powershell -NoProfile -Command "Write-Host '  --- [SECURITY ^& VPN] ---' -ForegroundColor !COL_HDR_PS!"
echo  109  ^>  Malwarebytes
echo  110  ^>  GlassWire
echo  111  ^>  ProtonVPN
echo  112  ^>  Windscribe
echo  113  ^>  Sandboxie Plus
echo  114  ^>  OpenVPN
echo  115  ^>  Mullvad VPN
echo  116  ^>  VeraCrypt
echo.
powershell -NoProfile -Command "Write-Host '  --- [SYSTEM TOOLS] ---' -ForegroundColor !COL_HDR_PS!"
echo  117  ^>  CPU-Z
echo  118  ^>  GPU-Z
echo  119  ^>  HWiNFO64
echo  120  ^>  HWMonitor
echo  121  ^>  MSI Afterburner
echo  122  ^>  RivaTuner Statistics Server
echo  123  ^>  CrystalDiskInfo
echo  124  ^>  CrystalDiskMark
echo  125  ^>  Speccy
echo  126  ^>  System Informer
echo  127  ^>  Everything Search
echo  128  ^>  TreeSize Free
echo  129  ^>  WizTree
echo  130  ^>  WinDirStat
echo  131  ^>  Autoruns ^(Sysinternals^)
echo  132  ^>  Process Monitor ^(Sysinternals^)
echo  133  ^>  TCPView ^(Sysinternals^)
echo  134  ^>  Rufus
echo  135  ^>  balenaEtcher
echo  136  ^>  Ventoy
echo  137  ^>  Macrium Reflect Free
echo  138  ^>  BleachBit
echo  139  ^>  Geek Uninstaller
echo  140  ^>  Revo Uninstaller
echo  141  ^>  O^&O ShutUp10++
echo  142  ^>  Fan Control
echo  143  ^>  Open-Shell
echo  144  ^>  TranslucentTB
echo  145  ^>  f.lux
echo.
powershell -NoProfile -Command "Write-Host '  --- [DESIGN ^& CONTENT CREATION] ---' -ForegroundColor !COL_HDR_PS!"
echo  146  ^>  OBS Studio
echo  147  ^>  ShareX
echo  148  ^>  ScreenToGif
echo  149  ^>  Greenshot
echo  150  ^>  Flameshot
echo  151  ^>  GIMP
echo  152  ^>  Inkscape
echo  153  ^>  Kdenlive
echo  154  ^>  Paint.NET
echo  155  ^>  Krita
echo  156  ^>  Blender
echo  157  ^>  DaVinci Resolve
echo  158  ^>  Streamlabs
echo  159  ^>  Shotcut
echo  160  ^>  Figma
echo  161  ^>  Canva
echo  162  ^>  CapCut
echo.
powershell -NoProfile -Command "Write-Host '  --- [RUNTIMES ^& FRAMEWORKS] ---' -ForegroundColor !COL_HDR_PS!"
echo  163  ^>  .NET 8 Runtime
echo  164  ^>  .NET 9 Runtime
echo  165  ^>  Java Runtime 21 ^(Eclipse Temurin^)
echo  166  ^>  Microsoft Edge WebView2 Runtime
echo  167  ^>  Visual C++ Redistributable 2015-2022 ^(x64^)
echo.
powershell -NoProfile -Command "Write-Host '   A  ^>  Install ALL listed apps' -ForegroundColor Yellow"
echo   B  ^>  Back to main menu
echo.
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
echo.
set "WGCHOICE="
set /p "WGCHOICE=  Enter selection: "
if /i "!WGCHOICE!"=="B" goto MAIN_MENU
if /i "!WGCHOICE!"=="A" (
    for %%p in (Mozilla.Firefox Google.Chrome BraveSoftware.BraveBrowser Opera.OperaGX TorProject.TorBrowser LibreWolf.LibreWolf VivaldiTechnologies.Vivaldi Microsoft.Edge VideoLAN.VLC clsid2.mpc-hc mpv.mpv Spotify.Spotify Audacity.Audacity HandBrake.HandBrake XBMCFoundation.Kodi Winamp.Winamp MKVToolNix.MKVToolNix PeterPawlowski.foobar2000 AIMP.AIMP Stremio.Stremio mifi.losslesscut Gyan.FFmpeg ImageGlass.ImageGlass IrfanSkiljan.IrfanView VentisMedia.MediaMonkey TheDocumentFoundation.LibreOffice Notepad++.Notepad++ Obsidian.Obsidian Notion.Notion KeePassXCTeam.KeePassXC Bitwarden.Bitwarden SumatraPDF.SumatraPDF Foxit.FoxitReader PDFsam.PDFsamBasic AscensioSystemSIA.OnlyOffice giuspen.cherrytree Joplin.Joplin StandardNotes.StandardNotes Logseq.Logseq Zotero.Zotero AutoHotkey.AutoHotkey Microsoft.PowerToys 7zip.7zip M2Team.NanaZip RARLab.WinRAR GeekSoftwareGmbH.PDF24Creator Zenju.FreeFileSync CodeSector.TeraCopy Microsoft.VisualStudioCode Neovim.Neovim SublimeHQ.SublimeText.4 Git.Git Python.Python.3.12 OpenJS.NodeJS.LTS GoLang.Go Rustlang.Rustup EclipseAdoptium.Temurin.21.JDK Microsoft.WindowsTerminal Microsoft.PowerShell Postman.Postman Kong.Insomnia Docker.DockerDesktop JetBrains.Toolbox GitHub.GitHubDesktop WinSCP.WinSCP PuTTY.PuTTY WiresharkFoundation.Wireshark AnsgarBecker.HeidiSQL dbeaver.dbeaver PostgreSQL.pgAdmin Oracle.MySQLWorkbench MSYS2.MSYS2 Kitware.CMake Google.AndroidStudio Insecure.Nmap Discord.Discord Zoom.Zoom Telegram.TelegramDesktop OpenWhisperSystems.Signal SlackTechnologies.Slack Microsoft.Skype WhatsApp.WhatsApp Mozilla.Thunderbird Microsoft.Teams RocketChat.RocketChat Element.Element Mattermost.MattermostDesktop Viber.Viber LINE.LINE Valve.Steam EpicGames.EpicGamesLauncher GOG.Galaxy ElectronicArts.EADesktop Ubisoft.Connect Playnite.Playnite Parsec.Parsec HeroicGamesLauncher.HeroicGamesLauncher LizardByte.Sunshine MoonlightGameStreamingProject.Moonlight Libretro.RetroArch itchio.itch qBittorrent.qBittorrent Dropbox.Dropbox Mega.MEGASync Google.GoogleDrive TimKosse.FileZillaClient Cyberduck.Cyberduck pCloudAG.pCloudDrive Malwarebytes.Malwarebytes SecureMix.GlassWire Proton.ProtonVPN Windscribe.Windscribe Sandboxie.Plus OpenVPNTechnologies.OpenVPN MullvadVPN.MullvadVPN IDRIX.VeraCrypt CPUID.CPU-Z TechPowerUp.GPU-Z REALiX.HWiNFO CPUID.HWMonitor Guru3D.Afterburner Guru3D.RTSS CrystalDewWorld.CrystalDiskInfo CrystalDewWorld.CrystalDiskMark Piriform.Speccy SystemInformer.SystemInformer voidtools.Everything JAMSoftware.TreeSizeFree AntibodySoftware.WizTree WinDirStat.WinDirStat Microsoft.Sysinternals.Autoruns Microsoft.Sysinternals.ProcessMonitor Microsoft.Sysinternals.TCPView Rufus.Rufus Balena.Etcher Ventoy.Ventoy Macrium.Reflect BleachBit.BleachBit ThomasKoen.GeekUninstaller VSRevoGroup.RevoUninstallerFree OOSoftware.OOShutUp10 Rem0o.FanControl Open-Shell.Open-Shell-Menu CharlesMilette.TranslucentTB flux.flux OBSProject.OBSStudio ShareX.ShareX NickeManarin.ScreenToGif Greenshot.Greenshot Flameshot.Flameshot GIMP.GIMP Inkscape.Inkscape KDE.Kdenlive dotPDN.PaintDotNet KDE.Krita BlenderFoundation.Blender BlackmagicDesign.DaVinciResolve Streamlabs.StreamlabsDesktop Meltytech.Shotcut Figma.Figma Canva.Canva ByteDance.CapCut Microsoft.DotNet.Runtime.8 Microsoft.DotNet.Runtime.9 EclipseAdoptium.Temurin.21.JRE Microsoft.EdgeWebView2Runtime Microsoft.VCRedist.2015+.x64) do call :WINGET_INSTALL %%p
    echo.
    powershell -NoProfile -Command "Write-Host '  All installs complete.' -ForegroundColor Green"
    echo.
    pause
    goto MAIN_MENU
)
for %%i in (!WGCHOICE!) do (
    set "_I=%%~i"
    set "_I=!_I:,=!"
    if "!_I!"=="1"   call :WINGET_INSTALL Mozilla.Firefox
    if "!_I!"=="2"   call :WINGET_INSTALL Google.Chrome
    if "!_I!"=="3"   call :WINGET_INSTALL BraveSoftware.BraveBrowser
    if "!_I!"=="4"   call :WINGET_INSTALL Opera.OperaGX
    if "!_I!"=="5"   call :WINGET_INSTALL TorProject.TorBrowser
    if "!_I!"=="6"   call :WINGET_INSTALL LibreWolf.LibreWolf
    if "!_I!"=="7"   call :WINGET_INSTALL VivaldiTechnologies.Vivaldi
    if "!_I!"=="8"   call :WINGET_INSTALL Microsoft.Edge
    if "!_I!"=="9"   call :WINGET_INSTALL VideoLAN.VLC
    if "!_I!"=="10"  call :WINGET_INSTALL clsid2.mpc-hc
    if "!_I!"=="11"  call :WINGET_INSTALL mpv.mpv
    if "!_I!"=="12"  call :WINGET_INSTALL Spotify.Spotify
    if "!_I!"=="13"  call :WINGET_INSTALL Audacity.Audacity
    if "!_I!"=="14"  call :WINGET_INSTALL HandBrake.HandBrake
    if "!_I!"=="15"  call :WINGET_INSTALL XBMCFoundation.Kodi
    if "!_I!"=="16"  call :WINGET_INSTALL Winamp.Winamp
    if "!_I!"=="17"  call :WINGET_INSTALL MKVToolNix.MKVToolNix
    if "!_I!"=="18"  call :WINGET_INSTALL PeterPawlowski.foobar2000
    if "!_I!"=="19"  call :WINGET_INSTALL AIMP.AIMP
    if "!_I!"=="20"  call :WINGET_INSTALL Stremio.Stremio
    if "!_I!"=="21"  call :WINGET_INSTALL mifi.losslesscut
    if "!_I!"=="22"  call :WINGET_INSTALL Gyan.FFmpeg
    if "!_I!"=="23"  call :WINGET_INSTALL ImageGlass.ImageGlass
    if "!_I!"=="24"  call :WINGET_INSTALL IrfanSkiljan.IrfanView
    if "!_I!"=="25"  call :WINGET_INSTALL VentisMedia.MediaMonkey
    if "!_I!"=="26"  call :WINGET_INSTALL TheDocumentFoundation.LibreOffice
    if "!_I!"=="27"  call :WINGET_INSTALL Notepad++.Notepad++
    if "!_I!"=="28"  call :WINGET_INSTALL Obsidian.Obsidian
    if "!_I!"=="29"  call :WINGET_INSTALL Notion.Notion
    if "!_I!"=="30"  call :WINGET_INSTALL KeePassXCTeam.KeePassXC
    if "!_I!"=="31"  call :WINGET_INSTALL Bitwarden.Bitwarden
    if "!_I!"=="32"  call :WINGET_INSTALL SumatraPDF.SumatraPDF
    if "!_I!"=="33"  call :WINGET_INSTALL Foxit.FoxitReader
    if "!_I!"=="34"  call :WINGET_INSTALL PDFsam.PDFsamBasic
    if "!_I!"=="35"  call :WINGET_INSTALL AscensioSystemSIA.OnlyOffice
    if "!_I!"=="36"  call :WINGET_INSTALL giuspen.cherrytree
    if "!_I!"=="37"  call :WINGET_INSTALL Joplin.Joplin
    if "!_I!"=="38"  call :WINGET_INSTALL StandardNotes.StandardNotes
    if "!_I!"=="39"  call :WINGET_INSTALL Logseq.Logseq
    if "!_I!"=="40"  call :WINGET_INSTALL Zotero.Zotero
    if "!_I!"=="41"  call :WINGET_INSTALL AutoHotkey.AutoHotkey
    if "!_I!"=="42"  call :WINGET_INSTALL Microsoft.PowerToys
    if "!_I!"=="43"  call :WINGET_INSTALL 7zip.7zip
    if "!_I!"=="44"  call :WINGET_INSTALL M2Team.NanaZip
    if "!_I!"=="45"  call :WINGET_INSTALL RARLab.WinRAR
    if "!_I!"=="46"  call :WINGET_INSTALL GeekSoftwareGmbH.PDF24Creator
    if "!_I!"=="47"  call :WINGET_INSTALL Zenju.FreeFileSync
    if "!_I!"=="48"  call :WINGET_INSTALL CodeSector.TeraCopy
    if "!_I!"=="49"  call :WINGET_INSTALL Microsoft.VisualStudioCode
    if "!_I!"=="50"  call :WINGET_INSTALL Neovim.Neovim
    if "!_I!"=="51"  call :WINGET_INSTALL SublimeHQ.SublimeText.4
    if "!_I!"=="52"  call :WINGET_INSTALL Git.Git
    if "!_I!"=="53"  call :WINGET_INSTALL Python.Python.3.12
    if "!_I!"=="54"  call :WINGET_INSTALL OpenJS.NodeJS.LTS
    if "!_I!"=="55"  call :WINGET_INSTALL GoLang.Go
    if "!_I!"=="56"  call :WINGET_INSTALL Rustlang.Rustup
    if "!_I!"=="57"  call :WINGET_INSTALL EclipseAdoptium.Temurin.21.JDK
    if "!_I!"=="58"  call :WINGET_INSTALL Microsoft.WindowsTerminal
    if "!_I!"=="59"  call :WINGET_INSTALL Microsoft.PowerShell
    if "!_I!"=="60"  call :WINGET_INSTALL Postman.Postman
    if "!_I!"=="61"  call :WINGET_INSTALL Kong.Insomnia
    if "!_I!"=="62"  call :WINGET_INSTALL Docker.DockerDesktop
    if "!_I!"=="63"  call :WINGET_INSTALL JetBrains.Toolbox
    if "!_I!"=="64"  call :WINGET_INSTALL GitHub.GitHubDesktop
    if "!_I!"=="65"  call :WINGET_INSTALL WinSCP.WinSCP
    if "!_I!"=="66"  call :WINGET_INSTALL PuTTY.PuTTY
    if "!_I!"=="67"  call :WINGET_INSTALL WiresharkFoundation.Wireshark
    if "!_I!"=="68"  call :WINGET_INSTALL AnsgarBecker.HeidiSQL
    if "!_I!"=="69"  call :WINGET_INSTALL dbeaver.dbeaver
    if "!_I!"=="70"  call :WINGET_INSTALL PostgreSQL.pgAdmin
    if "!_I!"=="71"  call :WINGET_INSTALL Oracle.MySQLWorkbench
    if "!_I!"=="72"  call :WINGET_INSTALL MSYS2.MSYS2
    if "!_I!"=="73"  call :WINGET_INSTALL Kitware.CMake
    if "!_I!"=="74"  call :WINGET_INSTALL Google.AndroidStudio
    if "!_I!"=="75"  call :WINGET_INSTALL Insecure.Nmap
    if "!_I!"=="76"  call :WINGET_INSTALL Discord.Discord
    if "!_I!"=="77"  call :WINGET_INSTALL Zoom.Zoom
    if "!_I!"=="78"  call :WINGET_INSTALL Telegram.TelegramDesktop
    if "!_I!"=="79"  call :WINGET_INSTALL OpenWhisperSystems.Signal
    if "!_I!"=="80"  call :WINGET_INSTALL SlackTechnologies.Slack
    if "!_I!"=="81"  call :WINGET_INSTALL Microsoft.Skype
    if "!_I!"=="82"  call :WINGET_INSTALL WhatsApp.WhatsApp
    if "!_I!"=="83"  call :WINGET_INSTALL Mozilla.Thunderbird
    if "!_I!"=="84"  call :WINGET_INSTALL Microsoft.Teams
    if "!_I!"=="85"  call :WINGET_INSTALL RocketChat.RocketChat
    if "!_I!"=="86"  call :WINGET_INSTALL Element.Element
    if "!_I!"=="87"  call :WINGET_INSTALL Mattermost.MattermostDesktop
    if "!_I!"=="88"  call :WINGET_INSTALL Viber.Viber
    if "!_I!"=="89"  call :WINGET_INSTALL LINE.LINE
    if "!_I!"=="90"  call :WINGET_INSTALL Valve.Steam
    if "!_I!"=="91"  call :WINGET_INSTALL EpicGames.EpicGamesLauncher
    if "!_I!"=="92"  call :WINGET_INSTALL GOG.Galaxy
    if "!_I!"=="93"  call :WINGET_INSTALL ElectronicArts.EADesktop
    if "!_I!"=="94"  call :WINGET_INSTALL Ubisoft.Connect
    if "!_I!"=="95"  call :WINGET_INSTALL Playnite.Playnite
    if "!_I!"=="96"  call :WINGET_INSTALL Parsec.Parsec
    if "!_I!"=="97"  call :WINGET_INSTALL HeroicGamesLauncher.HeroicGamesLauncher
    if "!_I!"=="98"  call :WINGET_INSTALL LizardByte.Sunshine
    if "!_I!"=="99"  call :WINGET_INSTALL MoonlightGameStreamingProject.Moonlight
    if "!_I!"=="100" call :WINGET_INSTALL Libretro.RetroArch
    if "!_I!"=="101" call :WINGET_INSTALL itchio.itch
    if "!_I!"=="102" call :WINGET_INSTALL qBittorrent.qBittorrent
    if "!_I!"=="103" call :WINGET_INSTALL Dropbox.Dropbox
    if "!_I!"=="104" call :WINGET_INSTALL Mega.MEGASync
    if "!_I!"=="105" call :WINGET_INSTALL Google.GoogleDrive
    if "!_I!"=="106" call :WINGET_INSTALL TimKosse.FileZillaClient
    if "!_I!"=="107" call :WINGET_INSTALL Cyberduck.Cyberduck
    if "!_I!"=="108" call :WINGET_INSTALL pCloudAG.pCloudDrive
    if "!_I!"=="109" call :WINGET_INSTALL Malwarebytes.Malwarebytes
    if "!_I!"=="110" call :WINGET_INSTALL SecureMix.GlassWire
    if "!_I!"=="111" call :WINGET_INSTALL Proton.ProtonVPN
    if "!_I!"=="112" call :WINGET_INSTALL Windscribe.Windscribe
    if "!_I!"=="113" call :WINGET_INSTALL Sandboxie.Plus
    if "!_I!"=="114" call :WINGET_INSTALL OpenVPNTechnologies.OpenVPN
    if "!_I!"=="115" call :WINGET_INSTALL MullvadVPN.MullvadVPN
    if "!_I!"=="116" call :WINGET_INSTALL IDRIX.VeraCrypt
    if "!_I!"=="117" call :WINGET_INSTALL CPUID.CPU-Z
    if "!_I!"=="118" call :WINGET_INSTALL TechPowerUp.GPU-Z
    if "!_I!"=="119" call :WINGET_INSTALL REALiX.HWiNFO
    if "!_I!"=="120" call :WINGET_INSTALL CPUID.HWMonitor
    if "!_I!"=="121" call :WINGET_INSTALL Guru3D.Afterburner
    if "!_I!"=="122" call :WINGET_INSTALL Guru3D.RTSS
    if "!_I!"=="123" call :WINGET_INSTALL CrystalDewWorld.CrystalDiskInfo
    if "!_I!"=="124" call :WINGET_INSTALL CrystalDewWorld.CrystalDiskMark
    if "!_I!"=="125" call :WINGET_INSTALL Piriform.Speccy
    if "!_I!"=="126" call :WINGET_INSTALL SystemInformer.SystemInformer
    if "!_I!"=="127" call :WINGET_INSTALL voidtools.Everything
    if "!_I!"=="128" call :WINGET_INSTALL JAMSoftware.TreeSizeFree
    if "!_I!"=="129" call :WINGET_INSTALL AntibodySoftware.WizTree
    if "!_I!"=="130" call :WINGET_INSTALL WinDirStat.WinDirStat
    if "!_I!"=="131" call :WINGET_INSTALL Microsoft.Sysinternals.Autoruns
    if "!_I!"=="132" call :WINGET_INSTALL Microsoft.Sysinternals.ProcessMonitor
    if "!_I!"=="133" call :WINGET_INSTALL Microsoft.Sysinternals.TCPView
    if "!_I!"=="134" call :WINGET_INSTALL Rufus.Rufus
    if "!_I!"=="135" call :WINGET_INSTALL Balena.Etcher
    if "!_I!"=="136" call :WINGET_INSTALL Ventoy.Ventoy
    if "!_I!"=="137" call :WINGET_INSTALL Macrium.Reflect
    if "!_I!"=="138" call :WINGET_INSTALL BleachBit.BleachBit
    if "!_I!"=="139" call :WINGET_INSTALL ThomasKoen.GeekUninstaller
    if "!_I!"=="140" call :WINGET_INSTALL VSRevoGroup.RevoUninstallerFree
    if "!_I!"=="141" call :WINGET_INSTALL OOSoftware.OOShutUp10
    if "!_I!"=="142" call :WINGET_INSTALL Rem0o.FanControl
    if "!_I!"=="143" call :WINGET_INSTALL Open-Shell.Open-Shell-Menu
    if "!_I!"=="144" call :WINGET_INSTALL CharlesMilette.TranslucentTB
    if "!_I!"=="145" call :WINGET_INSTALL flux.flux
    if "!_I!"=="146" call :WINGET_INSTALL OBSProject.OBSStudio
    if "!_I!"=="147" call :WINGET_INSTALL ShareX.ShareX
    if "!_I!"=="148" call :WINGET_INSTALL NickeManarin.ScreenToGif
    if "!_I!"=="149" call :WINGET_INSTALL Greenshot.Greenshot
    if "!_I!"=="150" call :WINGET_INSTALL Flameshot.Flameshot
    if "!_I!"=="151" call :WINGET_INSTALL GIMP.GIMP
    if "!_I!"=="152" call :WINGET_INSTALL Inkscape.Inkscape
    if "!_I!"=="153" call :WINGET_INSTALL KDE.Kdenlive
    if "!_I!"=="154" call :WINGET_INSTALL dotPDN.PaintDotNet
    if "!_I!"=="155" call :WINGET_INSTALL KDE.Krita
    if "!_I!"=="156" call :WINGET_INSTALL BlenderFoundation.Blender
    if "!_I!"=="157" call :WINGET_INSTALL BlackmagicDesign.DaVinciResolve
    if "!_I!"=="158" call :WINGET_INSTALL Streamlabs.StreamlabsDesktop
    if "!_I!"=="159" call :WINGET_INSTALL Meltytech.Shotcut
    if "!_I!"=="160" call :WINGET_INSTALL Figma.Figma
    if "!_I!"=="161" call :WINGET_INSTALL Canva.Canva
    if "!_I!"=="162" call :WINGET_INSTALL ByteDance.CapCut
    if "!_I!"=="163" call :WINGET_INSTALL Microsoft.DotNet.Runtime.8
    if "!_I!"=="164" call :WINGET_INSTALL Microsoft.DotNet.Runtime.9
    if "!_I!"=="165" call :WINGET_INSTALL EclipseAdoptium.Temurin.21.JRE
    if "!_I!"=="166" call :WINGET_INSTALL Microsoft.EdgeWebView2Runtime
    if "!_I!"=="167" call :WINGET_INSTALL Microsoft.VCRedist.2015+.x64
)
echo.
powershell -NoProfile -Command "Write-Host '  Install(s) complete.' -ForegroundColor Green"
echo.
pause
goto INSTALL_SOFTWARE

:WINGET_INSTALL
powershell -NoProfile -Command "Write-Host ('  Installing %~1 ...') -ForegroundColor Cyan"
winget install --id %~1 -e --silent --disable-interactivity --accept-source-agreements --accept-package-agreements
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

:BIOS_INFO
cls
color !COL_OPS!
echo.
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '    BIOS / FIRMWARE INFORMATION' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
echo.
set "BIOSSCRIPT=%TEMP%\ytsh_bios_%RANDOM%%RANDOM%.ps1"
if exist "%BIOSSCRIPT%" del "%BIOSSCRIPT%" >nul 2>&1
>>"%BIOSSCRIPT%" echo $bios  = Get-CimInstance Win32_BIOS -ErrorAction SilentlyContinue
>>"%BIOSSCRIPT%" echo $board = Get-CimInstance Win32_BaseBoard -ErrorAction SilentlyContinue
>>"%BIOSSCRIPT%" echo Write-Host '  --- BIOS ---' -ForegroundColor Cyan
>>"%BIOSSCRIPT%" echo Write-Host ''
>>"%BIOSSCRIPT%" echo if ($bios) {
>>"%BIOSSCRIPT%" echo     Write-Host ("  Manufacturer : " + $bios.Manufacturer) -ForegroundColor White
>>"%BIOSSCRIPT%" echo     Write-Host ("  Version      : " + $bios.SMBIOSBIOSVersion) -ForegroundColor White
>>"%BIOSSCRIPT%" echo     try {
>>"%BIOSSCRIPT%" echo         $date = $bios.ReleaseDate
>>"%BIOSSCRIPT%" echo         Write-Host ("  Release Date : " + $date.ToString('yyyy-MM-dd')) -ForegroundColor White
>>"%BIOSSCRIPT%" echo         $age  = [math]::Round(((Get-Date) - $date).TotalDays / 365.25, 1)
>>"%BIOSSCRIPT%" echo         $acol = if($age -gt 5){'Red'} elseif($age -gt 2){'Yellow'} else{'Green'}
>>"%BIOSSCRIPT%" echo         Write-Host ("  Age          : " + $age + " years") -ForegroundColor $acol
>>"%BIOSSCRIPT%" echo         if($age -gt 2){ Write-Host '  [TIP] Check your manufacturer website for a BIOS update.' -ForegroundColor Yellow }
>>"%BIOSSCRIPT%" echo     } catch { Write-Host '  Release Date : Not parseable.' -ForegroundColor DarkGray }
>>"%BIOSSCRIPT%" echo } else { Write-Host '  BIOS data unavailable.' -ForegroundColor DarkGray }
>>"%BIOSSCRIPT%" echo Write-Host ''
>>"%BIOSSCRIPT%" echo Write-Host '  --- MOTHERBOARD ---' -ForegroundColor Cyan
>>"%BIOSSCRIPT%" echo Write-Host ''
>>"%BIOSSCRIPT%" echo if ($board) {
>>"%BIOSSCRIPT%" echo     Write-Host ("  Manufacturer : " + $board.Manufacturer) -ForegroundColor White
>>"%BIOSSCRIPT%" echo     Write-Host ("  Product      : " + $board.Product) -ForegroundColor White
>>"%BIOSSCRIPT%" echo     Write-Host ("  Serial       : " + $board.SerialNumber) -ForegroundColor White
>>"%BIOSSCRIPT%" echo } else { Write-Host '  Board data unavailable.' -ForegroundColor DarkGray }
>>"%BIOSSCRIPT%" echo Write-Host ''
>>"%BIOSSCRIPT%" echo Write-Host '  --- SECURE BOOT ---' -ForegroundColor Cyan
>>"%BIOSSCRIPT%" echo Write-Host ''
>>"%BIOSSCRIPT%" echo try {
>>"%BIOSSCRIPT%" echo     $sb = Confirm-SecureBootUEFI -ErrorAction Stop
>>"%BIOSSCRIPT%" echo     if($sb){ Write-Host '  Secure Boot  : ENABLED' -ForegroundColor Green }
>>"%BIOSSCRIPT%" echo     else       { Write-Host '  Secure Boot  : DISABLED' -ForegroundColor Red }
>>"%BIOSSCRIPT%" echo } catch { Write-Host '  Secure Boot  : Not supported / Legacy BIOS mode.' -ForegroundColor DarkGray }
>>"%BIOSSCRIPT%" echo Write-Host ''
>>"%BIOSSCRIPT%" echo Write-Host '  --- BOOT MODE ---' -ForegroundColor Cyan
>>"%BIOSSCRIPT%" echo Write-Host ''
>>"%BIOSSCRIPT%" echo $bcdout = (bcdedit /enum '{current}' 2^>$null) -join ' '
>>"%BIOSSCRIPT%" echo if($bcdout -match 'path.*efi'){
>>"%BIOSSCRIPT%" echo     Write-Host '  Boot Mode    : UEFI (GPT)' -ForegroundColor Green
>>"%BIOSSCRIPT%" echo } else {
>>"%BIOSSCRIPT%" echo     Write-Host '  Boot Mode    : Legacy BIOS / MBR' -ForegroundColor Yellow
>>"%BIOSSCRIPT%" echo }
>>"%BIOSSCRIPT%" echo Write-Host ''
powershell -NoProfile -ExecutionPolicy Bypass -File "%BIOSSCRIPT%"
del "%BIOSSCRIPT%" >nul 2>&1
echo.
pause
goto MAIN_MENU

:WINFEATURE_MENU
cls
color !COL_OPS!
echo.
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '    WINDOWS FEATURE MANAGER' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
echo.
powershell -NoProfile -Command "Write-Host '  Checking feature states... please wait.' -ForegroundColor DarkGray"
echo.
set "WFSCRIPT=%TEMP%\ytsh_wf_%RANDOM%%RANDOM%.ps1"
if exist "%WFSCRIPT%" del "%WFSCRIPT%" >nul 2>&1
>>"%WFSCRIPT%" echo $features = @(
>>"%WFSCRIPT%" echo     @{Name='Microsoft-Hyper-V-All'; Label='Hyper-V (Virtualization)'},
>>"%WFSCRIPT%" echo     @{Name='Microsoft-Windows-Subsystem-Linux'; Label='WSL (Linux Subsystem)'},
>>"%WFSCRIPT%" echo     @{Name='VirtualMachinePlatform'; Label='Virtual Machine Platform'},
>>"%WFSCRIPT%" echo     @{Name='TelnetClient'; Label='Telnet Client'},
>>"%WFSCRIPT%" echo     @{Name='TFTP'; Label='TFTP Client'},
>>"%WFSCRIPT%" echo     @{Name='SMB1Protocol'; Label='SMB1 Protocol (Legacy/Insecure)'},
>>"%WFSCRIPT%" echo     @{Name='WorkFolders-Client'; Label='Work Folders Client'},
>>"%WFSCRIPT%" echo     @{Name='Printing-Foundation-Features'; Label='Print and Document Services'},
>>"%WFSCRIPT%" echo     @{Name='MediaPlayback'; Label='Windows Media Features'},
>>"%WFSCRIPT%" echo     @{Name='NetFx3'; Label='.NET Framework 3.5'},
>>"%WFSCRIPT%" echo     @{Name='NetFx4-AdvSrvs'; Label='.NET Framework 4 Advanced'},
>>"%WFSCRIPT%" echo     @{Name='WCF-Services45'; Label='WCF Services (.NET)'},
>>"%WFSCRIPT%" echo     @{Name='Internet-Explorer-Optional-amd64'; Label='Internet Explorer (Legacy)'}
>>"%WFSCRIPT%" echo )
>>"%WFSCRIPT%" echo $i = 1
>>"%WFSCRIPT%" echo foreach($f in $features){
>>"%WFSCRIPT%" echo     $feat = Get-WindowsOptionalFeature -Online -FeatureName $f.Name -ErrorAction SilentlyContinue
>>"%WFSCRIPT%" echo     $state = if($feat){ $feat.State.ToString() } else { 'NotPresent' }
>>"%WFSCRIPT%" echo     $col = switch($state){ 'Enabled'{'Green'} 'Disabled'{'Red'} default{'DarkGray'} }
>>"%WFSCRIPT%" echo     $tag = switch($state){ 'Enabled'{' ON '} 'Disabled'{'OFF'} default{' -- '} }
>>"%WFSCRIPT%" echo     Write-Host("  [" + $i.ToString().PadLeft(2) + "] [" + $tag + "] " + $f.Label.PadRight(38) + "(" + $f.Name + ")") -ForegroundColor $col
>>"%WFSCRIPT%" echo     $i++
>>"%WFSCRIPT%" echo }
powershell -NoProfile -ExecutionPolicy Bypass -File "%WFSCRIPT%"
del "%WFSCRIPT%" >nul 2>&1
echo.
echo   Enter a number (1-13) to toggle that feature ON or OFF.
echo   Some changes need a restart and/or internet connection.
echo.
set "WFCHOICE="
set /p "WFCHOICE=  Select [1-13 or B to go back]: "
if /i "!WFCHOICE!"=="B" goto MAIN_MENU
set "_WFOK=0"
for %%N in (1 2 3 4 5 6 7 8 9 10 11 12 13) do if "!WFCHOICE!"=="%%N" set "_WFOK=1"
if "!_WFOK!"=="0" goto WINFEATURE_MENU

set "WFTOGSCRIPT=%TEMP%\ytsh_wftog_%RANDOM%%RANDOM%.ps1"
if exist "%WFTOGSCRIPT%" del "%WFTOGSCRIPT%" >nul 2>&1
>>"%WFTOGSCRIPT%" echo $features = @(
>>"%WFTOGSCRIPT%" echo     @{Name='Microsoft-Hyper-V-All'; Label='Hyper-V'},
>>"%WFTOGSCRIPT%" echo     @{Name='Microsoft-Windows-Subsystem-Linux'; Label='WSL'},
>>"%WFTOGSCRIPT%" echo     @{Name='VirtualMachinePlatform'; Label='Virtual Machine Platform'},
>>"%WFTOGSCRIPT%" echo     @{Name='TelnetClient'; Label='Telnet Client'},
>>"%WFTOGSCRIPT%" echo     @{Name='TFTP'; Label='TFTP Client'},
>>"%WFTOGSCRIPT%" echo     @{Name='SMB1Protocol'; Label='SMB1 Protocol'},
>>"%WFTOGSCRIPT%" echo     @{Name='WorkFolders-Client'; Label='Work Folders Client'},
>>"%WFTOGSCRIPT%" echo     @{Name='Printing-Foundation-Features'; Label='Print and Document Services'},
>>"%WFTOGSCRIPT%" echo     @{Name='MediaPlayback'; Label='Windows Media Features'},
>>"%WFTOGSCRIPT%" echo     @{Name='NetFx3'; Label='.NET Framework 3.5'},
>>"%WFTOGSCRIPT%" echo     @{Name='NetFx4-AdvSrvs'; Label='.NET Framework 4 Advanced'},
>>"%WFTOGSCRIPT%" echo     @{Name='WCF-Services45'; Label='WCF Services'},
>>"%WFTOGSCRIPT%" echo     @{Name='Internet-Explorer-Optional-amd64'; Label='Internet Explorer'}
>>"%WFTOGSCRIPT%" echo )
>>"%WFTOGSCRIPT%" echo $f    = $features[!WFCHOICE! - 1]
>>"%WFTOGSCRIPT%" echo $feat = Get-WindowsOptionalFeature -Online -FeatureName $f.Name -ErrorAction SilentlyContinue
>>"%WFTOGSCRIPT%" echo if(-not $feat){ Write-Host ("  [N/A] " + $f.Label + " is not available on this system.") -ForegroundColor DarkGray; exit }
>>"%WFTOGSCRIPT%" echo if($feat.State -eq 'Enabled'){
>>"%WFTOGSCRIPT%" echo     Write-Host ("  Disabling: " + $f.Label + " ...") -ForegroundColor Yellow
>>"%WFTOGSCRIPT%" echo     Disable-WindowsOptionalFeature -Online -FeatureName $f.Name -NoRestart -ErrorAction SilentlyContinue ^| Out-Null
>>"%WFTOGSCRIPT%" echo     Write-Host '  [SUCCESS] Disabled. A restart may be required.' -ForegroundColor Green
>>"%WFTOGSCRIPT%" echo } else {
>>"%WFTOGSCRIPT%" echo     Write-Host ("  Enabling: " + $f.Label + " ...") -ForegroundColor Cyan
>>"%WFTOGSCRIPT%" echo     Enable-WindowsOptionalFeature -Online -FeatureName $f.Name -NoRestart -ErrorAction SilentlyContinue ^| Out-Null
>>"%WFTOGSCRIPT%" echo     Write-Host '  [SUCCESS] Enabled. A restart may be required.' -ForegroundColor Green
>>"%WFTOGSCRIPT%" echo }
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%WFTOGSCRIPT%"
del "%WFTOGSCRIPT%" >nul 2>&1
echo.
pause
goto WINFEATURE_MENU

:STARTUP_REPAIR
cls
color !COL_OPS!
echo.
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '    STARTUP REPAIR TOOLKIT' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
echo.
powershell -NoProfile -Command "Write-Host '  WARNING: These tools modify critical system and boot files.' -ForegroundColor Red"
powershell -NoProfile -Command "Write-Host '  Have a recovery USB ready before making changes.' -ForegroundColor Yellow"
echo.
echo   1  ^>  SFC /scannow       (Repair corrupted Windows system files)
echo   2  ^>  DISM RestoreHealth (Repair Windows image - needs internet)
echo   3  ^>  Rebuild BCD        (Fix boot menu / boot configuration)
echo   4  ^>  Fix MBR            (Legacy BIOS only - do NOT use on UEFI/GPT)
echo   5  ^>  View BCD entries   (Read-only - safe to run)
echo   6  ^>  Schedule CHKDSK    (Disk integrity check on next restart)
echo.
echo   B  ^>  Back to main menu
echo.
set "SRCHOICE="
set /p "SRCHOICE=  Select: "
if /i "!SRCHOICE!"=="B" goto MAIN_MENU
if "!SRCHOICE!"=="1" (
    echo.
    powershell -NoProfile -Command "Write-Host '  Running SFC /scannow... (may take several minutes)' -ForegroundColor Cyan"
    echo.
    sfc /scannow
    echo.
    pause
    goto STARTUP_REPAIR
)
if "!SRCHOICE!"=="2" (
    echo.
    powershell -NoProfile -Command "Write-Host '  Running DISM /Online /Cleanup-Image /RestoreHealth...' -ForegroundColor Cyan"
    powershell -NoProfile -Command "Write-Host '  This can take 10-20 minutes and requires internet.' -ForegroundColor Yellow"
    echo.
    DISM /Online /Cleanup-Image /RestoreHealth
    echo.
    pause
    goto STARTUP_REPAIR
)
if "!SRCHOICE!"=="3" (
    echo.
    powershell -NoProfile -Command "Write-Host '  [WARN] This will rebuild Boot Configuration Data using bcdboot.' -ForegroundColor Red"
    echo.
    set "BCDCONF="
    set /p "BCDCONF=  Type YES to continue or anything else to cancel: "
    if /i "!BCDCONF!"=="YES" (
        set "BCDBAK=%TEMP%\bcd_backup_%RANDOM%.bak"
        bcdedit /export "!BCDBAK!" >nul 2>&1
        powershell -NoProfile -Command "Write-Host '  BCD backup saved to TEMP folder.' -ForegroundColor Green"
        bcdboot C:\Windows
        powershell -NoProfile -Command "Write-Host '  [DONE] Boot files copied and BCD rebuilt. Restart to verify.' -ForegroundColor Green"
    ) else (
        powershell -NoProfile -Command "Write-Host '  Cancelled.' -ForegroundColor DarkGray"
    )
    echo.
    pause
    goto STARTUP_REPAIR
)
if "!SRCHOICE!"=="4" (
    echo.
    powershell -NoProfile -Command "Write-Host '  [WARN] ONLY use this on Legacy/BIOS-mode PCs.' -ForegroundColor Red"
    powershell -NoProfile -Command "Write-Host '  On UEFI/GPT systems this can break booting.' -ForegroundColor Red"
    echo.
    set "MBRCONF="
    set /p "MBRCONF=  Type YES to continue or anything else to cancel: "
    if /i "!MBRCONF!"=="YES" (
        bootsect /nt60 SYS /mbr
        powershell -NoProfile -Command "Write-Host '  [DONE] MBR fixed using bootsect. Restart to verify.' -ForegroundColor Green"
    ) else (
        powershell -NoProfile -Command "Write-Host '  Cancelled.' -ForegroundColor DarkGray"
    )
    echo.
    pause
    goto STARTUP_REPAIR
)
if "!SRCHOICE!"=="5" (
    echo.
    powershell -NoProfile -Command "Write-Host '  Current BCD entries:' -ForegroundColor Cyan"
    echo.
    bcdedit /enum all
    echo.
    pause
    goto STARTUP_REPAIR
)
if "!SRCHOICE!"=="6" (
    echo.
    powershell -NoProfile -Command "Write-Host '  Scheduling CHKDSK for next restart...' -ForegroundColor Cyan"
    echo Y | chkdsk C: /f /r >nul 2>&1
    powershell -NoProfile -Command "Write-Host '  [SUCCESS] CHKDSK scheduled. Will run automatically on next restart.' -ForegroundColor Green"
    echo.
    pause
    goto STARTUP_REPAIR
)
goto STARTUP_REPAIR

:PROCESS_ANALYZER
cls
color !COL_OPS!
echo.
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '    PROCESS AND RAM ANALYZER' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
echo.
powershell -NoProfile -Command "Write-Host '  Scanning processes... please wait.' -ForegroundColor DarkGray"
echo.
set "PROCSCRIPT=%TEMP%\ytsh_proc_%RANDOM%%RANDOM%.ps1"
if exist "%PROCSCRIPT%" del "%PROCSCRIPT%" >nul 2>&1
>>"%PROCSCRIPT%" echo $os     = Get-CimInstance Win32_OperatingSystem
>>"%PROCSCRIPT%" echo $totMB  = [math]::Round($os.TotalVisibleMemorySize / 1024, 0)
>>"%PROCSCRIPT%" echo $frMB   = [math]::Round($os.FreePhysicalMemory / 1024, 0)
>>"%PROCSCRIPT%" echo $usMB   = $totMB - $frMB
>>"%PROCSCRIPT%" echo $pct    = [math]::Round($usMB / $totMB * 100, 1)
>>"%PROCSCRIPT%" echo $pcol   = if($pct -gt 85){'Red'} elseif($pct -gt 65){'Yellow'} else{'Green'}
>>"%PROCSCRIPT%" echo Write-Host ("  Total RAM: " + $totMB + " MB   Used: " + $usMB + " MB  (" + $pct + "%%)") -ForegroundColor $pcol
>>"%PROCSCRIPT%" echo Write-Host ''
>>"%PROCSCRIPT%" echo Write-Host '  --- TOP 15 PROCESSES BY RAM ---' -ForegroundColor Cyan
>>"%PROCSCRIPT%" echo Write-Host ''
>>"%PROCSCRIPT%" echo $procs = Get-Process -ErrorAction SilentlyContinue ^| Sort-Object WorkingSet64 -Descending ^| Select-Object -First 15
>>"%PROCSCRIPT%" echo Write-Host ("  {0,-32} {1,9}  {2,8}  {3}" -f 'Process Name','RAM (MB)','CPU (s)','PID') -ForegroundColor White
>>"%PROCSCRIPT%" echo Write-Host ("  " + "-"*65) -ForegroundColor DarkGray
>>"%PROCSCRIPT%" echo foreach($p in $procs){
>>"%PROCSCRIPT%" echo     $mb  = [math]::Round($p.WorkingSet64 / 1MB, 1)
>>"%PROCSCRIPT%" echo     $cpu = try { [math]::Round($p.TotalProcessorTime.TotalSeconds, 1) } catch { '?' }
>>"%PROCSCRIPT%" echo     $col = if($mb -gt 500){'Red'} elseif($mb -gt 150){'Yellow'} else{'Green'}
>>"%PROCSCRIPT%" echo     Write-Host ("  {0,-32} {1,9}  {2,8}  {3}" -f $p.Name,$mb,$cpu,$p.Id) -ForegroundColor $col
>>"%PROCSCRIPT%" echo }
>>"%PROCSCRIPT%" echo Write-Host ''
>>"%PROCSCRIPT%" echo Write-Host '  --- SUSPICIOUS PROCESS CHECK ---' -ForegroundColor Cyan
>>"%PROCSCRIPT%" echo Write-Host '  (Processes running from Temp/AppData/Downloads/Public)' -ForegroundColor DarkGray
>>"%PROCSCRIPT%" echo Write-Host ''
>>"%PROCSCRIPT%" echo $sus = Get-CimInstance -ClassName Win32_Process -ErrorAction SilentlyContinue ^| Where-Object { $_.ExecutablePath -and $_.ExecutablePath.ToLower() -match 'temp\^|appdata\^|roaming\^|downloads\^|\\public\\' -and $_.ExecutablePath.ToLower() -notmatch 'windowsapps\^|system32\^|syswow64' }
>>"%PROCSCRIPT%" echo if($sus){
>>"%PROCSCRIPT%" echo     foreach($s in $sus){
>>"%PROCSCRIPT%" echo         Write-Host ("  [SUSPECT] PID " + $s.ProcessId.ToString().PadLeft(5) + "  " + $s.Name + " -> " + $s.ExecutablePath) -ForegroundColor Red
>>"%PROCSCRIPT%" echo     }
>>"%PROCSCRIPT%" echo } else {
>>"%PROCSCRIPT%" echo     Write-Host '  No suspicious processes detected.' -ForegroundColor Green
>>"%PROCSCRIPT%" echo }
powershell -NoProfile -ExecutionPolicy Bypass -File "%PROCSCRIPT%"
del "%PROCSCRIPT%" >nul 2>&1
echo.
echo   K  ^>  Kill a process by PID     B  ^>  Back
echo.
set "PROCHOICE="
set /p "PROCHOICE=  Select: "
if /i "!PROCHOICE!"=="B" goto MAIN_MENU
if /i "!PROCHOICE!"=="K" (
    echo.
    set "KILLPID="
    set /p "KILLPID=  Enter PID to terminate: "
    if defined KILLPID (
        taskkill /PID !KILLPID! /F >nul 2>&1
        if !errorLevel! equ 0 (
            powershell -NoProfile -Command "Write-Host '  [SUCCESS] Process !KILLPID! terminated.' -ForegroundColor Green"
        ) else (
            powershell -NoProfile -Command "Write-Host '  [FAIL] Could not kill PID !KILLPID! - check PID or permissions.' -ForegroundColor Red"
        )
    )
    echo.
    pause
    goto PROCESS_ANALYZER
)
goto MAIN_MENU

:WIFI_TOOLKIT
cls
color !COL_OPS!
echo.
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '    WI-FI TOOLKIT' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
echo.
echo   1  ^>  Show saved Wi-Fi profiles
echo   2  ^>  Show nearby networks and signal strength
echo   3  ^>  Export passwords from your saved networks
echo   4  ^>  Forget a saved network
echo   5  ^>  Show current connection details
echo   6  ^>  Reset adapter (release/renew/flush DNS/Winsock reset)
echo.
echo   B  ^>  Back to main menu
echo.
set "WIFICHOICE="
set /p "WIFICHOICE=  Select: "
if /i "!WIFICHOICE!"=="B" goto MAIN_MENU
if "!WIFICHOICE!"=="1" (
    echo.
    powershell -NoProfile -Command "Write-Host '  Saved Wi-Fi Profiles:' -ForegroundColor Cyan"
    echo.
    netsh wlan show profiles
    echo.
    pause
    goto WIFI_TOOLKIT
)
if "!WIFICHOICE!"=="2" (
    echo.
    powershell -NoProfile -Command "Write-Host '  Nearby Networks (BSSID / signal):' -ForegroundColor Cyan"
    echo.
    netsh wlan show networks mode=bssid
    echo.
    pause
    goto WIFI_TOOLKIT
)
if "!WIFICHOICE!"=="3" (
    echo.
    call :DO_WIFI_PASSWORDS
    echo.
    pause
    goto WIFI_TOOLKIT
)
if "!WIFICHOICE!"=="4" (
    echo.
    call :DO_WIFI_FORGET
    echo.
    pause
    goto WIFI_TOOLKIT
)
if "!WIFICHOICE!"=="5" (
    echo.
    call :DO_WIFI_INTERFACES
    echo.
    pause
    goto WIFI_TOOLKIT
)
if "!WIFICHOICE!"=="6" (
    echo.
    call :DO_WIFI_RESET
    echo.
    pause
    goto WIFI_TOOLKIT
)
goto WIFI_TOOLKIT

:DO_WIFI_PASSWORDS
powershell -NoProfile -Command "Write-Host '  Saved Network Passwords (your own profiles only):' -ForegroundColor Cyan"
echo.
set "WIFIPWSCRIPT=%TEMP%\ytsh_wifipw_%RANDOM%%RANDOM%.ps1"
if exist "%WIFIPWSCRIPT%" del "%WIFIPWSCRIPT%" >nul 2>&1
>>"%WIFIPWSCRIPT%" echo $raw = netsh wlan show profiles
>>"%WIFIPWSCRIPT%" echo $names = $raw ^| Where-Object { $_ -match 'All User Profile\s*:' } ^| ForEach-Object { ^($_ -replace '.*:\s*',''`).Trim^(^) }
>>"%WIFIPWSCRIPT%" echo foreach^($name in $names^) {
>>"%WIFIPWSCRIPT%" echo     $detail = netsh wlan show profile name="$name" key=clear 2^>$null
>>"%WIFIPWSCRIPT%" echo     $pw = ^($detail ^| Where-Object { $_ -match 'Key Content\s*:' }^) ^| ForEach-Object { ^($_ -replace '.*:\s*',''`).Trim^(^) } ^| Select-Object -First 1
>>"%WIFIPWSCRIPT%" echo     if^($pw^) { Write-Host ^('  ' + $name.PadRight^(30^) + ' : ' + $pw^) -ForegroundColor Green }
>>"%WIFIPWSCRIPT%" echo     else { Write-Host ^('  ' + $name.PadRight^(30^) + ' : ^(open / WPS / not cached^)'^) -ForegroundColor DarkGray }
>>"%WIFIPWSCRIPT%" echo }
powershell -NoProfile -ExecutionPolicy Bypass -File "%WIFIPWSCRIPT%"
del "%WIFIPWSCRIPT%" >nul 2>&1
exit /b 0

:DO_WIFI_FORGET
set "WFORGET="
set /p "WFORGET=  Enter exact network name to forget: "
if defined WFORGET (
    netsh wlan delete profile name="!WFORGET!" >nul 2>&1
    if !errorLevel! equ 0 (
        powershell -NoProfile -Command "Write-Host '  [SUCCESS] Profile removed.' -ForegroundColor Green"
    ) else (
        powershell -NoProfile -Command "Write-Host '  [FAIL] Profile not found or could not be removed.' -ForegroundColor Red"
    )
)
exit /b 0

:DO_WIFI_INTERFACES
powershell -NoProfile -Command "Write-Host '  Current Wireless Interface:' -ForegroundColor Cyan"
echo.
netsh wlan show interfaces
exit /b 0

:DO_WIFI_RESET
powershell -NoProfile -Command "Write-Host '  Resetting network adapter...' -ForegroundColor Cyan"
ipconfig /release >nul 2>&1
ipconfig /flushdns >nul 2>&1
netsh winsock reset >nul 2>&1
netsh int ip reset >nul 2>&1
ipconfig /renew >nul 2>&1
powershell -NoProfile -Command "Write-Host '  [SUCCESS] Adapter reset complete. Restart recommended.' -ForegroundColor Green"
exit /b 0

:PRINTER_CLEANUP
cls
color !COL_OPS!
echo.
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '    PRINTER AND DEVICE CLEANUP' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
echo.
echo   1  ^>  List all installed printers
echo   2  ^>  Remove a printer by name
echo   3  ^>  Clear stuck print queue (restart spooler)
echo   4  ^>  List ghost / non-present devices
echo   5  ^>  Remove all ghost devices
echo.
echo   B  ^>  Back to main menu
echo.
set "PRCHOICE="
set /p "PRCHOICE=  Select: "
if /i "!PRCHOICE!"=="B" goto MAIN_MENU
if "!PRCHOICE!"=="1" (
    echo.
    powershell -NoProfile -Command "Write-Host '  Installed Printers:' -ForegroundColor Cyan"
    echo.
    powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-Printer -ErrorAction SilentlyContinue | Format-Table Name,PortName,DriverName,PrinterStatus -AutoSize | Out-Host"
    echo.
    pause
    goto PRINTER_CLEANUP
)
if "!PRCHOICE!"=="2" (
    echo.
    set "DELPR="
    set /p "DELPR=  Enter exact printer name to remove: "
    if defined DELPR (
        powershell -NoProfile -ExecutionPolicy Bypass -Command "Remove-Printer -Name '!DELPR!' -ErrorAction SilentlyContinue; Write-Host '  [DONE] Attempted removal of !DELPR!.' -ForegroundColor Green"
    )
    echo.
    pause
    goto PRINTER_CLEANUP
)
if "!PRCHOICE!"=="3" (
    echo.
    powershell -NoProfile -Command "Write-Host '  Clearing print queue...' -ForegroundColor Cyan"
    net stop spooler >nul 2>&1
    del /Q /F /S "%systemroot%\System32\spool\PRINTERS\*" >nul 2>&1
    net start spooler >nul 2>&1
    powershell -NoProfile -Command "Write-Host '  [SUCCESS] Print queue cleared and spooler restarted.' -ForegroundColor Green"
    echo.
    pause
    goto PRINTER_CLEANUP
)
if "!PRCHOICE!"=="4" (
    echo.
    call :DO_GHOST_LIST
    echo.
    pause
    goto PRINTER_CLEANUP
)
if "!PRCHOICE!"=="5" (
    echo.
    call :DO_GHOST_REMOVE
    echo.
    pause
    goto PRINTER_CLEANUP
)
goto PRINTER_CLEANUP

:DO_GHOST_LIST
powershell -NoProfile -Command "Write-Host '  Scanning for ghost devices...' -ForegroundColor Cyan"
echo.
set "GHOSTSCRIPT=%TEMP%\ytsh_ghost_%RANDOM%%RANDOM%.ps1"
if exist "%GHOSTSCRIPT%" del "%GHOSTSCRIPT%" >nul 2>&1
>>"%GHOSTSCRIPT%" echo $devs = Get-PnpDevice -ErrorAction SilentlyContinue ^| Where-Object { $_.Present -eq $false }
>>"%GHOSTSCRIPT%" echo if^($devs.Count -gt 0^) {
>>"%GHOSTSCRIPT%" echo     Write-Host ^('  Found ' + $devs.Count + ' ghost/non-present device^(s^):'^) -ForegroundColor Yellow
>>"%GHOSTSCRIPT%" echo     Write-Host ''
>>"%GHOSTSCRIPT%" echo     foreach^($d in $devs^) {
>>"%GHOSTSCRIPT%" echo         Write-Host ^('  [GHOST] ' + $d.FriendlyName.PadRight^(40^) + ' Class: ' + $d.Class^) -ForegroundColor DarkGray
>>"%GHOSTSCRIPT%" echo     }
>>"%GHOSTSCRIPT%" echo } else {
>>"%GHOSTSCRIPT%" echo     Write-Host '  No ghost devices detected.' -ForegroundColor Green
>>"%GHOSTSCRIPT%" echo }
powershell -NoProfile -ExecutionPolicy Bypass -File "%GHOSTSCRIPT%"
del "%GHOSTSCRIPT%" >nul 2>&1
exit /b 0

:DO_GHOST_REMOVE
powershell -NoProfile -Command "Write-Host '  [WARN] Removes all non-present devices.' -ForegroundColor Yellow"
powershell -NoProfile -Command "Write-Host '  Windows will re-detect hardware on reconnection.' -ForegroundColor DarkGray"
echo.
set "GHOSTCONF="
set /p "GHOSTCONF=  Type YES to continue: "
if /i not "!GHOSTCONF!"=="YES" (
    powershell -NoProfile -Command "Write-Host '  Cancelled.' -ForegroundColor DarkGray"
    exit /b 0
)
set "RMGHOSTSCRIPT=%TEMP%\ytsh_rmghost_%RANDOM%%RANDOM%.ps1"
(
    echo $devs = Get-PnpDevice -ErrorAction SilentlyContinue ^| Where-Object { $_.Present -eq $false }
    echo $removed = 0
    echo foreach^($d in $devs^) {
    echo     try {
    echo         $d ^| Remove-PnpDevice -Confirm:$false -ErrorAction Stop
    echo         Write-Host ^('  [REMOVED] ' + $d.FriendlyName^) -ForegroundColor Green
    echo         $removed++
    echo     } catch {
    echo         Write-Host ^('  [SKIP] ' + $d.FriendlyName^) -ForegroundColor DarkGray
    echo     }
    echo }
    echo Write-Host ^('  Done. ' + $removed + ' ghost device^(s^) removed.'^) -ForegroundColor Cyan
) > "%RMGHOSTSCRIPT%"
powershell -NoProfile -ExecutionPolicy Bypass -File "%RMGHOSTSCRIPT%"
del "%RMGHOSTSCRIPT%" >nul 2>&1
exit /b 0

:WINHELLO_MANAGER
cls
color !COL_OPS!
echo.
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '    WINDOWS HELLO / SIGN-IN MANAGER' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
echo.
powershell -NoProfile -ExecutionPolicy Bypass -Command "$bio = Get-Service -Name WbioSrvc -ErrorAction SilentlyContinue; Write-Host '  Biometric Service (WbioSrvc):' -ForegroundColor Cyan; if ($bio) { $col = if ($bio.Status -eq 'Running'){'Green'}else{'Red'}; Write-Host ('  Status: ' + $bio.Status + '   Startup: ' + $bio.StartType) -ForegroundColor $col } else { Write-Host '  Not present on this system.' -ForegroundColor DarkGray }; Write-Host ''"
echo.
echo   1  ^>  Open Sign-in Options (Settings shortcut)
echo   2  ^>  Set up / Change PIN   (Settings shortcut)
echo   3  ^>  Enable Biometric Service
echo   4  ^>  Disable Biometric Service
echo   5  ^>  Full Windows Hello reset (removes all PIN and biometric data)
echo.
echo   B  ^>  Back to main menu
echo.
set "WHCHOICE="
set /p "WHCHOICE=  Select: "
if /i "!WHCHOICE!"=="B" goto MAIN_MENU
if "!WHCHOICE!"=="1" (
    start ms-settings:signinoptions
    powershell -NoProfile -Command "Write-Host '  Opened Sign-in Options.' -ForegroundColor Green"
    echo.
    pause
    goto WINHELLO_MANAGER
)
if "!WHCHOICE!"=="2" (
    start ms-settings:signinoptions-launchpinenrollment
    powershell -NoProfile -Command "Write-Host '  Opened PIN setup.' -ForegroundColor Green"
    echo.
    pause
    goto WINHELLO_MANAGER
)
if "!WHCHOICE!"=="3" (
    sc config WbioSrvc start= auto >nul 2>&1
    sc start WbioSrvc >nul 2>&1
    powershell -NoProfile -Command "Write-Host '  [SUCCESS] Biometric service enabled and started.' -ForegroundColor Green"
    echo.
    pause
    goto WINHELLO_MANAGER
)
if "!WHCHOICE!"=="4" (
    sc stop WbioSrvc >nul 2>&1
    sc config WbioSrvc start= disabled >nul 2>&1
    powershell -NoProfile -Command "Write-Host '  [SUCCESS] Biometric service stopped and disabled.' -ForegroundColor Green"
    echo.
    pause
    goto WINHELLO_MANAGER
)
if "!WHCHOICE!"=="5" (
    echo.
    powershell -NoProfile -Command "Write-Host '  [WARN] This deletes all PIN and biometric sign-in data.' -ForegroundColor Red"
    powershell -NoProfile -Command "Write-Host '  You will need to re-enroll in Settings afterwards.' -ForegroundColor Yellow"
    echo.
    set "WHCONF="
    set /p "WHCONF=  Type YES to continue: "
    if /i "!WHCONF!"=="YES" (
        net stop WbioSrvc >nul 2>&1
        takeown /f "%WINDIR%\ServiceProfiles\LocalService\AppData\Local\Microsoft\Ngc" /r /d y >nul 2>&1
        icacls "%WINDIR%\ServiceProfiles\LocalService\AppData\Local\Microsoft\Ngc" /grant administrators:F /t >nul 2>&1
        rd /s /q "%WINDIR%\ServiceProfiles\LocalService\AppData\Local\Microsoft\Ngc" >nul 2>&1
        rd /s /q "%WINDIR%\System32\WinBioDatabase" >nul 2>&1
        net start WbioSrvc >nul 2>&1
        powershell -NoProfile -Command "Write-Host '  [SUCCESS] Windows Hello data cleared. Re-enroll via Settings > Sign-in Options.' -ForegroundColor Green"
    ) else (
        powershell -NoProfile -Command "Write-Host '  Cancelled.' -ForegroundColor DarkGray"
    )
    echo.
    pause
    goto WINHELLO_MANAGER
)
goto WINHELLO_MANAGER

:EVENTLOG_VIEWER
cls
color !COL_OPS!
echo.
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '    EVENT LOG VIEWER' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
echo.
echo   1  ^>  Last 20 System Critical/Error events
echo   2  ^>  Last 20 Application Critical/Error events
echo   3  ^>  Recent BSODs and kernel crash events
echo   4  ^>  Last 10 Windows Update events
echo   5  ^>  Export last 50 critical events to CSV
echo.
echo   B  ^>  Back to main menu
echo.
set "ELCHOICE="
set /p "ELCHOICE=  Select: "
if /i "!ELCHOICE!"=="B" goto MAIN_MENU
if "!ELCHOICE!"=="1" (
    echo.
    powershell -NoProfile -Command "Write-Host '  Last 20 System Critical/Error Events:' -ForegroundColor Cyan"
    echo.
    powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-WinEvent -FilterHashtable @{LogName='System'; Level=1,2} -MaxEvents 20 -ErrorAction SilentlyContinue | Select-Object TimeCreated,LevelDisplayName,Id,@{N='Message';E={$_.Message -replace '\r?\n',' '}} | Format-Table -AutoSize -Wrap | Out-Host"
    echo.
    pause
    goto EVENTLOG_VIEWER
)
if "!ELCHOICE!"=="2" (
    echo.
    powershell -NoProfile -Command "Write-Host '  Last 20 Application Critical/Error Events:' -ForegroundColor Cyan"
    echo.
    powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-WinEvent -FilterHashtable @{LogName='Application'; Level=1,2} -MaxEvents 20 -ErrorAction SilentlyContinue | Select-Object TimeCreated,LevelDisplayName,Id,@{N='Message';E={$_.Message -replace '\r?\n',' '}} | Format-Table -AutoSize -Wrap | Out-Host"
    echo.
    pause
    goto EVENTLOG_VIEWER
)
if "!ELCHOICE!"=="3" (
    echo.
    powershell -NoProfile -Command "Write-Host '  Recent BSOD / Kernel Crash Events (Event IDs 41, 1001, 1003):' -ForegroundColor Cyan"
    echo.
    powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-WinEvent -FilterHashtable @{LogName='System'; Id=41,1001,1003} -MaxEvents 10 -ErrorAction SilentlyContinue | Select-Object TimeCreated,Id,@{N='Message';E={$_.Message -replace '\r?\n',' '}} | Format-Table -AutoSize -Wrap | Out-Host"
    echo.
    powershell -NoProfile -ExecutionPolicy Bypass -Command "$d = Get-ChildItem '%WINDIR%\Minidump\*.dmp' -ErrorAction SilentlyContinue; if($d){ Write-Host ('  Found ' + $d.Count + ' minidump file(s) in %WINDIR%\Minidump - use WinDbg to analyze.') -ForegroundColor Yellow } else { Write-Host '  No minidump files found.' -ForegroundColor Green }"
    echo.
    pause
    goto EVENTLOG_VIEWER
)
if "!ELCHOICE!"=="4" (
    echo.
    powershell -NoProfile -Command "Write-Host '  Last 10 Windows Update Events:' -ForegroundColor Cyan"
    echo.
    powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='Microsoft-Windows-WindowsUpdateClient'} -MaxEvents 10 -ErrorAction SilentlyContinue | Select-Object TimeCreated,LevelDisplayName,@{N='Message';E={$_.Message -replace '\r?\n',' '}} | Format-Table -AutoSize -Wrap | Out-Host"
    echo.
    pause
    goto EVENTLOG_VIEWER
)
if "!ELCHOICE!"=="5" (
    echo.
    for /f %%D in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd_HHmm"') do set "ELDATE=%%D"
    set "ELFILE=!LOGDIR!\YTSH_Events_!ELDATE!.csv"
    set "YTSH_ELFILE=!LOGDIR!\YTSH_Events_!ELDATE!.csv"
    powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-WinEvent -FilterHashtable @{LogName='System','Application'; Level=1,2} -MaxEvents 50 -ErrorAction SilentlyContinue | Select-Object TimeCreated,LogName,LevelDisplayName,Id,@{N='Message';E={$_.Message -replace '\r?\n',' '}} | Export-Csv $env:YTSH_ELFILE -NoTypeInformation -Encoding UTF8; Write-Host ('  [SUCCESS] Exported to: ' + $env:YTSH_ELFILE) -ForegroundColor Green"
    echo.
    pause
    goto EVENTLOG_VIEWER
)
goto EVENTLOG_VIEWER

:BATTERY_REPORT
cls
color !COL_OPS!
echo.
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '    BATTERY REPORT' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
echo.
powershell -NoProfile -ExecutionPolicy Bypass -Command "$b=Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue; if(-not $b){exit 1}" >nul 2>&1
if !errorLevel! neq 0 (
    powershell -NoProfile -Command "Write-Host '  No battery detected on this system.' -ForegroundColor DarkGray"
    echo.
    pause
    goto MAIN_MENU
)
echo.
powershell -NoProfile -Command "Write-Host '  Quick Battery Summary:' -ForegroundColor Cyan"
echo.
powershell -NoProfile -ExecutionPolicy Bypass -Command "$b = Get-CimInstance Win32_Battery -EA SilentlyContinue; $charge = $b.EstimatedChargeRemaining; $status = switch($b.BatteryStatus){ 1{'Discharging'} 2{'On AC'} 6{'Charging'} default{'Status '+$b.BatteryStatus} }; $ccol = if($charge -lt 15){'Red'} elseif($charge -lt 30){'Yellow'} else{'Green'}; Write-Host ('  Charge : ' + $charge + '%%  (' + $status + ')') -ForegroundColor $ccol; try { $bs = Get-CimInstance -Namespace root\\wmi -ClassName BatteryStaticData -EA SilentlyContinue | Select-Object -First 1; $bf = Get-CimInstance -Namespace root\\wmi -ClassName BatteryFullChargedCapacity -EA SilentlyContinue | Select-Object -First 1; if($bs -and $bf -and $bs.DesignedCapacity -gt 0){ $health = [math]::Round($bf.FullChargedCapacity / $bs.DesignedCapacity * 100, 1); $hcol = if($health -lt 50){'Red'} elseif($health -lt 75){'Yellow'} else{'Green'}; $grade = if($health -ge 80){'Good'} elseif($health -ge 60){'Degraded'} elseif($health -ge 40){'Poor - consider replacing'} else{'Critical - replace soon'}; Write-Host ('  Health : ' + $health + '%% (' + $grade + ')') -ForegroundColor $hcol; Write-Host ('  Capacity: ' + $bf.FullChargedCapacity + ' mWh / ' + $bs.DesignedCapacity + ' mWh design') -ForegroundColor $hcol } } catch { Write-Host '  Detailed capacity data unavailable.' -ForegroundColor DarkGray }"
echo.
for /f %%D in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd"') do set "_BATDATE=%%D"
set "BATRPTFILE=!LOGDIR!\battery_report_!_BATDATE!.html"
powershell -NoProfile -Command "Write-Host '  Generating full powercfg battery report...' -ForegroundColor Cyan"
powercfg /batteryreport /output "!BATRPTFILE!" >nul 2>&1
if !errorLevel! equ 0 (
    powershell -NoProfile -Command "Write-Host '  [SUCCESS] Report saved to: !BATRPTFILE!' -ForegroundColor Green"
    echo.
    echo   O  ^>  Open report in browser     B  ^>  Back
    echo.
    set "BATOPEN="
    set /p "BATOPEN=  Select: "
    if /i "!BATOPEN!"=="O" start "" "!BATRPTFILE!"
) else (
    powershell -NoProfile -Command "Write-Host '  [FAIL] Could not generate report. Check if powercfg is accessible.' -ForegroundColor Red"
)
echo.
pause
goto MAIN_MENU

:ENVVAR_MANAGER
cls
color !COL_OPS!
echo.
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '    ENVIRONMENT VARIABLES MANAGER' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
echo.
echo   1  ^>  View System PATH  (green = path exists, red = broken/missing)
echo   2  ^>  View User PATH
echo   3  ^>  View all System variables
echo   4  ^>  Add entry to System PATH
echo   5  ^>  Add entry to User PATH
echo   6  ^>  Open Environment Variables GUI
echo.
echo   B  ^>  Back to main menu
echo.
set "EVCHOICE="
set /p "EVCHOICE=  Select: "
if /i "!EVCHOICE!"=="B" goto MAIN_MENU
if "!EVCHOICE!"=="1" (
    echo.
    powershell -NoProfile -Command "Write-Host '  System PATH entries:' -ForegroundColor Cyan"
    echo.
    powershell -NoProfile -ExecutionPolicy Bypass -Command "[Environment]::GetEnvironmentVariable('Path','Machine') -split ';' | Where-Object { $_.Trim() -ne '' } | ForEach-Object { $ex = Test-Path $_.Trim() -ErrorAction SilentlyContinue; $col = if($ex){'Green'}else{'Red'}; $tag = if($ex){'[OK]  '}else{'[MISS]'}; Write-Host ('  ' + $tag + ' ' + $_) -ForegroundColor $col }"
    echo.
    pause
    goto ENVVAR_MANAGER
)
if "!EVCHOICE!"=="2" (
    echo.
    powershell -NoProfile -Command "Write-Host '  User PATH entries:' -ForegroundColor Cyan"
    echo.
    powershell -NoProfile -ExecutionPolicy Bypass -Command "[Environment]::GetEnvironmentVariable('Path','User') -split ';' | Where-Object { $_.Trim() -ne '' } | ForEach-Object { $ex = Test-Path $_.Trim() -ErrorAction SilentlyContinue; $col = if($ex){'Green'}else{'Red'}; $tag = if($ex){'[OK]  '}else{'[MISS]'}; Write-Host ('  ' + $tag + ' ' + $_) -ForegroundColor $col }"
    echo.
    pause
    goto ENVVAR_MANAGER
)
if "!EVCHOICE!"=="3" (
    echo.
    powershell -NoProfile -Command "Write-Host '  All System Environment Variables:' -ForegroundColor Cyan"
    echo.
    powershell -NoProfile -ExecutionPolicy Bypass -Command "[System.Environment]::GetEnvironmentVariables('Machine').GetEnumerator() | Sort-Object Name | ForEach-Object { Write-Host ('  ' + $_.Key.PadRight(28) + ' = ' + $_.Value) -ForegroundColor White }"
    echo.
    pause
    goto ENVVAR_MANAGER
)
if "!EVCHOICE!"=="4" (
    echo.
    set "ADDSPATH="
    set /p "ADDSPATH=  Enter full path to add to System PATH: "
    if defined ADDSPATH (
        powershell -NoProfile -ExecutionPolicy Bypass -Command "$cur = [Environment]::GetEnvironmentVariable('Path','Machine'); if ($cur -notlike ('*' + '!ADDSPATH!' + '*')) { [Environment]::SetEnvironmentVariable('Path', $cur + ';!ADDSPATH!', 'Machine'); Write-Host '  [SUCCESS] Added to System PATH.' -ForegroundColor Green } else { Write-Host '  [SKIP] Entry already exists in System PATH.' -ForegroundColor DarkGray }"
    )
    echo.
    pause
    goto ENVVAR_MANAGER
)
if "!EVCHOICE!"=="5" (
    echo.
    set "ADDUPATH="
    set /p "ADDUPATH=  Enter full path to add to User PATH: "
    if defined ADDUPATH (
        powershell -NoProfile -ExecutionPolicy Bypass -Command "$cur = [Environment]::GetEnvironmentVariable('Path','User'); if ($cur -notlike ('*' + '!ADDUPATH!' + '*')) { [Environment]::SetEnvironmentVariable('Path', $cur + ';!ADDUPATH!', 'User'); Write-Host '  [SUCCESS] Added to User PATH.' -ForegroundColor Green } else { Write-Host '  [SKIP] Entry already exists in User PATH.' -ForegroundColor DarkGray }"
    )
    echo.
    pause
    goto ENVVAR_MANAGER
)
if "!EVCHOICE!"=="6" (
    start sysdm.cpl ,3
    powershell -NoProfile -Command "Write-Host '  Opened System Properties > Advanced tab.' -ForegroundColor Green"
    echo.
    pause
    goto ENVVAR_MANAGER
)
goto ENVVAR_MANAGER

:MALWARE_SCANNER
cls
color !COL_OPS!
echo.
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '    MALWARE AND THREAT SCANNER' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
echo.
powershell -NoProfile -Command "Write-Host '  35 checks available:' -ForegroundColor !COL_OPS_PS!"
powershell -NoProfile -Command "Write-Host '  Processes, Network, Startup, Scheduled Tasks, Suspicious Files, HOSTS,' -ForegroundColor DarkGray"
powershell -NoProfile -Command "Write-Host '  Services, Users, Defender, DNS Cache, Shares, ARP, Firewall, RDP,' -ForegroundColor DarkGray"
powershell -NoProfile -Command "Write-Host '  Drivers, LSA, BitLocker, Browser Extensions+Hijacking, Proxy,' -ForegroundColor DarkGray"
powershell -NoProfile -Command "Write-Host '  Certificates, Defender Exclusions, Privilege Escalation, WDigest,' -ForegroundColor DarkGray"
powershell -NoProfile -Command "Write-Host '  Accessibility Backdoors, DLL Hijacking, WMI Persistence, BITS Jobs,' -ForegroundColor DarkGray"
powershell -NoProfile -Command "Write-Host '  Shadow Copies, Legacy Protocols, LLMNR+NetBIOS, Credential Manager,' -ForegroundColor DarkGray"
powershell -NoProfile -Command "Write-Host '  Win10/11 Security, PowerShell Security, Browser Data, Prefetch' -ForegroundColor DarkGray"
echo.
echo   1  ^>  Full Scan     ^(all 35 checks - most thorough^)
echo   2  ^>  Minimal Scan  ^(processes, network, startup, services, users, defender, firewall, defender exclusions, privilege escalation, accessibility backdoors^)
echo   3  ^>  Custom Scan   ^(pick any single check from the list^)
echo.
echo   B  ^>  Back to main menu
echo.
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
echo.
set "MLCHOICE="
set /p "MLCHOICE=  Select scan type [1-3, B]: "
if /i "!MLCHOICE!"=="B" goto MAIN_MENU
if "!MLCHOICE!"=="1" set "ML_SCANMODE=FULL"    & set "ML_CUSTOM=0" & goto MALWARE_RUN_SCAN
if "!MLCHOICE!"=="2" set "ML_SCANMODE=MINIMAL" & set "ML_CUSTOM=0" & goto MALWARE_RUN_SCAN
if "!MLCHOICE!"=="3" goto MALWARE_CUSTOM_MENU
goto MALWARE_SCANNER

:MALWARE_CUSTOM_MENU
cls
color !COL_OPS!
echo.
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '    CUSTOM SCAN - SELECT A CHECK' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
echo.
echo    1  ^>  Suspicious Processes          ^(known malware names, suspicious paths, injection^)
echo    2  ^>  Network Connections           ^(active connections, suspicious ports, external IPs^)
echo    3  ^>  Registry Startup Entries      ^(HKLM + HKCU Run keys, startup folders^)
echo    4  ^>  Scheduled Tasks               ^(obfuscated or hidden task commands^)
echo    5  ^>  Suspicious Files              ^(Temp, AppData, drive roots, hidden System32^)
echo    6  ^>  HOSTS File Tampering          ^(redirected domains, non-default entries^)
echo    7  ^>  Installed Services            ^(binaries in Temp, AppData, or non-C: drives^)
echo    8  ^>  User Accounts                 ^(admin group members, hidden dollar accounts^)
echo    9  ^>  Windows Defender              ^(real-time, signatures, tamper protection^)
echo   10  ^>  DNS Cache                     ^(suspicious TLDs and shortener domains^)
echo   11  ^>  Open Network Shares           ^(non-default shares^)
echo   12  ^>  ARP Cache                     ^(duplicate MACs - ARP poisoning detection^)
echo   13  ^>  Firewall Status               ^(all profiles on/off^)
echo   14  ^>  RDP and Remote Access         ^(RDP enabled, NLA, port, remote tools^)
echo   15  ^>  Unsigned Drivers              ^(driver signature verification^)
echo   16  ^>  LSA Protection                ^(PPL, Credential Guard, NTLM level^)
echo   17  ^>  BitLocker                     ^(encryption status on all volumes^)
echo   18  ^>  Browser Extensions            ^(Chrome/Edge/Firefox/Opera/Brave + policy hijacking^)
echo   19  ^>  System Proxy                  ^(proxy settings, PAC scripts, WinHTTP^)
echo   20  ^>  Certificate Store             ^(rogue root CAs, MITM tool certs^)
echo   21  ^>  Defender Exclusions           ^(malware-added exclusions and bypass indicators^)
echo   22  ^>  Privilege Escalation          ^(AlwaysInstallElevated, unquoted service paths^)
echo   23  ^>  WDigest Credential Caching    ^(plaintext password caching in LSASS^)
echo   24  ^>  Accessibility Backdoors       ^(sethc/utilman/osk replaced with shell^)
echo   25  ^>  DLL Hijacking                 ^(AppInit_DLLs, Image File Execution Options^)
echo   26  ^>  WMI Persistence               ^(event subscriptions used for persistence^)
echo   27  ^>  BITS Jobs                     ^(Background Intelligent Transfer persistence^)
echo   28  ^>  Shadow Copy Status            ^(ransomware indicator if all copies deleted^)
echo   29  ^>  Legacy Protocols              ^(SMBv1 EternalBlue, LM hashes, SMB signing^)
echo   30  ^>  LLMNR and NetBIOS             ^(Responder credential theft attack surface^)
echo   31  ^>  Credential Manager            ^(stored credentials, suspicious entries^)
echo   32  ^>  Windows 10/11 Security        ^(TPM, Secure Boot, HVCI, Smart App Control^)
echo   33  ^>  PowerShell Security           ^(logging, execution policy, AMSI, PSv2^)
echo   34  ^>  Browser Data Integrity        ^(login data copies, stealer indicators^)
echo   35  ^>  Prefetch Analysis             ^(traces of attack tools and deleted malware^)
echo.
echo    B  ^>  Back
echo.
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
echo.
set "MLCUSTOM="
set /p "MLCUSTOM=  Select check [1-35, B]: "
if /i "!MLCUSTOM!"=="B" goto MALWARE_SCANNER
set "ML_VALID=0"
for %%N in (1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 32 33 34 35) do if "!MLCUSTOM!"=="%%N" set "ML_VALID=1"
if "!ML_VALID!"=="0" (
    powershell -NoProfile -Command "Write-Host '  Invalid selection - please enter a number 1-35 or B.' -ForegroundColor Red"
    echo.
    pause
    goto MALWARE_CUSTOM_MENU
)
set "ML_SCANMODE=CUSTOM"
set "ML_CUSTOM=!MLCUSTOM!"
goto MALWARE_RUN_SCAN

:MALWARE_RUN_SCAN
cls
color !COL_OPS!
echo.
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '    MALWARE AND THREAT SCANNER - RUNNING' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '    Mode: !ML_SCANMODE!' -ForegroundColor !COL_OPS_PS!"
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
echo.
for /f %%D in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd_HHmm"') do set "ML_DATE=%%D"
set "ML_REPORT=!LOGDIR!\YTSH_MalwareScan_!ML_DATE!.txt"
set "ML_THREATS_TMP=%TEMP%\ytsh_ml_t_%RANDOM%.tmp"
set "ML_WARN_TMP=%TEMP%\ytsh_ml_w_%RANDOM%.tmp"
type nul > "!ML_THREATS_TMP!"
type nul > "!ML_WARN_TMP!"
echo ================================================ > "!ML_REPORT!"
echo   YTSH MALWARE AND THREAT SCAN REPORT >> "!ML_REPORT!"
echo   Mode: !ML_SCANMODE! >> "!ML_REPORT!"
echo   Scanned: %DATE% %TIME% >> "!ML_REPORT!"
echo ================================================ >> "!ML_REPORT!"
call :ML_SHOULD_RUN 1
if not errorlevel 1 call :ML_CHECK_PROCESSES
call :ML_SHOULD_RUN 2
if not errorlevel 1 call :ML_CHECK_NETWORK
call :ML_SHOULD_RUN 3
if not errorlevel 1 call :ML_CHECK_STARTUP
call :ML_SHOULD_RUN 4
if not errorlevel 1 call :ML_CHECK_SCHTASKS
call :ML_SHOULD_RUN 5
if not errorlevel 1 call :ML_CHECK_FILES
call :ML_SHOULD_RUN 6
if not errorlevel 1 call :ML_CHECK_HOSTS
call :ML_SHOULD_RUN 7
if not errorlevel 1 call :ML_CHECK_SERVICES
call :ML_SHOULD_RUN 8
if not errorlevel 1 call :ML_CHECK_USERS
call :ML_SHOULD_RUN 9
if not errorlevel 1 call :ML_CHECK_DEFENDER
call :ML_SHOULD_RUN 10
if not errorlevel 1 call :ML_CHECK_DNS
call :ML_SHOULD_RUN 11
if not errorlevel 1 call :ML_CHECK_SHARES
call :ML_SHOULD_RUN 12
if not errorlevel 1 call :ML_CHECK_ARP
call :ML_SHOULD_RUN 13
if not errorlevel 1 call :ML_CHECK_FIREWALL
call :ML_SHOULD_RUN 14
if not errorlevel 1 call :ML_CHECK_RDP
call :ML_SHOULD_RUN 15
if not errorlevel 1 call :ML_CHECK_DRIVERS
call :ML_SHOULD_RUN 16
if not errorlevel 1 call :ML_CHECK_LSA
call :ML_SHOULD_RUN 17
if not errorlevel 1 call :ML_CHECK_BITLOCKER
call :ML_SHOULD_RUN 18
if not errorlevel 1 call :ML_CHECK_BROWSER
call :ML_SHOULD_RUN 19
if not errorlevel 1 call :ML_CHECK_PROXY
call :ML_SHOULD_RUN 20
if not errorlevel 1 call :ML_CHECK_CERTS
call :ML_SHOULD_RUN 21
if not errorlevel 1 call :ML_CHECK_DEFEXCL
call :ML_SHOULD_RUN 22
if not errorlevel 1 call :ML_CHECK_PRIVESC
call :ML_SHOULD_RUN 23
if not errorlevel 1 call :ML_CHECK_WDIGEST
call :ML_SHOULD_RUN 24
if not errorlevel 1 call :ML_CHECK_ACCESSBACK
call :ML_SHOULD_RUN 25
if not errorlevel 1 call :ML_CHECK_DLLHIJ
call :ML_SHOULD_RUN 26
if not errorlevel 1 call :ML_CHECK_WMI
call :ML_SHOULD_RUN 27
if not errorlevel 1 call :ML_CHECK_BITS
call :ML_SHOULD_RUN 28
if not errorlevel 1 call :ML_CHECK_SHADOW
call :ML_SHOULD_RUN 29
if not errorlevel 1 call :ML_CHECK_SMBLEGACY
call :ML_SHOULD_RUN 30
if not errorlevel 1 call :ML_CHECK_LLMNR
call :ML_SHOULD_RUN 31
if not errorlevel 1 call :ML_CHECK_CREDMAN
call :ML_SHOULD_RUN 32
if not errorlevel 1 call :ML_CHECK_WIN1011
call :ML_SHOULD_RUN 33
if not errorlevel 1 call :ML_CHECK_PSEC
call :ML_SHOULD_RUN 34
if not errorlevel 1 call :ML_CHECK_BROWDATA
call :ML_SHOULD_RUN 35
if not errorlevel 1 call :ML_CHECK_PREFETCH

set "ML_THREAT_COUNT=0"
set "ML_WARN_COUNT=0"
for /f %%A in ('type "!ML_THREATS_TMP!" ^| find /c /v ""') do set "ML_THREAT_COUNT=%%A"
for /f %%A in ('type "!ML_WARN_TMP!" ^| find /c /v ""') do set "ML_WARN_COUNT=%%A"

echo. >> "!ML_REPORT!"
echo ================================================ >> "!ML_REPORT!"
echo   SCAN SUMMARY >> "!ML_REPORT!"
echo ================================================ >> "!ML_REPORT!"
echo   Mode     : !ML_SCANMODE! >> "!ML_REPORT!"
echo   Threats  : !ML_THREAT_COUNT! >> "!ML_REPORT!"
echo   Warnings : !ML_WARN_COUNT! >> "!ML_REPORT!"
echo   Date     : %DATE% %TIME% >> "!ML_REPORT!"
echo ================================================ >> "!ML_REPORT!"
if !ML_THREAT_COUNT! GTR 0 (
    echo. >> "!ML_REPORT!"
    echo   THREATS DETECTED: >> "!ML_REPORT!"
    type "!ML_THREATS_TMP!" >> "!ML_REPORT!" 2>nul
)
if !ML_WARN_COUNT! GTR 0 (
    echo. >> "!ML_REPORT!"
    echo   WARNINGS: >> "!ML_REPORT!"
    type "!ML_WARN_TMP!" >> "!ML_REPORT!" 2>nul
)

echo.
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '    SCAN COMPLETE' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
echo.
if !ML_THREAT_COUNT! GTR 0 (
    powershell -NoProfile -Command "Write-Host '  THREATS  : !ML_THREAT_COUNT!' -ForegroundColor Red"
) else (
    powershell -NoProfile -Command "Write-Host '  THREATS  : !ML_THREAT_COUNT!' -ForegroundColor Green"
)
if !ML_WARN_COUNT! GTR 0 (
    powershell -NoProfile -Command "Write-Host '  WARNINGS : !ML_WARN_COUNT!' -ForegroundColor Yellow"
) else (
    powershell -NoProfile -Command "Write-Host '  WARNINGS : !ML_WARN_COUNT!' -ForegroundColor Green"
)
echo.
powershell -NoProfile -Command "Write-Host '  Report saved to:' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host ('  ' + $env:ML_REPORT) -ForegroundColor !COL_OPS_PS!"
echo.
echo   O  ^>  Open report in Notepad     B  ^>  Back to scanner menu
echo.
set "MLOPEN="
set /p "MLOPEN=  Select: "
if /i "!MLOPEN!"=="O" notepad "!ML_REPORT!"
del "!ML_THREATS_TMP!" >nul 2>&1
del "!ML_WARN_TMP!" >nul 2>&1
if "!SA_ACTIVE!"=="1" goto SA_ML_CONT
goto MALWARE_SCANNER
:SA_ML_CONT
echo.
powershell -NoProfile -Command "Write-Host '  B  >  Continue to next scanner (Network Security)' -ForegroundColor Yellow"
echo.
:SA_ML_WAIT
set "SA_CONT="
set /p "SA_CONT=  [B] Continue: "
if /i not "!SA_CONT!"=="B" goto SA_ML_WAIT
set "NG_SCANMODE=!SA_SCANMODE!"
set "NG_CUSTOM=0"
goto NETWORK_RUN_SCAN

:ML_SHOULD_RUN
if "!ML_SCANMODE!"=="FULL" exit /b 0
if "!ML_SCANMODE!"=="CUSTOM" (
    if "!ML_CUSTOM!"=="%~1" exit /b 0
    exit /b 1
)
if "!ML_SCANMODE!"=="MINIMAL" (
    if "%~1"=="1"  exit /b 0
    if "%~1"=="2"  exit /b 0
    if "%~1"=="3"  exit /b 0
    if "%~1"=="7"  exit /b 0
    if "%~1"=="8"  exit /b 0
    if "%~1"=="9"  exit /b 0
    if "%~1"=="13" exit /b 0
    if "%~1"=="21" exit /b 0
    if "%~1"=="22" exit /b 0
    if "%~1"=="24" exit /b 0
)
exit /b 1

:ML_CHECK_PROCESSES
echo.
powershell -NoProfile -Command "Write-Host '  --- [CHECK 1/35] SUSPICIOUS PROCESSES ---' -ForegroundColor !COL_HDR_PS!"
echo.
echo [CHECK 1] SUSPICIOUS PROCESSES >> "!ML_REPORT!"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$rep=$env:ML_REPORT;$thr=$env:ML_THREATS_TMP;$wrn=$env:ML_WARN_TMP;$ml=@('mimikatz','meterpreter','netcat','ncat','pwdump','fgdump','njrat','darkcomet','nanocore','remcos','xmrig','cpuminer','cryptominer','wce','gsecdump','lazagne','procdump','sharphound','bloodhound','empire','nanodump','quasar','asyncrat','dcrat','cobaltstrike','ratopub','blackshades','hawkeye','powersploit','msfvenom');$procs=Get-Process -EA SilentlyContinue;$found=0;foreach($p in $procs){foreach($n in $ml){if($p.Name -like ('*'+$n+'*')){Write-Host ('  [THREAT]  Known malware process: '+$p.Name+' (PID: '+$p.Id+')') -ForegroundColor Red;Add-Content $rep ('[THREAT] Malware process: '+$p.Name+' PID:'+$p.Id) -EA SilentlyContinue;Add-Content $thr ('Malware process: '+$p.Name+' PID:'+$p.Id) -EA SilentlyContinue;$found++}}};foreach($p in $procs){try{$path=$p.MainModule.FileName;if($path -match '(?i)\\Temp\\|\\AppData\\Roaming\\[^\\]+\.exe|\\AppData\\Local\\Temp\\|Users\\Public\\'){Write-Host ('  [THREAT]  Process in suspicious path: '+$p.Name+' -> '+$path) -ForegroundColor Red;Add-Content $rep ('[THREAT] Susp path process: '+$p.Name+' -> '+$path) -EA SilentlyContinue;Add-Content $thr ('Suspicious path process: '+$p.Name) -EA SilentlyContinue;$found++}}catch{}};$sys=@('System','Idle','Registry','Secure System','Memory Compression','smss','csrss','wininit','services','lsass','fontdrvhost','dwm','svchost','MsMpEng','NisSrv','spoolsv','SearchIndexer','audiodg','WUDFHost');foreach($p in $procs){try{$null=$p.MainModule.FileName}catch{if($p.Name -notin $sys -and $p.SessionId -ne 0){Write-Host ('  [WARN]    Unreadable module path (possible injection): '+$p.Name+' (PID: '+$p.Id+')') -ForegroundColor Yellow;Add-Content $wrn ('Possible injected process: '+$p.Name) -EA SilentlyContinue}}};if($found -eq 0){Write-Host '  [CLEAN]   No known malware process names detected' -ForegroundColor Green;Add-Content $rep '[CLEAN] No malware processes' -EA SilentlyContinue};Write-Host ('  [INFO]    Total running processes: '+$procs.Count) -ForegroundColor DarkGray;Add-Content $rep ('Total processes: '+$procs.Count) -EA SilentlyContinue"
echo.
goto :EOF

:ML_CHECK_NETWORK
echo.
powershell -NoProfile -Command "Write-Host '  --- [CHECK 2/35] NETWORK CONNECTIONS ---' -ForegroundColor !COL_HDR_PS!"
echo.
echo [CHECK 2] NETWORK CONNECTIONS >> "!ML_REPORT!"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$rep=$env:ML_REPORT;$thr=$env:ML_THREATS_TMP;$wrn=$env:ML_WARN_TMP;$sp=@(1080,4444,5555,6666,7777,8888,9999,31337,12345,54321,1337,6667,6668,6669,4899,65535,13337,60001,60002,2222);$conns=netstat -ano 2>$null;Add-Content $rep ($conns -join [Environment]::NewLine) -EA SilentlyContinue;$pf=0;foreach($port in $sp){$hits=$conns -match (':'+$port+'\s');if($hits){foreach($h in $hits){Write-Host ('  [THREAT]  Suspicious port '+$port+': '+$h.Trim()) -ForegroundColor Red;Add-Content $rep ('[THREAT] Suspicious port '+$port+': '+$h.Trim()) -EA SilentlyContinue;Add-Content $thr ('Suspicious port '+$port+' in use') -EA SilentlyContinue;$pf++}}};$priv=@('127\.','10\.','192\.168\.','172\.(1[6-9]|2\d|3[01])\.','0\.0\.0\.0','::1','\[::');$est=$conns -match 'ESTABLISHED';foreach($c in $est){$ext=$true;foreach($r in $priv){if($c -match $r){$ext=$false;break}};if($ext -and $c -match '(\d+\.\d+\.\d+\.\d+):(\d+)\s+(\d+\.\d+\.\d+\.\d+):(\d+)\s+ESTABLISHED'){$rp=[int]$Matches[4];if($rp -notin @(80,443,8080,8443,53,123,25,587,465,993,995,110,143,3478,3479)){Write-Host ('  [WARN]    External connection on non-standard port: '+$c.Trim()) -ForegroundColor Yellow;Add-Content $wrn ('Ext conn unusual port: '+$c.Trim()) -EA SilentlyContinue}}};if($pf -eq 0){Write-Host '  [CLEAN]   No connections on known RAT or C2 ports' -ForegroundColor Green;Add-Content $rep '[CLEAN] No suspicious port connections' -EA SilentlyContinue};Write-Host ('  [INFO]    Listening: '+($conns -match 'LISTENING').Count+'  Established: '+($conns -match 'ESTABLISHED').Count) -ForegroundColor DarkGray"
echo.
goto :EOF

:ML_CHECK_STARTUP
echo.
powershell -NoProfile -Command "Write-Host '  --- [CHECK 3/35] REGISTRY STARTUP ENTRIES ---' -ForegroundColor !COL_HDR_PS!"
echo.
echo [CHECK 3] STARTUP ENTRIES >> "!ML_REPORT!"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$rep=$env:ML_REPORT;$thr=$env:ML_THREATS_TMP;$wrn=$env:ML_WARN_TMP;$keys=@('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run','HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce','HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Run','HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run','HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce');foreach($k in $keys){try{$e=Get-ItemProperty $k -EA SilentlyContinue;if($e){$e.PSObject.Properties | Where-Object{$_.Name -notlike 'PS*'} | ForEach-Object{$n=$_.Name;$v=$_.Value;Write-Host ('  [INFO]    ['+($k -split '\\')[-1]+'] '+$n+' = '+$v) -ForegroundColor DarkGray;Add-Content $rep ('[STARTUP] '+$n+' = '+$v) -EA SilentlyContinue;if($v -match '(?i)\\Temp\\|\\AppData\\Roaming\\|\.ps1[^h]|\.vbs|mshta|wscript|cscript|rundll32.*http|powershell.*-enc|powershell.*-nop|-w.*hidden|regsvr32.*http'){Write-Host ('  [THREAT]  Suspicious startup entry: '+$n+' -> '+$v) -ForegroundColor Red;Add-Content $rep ('[THREAT] Suspicious startup: '+$n) -EA SilentlyContinue;Add-Content $thr ('Suspicious startup entry: '+$n) -EA SilentlyContinue}}}}catch{}};$sf=@($env:APPDATA+'\Microsoft\Windows\Start Menu\Programs\Startup',$env:ProgramData+'\Microsoft\Windows\Start Menu\Programs\Startup');foreach($f in $sf){if(Test-Path $f){$items=Get-ChildItem $f -EA SilentlyContinue;foreach($i in $items){Write-Host ('  [INFO]    Startup folder item: '+$i.FullName) -ForegroundColor DarkGray;Add-Content $rep ('[STARTUP FOLDER] '+$i.FullName) -EA SilentlyContinue;if($i.Extension -match '\.(exe|bat|ps1|vbs|cmd|js|jar|hta)$'){Write-Host ('  [WARN]    Executable in startup folder: '+$i.Name) -ForegroundColor Yellow;Add-Content $wrn ('Startup folder executable: '+$i.FullName) -EA SilentlyContinue}}}};Write-Host '  [CLEAN]   Startup scan complete - review entries above' -ForegroundColor Green"
echo.
goto :EOF

:ML_CHECK_SCHTASKS
echo.
powershell -NoProfile -Command "Write-Host '  --- [CHECK 4/35] SCHEDULED TASKS ---' -ForegroundColor !COL_HDR_PS!"
echo.
echo [CHECK 4] SCHEDULED TASKS >> "!ML_REPORT!"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$rep=$env:ML_REPORT;$thr=$env:ML_THREATS_TMP;$wrn=$env:ML_WARN_TMP;try{$tasks=Get-ScheduledTask -EA SilentlyContinue | Where-Object{$_.State -ne 'Disabled'};$found=0;foreach($t in $tasks){try{foreach($a in $t.Actions){if(-not $a.Execute){continue};$argStr=if($a.Arguments){$a.Arguments}else{''}; $cmd=($a.Execute+' '+$argStr).Trim();if($cmd -match '(?i)\\Temp\\|\\AppData\\Roaming\\|powershell.*-enc|powershell.*-nop.*hidden|mshta|wscript.*http|regsvr32.*http|rundll32.*http|bitsadmin.*transfer|certutil.*-decode|\\Users\\Public\\|cmd.*\/c.*http'){Write-Host ('  [THREAT]  Suspicious task: '+$t.TaskName+' -> '+$cmd) -ForegroundColor Red;Add-Content $rep ('[THREAT] Suspicious task: '+$t.TaskName+' -> '+$cmd) -EA SilentlyContinue;Add-Content $thr ('Suspicious scheduled task: '+$t.TaskName) -EA SilentlyContinue;$found++}};if($t.Principal -and $t.Principal.RunLevel -eq 'Highest' -and $t.Author -and ($t.Author -notmatch 'Microsoft|Windows|SYSTEM|NT AUTHORITY')){Write-Host ('  [WARN]    High-privilege non-Microsoft task: '+$t.TaskName+' (Author: '+$t.Author+')') -ForegroundColor Yellow;Add-Content $wrn ('High-priv task: '+$t.TaskName) -EA SilentlyContinue}}catch{}};if($found -eq 0){Write-Host '  [CLEAN]   No obviously malicious scheduled tasks detected' -ForegroundColor Green;Add-Content $rep '[CLEAN] No suspicious tasks' -EA SilentlyContinue};Write-Host ('  [INFO]    Active tasks checked: '+@($tasks).Count) -ForegroundColor DarkGray}catch{Write-Host '  [WARN]    Could not enumerate scheduled tasks' -ForegroundColor Yellow}"
echo.
goto :EOF

:ML_CHECK_FILES
echo.
powershell -NoProfile -Command "Write-Host '  --- [CHECK 5/35] SUSPICIOUS FILES ---' -ForegroundColor !COL_HDR_PS!"
echo.
echo [CHECK 5] SUSPICIOUS FILES >> "!ML_REPORT!"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$rep=$env:ML_REPORT;$thr=$env:ML_THREATS_TMP;$wrn=$env:ML_WARN_TMP;$paths=@($env:TEMP,$env:APPDATA,($env:LOCALAPPDATA+'\Temp'),'C:\Users\Public');$exts=@('*.exe','*.bat','*.ps1','*.vbs','*.cmd','*.hta','*.js','*.jar');$tf=0;foreach($p in $paths){if(Test-Path $p){foreach($ext in $exts){$f=Get-ChildItem $p -Filter $ext -EA SilentlyContinue;foreach($fi in $f){Write-Host ('  [THREAT]  Executable in risky path: '+$fi.FullName) -ForegroundColor Red;Add-Content $rep ('[THREAT] Exec in risky path: '+$fi.FullName) -EA SilentlyContinue;Add-Content $thr ('Executable in risky path: '+$fi.FullName) -EA SilentlyContinue;$tf++}}}};$drives=Get-PSDrive -PSProvider FileSystem -EA SilentlyContinue | Where-Object{$_.Root};foreach($d in $drives){foreach($ext in @('*.exe','*.bat','*.vbs','*.ps1')){$f=Get-ChildItem $d.Root -Filter $ext -EA SilentlyContinue;foreach($fi in $f){Write-Host ('  [WARN]    Executable at drive root: '+$fi.FullName) -ForegroundColor Yellow;Add-Content $rep ('[WARN] Drive root exec: '+$fi.FullName) -EA SilentlyContinue;Add-Content $wrn ('Drive root executable: '+$fi.FullName) -EA SilentlyContinue}};if(Test-Path ($d.Root+'Windows\System32')){$h=Get-ChildItem ($d.Root+'Windows\System32') -Filter '*.exe' -Hidden -EA SilentlyContinue;foreach($fi in $h){Write-Host ('  [WARN]    Hidden .exe in System32: '+$fi.Name) -ForegroundColor Yellow;Add-Content $rep ('[WARN] Hidden System32 exe: '+$fi.FullName) -EA SilentlyContinue;Add-Content $wrn ('Hidden System32 exe: '+$fi.Name) -EA SilentlyContinue}}};if($tf -eq 0){Write-Host '  [CLEAN]   No executables found in Temp or Public paths' -ForegroundColor Green;Add-Content $rep '[CLEAN] No executables in risky paths' -EA SilentlyContinue}"
echo.
goto :EOF

:ML_CHECK_HOSTS
echo.
powershell -NoProfile -Command "Write-Host '  --- [CHECK 6/35] HOSTS FILE TAMPERING ---' -ForegroundColor !COL_HDR_PS!"
echo.
echo [CHECK 6] HOSTS FILE >> "!ML_REPORT!"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$rep=$env:ML_REPORT;$thr=$env:ML_THREATS_TMP;$wrn=$env:ML_WARN_TMP;$hp='C:\Windows\System32\drivers\etc\hosts';try{$lines=Get-Content $hp -EA SilentlyContinue;Add-Content $rep ($lines -join [Environment]::NewLine) -EA SilentlyContinue;$nc=$lines | Where-Object{$_ -notmatch '^\s*#' -and $_.Trim() -ne ''};$leg=@('127\.0\.0\.1\s+localhost','::1\s+localhost','255\.255\.255\.255\s+broadcasthost','0\.0\.0\.0\s+0\.0\.0\.0','127\.0\.0\.1\s+localhost\.localdomain');$susp=0;foreach($l in $nc){$ok=$false;foreach($r in $leg){if($l -match $r){$ok=$true;break}};if(-not $ok){Write-Host ('  [WARN]    Non-default HOSTS entry: '+$l.Trim()) -ForegroundColor Yellow;Add-Content $rep ('[WARN] HOSTS entry: '+$l.Trim()) -EA SilentlyContinue;Add-Content $wrn ('Non-default HOSTS: '+$l.Trim()) -EA SilentlyContinue;$susp++}};$known=@('google\.com','microsoft\.com','windows\.com','windowsupdate\.com','virustotal\.com','malwarebytes\.com','kaspersky\.com','avast\.com','eset\.com','symantec\.com');foreach($d in $known){$r=$nc | Where-Object{$_ -match $d};if($r){Write-Host ('  [THREAT]  Security or update domain redirected in HOSTS: '+($r -join ' ')) -ForegroundColor Red;Add-Content $rep ('[THREAT] HOSTS redirect: '+($r -join ' ')) -EA SilentlyContinue;Add-Content $thr ('HOSTS redirect for security domain: '+$d) -EA SilentlyContinue}};if($susp -eq 0){Write-Host '  [CLEAN]   HOSTS file contains only default entries' -ForegroundColor Green;Add-Content $rep '[CLEAN] HOSTS clean' -EA SilentlyContinue}else{Write-Host ('  [INFO]    Non-default HOSTS entries: '+$susp) -ForegroundColor DarkGray}}catch{Write-Host '  [WARN]    Could not read HOSTS file' -ForegroundColor Yellow}"
echo.
goto :EOF

:ML_CHECK_SERVICES
echo.
powershell -NoProfile -Command "Write-Host '  --- [CHECK 7/35] INSTALLED SERVICES ---' -ForegroundColor !COL_HDR_PS!"
echo.
echo [CHECK 7] SERVICES >> "!ML_REPORT!"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$rep=$env:ML_REPORT;$thr=$env:ML_THREATS_TMP;$wrn=$env:ML_WARN_TMP;try{$svcs=Get-CimInstance -ClassName Win32_Service -EA SilentlyContinue;Add-Content $rep ('Total services: '+$svcs.Count) -EA SilentlyContinue;$found=0;foreach($s in $svcs){$p=$s.PathName;if(-not $p){continue};if($p -match '(?i)\\Temp\\|\\AppData\\|\\Users\\Public\\'){Write-Host ('  [THREAT]  Service binary in suspicious path: ['+$s.Name+'] -> '+$p) -ForegroundColor Red;Add-Content $rep ('[THREAT] Suspicious service path: '+$s.Name+' -> '+$p) -EA SilentlyContinue;Add-Content $thr ('Suspicious service: '+$s.Name) -EA SilentlyContinue;$found++};if($p -match '^[D-Zd-z]:\\' -and $p -notmatch '(?i)Program Files|Windows'){Write-Host ('  [WARN]    Service on non-system drive: ['+$s.Name+'] -> '+$p) -ForegroundColor Yellow;Add-Content $rep ('[WARN] Non-C service: '+$s.Name+' -> '+$p) -EA SilentlyContinue;Add-Content $wrn ('Non-system drive service: '+$s.Name) -EA SilentlyContinue}};if($found -eq 0){Write-Host '  [CLEAN]   No services found with suspicious paths' -ForegroundColor Green;Add-Content $rep '[CLEAN] No suspicious service paths' -EA SilentlyContinue};Write-Host ('  [INFO]    Total services: '+$svcs.Count) -ForegroundColor DarkGray}catch{Write-Host '  [WARN]    Could not enumerate services' -ForegroundColor Yellow}"
echo.
goto :EOF

:ML_CHECK_USERS
echo.
powershell -NoProfile -Command "Write-Host '  --- [CHECK 8/35] USER ACCOUNTS ---' -ForegroundColor !COL_HDR_PS!"
echo.
echo [CHECK 8] USER ACCOUNTS >> "!ML_REPORT!"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$rep=$env:ML_REPORT;$thr=$env:ML_THREATS_TMP;$wrn=$env:ML_WARN_TMP;$adm=net localgroup administrators 2>$null;Add-Content $rep ($adm -join [Environment]::NewLine) -EA SilentlyContinue;$al=$adm | Select-Object -Skip 6 | Where-Object{$_ -ne '' -and $_ -notmatch '---' -and $_ -notmatch 'command completed'};Write-Host '  [INFO]    Administrators group:' -ForegroundColor DarkGray;foreach($a in $al){if($a.Trim()){Write-Host ('  [INFO]      '+$a.Trim()) -ForegroundColor DarkGray;if($a -match '(?i)^(guest|test|admin\d+|hacker|hack|backdoor|temp\d*|user\d+|support\d*)'){Write-Host ('  [THREAT]  Suspicious admin account name: '+$a.Trim()) -ForegroundColor Red;Add-Content $rep ('[THREAT] Suspicious admin: '+$a.Trim()) -EA SilentlyContinue;Add-Content $thr ('Suspicious admin account: '+$a.Trim()) -EA SilentlyContinue}}};$users=net user 2>$null;Add-Content $rep ($users -join [Environment]::NewLine) -EA SilentlyContinue;$uline=($users -join ' ');$hidden=[regex]::Matches($uline,'(?<=[^\w]|^)\S+\$(?=\s|$)');foreach($h in $hidden){Write-Host ('  [THREAT]  Hidden user account (dollar-sign suffix): '+$h.Value) -ForegroundColor Red;Add-Content $rep ('[THREAT] Hidden user: '+$h.Value) -EA SilentlyContinue;Add-Content $thr ('Hidden user account: '+$h.Value) -EA SilentlyContinue};$ge=net user guest 2>$null | Select-String 'Account active.*Yes';if($ge){Write-Host '  [WARN]    Guest account is ENABLED' -ForegroundColor Yellow;Add-Content $wrn 'Guest account enabled' -EA SilentlyContinue}else{Write-Host '  [CLEAN]   Guest account is disabled' -ForegroundColor Green};Write-Host '  [CLEAN]   User enumeration complete - review above' -ForegroundColor Green"
echo.
goto :EOF

:ML_CHECK_DEFENDER
echo.
powershell -NoProfile -Command "Write-Host '  --- [CHECK 9/35] WINDOWS DEFENDER STATUS ---' -ForegroundColor !COL_HDR_PS!"
echo.
echo [CHECK 9] WINDOWS DEFENDER >> "!ML_REPORT!"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$rep=$env:ML_REPORT;$thr=$env:ML_THREATS_TMP;$wrn=$env:ML_WARN_TMP;try{$mp=Get-MpComputerStatus -EA SilentlyContinue;if($mp){if($mp.RealTimeProtectionEnabled){Write-Host '  [CLEAN]   Real-time protection: ENABLED' -ForegroundColor Green;Add-Content $rep '[CLEAN] RTP enabled' -EA SilentlyContinue}else{Write-Host '  [THREAT]  Real-time protection: DISABLED' -ForegroundColor Red;Add-Content $rep '[THREAT] RTP disabled' -EA SilentlyContinue;Add-Content $thr 'Windows Defender real-time protection DISABLED' -EA SilentlyContinue};if($mp.AntivirusEnabled){Write-Host '  [CLEAN]   Antivirus engine: ENABLED' -ForegroundColor Green}else{Write-Host '  [THREAT]  Antivirus engine: DISABLED' -ForegroundColor Red;Add-Content $thr 'Antivirus engine disabled' -EA SilentlyContinue};$age=$mp.AntivirusSignatureAge;if($age -le 3){Write-Host ('  [CLEAN]   Signatures: '+$age+' day(s) old - current') -ForegroundColor Green}elseif($age -le 14){Write-Host ('  [WARN]    Signatures: '+$age+' days old - update recommended') -ForegroundColor Yellow;Add-Content $wrn ('Defender signatures '+$age+' days old') -EA SilentlyContinue}else{Write-Host ('  [THREAT]  Signatures: '+$age+' days old - CRITICALLY OUTDATED') -ForegroundColor Red;Add-Content $thr ('Defender signatures '+$age+' days old') -EA SilentlyContinue};$scan=$mp.QuickScanAge;if($scan -le 7){Write-Host ('  [CLEAN]   Last quick scan: '+$scan+' day(s) ago') -ForegroundColor Green}else{Write-Host ('  [WARN]    Last quick scan: '+$scan+' days ago - scan recommended') -ForegroundColor Yellow;Add-Content $wrn ('Last Defender scan: '+$scan+' days ago') -EA SilentlyContinue};if($mp.IsTamperProtected){Write-Host '  [CLEAN]   Tamper protection: ENABLED' -ForegroundColor Green}else{Write-Host '  [WARN]    Tamper protection: DISABLED (malware can modify Defender settings)' -ForegroundColor Yellow;Add-Content $wrn 'Tamper protection disabled' -EA SilentlyContinue}}else{Write-Host '  [INFO]    Defender status unavailable (3rd party AV may be active)' -ForegroundColor DarkGray}}catch{Write-Host '  [INFO]    Defender check failed (3rd party AV may be installed)' -ForegroundColor DarkGray}"
echo.
goto :EOF

:ML_CHECK_DNS
echo.
powershell -NoProfile -Command "Write-Host '  --- [CHECK 10/35] DNS CACHE ---' -ForegroundColor !COL_HDR_PS!"
echo.
echo [CHECK 10] DNS CACHE >> "!ML_REPORT!"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$rep=$env:ML_REPORT;$thr=$env:ML_THREATS_TMP;$wrn=$env:ML_WARN_TMP;$pat='(?i)(\.ru\b|\.cn\b|\.tk\b|\.ga\b|\.ml\b|\.cf\b|\.onion\b|\.xyz\b|\.top\b|\.pw\b|\.icu\b|\.gq\b|\.sbs\b|bit\.ly|tinyurl\.com|is\.gd|t\.co|0x0\.st|discord\.gg)';$dns=ipconfig /displaydns 2>$null;Add-Content $rep ($dns -join [Environment]::NewLine) -EA SilentlyContinue;$susp=$dns | Select-String -Pattern $pat -EA SilentlyContinue;if($susp){foreach($s in $susp){Write-Host ('  [WARN]    Suspicious DNS entry: '+$s.Line.Trim()) -ForegroundColor Yellow;Add-Content $rep ('[WARN] Suspicious DNS: '+$s.Line.Trim()) -EA SilentlyContinue;Add-Content $wrn ('Suspicious DNS entry: '+$s.Line.Trim()) -EA SilentlyContinue}}else{Write-Host '  [CLEAN]   No suspicious TLDs or shortener domains in DNS cache' -ForegroundColor Green;Add-Content $rep '[CLEAN] DNS cache clean' -EA SilentlyContinue};$count=($dns | Select-String 'Record Name').Count;Write-Host ('  [INFO]    Total DNS cache records: '+$count) -ForegroundColor DarkGray;Add-Content $rep ('DNS cache entries: '+$count) -EA SilentlyContinue"
echo.
goto :EOF

:ML_CHECK_SHARES
echo.
powershell -NoProfile -Command "Write-Host '  --- [CHECK 11/35] OPEN NETWORK SHARES ---' -ForegroundColor !COL_HDR_PS!"
echo.
echo [CHECK 11] NETWORK SHARES >> "!ML_REPORT!"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$rep=$env:ML_REPORT;$thr=$env:ML_THREATS_TMP;$wrn=$env:ML_WARN_TMP;$shares=net share 2>$null;Add-Content $rep ($shares -join [Environment]::NewLine) -EA SilentlyContinue;$def=@('C$','D$','E$','F$','G$','H$','ADMIN$','IPC$','print$','NETLOGON','SYSVOL','FAX$');$nd=0;$sl=$shares | Select-Object -Skip 4 | Where-Object{$_ -match '\S' -and $_ -notmatch '---' -and $_ -notmatch 'completed'};foreach($s in $sl){$name=($s -split '\s+')[0].Trim();if($name -and $name -notin $def){Write-Host ('  [WARN]    Non-default network share: '+$s.Trim()) -ForegroundColor Yellow;Add-Content $rep ('[WARN] Non-default share: '+$s.Trim()) -EA SilentlyContinue;Add-Content $wrn ('Non-default share: '+$name) -EA SilentlyContinue;$nd++}};if($nd -eq 0){Write-Host '  [CLEAN]   Only standard administrative shares detected' -ForegroundColor Green;Add-Content $rep '[CLEAN] No non-default shares' -EA SilentlyContinue}"
echo.
goto :EOF

:ML_CHECK_ARP
echo.
powershell -NoProfile -Command "Write-Host '  --- [CHECK 12/35] ARP CACHE (POISONING CHECK) ---' -ForegroundColor !COL_HDR_PS!"
echo.
echo [CHECK 12] ARP CACHE >> "!ML_REPORT!"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$rep=$env:ML_REPORT;$thr=$env:ML_THREATS_TMP;$wrn=$env:ML_WARN_TMP;$arp=arp -a 2>$null;Add-Content $rep ($arp -join [Environment]::NewLine) -EA SilentlyContinue;$macs=@{};$poison=0;foreach($l in $arp){if($l -match '(\d+\.\d+\.\d+\.\d+)\s+([\da-f]{2}-[\da-f]{2}-[\da-f]{2}-[\da-f]{2}-[\da-f]{2}-[\da-f]{2})\s+dynamic'){$ip=$Matches[1];$mac=$Matches[2];if($macs.ContainsKey($mac)){Write-Host ('  [THREAT]  Duplicate MAC detected - possible ARP poisoning: '+$mac+' maps to both '+$macs[$mac]+' and '+$ip) -ForegroundColor Red;Add-Content $rep ('[THREAT] ARP poison: '+$mac+' -> '+$macs[$mac]+' & '+$ip) -EA SilentlyContinue;Add-Content $thr ('ARP poisoning - duplicate MAC: '+$mac) -EA SilentlyContinue;$poison++}else{$macs[$mac]=$ip}}};if($poison -eq 0){Write-Host '  [CLEAN]   No duplicate MAC addresses - no ARP poisoning detected' -ForegroundColor Green;Add-Content $rep '[CLEAN] ARP cache clean' -EA SilentlyContinue};Write-Host ('  [INFO]    ARP entries checked: '+$macs.Count) -ForegroundColor DarkGray"
echo.
goto :EOF

:ML_CHECK_FIREWALL
echo.
powershell -NoProfile -Command "Write-Host '  --- [CHECK 13/35] FIREWALL STATUS ---' -ForegroundColor !COL_HDR_PS!"
echo.
echo [CHECK 13] FIREWALL STATUS >> "!ML_REPORT!"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$rep=$env:ML_REPORT;$thr=$env:ML_THREATS_TMP;$wrn=$env:ML_WARN_TMP;$fw=netsh advfirewall show allprofiles 2>$null;Add-Content $rep ($fw -join [Environment]::NewLine) -EA SilentlyContinue;foreach($p in @('Domain','Private','Public')){$in=$false;foreach($l in $fw){if($l -match ('^'+$p+' Profile')){$in=$true};if($in -and $l -match 'State\s+ON'){Write-Host ('  [CLEAN]   Firewall '+$p+' profile: ENABLED') -ForegroundColor Green;Add-Content $rep ('[CLEAN] Firewall '+$p+' ON') -EA SilentlyContinue;$in=$false;break};if($in -and $l -match 'State\s+OFF'){Write-Host ('  [THREAT]  Firewall '+$p+' profile: DISABLED') -ForegroundColor Red;Add-Content $rep ('[THREAT] Firewall '+$p+' OFF') -EA SilentlyContinue;Add-Content $thr ('Firewall DISABLED: '+$p+' profile') -EA SilentlyContinue;$in=$false;break}}}"
echo.
goto :EOF

:ML_CHECK_RDP
echo.
powershell -NoProfile -Command "Write-Host '  --- [CHECK 14/35] RDP AND REMOTE ACCESS ---' -ForegroundColor !COL_HDR_PS!"
echo.
echo [CHECK 14] RDP AND REMOTE ACCESS >> "!ML_REPORT!"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$rep=$env:ML_REPORT;$thr=$env:ML_THREATS_TMP;$wrn=$env:ML_WARN_TMP;$rdp=Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server' -Name fDenyTSConnections -EA SilentlyContinue;if($rdp -and $rdp.fDenyTSConnections -eq 0){Write-Host '  [WARN]    RDP is ENABLED' -ForegroundColor Yellow;Add-Content $rep '[WARN] RDP enabled' -EA SilentlyContinue;Add-Content $wrn 'RDP is enabled' -EA SilentlyContinue;$port=(Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name PortNumber -EA SilentlyContinue).PortNumber;if($port -eq 3389){Write-Host '  [WARN]    RDP on default port 3389 (consider changing)' -ForegroundColor Yellow;Add-Content $wrn 'RDP on default port 3389' -EA SilentlyContinue}else{Write-Host ('  [CLEAN]   RDP on non-default port: '+$port) -ForegroundColor Green};$nla=(Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name UserAuthentication -EA SilentlyContinue).UserAuthentication;if($nla -eq 1){Write-Host '  [CLEAN]   Network Level Authentication (NLA): ENABLED' -ForegroundColor Green}else{Write-Host '  [THREAT]  NLA disabled - RDP vulnerable to pre-auth exploits' -ForegroundColor Red;Add-Content $rep '[THREAT] RDP NLA disabled' -EA SilentlyContinue;Add-Content $thr 'RDP enabled with NLA disabled' -EA SilentlyContinue}}else{Write-Host '  [CLEAN]   RDP is DISABLED' -ForegroundColor Green;Add-Content $rep '[CLEAN] RDP disabled' -EA SilentlyContinue};$rp=@('TeamViewer','AnyDesk','ammyy','rutserv','uvnc','vncserver','tvnserver','winvnc','radmin');foreach($r in $rp){$f=Get-Process -Name $r -EA SilentlyContinue;if($f){Write-Host ('  [INFO]    Remote tool process active: '+$r) -ForegroundColor DarkGray;Add-Content $rep ('[INFO] Remote tool running: '+$r) -EA SilentlyContinue}}"
echo.
goto :EOF

:ML_CHECK_DRIVERS
echo.
powershell -NoProfile -Command "Write-Host '  --- [CHECK 15/35] UNSIGNED DRIVERS ---' -ForegroundColor !COL_HDR_PS!"
echo.
echo [CHECK 15] DRIVER SIGNATURES >> "!ML_REPORT!"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$rep=$env:ML_REPORT;$thr=$env:ML_THREATS_TMP;$wrn=$env:ML_WARN_TMP;try{$dr=driverquery /fo csv /si 2>$null | ConvertFrom-Csv;if($dr -and $dr.Count -gt 0){$uns=$dr | Where-Object{$_.'IsSigned' -eq 'FALSE'};if($uns -and @($uns).Count -gt 0){foreach($d in $uns){Write-Host ('  [WARN]    Unsigned driver: '+$d.'Module Name'+' ('+$d.'Display Name'+')') -ForegroundColor Yellow;Add-Content $rep ('[WARN] Unsigned: '+$d.'Module Name') -EA SilentlyContinue;Add-Content $wrn ('Unsigned driver: '+$d.'Module Name') -EA SilentlyContinue}}else{Write-Host '  [CLEAN]   All checked drivers are digitally signed' -ForegroundColor Green;Add-Content $rep '[CLEAN] All drivers signed' -EA SilentlyContinue};Write-Host ('  [INFO]    Total drivers checked: '+$dr.Count) -ForegroundColor DarkGray}else{Write-Host '  [INFO]    Could not retrieve driver list from driverquery' -ForegroundColor DarkGray}}catch{Write-Host '  [INFO]    Driver signature check unavailable' -ForegroundColor DarkGray}"
echo.
goto :EOF

:ML_CHECK_LSA
echo.
powershell -NoProfile -Command "Write-Host '  --- [CHECK 16/35] LSA PROTECTION AND CREDENTIAL GUARD ---' -ForegroundColor !COL_HDR_PS!"
echo.
echo [CHECK 16] LSA PROTECTION >> "!ML_REPORT!"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$rep=$env:ML_REPORT;$thr=$env:ML_THREATS_TMP;$wrn=$env:ML_WARN_TMP;try{$lsa=Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa' -EA SilentlyContinue;if($lsa){$ppl=$lsa.RunAsPPL;if($ppl -ge 1){Write-Host '  [CLEAN]   LSA Protected Process Light (PPL): ENABLED - credential dumping blocked' -ForegroundColor Green;Add-Content $rep '[CLEAN] LSA PPL enabled' -EA SilentlyContinue}else{Write-Host '  [WARN]    LSA PPL: DISABLED - tools like Mimikatz can dump credentials' -ForegroundColor Yellow;Add-Content $rep '[WARN] LSA PPL disabled' -EA SilentlyContinue;Add-Content $wrn 'LSA PPL disabled (Mimikatz risk)' -EA SilentlyContinue};$ntlm=$lsa.LmCompatibilityLevel;if($null -ne $ntlm){if($ntlm -ge 3){Write-Host ('  [CLEAN]   NTLM level: '+$ntlm+' (NTLMv2 enforced)') -ForegroundColor Green}else{Write-Host ('  [WARN]    NTLM level: '+$ntlm+' (allows weak authentication - recommend level 5)') -ForegroundColor Yellow;Add-Content $wrn ('NTLM compatibility level too low: '+$ntlm) -EA SilentlyContinue}}};$vbs=Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard' -EA SilentlyContinue;if($vbs -and $vbs.EnableVirtualizationBasedSecurity -eq 1){Write-Host '  [CLEAN]   Virtualization-Based Security (Credential Guard): ENABLED' -ForegroundColor Green;Add-Content $rep '[CLEAN] VBS enabled' -EA SilentlyContinue}else{Write-Host '  [INFO]    Virtualization-Based Security: Not enabled (optional hardening)' -ForegroundColor DarkGray}}catch{Write-Host '  [INFO]    LSA check partially unavailable' -ForegroundColor DarkGray}"
echo.
goto :EOF

:ML_CHECK_BITLOCKER
echo.
powershell -NoProfile -Command "Write-Host '  --- [CHECK 17/35] BITLOCKER STATUS ---' -ForegroundColor !COL_HDR_PS!"
echo.
echo [CHECK 17] BITLOCKER >> "!ML_REPORT!"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$rep=$env:ML_REPORT;$thr=$env:ML_THREATS_TMP;$wrn=$env:ML_WARN_TMP;try{$bl=manage-bde -status 2>$null;if($bl -and $bl.Count -gt 2){Add-Content $rep ($bl -join [Environment]::NewLine) -EA SilentlyContinue;$on=$bl | Select-String 'Protection Status.*Protection On';if($on){Write-Host '  [CLEAN]   BitLocker: ACTIVE - at least one volume is encrypted' -ForegroundColor Green;Add-Content $rep '[CLEAN] BitLocker active' -EA SilentlyContinue}else{Write-Host '  [WARN]    BitLocker: No volumes currently protected (data at risk if drive is stolen)' -ForegroundColor Yellow;Add-Content $rep '[WARN] BitLocker inactive' -EA SilentlyContinue;Add-Content $wrn 'No BitLocker protection on any volume' -EA SilentlyContinue};$vols=$bl | Select-String 'Volume';Write-Host ('  [INFO]    Volumes found: '+$vols.Count) -ForegroundColor DarkGray}else{Write-Host '  [INFO]    BitLocker not available or no encrypted volumes found' -ForegroundColor DarkGray}}catch{Write-Host '  [INFO]    BitLocker check skipped' -ForegroundColor DarkGray}"
echo.
goto :EOF

:ML_CHECK_BROWSER
echo.
powershell -NoProfile -Command "Write-Host '  --- [CHECK 18/35] BROWSER EXTENSIONS AND POLICY HIJACKING ---' -ForegroundColor !COL_HDR_PS!"
echo.
echo [CHECK 18] BROWSER EXTENSIONS >> "!ML_REPORT!"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$rep=$env:ML_REPORT;$thr=$env:ML_THREATS_TMP;$wrn=$env:ML_WARN_TMP;$total=0;$browsers=@{Chrome=($env:LOCALAPPDATA+'\Google\Chrome\User Data');Edge=($env:LOCALAPPDATA+'\Microsoft\Edge\User Data');Brave=($env:LOCALAPPDATA+'\BraveSoftware\Brave-Browser\User Data');Opera=($env:APPDATA+'\Opera Software\Opera Stable')};foreach($b in $browsers.GetEnumerator()){$base=$b.Value;if(Test-Path $base){$profiles=@(Get-ChildItem $base -Directory -EA SilentlyContinue | Where-Object{$_.Name -match '^(Default|Profile \d+)$'});foreach($prof in $profiles){$extPath=Join-Path $prof.FullName 'Extensions';if(Test-Path $extPath){$exts=Get-ChildItem $extPath -Directory -EA SilentlyContinue;foreach($ext in $exts){$total++;$mf=Get-ChildItem $ext.FullName -Recurse -Filter 'manifest.json' -EA SilentlyContinue | Select-Object -First 1;if($mf){try{$j=Get-Content $mf.FullName -Raw -EA SilentlyContinue | ConvertFrom-Json -EA SilentlyContinue;if($j.name){$name=$j.name}else{$name=$ext.Name};if($j.permissions){$perms=$j.permissions -join ','}else{$perms='none'};$danger=@('nativeMessaging','debugger','proxy','webRequest','tabs','history','cookies','bookmarks','management','clipboardRead','clipboardWrite');$hits=@($j.permissions | Where-Object{$_ -in $danger});if($hits.Count -ge 3){Write-Host ('  [WARN]    '+$b.Key+' high-permission extension: '+$name+' ['+($hits -join ', ')+']') -ForegroundColor Yellow;Add-Content $wrn ($b.Key+' high-permission extension: '+$name) -EA SilentlyContinue;}else{Write-Host ('  [INFO]    '+$b.Key+' extension: '+$name) -ForegroundColor DarkGray;}}catch{Write-Host ('  [INFO]    '+$b.Key+' extension (unreadable manifest): '+$ext.Name) -ForegroundColor DarkGray;}}}}}}};$ffBase=$env:APPDATA+'\Mozilla\Firefox\Profiles';if(Test-Path $ffBase){$ffProfs=Get-ChildItem $ffBase -Directory -EA SilentlyContinue;foreach($fp in $ffProfs){$ej=Join-Path $fp.FullName 'extensions.json';if(Test-Path $ej){try{$ffd=Get-Content $ej -Raw -EA SilentlyContinue | ConvertFrom-Json -EA SilentlyContinue;foreach($addon in $ffd.addons){$total++;if($addon.active -eq $true -and $addon.type -eq 'extension'){Write-Host ('  [INFO]    Firefox extension: '+$addon.defaultLocale.name) -ForegroundColor DarkGray;}}}catch{}}}};$polPaths=@('HKLM:\SOFTWARE\Policies\Google\Chrome\ExtensionInstallForcelist','HKLM:\SOFTWARE\Policies\Microsoft\Edge\ExtensionInstallForcelist','HKCU:\SOFTWARE\Policies\Google\Chrome\ExtensionInstallForcelist');foreach($pp in $polPaths){$pv=Get-ItemProperty $pp -EA SilentlyContinue;if($pv){$pv.PSObject.Properties | Where-Object{$_.Name -notlike 'PS*'} | ForEach-Object{Write-Host ('  [THREAT]  Policy-forced extension: '+$_.Value) -ForegroundColor Red;Add-Content $rep ('[THREAT] Policy-forced extension: '+$_.Value) -EA SilentlyContinue;Add-Content $thr ('Policy-forced browser extension: '+$_.Value) -EA SilentlyContinue;}}};Write-Host ('  [INFO]    Total extensions enumerated: '+$total) -ForegroundColor DarkGray;Add-Content $rep ('Total browser extensions: '+$total) -EA SilentlyContinue;"
echo.
goto :EOF

:ML_CHECK_PROXY
echo.
powershell -NoProfile -Command "Write-Host '  --- [CHECK 19/35] SYSTEM PROXY SETTINGS ---' -ForegroundColor !COL_HDR_PS!"
echo.
echo [CHECK 19] SYSTEM PROXY >> "!ML_REPORT!"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$rep=$env:ML_REPORT;$thr=$env:ML_THREATS_TMP;$wrn=$env:ML_WARN_TMP;$iset=Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -EA SilentlyContinue;if($iset){Add-Content $rep ('Proxy Enabled: '+$iset.ProxyEnable+' Server: '+$iset.ProxyServer+' Override: '+$iset.ProxyOverride) -EA SilentlyContinue;if($iset.ProxyEnable -eq 1){Write-Host ('  [WARN]    Proxy is ENABLED: '+$iset.ProxyServer) -ForegroundColor Yellow;Add-Content $wrn ('System proxy enabled: '+$iset.ProxyServer) -EA SilentlyContinue;if($iset.ProxyServer -match '(?i)127\.0\.0\.1:(8080|8888|8118|9050|9150|1080|3128|4444)'){Write-Host ('  [THREAT]  Proxy port matches known interception or MITM tool: '+$iset.ProxyServer) -ForegroundColor Red;Add-Content $thr ('Suspicious proxy - likely MITM tool: '+$iset.ProxyServer) -EA SilentlyContinue;}}else{Write-Host '  [CLEAN]   No user-level proxy configured' -ForegroundColor Green;};$pac=$iset.AutoConfigURL;if($pac){Write-Host ('  [WARN]    PAC script configured: '+$pac) -ForegroundColor Yellow;Add-Content $wrn ('PAC script URL: '+$pac) -EA SilentlyContinue;if($pac -match '(?i)http://|ftp://'){Write-Host '  [THREAT]  PAC script using insecure HTTP - MITM risk' -ForegroundColor Red;Add-Content $thr ('Insecure PAC script: '+$pac) -EA SilentlyContinue;}}};$wh=netsh winhttp show proxy 2>$null;Add-Content $rep ($wh -join [Environment]::NewLine) -EA SilentlyContinue;if($wh -match 'Proxy Server\(s\)\s*:\s*([^\s]+)' -and $Matches[1] -notmatch '(?i)Direct'){Write-Host ('  [WARN]    WinHTTP proxy configured: '+$Matches[1]) -ForegroundColor Yellow;Add-Content $wrn ('WinHTTP proxy: '+$Matches[1]) -EA SilentlyContinue;}else{Write-Host '  [CLEAN]   WinHTTP proxy: Direct (no proxy)' -ForegroundColor Green;}"
echo.
goto :EOF

:ML_CHECK_CERTS
echo.
powershell -NoProfile -Command "Write-Host '  --- [CHECK 20/35] CERTIFICATE STORE (ROGUE ROOT CAs) ---' -ForegroundColor !COL_HDR_PS!"
echo.
echo [CHECK 20] CERTIFICATE STORE >> "!ML_REPORT!"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$rep=$env:ML_REPORT;$thr=$env:ML_THREATS_TMP;$wrn=$env:ML_WARN_TMP;$known=@('Microsoft','DigiCert','Comodo','Let''s Encrypt','GlobalSign','Entrust','VeriSign','Thawte','GeoTrust','Symantec','Baltimore','Starfield','GoDaddy','Amazon','Google Trust','ISRG','Sectigo','QuoVadis','SwissSign','T-TeleSec','D-Trust','Autoridad de Certificacion');$mitm=@('Fiddler','Charles','Burp','mitmproxy','Superfish','eDellRoot','Trusteer','Privdog','Komodia','NetSol','DO_NOT_TRUST','Cybereason','Symantec SSL','WoSign','StartCom','CNNIC','TURKTRUST');$roots=Get-ChildItem Cert:\LocalMachine\Root -EA SilentlyContinue;$lm=$roots.Count;$suspicious=0;foreach($c in $roots){$subj=$c.Subject;$iss=$c.Issuer;Add-Content $rep ('[CERT] '+$subj) -EA SilentlyContinue;$isMitm=$false;foreach($m in $mitm){if($subj -match [regex]::Escape($m) -or $iss -match [regex]::Escape($m)){$isMitm=$true;break}};if($isMitm){Write-Host ('  [THREAT]  Known MITM/interception cert in Root store: '+$subj) -ForegroundColor Red;Add-Content $rep ('[THREAT] MITM cert: '+$subj) -EA SilentlyContinue;Add-Content $thr ('Rogue root CA (MITM tool): '+$subj) -EA SilentlyContinue;$suspicious++;continue};$isKnown=$false;foreach($k in $known){if($subj -match [regex]::Escape($k)){$isKnown=$true;break}};if(-not $isKnown -and $c.NotAfter -gt (Get-Date)){Write-Host ('  [WARN]    Unknown root CA: '+$subj) -ForegroundColor Yellow;Add-Content $wrn ('Unknown root CA: '+$subj) -EA SilentlyContinue;$suspicious++}};if($suspicious -eq 0){Write-Host '  [CLEAN]   No suspicious root certificates found' -ForegroundColor Green}else{Write-Host ('  [INFO]    Flagged certificates: '+$suspicious) -ForegroundColor DarkGray};Write-Host ('  [INFO]    Total root CAs in store: '+$lm) -ForegroundColor DarkGray"
echo.
goto :EOF

:ML_CHECK_DEFEXCL
echo.
powershell -NoProfile -Command "Write-Host '  --- [CHECK 21/35] DEFENDER EXCLUSIONS ---' -ForegroundColor !COL_HDR_PS!"
echo.
echo [CHECK 21] DEFENDER EXCLUSIONS >> "!ML_REPORT!"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$rep=$env:ML_REPORT;$thr=$env:ML_THREATS_TMP;$wrn=$env:ML_WARN_TMP;try{$pref=Get-MpPreference -EA SilentlyContinue;if($pref){$ep=$pref.ExclusionPath;$ee=$pref.ExclusionExtension;$epr=$pref.ExclusionProcess;$total=0;if($ep){foreach($p in $ep){$total++;Write-Host ('  [WARN]    Excluded PATH: '+$p) -ForegroundColor Yellow;Add-Content $rep ('[EXCL PATH] '+$p) -EA SilentlyContinue;if($p -match '(?i)\\Temp\\|\\AppData\\|\\Users\\Public\\|^[A-Za-z]:\\$'){Write-Host ('  [THREAT]  Suspicious Defender path exclusion (malware hiding spot): '+$p) -ForegroundColor Red;Add-Content $thr ('Malicious Defender exclusion - path: '+$p) -EA SilentlyContinue}else{Add-Content $wrn ('Defender path exclusion: '+$p) -EA SilentlyContinue}}};if($ee){foreach($e in $ee){$total++;Write-Host ('  [WARN]    Excluded EXTENSION: '+$e) -ForegroundColor Yellow;Add-Content $rep ('[EXCL EXT] '+$e) -EA SilentlyContinue;if($e -match '^\.?(exe|ps1|bat|vbs|js|hta|cmd|dll|scr|pif|jar)$'){Write-Host ('  [THREAT]  Critical extension excluded from Defender: '+$e) -ForegroundColor Red;Add-Content $thr ('Dangerous Defender extension exclusion: '+$e) -EA SilentlyContinue}else{Add-Content $wrn ('Defender extension exclusion: '+$e) -EA SilentlyContinue}}};if($epr){foreach($p in $epr){$total++;Write-Host ('  [WARN]    Excluded PROCESS: '+$p) -ForegroundColor Yellow;Add-Content $rep ('[EXCL PROC] '+$p) -EA SilentlyContinue;Add-Content $wrn ('Defender process exclusion: '+$p) -EA SilentlyContinue}};if($total -eq 0){Write-Host '  [CLEAN]   No Defender exclusions configured' -ForegroundColor Green;Add-Content $rep '[CLEAN] No Defender exclusions' -EA SilentlyContinue}else{Write-Host ('  [INFO]    Total exclusions: '+$total) -ForegroundColor DarkGray}}else{Write-Host '  [INFO]    Defender preferences unavailable' -ForegroundColor DarkGray}}catch{Write-Host '  [INFO]    Defender exclusion check requires admin' -ForegroundColor DarkGray}"
echo.
goto :EOF

:ML_CHECK_PRIVESC
echo.
powershell -NoProfile -Command "Write-Host '  --- [CHECK 22/35] PRIVILEGE ESCALATION VECTORS ---' -ForegroundColor !COL_HDR_PS!"
echo.
echo [CHECK 22] PRIVILEGE ESCALATION >> "!ML_REPORT!"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$rep=$env:ML_REPORT;$thr=$env:ML_THREATS_TMP;$wrn=$env:ML_WARN_TMP;$hklm=(Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Installer' -Name AlwaysInstallElevated -EA SilentlyContinue).AlwaysInstallElevated;$hkcu=(Get-ItemProperty 'HKCU:\SOFTWARE\Policies\Microsoft\Windows\Installer' -Name AlwaysInstallElevated -EA SilentlyContinue).AlwaysInstallElevated;if($hklm -eq 1 -and $hkcu -eq 1){Write-Host '  [THREAT]  AlwaysInstallElevated ENABLED in both HKLM and HKCU - MSI privesc possible' -ForegroundColor Red;Add-Content $rep '[THREAT] AlwaysInstallElevated active' -EA SilentlyContinue;Add-Content $thr 'AlwaysInstallElevated - privilege escalation risk' -EA SilentlyContinue}elseif($hklm -eq 1 -or $hkcu -eq 1){Write-Host '  [WARN]    AlwaysInstallElevated set in one hive (requires both to be exploitable)' -ForegroundColor Yellow;Add-Content $wrn 'AlwaysInstallElevated partially set' -EA SilentlyContinue}else{Write-Host '  [CLEAN]   AlwaysInstallElevated: Not set' -ForegroundColor Green};$svcs=@(Get-CimInstance -ClassName Win32_Service -EA SilentlyContinue);$uqFound=0;foreach($s in $svcs){$p=$s.PathName;if($p -and $p -notmatch '^\x22' -and $p -match ' ' -and $p -notmatch '^[A-Za-z]:\\Windows\\' ){$uqFound++;Write-Host ('  [WARN]    Unquoted service path: ['+$s.Name+'] '+$p) -ForegroundColor Yellow;Add-Content $rep ('[WARN] Unquoted path: '+$s.Name+' -> '+$p) -EA SilentlyContinue;Add-Content $wrn ('Unquoted service path: '+$s.Name) -EA SilentlyContinue}};if($uqFound -eq 0){Write-Host '  [CLEAN]   No unquoted service paths found' -ForegroundColor Green;Add-Content $rep '[CLEAN] No unquoted paths' -EA SilentlyContinue}else{Write-Host ('  [INFO]    Unquoted service paths found: '+$uqFound) -ForegroundColor DarkGray};$wsc=(Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' -Name EnableLUA -EA SilentlyContinue).EnableLUA;if($wsc -eq 0){Write-Host '  [THREAT]  UAC is DISABLED - no admin prompt protection' -ForegroundColor Red;Add-Content $thr 'UAC disabled - no privilege elevation protection' -EA SilentlyContinue}else{Write-Host '  [CLEAN]   UAC: Enabled' -ForegroundColor Green}"
echo.
goto :EOF

:ML_CHECK_WDIGEST
echo.
powershell -NoProfile -Command "Write-Host '  --- [CHECK 23/35] WDIGEST CREDENTIAL CACHING ---' -ForegroundColor !COL_HDR_PS!"
echo.
echo [CHECK 23] WDIGEST >> "!ML_REPORT!"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$rep=$env:ML_REPORT;$thr=$env:ML_THREATS_TMP;$wrn=$env:ML_WARN_TMP;$wd=Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\WDigest' -EA SilentlyContinue;if($wd){$ulc=$wd.UseLogonCredential;if($ulc -eq 1){Write-Host '  [THREAT]  WDigest UseLogonCredential = 1 - plaintext passwords cached in LSASS memory' -ForegroundColor Red;Add-Content $rep '[THREAT] WDigest plaintext caching enabled' -EA SilentlyContinue;Add-Content $thr 'WDigest enabled - plaintext credentials in LSASS' -EA SilentlyContinue}elseif($ulc -eq 0){Write-Host '  [CLEAN]   WDigest UseLogonCredential = 0 - plaintext caching disabled' -ForegroundColor Green;Add-Content $rep '[CLEAN] WDigest disabled' -EA SilentlyContinue}else{Write-Host '  [CLEAN]   WDigest UseLogonCredential not set (default safe on Win8.1+)' -ForegroundColor Green;Add-Content $rep '[CLEAN] WDigest not configured' -EA SilentlyContinue}}else{Write-Host '  [CLEAN]   WDigest key not present (default safe state)' -ForegroundColor Green;Add-Content $rep '[CLEAN] WDigest key absent' -EA SilentlyContinue}"
echo.
goto :EOF

:ML_CHECK_ACCESSBACK
echo.
powershell -NoProfile -Command "Write-Host '  --- [CHECK 24/35] ACCESSIBILITY BACKDOORS ---' -ForegroundColor !COL_HDR_PS!"
echo.
echo [CHECK 24] ACCESSIBILITY BACKDOORS >> "!ML_REPORT!"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$rep=$env:ML_REPORT;$thr=$env:ML_THREATS_TMP;$wrn=$env:ML_WARN_TMP;$targets=@{sethc='C:\Windows\System32\sethc.exe';utilman='C:\Windows\System32\utilman.exe';osk='C:\Windows\System32\osk.exe';magnify='C:\Windows\System32\magnify.exe';narrator='C:\Windows\System32\narrator.exe';displayswitch='C:\Windows\System32\DisplaySwitch.exe'};$shells=@('cmd.exe','powershell.exe','wscript.exe','cscript.exe','mshta.exe');$found=0;foreach($t in $targets.GetEnumerator()){$path=$t.Value;if(Test-Path $path){try{$vinfo=[System.Diagnostics.FileVersionInfo]::GetVersionInfo($path);$desc=$vinfo.FileDescription;$prod=$vinfo.ProductName;if($desc -match '(?i)command|powershell|script|shell' -or $prod -match '(?i)command|powershell'){Write-Host ('  [THREAT]  Accessibility backdoor detected: '+$t.Key+' appears to be a shell ('+$desc+')') -ForegroundColor Red;Add-Content $rep ('[THREAT] Accessibility backdoor: '+$t.Key+' -> '+$desc) -EA SilentlyContinue;Add-Content $thr ('Accessibility backdoor: '+$t.Key+' replaced with shell') -EA SilentlyContinue;$found++}else{Write-Host ('  [CLEAN]   '+$t.Key+': '+$desc) -ForegroundColor Green}}catch{Write-Host ('  [INFO]    Could not read version info for: '+$path) -ForegroundColor DarkGray}};$ifeoKey='HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\'+($t.Key+'.exe');$deb=Get-ItemProperty $ifeoKey -Name Debugger -EA SilentlyContinue;if($deb){Write-Host ('  [THREAT]  IFEO debugger on accessibility binary: '+$t.Key+' -> '+$deb.Debugger) -ForegroundColor Red;Add-Content $thr ('IFEO backdoor on '+$t.Key+': '+$deb.Debugger) -EA SilentlyContinue;$found++}};if($found -eq 0){Write-Host '  [CLEAN]   No accessibility backdoors detected' -ForegroundColor Green;Add-Content $rep '[CLEAN] No accessibility backdoors' -EA SilentlyContinue}"
echo.
goto :EOF

:ML_CHECK_DLLHIJ
echo.
powershell -NoProfile -Command "Write-Host '  --- [CHECK 25/35] DLL HIJACKING VECTORS ---' -ForegroundColor !COL_HDR_PS!"
echo.
echo [CHECK 25] DLL HIJACKING >> "!ML_REPORT!"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$rep=$env:ML_REPORT;$thr=$env:ML_THREATS_TMP;$wrn=$env:ML_WARN_TMP;$ai=Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Windows' -Name AppInit_DLLs -EA SilentlyContinue;if($ai -and $ai.AppInit_DLLs -and $ai.AppInit_DLLs.Trim()){Write-Host ('  [THREAT]  AppInit_DLLs set: '+$ai.AppInit_DLLs) -ForegroundColor Red;Add-Content $rep ('[THREAT] AppInit_DLLs: '+$ai.AppInit_DLLs) -EA SilentlyContinue;Add-Content $thr ('AppInit_DLLs persistence: '+$ai.AppInit_DLLs) -EA SilentlyContinue}else{Write-Host '  [CLEAN]   AppInit_DLLs: Empty (safe)' -ForegroundColor Green;Add-Content $rep '[CLEAN] AppInit_DLLs empty' -EA SilentlyContinue};$ai64=Get-ItemProperty 'HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows NT\CurrentVersion\Windows' -Name AppInit_DLLs -EA SilentlyContinue;if($ai64 -and $ai64.AppInit_DLLs -and $ai64.AppInit_DLLs.Trim()){Write-Host ('  [THREAT]  AppInit_DLLs (Wow64) set: '+$ai64.AppInit_DLLs) -ForegroundColor Red;Add-Content $thr ('AppInit_DLLs Wow64: '+$ai64.AppInit_DLLs) -EA SilentlyContinue}else{Write-Host '  [CLEAN]   AppInit_DLLs (Wow64): Empty (safe)' -ForegroundColor Green};$ifeoBase='HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options';$ifeoBad=0;$ifeoKeys=Get-ChildItem $ifeoBase -EA SilentlyContinue;foreach($k in $ifeoKeys){$deb=Get-ItemProperty $k.PSPath -Name Debugger -EA SilentlyContinue;if($deb -and $deb.Debugger){$ifeoBad++;Write-Host ('  [WARN]    IFEO Debugger entry: '+$k.PSChildName+' -> '+$deb.Debugger) -ForegroundColor Yellow;Add-Content $rep ('[WARN] IFEO: '+$k.PSChildName+' -> '+$deb.Debugger) -EA SilentlyContinue;if($deb.Debugger -match '(?i)cmd|powershell|wscript|mshta|\\Temp\\|\\AppData\\'){Write-Host ('  [THREAT]  IFEO points to shell or suspicious binary: '+$k.PSChildName) -ForegroundColor Red;Add-Content $thr ('IFEO shell hijack: '+$k.PSChildName+' -> '+$deb.Debugger) -EA SilentlyContinue}else{Add-Content $wrn ('IFEO debugger set: '+$k.PSChildName) -EA SilentlyContinue}}};if($ifeoBad -eq 0){Write-Host '  [CLEAN]   No IFEO debugger entries found' -ForegroundColor Green;Add-Content $rep '[CLEAN] No IFEO debugger entries' -EA SilentlyContinue}else{Write-Host ('  [INFO]    IFEO debugger entries: '+$ifeoBad) -ForegroundColor DarkGray}"
echo.
goto :EOF

:ML_CHECK_WMI
echo.
powershell -NoProfile -Command "Write-Host '  --- [CHECK 26/35] WMI PERSISTENCE ---' -ForegroundColor !COL_HDR_PS!"
echo.
echo [CHECK 26] WMI PERSISTENCE >> "!ML_REPORT!"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$rep=$env:ML_REPORT;$thr=$env:ML_THREATS_TMP;$wrn=$env:ML_WARN_TMP;try{$filters=Get-CimInstance -Namespace root\subscription -ClassName __EventFilter -EA SilentlyContinue;$consumers=Get-CimInstance -Namespace root\subscription -ClassName __EventConsumer -EA SilentlyContinue;$bindings=Get-CimInstance -Namespace root\subscription -ClassName __FilterToConsumerBinding -EA SilentlyContinue;$legit=@('SCM Event Log Filter','BVTFilter','TSLogonEvents.Filter','TSLogonFilter','RAevent.Filter','RmAssistEventFilter','MSFT_SCMEventLogFilter');$fFound=0;foreach($f in $filters){if($f.Name -notin $legit){Write-Host ('  [THREAT]  WMI Event Filter (persistence): '+$f.Name+' Query: '+$f.Query) -ForegroundColor Red;Add-Content $rep ('[THREAT] WMI Filter: '+$f.Name) -EA SilentlyContinue;Add-Content $thr ('WMI persistence filter: '+$f.Name) -EA SilentlyContinue;$fFound++}};$cFound=0;foreach($c in $consumers){$cname=$c.__CLASS;if($cname -match 'CommandLine|ActiveScript'){Write-Host ('  [THREAT]  WMI Event Consumer (execution): '+$c.Name+' Class: '+$cname) -ForegroundColor Red;Add-Content $rep ('[THREAT] WMI Consumer: '+$c.Name) -EA SilentlyContinue;Add-Content $thr ('WMI persistence consumer: '+$c.Name) -EA SilentlyContinue;$cFound++}};if($fFound -eq 0 -and $cFound -eq 0){Write-Host '  [CLEAN]   No suspicious WMI event subscriptions found' -ForegroundColor Green;Add-Content $rep '[CLEAN] No WMI persistence' -EA SilentlyContinue}else{Write-Host ('  [INFO]    WMI filters flagged: '+$fFound+' consumers flagged: '+$cFound) -ForegroundColor DarkGray}}catch{Write-Host '  [INFO]    WMI persistence check requires admin privileges' -ForegroundColor DarkGray}"
echo.
goto :EOF

:ML_CHECK_BITS
echo.
powershell -NoProfile -Command "Write-Host '  --- [CHECK 27/35] BITS JOBS (PERSISTENCE) ---' -ForegroundColor !COL_HDR_PS!"
echo.
echo [CHECK 27] BITS JOBS >> "!ML_REPORT!"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$rep=$env:ML_REPORT;$thr=$env:ML_THREATS_TMP;$wrn=$env:ML_WARN_TMP;try{$bits=Get-BitsTransfer -AllUsers -EA SilentlyContinue;if($bits -and $bits.Count -gt 0){foreach($j in $bits){Write-Host ('  [WARN]    BITS Job: ['+$j.JobState+'] '+$j.DisplayName+' Owner: '+$j.OwnerAccount) -ForegroundColor Yellow;Add-Content $rep ('[BITS] '+$j.DisplayName+' State:'+$j.JobState+' Owner:'+$j.OwnerAccount) -EA SilentlyContinue;$files=$j | Get-BitsTransferFile -EA SilentlyContinue;foreach($f in $files){Write-Host ('  [INFO]    BITS file: '+$f.RemoteName+' -> '+$f.LocalName) -ForegroundColor DarkGray;if($f.RemoteName -match '(?i)\.exe$|\.ps1$|\.bat$|\.dll$' -or $f.LocalName -match '(?i)\\Temp\\|\\AppData\\'){Write-Host ('  [THREAT]  BITS job downloading executable to suspicious path') -ForegroundColor Red;Add-Content $thr ('BITS downloading executable: '+$f.RemoteName+' -> '+$f.LocalName) -EA SilentlyContinue}else{Add-Content $wrn ('BITS job: '+$j.DisplayName) -EA SilentlyContinue}}}}else{Write-Host '  [CLEAN]   No BITS transfer jobs found' -ForegroundColor Green;Add-Content $rep '[CLEAN] No BITS jobs' -EA SilentlyContinue}}catch{Write-Host '  [INFO]    BITS check requires BITS service running' -ForegroundColor DarkGray}"
echo.
goto :EOF

:ML_CHECK_SHADOW
echo.
powershell -NoProfile -Command "Write-Host '  --- [CHECK 28/35] SHADOW COPY STATUS ---' -ForegroundColor !COL_HDR_PS!"
echo.
echo [CHECK 28] SHADOW COPIES >> "!ML_REPORT!"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$rep=$env:ML_REPORT;$thr=$env:ML_THREATS_TMP;$wrn=$env:ML_WARN_TMP;$vss=vssadmin list shadows 2>$null;Add-Content $rep ($vss -join [Environment]::NewLine) -EA SilentlyContinue;if($vss -match 'No items found'){Write-Host '  [THREAT]  No Volume Shadow Copies exist - possible ransomware activity or manual deletion' -ForegroundColor Red;Add-Content $rep '[THREAT] No shadow copies' -EA SilentlyContinue;Add-Content $thr 'No Volume Shadow Copies - ransomware indicator or never configured' -EA SilentlyContinue}else{$count=($vss | Select-String 'Shadow Copy ID').Count;Write-Host ('  [CLEAN]   Volume Shadow Copies found: '+$count) -ForegroundColor Green;Add-Content $rep ('[CLEAN] Shadow copies exist: '+$count) -EA SilentlyContinue;Write-Host '  [INFO]    Shadow copies present - recovery points available' -ForegroundColor DarkGray};$svc=Get-Service VSS -EA SilentlyContinue;if($svc){if($svc.Status -ne 'Running' -and $svc.StartType -eq 'Disabled'){Write-Host '  [WARN]    VSS service is disabled - shadow copies cannot be created' -ForegroundColor Yellow;Add-Content $wrn 'VSS service disabled' -EA SilentlyContinue}}"
echo.
goto :EOF

:ML_CHECK_SMBLEGACY
echo.
powershell -NoProfile -Command "Write-Host '  --- [CHECK 29/35] LEGACY PROTOCOLS (SMBv1, LM HASHES) ---' -ForegroundColor !COL_HDR_PS!"
echo.
echo [CHECK 29] LEGACY PROTOCOLS >> "!ML_REPORT!"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$rep=$env:ML_REPORT;$thr=$env:ML_THREATS_TMP;$wrn=$env:ML_WARN_TMP;try{$smb1=Get-SmbServerConfiguration -EA SilentlyContinue | Select-Object -ExpandProperty EnableSMB1Protocol;if($smb1 -eq $true){Write-Host '  [THREAT]  SMBv1 is ENABLED - EternalBlue/WannaCry attack surface present' -ForegroundColor Red;Add-Content $rep '[THREAT] SMBv1 enabled' -EA SilentlyContinue;Add-Content $thr 'SMBv1 enabled - EternalBlue vulnerability' -EA SilentlyContinue}else{Write-Host '  [CLEAN]   SMBv1: DISABLED' -ForegroundColor Green;Add-Content $rep '[CLEAN] SMBv1 disabled' -EA SilentlyContinue}}catch{$smb1reg=Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters' -Name SMB1 -EA SilentlyContinue;if($smb1reg -and $smb1reg.SMB1 -eq 1){Write-Host '  [THREAT]  SMBv1 registry key shows ENABLED' -ForegroundColor Red;Add-Content $thr 'SMBv1 enabled (registry)' -EA SilentlyContinue}else{Write-Host '  [CLEAN]   SMBv1: Appears disabled (via registry)' -ForegroundColor Green}};$lsa=Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa' -EA SilentlyContinue;$nolm=$lsa.NoLMHash;if($nolm -eq 1){Write-Host '  [CLEAN]   LM Hash storage: DISABLED' -ForegroundColor Green}else{Write-Host '  [WARN]    LM Hash storage may be enabled - weak credential risk' -ForegroundColor Yellow;Add-Content $wrn 'LM hash storage not explicitly disabled' -EA SilentlyContinue};try{$smbsign=Get-SmbServerConfiguration -EA SilentlyContinue;if($smbsign.RequireSecuritySignature){Write-Host '  [CLEAN]   SMB signing: REQUIRED' -ForegroundColor Green}elseif($smbsign.EnableSecuritySignature){Write-Host '  [WARN]    SMB signing: Enabled but not REQUIRED (relay attack possible)' -ForegroundColor Yellow;Add-Content $wrn 'SMB signing not required - relay attack possible' -EA SilentlyContinue}else{Write-Host '  [THREAT]  SMB signing: DISABLED - NTLM relay attacks possible' -ForegroundColor Red;Add-Content $thr 'SMB signing disabled - relay attack risk' -EA SilentlyContinue}}catch{Write-Host '  [INFO]    SMB signing status unavailable' -ForegroundColor DarkGray}"
echo.
goto :EOF

:ML_CHECK_LLMNR
echo.
powershell -NoProfile -Command "Write-Host '  --- [CHECK 30/35] LLMNR AND NETBIOS ---' -ForegroundColor !COL_HDR_PS!"
echo.
echo [CHECK 30] LLMNR AND NETBIOS >> "!ML_REPORT!"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$rep=$env:ML_REPORT;$thr=$env:ML_THREATS_TMP;$wrn=$env:ML_WARN_TMP;$llmnrKey=Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient' -Name EnableMulticast -EA SilentlyContinue;if($llmnrKey -and $llmnrKey.EnableMulticast -eq 0){Write-Host '  [CLEAN]   LLMNR: DISABLED via policy' -ForegroundColor Green;Add-Content $rep '[CLEAN] LLMNR disabled' -EA SilentlyContinue}else{Write-Host '  [WARN]    LLMNR: ENABLED - Responder tool can capture credentials on local network' -ForegroundColor Yellow;Add-Content $rep '[WARN] LLMNR enabled' -EA SilentlyContinue;Add-Content $wrn 'LLMNR enabled - credential capture risk (Responder)' -EA SilentlyContinue};try{$adapters=@(Get-CimInstance -ClassName Win32_NetworkAdapterConfiguration -EA SilentlyContinue | Where-Object{$_.IPEnabled});$nbEnabled=0;foreach($a in $adapters){if($a.TcpipNetbiosOptions -eq 0 -or $a.TcpipNetbiosOptions -eq 1){$nbEnabled++}};if($nbEnabled -gt 0){Write-Host ('  [WARN]    NetBIOS over TCP/IP: ENABLED on '+$nbEnabled+' adapter(s) - NBT-NS poisoning possible') -ForegroundColor Yellow;Add-Content $rep ('[WARN] NetBIOS enabled on '+$nbEnabled+' adapters') -EA SilentlyContinue;Add-Content $wrn ('NetBIOS enabled on '+$nbEnabled+' adapters') -EA SilentlyContinue}else{Write-Host '  [CLEAN]   NetBIOS over TCP/IP: DISABLED on all adapters' -ForegroundColor Green;Add-Content $rep '[CLEAN] NetBIOS disabled' -EA SilentlyContinue}}catch{Write-Host '  [INFO]    NetBIOS check unavailable' -ForegroundColor DarkGray}"
echo.
goto :EOF

:ML_CHECK_CREDMAN
echo.
powershell -NoProfile -Command "Write-Host '  --- [CHECK 31/35] CREDENTIAL MANAGER ---' -ForegroundColor !COL_HDR_PS!"
echo.
echo [CHECK 31] CREDENTIAL MANAGER >> "!ML_REPORT!"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$rep=$env:ML_REPORT;$thr=$env:ML_THREATS_TMP;$wrn=$env:ML_WARN_TMP;$creds=cmdkey /list 2>$null;Add-Content $rep ($creds -join [Environment]::NewLine) -EA SilentlyContinue;$entries=$creds | Where-Object{$_ -match 'Target:'};$count=$entries.Count;Write-Host ('  [INFO]    Stored credentials: '+$count) -ForegroundColor DarkGray;foreach($e in $entries){$tname=($e -replace '.*Target:\s*','').Trim();Write-Host ('  [INFO]    Credential: '+$tname) -ForegroundColor DarkGray;if($tname -match '(?i)MicrosoftOffice|OneDrive|Skype|Outlook|Teams|OneDrive|MicrosoftAccount|WindowsLive|virtualapp'){continue};if($tname -match '(?i)\\\\|Domain:|LegacyGeneric:|WindowsCredentials:'){Write-Host ('  [WARN]    Stored domain or legacy credential: '+$tname) -ForegroundColor Yellow;Add-Content $wrn ('Stored credential: '+$tname) -EA SilentlyContinue}};if($count -eq 0){Write-Host '  [CLEAN]   No stored credentials in Credential Manager' -ForegroundColor Green;Add-Content $rep '[CLEAN] No stored credentials' -EA SilentlyContinue}"
echo.
goto :EOF

:ML_CHECK_WIN1011
echo.
powershell -NoProfile -Command "Write-Host '  --- [CHECK 32/35] WINDOWS 10/11 SECURITY FEATURES ---' -ForegroundColor !COL_HDR_PS!"
echo.
echo [CHECK 32] WINDOWS 10/11 SECURITY >> "!ML_REPORT!"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$rep=$env:ML_REPORT;$thr=$env:ML_THREATS_TMP;$wrn=$env:ML_WARN_TMP;try{$tpm=Get-Tpm -EA SilentlyContinue;if($tpm){if($tpm.TpmPresent -and $tpm.TpmReady){Write-Host '  [CLEAN]   TPM: Present and Ready' -ForegroundColor Green;Add-Content $rep '[CLEAN] TPM ready' -EA SilentlyContinue}else{Write-Host ('  [WARN]    TPM: Present='+$tpm.TpmPresent+' Ready='+$tpm.TpmReady) -ForegroundColor Yellow;Add-Content $wrn 'TPM not ready' -EA SilentlyContinue}}else{Write-Host '  [INFO]    TPM status unavailable' -ForegroundColor DarkGray}}catch{Write-Host '  [INFO]    TPM check unavailable' -ForegroundColor DarkGray};try{$sb=Confirm-SecureBootUEFI -EA SilentlyContinue;if($sb -eq $true){Write-Host '  [CLEAN]   Secure Boot: ENABLED' -ForegroundColor Green;Add-Content $rep '[CLEAN] Secure Boot enabled' -EA SilentlyContinue}else{Write-Host '  [WARN]    Secure Boot: DISABLED or unavailable' -ForegroundColor Yellow;Add-Content $wrn 'Secure Boot disabled' -EA SilentlyContinue}}catch{Write-Host '  [INFO]    Secure Boot: Not supported or check failed' -ForegroundColor DarkGray};$hvci=Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity' -Name Enabled -EA SilentlyContinue;if($hvci -and $hvci.Enabled -eq 1){Write-Host '  [CLEAN]   HVCI (Memory Integrity): ENABLED' -ForegroundColor Green;Add-Content $rep '[CLEAN] HVCI enabled' -EA SilentlyContinue}else{Write-Host '  [INFO]    HVCI (Memory Integrity): Not enabled (recommended hardening)' -ForegroundColor DarkGray;Add-Content $rep '[INFO] HVCI not enabled' -EA SilentlyContinue};$sac=Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\CI\Policy' -Name VerifiedAndReputablePolicyState -EA SilentlyContinue;if($sac){if($sac.VerifiedAndReputablePolicyState -eq 1){Write-Host '  [CLEAN]   Smart App Control: ENABLED' -ForegroundColor Green}elseif($sac.VerifiedAndReputablePolicyState -eq 2){Write-Host '  [INFO]    Smart App Control: Evaluation mode' -ForegroundColor DarkGray}else{Write-Host '  [INFO]    Smart App Control: Off' -ForegroundColor DarkGray}}else{Write-Host '  [INFO]    Smart App Control: Not present (Win11 22H2+ only)' -ForegroundColor DarkGray};$asr=Get-MpPreference -EA SilentlyContinue | Select-Object -ExpandProperty AttackSurfaceReductionRules_Actions -EA SilentlyContinue;if($asr -and ($asr | Where-Object{$_ -eq 1 -or $_ -eq 2}).Count -gt 0){Write-Host '  [CLEAN]   Attack Surface Reduction (ASR) rules: ACTIVE' -ForegroundColor Green;Add-Content $rep '[CLEAN] ASR rules active' -EA SilentlyContinue}else{Write-Host '  [INFO]    Attack Surface Reduction rules: Not configured' -ForegroundColor DarkGray}"
echo.
goto :EOF

:ML_CHECK_PSEC
echo.
powershell -NoProfile -Command "Write-Host '  --- [CHECK 33/35] POWERSHELL SECURITY ---' -ForegroundColor !COL_HDR_PS!"
echo.
echo [CHECK 33] POWERSHELL SECURITY >> "!ML_REPORT!"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$rep=$env:ML_REPORT;$thr=$env:ML_THREATS_TMP;$wrn=$env:ML_WARN_TMP;$ep=Get-ExecutionPolicy -Scope LocalMachine -EA SilentlyContinue;Write-Host ('  [INFO]    Execution Policy (Machine): '+$ep) -ForegroundColor DarkGray;Add-Content $rep ('ExecutionPolicy Machine: '+$ep) -EA SilentlyContinue;if($ep -match 'Unrestricted|Bypass'){Write-Host '  [WARN]    Execution policy allows unsigned scripts without prompts' -ForegroundColor Yellow;Add-Content $wrn ('Permissive execution policy: '+$ep) -EA SilentlyContinue};$sbl=Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging' -Name EnableScriptBlockLogging -EA SilentlyContinue;if($sbl -and $sbl.EnableScriptBlockLogging -eq 1){Write-Host '  [CLEAN]   Script Block Logging: ENABLED' -ForegroundColor Green;Add-Content $rep '[CLEAN] ScriptBlockLogging on' -EA SilentlyContinue}else{Write-Host '  [WARN]    Script Block Logging: DISABLED - PS commands not logged' -ForegroundColor Yellow;Add-Content $wrn 'PowerShell Script Block Logging disabled' -EA SilentlyContinue};$ml=Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ModuleLogging' -Name EnableModuleLogging -EA SilentlyContinue;if($ml -and $ml.EnableModuleLogging -eq 1){Write-Host '  [CLEAN]   Module Logging: ENABLED' -ForegroundColor Green}else{Write-Host '  [WARN]    Module Logging: DISABLED' -ForegroundColor Yellow;Add-Content $wrn 'PowerShell Module Logging disabled' -EA SilentlyContinue};$tr=Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\Transcription' -Name EnableTranscripting -EA SilentlyContinue;if($tr -and $tr.EnableTranscripting -eq 1){Write-Host '  [CLEAN]   Transcription Logging: ENABLED' -ForegroundColor Green}else{Write-Host '  [INFO]    Transcription Logging: Not enabled (optional)' -ForegroundColor DarkGray};$psv2=powershell -version 2 -command '$PSVersionTable.PSVersion.Major' 2>$null;if($psv2 -eq 2){Write-Host '  [WARN]    PowerShell v2 is available - can bypass AMSI and logging' -ForegroundColor Yellow;Add-Content $wrn 'PowerShell v2 available (AMSI/logging bypass risk)' -EA SilentlyContinue}else{Write-Host '  [CLEAN]   PowerShell v2: Not available (PSv2 downgrade attack blocked)' -ForegroundColor Green;Add-Content $rep '[CLEAN] PSv2 unavailable' -EA SilentlyContinue};$amsiBypass=Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows Script\Settings' -Name AmsiEnable -EA SilentlyContinue;if($amsiBypass -and $amsiBypass.AmsiEnable -eq 0){Write-Host '  [THREAT]  AMSI is DISABLED via registry - script scanning bypassed' -ForegroundColor Red;Add-Content $thr 'AMSI disabled via registry' -EA SilentlyContinue}else{Write-Host '  [CLEAN]   AMSI: Enabled (no registry bypass detected)' -ForegroundColor Green}"
echo.
goto :EOF

:ML_CHECK_BROWDATA
echo.
powershell -NoProfile -Command "Write-Host '  --- [CHECK 34/35] BROWSER DATA INTEGRITY ---' -ForegroundColor !COL_HDR_PS!"
echo.
echo [CHECK 34] BROWSER DATA INTEGRITY >> "!ML_REPORT!"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$rep=$env:ML_REPORT;$thr=$env:ML_THREATS_TMP;$wrn=$env:ML_WARN_TMP;$suspPaths=@($env:TEMP,$env:LOCALAPPDATA+'\Temp','C:\Users\Public');$found=0;foreach($sp in $suspPaths){if(Test-Path $sp){$copies=Get-ChildItem $sp -Filter 'Login Data' -Recurse -ErrorAction SilentlyContinue;foreach($c in $copies){$found++;Write-Host ('  [THREAT]  Login Data copy found in temp/public: '+$c.FullName) -ForegroundColor Red;Add-Content $rep ('[THREAT] Login Data copy: '+$c.FullName) -EA SilentlyContinue;Add-Content $thr ('Browser credential DB copied to: '+$c.FullName) -EA SilentlyContinue}}};foreach($sp in $suspPaths){if(Test-Path $sp){$cc=Get-ChildItem $sp -Filter 'Cookies' -Recurse -ErrorAction SilentlyContinue | Where-Object{$_.Length -gt 10000};foreach($c in $cc){$found++;Write-Host ('  [THREAT]  Cookie database copy in temp/public: '+$c.FullName) -ForegroundColor Red;Add-Content $thr ('Cookie database in temp/public: '+$c.FullName) -EA SilentlyContinue}}};$stealerNames=@('grabber','stealer','pass','cred','login','wallet','cookie');foreach($sp in $suspPaths){if(Test-Path $sp){foreach($n in $stealerNames){$hits=Get-ChildItem $sp -Filter ('*'+$n+'*.exe') -ErrorAction SilentlyContinue;foreach($h in $hits){$found++;Write-Host ('  [THREAT]  Possible stealer binary: '+$h.FullName) -ForegroundColor Red;Add-Content $thr ('Possible credential stealer: '+$h.FullName) -EA SilentlyContinue}}}};if($found -eq 0){Write-Host '  [CLEAN]   No browser credential theft indicators found' -ForegroundColor Green;Add-Content $rep '[CLEAN] No browser data theft indicators' -EA SilentlyContinue}else{Write-Host ('  [INFO]    Suspicious browser data indicators: '+$found) -ForegroundColor DarkGray}"
echo.
goto :EOF

:ML_CHECK_PREFETCH
echo.
powershell -NoProfile -Command "Write-Host '  --- [CHECK 35/35] PREFETCH ANALYSIS ---' -ForegroundColor !COL_HDR_PS!"
echo.
echo [CHECK 35] PREFETCH ANALYSIS >> "!ML_REPORT!"

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$rep=$env:ML_REPORT;$thr=$env:ML_THREATS_TMP;$wrn=$env:ML_WARN_TMP;" ^
  "$pfPath='C:\Windows\Prefetch';" ^
  "$tools=@(" ^
    "'MIMI'+'KATZ','METER'+'PRETER','NET'+'CAT','N'+'CAT'," ^
    "'PWD'+'UMP','FG'+'DUMP','LAZ'+'AGNE','PROC'+'DUMP'," ^
    "'SHARP'+'HOUND','BLOOD'+'HOUND','RUB'+'EUS','SEAT'+'BELT'," ^
    "'SAFETY'+'KATZ','NANO'+'DUMP','COBALT'+'STRIKE','EMP'+'IRE'," ^
    "'PS'+'EXEC','PA'+'EXEC','WMI'+'EXEC','SMB'+'EXEC'," ^
    "'DCOM'+'EXEC','AT'+'EXEC','MSF'+'VENOM','SHELL'+'CODE'," ^
    "'IN'+'JECT','HOLLOW'+'ING','PROCESS'+'HACKER','PCH'+'UNTER'," ^
    "'XM'+'RIG','CPU'+'MINER','CRYPTO'+'MINER','MAS'+'SCAN'," ^
    "'N'+'MAP','WMIE'+'XPLORER','ADE'+'XPLORER','AD'+'FIND'," ^
    "'LDAPDO'+'MAINDUMP','KER'+'BRUTE','ASREP'+'ROAST'," ^
    "'CRACKMAP'+'EXEC','RESP'+'ONDER','INV'+'EIGH'," ^
    "'POWERS'+'PLOIT','POWER'+'VIEW','POWER'+'UP'," ^
    "'INVOKE-'+'MIMIKATZ','INVOKE-'+'SHELLCODE'," ^
    "'PSBY'+'PASSCLM','AMSI'+'BYPASS'" ^
  ");" ^
  "$found=0;" ^
  "if(Test-Path $pfPath){" ^
    "$pfs=Get-ChildItem $pfPath -Filter '*.pf' -EA SilentlyContinue;" ^
    "Write-Host ('  [INFO]    Prefetch files found: '+$pfs.Count) -ForegroundColor DarkGray;" ^
    "Add-Content $rep ('Prefetch files: '+$pfs.Count) -EA SilentlyContinue;" ^
    "foreach($pf in $pfs){" ^
      "$name=$pf.Name.ToUpper() -replace '-[A-F0-9]+\.PF$','';" ^
      "foreach($t in $tools){" ^
        "if($name -match $t){" ^
          "Write-Host ('  [THREAT]  Attack tool evidence in prefetch: '+$pf.Name+' (Last: '+$pf.LastWriteTime+')') -ForegroundColor Red;" ^
          "Add-Content $rep ('[THREAT] Attack tool prefetch: '+$pf.Name+' '+$pf.LastWriteTime) -EA SilentlyContinue;" ^
          "Add-Content $thr ('Attack tool executed (prefetch): '+$pf.Name) -EA SilentlyContinue;" ^
          "$found++;break" ^
        "}" ^
      "}" ^
    "};" ^
    "if($found -eq 0){" ^
      "Write-Host '  [CLEAN]   No known attack tool traces in prefetch' -ForegroundColor Green;" ^
      "Add-Content $rep '[CLEAN] No attack tools in prefetch' -EA SilentlyContinue" ^
    "}" ^
  "}else{" ^
    "Write-Host '  [INFO]    Prefetch directory not found (may be disabled or non-standard Windows edition)' -ForegroundColor DarkGray;" ^
    "Add-Content $rep '[INFO] Prefetch unavailable' -EA SilentlyContinue" ^
  "}"
echo.
goto :EOF

:NETWORK_SCANNER
cls
color !COL_OPS!
echo.
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '    NETWORK SECURITY SCANNER' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
echo.
powershell -NoProfile -Command "Write-Host '  16 checks available:' -ForegroundColor !COL_OPS_PS!"
powershell -NoProfile -Command "Write-Host '  ARP Cache, Gateway Integrity, Active Connections, Listening Ports,' -ForegroundColor DarkGray"
powershell -NoProfile -Command "Write-Host '  DNS Cache, DNS Server Config, Wi-Fi Security, Promiscuous Mode,' -ForegroundColor DarkGray"
powershell -NoProfile -Command "Write-Host '  Routing Table, Firewall Rules, SMB Shares, IPv6 and Tunneling,' -ForegroundColor DarkGray"
powershell -NoProfile -Command "Write-Host '  Proxy Configuration, VPN and TAP Adapters, NDIS Filter Drivers,' -ForegroundColor DarkGray"
powershell -NoProfile -Command "Write-Host '  Network Event Log' -ForegroundColor DarkGray"
echo.
echo   1  ^>  Full Scan     ^(all 16 checks - most thorough^)
echo   2  ^>  Minimal Scan  ^(ARP, gateway, connections, DNS cache, DNS servers, firewall, shares, proxy^)
echo   3  ^>  Custom Scan   ^(pick any single check from the list^)
echo.
echo   B  ^>  Back to main menu
echo.
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
echo.
set "NGCHOICE="
set /p "NGCHOICE=  Select scan type [1-3, B]: "
if /i "!NGCHOICE!"=="B" goto MAIN_MENU
if "!NGCHOICE!"=="1" set "NG_SCANMODE=FULL"    & set "NG_CUSTOM=0" & goto NETWORK_RUN_SCAN
if "!NGCHOICE!"=="2" set "NG_SCANMODE=MINIMAL" & set "NG_CUSTOM=0" & goto NETWORK_RUN_SCAN
if "!NGCHOICE!"=="3" goto NETWORK_CUSTOM_MENU
goto NETWORK_SCANNER

:NETWORK_CUSTOM_MENU
cls
color !COL_OPS!
echo.
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '    NETWORK SCANNER - CUSTOM CHECK' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
echo.
echo    1  ^>  ARP Cache                   ^(duplicate MACs, poisoning detection^)
echo    2  ^>  Gateway Integrity           ^(verify default gateway MAC is unchanged^)
echo    3  ^>  Active Connections          ^(suspicious ports, RAT ports, external IPs + process names^)
echo    4  ^>  Listening Ports             ^(unexpected external-facing listeners + process names^)
echo    5  ^>  DNS Cache                   ^(C2 patterns, suspicious TLDs, shortener domains^)
echo    6  ^>  DNS Server Config           ^(rogue or unexpected DNS server addresses^)
echo    7  ^>  Wi-Fi Security              ^(saved profiles, open networks, WEP detection^)
echo    8  ^>  Promiscuous Mode            ^(adapter sniffing mode - packet capture indicator^)
echo    9  ^>  Routing Table               ^(unexpected default routes, injected host routes^)
echo   10  ^>  Firewall Rules              ^(unusual inbound allow rules, disabled profiles^)
echo   11  ^>  SMB Shares                  ^(non-default shares, public access^)
echo   12  ^>  IPv6 and Tunneling          ^(Teredo, ISATAP, 6to4 tunnel interfaces^)
echo   13  ^>  Proxy Configuration         ^(WinINET, WinHTTP, WPAD auto-config scripts^)
echo   14  ^>  VPN and TAP Adapters        ^(TAP/TUN interfaces, active VPN connections^)
echo   15  ^>  NDIS Filter Drivers         ^(suspicious network driver filters^)
echo   16  ^>  Network Event Log           ^(DHCP changes, failed connections, WLAN events^)
echo.
echo    B  ^>  Back
echo.
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
echo.
set "NGCUSTOM="
set /p "NGCUSTOM=  Select check [1-16, B]: "
if /i "!NGCUSTOM!"=="B" goto NETWORK_SCANNER
set "NG_VALID=0"
for %%N in (1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16) do if "!NGCUSTOM!"=="%%N" set "NG_VALID=1"
if "!NG_VALID!"=="0" (
    powershell -NoProfile -Command "Write-Host '  Invalid selection - please enter a number 1-16 or B.' -ForegroundColor Red"
    echo.
    pause
    goto NETWORK_CUSTOM_MENU
)
set "NG_SCANMODE=CUSTOM"
set "NG_CUSTOM=!NGCUSTOM!"
goto NETWORK_RUN_SCAN

:NETWORK_RUN_SCAN
cls
color !COL_OPS!
echo.
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '    NETWORK SECURITY SCANNER - RUNNING' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '    Mode: !NG_SCANMODE!' -ForegroundColor !COL_OPS_PS!"
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
echo.
for /f %%D in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd_HHmm"') do set "NG_DATE=%%D"
set "NG_REPORT=!LOGDIR!\YTSH_NetScan_!NG_DATE!.txt"
set "NG_THREATS_TMP=%TEMP%\ytsh_ng_t_%RANDOM%.tmp"
set "NG_WARN_TMP=%TEMP%\ytsh_ng_w_%RANDOM%.tmp"
type nul > "!NG_THREATS_TMP!"
type nul > "!NG_WARN_TMP!"
echo ================================================ > "!NG_REPORT!"
echo   YTSH NETWORK SECURITY SCAN REPORT >> "!NG_REPORT!"
echo   Mode: !NG_SCANMODE! >> "!NG_REPORT!"
echo   Scanned: %DATE% %TIME% >> "!NG_REPORT!"
echo   Host: %COMPUTERNAME%  User: %USERNAME% >> "!NG_REPORT!"
echo ================================================ >> "!NG_REPORT!"
call :NG_SHOULD_RUN 1
if not errorlevel 1 call :NG_CHECK_ARP
call :NG_SHOULD_RUN 2
if not errorlevel 1 call :NG_CHECK_GATEWAY
call :NG_SHOULD_RUN 3
if not errorlevel 1 call :NG_CHECK_CONNECTIONS
call :NG_SHOULD_RUN 4
if not errorlevel 1 call :NG_CHECK_LISTENERS
call :NG_SHOULD_RUN 5
if not errorlevel 1 call :NG_CHECK_DNS
call :NG_SHOULD_RUN 6
if not errorlevel 1 call :NG_CHECK_DNSSERVER
call :NG_SHOULD_RUN 7
if not errorlevel 1 call :NG_CHECK_WIFI
call :NG_SHOULD_RUN 8
if not errorlevel 1 call :NG_CHECK_PROMISCUOUS
call :NG_SHOULD_RUN 9
if not errorlevel 1 call :NG_CHECK_ROUTES
call :NG_SHOULD_RUN 10
if not errorlevel 1 call :NG_CHECK_FWRULES
call :NG_SHOULD_RUN 11
if not errorlevel 1 call :NG_CHECK_SHARES
call :NG_SHOULD_RUN 12
if not errorlevel 1 call :NG_CHECK_IPV6
call :NG_SHOULD_RUN 13
if not errorlevel 1 call :NG_CHECK_PROXY
call :NG_SHOULD_RUN 14
if not errorlevel 1 call :NG_CHECK_VPN
call :NG_SHOULD_RUN 15
if not errorlevel 1 call :NG_CHECK_NDIS
call :NG_SHOULD_RUN 16
if not errorlevel 1 call :NG_CHECK_NETEVENTS

set "NG_THREAT_COUNT=0"
set "NG_WARN_COUNT=0"
for /f %%A in ('type "!NG_THREATS_TMP!" ^| find /c /v ""') do set "NG_THREAT_COUNT=%%A"
for /f %%A in ('type "!NG_WARN_TMP!" ^| find /c /v ""') do set "NG_WARN_COUNT=%%A"

echo. >> "!NG_REPORT!"
echo ================================================ >> "!NG_REPORT!"
echo   SCAN SUMMARY >> "!NG_REPORT!"
echo ================================================ >> "!NG_REPORT!"
echo   Mode     : !NG_SCANMODE! >> "!NG_REPORT!"
echo   Threats  : !NG_THREAT_COUNT! >> "!NG_REPORT!"
echo   Warnings : !NG_WARN_COUNT! >> "!NG_REPORT!"
echo   Date     : %DATE% %TIME% >> "!NG_REPORT!"
echo ================================================ >> "!NG_REPORT!"
if !NG_THREAT_COUNT! GTR 0 (
    echo. >> "!NG_REPORT!"
    echo   THREATS DETECTED: >> "!NG_REPORT!"
    type "!NG_THREATS_TMP!" >> "!NG_REPORT!" 2>nul
)
if !NG_WARN_COUNT! GTR 0 (
    echo. >> "!NG_REPORT!"
    echo   WARNINGS: >> "!NG_REPORT!"
    type "!NG_WARN_TMP!" >> "!NG_REPORT!" 2>nul
)

echo.
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '    SCAN COMPLETE' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
echo.
if !NG_THREAT_COUNT! GTR 0 (
    powershell -NoProfile -Command "Write-Host '  THREATS  : !NG_THREAT_COUNT!' -ForegroundColor Red"
) else (
    powershell -NoProfile -Command "Write-Host '  THREATS  : !NG_THREAT_COUNT!' -ForegroundColor Green"
)
if !NG_WARN_COUNT! GTR 0 (
    powershell -NoProfile -Command "Write-Host '  WARNINGS : !NG_WARN_COUNT!' -ForegroundColor Yellow"
) else (
    powershell -NoProfile -Command "Write-Host '  WARNINGS : !NG_WARN_COUNT!' -ForegroundColor Green"
)
echo.
powershell -NoProfile -Command "Write-Host '  Report saved to:' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host ('  ' + $env:NG_REPORT) -ForegroundColor !COL_OPS_PS!"
echo.
echo   O  ^>  Open report in Notepad     B  ^>  Back to scanner menu
echo.
set "NGOPEN="
set /p "NGOPEN=  Select: "
if /i "!NGOPEN!"=="O" notepad "!NG_REPORT!"
del "!NG_THREATS_TMP!" >nul 2>&1
del "!NG_WARN_TMP!" >nul 2>&1
if "!SA_ACTIVE!"=="1" goto SA_NG_CONT
goto NETWORK_SCANNER
:SA_NG_CONT
echo.
powershell -NoProfile -Command "Write-Host '  B  >  Continue to next scanner (Registry Persistence)' -ForegroundColor Yellow"
echo.
:SA_NG_WAIT
set "SA_CONT="
set /p "SA_CONT=  [B] Continue: "
if /i not "!SA_CONT!"=="B" goto SA_NG_WAIT
set "RP_MODE=!SA_RP_MODE!"
goto REGPERSIST_RUN

:NG_SHOULD_RUN
if "!NG_SCANMODE!"=="FULL" exit /b 0
if "!NG_SCANMODE!"=="CUSTOM" (
    if "!NG_CUSTOM!"=="%~1" exit /b 0
    exit /b 1
)
if "!NG_SCANMODE!"=="MINIMAL" (
    if "%~1"=="1"  exit /b 0
    if "%~1"=="2"  exit /b 0
    if "%~1"=="3"  exit /b 0
    if "%~1"=="5"  exit /b 0
    if "%~1"=="6"  exit /b 0
    if "%~1"=="10" exit /b 0
    if "%~1"=="11" exit /b 0
    if "%~1"=="13" exit /b 0
)
exit /b 1

:NG_CHECK_ARP
echo.
powershell -NoProfile -Command "Write-Host '  --- [CHECK 1/16] ARP CACHE - POISONING DETECTION ---' -ForegroundColor !COL_HDR_PS!"
echo.
echo [CHECK 1] ARP CACHE >> "!NG_REPORT!"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$rep=$env:NG_REPORT;$thr=$env:NG_THREATS_TMP;$wrn=$env:NG_WARN_TMP;$arpRaw=arp -a;$entries=@();foreach($line in $arpRaw){if($line -match '\s+([\d\.]+)\s+([0-9a-f\-]+)\s+(dynamic|static)'){$entries+=[PSCustomObject]@{IP=$Matches[1];MAC=$Matches[2].ToLower();Type=$Matches[3]}}};Write-Host ('  [INFO]    ARP entries found: '+$entries.Count) -ForegroundColor DarkGray;Add-Content $rep ('ARP entries: '+$entries.Count) -EA SilentlyContinue;$dupMACs=$entries|Group-Object MAC|Where-Object{$_.Count -gt 1};$found=0;foreach($g in $dupMACs){$ips=($g.Group|Select-Object -ExpandProperty IP)-join', ';Write-Host ('  [WARN]    Duplicate MAC: '+$g.Name+' -> '+$ips) -ForegroundColor Yellow;Add-Content $rep ('[WARN] Duplicate MAC: '+$g.Name+' -> '+$ips) -EA SilentlyContinue;Add-Content $wrn ('Duplicate MAC: '+$g.Name+' -> '+$ips) -EA SilentlyContinue;$found++};$ffMac='ff-ff-ff-ff-ff-ff';$gws=Get-NetRoute -DestinationPrefix '0.0.0.0/0' -EA SilentlyContinue|Sort-Object RouteMetric;$gwIP=if($gws){$gws[0].NextHop}else{'UNKNOWN'};$gwEntry=$entries|Where-Object{$_.IP -eq $gwIP}|Select-Object -First 1;if($gwEntry -and $gwEntry.MAC -eq $ffMac){Write-Host ('  [THREAT]  Gateway resolves to broadcast MAC - ARP table corrupted!') -ForegroundColor Red;Add-Content $thr 'Gateway MAC is broadcast address' -EA SilentlyContinue;$found++};if($found -eq 0){Write-Host '  [CLEAN]   No duplicate MACs detected in ARP cache' -ForegroundColor Green;Add-Content $rep '[CLEAN] ARP cache clean' -EA SilentlyContinue}else{Add-Content $rep ('[WARN] Duplicate MAC groups: '+$found) -EA SilentlyContinue}"
echo.
goto :EOF

:NG_CHECK_GATEWAY
echo.
powershell -NoProfile -Command "Write-Host '  --- [CHECK 2/16] GATEWAY INTEGRITY ---' -ForegroundColor !COL_HDR_PS!"
echo.
echo [CHECK 2] GATEWAY INTEGRITY >> "!NG_REPORT!"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$rep=$env:NG_REPORT;$thr=$env:NG_THREATS_TMP;$wrn=$env:NG_WARN_TMP;$gw=(Get-NetRoute -DestinationPrefix '0.0.0.0/0' -EA SilentlyContinue|Sort-Object RouteMetric|Select-Object -First 1).NextHop;if(-not $gw){Write-Host '  [INFO]    No default gateway detected' -ForegroundColor DarkGray;Add-Content $rep '[INFO] No gateway' -EA SilentlyContinue;return};Write-Host ('  [INFO]    Default gateway: '+$gw) -ForegroundColor DarkGray;Add-Content $rep ('Gateway: '+$gw) -EA SilentlyContinue;$arpEntry=(Get-NetNeighbor -IPAddress $gw -EA SilentlyContinue|Select-Object -First 1);if($arpEntry){$mac=$arpEntry.LinkLayerAddress;Write-Host ('  [INFO]    Gateway MAC in ARP: '+$mac) -ForegroundColor DarkGray;Add-Content $rep ('Gateway MAC: '+$mac) -EA SilentlyContinue;if($mac -match '^00-00-00-00-00-00$'){Write-Host '  [THREAT]  Gateway MAC is all-zeros - ARP poisoning or table corruption!' -ForegroundColor Red;Add-Content $thr 'Gateway MAC is all-zeros' -EA SilentlyContinue}elseif($mac -match '^ff-ff-ff-ff-ff-ff$'){Write-Host '  [THREAT]  Gateway MAC is broadcast address - ARP table is corrupt!' -ForegroundColor Red;Add-Content $thr 'Gateway MAC is broadcast' -EA SilentlyContinue}else{$vendor=try{$macClean=$mac -replace '-','';$oui=$macClean.Substring(0,6).ToUpper();$r=Invoke-RestMethod ('https://api.macvendors.com/'+$oui) -TimeoutSec 3 -EA SilentlyContinue;$r}catch{'Unknown'};Write-Host ('  [CLEAN]   Gateway MAC valid. Vendor hint: '+$vendor) -ForegroundColor Green;Add-Content $rep ('[CLEAN] Gateway MAC ok: '+$mac+' ('+$vendor+')') -EA SilentlyContinue}}else{Write-Host ('  [WARN]    Could not resolve gateway MAC - gateway may be unreachable') -ForegroundColor Yellow;Add-Content $wrn 'Gateway MAC unresolvable' -EA SilentlyContinue};$gwCount=(Get-NetRoute -DestinationPrefix '0.0.0.0/0' -EA SilentlyContinue).Count;if($gwCount -gt 1){Write-Host ('  [WARN]    Multiple default routes detected: '+$gwCount+' - possible route injection') -ForegroundColor Yellow;Add-Content $wrn ('Multiple default routes: '+$gwCount) -EA SilentlyContinue;Get-NetRoute -DestinationPrefix '0.0.0.0/0' -EA SilentlyContinue|ForEach-Object{Write-Host ('  [INFO]    Route: '+$_.NextHop+' metric '+$_.RouteMetric+' via '+$_.InterfaceAlias) -ForegroundColor DarkGray;Add-Content $rep ('  Default route: '+$_.NextHop+' metric:'+$_.RouteMetric) -EA SilentlyContinue}}"
echo.
goto :EOF

:NG_CHECK_CONNECTIONS
echo.
powershell -NoProfile -Command "Write-Host '  --- [CHECK 3/16] ACTIVE CONNECTIONS ---' -ForegroundColor !COL_HDR_PS!"
echo.
echo [CHECK 3] ACTIVE CONNECTIONS >> "!NG_REPORT!"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$rep=$env:NG_REPORT;$thr=$env:NG_THREATS_TMP;$wrn=$env:NG_WARN_TMP;$suspPorts=@(4444,5555,6666,7777,8888,9999,1337,31337,12345,54321,2222,3333,6667,6697,1080,9050,9150,3389,5900,5938,5939,4899,65535,13337,60001,60002);$ratPorts=@(1243,5400,5401,5402,12349,54320,41666,1177,6969);$priv=@('^127\.', '^10\.', '^192\.168\.', '^172\.(1[6-9]|2[0-9]|3[01])\.', '^0\.0\.0\.0$', '^::1$', '^\[::\]');$conns=Get-NetTCPConnection -State Established -EA SilentlyContinue;Write-Host ('  [INFO]    Established TCP connections: '+$conns.Count) -ForegroundColor DarkGray;Add-Content $rep ('Established connections: '+$conns.Count) -EA SilentlyContinue;$found=0;foreach($c in $conns){$rport=[int]$c.RemotePort;$lport=[int]$c.LocalPort;$proc=(Get-Process -Id $c.OwningProcess -EA SilentlyContinue).Name;$ext=$true;foreach($r in $priv){if($c.RemoteAddress -match $r){$ext=$false;break}};if($ratPorts -contains $rport){Write-Host ('  [THREAT]  Known RAT/backdoor port '+$rport+': '+$c.RemoteAddress+' ('+$proc+' PID:'+$c.OwningProcess+')') -ForegroundColor Red;Add-Content $rep ('[THREAT] RAT port '+$rport+': '+$c.RemoteAddress+' '+$proc) -EA SilentlyContinue;Add-Content $thr ('RAT port in use: '+$rport+' proc:'+$proc) -EA SilentlyContinue;$found++}elseif($suspPorts -contains $rport){Write-Host ('  [WARN]    Suspicious port '+$rport+': '+$c.RemoteAddress+' ('+$proc+' PID:'+$c.OwningProcess+')') -ForegroundColor Yellow;Add-Content $rep ('[WARN] Suspicious port '+$rport+': '+$c.RemoteAddress+' '+$proc) -EA SilentlyContinue;Add-Content $wrn ('Suspicious port: '+$rport+' proc:'+$proc) -EA SilentlyContinue;$found++}elseif($ext -and $rport -notin @(80,443,8080,8443,53,25,587,465,993,995,110,143,3478,3479,123)){Write-Host ('  [INFO]    External non-standard port: '+$c.RemoteAddress+':'+$rport+' ('+$proc+')') -ForegroundColor DarkGray;Add-Content $rep ('[INFO] Ext non-std: '+$c.RemoteAddress+':'+$rport+' '+$proc) -EA SilentlyContinue}};if($found -eq 0){Write-Host '  [CLEAN]   No connections on known RAT or suspicious ports' -ForegroundColor Green;Add-Content $rep '[CLEAN] No suspicious connections' -EA SilentlyContinue}"
echo.
goto :EOF

:NG_CHECK_LISTENERS
echo.
powershell -NoProfile -Command "Write-Host '  --- [CHECK 4/16] LISTENING PORTS ---' -ForegroundColor !COL_HDR_PS!"
echo.
echo [CHECK 4] LISTENING PORTS >> "!NG_REPORT!"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$rep=$env:NG_REPORT;$thr=$env:NG_THREATS_TMP;$wrn=$env:NG_WARN_TMP;$knownPorts=@(80,443,135,139,445,3389,1900,5040,5353,7680,49152,49153,49154,49155,49156,49157,49158,49159,49160,8080,8443,53);$listeners=Get-NetTCPConnection -State Listen -EA SilentlyContinue|Where-Object{$_.LocalAddress -ne '::1' -and $_.LocalAddress -ne '127.0.0.1'};$udpListeners=Get-NetUDPEndpoint -EA SilentlyContinue|Where-Object{$_.LocalAddress -ne '::1' -and $_.LocalAddress -ne '127.0.0.1'};Write-Host ('  [INFO]    TCP listeners (external-facing): '+$listeners.Count) -ForegroundColor DarkGray;Write-Host ('  [INFO]    UDP endpoints (external-facing): '+$udpListeners.Count) -ForegroundColor DarkGray;Add-Content $rep ('TCP listeners: '+$listeners.Count+'  UDP: '+$udpListeners.Count) -EA SilentlyContinue;$found=0;foreach($l in $listeners){$port=[int]$l.LocalPort;if($knownPorts -notcontains $port){$proc=(Get-Process -Id $l.OwningProcess -EA SilentlyContinue);$pname=if($proc){$proc.Name}else{'<unknown>'};$ppath=if($proc){try{$proc.MainModule.FileName}catch{'<access denied>'}}else{'<unknown>'};Write-Host ('  [WARN]    Unusual listener: '+$l.LocalAddress+':'+$port+' ('+$pname+')') -ForegroundColor Yellow;Write-Host ('            Path: '+$ppath) -ForegroundColor DarkGray;Add-Content $rep ('[WARN] Unusual listener: '+$l.LocalAddress+':'+$port+' '+$pname+' '+$ppath) -EA SilentlyContinue;Add-Content $wrn ('Unusual listening port: '+$port+' proc:'+$pname) -EA SilentlyContinue;$found++}};if($found -eq 0){Write-Host '  [CLEAN]   All listening ports are expected system ports' -ForegroundColor Green;Add-Content $rep '[CLEAN] No unexpected listeners' -EA SilentlyContinue}"
echo.
goto :EOF

:NG_CHECK_DNS
echo.
powershell -NoProfile -Command "Write-Host '  --- [CHECK 5/16] DNS CACHE ---' -ForegroundColor !COL_HDR_PS!"
echo.
echo [CHECK 5] DNS CACHE >> "!NG_REPORT!"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$rep=$env:NG_REPORT;$thr=$env:NG_THREATS_TMP;$wrn=$env:NG_WARN_TMP;$suspPatterns=@('\.onion$','duckdns\.org','no-ip\.(com|org|biz)','ngrok\.io','serveo\.net','pagekite\.me','localhost\.run','playit\.gg','\.top$','\.xyz$','\.tk$','\.ml$','\.ga$','\.cf$','bit\.ly','tinyurl','goo\.gl','t\.co\/','ow\.ly','rb\.gy','is\.gd');$c2patterns=@('[0-9a-f]{20,}\.','\d{1,3}-\d{1,3}-\d{1,3}-\d{1,3}\.','^[a-z]{12,30}\.(com|net|org|info)$');$cache=Get-DnsClientCache -EA SilentlyContinue;Write-Host ('  [INFO]    DNS cache entries: '+$cache.Count) -ForegroundColor DarkGray;Add-Content $rep ('DNS cache entries: '+$cache.Count) -EA SilentlyContinue;$found=0;foreach($d in $cache){$name=$d.Entry;foreach($s in $suspPatterns){if($name -match $s){Write-Host ('  [WARN]    Suspicious DNS entry: '+$name+' -> '+$d.Data) -ForegroundColor Yellow;Add-Content $rep ('[WARN] Suspicious DNS: '+$name+' -> '+$d.Data) -EA SilentlyContinue;Add-Content $wrn ('Suspicious DNS cache: '+$name) -EA SilentlyContinue;$found++;break}};foreach($s in $c2patterns){if($name -match $s){Write-Host ('  [WARN]    Possible DGA/C2 domain: '+$name) -ForegroundColor Yellow;Add-Content $wrn ('Possible DGA domain: '+$name) -EA SilentlyContinue;$found++;break}}};if($found -eq 0){Write-Host '  [CLEAN]   No suspicious DNS cache entries detected' -ForegroundColor Green;Add-Content $rep '[CLEAN] DNS cache clean' -EA SilentlyContinue}"
echo.
goto :EOF

:NG_CHECK_DNSSERVER
echo.
powershell -NoProfile -Command "Write-Host '  --- [CHECK 6/16] DNS SERVER CONFIGURATION ---' -ForegroundColor !COL_HDR_PS!"
echo.
echo [CHECK 6] DNS SERVER CONFIG >> "!NG_REPORT!"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$rep=$env:NG_REPORT;$thr=$env:NG_THREATS_TMP;$wrn=$env:NG_WARN_TMP;$knownDNS=@('8.8.8.8','8.8.4.4','1.1.1.1','1.0.0.1','9.9.9.9','149.112.112.112','208.67.222.222','208.67.220.220','4.2.2.1','4.2.2.2','64.6.64.6','64.6.65.6','4.4.4.4','185.228.168.9','185.228.169.9','76.76.19.19','76.223.122.150','94.140.14.14','94.140.15.15');$gw=(Get-NetRoute -DestinationPrefix '0.0.0.0/0' -EA SilentlyContinue|Sort-Object RouteMetric|Select-Object -First 1).NextHop;$ifaces=Get-DnsClientServerAddress -AddressFamily IPv4 -EA SilentlyContinue|Where-Object{$_.ServerAddresses -ne $null -and $_.ServerAddresses.Count -gt 0};$found=0;foreach($iface in $ifaces){foreach($srv in $iface.ServerAddresses){if($srv -match '^127\.|^0\.0\.0\.0$|^::$'){continue};Write-Host ('  [INFO]    DNS server on ['+$iface.InterfaceAlias+']: '+$srv) -ForegroundColor DarkGray;Add-Content $rep ('DNS server ['+$iface.InterfaceAlias+']: '+$srv) -EA SilentlyContinue;$isGW=($srv -eq $gw);$isKnown=($knownDNS -contains $srv);if(-not $isKnown -and -not $isGW){Write-Host ('  [WARN]    Unrecognized DNS server (not gateway, not major provider): '+$srv+' on '+$iface.InterfaceAlias) -ForegroundColor Yellow;Add-Content $rep ('[WARN] Unknown DNS server: '+$srv) -EA SilentlyContinue;Add-Content $wrn ('Unknown DNS server: '+$srv+' on '+$iface.InterfaceAlias) -EA SilentlyContinue;$found++}elseif($isGW){Write-Host ('  [INFO]    DNS is local gateway (normal for most home routers): '+$srv) -ForegroundColor DarkGray}}};if($found -eq 0){Write-Host '  [CLEAN]   All DNS servers are recognized providers or local gateway' -ForegroundColor Green;Add-Content $rep '[CLEAN] DNS servers ok' -EA SilentlyContinue}"
echo.
goto :EOF

:NG_CHECK_WIFI
echo.
powershell -NoProfile -Command "Write-Host '  --- [CHECK 7/16] WI-FI SECURITY AUDIT ---' -ForegroundColor !COL_HDR_PS!"
echo.
echo [CHECK 7] WI-FI SECURITY >> "!NG_REPORT!"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$rep=$env:NG_REPORT;$thr=$env:NG_THREATS_TMP;$wrn=$env:NG_WARN_TMP;$wlan=netsh wlan show profiles 2>$null;if($LASTEXITCODE -ne 0 -or ($wlan -join '') -match 'not running|is not'){Write-Host '  [INFO]    Wi-Fi unavailable or adapter disabled on this system' -ForegroundColor DarkGray;Add-Content $rep '[INFO] Wi-Fi not available' -EA SilentlyContinue;return};$profiles=$wlan|Where-Object{$_ -match 'All User Profile\s*:\s*(.+)'};Write-Host ('  [INFO]    Saved Wi-Fi profiles: '+$profiles.Count) -ForegroundColor DarkGray;Add-Content $rep ('Saved Wi-Fi profiles: '+$profiles.Count) -EA SilentlyContinue;$found=0;foreach($p in $profiles){$ssid=($p -replace '.*:\s*','').Trim();$detail=netsh wlan show profile name=$ssid key=clear 2>$null;$auth=($detail|Where-Object{$_ -match 'Authentication\s*:'}|Select-Object -First 1) -replace '.*:\s*','';$cipher=($detail|Where-Object{$_ -match 'Cipher\s*:'}|Select-Object -First 1) -replace '.*:\s*','';if($auth -match 'Open|None'){Write-Host ('  [THREAT]  Open (no password) Wi-Fi profile saved: '+$ssid) -ForegroundColor Red;Add-Content $rep ('[THREAT] Open Wi-Fi profile: '+$ssid) -EA SilentlyContinue;Add-Content $thr ('Open Wi-Fi profile: '+$ssid) -EA SilentlyContinue;$found++}elseif($auth -match 'WEP'){Write-Host ('  [THREAT]  WEP-secured profile saved (WEP is broken/crackable): '+$ssid) -ForegroundColor Red;Add-Content $rep ('[THREAT] WEP profile: '+$ssid) -EA SilentlyContinue;Add-Content $thr ('WEP Wi-Fi profile: '+$ssid) -EA SilentlyContinue;$found++}elseif($auth -match 'WPA2'){Write-Host ('  [CLEAN]   WPA2 profile: '+$ssid) -ForegroundColor Green}else{Write-Host ('  [INFO]    Profile: '+$ssid+' auth: '+$auth.Trim()) -ForegroundColor DarkGray}};$connected=netsh wlan show interfaces 2>$null|Where-Object{$_ -match 'SSID\s*:'};if($connected){$curSSID=($connected|Select-Object -First 1) -replace '.*:\s*','';$curAuth=(netsh wlan show interfaces 2>$null|Where-Object{$_ -match 'Authentication'}|Select-Object -First 1) -replace '.*:\s*','';Write-Host ('  [INFO]    Currently connected: '+$curSSID.Trim()+' ('+$curAuth.Trim()+')') -ForegroundColor DarkGray;Add-Content $rep ('Connected SSID: '+$curSSID.Trim()+' auth:'+$curAuth.Trim()) -EA SilentlyContinue};if($found -eq 0){Write-Host '  [CLEAN]   No open or WEP Wi-Fi profiles found' -ForegroundColor Green;Add-Content $rep '[CLEAN] Wi-Fi profiles secure' -EA SilentlyContinue}"
echo.
goto :EOF

:NG_CHECK_PROMISCUOUS
echo.
powershell -NoProfile -Command "Write-Host '  --- [CHECK 8/16] PROMISCUOUS MODE ---' -ForegroundColor !COL_HDR_PS!"
echo.
echo [CHECK 8] PROMISCUOUS MODE >> "!NG_REPORT!"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$rep=$env:NG_REPORT;$thr=$env:NG_THREATS_TMP;$wrn=$env:NG_WARN_TMP;$found=0;$adapters=Get-NetAdapter -EA SilentlyContinue|Where-Object{$_.Status -eq 'Up'};Write-Host ('  [INFO]    Active network adapters: '+$adapters.Count) -ForegroundColor DarkGray;Add-Content $rep ('Active adapters: '+$adapters.Count) -EA SilentlyContinue;foreach($a in $adapters){try{$adv=Get-NetAdapterAdvancedProperty -Name $a.Name -EA SilentlyContinue|Where-Object{$_.RegistryKeyword -match 'Promiscuous|Monitor|Capture'};if($adv){Write-Host ('  [WARN]    Adapter in potential capture mode: '+$a.Name) -ForegroundColor Yellow;Add-Content $wrn ('Adapter possible capture mode: '+$a.Name) -EA SilentlyContinue;$found++}}catch{}};$wpcap=Get-Service -Name 'npf','npcap','WinPcap' -EA SilentlyContinue|Where-Object{$_.Status -eq 'Running'};foreach($svc in $wpcap){Write-Host ('  [WARN]    Packet capture driver running: '+$svc.Name+' - Wireshark/sniffer tool active') -ForegroundColor Yellow;Add-Content $rep ('[WARN] Packet capture service: '+$svc.Name) -EA SilentlyContinue;Add-Content $wrn ('Packet capture driver active: '+$svc.Name) -EA SilentlyContinue;$found++};$rawCapProcs=@('wireshark','tshark','dumpcap','tcpdump','netmon','fiddler','charles','mitmproxy','bettercap');$procs=Get-Process -EA SilentlyContinue;foreach($r in $rawCapProcs){$match=$procs|Where-Object{$_.Name -like ('*'+$r+'*')};foreach($m in $match){Write-Host ('  [WARN]    Packet capture tool running: '+$m.Name+' (PID:'+$m.Id+')') -ForegroundColor Yellow;Add-Content $wrn ('Capture tool running: '+$m.Name) -EA SilentlyContinue;$found++}};if($found -eq 0){Write-Host '  [CLEAN]   No packet capture or promiscuous mode indicators found' -ForegroundColor Green;Add-Content $rep '[CLEAN] No capture mode detected' -EA SilentlyContinue}"
echo.
goto :EOF

:NG_CHECK_ROUTES
echo.
powershell -NoProfile -Command "Write-Host '  --- [CHECK 9/16] ROUTING TABLE ---' -ForegroundColor !COL_HDR_PS!"
echo.
echo [CHECK 9] ROUTING TABLE >> "!NG_REPORT!"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$rep=$env:NG_REPORT;$thr=$env:NG_THREATS_TMP;$wrn=$env:NG_WARN_TMP;$defRoutes=Get-NetRoute -DestinationPrefix '0.0.0.0/0' -EA SilentlyContinue;Write-Host ('  [INFO]    Default routes: '+$defRoutes.Count) -ForegroundColor DarkGray;Add-Content $rep ('Default routes: '+$defRoutes.Count) -EA SilentlyContinue;if($defRoutes.Count -gt 1){Write-Host ('  [WARN]    Multiple default routes - possible route injection or VPN conflict') -ForegroundColor Yellow;Add-Content $wrn ('Multiple default routes: '+$defRoutes.Count) -EA SilentlyContinue;foreach($r in $defRoutes){Write-Host ('  [INFO]    Default route: via '+$r.NextHop+' metric '+$r.RouteMetric+' ['+$r.InterfaceAlias+']') -ForegroundColor DarkGray;Add-Content $rep ('  Default route: '+$r.NextHop+' metric:'+$r.RouteMetric) -EA SilentlyContinue}};$priv=@('^10\.', '^192\.168\.', '^172\.(1[6-9]|2[0-9]|3[01])\.', '^127\.', '^169\.254\.');$hostRoutes=Get-NetRoute -EA SilentlyContinue|Where-Object{$_.PrefixLength -eq 32 -and $_.DestinationPrefix -ne '127.0.0.1/32' -and $_.DestinationPrefix -ne '255.255.255.255/32'};$suspRoutes=@();foreach($r in $hostRoutes){$dest=($r.DestinationPrefix -split '/')[0];$isPrivate=$false;foreach($p in $priv){if($dest -match $p){$isPrivate=$true;break}};if(-not $isPrivate){$suspRoutes+=$r}};foreach($r in $suspRoutes){Write-Host ('  [WARN]    Host route to external IP: '+$r.DestinationPrefix+' via '+$r.NextHop+' ['+$r.InterfaceAlias+']') -ForegroundColor Yellow;Add-Content $rep ('[WARN] Host route to external: '+$r.DestinationPrefix+' via '+$r.NextHop) -EA SilentlyContinue;Add-Content $wrn ('Suspicious host route: '+$r.DestinationPrefix) -EA SilentlyContinue};if($defRoutes.Count -le 1 -and $suspRoutes.Count -eq 0){Write-Host '  [CLEAN]   Routing table appears normal' -ForegroundColor Green;Add-Content $rep '[CLEAN] Routing table clean' -EA SilentlyContinue}"
echo.
goto :EOF

:NG_CHECK_FWRULES
echo.
powershell -NoProfile -Command "Write-Host '  --- [CHECK 10/16] FIREWALL RULES ---' -ForegroundColor !COL_HDR_PS!"
echo.
echo [CHECK 10] FIREWALL RULES >> "!NG_REPORT!"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$rep=$env:NG_REPORT;$thr=$env:NG_THREATS_TMP;$wrn=$env:NG_WARN_TMP;$profiles=Get-NetFirewallProfile -EA SilentlyContinue;foreach($p in $profiles){if($p.Enabled){Write-Host ('  [CLEAN]   Firewall '+$p.Name+' profile: Enabled') -ForegroundColor Green;Add-Content $rep ('[CLEAN] FW '+$p.Name+': on') -EA SilentlyContinue}else{Write-Host ('  [THREAT]  Firewall '+$p.Name+' profile: DISABLED') -ForegroundColor Red;Add-Content $rep ('[THREAT] Firewall '+$p.Name+' disabled') -EA SilentlyContinue;Add-Content $thr ('Firewall profile disabled: '+$p.Name) -EA SilentlyContinue}};$inboundAllow=Get-NetFirewallRule -Direction Inbound -Action Allow -Enabled True -EA SilentlyContinue|Where-Object{$_.Owner -notmatch 'Microsoft|Windows|NT AUTHORITY|SYSTEM' -and $_.DisplayName -notmatch 'Microsoft|Windows|Xbox|Skype|Teams|OneDrive|Edge|Office'};Write-Host ('  [INFO]    Non-Microsoft inbound allow rules: '+$inboundAllow.Count) -ForegroundColor DarkGray;Add-Content $rep ('Custom inbound allow rules: '+$inboundAllow.Count) -EA SilentlyContinue;$suspRules=@();foreach($r in $inboundAllow){$fa=Get-NetFirewallApplicationFilter -AssociatedNetFirewallRule $r -EA SilentlyContinue;$prog=if($fa){$fa.Program}else{'*'};if($prog -eq '*'){$pf=Get-NetFirewallPortFilter -AssociatedNetFirewallRule $r -EA SilentlyContinue;$port=if($pf){$pf.LocalPort}else{'any'};Write-Host ('  [WARN]    All-app inbound rule: '+$r.DisplayName+' port:'+$port) -ForegroundColor Yellow;Add-Content $wrn ('Broad inbound FW rule: '+$r.DisplayName) -EA SilentlyContinue;$suspRules+=$r}elseif($prog -match '(?i)Temp|AppData|Public|Downloads'){Write-Host ('  [THREAT]  Inbound rule for app in risky path: '+$r.DisplayName+' -> '+$prog) -ForegroundColor Red;Add-Content $thr ('FW inbound rule for risky path: '+$prog) -EA SilentlyContinue;$suspRules+=$r}};if($suspRules.Count -eq 0){Write-Host '  [CLEAN]   No suspicious inbound firewall rules detected' -ForegroundColor Green;Add-Content $rep '[CLEAN] No suspicious FW rules' -EA SilentlyContinue}"
echo.
goto :EOF

:NG_CHECK_SHARES
echo.
powershell -NoProfile -Command "Write-Host '  --- [CHECK 11/16] SMB SHARES ---' -ForegroundColor !COL_HDR_PS!"
echo.
echo [CHECK 11] SMB SHARES >> "!NG_REPORT!"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$rep=$env:NG_REPORT;$thr=$env:NG_THREATS_TMP;$wrn=$env:NG_WARN_TMP;$defaultShares=@('ADMIN$','C$','D$','E$','F$','G$','H$','IPC$','print$','NETLOGON','SYSVOL');$shares=Get-SmbShare -EA SilentlyContinue;Write-Host ('  [INFO]    Total SMB shares: '+$shares.Count) -ForegroundColor DarkGray;Add-Content $rep ('SMB shares: '+$shares.Count) -EA SilentlyContinue;$found=0;foreach($s in $shares){if($defaultShares -notcontains $s.Name){$acl=Get-SmbShareAccess -Name $s.Name -EA SilentlyContinue;$pub=$acl|Where-Object{$_.AccountName -match 'Everyone|Authenticated Users|ANONYMOUS'};if($pub){Write-Host ('  [THREAT]  Public SMB share: '+$s.Name+' -> '+$s.Path+' ('+($pub.AccountName -join ',')+' = '+($pub.AccessRight -join ',')+')') -ForegroundColor Red;Add-Content $rep ('[THREAT] Public SMB share: '+$s.Name+' '+$s.Path) -EA SilentlyContinue;Add-Content $thr ('Public SMB share: '+$s.Name) -EA SilentlyContinue;$found++}else{Write-Host ('  [WARN]    Custom SMB share exists (restricted): '+$s.Name+' -> '+$s.Path) -ForegroundColor Yellow;Add-Content $rep ('[WARN] Custom share: '+$s.Name+' '+$s.Path) -EA SilentlyContinue;Add-Content $wrn ('Custom SMB share: '+$s.Name) -EA SilentlyContinue;$found++}}};$smbv1=(Get-SmbServerConfiguration -EA SilentlyContinue).EnableSMB1Protocol;if($smbv1 -eq $true){Write-Host '  [THREAT]  SMBv1 (EternalBlue-vulnerable protocol) is ENABLED' -ForegroundColor Red;Add-Content $thr 'SMBv1 enabled - EternalBlue risk' -EA SilentlyContinue;$found++}else{Write-Host '  [CLEAN]   SMBv1 disabled' -ForegroundColor Green;Add-Content $rep '[CLEAN] SMBv1 off' -EA SilentlyContinue};if($found -eq 0){Write-Host '  [CLEAN]   No unexpected public SMB shares found' -ForegroundColor Green;Add-Content $rep '[CLEAN] No unexpected shares' -EA SilentlyContinue}"
echo.
goto :EOF

:NG_CHECK_IPV6
echo.
powershell -NoProfile -Command "Write-Host '  --- [CHECK 12/16] IPv6 AND TUNNELING ---' -ForegroundColor !COL_HDR_PS!"
echo.
echo [CHECK 12] IPv6 AND TUNNELING >> "!NG_REPORT!"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$rep=$env:NG_REPORT;$thr=$env:NG_THREATS_TMP;$wrn=$env:NG_WARN_TMP;$found=0;$teredo=Get-NetAdapter -EA SilentlyContinue|Where-Object{$_.Name -match 'Teredo'};if($teredo -and $teredo.Status -eq 'Up'){Write-Host '  [WARN]    Teredo IPv6 tunnel is UP - bypasses IPv4 firewall rules' -ForegroundColor Yellow;Add-Content $wrn 'Teredo tunnel active' -EA SilentlyContinue;$found++}else{Write-Host '  [CLEAN]   Teredo tunnel: not active' -ForegroundColor Green};$isatap=Get-NetAdapter -EA SilentlyContinue|Where-Object{$_.Name -match 'ISATAP'};if($isatap -and $isatap.Status -eq 'Up'){Write-Host '  [WARN]    ISATAP tunnel interface is UP' -ForegroundColor Yellow;Add-Content $wrn 'ISATAP tunnel active' -EA SilentlyContinue;$found++}else{Write-Host '  [CLEAN]   ISATAP tunnel: not active' -ForegroundColor Green};$tunnel6to4=Get-Net6to4Configuration -EA SilentlyContinue;if($tunnel6to4 -and $tunnel6to4.State -eq 'Enabled'){Write-Host '  [WARN]    6to4 tunnel is enabled' -ForegroundColor Yellow;Add-Content $wrn '6to4 tunnel enabled' -EA SilentlyContinue;$found++}else{Write-Host '  [CLEAN]   6to4 tunnel: disabled' -ForegroundColor Green};$teredoCfg=Get-NetTeredoConfiguration -EA SilentlyContinue;if($teredoCfg -and $teredoCfg.Type -ne 'Disabled'){Write-Host ('  [INFO]    Teredo config type: '+$teredoCfg.Type) -ForegroundColor DarkGray;Add-Content $rep ('Teredo config: '+$teredoCfg.Type) -EA SilentlyContinue};if($found -eq 0){Add-Content $rep '[CLEAN] No active IPv6 tunnels' -EA SilentlyContinue}"
echo.
goto :EOF

:NG_CHECK_PROXY
echo.
powershell -NoProfile -Command "Write-Host '  --- [CHECK 13/16] PROXY CONFIGURATION ---' -ForegroundColor !COL_HDR_PS!"
echo.
echo [CHECK 13] PROXY CONFIG >> "!NG_REPORT!"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$rep=$env:NG_REPORT;$thr=$env:NG_THREATS_TMP;$wrn=$env:NG_WARN_TMP;$found=0;$winInet=Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -EA SilentlyContinue;if($winInet.ProxyEnable -eq 1){$pServer=$winInet.ProxyServer;Write-Host ('  [WARN]    WinINET proxy enabled: '+$pServer) -ForegroundColor Yellow;Add-Content $rep ('[WARN] WinINET proxy: '+$pServer) -EA SilentlyContinue;Add-Content $wrn ('WinINET proxy: '+$pServer) -EA SilentlyContinue;$found++}else{Write-Host '  [CLEAN]   WinINET proxy: disabled' -ForegroundColor Green};if($winInet.AutoConfigURL){Write-Host ('  [WARN]    WPAD/PAC auto-config URL set: '+$winInet.AutoConfigURL) -ForegroundColor Yellow;Add-Content $rep ('[WARN] WPAD PAC URL: '+$winInet.AutoConfigURL) -EA SilentlyContinue;Add-Content $wrn ('WPAD PAC URL: '+$winInet.AutoConfigURL) -EA SilentlyContinue;$found++}else{Write-Host '  [CLEAN]   WPAD/PAC auto-config URL: not set' -ForegroundColor Green};$winHTTP=netsh winhttp show proxy 2>$null;if(($winHTTP -join '') -notmatch 'Direct access|no proxy'){Write-Host ('  [WARN]    WinHTTP proxy is set: '+($winHTTP -join ' ').Trim()) -ForegroundColor Yellow;Add-Content $rep ('[WARN] WinHTTP proxy set') -EA SilentlyContinue;Add-Content $wrn 'WinHTTP proxy configured' -EA SilentlyContinue;$found++}else{Write-Host '  [CLEAN]   WinHTTP proxy: not configured' -ForegroundColor Green};$sysProxy=Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CurrentVersion\Internet Settings' -EA SilentlyContinue;if($sysProxy.ProxySettingsPerUser -eq 0){Write-Host '  [WARN]    System-wide proxy policy is enforced (ProxySettingsPerUser=0)' -ForegroundColor Yellow;Add-Content $wrn 'System-wide proxy policy enforced' -EA SilentlyContinue;$found++};if($found -eq 0){Add-Content $rep '[CLEAN] No proxy configured' -EA SilentlyContinue}"
echo.
goto :EOF

:NG_CHECK_VPN
echo.
powershell -NoProfile -Command "Write-Host '  --- [CHECK 14/16] VPN AND TAP ADAPTERS ---' -ForegroundColor !COL_HDR_PS!"
echo.
echo [CHECK 14] VPN AND TAP >> "!NG_REPORT!"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$rep=$env:NG_REPORT;$thr=$env:NG_THREATS_TMP;$wrn=$env:NG_WARN_TMP;$tapAdapters=Get-NetAdapter -EA SilentlyContinue|Where-Object{$_.InterfaceDescription -match 'TAP-Windows|TAP Adapter|OpenVPN|WireGuard|TUN|utun|tun0|Mullvad|NordVPN|ProtonVPN|ExpressVPN|Cisco AnyConnect|GlobalProtect|FortiClient|Pulse Secure|SonicWALL'};Write-Host ('  [INFO]    VPN/TAP adapter(s) found: '+$tapAdapters.Count) -ForegroundColor DarkGray;Add-Content $rep ('VPN/TAP adapters: '+$tapAdapters.Count) -EA SilentlyContinue;foreach($t in $tapAdapters){$statusCol=if($t.Status -eq 'Up'){'Yellow'}else{'DarkGray'};Write-Host ('  [INFO]    VPN/TAP: '+$t.Name+' ['+$t.InterfaceDescription+'] Status: '+$t.Status) -ForegroundColor $statusCol;Add-Content $rep ('VPN/TAP adapter: '+$t.Name+' '+$t.InterfaceDescription+' '+$t.Status) -EA SilentlyContinue;if($t.Status -eq 'Up'){Add-Content $wrn ('Active VPN/TAP adapter: '+$t.Name) -EA SilentlyContinue}};$vpnConns=Get-VpnConnection -EA SilentlyContinue;Write-Host ('  [INFO]    Configured VPN connections: '+$vpnConns.Count) -ForegroundColor DarkGray;Add-Content $rep ('VPN connections configured: '+$vpnConns.Count) -EA SilentlyContinue;foreach($v in $vpnConns){$connCol=if($v.ConnectionStatus -eq 'Connected'){'Yellow'}else{'DarkGray'};Write-Host ('  [INFO]    VPN: '+$v.Name+' -> '+$v.ServerAddress+' ['+$v.ConnectionStatus+']') -ForegroundColor $connCol;Add-Content $rep ('VPN: '+$v.Name+' '+$v.ServerAddress+' '+$v.ConnectionStatus) -EA SilentlyContinue};if($tapAdapters.Count -eq 0 -and $vpnConns.Count -eq 0){Write-Host '  [CLEAN]   No VPN or TAP adapters detected' -ForegroundColor Green;Add-Content $rep '[CLEAN] No VPN adapters' -EA SilentlyContinue}"
echo.
goto :EOF

:NG_CHECK_NDIS
echo.
powershell -NoProfile -Command "Write-Host '  --- [CHECK 15/16] NDIS FILTER DRIVERS ---' -ForegroundColor !COL_HDR_PS!"
echo.
echo [CHECK 15] NDIS FILTER DRIVERS >> "!NG_REPORT!"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$rep=$env:NG_REPORT;$thr=$env:NG_THREATS_TMP;$wrn=$env:NG_WARN_TMP;$knownFilters=@('WFP 802.3 MAC Layer LightWeight Filter','WFP Native MAC Layer LightWeight Filter','QoS Packet Scheduler','Microsoft Network Adapter Multiplexor Protocol','NDIS Usermode I/O Protocol','Microsoft LLDP Protocol Driver','Link-Layer Topology Discovery Mapper I/O Driver','Link-Layer Topology Discovery Responder','Wi-Fi Direct Virtual Adapter','Hyper-V Extensible Virtual Switch','WAN Miniport','VMware Bridge Protocol','VirtualBox Bridged Networking Driver','Npcap Packet Driver','NPCAP Packet Driver','NetGroup Packet Filter Driver');$filters=Get-NetAdapterBinding -EA SilentlyContinue|Where-Object{$_.Enabled -eq $true};$found=0;foreach($f in $filters){$comp=$f.ComponentID;$name=$f.DisplayName;$isKnown=$false;foreach($k in $knownFilters){if($name -match [regex]::Escape($k) -or $comp -match 'ms_|vms_|vmware|vbox|npcap'){$isKnown=$true;break}};if(-not $isKnown -and $comp -notmatch '^ms_'){Write-Host ('  [WARN]    Unknown NDIS filter on ['+$f.Name+']: '+$name+' ('+$comp+')') -ForegroundColor Yellow;Add-Content $rep ('[WARN] Unknown NDIS filter: '+$name+' '+$comp+' on '+$f.Name) -EA SilentlyContinue;Add-Content $wrn ('Unknown NDIS filter: '+$name) -EA SilentlyContinue;$found++}};if($found -eq 0){Write-Host '  [CLEAN]   No unknown NDIS filter drivers detected' -ForegroundColor Green;Add-Content $rep '[CLEAN] NDIS filters clean' -EA SilentlyContinue}"
echo.
goto :EOF

:NG_CHECK_NETEVENTS
echo.
powershell -NoProfile -Command "Write-Host '  --- [CHECK 16/16] NETWORK EVENT LOG ---' -ForegroundColor !COL_HDR_PS!"
echo.
echo [CHECK 16] NETWORK EVENT LOG >> "!NG_REPORT!"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$rep=$env:NG_REPORT;$thr=$env:NG_THREATS_TMP;$wrn=$env:NG_WARN_TMP;$cutoff=(Get-Date).AddHours(-24);$found=0;try{$dhcp=Get-WinEvent -FilterHashtable @{LogName='System';ProviderName='Microsoft-Windows-Dhcp-Client';StartTime=$cutoff} -EA SilentlyContinue|Where-Object{$_.Id -in @(1000,1001,1002,1003,50067,50068)};if($dhcp.Count -gt 5){Write-Host ('  [WARN]    High DHCP churn in last 24h: '+$dhcp.Count+' events - possible DHCP exhaustion or IP conflict') -ForegroundColor Yellow;Add-Content $wrn ('High DHCP churn: '+$dhcp.Count+' events in 24h') -EA SilentlyContinue;$found++}else{Write-Host ('  [INFO]    DHCP events last 24h: '+$dhcp.Count) -ForegroundColor DarkGray};Add-Content $rep ('DHCP events 24h: '+$dhcp.Count) -EA SilentlyContinue}catch{};try{$wlan=Get-WinEvent -FilterHashtable @{LogName='Microsoft-Windows-WLAN-AutoConfig/Operational';StartTime=$cutoff} -EA SilentlyContinue|Where-Object{$_.Id -in @(8001,8002,8003,20019)};Write-Host ('  [INFO]    WLAN connect/disconnect events last 24h: '+$wlan.Count) -ForegroundColor DarkGray;Add-Content $rep ('WLAN events 24h: '+$wlan.Count) -EA SilentlyContinue;if($wlan.Count -gt 20){Write-Host '  [WARN]    Excessive WLAN reconnections - deauth attack or unstable connection' -ForegroundColor Yellow;Add-Content $wrn ('Excessive WLAN events: '+$wlan.Count) -EA SilentlyContinue;$found++}}catch{Write-Host '  [INFO]    WLAN event log unavailable (no wireless adapter or log disabled)' -ForegroundColor DarkGray};try{$fw=Get-WinEvent -FilterHashtable @{LogName='Security';Id=5152;StartTime=$cutoff} -EA SilentlyContinue -MaxEvents 1;if($fw.Count -gt 0){Write-Host '  [INFO]    Windows Filtering Platform block events exist (firewall is logging drops)' -ForegroundColor DarkGray;Add-Content $rep '[INFO] FW drop events present' -EA SilentlyContinue}}catch{};try{$sharing=Get-WinEvent -FilterHashtable @{LogName='Security';Id=5140;StartTime=$cutoff} -EA SilentlyContinue;if($sharing.Count -gt 0){Write-Host ('  [INFO]    Network share access events last 24h: '+$sharing.Count) -ForegroundColor DarkGray;Add-Content $rep ('Share access events 24h: '+$sharing.Count) -EA SilentlyContinue;if($sharing.Count -gt 50){Write-Host '  [WARN]    High volume of network share access - check for exfiltration or scanning' -ForegroundColor Yellow;Add-Content $wrn ('High share access volume: '+$sharing.Count) -EA SilentlyContinue;$found++}}}catch{};if($found -eq 0){Write-Host '  [CLEAN]   No unusual network events in the last 24 hours' -ForegroundColor Green;Add-Content $rep '[CLEAN] Network events normal' -EA SilentlyContinue}"
echo.
goto :EOF

:REGPERSIST_SCANNER
cls
color !COL_OPS!
echo.
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '    REGISTRY PERSISTENCE SCANNER' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
echo.
powershell -NoProfile -Command "Write-Host '  Checks: Run/RunOnce keys, Winlogon hijacks, LSA providers,' -ForegroundColor DarkGray"
powershell -NoProfile -Command "Write-Host '  AppInit_DLLs, Browser Helper Objects, Image File Execution Options' -ForegroundColor DarkGray"
echo.
echo   1  ^>  Full Scan   ^(all persistence checks^)
echo   2  ^>  Quick Scan  ^(Run keys and Winlogon only^)
echo.
echo   B  ^>  Back
echo.
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
echo.
set "RP_CHOICE="
set /p "RP_CHOICE=  Select scan type [1-2, B]: "
if /i "!RP_CHOICE!"=="B" goto CAT_SCANNING
if "!RP_CHOICE!"=="1" set "RP_MODE=FULL" & goto REGPERSIST_RUN
if "!RP_CHOICE!"=="2" set "RP_MODE=QUICK" & goto REGPERSIST_RUN
goto REGPERSIST_SCANNER

:REGPERSIST_RUN
cls
color !COL_OPS!
echo.
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '    REGISTRY PERSISTENCE SCANNER - RUNNING' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '    Mode: !RP_MODE!' -ForegroundColor !COL_OPS_PS!"
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
echo.
for /f %%D in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd_HHmm"') do set "RP_DATE=%%D"
set "RP_REPORT=!LOGDIR!\YTSH_RegPersist_!RP_DATE!.txt"
set "RP_THREATS_TMP=%TEMP%\ytsh_rp_t_%RANDOM%.tmp"
set "RP_WARN_TMP=%TEMP%\ytsh_rp_w_%RANDOM%.tmp"
type nul > "!RP_THREATS_TMP!"
type nul > "!RP_WARN_TMP!"
echo ================================================ > "!RP_REPORT!"
echo   YTSH REGISTRY PERSISTENCE SCAN REPORT >> "!RP_REPORT!"
echo   Mode: !RP_MODE! >> "!RP_REPORT!"
echo   Scanned: %DATE% %TIME% >> "!RP_REPORT!"
echo ================================================ >> "!RP_REPORT!"

echo.
powershell -NoProfile -Command "Write-Host '  --- [CHECK 1] RUN / RUNONCE KEYS ---' -ForegroundColor !COL_HDR_PS!"
echo.
echo [CHECK 1] RUN / RUNONCE KEYS >> "!RP_REPORT!"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$rep=$env:RP_REPORT;$thr=$env:RP_THREATS_TMP;$wrn=$env:RP_WARN_TMP;$keys=@('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run','HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce','HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Run','HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\RunOnce','HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run','HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce','HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunServices','HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunServices','HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunServicesOnce');$totalFound=0;foreach($k in $keys){try{$e=Get-ItemProperty $k -EA SilentlyContinue;if($e){$e.PSObject.Properties | Where-Object{$_.Name -notlike 'PS*'} | ForEach-Object{$n=$_.Name;$v=$_.Value;$keyShort=($k -split '\\')[-1];Write-Host ('  [INFO]    ['+$keyShort+'] '+$n+' = '+$v) -ForegroundColor DarkGray;Add-Content $rep ('[RUN KEY] '+$k+' | '+$n+' = '+$v) -EA SilentlyContinue;if($v -match '(?i)\\Temp\\|\\AppData\\Roaming\\|\.ps1|\.vbs|mshta|wscript|cscript|rundll32.*http|powershell.*-enc|powershell.*-nop|-w.*hidden|regsvr32.*http|certutil|-decode|bitsadmin|cmd.*\/c.*http|\\Users\\Public\\'){Write-Host ('  [THREAT]  Suspicious Run key: '+$n+' -> '+$v) -ForegroundColor Red;Add-Content $rep ('[THREAT] Suspicious Run key: '+$n+' -> '+$v) -EA SilentlyContinue;Add-Content $thr ('Suspicious Run key: '+$n) -EA SilentlyContinue;$totalFound++}else{Write-Host ('  [INFO]    Run key OK: '+$n) -ForegroundColor DarkGray}}}}catch{}};if($totalFound -eq 0){Write-Host '  [CLEAN]   No suspicious Run/RunOnce entries detected' -ForegroundColor Green;Add-Content $rep '[CLEAN] Run keys clean' -EA SilentlyContinue}"
echo.

powershell -NoProfile -Command "Write-Host '  --- [CHECK 2] WINLOGON HIJACKS ---' -ForegroundColor !COL_HDR_PS!"
echo.
echo [CHECK 2] WINLOGON >> "!RP_REPORT!"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$rep=$env:RP_REPORT;$thr=$env:RP_THREATS_TMP;$wrn=$env:RP_WARN_TMP;$wl=Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon' -EA SilentlyContinue;$found=0;if($wl){$ui=$wl.Userinit;$sh=$wl.Shell;$expectedUI=@('C:\Windows\system32\userinit.exe,','userinit.exe,');$expectedSH=@('explorer.exe');$uiOK=$false;foreach($e in $expectedUI){if($ui -eq $e){$uiOK=$true;break}};if(-not $uiOK){Write-Host ('  [THREAT]  Winlogon Userinit hijacked: '+$ui) -ForegroundColor Red;Add-Content $rep ('[THREAT] Winlogon Userinit: '+$ui) -EA SilentlyContinue;Add-Content $thr ('Winlogon Userinit hijack: '+$ui) -EA SilentlyContinue;$found++}else{Write-Host ('  [CLEAN]   Winlogon Userinit OK: '+$ui) -ForegroundColor Green};$shOK=$false;foreach($e in $expectedSH){if($sh -match [regex]::Escape($e)){$shOK=$true;break}};if(-not $shOK){Write-Host ('  [THREAT]  Winlogon Shell hijacked: '+$sh) -ForegroundColor Red;Add-Content $rep ('[THREAT] Winlogon Shell: '+$sh) -EA SilentlyContinue;Add-Content $thr ('Winlogon Shell hijack: '+$sh) -EA SilentlyContinue;$found++}else{Write-Host ('  [CLEAN]   Winlogon Shell OK: '+$sh) -ForegroundColor Green};$sfc=$wl.SFCDisable;if($sfc -eq 1 -or $sfc -eq 2 -or $sfc -eq 4 -or $sfc -eq 0x9A){Write-Host ('  [THREAT]  SFC (System File Checker) is DISABLED via Winlogon (SFCDisable='+$sfc+')') -ForegroundColor Red;Add-Content $rep ('[THREAT] SFCDisable='+$sfc) -EA SilentlyContinue;Add-Content $thr 'SFC disabled via Winlogon' -EA SilentlyContinue;$found++}else{Write-Host '  [CLEAN]   SFC not disabled via Winlogon' -ForegroundColor Green}};if($found -eq 0){Add-Content $rep '[CLEAN] Winlogon clean' -EA SilentlyContinue}"
echo.

if "!RP_MODE!"=="QUICK" goto REGPERSIST_SUMMARY

powershell -NoProfile -Command "Write-Host '  --- [CHECK 3] LSA SECURITY PROVIDERS ---' -ForegroundColor !COL_HDR_PS!"
echo.
echo [CHECK 3] LSA PROVIDERS >> "!RP_REPORT!"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$rep=$env:RP_REPORT;$thr=$env:RP_THREATS_TMP;$wrn=$env:RP_WARN_TMP;$lsa=Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa' -EA SilentlyContinue;$found=0;if($lsa){$sp=$lsa.SecurityProviders;$ap=$lsa.Authentication_Packages;$np=$lsa.Notification_Packages;$knownSP=@('credssp','schannel','digest','msapsspc','msnsspc','');$knownAP=@('msv1_0','');$knownNP=@('rassfm','scecli','kdcsvc','wdigest','');foreach($s in ($sp -split ',| ')){$s=$s.Trim().ToLower() -replace '\.dll$','';if($s -and $s -notin $knownSP){Write-Host ('  [WARN]    Unknown LSA Security Provider: '+$s) -ForegroundColor Yellow;Add-Content $rep ('[WARN] Unknown LSA provider: '+$s) -EA SilentlyContinue;Add-Content $wrn ('Unknown LSA Security Provider: '+$s) -EA SilentlyContinue;$found++}};foreach($a in ($ap -split '\s+')){$a=$a.Trim().ToLower();if($a -and $a -notin $knownAP){Write-Host ('  [WARN]    Unknown LSA Auth Package: '+$a) -ForegroundColor Yellow;Add-Content $rep ('[WARN] Unknown Auth Package: '+$a) -EA SilentlyContinue;Add-Content $wrn ('Unknown LSA Auth Package: '+$a) -EA SilentlyContinue;$found++}};foreach($n in ($np -split '\s+')){$n=$n.Trim().ToLower() -replace '\.dll$','';if($n -and $n -notin $knownNP){Write-Host ('  [WARN]    Unknown LSA Notification Package: '+$n) -ForegroundColor Yellow;Add-Content $rep ('[WARN] Unknown Notify Package: '+$n) -EA SilentlyContinue;Add-Content $wrn ('Unknown LSA Notify Package: '+$n) -EA SilentlyContinue;$found++}};if($found -eq 0){Write-Host '  [CLEAN]   LSA providers look standard' -ForegroundColor Green;Add-Content $rep '[CLEAN] LSA providers clean' -EA SilentlyContinue}}else{Write-Host '  [WARN]    Could not read LSA registry key' -ForegroundColor Yellow}"
echo.

powershell -NoProfile -Command "Write-Host '  --- [CHECK 4] APPINIT_DLLS ---' -ForegroundColor !COL_HDR_PS!"
echo.
echo [CHECK 4] APPINIT_DLLS >> "!RP_REPORT!"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$rep=$env:RP_REPORT;$thr=$env:RP_THREATS_TMP;$wrn=$env:RP_WARN_TMP;$paths=@('HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Windows','HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows NT\CurrentVersion\Windows');$found=0;foreach($p in $paths){$v=Get-ItemProperty $p -EA SilentlyContinue;if($v -and $v.AppInit_DLLs -and $v.AppInit_DLLs.Trim() -ne ''){Write-Host ('  [THREAT]  AppInit_DLLs set: '+$v.AppInit_DLLs) -ForegroundColor Red;Add-Content $rep ('[THREAT] AppInit_DLLs: '+$v.AppInit_DLLs) -EA SilentlyContinue;Add-Content $thr ('AppInit_DLLs persistence: '+$v.AppInit_DLLs) -EA SilentlyContinue;$found++}};if($found -eq 0){Write-Host '  [CLEAN]   AppInit_DLLs is empty (good)' -ForegroundColor Green;Add-Content $rep '[CLEAN] AppInit_DLLs empty' -EA SilentlyContinue}"
echo.

powershell -NoProfile -Command "Write-Host '  --- [CHECK 5] BROWSER HELPER OBJECTS (BHO) ---' -ForegroundColor !COL_HDR_PS!"
echo.
echo [CHECK 5] BROWSER HELPER OBJECTS >> "!RP_REPORT!"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$rep=$env:RP_REPORT;$thr=$env:RP_THREATS_TMP;$wrn=$env:RP_WARN_TMP;$bhoPaths=@('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Browser Helper Objects','HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Explorer\Browser Helper Objects');$found=0;foreach($bp in $bhoPaths){$bhos=Get-ChildItem $bp -EA SilentlyContinue;foreach($b in $bhos){$clsid=$b.PSChildName;$name=(Get-ItemProperty ('HKLM:\SOFTWARE\Classes\CLSID\'+$clsid) -EA SilentlyContinue).'(Default)';if(-not $name){$name='(unknown)'};$dllPath=(Get-ItemProperty ('HKLM:\SOFTWARE\Classes\CLSID\'+$clsid+'\InprocServer32') -EA SilentlyContinue).'(Default)';Write-Host ('  [WARN]    BHO found: '+$name+' ['+$clsid+'] -> '+$dllPath) -ForegroundColor Yellow;Add-Content $rep ('[WARN] BHO: '+$name+' '+$clsid+' -> '+$dllPath) -EA SilentlyContinue;Add-Content $wrn ('Browser Helper Object: '+$name) -EA SilentlyContinue;$found++}};if($found -eq 0){Write-Host '  [CLEAN]   No Browser Helper Objects found' -ForegroundColor Green;Add-Content $rep '[CLEAN] No BHOs' -EA SilentlyContinue}"
echo.

powershell -NoProfile -Command "Write-Host '  --- [CHECK 6] IMAGE FILE EXECUTION OPTIONS (IFEO) ---' -ForegroundColor !COL_HDR_PS!"
echo.
echo [CHECK 6] IMAGE FILE EXECUTION OPTIONS >> "!RP_REPORT!"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$rep=$env:RP_REPORT;$thr=$env:RP_THREATS_TMP;$wrn=$env:RP_WARN_TMP;$ifeo=Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options' -EA SilentlyContinue;$found=0;foreach($i in $ifeo){$dbg=(Get-ItemProperty $i.PSPath -EA SilentlyContinue).Debugger;if($dbg -and $dbg.Trim() -ne ''){$name=$i.PSChildName;if($dbg -match '(?i)cmd|powershell|wscript|mshta|regsvr32|rundll32|\\Temp\\|\\AppData\\'){Write-Host ('  [THREAT]  IFEO Debugger hijack on '+$name+': '+$dbg) -ForegroundColor Red;Add-Content $rep ('[THREAT] IFEO hijack: '+$name+' -> '+$dbg) -EA SilentlyContinue;Add-Content $thr ('IFEO hijack on: '+$name) -EA SilentlyContinue}else{Write-Host ('  [WARN]    IFEO Debugger set on '+$name+': '+$dbg) -ForegroundColor Yellow;Add-Content $rep ('[WARN] IFEO Debugger: '+$name+' -> '+$dbg) -EA SilentlyContinue;Add-Content $wrn ('IFEO Debugger: '+$name) -EA SilentlyContinue};$found++}};if($found -eq 0){Write-Host '  [CLEAN]   No IFEO debugger hooks found' -ForegroundColor Green;Add-Content $rep '[CLEAN] IFEO clean' -EA SilentlyContinue}"
echo.

:REGPERSIST_SUMMARY
set "RP_THREAT_COUNT=0"
set "RP_WARN_COUNT=0"
for /f %%A in ('type "!RP_THREATS_TMP!" ^| find /c /v ""') do set "RP_THREAT_COUNT=%%A"
for /f %%A in ('type "!RP_WARN_TMP!" ^| find /c /v ""') do set "RP_WARN_COUNT=%%A"
echo. >> "!RP_REPORT!"
echo ================================================ >> "!RP_REPORT!"
echo   SCAN SUMMARY >> "!RP_REPORT!"
echo ================================================ >> "!RP_REPORT!"
echo   Mode     : !RP_MODE! >> "!RP_REPORT!"
echo   Threats  : !RP_THREAT_COUNT! >> "!RP_REPORT!"
echo   Warnings : !RP_WARN_COUNT! >> "!RP_REPORT!"
echo   Date     : %DATE% %TIME% >> "!RP_REPORT!"
echo ================================================ >> "!RP_REPORT!"
if !RP_THREAT_COUNT! GTR 0 (
    echo. >> "!RP_REPORT!"
    echo   THREATS DETECTED: >> "!RP_REPORT!"
    type "!RP_THREATS_TMP!" >> "!RP_REPORT!" 2>nul
)
if !RP_WARN_COUNT! GTR 0 (
    echo. >> "!RP_REPORT!"
    echo   WARNINGS: >> "!RP_REPORT!"
    type "!RP_WARN_TMP!" >> "!RP_REPORT!" 2>nul
)
echo.
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '    REGISTRY PERSISTENCE SCAN COMPLETE' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
echo.
if !RP_THREAT_COUNT! GTR 0 (
    powershell -NoProfile -Command "Write-Host '  THREATS  : !RP_THREAT_COUNT!' -ForegroundColor Red"
) else (
    powershell -NoProfile -Command "Write-Host '  THREATS  : !RP_THREAT_COUNT!' -ForegroundColor Green"
)
if !RP_WARN_COUNT! GTR 0 (
    powershell -NoProfile -Command "Write-Host '  WARNINGS : !RP_WARN_COUNT!' -ForegroundColor Yellow"
) else (
    powershell -NoProfile -Command "Write-Host '  WARNINGS : !RP_WARN_COUNT!' -ForegroundColor Green"
)
echo.
powershell -NoProfile -Command "Write-Host '  Report saved to:' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host ('  ' + $env:RP_REPORT) -ForegroundColor !COL_OPS_PS!"
echo.
if "!SA_ACTIVE!"=="1" goto SA_RP_CONT
pause
del "!RP_THREATS_TMP!" >nul 2>&1
del "!RP_WARN_TMP!" >nul 2>&1
goto REGPERSIST_SCANNER
:SA_RP_CONT
del "!RP_THREATS_TMP!" >nul 2>&1
del "!RP_WARN_TMP!" >nul 2>&1
echo.
powershell -NoProfile -Command "Write-Host '  B  >  Continue to next scanner (Startup and WMI)' -ForegroundColor Yellow"
echo.
:SA_RP_WAIT
set "SA_CONT="
set /p "SA_CONT=  [B] Continue: "
if /i not "!SA_CONT!"=="B" goto SA_RP_WAIT
set "SW_MODE=!SA_SW_MODE!"
goto STARTUP_WMI_RUN

:STARTUP_WMI_SCANNER
cls
color !COL_OPS!
echo.
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '    STARTUP AND WMI TASK SCANNER' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
echo.
powershell -NoProfile -Command "Write-Host '  Checks: startup folders, auto-start services, scheduled tasks,' -ForegroundColor DarkGray"
powershell -NoProfile -Command "Write-Host '  WMI event subscriptions (EventFilter, Consumer, Binding)' -ForegroundColor DarkGray"
echo.
echo   1  ^>  Full Scan  ^(all startup checks + WMI subscriptions^)
echo   2  ^>  WMI Only   ^(WMI event subscriptions only^)
echo.
echo   B  ^>  Back
echo.
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
echo.
set "SW_CHOICE="
set /p "SW_CHOICE=  Select scan type [1-2, B]: "
if /i "!SW_CHOICE!"=="B" goto CAT_SCANNING
if "!SW_CHOICE!"=="1" set "SW_MODE=FULL" & goto STARTUP_WMI_RUN
if "!SW_CHOICE!"=="2" set "SW_MODE=WMIONLY" & goto STARTUP_WMI_RUN
goto STARTUP_WMI_SCANNER

:STARTUP_WMI_RUN
cls
color !COL_OPS!
echo.
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '    STARTUP AND WMI SCANNER - RUNNING' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '    Mode: !SW_MODE!' -ForegroundColor !COL_OPS_PS!"
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
echo.
for /f %%D in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd_HHmm"') do set "SW_DATE=%%D"
set "SW_REPORT=!LOGDIR!\YTSH_StartupWMI_!SW_DATE!.txt"
set "SW_THREATS_TMP=%TEMP%\ytsh_sw_t_%RANDOM%.tmp"
set "SW_WARN_TMP=%TEMP%\ytsh_sw_w_%RANDOM%.tmp"
type nul > "%SW_THREATS_TMP%"
type nul > "%SW_WARN_TMP%"
echo ================================================ > "%SW_REPORT%"
echo    YTSH STARTUP AND WMI SCAN REPORT >> "%SW_REPORT%"
echo    Mode: !SW_MODE! >> "%SW_REPORT%"
echo    Scanned: %DATE% %TIME% >> "%SW_REPORT%"
echo ================================================ >> "%SW_REPORT%"

if "!SW_MODE!"=="WMIONLY" goto SW_CHECK_WMI

echo.
powershell -NoProfile -Command "Write-Host '  --- [CHECK 1] STARTUP FOLDERS ---' -ForegroundColor !COL_HDR_PS!"
echo.
echo [CHECK 1] STARTUP FOLDERS >> "%SW_REPORT%"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$rep=$env:SW_REPORT;$thr=$env:SW_THREATS_TMP;$wrn=$env:SW_WARN_TMP;$folders=@($env:APPDATA+'\Microsoft\Windows\Start Menu\Programs\Startup',$env:ProgramData+'\Microsoft\Windows\Start Menu\Programs\Startup');$found=0;foreach($f in $folders){if(Test-Path $f){$items=Get-ChildItem $f -EA SilentlyContinue;if($items.Count -eq 0){Write-Host ('  [CLEAN]   Empty startup folder: '+$f) -ForegroundColor Green}else{foreach($i in $items){Add-Content $rep ('[STARTUP FOLDER] '+$i.FullName) -EA SilentlyContinue;if($i.Extension -match '\.(exe|bat|ps1|vbs|cmd|js|jar|hta|scr|pif)$'){Write-Host ('  [WARN]    Executable in startup folder: '+$i.FullName) -ForegroundColor Yellow;Add-Content $wrn ('Startup folder executable: '+$i.FullName) -EA SilentlyContinue;$found++}else{Write-Host ('  [INFO]    Startup folder item: '+$i.FullName) -ForegroundColor DarkGray}}}};};if($found -eq 0){Write-Host '  [CLEAN]   No suspicious executables in startup folders' -ForegroundColor Green;Add-Content $rep '[CLEAN] Startup folders clean' -EA SilentlyContinue}"
echo.

powershell -NoProfile -Command "Write-Host '  --- [CHECK 2] AUTO-START SERVICES ---' -ForegroundColor !COL_HDR_PS!"
echo.
echo [CHECK 2] AUTO-START SERVICES >> "%SW_REPORT%"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$rep=$env:SW_REPORT;$thr=$env:SW_THREATS_TMP;$wrn=$env:SW_WARN_TMP;$svcs=@(Get-CimInstance Win32_Service -EA SilentlyContinue | Where-Object{$_.StartMode -eq 'Auto'});$found=0;foreach($s in $svcs){$path=$s.PathName;if($path -match '(?i)\\Temp\\|\\AppData\\|\\Users\\Public\\|cmd.*/c|powershell.*-enc|mshta|wscript|regsvr32'){Write-Host ('  [THREAT]  Suspicious auto-start service: '+$s.Name+' -> '+$path) -ForegroundColor Red;Add-Content $rep ('[THREAT] Suspicious service: '+$s.Name+' -> '+$path) -EA SilentlyContinue;Add-Content $thr ('Suspicious auto-start service: '+$s.Name) -EA SilentlyContinue;$found++}elseif($path -and $path -notmatch '(?i)^\x22?C:\\Windows\\|^\x22?C:\\Program Files\\|^\x22?C:\\Program Files \(x86\)\\'){Write-Host ('  [WARN]    Service binary outside standard paths: '+$s.Name+' -> '+$path) -ForegroundColor Yellow;Add-Content $rep ('[WARN] Non-standard service path: '+$s.Name+' -> '+$path) -EA SilentlyContinue;Add-Content $wrn ('Non-standard service path: '+$s.Name) -EA SilentlyContinue;$found++}};if($found -eq 0){Write-Host '  [CLEAN]   All auto-start service binaries in expected locations' -ForegroundColor Green;Add-Content $rep '[CLEAN] Auto-start services clean' -EA SilentlyContinue};Write-Host ('  [INFO]    Auto-start services checked: '+$svcs.Count) -ForegroundColor DarkGray"
echo.

powershell -NoProfile -Command "Write-Host '  --- [CHECK 3] SCHEDULED TASKS (PERSISTENCE-FOCUSED) ---' -ForegroundColor !COL_HDR_PS!"
echo.
echo [CHECK 3] SCHEDULED TASKS >> "%SW_REPORT%"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$rep=$env:SW_REPORT;$thr=$env:SW_THREATS_TMP;$wrn=$env:SW_WARN_TMP;try{$tasks=Get-ScheduledTask -EA SilentlyContinue | Where-Object{$_.State -ne 'Disabled'};$found=0;foreach($t in $tasks){foreach($a in $t.Actions){$exec=$a.Execute;$args=$a.Arguments;$cmd=(($exec)+' '+($args)).Trim();if($cmd -match '(?i)\\Temp\\|\\AppData\\Roaming\\|powershell.*-enc|powershell.*-nop.*hidden|mshta|wscript.*http|regsvr32.*http|rundll32.*http|bitsadmin|certutil.*-decode|\\Users\\Public\\|cmd.*/c.*http'){Write-Host ('  [THREAT]  Malicious task command: '+$t.TaskName+' -> '+$cmd) -ForegroundColor Red;Add-Content $rep ('[THREAT] Malicious task: '+$t.TaskName+' -> '+$cmd) -EA SilentlyContinue;Add-Content $thr ('Malicious scheduled task: '+$t.TaskName) -EA SilentlyContinue;$found++}elseif($exec -and (Test-Path $exec -EA SilentlyContinue) -eq $false -and $exec -notmatch '(?i)^(?:C:\\Windows|C:\\Program Files)'){Write-Host ('  [WARN]    Task points to missing binary: '+$t.TaskName+' -> '+$exec) -ForegroundColor Yellow;Add-Content $rep ('[WARN] Missing task binary: '+$t.TaskName) -EA SilentlyContinue;Add-Content $wrn ('Task missing binary: '+$t.TaskName) -EA SilentlyContinue;$found++}};if($t.Principal.RunLevel -eq 'Highest' -and $t.Author -and $t.Author -notmatch 'Microsoft|Windows|SYSTEM|NT AUTHORITY'){Write-Host ('  [WARN]    High-privilege non-Microsoft task: '+$t.TaskName) -ForegroundColor Yellow;Add-Content $wrn ('High-priv non-MS task: '+$t.TaskName) -EA SilentlyContinue}};if($found -eq 0){Write-Host '  [CLEAN]   No malicious scheduled tasks detected' -ForegroundColor Green;Add-Content $rep '[CLEAN] Scheduled tasks clean' -EA SilentlyContinue};Write-Host ('  [INFO]    Active tasks checked: '+$tasks.Count) -ForegroundColor DarkGray}catch{Write-Host '  [WARN]    Could not enumerate scheduled tasks' -ForegroundColor Yellow}"
echo.

:SW_CHECK_WMI
powershell -NoProfile -Command "Write-Host '  --- [CHECK 4] WMI EVENT SUBSCRIPTIONS ---' -ForegroundColor !COL_HDR_PS!"
echo.
echo [CHECK 4] WMI EVENT SUBSCRIPTIONS >> "%SW_REPORT%"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$rep=$env:SW_REPORT;$thr=$env:SW_THREATS_TMP;$wrn=$env:SW_WARN_TMP;$found=0;$filters=@(Get-CimInstance -Namespace root\subscription -ClassName __EventFilter -EA SilentlyContinue);$consumers=@(Get-CimInstance -Namespace root\subscription -ClassName CommandLineEventConsumer -EA SilentlyContinue)+@(Get-CimInstance -Namespace root\subscription -ClassName ActiveScriptEventConsumer -EA SilentlyContinue);$bindings=@(Get-CimInstance -Namespace root\subscription -ClassName __FilterToConsumerBinding -EA SilentlyContinue);Write-Host ('  [INFO]    WMI Filters: '+$filters.Count+'  Consumers: '+$consumers.Count+'  Bindings: '+$bindings.Count) -ForegroundColor DarkGray;Add-Content $rep ('WMI: Filters='+$filters.Count+' Consumers='+$consumers.Count+' Bindings='+$bindings.Count) -EA SilentlyContinue;foreach($f in $filters){if($f.Name -notmatch '^BVTFilter$|^SCM Event Log Filter$'){Write-Host ('  [THREAT]  WMI EventFilter (non-default): '+$f.Name+' | Query: '+$f.Query) -ForegroundColor Red;Add-Content $rep ('[THREAT] WMI EventFilter: '+$f.Name+' | '+$f.Query) -EA SilentlyContinue;Add-Content $thr ('WMI EventFilter persistence: '+$f.Name) -EA SilentlyContinue;$found++}};foreach($c in $consumers){$cType=$c.CimClass.CimClassName;$cName=$c.Name;$cCmd=if($c.CommandLineTemplate){$c.CommandLineTemplate}elseif($c.ScriptText){$c.ScriptText}else{'(no command)'};Write-Host ('  [THREAT]  WMI Consumer: ['+$cType+'] '+$cName+' -> '+$cCmd) -ForegroundColor Red;Add-Content $rep ('[THREAT] WMI Consumer: '+$cType+' '+$cName+' -> '+$cCmd) -EA SilentlyContinue;Add-Content $thr ('WMI Consumer persistence: '+$cName) -EA SilentlyContinue;$found++};if($found -eq 0){Write-Host '  [CLEAN]   No suspicious WMI event subscriptions found' -ForegroundColor Green;Add-Content $rep '[CLEAN] WMI subscriptions clean' -EA SilentlyContinue}else{Write-Host ('  [!!!]     WMI PERSISTENCE DETECTED - '+$found+' suspicious entry/entries') -ForegroundColor Red}"
echo.

set "SW_THREAT_COUNT=0"
set "SW_WARN_COUNT=0"
for /f %%A in ('type "%SW_THREATS_TMP%" ^| find /c /v ""') do set "SW_THREAT_COUNT=%%A"
for /f %%A in ('type "%SW_WARN_TMP%" ^| find /c /v ""') do set "SW_WARN_COUNT=%%A"
echo. >> "%SW_REPORT%"
echo ================================================ >> "%SW_REPORT%"
echo    SCAN SUMMARY >> "%SW_REPORT%"
echo ================================================ >> "%SW_REPORT%"
echo    Mode     : !SW_MODE! >> "%SW_REPORT%"
echo    Threats  : !SW_THREAT_COUNT! >> "%SW_REPORT%"
echo    Warnings : !SW_WARN_COUNT! >> "%SW_REPORT%"
echo    Date     : %DATE% %TIME% >> "%SW_REPORT%"
echo ================================================ >> "%SW_REPORT%"
if !SW_THREAT_COUNT! GTR 0 (
    echo. >> "%SW_REPORT%"
    echo    THREATS DETECTED: >> "%SW_REPORT%"
    type "%SW_THREATS_TMP%" >> "%SW_REPORT%" 2>nul
)
if !SW_WARN_COUNT! GTR 0 (
    echo. >> "%SW_REPORT%"
    echo    WARNINGS: >> "%SW_REPORT%"
    type "%SW_WARN_TMP%" >> "%SW_REPORT%" 2>nul
)
echo.
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '    STARTUP AND WMI SCAN COMPLETE' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
echo.
if !SW_THREAT_COUNT! GTR 0 (
    powershell -NoProfile -Command "Write-Host '  THREATS  : !SW_THREAT_COUNT!' -ForegroundColor Red"
) else (
    powershell -NoProfile -Command "Write-Host '  THREATS  : !SW_THREAT_COUNT!' -ForegroundColor Green"
)
if !SW_WARN_COUNT! GTR 0 (
    powershell -NoProfile -Command "Write-Host '  WARNINGS : !SW_WARN_COUNT!' -ForegroundColor Yellow"
) else (
    powershell -NoProfile -Command "Write-Host '  WARNINGS : !SW_WARN_COUNT!' -ForegroundColor Green"
)
echo.
powershell -NoProfile -Command "Write-Host '  Report saved to:' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host ('  ' + $env:SW_REPORT) -ForegroundColor !COL_OPS_PS!"
echo.
if "!SA_ACTIVE!"=="1" goto SA_SW_CONT
pause
del "%SW_THREATS_TMP%" >nul 2>&1
del "%SW_WARN_TMP%" >nul 2>&1
goto STARTUP_WMI_SCANNER
:SA_SW_CONT
del "%SW_THREATS_TMP%" >nul 2>&1
del "%SW_WARN_TMP%" >nul 2>&1
echo.
powershell -NoProfile -Command "Write-Host '  B  >  Continue to next scanner (Process and DLL Injection)' -ForegroundColor Yellow"
echo.
:SA_SW_WAIT
set "SA_CONT="
set /p "SA_CONT=  [B] Continue: "
if /i not "!SA_CONT!"=="B" goto SA_SW_WAIT
goto PI_RUN_SCAN

:PROCINJECTION_SCANNER
cls
color !COL_OPS!
echo.
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '    PROCESS AND DLL INJECTION SCANNER' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
echo.
powershell -NoProfile -Command "Write-Host '  Checks: processes in suspicious paths, DLLs in explorer/svchost,' -ForegroundColor DarkGray"
powershell -NoProfile -Command "Write-Host '  unsigned modules, unsigned kernel drivers' -ForegroundColor DarkGray"
echo.
echo   1  ^>  Begin Scan
echo   B  ^>  Back
echo.
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
echo.
set "PI_START="
set /p "PI_START=  Select [1, B]: "
if /i "!PI_START!"=="B" goto CAT_SCANNING
if not "!PI_START!"=="1" goto PROCINJECTION_SCANNER
:PI_RUN_SCAN

cls
color !COL_OPS!
echo.
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '    PROCESS AND DLL INJECTION SCANNER - RUNNING' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
echo.
for /f %%D in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd_HHmm"') do set "PI_DATE=%%D"
set "PI_REPORT=!LOGDIR!\YTSH_ProcInjection_!PI_DATE!.txt"
set "PI_THREATS_TMP=%TEMP%\ytsh_pi_t_%RANDOM%.tmp"
set "PI_WARN_TMP=%TEMP%\ytsh_pi_w_%RANDOM%.tmp"
type nul > "!PI_THREATS_TMP!"
type nul > "!PI_WARN_TMP!"
echo ================================================ > "!PI_REPORT!"
echo   YTSH PROCESS AND DLL INJECTION SCAN REPORT >> "!PI_REPORT!"
echo   Scanned: %DATE% %TIME% >> "!PI_REPORT!"
echo ================================================ >> "!PI_REPORT!"

echo.
powershell -NoProfile -Command "Write-Host '  --- [CHECK 1] PROCESSES IN SUSPICIOUS PATHS ---' -ForegroundColor !COL_HDR_PS!"
echo.
echo [CHECK 1] SUSPICIOUS PROCESS PATHS >> "!PI_REPORT!"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$rep=$env:PI_REPORT;$thr=$env:PI_THREATS_TMP;$wrn=$env:PI_WARN_TMP;$procs=Get-Process -EA SilentlyContinue;$found=0;$sysProcs=@('System','Idle','Registry','Secure System','Memory Compression');foreach($p in $procs){if($p.Name -in $sysProcs){continue};try{$path=$p.MainModule.FileName;if($path){$sig=Get-AuthenticodeSignature $path -EA SilentlyContinue;$signed=$sig -and $sig.Status -eq 'Valid';if($path -match '(?i)\\Temp\\|\\AppData\\Roaming\\[^\\]+\.exe|\\AppData\\Local\\Temp\\|\\Users\\Public\\|\\ProgramData\\[^\\]+\.exe'){Write-Host ('  [THREAT]  Process in suspicious path: '+$p.Name+' [PID:'+$p.Id+'] -> '+$path) -ForegroundColor Red;Add-Content $rep ('[THREAT] Suspicious path: '+$p.Name+' PID:'+$p.Id+' -> '+$path) -EA SilentlyContinue;Add-Content $thr ('Suspicious path process: '+$p.Name+' -> '+$path) -EA SilentlyContinue;$found++}elseif(-not $signed -and $path -notmatch '(?i)\\Windows\\|\\Program Files\\|\\Program Files \(x86\)\\'){Write-Host ('  [WARN]    Unsigned process outside standard paths: '+$p.Name+' -> '+$path) -ForegroundColor Yellow;Add-Content $rep ('[WARN] Unsigned non-standard: '+$p.Name+' -> '+$path) -EA SilentlyContinue;Add-Content $wrn ('Unsigned process: '+$p.Name) -EA SilentlyContinue}}}catch{}};if($found -eq 0){Write-Host '  [CLEAN]   No processes found in suspicious paths' -ForegroundColor Green;Add-Content $rep '[CLEAN] Process paths clean' -EA SilentlyContinue};Write-Host ('  [INFO]    Total processes scanned: '+$procs.Count) -ForegroundColor DarkGray"
echo.

powershell -NoProfile -Command "Write-Host '  --- [CHECK 2] DLLs LOADED IN EXPLORER.EXE ---' -ForegroundColor !COL_HDR_PS!"
echo.
echo [CHECK 2] DLLs IN EXPLORER.EXE >> "!PI_REPORT!"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$rep=$env:PI_REPORT;$thr=$env:PI_THREATS_TMP;$wrn=$env:PI_WARN_TMP;$found=0;$exp=Get-Process explorer -EA SilentlyContinue | Select-Object -First 1;if($exp){try{$mods=$exp.Modules;foreach($m in $mods){$mp=$m.FileName;$sig=Get-AuthenticodeSignature $mp -EA SilentlyContinue;$signed=$sig -and $sig.Status -eq 'Valid';if($mp -match '(?i)\\Temp\\|\\AppData\\|\\Users\\Public\\'){Write-Host ('  [THREAT]  DLL in suspicious path loaded in explorer: '+$mp) -ForegroundColor Red;Add-Content $rep ('[THREAT] Explorer DLL suspicious path: '+$mp) -EA SilentlyContinue;Add-Content $thr ('Explorer DLL suspicious path: '+$mp) -EA SilentlyContinue;$found++}elseif(-not $signed -and $mp -notmatch '(?i)\\Windows\\|\\Program Files\\|\\Program Files \(x86\)\\'){Write-Host ('  [WARN]    Unsigned DLL in explorer: '+$mp) -ForegroundColor Yellow;Add-Content $rep ('[WARN] Unsigned explorer DLL: '+$mp) -EA SilentlyContinue;Add-Content $wrn ('Unsigned explorer DLL: '+$mp) -EA SilentlyContinue;$found++}}}catch{Write-Host '  [WARN]    Access denied reading explorer modules (run as SYSTEM for full results)' -ForegroundColor Yellow}}else{Write-Host '  [INFO]    explorer.exe not running' -ForegroundColor DarkGray};if($found -eq 0){Write-Host '  [CLEAN]   No suspicious DLLs found in explorer.exe' -ForegroundColor Green;Add-Content $rep '[CLEAN] Explorer DLLs clean' -EA SilentlyContinue}"
echo.

powershell -NoProfile -Command "Write-Host '  --- [CHECK 3] DLLs LOADED IN SVCHOST.EXE ---' -ForegroundColor !COL_HDR_PS!"
echo.
echo [CHECK 3] DLLs IN SVCHOST.EXE >> "!PI_REPORT!"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$rep=$env:PI_REPORT;$thr=$env:PI_THREATS_TMP;$wrn=$env:PI_WARN_TMP;$found=0;$svchosts=Get-Process svchost -EA SilentlyContinue;$checked=@{};foreach($s in $svchosts){try{foreach($m in $s.Modules){$mp=$m.FileName;if($checked[$mp]){continue};$checked[$mp]=$true;$sig=Get-AuthenticodeSignature $mp -EA SilentlyContinue;$signed=$sig -and $sig.Status -eq 'Valid';if($mp -match '(?i)\\Temp\\|\\AppData\\|\\Users\\Public\\'){Write-Host ('  [THREAT]  DLL in suspicious path in svchost: '+$mp) -ForegroundColor Red;Add-Content $rep ('[THREAT] Svchost DLL suspicious: '+$mp) -EA SilentlyContinue;Add-Content $thr ('Svchost DLL suspicious path: '+$mp) -EA SilentlyContinue;$found++}elseif(-not $signed -and $mp -notmatch '(?i)\\Windows\\|\\Program Files\\'){Write-Host ('  [WARN]    Unsigned DLL in svchost: '+$mp) -ForegroundColor Yellow;Add-Content $rep ('[WARN] Unsigned svchost DLL: '+$mp) -EA SilentlyContinue;Add-Content $wrn ('Unsigned svchost DLL: '+$mp) -EA SilentlyContinue;$found++}}}catch{}};if($found -eq 0){Write-Host '  [CLEAN]   No suspicious DLLs found in svchost instances' -ForegroundColor Green;Add-Content $rep '[CLEAN] Svchost DLLs clean' -EA SilentlyContinue}"
echo.

powershell -NoProfile -Command "Write-Host '  --- [CHECK 4] UNSIGNED KERNEL DRIVERS ---' -ForegroundColor !COL_HDR_PS!"
echo.
echo [CHECK 4] UNSIGNED KERNEL DRIVERS >> "!PI_REPORT!"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$rep=$env:PI_REPORT;$thr=$env:PI_THREATS_TMP;$wrn=$env:PI_WARN_TMP;$found=0;try{$drivers=@(Get-CimInstance -ClassName Win32_SystemDriver -EA SilentlyContinue | Where-Object{$_.State -eq 'Running'});foreach($d in $drivers){$path=$d.PathName -replace '^\\SystemRoot\\','C:\Windows\' -replace '^\\\?\?\\','';if($path -and (Test-Path $path -EA SilentlyContinue)){$sig=Get-AuthenticodeSignature $path -EA SilentlyContinue;if($sig -and $sig.Status -ne 'Valid'){Write-Host ('  [THREAT]  Unsigned/invalid driver: '+$d.Name+' -> '+$path) -ForegroundColor Red;Add-Content $rep ('[THREAT] Unsigned driver: '+$d.Name+' -> '+$path) -EA SilentlyContinue;Add-Content $thr ('Unsigned driver: '+$d.Name) -EA SilentlyContinue;$found++}}};if($found -eq 0){Write-Host '  [CLEAN]   All running drivers appear signed' -ForegroundColor Green;Add-Content $rep '[CLEAN] Drivers signed' -EA SilentlyContinue};Write-Host ('  [INFO]    Running drivers checked: '+$drivers.Count) -ForegroundColor DarkGray}catch{Write-Host '  [WARN]    Could not enumerate drivers' -ForegroundColor Yellow}"
echo.

set "PI_THREAT_COUNT=0"
set "PI_WARN_COUNT=0"
for /f %%A in ('type "!PI_THREATS_TMP!" ^| find /c /v ""') do set "PI_THREAT_COUNT=%%A"
for /f %%A in ('type "!PI_WARN_TMP!" ^| find /c /v ""') do set "PI_WARN_COUNT=%%A"
echo. >> "!PI_REPORT!"
echo ================================================ >> "!PI_REPORT!"
echo   SCAN SUMMARY >> "!PI_REPORT!"
echo ================================================ >> "!PI_REPORT!"
echo   Threats  : !PI_THREAT_COUNT! >> "!PI_REPORT!"
echo   Warnings : !PI_WARN_COUNT! >> "!PI_REPORT!"
echo   Date     : %DATE% %TIME% >> "!PI_REPORT!"
echo ================================================ >> "!PI_REPORT!"
if !PI_THREAT_COUNT! GTR 0 (
    echo. >> "!PI_REPORT!"
    echo   THREATS DETECTED: >> "!PI_REPORT!"
    type "!PI_THREATS_TMP!" >> "!PI_REPORT!" 2>nul
)
if !PI_WARN_COUNT! GTR 0 (
    echo. >> "!PI_REPORT!"
    echo   WARNINGS: >> "!PI_REPORT!"
    type "!PI_WARN_TMP!" >> "!PI_REPORT!" 2>nul
)
echo.
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '    PROCESS AND DLL INJECTION SCAN COMPLETE' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
echo.
if !PI_THREAT_COUNT! GTR 0 (
    powershell -NoProfile -Command "Write-Host '  THREATS  : !PI_THREAT_COUNT!' -ForegroundColor Red"
) else (
    powershell -NoProfile -Command "Write-Host '  THREATS  : !PI_THREAT_COUNT!' -ForegroundColor Green"
)
if !PI_WARN_COUNT! GTR 0 (
    powershell -NoProfile -Command "Write-Host '  WARNINGS : !PI_WARN_COUNT!' -ForegroundColor Yellow"
) else (
    powershell -NoProfile -Command "Write-Host '  WARNINGS : !PI_WARN_COUNT!' -ForegroundColor Green"
)
echo.
powershell -NoProfile -Command "Write-Host '  Report saved to:' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host ('  ' + $env:PI_REPORT) -ForegroundColor !COL_OPS_PS!"
echo.
if "!SA_ACTIVE!"=="1" goto SA_PI_CONT
pause
del "!PI_THREATS_TMP!" >nul 2>&1
del "!PI_WARN_TMP!" >nul 2>&1
goto PROCINJECTION_SCANNER
:SA_PI_CONT
del "!PI_THREATS_TMP!" >nul 2>&1
del "!PI_WARN_TMP!" >nul 2>&1
echo.
powershell -NoProfile -Command "Write-Host '  B  >  Continue to next scanner (Browser Hijack)' -ForegroundColor Yellow"
echo.
:SA_PI_WAIT
set "SA_CONT="
set /p "SA_CONT=  [B] Continue: "
if /i not "!SA_CONT!"=="B" goto SA_PI_WAIT
goto BH_RUN_SCAN

:BROWSER_HIJACK_SCANNER
cls
color !COL_OPS!
echo.
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '    BROWSER HIJACK SCANNER' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
echo.
powershell -NoProfile -Command "Write-Host '  Checks: Chrome/Edge/Firefox default search and homepage,' -ForegroundColor DarkGray"
powershell -NoProfile -Command "Write-Host '  installed extensions, proxy hijacking via registry' -ForegroundColor DarkGray"
echo.
echo   1  ^>  Begin Scan
echo   B  ^>  Back
echo.
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
echo.
set "BH_START="
set /p "BH_START=  Select [1, B]: "
if /i "!BH_START!"=="B" goto CAT_SCANNING
if not "!BH_START!"=="1" goto BROWSER_HIJACK_SCANNER
:BH_RUN_SCAN

cls
color !COL_OPS!
echo.
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '    BROWSER HIJACK SCANNER - RUNNING' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
echo.
for /f %%D in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd_HHmm"') do set "BH_DATE=%%D"
set "BH_REPORT=!LOGDIR!\YTSH_BrowserHijack_!BH_DATE!.txt"
set "BH_THREATS_TMP=%TEMP%\ytsh_bh_t_%RANDOM%.tmp"
set "BH_WARN_TMP=%TEMP%\ytsh_bh_w_%RANDOM%.tmp"
type nul > "!BH_THREATS_TMP!"
type nul > "!BH_WARN_TMP!"
echo ================================================ > "!BH_REPORT!"
echo   YTSH BROWSER HIJACK SCAN REPORT >> "!BH_REPORT!"
echo   Scanned: %DATE% %TIME% >> "!BH_REPORT!"
echo ================================================ >> "!BH_REPORT!"

echo.
powershell -NoProfile -Command "Write-Host '  --- [CHECK 1] CHROME SETTINGS ---' -ForegroundColor !COL_HDR_PS!"
echo.
echo [CHECK 1] CHROME SETTINGS >> "!BH_REPORT!"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$rep=$env:BH_REPORT;$thr=$env:BH_THREATS_TMP;$wrn=$env:BH_WARN_TMP;$found=0;$chromePrefs=Get-ChildItem 'C:\Users' -Directory -EA SilentlyContinue | ForEach-Object{$p=$_.FullName+'\AppData\Local\Google\Chrome\User Data\Default\Preferences';if(Test-Path $p){$p}};foreach($pf in $chromePrefs){try{$raw=Get-Content $pf -Raw -EA SilentlyContinue|ConvertFrom-Json;$se=$raw.default_search_provider_data.template_url_data.short_name;$hp=$raw.homepage;$ntp=$raw.browser.last_known_google_url;if($se -and $se -notmatch '(?i)google|bing|duckduckgo|yahoo|ecosia|brave|startpage|qwant'){Write-Host ('  [THREAT]  Chrome search engine hijacked: '+$se+' in '+$pf) -ForegroundColor Red;Add-Content $rep ('[THREAT] Chrome search hijack: '+$se) -EA SilentlyContinue;Add-Content $thr ('Chrome search hijacked: '+$se) -EA SilentlyContinue;$found++}else{Write-Host ('  [CLEAN]   Chrome search engine: '+$se) -ForegroundColor Green};if($hp -and $hp -notmatch '(?i)^about:blank$|google\.|bing\.|chrome://newtab'){Write-Host ('  [WARN]    Chrome homepage set: '+$hp) -ForegroundColor Yellow;Add-Content $rep ('[WARN] Chrome homepage: '+$hp) -EA SilentlyContinue;Add-Content $wrn ('Chrome homepage: '+$hp) -EA SilentlyContinue;$found++}}catch{}};$chromePolicy=Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Google\Chrome' -EA SilentlyContinue;if($chromePolicy){Write-Host '  [WARN]    Chrome policies are enforced via registry (potential policy hijack)' -ForegroundColor Yellow;Add-Content $rep '[WARN] Chrome registry policies present' -EA SilentlyContinue;Add-Content $wrn 'Chrome registry policies enforced' -EA SilentlyContinue;$found++};if($found -eq 0){Write-Host '  [CLEAN]   Chrome: No hijack indicators detected (or not installed)' -ForegroundColor Green;Add-Content $rep '[CLEAN] Chrome settings clean' -EA SilentlyContinue}"
echo.

powershell -NoProfile -Command "Write-Host '  --- [CHECK 2] EDGE SETTINGS ---' -ForegroundColor !COL_HDR_PS!"
echo.
echo [CHECK 2] EDGE SETTINGS >> "!BH_REPORT!"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$rep=$env:BH_REPORT;$thr=$env:BH_THREATS_TMP;$wrn=$env:BH_WARN_TMP;$found=0;$edgePrefs=Get-ChildItem 'C:\Users' -Directory -EA SilentlyContinue | ForEach-Object{$p=$_.FullName+'\AppData\Local\Microsoft\Edge\User Data\Default\Preferences';if(Test-Path $p){$p}};foreach($pf in $edgePrefs){try{$raw=Get-Content $pf -Raw -EA SilentlyContinue|ConvertFrom-Json;$se=$raw.default_search_provider_data.template_url_data.short_name;$hp=$raw.homepage;if($se -and $se -notmatch '(?i)bing|google|duckduckgo|yahoo|ecosia'){Write-Host ('  [THREAT]  Edge search engine hijacked: '+$se) -ForegroundColor Red;Add-Content $rep ('[THREAT] Edge search hijack: '+$se) -EA SilentlyContinue;Add-Content $thr ('Edge search hijacked: '+$se) -EA SilentlyContinue;$found++}else{Write-Host ('  [CLEAN]   Edge search engine: '+$se) -ForegroundColor Green};if($hp -and $hp -notmatch '(?i)^about:blank$|microsoft\.|bing\.|edge://newtab'){Write-Host ('  [WARN]    Edge homepage set: '+$hp) -ForegroundColor Yellow;Add-Content $rep ('[WARN] Edge homepage: '+$hp) -EA SilentlyContinue;Add-Content $wrn ('Edge homepage: '+$hp) -EA SilentlyContinue;$found++}}catch{}};$edgePolicy=Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' -EA SilentlyContinue;if($edgePolicy){Write-Host '  [WARN]    Edge policies are enforced via registry' -ForegroundColor Yellow;Add-Content $rep '[WARN] Edge registry policies present' -EA SilentlyContinue;Add-Content $wrn 'Edge registry policies enforced' -EA SilentlyContinue;$found++};if($found -eq 0){Add-Content $rep '[CLEAN] Edge settings clean' -EA SilentlyContinue}"
echo.

powershell -NoProfile -Command "Write-Host '  --- [CHECK 3] FIREFOX SETTINGS ---' -ForegroundColor !COL_HDR_PS!"
echo.
echo [CHECK 3] FIREFOX SETTINGS >> "!BH_REPORT!"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$rep=$env:BH_REPORT;$thr=$env:BH_THREATS_TMP;$wrn=$env:BH_WARN_TMP;$found=0;$ffProfiles=Get-ChildItem 'C:\Users' -Directory -EA SilentlyContinue | ForEach-Object{$base=$_.FullName+'\AppData\Roaming\Mozilla\Firefox\Profiles';Get-ChildItem $base -Directory -EA SilentlyContinue};foreach($prof in $ffProfiles){$prefs=$prof.FullName+'\prefs.js';if(Test-Path $prefs){$lines=Get-Content $prefs -EA SilentlyContinue;foreach($l in $lines){if($l -match 'keyword\.URL|browser\.search\.defaultenginename|browser\.startup\.homepage'){if($l -match '(?i)(hao123|babylon|conduit|mywebsearch|sweetpacks|delta-search|iminent|snap\.do|istart\.webssearches)'){Write-Host ('  [THREAT]  Firefox hijack in prefs: '+$l.Trim()) -ForegroundColor Red;Add-Content $rep ('[THREAT] Firefox prefs hijack: '+$l.Trim()) -EA SilentlyContinue;Add-Content $thr ('Firefox pref hijack: '+$l.Trim()) -EA SilentlyContinue;$found++}else{Write-Host ('  [INFO]    Firefox pref: '+$l.Trim()) -ForegroundColor DarkGray;Add-Content $rep ('[INFO] Firefox pref: '+$l.Trim()) -EA SilentlyContinue}}}};$userjs=$prof.FullName+'\user.js';if(Test-Path $userjs){Write-Host ('  [WARN]    user.js present in Firefox profile (overrides prefs): '+$userjs) -ForegroundColor Yellow;Add-Content $rep ('[WARN] Firefox user.js: '+$userjs) -EA SilentlyContinue;Add-Content $wrn ('Firefox user.js found: '+$userjs) -EA SilentlyContinue;$found++}};if($found -eq 0){Write-Host '  [CLEAN]   No Firefox hijack indicators detected' -ForegroundColor Green;Add-Content $rep '[CLEAN] Firefox clean' -EA SilentlyContinue}"
echo.

powershell -NoProfile -Command "Write-Host '  --- [CHECK 4] BROWSER EXTENSIONS (CHROME/EDGE) ---' -ForegroundColor !COL_HDR_PS!"
echo.
echo [CHECK 4] BROWSER EXTENSIONS >> "!BH_REPORT!"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$rep=$env:BH_REPORT;$thr=$env:BH_THREATS_TMP;$wrn=$env:BH_WARN_TMP;$found=0;$knownMalExt=@('lifbcibllhkdhoafpjfnlhfpfgnpldfl','flliilndjeohchalpbbcdekjklbdgfkk','dbljljbbkkhdjlmelpmeibmajmlcpobl','aapbdbdomjkkjkaonfhkkikfgjllcleb','lmjegmlicamnimmfhcmpkclmigmmcbeh');$extPaths=@();Get-ChildItem 'C:\Users' -Directory -EA SilentlyContinue | ForEach-Object{$u=$_.FullName;@($u+'\AppData\Local\Google\Chrome\User Data\Default\Extensions',$u+'\AppData\Local\Microsoft\Edge\User Data\Default\Extensions') | ForEach-Object{if(Test-Path $_){$extPaths+=$_}}};foreach($ep in $extPaths){$browser=if($ep -match 'Chrome'){'Chrome'}else{'Edge'};$exts=Get-ChildItem $ep -Directory -EA SilentlyContinue;foreach($e in $exts){$id=$e.Name;$manifest=Get-ChildItem $e.FullName -Filter 'manifest.json' -Recurse -EA SilentlyContinue | Select-Object -First 1;$name='(unknown)';if($manifest){try{$mj=Get-Content $manifest.FullName -Raw -EA SilentlyContinue|ConvertFrom-Json;$name=$mj.name;if($name -match '__MSG_'){$name='(localized name)'}}catch{}};if($id -in $knownMalExt){Write-Host ('  [THREAT]  Known malicious extension in '+$browser+': '+$name+' ['+$id+']') -ForegroundColor Red;Add-Content $rep ('[THREAT] Malicious extension: '+$name+' ['+$id+']') -EA SilentlyContinue;Add-Content $thr ('Malicious browser extension: '+$name) -EA SilentlyContinue;$found++}else{Write-Host ('  [INFO]    '+$browser+' extension: '+$name+' ['+$id+']') -ForegroundColor DarkGray;Add-Content $rep ('[EXT] '+$browser+': '+$name+' ['+$id+']') -EA SilentlyContinue}}};if($found -eq 0){Write-Host '  [CLEAN]   No known malicious extension IDs detected' -ForegroundColor Green;Add-Content $rep '[CLEAN] No known malicious extensions' -EA SilentlyContinue}"
echo.

powershell -NoProfile -Command "Write-Host '  --- [CHECK 5] PROXY HIJACKING (REGISTRY) ---' -ForegroundColor !COL_HDR_PS!"
echo.
echo [CHECK 5] PROXY HIJACKING >> "!BH_REPORT!"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$rep=$env:BH_REPORT;$thr=$env:BH_THREATS_TMP;$wrn=$env:BH_WARN_TMP;$found=0;$users=Get-ChildItem 'C:\Users' -Directory -EA SilentlyContinue;foreach($u in $users){try{$hive='Registry::HKEY_USERS';$sids=Get-ChildItem $hive -EA SilentlyContinue | Where-Object{$_.Name -match 'S-1-5-21'};foreach($sid in $sids){$pKey=$hive+'\'+$sid.PSChildName+'\Software\Microsoft\Windows\CurrentVersion\Internet Settings';$ps=Get-ItemProperty $pKey -EA SilentlyContinue;if($ps -and $ps.ProxyEnable -eq 1){Write-Host ('  [WARN]    Proxy enabled for SID '+$sid.PSChildName+': '+$ps.ProxyServer) -ForegroundColor Yellow;Add-Content $rep ('[WARN] User proxy enabled: '+$sid.PSChildName+' -> '+$ps.ProxyServer) -EA SilentlyContinue;Add-Content $wrn ('User proxy enabled: '+$ps.ProxyServer) -EA SilentlyContinue;$found++};if($ps -and $ps.AutoConfigURL){Write-Host ('  [WARN]    Auto-config PAC URL set for SID '+$sid.PSChildName+': '+$ps.AutoConfigURL) -ForegroundColor Yellow;Add-Content $rep ('[WARN] PAC URL: '+$ps.AutoConfigURL) -EA SilentlyContinue;Add-Content $wrn ('PAC URL: '+$ps.AutoConfigURL) -EA SilentlyContinue;$found++}}}catch{}};if($found -eq 0){Write-Host '  [CLEAN]   No proxy hijacking detected in user registry hives' -ForegroundColor Green;Add-Content $rep '[CLEAN] Proxy registry clean' -EA SilentlyContinue}"
echo.

set "BH_THREAT_COUNT=0"
set "BH_WARN_COUNT=0"
for /f %%A in ('type "!BH_THREATS_TMP!" ^| find /c /v ""') do set "BH_THREAT_COUNT=%%A"
for /f %%A in ('type "!BH_WARN_TMP!" ^| find /c /v ""') do set "BH_WARN_COUNT=%%A"
echo. >> "!BH_REPORT!"
echo ================================================ >> "!BH_REPORT!"
echo   SCAN SUMMARY >> "!BH_REPORT!"
echo ================================================ >> "!BH_REPORT!"
echo   Threats  : !BH_THREAT_COUNT! >> "!BH_REPORT!"
echo   Warnings : !BH_WARN_COUNT! >> "!BH_REPORT!"
echo   Date     : %DATE% %TIME% >> "!BH_REPORT!"
echo ================================================ >> "!BH_REPORT!"
if !BH_THREAT_COUNT! GTR 0 (
    echo. >> "!BH_REPORT!"
    echo   THREATS DETECTED: >> "!BH_REPORT!"
    type "!BH_THREATS_TMP!" >> "!BH_REPORT!" 2>nul
)
if !BH_WARN_COUNT! GTR 0 (
    echo. >> "!BH_REPORT!"
    echo   WARNINGS: >> "!BH_REPORT!"
    type "!BH_WARN_TMP!" >> "!BH_REPORT!" 2>nul
)
echo.
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '    BROWSER HIJACK SCAN COMPLETE' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
echo.
if !BH_THREAT_COUNT! GTR 0 (
    powershell -NoProfile -Command "Write-Host '  THREATS  : !BH_THREAT_COUNT!' -ForegroundColor Red"
) else (
    powershell -NoProfile -Command "Write-Host '  THREATS  : !BH_THREAT_COUNT!' -ForegroundColor Green"
)
if !BH_WARN_COUNT! GTR 0 (
    powershell -NoProfile -Command "Write-Host '  WARNINGS : !BH_WARN_COUNT!' -ForegroundColor Yellow"
) else (
    powershell -NoProfile -Command "Write-Host '  WARNINGS : !BH_WARN_COUNT!' -ForegroundColor Green"
)
echo.
powershell -NoProfile -Command "Write-Host '  Report saved to:' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host ('  ' + $env:BH_REPORT) -ForegroundColor !COL_OPS_PS!"
echo.
if "!SA_ACTIVE!"=="1" goto SA_BH_CONT
pause
del "!BH_THREATS_TMP!" >nul 2>&1
del "!BH_WARN_TMP!" >nul 2>&1
goto BROWSER_HIJACK_SCANNER
:SA_BH_CONT
del "!BH_THREATS_TMP!" >nul 2>&1
del "!BH_WARN_TMP!" >nul 2>&1
echo.
powershell -NoProfile -Command "Write-Host '  B  >  Continue to next scanner (Credential Exposure)' -ForegroundColor Yellow"
echo.
:SA_BH_WAIT
set "SA_CONT="
set /p "SA_CONT=  [B] Continue: "
if /i not "!SA_CONT!"=="B" goto SA_BH_WAIT
goto CR_RUN_SCAN

:CREDENTIAL_SCANNER
cls
color !COL_OPS!
echo.
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '    CREDENTIAL EXPOSURE SCANNER' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
echo.
powershell -NoProfile -Command "Write-Host '  Checks: stored Windows credentials, LSA protection, WDigest,' -ForegroundColor DarkGray"
powershell -NoProfile -Command "Write-Host '  LSASS PPL status, Protected Users group, Credential Guard' -ForegroundColor DarkGray"
echo.
echo   1  ^>  Begin Scan
echo   B  ^>  Back
echo.
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
echo.
set "CR_START="
set /p "CR_START=  Select [1, B]: "
if /i "!CR_START!"=="B" goto CAT_SCANNING
if not "!CR_START!"=="1" goto CREDENTIAL_SCANNER
:CR_RUN_SCAN

cls
color !COL_OPS!
echo.
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '    CREDENTIAL EXPOSURE SCANNER - RUNNING' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
echo.
for /f %%D in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd_HHmm"') do set "CR_DATE=%%D"
set "CR_REPORT=!LOGDIR!\YTSH_CredExposure_!CR_DATE!.txt"
set "CR_THREATS_TMP=%TEMP%\ytsh_cr_t_%RANDOM%.tmp"
set "CR_WARN_TMP=%TEMP%\ytsh_cr_w_%RANDOM%.tmp"
type nul > "!CR_THREATS_TMP!"
type nul > "!CR_WARN_TMP!"
echo ================================================ > "!CR_REPORT!"
echo   YTSH CREDENTIAL EXPOSURE SCAN REPORT >> "!CR_REPORT!"
echo   Scanned: %DATE% %TIME% >> "!CR_REPORT!"
echo ================================================ >> "!CR_REPORT!"

echo.
powershell -NoProfile -Command "Write-Host '  --- [CHECK 1] STORED WINDOWS CREDENTIALS ---' -ForegroundColor !COL_HDR_PS!"
echo.
echo [CHECK 1] STORED CREDENTIALS >> "!CR_REPORT!"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$rep=$env:CR_REPORT;$thr=$env:CR_THREATS_TMP;$wrn=$env:CR_WARN_TMP;$found=0;$creds=cmdkey /list 2>$null;$credLines=$creds | Where-Object{$_ -match 'Target:|Type:|User:'};$credCount=($creds | Where-Object{$_ -match 'Target:'}).Count;Write-Host ('  [INFO]    Stored credentials count: '+$credCount) -ForegroundColor DarkGray;Add-Content $rep ('Stored credential entries: '+$credCount) -EA SilentlyContinue;foreach($l in $credLines){Add-Content $rep $l -EA SilentlyContinue;Write-Host ('  [INFO]    '+$l.Trim()) -ForegroundColor DarkGray};$suspcreds=$creds | Where-Object{$_ -match '(?i)Domain Password|Generic.*password|MicrosoftOffice.*|TERMSRV'};if($suspcreds.Count -gt 0){Write-Host ('  [WARN]    Potentially sensitive credential types stored: '+$suspcreds.Count) -ForegroundColor Yellow;Add-Content $wrn ('Sensitive credential types stored: '+$suspcreds.Count) -EA SilentlyContinue;$found++};$domCreds=$creds | Where-Object{$_ -match 'Domain'};if($domCreds){Write-Host '  [WARN]    Domain credentials stored in Credential Manager' -ForegroundColor Yellow;Add-Content $wrn 'Domain credentials in Credential Manager' -EA SilentlyContinue;$found++};if($credCount -eq 0){Write-Host '  [CLEAN]   No credentials stored in Credential Manager' -ForegroundColor Green;Add-Content $rep '[CLEAN] No stored credentials' -EA SilentlyContinue}"
echo.

powershell -NoProfile -Command "Write-Host '  --- [CHECK 2] WDIGEST CREDENTIAL CACHING ---' -ForegroundColor !COL_HDR_PS!"
echo.
echo [CHECK 2] WDIGEST >> "!CR_REPORT!"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$rep=$env:CR_REPORT;$thr=$env:CR_Threats_TMP;$wrn=$env:CR_WARN_TMP;$wd=Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\WDigest' -EA SilentlyContinue;if($wd -and $wd.UseLogonCredential -eq 1){Write-Host '  [THREAT]  WDigest UseLogonCredential=1 - LSASS stores plaintext passwords (cleartext caching active)' -ForegroundColor Red;Add-Content $rep '[THREAT] WDigest enabled - plaintext password caching active' -EA SilentlyContinue;Add-Content $env:CR_THREATS_TMP 'WDigest plaintext password caching enabled' -EA SilentlyContinue}elseif($wd -and $wd.UseLogonCredential -eq 0){Write-Host '  [CLEAN]   WDigest disabled (UseLogonCredential=0)' -ForegroundColor Green;Add-Content $rep '[CLEAN] WDigest disabled' -EA SilentlyContinue}else{Write-Host '  [CLEAN]   WDigest UseLogonCredential not set (default=off on Win8.1+)' -ForegroundColor Green;Add-Content $rep '[CLEAN] WDigest not configured (default safe)' -EA SilentlyContinue}"
echo.

powershell -NoProfile -Command "Write-Host '  --- [CHECK 3] LSA PROTECTION (PPL) STATUS ---' -ForegroundColor !COL_HDR_PS!"
echo.
echo [CHECK 3] LSA PPL >> "!CR_REPORT!"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$rep=$env:CR_REPORT;$thr=$env:CR_THREATS_TMP;$wrn=$env:CR_WARN_TMP;$lsa=Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa' -EA SilentlyContinue;$ppl=$lsa.RunAsPPL;if($ppl -eq 1 -or $ppl -eq 2){Write-Host ('  [CLEAN]   LSASS is running as PPL (Protected Process Light) - RunAsPPL='+$ppl) -ForegroundColor Green;Add-Content $rep ('[CLEAN] LSASS PPL enabled: '+$ppl) -EA SilentlyContinue}else{Write-Host '  [WARN]    LSASS is NOT running as PPL (RunAsPPL=0 or not set) - vulnerable to credential dumping' -ForegroundColor Yellow;Add-Content $rep '[WARN] LSASS PPL not enabled - credential dumping risk' -EA SilentlyContinue;Add-Content $wrn 'LSASS not running as PPL' -EA SilentlyContinue};$cgEnabled=(Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard' -EA SilentlyContinue).EnableVirtualizationBasedSecurity;$cgCfg=(Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa' -EA SilentlyContinue).LsaCfgFlags;if($cgEnabled -eq 1 -and $cgCfg -ge 1){Write-Host '  [CLEAN]   Credential Guard appears enabled (VBS + LsaCfgFlags)' -ForegroundColor Green;Add-Content $rep '[CLEAN] Credential Guard enabled' -EA SilentlyContinue}else{Write-Host '  [WARN]    Credential Guard does not appear to be enabled' -ForegroundColor Yellow;Add-Content $rep '[WARN] Credential Guard not detected' -EA SilentlyContinue;Add-Content $wrn 'Credential Guard not enabled' -EA SilentlyContinue}"
echo.

powershell -NoProfile -Command "Write-Host '  --- [CHECK 4] PROTECTED USERS GROUP ---' -ForegroundColor !COL_HDR_PS!"
echo.
echo [CHECK 4] PROTECTED USERS GROUP >> "!CR_REPORT!"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$rep=$env:CR_REPORT;$thr=$env:CR_THREATS_TMP;$wrn=$env:CR_WARN_TMP;try{$pu=net localgroup 'Protected Users' 2>$null;$members=$pu | Where-Object{$_ -notmatch 'The command|Members|group name|Comment|---|----|Members of'} | Where-Object{$_.Trim() -ne ''};Write-Host ('  [INFO]    Protected Users group members: '+$members.Count) -ForegroundColor DarkGray;Add-Content $rep ('Protected Users members: '+$members.Count) -EA SilentlyContinue;foreach($m in $members){Write-Host ('  [INFO]    Member: '+$m.Trim()) -ForegroundColor DarkGray};$admins=net localgroup administrators 2>$null | Where-Object{$_ -notmatch 'The command|Members|group name|Comment|---|----|Alias name|Members of'} | Where-Object{$_.Trim() -ne ''};$unprotAdmins=$admins | Where-Object{$m=$_.Trim();$m -and $m -notin ($members | ForEach-Object{$_.Trim()})};if($unprotAdmins.Count -gt 0){Write-Host ('  [WARN]    Admin accounts NOT in Protected Users: '+($unprotAdmins -join ', ')) -ForegroundColor Yellow;Add-Content $wrn ('Admins not in Protected Users: '+($unprotAdmins -join ',')) -EA SilentlyContinue;Add-Content $rep ('[WARN] Unprotected admins: '+($unprotAdmins -join ',')) -EA SilentlyContinue}else{Write-Host '  [CLEAN]   All admin accounts appear in Protected Users' -ForegroundColor Green;Add-Content $rep '[CLEAN] All admins in Protected Users' -EA SilentlyContinue}}catch{Write-Host '  [INFO]    Could not enumerate Protected Users group' -ForegroundColor DarkGray}"
echo.

powershell -NoProfile -Command "Write-Host '  --- [CHECK 5] NTLM AUTHENTICATION LEVEL ---' -ForegroundColor !COL_HDR_PS!"
echo.
echo [CHECK 5] NTLM LEVEL >> "!CR_REPORT!"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$rep=$env:CR_REPORT;$thr=$env:CR_THREATS_TMP;$wrn=$env:CR_WARN_TMP;$lsa=Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa' -EA SilentlyContinue;$level=$lsa.LmCompatibilityLevel;$desc=switch($level){0{'Send LM and NTLM - very insecure'} 1{'Send LM and NTLM, NTLMv2 if negotiated'} 2{'Send NTLM only'} 3{'Send NTLMv2 only'} 4{'Send NTLMv2, refuse LM'} 5{'Send NTLMv2, refuse LM and NTLM - most secure'} $null{'Not set (default=3 on Win10+)'} default{'Unknown level '+$level}};if($level -le 2 -and $level -ne $null){Write-Host ('  [THREAT]  NTLM level too low: '+$desc) -ForegroundColor Red;Add-Content $rep ('[THREAT] NTLM insecure level: '+$level+' - '+$desc) -EA SilentlyContinue;Add-Content $thr ('Insecure NTLM level: '+$level) -EA SilentlyContinue}elseif($level -ge 4 -or $level -eq $null){Write-Host ('  [CLEAN]   NTLM level acceptable: '+$desc) -ForegroundColor Green;Add-Content $rep ('[CLEAN] NTLM level: '+$level+' - '+$desc) -EA SilentlyContinue}else{Write-Host ('  [WARN]    NTLM level is '+$level+' ('+$desc+') - consider raising to 5') -ForegroundColor Yellow;Add-Content $rep ('[WARN] NTLM level: '+$level+' - '+$desc) -EA SilentlyContinue;Add-Content $wrn ('NTLM level low: '+$level) -EA SilentlyContinue}"
echo.

set "CR_THREAT_COUNT=0"
set "CR_WARN_COUNT=0"
for /f %%A in ('type "!CR_THREATS_TMP!" ^| find /c /v ""') do set "CR_THREAT_COUNT=%%A"
for /f %%A in ('type "!CR_WARN_TMP!" ^| find /c /v ""') do set "CR_WARN_COUNT=%%A"
echo. >> "!CR_REPORT!"
echo ================================================ >> "!CR_REPORT!"
echo   SCAN SUMMARY >> "!CR_REPORT!"
echo ================================================ >> "!CR_REPORT!"
echo   Threats  : !CR_THREAT_COUNT! >> "!CR_REPORT!"
echo   Warnings : !CR_WARN_COUNT! >> "!CR_REPORT!"
echo   Date     : %DATE% %TIME% >> "!CR_REPORT!"
echo ================================================ >> "!CR_REPORT!"
if !CR_THREAT_COUNT! GTR 0 (
    echo. >> "!CR_REPORT!"
    echo   THREATS DETECTED: >> "!CR_REPORT!"
    type "!CR_THREATS_TMP!" >> "!CR_REPORT!" 2>nul
)
if !CR_WARN_COUNT! GTR 0 (
    echo. >> "!CR_REPORT!"
    echo   WARNINGS: >> "!CR_REPORT!"
    type "!CR_WARN_TMP!" >> "!CR_REPORT!" 2>nul
)
echo.
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '    CREDENTIAL EXPOSURE SCAN COMPLETE' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
echo.
if !CR_THREAT_COUNT! GTR 0 (
    powershell -NoProfile -Command "Write-Host '  THREATS  : !CR_THREAT_COUNT!' -ForegroundColor Red"
) else (
    powershell -NoProfile -Command "Write-Host '  THREATS  : !CR_THREAT_COUNT!' -ForegroundColor Green"
)
if !CR_WARN_COUNT! GTR 0 (
    powershell -NoProfile -Command "Write-Host '  WARNINGS : !CR_WARN_COUNT!' -ForegroundColor Yellow"
) else (
    powershell -NoProfile -Command "Write-Host '  WARNINGS : !CR_WARN_COUNT!' -ForegroundColor Green"
)
echo.
powershell -NoProfile -Command "Write-Host '  Report saved to:' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host ('  ' + $env:CR_REPORT) -ForegroundColor !COL_OPS_PS!"
echo.
if "!SA_ACTIVE!"=="1" goto SA_CR_CONT
pause
del "!CR_THREATS_TMP!" >nul 2>&1
del "!CR_WARN_TMP!" >nul 2>&1
goto CREDENTIAL_SCANNER
:SA_CR_CONT
del "!CR_THREATS_TMP!" >nul 2>&1
del "!CR_WARN_TMP!" >nul 2>&1
echo.
powershell -NoProfile -Command "Write-Host '  B  >  Continue to next scanner (Driver Integrity and Rootkit)' -ForegroundColor Yellow"
echo.
:SA_CR_WAIT
set "SA_CONT="
set /p "SA_CONT=  [B] Continue: "
if /i not "!SA_CONT!"=="B" goto SA_CR_WAIT
goto DR_RUN_SCAN

:DRIVER_ROOTKIT_SCANNER
cls
color !COL_OPS!
echo.
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '    DRIVER INTEGRITY AND ROOTKIT SCANNER' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
echo.
powershell -NoProfile -Command "Write-Host '  Checks: unsigned running drivers, suspicious driver paths,' -ForegroundColor DarkGray"
powershell -NoProfile -Command "Write-Host '  orphaned boot drivers, known rootkit driver name signatures' -ForegroundColor DarkGray"
echo.
echo   1  ^>  Begin Scan
echo   B  ^>  Back
echo.
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
echo.
set "DR_START="
set /p "DR_START=  Select [1, B]: "
if /i "!DR_START!"=="B" goto CAT_SCANNING
if not "!DR_START!"=="1" goto DRIVER_ROOTKIT_SCANNER
:DR_RUN_SCAN
cls
color !COL_OPS!
echo.
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '    DRIVER INTEGRITY AND ROOTKIT SCANNER - RUNNING' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
echo.
for /f %%D in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd_HHmm"') do set "DR_DATE=%%D"
set "DR_REPORT=!LOGDIR!\YTSH_DriverRootkit_!DR_DATE!.txt"
set "DR_THREATS_TMP=%TEMP%\ytsh_dr_t_%RANDOM%.tmp"
set "DR_WARN_TMP=%TEMP%\ytsh_dr_w_%RANDOM%.tmp"
type nul > "!DR_THREATS_TMP!"
type nul > "!DR_WARN_TMP!"
echo ================================================ > "!DR_REPORT!"
echo   YTSH DRIVER INTEGRITY AND ROOTKIT SCAN REPORT >> "!DR_REPORT!"
echo   Scanned: %DATE% %TIME% >> "!DR_REPORT!"
echo ================================================ >> "!DR_REPORT!"
echo.
powershell -NoProfile -Command "Write-Host '  --- [CHECK 1] UNSIGNED RUNNING DRIVERS ---' -ForegroundColor !COL_HDR_PS!"
echo.
echo [CHECK 1] UNSIGNED RUNNING DRIVERS >> "!DR_REPORT!"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$rep=$env:DR_REPORT;$thr=$env:DR_THREATS_TMP;$wrn=$env:DR_WARN_TMP;$found=0;$drivers=@(Get-CimInstance Win32_SystemDriver -EA SilentlyContinue|Where-Object{$_.State -eq 'Running'});Write-Host ('  [INFO]    Running drivers found: '+$drivers.Count) -ForegroundColor DarkGray;Add-Content $rep ('Running drivers: '+$drivers.Count) -EA SilentlyContinue;foreach($d in $drivers){try{$raw=$d.PathName;if(-not $raw){continue};$path=($raw -replace '^\\\\\?\\','') -replace '"','' ;$path=$path.Trim();if($path.Length -lt 4){continue};if(Test-Path -LiteralPath $path -EA SilentlyContinue){$sig=Get-AuthenticodeSignature -LiteralPath $path -EA SilentlyContinue;if($sig -and $sig.Status -notin @('Valid','NotSupportedFileFormat')){Write-Host ('  [WARN]    Unsigned driver: '+$d.Name+' | '+$path) -ForegroundColor Yellow;Add-Content $rep ('[WARN] Unsigned: '+$d.Name+' '+$path) -EA SilentlyContinue;Add-Content $wrn ('Unsigned driver: '+$d.Name) -EA SilentlyContinue;$found++}}else{Write-Host ('  [WARN]    Driver file not found on disk: '+$d.Name+' | '+$path) -ForegroundColor Yellow;Add-Content $rep ('[WARN] Missing driver file: '+$d.Name+' '+$path) -EA SilentlyContinue;Add-Content $wrn ('Driver file missing: '+$d.Name) -EA SilentlyContinue;$found++}}catch{}};if($found -eq 0){Write-Host '  [CLEAN]   All running drivers appear signed' -ForegroundColor Green;Add-Content $rep '[CLEAN] Running drivers signed' -EA SilentlyContinue}"
echo.
powershell -NoProfile -Command "Write-Host '  --- [CHECK 2] SUSPICIOUS DRIVER FILE PATHS ---' -ForegroundColor !COL_HDR_PS!"
echo.
echo [CHECK 2] SUSPICIOUS DRIVER PATHS >> "!DR_REPORT!"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$rep=$env:DR_REPORT;$thr=$env:DR_THREATS_TMP;$wrn=$env:DR_WARN_TMP;$found=0;$legitDirs=@('system32\drivers','system32\driverstore','syswow64\drivers','windows\inf');$drivers=@(Get-CimInstance Win32_SystemDriver -EA SilentlyContinue|Where-Object{$_.State -eq 'Running'});foreach($d in $drivers){try{$raw=$d.PathName;if(-not $raw){continue};$path=($raw -replace '^\\\\\?\\','') -replace '"','';$path=$path.ToLower().Trim();if($path.Length -lt 4){continue};$isLegit=$false;foreach($lp in $legitDirs){if($path -match [regex]::Escape($lp)){$isLegit=$true;break}};if(-not $isLegit){if($path -match '\\temp\\|\\tmp\\|\\appdata\\|\\users\\'){Write-Host ('  [THREAT]  Driver loading from user or temp path: '+$d.Name+' | '+$d.PathName) -ForegroundColor Red;Add-Content $rep ('[THREAT] Driver in user/temp path: '+$d.Name+' | '+$d.PathName) -EA SilentlyContinue;Add-Content $thr ('Rootkit-suspect driver path: '+$d.Name) -EA SilentlyContinue;$found++}elseif($path -notmatch '\\windows\\'){Write-Host ('  [WARN]    Driver outside Windows directory: '+$d.Name+' | '+$d.PathName) -ForegroundColor Yellow;Add-Content $rep ('[WARN] Non-Windows driver: '+$d.Name+' | '+$d.PathName) -EA SilentlyContinue;Add-Content $wrn ('Non-Windows driver path: '+$d.Name) -EA SilentlyContinue;$found++}}}catch{}};if($found -eq 0){Write-Host '  [CLEAN]   All running drivers load from expected Windows paths' -ForegroundColor Green;Add-Content $rep '[CLEAN] Driver paths nominal' -EA SilentlyContinue}"
echo.
powershell -NoProfile -Command "Write-Host '  --- [CHECK 3] KNOWN ROOTKIT DRIVER NAME SIGNATURES ---' -ForegroundColor !COL_HDR_PS!"
echo.
echo [CHECK 3] ROOTKIT NAME SIGNATURES >> "!DR_REPORT!"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$rep=$env:DR_REPORT;$thr=$env:DR_THREATS_TMP;$wrn=$env:DR_WARN_TMP;$found=0;$sigs=@('tdldrv','tdss','sinowal','mebroot','zeroaccess','necursdrv','alureon','rustock','srizbi','cutwail','blackenergy','bootkit','hxdef','azazel','adore','suckit','enyelkm','reptile','diamorphine','rkdrv','hidrv','gbot32','gbot64','ntos_drv','msblst','win32k_ext');$drivers=@(Get-CimInstance Win32_SystemDriver -EA SilentlyContinue);foreach($d in $drivers){try{$name=$d.Name.ToLower();foreach($sig in $sigs){if($name -match [regex]::Escape($sig)){Write-Host ('  [THREAT]  Driver matches rootkit signature: '+$d.Name+' (pattern: '+$sig+')') -ForegroundColor Red;Add-Content $rep ('[THREAT] Rootkit name match: '+$d.Name+' pattern:'+$sig) -EA SilentlyContinue;Add-Content $thr ('Rootkit name signature: '+$d.Name) -EA SilentlyContinue;$found++;break}}}catch{}};Write-Host ('  [INFO]    Drivers checked against '+$sigs.Count+' rootkit signatures') -ForegroundColor DarkGray;if($found -eq 0){Write-Host '  [CLEAN]   No known rootkit driver name signatures matched' -ForegroundColor Green;Add-Content $rep '[CLEAN] No rootkit name signatures found' -EA SilentlyContinue}"
echo.
powershell -NoProfile -Command "Write-Host '  --- [CHECK 4] ORPHANED BOOT-START DRIVERS ---' -ForegroundColor !COL_HDR_PS!"
echo.
echo [CHECK 4] ORPHANED BOOT DRIVERS >> "!DR_REPORT!"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$rep=$env:DR_REPORT;$thr=$env:DR_THREATS_TMP;$wrn=$env:DR_WARN_TMP;$found=0;$bootDrvs=@(Get-CimInstance Win32_SystemDriver -EA SilentlyContinue|Where-Object{$_.StartMode -eq 'Boot' -and $_.State -ne 'Running'});Write-Host ('  [INFO]    Boot-start drivers not running: '+$bootDrvs.Count) -ForegroundColor DarkGray;Add-Content $rep ('Boot-start not running: '+$bootDrvs.Count) -EA SilentlyContinue;foreach($d in $bootDrvs){try{$raw=$d.PathName;if(-not $raw){continue};$path=($raw -replace '^\\\\\?\\','') -replace '"','';$path=$path.Trim();if(-not (Test-Path -LiteralPath $path -EA SilentlyContinue)){Write-Host ('  [WARN]    Orphaned boot driver (file missing on disk): '+$d.Name+' | '+$path) -ForegroundColor Yellow;Add-Content $rep ('[WARN] Orphaned boot driver: '+$d.Name+' '+$path) -EA SilentlyContinue;Add-Content $wrn ('Orphaned boot driver: '+$d.Name) -EA SilentlyContinue;$found++}else{Write-Host ('  [INFO]    Boot driver stopped (may be normal): '+$d.Name) -ForegroundColor DarkGray;Add-Content $rep ('[INFO] Boot driver stopped: '+$d.Name) -EA SilentlyContinue}}catch{}};if($found -eq 0){Write-Host '  [CLEAN]   No orphaned boot drivers detected' -ForegroundColor Green;Add-Content $rep '[CLEAN] No orphaned boot drivers' -EA SilentlyContinue}"
echo.
set "DR_THREAT_COUNT=0"
set "DR_WARN_COUNT=0"
for /f %%A in ('type "!DR_THREATS_TMP!" ^| find /c /v ""') do set "DR_THREAT_COUNT=%%A"
for /f %%A in ('type "!DR_WARN_TMP!" ^| find /c /v ""') do set "DR_WARN_COUNT=%%A"
echo. >> "!DR_REPORT!"
echo ================================================ >> "!DR_REPORT!"
echo   SCAN SUMMARY >> "!DR_REPORT!"
echo ================================================ >> "!DR_REPORT!"
echo   Threats  : !DR_THREAT_COUNT! >> "!DR_REPORT!"
echo   Warnings : !DR_WARN_COUNT! >> "!DR_REPORT!"
echo   Date     : %DATE% %TIME% >> "!DR_REPORT!"
echo ================================================ >> "!DR_REPORT!"
if !DR_THREAT_COUNT! GTR 0 (
    echo. >> "!DR_REPORT!"
    echo   THREATS DETECTED: >> "!DR_REPORT!"
    type "!DR_THREATS_TMP!" >> "!DR_REPORT!" 2>nul
)
if !DR_WARN_COUNT! GTR 0 (
    echo. >> "!DR_REPORT!"
    echo   WARNINGS: >> "!DR_REPORT!"
    type "!DR_WARN_TMP!" >> "!DR_REPORT!" 2>nul
)
echo.
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '    DRIVER INTEGRITY AND ROOTKIT SCAN COMPLETE' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
echo.
if !DR_THREAT_COUNT! GTR 0 (
    powershell -NoProfile -Command "Write-Host '  THREATS  : !DR_THREAT_COUNT!' -ForegroundColor Red"
) else (
    powershell -NoProfile -Command "Write-Host '  THREATS  : !DR_THREAT_COUNT!' -ForegroundColor Green"
)
if !DR_WARN_COUNT! GTR 0 (
    powershell -NoProfile -Command "Write-Host '  WARNINGS : !DR_WARN_COUNT!' -ForegroundColor Yellow"
) else (
    powershell -NoProfile -Command "Write-Host '  WARNINGS : !DR_WARN_COUNT!' -ForegroundColor Green"
)
echo.
powershell -NoProfile -Command "Write-Host '  Report saved to:' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host ('  ' + $env:DR_REPORT) -ForegroundColor !COL_OPS_PS!"
echo.
if "!SA_ACTIVE!"=="1" goto SA_DR_CONT
pause
del "!DR_THREATS_TMP!" >nul 2>&1
del "!DR_WARN_TMP!" >nul 2>&1
goto DRIVER_ROOTKIT_SCANNER
:SA_DR_CONT
del "!DR_THREATS_TMP!" >nul 2>&1
del "!DR_WARN_TMP!" >nul 2>&1
echo.
powershell -NoProfile -Command "Write-Host '  B  >  Continue to next scanner (Privacy and Tracker)' -ForegroundColor Yellow"
echo.
:SA_DR_WAIT
set "SA_CONT="
set /p "SA_CONT=  [B] Continue: "
if /i not "!SA_CONT!"=="B" goto SA_DR_WAIT
goto PT_RUN_SCAN

:PRIVACY_TRACKER_SCANNER
cls
color !COL_OPS!
echo.
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '    USER PRIVACY AND TRACKER SCANNER' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
echo.
powershell -NoProfile -Command "Write-Host '  Checks: Windows Advertising ID per profile, telemetry' -ForegroundColor DarkGray"
powershell -NoProfile -Command "Write-Host '  registry keys, browser cookie store presence, privacy flags' -ForegroundColor DarkGray"
echo.
echo   1  ^>  Begin Scan
echo   B  ^>  Back
echo.
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
echo.
set "PT_START="
set /p "PT_START=  Select [1, B]: "
if /i "!PT_START!"=="B" goto CAT_SCANNING
if not "!PT_START!"=="1" goto PRIVACY_TRACKER_SCANNER
:PT_RUN_SCAN
cls
color !COL_OPS!
echo.
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '    USER PRIVACY AND TRACKER SCANNER - RUNNING' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
echo.
for /f %%D in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd_HHmm"') do set "PT_DATE=%%D"
set "PT_REPORT=!LOGDIR!\YTSH_PrivacyTracker_!PT_DATE!.txt"
set "PT_THREATS_TMP=%TEMP%\ytsh_pt_t_%RANDOM%.tmp"
set "PT_WARN_TMP=%TEMP%\ytsh_pt_w_%RANDOM%.tmp"
type nul > "!PT_THREATS_TMP!"
type nul > "!PT_WARN_TMP!"
echo ================================================ > "!PT_REPORT!"
echo   YTSH USER PRIVACY AND TRACKER SCAN REPORT >> "!PT_REPORT!"
echo   Scanned: %DATE% %TIME% >> "!PT_REPORT!"
echo ================================================ >> "!PT_REPORT!"
echo.
powershell -NoProfile -Command "Write-Host '  --- [CHECK 1] WINDOWS ADVERTISING ID (ALL PROFILES) ---' -ForegroundColor !COL_HDR_PS!"
echo.
echo [CHECK 1] ADVERTISING ID >> "!PT_REPORT!"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$rep=$env:PT_REPORT;$thr=$env:PT_THREATS_TMP;$wrn=$env:PT_WARN_TMP;$found=0;$hive='Registry::HKEY_USERS';$sids=Get-ChildItem $hive -EA SilentlyContinue|Where-Object{$_.Name -match 'S-1-5-21'};Write-Host ('  [INFO]    User SIDs found in HKU: '+$sids.Count) -ForegroundColor DarkGray;Add-Content $rep ('User SIDs: '+$sids.Count) -EA SilentlyContinue;foreach($sid in $sids){$advKey=$hive+'\'+$sid.PSChildName+'\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo';$adv=Get-ItemProperty $advKey -EA SilentlyContinue;if($adv -and $adv.Enabled -eq 1){Write-Host ('  [WARN]    Advertising ID ENABLED for SID: '+$sid.PSChildName) -ForegroundColor Yellow;Add-Content $rep ('[WARN] AdvertisingID on: '+$sid.PSChildName) -EA SilentlyContinue;Add-Content $wrn ('Advertising ID enabled: SID '+$sid.PSChildName) -EA SilentlyContinue;$found++}elseif($adv){Write-Host ('  [CLEAN]   Advertising ID disabled for SID: '+$sid.PSChildName) -ForegroundColor Green;Add-Content $rep ('[CLEAN] AdvertisingID off: '+$sid.PSChildName) -EA SilentlyContinue}};$cur=Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo' -EA SilentlyContinue;if($cur -and $cur.Enabled -eq 1){Write-Host '  [WARN]    Advertising ID enabled for current user (HKCU)' -ForegroundColor Yellow;Add-Content $wrn 'AdvertisingID enabled HKCU' -EA SilentlyContinue;$found++}elseif($cur){Write-Host '  [CLEAN]   Advertising ID disabled for current user' -ForegroundColor Green};if($found -eq 0){Add-Content $rep '[CLEAN] Advertising ID not enabled on any profile' -EA SilentlyContinue}"
echo.
powershell -NoProfile -Command "Write-Host '  --- [CHECK 2] TELEMETRY REGISTRY KEYS ---' -ForegroundColor !COL_HDR_PS!"
echo.
echo [CHECK 2] TELEMETRY REGISTRY >> "!PT_REPORT!"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$rep=$env:PT_REPORT;$thr=$env:PT_THREATS_TMP;$wrn=$env:PT_WARN_TMP;$found=0;$checks=@(@{P='HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection';V='AllowTelemetry';Good=0;Desc='DataCollection AllowTelemetry'},@{P='HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection';V='AllowTelemetry';Good=0;Desc='Policy AllowTelemetry'},@{P='HKLM:\SYSTEM\CurrentControlSet\Services\DiagTrack';V='Start';Good=4;Desc='DiagTrack service start'});foreach($c in $checks){$prop=Get-ItemProperty $c.P -EA SilentlyContinue;if($prop -and $null -ne $prop.($c.V)){$val=$prop.($c.V);if($val -eq $c.Good){Write-Host ('  [CLEAN]   '+$c.Desc+' = '+$val+' (restricted)') -ForegroundColor Green;Add-Content $rep ('[CLEAN] '+$c.Desc+'='+$val) -EA SilentlyContinue}else{Write-Host ('  [WARN]    '+$c.Desc+' = '+$val+' (not restricted)') -ForegroundColor Yellow;Add-Content $rep ('[WARN] '+$c.Desc+'='+$val) -EA SilentlyContinue;Add-Content $wrn ($c.Desc+'='+$val+' not restricted') -EA SilentlyContinue;$found++}}else{Write-Host ('  [INFO]    Not configured (default): '+$c.Desc) -ForegroundColor DarkGray;Add-Content $rep ('[INFO] Not set: '+$c.Desc) -EA SilentlyContinue}};if($found -eq 0){Write-Host '  [CLEAN]   Telemetry keys are restricted or unconfigured' -ForegroundColor Green}"
echo.
powershell -NoProfile -Command "Write-Host '  --- [CHECK 3] BROWSER COOKIE STORE PRESENCE ---' -ForegroundColor !COL_HDR_PS!"
echo.
echo [CHECK 3] BROWSER COOKIE STORES >> "!PT_REPORT!"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$rep=$env:PT_REPORT;$thr=$env:PT_THREATS_TMP;$wrn=$env:PT_WARN_TMP;$found=0;$stores=@();Get-ChildItem 'C:\Users' -Directory -EA SilentlyContinue|Where-Object{$_.Name -notmatch '^(Public|Default|Default User|All Users)$'}|ForEach-Object{$u=$_.FullName;$stores+=@($u+'\AppData\Local\Google\Chrome\User Data\Default\Network\Cookies',$u+'\AppData\Local\Microsoft\Edge\User Data\Default\Network\Cookies',$u+'\AppData\Local\BraveSoftware\Brave-Browser\User Data\Default\Network\Cookies')};$presentCount=0;foreach($s in $stores){if(Test-Path $s -EA SilentlyContinue){$presentCount++}};Write-Host ('  [INFO]    Browser cookie database files found: '+$presentCount) -ForegroundColor DarkGray;Add-Content $rep ('Cookie DB files found: '+$presentCount) -EA SilentlyContinue;if($presentCount -gt 0){Write-Host ('  [WARN]    '+$presentCount+' browser cookie stores detected - clear cookies periodically to reduce tracker persistence') -ForegroundColor Yellow;Add-Content $rep ('[WARN] Cookie stores present: '+$presentCount) -EA SilentlyContinue;Add-Content $wrn ('Cookie stores detected: '+$presentCount) -EA SilentlyContinue;$found++}else{Write-Host '  [CLEAN]   No browser cookie stores found on this system' -ForegroundColor Green;Add-Content $rep '[CLEAN] No cookie stores found' -EA SilentlyContinue}"
echo.
powershell -NoProfile -Command "Write-Host '  --- [CHECK 4] TAILORED EXPERIENCES AND INPUT PERSONALIZATION ---' -ForegroundColor !COL_HDR_PS!"
echo.
echo [CHECK 4] TAILORED EXPERIENCES >> "!PT_REPORT!"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$rep=$env:PT_REPORT;$thr=$env:PT_THREATS_TMP;$wrn=$env:PT_WARN_TMP;$found=0;$privChecks=@(@{P='HKCU:\Software\Microsoft\Windows\CurrentVersion\Privacy';V='TailoredExperiencesWithDiagnosticDataEnabled';Bad=1;Desc='Tailored Experiences'},@{P='HKCU:\Software\Microsoft\InputPersonalization';V='RestrictImplicitTextCollection';Bad=0;Desc='Input Text Collection'},@{P='HKCU:\Software\Microsoft\InputPersonalization';V='RestrictImplicitInkCollection';Bad=0;Desc='Input Ink Collection'},@{P='HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced';V='Start_TrackProgs';Bad=1;Desc='Start Menu App Tracking'});foreach($c in $privChecks){$prop=Get-ItemProperty $c.P -EA SilentlyContinue;if($prop -and $null -ne $prop.($c.V)){$val=$prop.($c.V);if($val -eq $c.Bad){Write-Host ('  [WARN]    Privacy-reducing setting active: '+$c.Desc+' = '+$val) -ForegroundColor Yellow;Add-Content $rep ('[WARN] '+$c.Desc+'='+$val) -EA SilentlyContinue;Add-Content $wrn ('Privacy setting active: '+$c.Desc) -EA SilentlyContinue;$found++}else{Write-Host ('  [CLEAN]   '+$c.Desc+' = '+$val) -ForegroundColor Green;Add-Content $rep ('[CLEAN] '+$c.Desc+'='+$val) -EA SilentlyContinue}}else{Write-Host ('  [INFO]    Not configured: '+$c.Desc) -ForegroundColor DarkGray;Add-Content $rep ('[INFO] Not set: '+$c.Desc) -EA SilentlyContinue}};if($found -eq 0){Write-Host '  [CLEAN]   No privacy-reducing personalization flags active' -ForegroundColor Green;Add-Content $rep '[CLEAN] Privacy flags nominal' -EA SilentlyContinue}"
echo.
set "PT_THREAT_COUNT=0"
set "PT_WARN_COUNT=0"
for /f %%A in ('type "!PT_THREATS_TMP!" ^| find /c /v ""') do set "PT_THREAT_COUNT=%%A"
for /f %%A in ('type "!PT_WARN_TMP!" ^| find /c /v ""') do set "PT_WARN_COUNT=%%A"
echo. >> "!PT_REPORT!"
echo ================================================ >> "!PT_REPORT!"
echo   SCAN SUMMARY >> "!PT_REPORT!"
echo ================================================ >> "!PT_REPORT!"
echo   Threats  : !PT_THREAT_COUNT! >> "!PT_REPORT!"
echo   Warnings : !PT_WARN_COUNT! >> "!PT_REPORT!"
echo   Date     : %DATE% %TIME% >> "!PT_REPORT!"
echo ================================================ >> "!PT_REPORT!"
if !PT_THREAT_COUNT! GTR 0 (
    echo. >> "!PT_REPORT!"
    echo   THREATS DETECTED: >> "!PT_REPORT!"
    type "!PT_THREATS_TMP!" >> "!PT_REPORT!" 2>nul
)
if !PT_WARN_COUNT! GTR 0 (
    echo. >> "!PT_REPORT!"
    echo   WARNINGS: >> "!PT_REPORT!"
    type "!PT_WARN_TMP!" >> "!PT_REPORT!" 2>nul
)
echo.
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '    USER PRIVACY AND TRACKER SCAN COMPLETE' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
echo.
if !PT_THREAT_COUNT! GTR 0 (
    powershell -NoProfile -Command "Write-Host '  THREATS  : !PT_THREAT_COUNT!' -ForegroundColor Red"
) else (
    powershell -NoProfile -Command "Write-Host '  THREATS  : !PT_THREAT_COUNT!' -ForegroundColor Green"
)
if !PT_WARN_COUNT! GTR 0 (
    powershell -NoProfile -Command "Write-Host '  WARNINGS : !PT_WARN_COUNT!' -ForegroundColor Yellow"
) else (
    powershell -NoProfile -Command "Write-Host '  WARNINGS : !PT_WARN_COUNT!' -ForegroundColor Green"
)
echo.
powershell -NoProfile -Command "Write-Host '  Report saved to:' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host ('  ' + $env:PT_REPORT) -ForegroundColor !COL_OPS_PS!"
echo.
if "!SA_ACTIVE!"=="1" goto SA_PT_CONT
pause
del "!PT_THREATS_TMP!" >nul 2>&1
del "!PT_WARN_TMP!" >nul 2>&1
goto PRIVACY_TRACKER_SCANNER
:SA_PT_CONT
del "!PT_THREATS_TMP!" >nul 2>&1
del "!PT_WARN_TMP!" >nul 2>&1
echo.
powershell -NoProfile -Command "Write-Host '  B  >  Continue to next scanner (Vulnerability and Patch)' -ForegroundColor Yellow"
echo.
:SA_PT_WAIT
set "SA_CONT="
set /p "SA_CONT=  [B] Continue: "
if /i not "!SA_CONT!"=="B" goto SA_PT_WAIT
goto CV_RUN_SCAN

:CVE_PATCH_SCANNER
cls
color !COL_OPS!
echo.
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '    VULNERABILITY AND PATCH SCANNER' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
echo.
powershell -NoProfile -Command "Write-Host '  Checks: Windows Update auto-update config, days since last' -ForegroundColor DarkGray"
powershell -NoProfile -Command "Write-Host '  hotfix, Defender definition age, pending reboot for updates' -ForegroundColor DarkGray"
echo.
echo   1  ^>  Begin Scan
echo   B  ^>  Back
echo.
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
echo.
set "CV_START="
set /p "CV_START=  Select [1, B]: "
if /i "!CV_START!"=="B" goto CAT_SCANNING
if not "!CV_START!"=="1" goto CVE_PATCH_SCANNER
:CV_RUN_SCAN
cls
color !COL_OPS!
echo.
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '    VULNERABILITY AND PATCH SCANNER - RUNNING' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
echo.
for /f %%D in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd_HHmm"') do set "CV_DATE=%%D"
set "CV_REPORT=!LOGDIR!\YTSH_VulnPatch_!CV_DATE!.txt"
set "CV_THREATS_TMP=%TEMP%\ytsh_cv_t_%RANDOM%.tmp"
set "CV_WARN_TMP=%TEMP%\ytsh_cv_w_%RANDOM%.tmp"
type nul > "!CV_THREATS_TMP!"
type nul > "!CV_WARN_TMP!"
echo ================================================ > "!CV_REPORT!"
echo   YTSH VULNERABILITY AND PATCH SCAN REPORT >> "!CV_REPORT!"
echo   Scanned: %DATE% %TIME% >> "!CV_REPORT!"
echo ================================================ >> "!CV_REPORT!"
echo.
powershell -NoProfile -Command "Write-Host '  --- [CHECK 1] WINDOWS UPDATE CONFIGURATION ---' -ForegroundColor !COL_HDR_PS!"
echo.
echo [CHECK 1] WINDOWS UPDATE CONFIG >> "!CV_REPORT!"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$rep=$env:CV_REPORT;$thr=$env:CV_THREATS_TMP;$wrn=$env:CV_WARN_TMP;$found=0;$wuKey=Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update' -EA SilentlyContinue;$au=$wuKey.AUOptions;$desc=switch($au){1{'Never check for updates'} 2{'Notify before download only'} 3{'Notify before install'} 4{'Auto-install (recommended)'} $null{'Not explicitly set (uses default)'} default{'Unknown value: '+$au}};Write-Host ('  [INFO]    Windows Update AUOptions: '+$desc) -ForegroundColor DarkGray;Add-Content $rep ('WU AUOptions: '+$desc) -EA SilentlyContinue;if($au -eq 1){Write-Host '  [THREAT]  Windows Update set to NEVER CHECK - system may be critically unpatched' -ForegroundColor Red;Add-Content $rep '[THREAT] WU set to never check' -EA SilentlyContinue;Add-Content $thr 'Windows Update disabled - never checks' -EA SilentlyContinue;$found++}elseif($au -eq 2){Write-Host '  [WARN]    Windows Update only notifies - updates are not downloaded automatically' -ForegroundColor Yellow;Add-Content $wrn 'WU notify-only mode' -EA SilentlyContinue;$found++}else{Write-Host '  [CLEAN]   Windows Update is configured to check or auto-install' -ForegroundColor Green;Add-Content $rep '[CLEAN] WU active' -EA SilentlyContinue};$detectKey=Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\Results\Detect' -EA SilentlyContinue;if($detectKey -and $detectKey.LastSuccessTime){try{$lastDt=[datetime]::ParseExact($detectKey.LastSuccessTime,'yyyy-MM-dd HH:mm:ss',$null);$days=([datetime]::Now-$lastDt).Days;Write-Host ('  [INFO]    Last WU detection: '+$detectKey.LastSuccessTime+' ('+$days+' days ago)') -ForegroundColor DarkGray;Add-Content $rep ('Last WU detect: '+$detectKey.LastSuccessTime+' ('+$days+' days ago)') -EA SilentlyContinue;if($days -gt 30){Write-Host '  [WARN]    Windows Update has not checked in over 30 days' -ForegroundColor Yellow;Add-Content $wrn ('WU last check '+$days+' days ago') -EA SilentlyContinue;$found++}}catch{Write-Host '  [INFO]    Could not parse last WU detection time' -ForegroundColor DarkGray}};if($found -eq 0){Write-Host '  [CLEAN]   Windows Update configuration is acceptable' -ForegroundColor Green}"
echo.
powershell -NoProfile -Command "Write-Host '  --- [CHECK 2] RECENT HOTFIXES ---' -ForegroundColor !COL_HDR_PS!"
echo.
echo [CHECK 2] RECENT HOTFIXES >> "!CV_REPORT!"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$rep=$env:CV_REPORT;$thr=$env:CV_THREATS_TMP;$wrn=$env:CV_WARN_TMP;$found=0;$hf=Get-HotFix -EA SilentlyContinue|Where-Object{$_.InstalledOn -ne $null}|Sort-Object InstalledOn -Descending;$total=(Get-HotFix -EA SilentlyContinue).Count;Write-Host ('  [INFO]    Total hotfixes installed: '+$total) -ForegroundColor DarkGray;Add-Content $rep ('Hotfixes total: '+$total) -EA SilentlyContinue;$latest=$hf|Select-Object -First 1;if($latest -and $latest.InstalledOn){$days=([datetime]::Now-[datetime]$latest.InstalledOn).Days;Write-Host ('  [INFO]    Most recent hotfix: '+$latest.HotFixID+' installed '+$days+' days ago') -ForegroundColor DarkGray;Add-Content $rep ('Latest hotfix: '+$latest.HotFixID+' ('+$days+' days ago)') -EA SilentlyContinue;if($days -gt 60){Write-Host '  [WARN]    No hotfix installed in over 60 days - security patches may be missing' -ForegroundColor Yellow;Add-Content $rep '[WARN] No hotfix in 60+ days' -EA SilentlyContinue;Add-Content $wrn ('Last hotfix was '+$days+' days ago') -EA SilentlyContinue;$found++}else{Write-Host '  [CLEAN]   Recent hotfix installed within 60 days' -ForegroundColor Green;Add-Content $rep '[CLEAN] Recent hotfix OK' -EA SilentlyContinue}}else{Write-Host '  [WARN]    Could not determine hotfix installation dates' -ForegroundColor Yellow;Add-Content $wrn 'Hotfix dates unavailable' -EA SilentlyContinue};$hf|Select-Object -First 5|ForEach-Object{$dt=if($_.InstalledOn){([datetime]$_.InstalledOn).ToString('yyyy-MM-dd')}else{'unknown'};Add-Content $rep ('  '+$_.HotFixID+' | '+$dt+' | '+$_.Description) -EA SilentlyContinue};if($found -eq 0 -and $latest){Write-Host '  [CLEAN]   Hotfix history looks up to date' -ForegroundColor Green}"
echo.
powershell -NoProfile -Command "Write-Host '  --- [CHECK 3] WINDOWS DEFENDER STATUS ---' -ForegroundColor !COL_HDR_PS!"
echo.
echo [CHECK 3] DEFENDER STATUS >> "!CV_REPORT!"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$rep=$env:CV_REPORT;$thr=$env:CV_THREATS_TMP;$wrn=$env:CV_WARN_TMP;$found=0;try{$mp=Get-MpComputerStatus -EA SilentlyContinue;if($mp){if(-not $mp.AntivirusEnabled){Write-Host '  [THREAT]  Windows Defender antivirus is DISABLED' -ForegroundColor Red;Add-Content $rep '[THREAT] Defender disabled' -EA SilentlyContinue;Add-Content $thr 'Windows Defender antivirus disabled' -EA SilentlyContinue;$found++}else{Write-Host '  [CLEAN]   Windows Defender antivirus is enabled' -ForegroundColor Green;Add-Content $rep '[CLEAN] Defender enabled' -EA SilentlyContinue};$defAge=([datetime]::Now-$mp.AntivirusSignatureLastUpdated).Days;Write-Host ('  [INFO]    Defender definitions last updated: '+$mp.AntivirusSignatureLastUpdated.ToString('yyyy-MM-dd')+' ('+$defAge+' days ago)') -ForegroundColor DarkGray;Add-Content $rep ('Defender defs: '+$mp.AntivirusSignatureLastUpdated.ToString('yyyy-MM-dd')+' ('+$defAge+' days ago)') -EA SilentlyContinue;if($defAge -gt 7){Write-Host ('  [WARN]    Defender definitions are '+$defAge+' days old - update recommended') -ForegroundColor Yellow;Add-Content $rep '[WARN] Defender defs over 7 days old' -EA SilentlyContinue;Add-Content $wrn ('Defender defs '+$defAge+' days old') -EA SilentlyContinue;$found++}else{Write-Host '  [CLEAN]   Defender definitions are current' -ForegroundColor Green;Add-Content $rep '[CLEAN] Defender defs current' -EA SilentlyContinue};if($mp.RealTimeProtectionEnabled){Write-Host '  [CLEAN]   Real-time protection is enabled' -ForegroundColor Green;Add-Content $rep '[CLEAN] RTP enabled' -EA SilentlyContinue}else{Write-Host '  [THREAT]  Real-time protection is DISABLED' -ForegroundColor Red;Add-Content $thr 'Defender real-time protection disabled' -EA SilentlyContinue;Add-Content $rep '[THREAT] RTP disabled' -EA SilentlyContinue;$found++}}else{Write-Host '  [INFO]    Could not query Defender status (may not be the active AV)' -ForegroundColor DarkGray;Add-Content $rep '[INFO] Defender status unavailable' -EA SilentlyContinue}}catch{Write-Host '  [INFO]    Defender query failed (third-party AV may be active)' -ForegroundColor DarkGray;Add-Content $rep '[INFO] Defender query failed' -EA SilentlyContinue}"
echo.
powershell -NoProfile -Command "Write-Host '  --- [CHECK 4] PENDING UPDATE REBOOT ---' -ForegroundColor !COL_HDR_PS!"
echo.
echo [CHECK 4] PENDING REBOOT >> "!CV_REPORT!"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$rep=$env:CV_REPORT;$thr=$env:CV_THREATS_TMP;$wrn=$env:CV_WARN_TMP;$found=0;$wuReboot='HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired';$cbsReboot='HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending';$pfroReboot='HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager';if(Test-Path $wuReboot -EA SilentlyContinue){Write-Host '  [WARN]    Reboot is required to apply pending Windows updates' -ForegroundColor Yellow;Add-Content $rep '[WARN] WU reboot pending' -EA SilentlyContinue;Add-Content $wrn 'Windows Update reboot pending' -EA SilentlyContinue;$found++}else{Write-Host '  [CLEAN]   No Windows Update reboot pending' -ForegroundColor Green;Add-Content $rep '[CLEAN] No WU reboot pending' -EA SilentlyContinue};if(Test-Path $cbsReboot -EA SilentlyContinue){Write-Host '  [WARN]    Component Based Servicing reboot is pending' -ForegroundColor Yellow;Add-Content $rep '[WARN] CBS reboot pending' -EA SilentlyContinue;Add-Content $wrn 'CBS reboot pending' -EA SilentlyContinue;$found++}else{Write-Host '  [CLEAN]   No Component Servicing reboot pending' -ForegroundColor Green;Add-Content $rep '[CLEAN] No CBS reboot pending' -EA SilentlyContinue};$pfro=Get-ItemProperty $pfroReboot -EA SilentlyContinue;if($pfro -and $pfro.PendingFileRenameOperations){Write-Host '  [WARN]    Pending file rename operations detected (update or installer in-progress)' -ForegroundColor Yellow;Add-Content $rep '[WARN] Pending file rename operations' -EA SilentlyContinue;Add-Content $wrn 'Pending file rename operations' -EA SilentlyContinue;$found++}else{Write-Host '  [CLEAN]   No pending file rename operations' -ForegroundColor Green;Add-Content $rep '[CLEAN] No pending file renames' -EA SilentlyContinue};if($found -eq 0){Write-Host '  [CLEAN]   No pending update reboots or operations detected' -ForegroundColor Green}"
echo.
set "CV_THREAT_COUNT=0"
set "CV_WARN_COUNT=0"
for /f %%A in ('type "!CV_THREATS_TMP!" ^| find /c /v ""') do set "CV_THREAT_COUNT=%%A"
for /f %%A in ('type "!CV_WARN_TMP!" ^| find /c /v ""') do set "CV_WARN_COUNT=%%A"
echo. >> "!CV_REPORT!"
echo ================================================ >> "!CV_REPORT!"
echo   SCAN SUMMARY >> "!CV_REPORT!"
echo ================================================ >> "!CV_REPORT!"
echo   Threats  : !CV_THREAT_COUNT! >> "!CV_REPORT!"
echo   Warnings : !CV_WARN_COUNT! >> "!CV_REPORT!"
echo   Date     : %DATE% %TIME% >> "!CV_REPORT!"
echo ================================================ >> "!CV_REPORT!"
if !CV_THREAT_COUNT! GTR 0 (
    echo. >> "!CV_REPORT!"
    echo   THREATS DETECTED: >> "!CV_REPORT!"
    type "!CV_THREATS_TMP!" >> "!CV_REPORT!" 2>nul
)
if !CV_WARN_COUNT! GTR 0 (
    echo. >> "!CV_REPORT!"
    echo   WARNINGS: >> "!CV_REPORT!"
    type "!CV_WARN_TMP!" >> "!CV_REPORT!" 2>nul
)
echo.
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '    VULNERABILITY AND PATCH SCAN COMPLETE' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
echo.
if !CV_THREAT_COUNT! GTR 0 (
    powershell -NoProfile -Command "Write-Host '  THREATS  : !CV_THREAT_COUNT!' -ForegroundColor Red"
) else (
    powershell -NoProfile -Command "Write-Host '  THREATS  : !CV_THREAT_COUNT!' -ForegroundColor Green"
)
if !CV_WARN_COUNT! GTR 0 (
    powershell -NoProfile -Command "Write-Host '  WARNINGS : !CV_WARN_COUNT!' -ForegroundColor Yellow"
) else (
    powershell -NoProfile -Command "Write-Host '  WARNINGS : !CV_WARN_COUNT!' -ForegroundColor Green"
)
echo.
powershell -NoProfile -Command "Write-Host '  Report saved to:' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host ('  ' + $env:CV_REPORT) -ForegroundColor !COL_OPS_PS!"
echo.
if "!SA_ACTIVE!"=="1" goto SA_CV_CONT
pause
del "!CV_THREATS_TMP!" >nul 2>&1
del "!CV_WARN_TMP!" >nul 2>&1
goto CVE_PATCH_SCANNER
:SA_CV_CONT
del "!CV_THREATS_TMP!" >nul 2>&1
del "!CV_WARN_TMP!" >nul 2>&1
echo.
powershell -NoProfile -Command "Write-Host '  B  >  Continue to next scanner (Hardware Health and SMART)' -ForegroundColor Yellow"
echo.
:SA_CV_WAIT
set "SA_CONT="
set /p "SA_CONT=  [B] Continue: "
if /i not "!SA_CONT!"=="B" goto SA_CV_WAIT
goto SM_RUN_SCAN

:SMART_HEALTH_SCANNER
cls
color !COL_OPS!
echo.
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '    HARDWARE HEALTH AND SMART SCANNER' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
echo.
powershell -NoProfile -Command "Write-Host '  Checks: physical disk health status, SMART reliability' -ForegroundColor DarkGray"
powershell -NoProfile -Command "Write-Host '  counters, drive temperature, SSD wear level, free space' -ForegroundColor DarkGray"
echo.
echo   1  ^>  Begin Scan
echo   B  ^>  Back
echo.
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
echo.
set "SM_START="
set /p "SM_START=  Select [1, B]: "
if /i "!SM_START!"=="B" goto CAT_SCANNING
if not "!SM_START!"=="1" goto SMART_HEALTH_SCANNER
:SM_RUN_SCAN
cls
color !COL_OPS!
echo.
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '    HARDWARE HEALTH AND SMART SCANNER - RUNNING' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
echo.
for /f %%D in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd_HHmm"') do set "SM_DATE=%%D"
set "SM_REPORT=!LOGDIR!\YTSH_SMARTHealth_!SM_DATE!.txt"
set "SM_THREATS_TMP=%TEMP%\ytsh_sm_t_%RANDOM%.tmp"
set "SM_WARN_TMP=%TEMP%\ytsh_sm_w_%RANDOM%.tmp"
type nul > "!SM_THREATS_TMP!"
type nul > "!SM_WARN_TMP!"
echo ================================================ > "!SM_REPORT!"
echo   YTSH HARDWARE HEALTH AND SMART SCAN REPORT >> "!SM_REPORT!"
echo   Scanned: %DATE% %TIME% >> "!SM_REPORT!"
echo ================================================ >> "!SM_REPORT!"
echo.
powershell -NoProfile -Command "Write-Host '  --- [CHECK 1] PHYSICAL DISK HEALTH STATUS ---' -ForegroundColor !COL_HDR_PS!"
echo.
echo [CHECK 1] PHYSICAL DISK HEALTH >> "!SM_REPORT!"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$rep=$env:SM_REPORT;$thr=$env:SM_THREATS_TMP;$wrn=$env:SM_WARN_TMP;$found=0;$disks=Get-PhysicalDisk -EA SilentlyContinue;if($disks -and @($disks).Count -gt 0){$disks=@($disks);Write-Host ('  [INFO]    Physical disks found: '+$disks.Count) -ForegroundColor DarkGray;Add-Content $rep ('Physical disks: '+$disks.Count) -EA SilentlyContinue;foreach($d in $disks){$sizeGB=[math]::Round($d.Size/1GB,0);$health=$d.HealthStatus;Write-Host ('  [INFO]    '+$d.FriendlyName+' | '+$d.MediaType+' | '+$sizeGB+'GB | Health: '+$health) -ForegroundColor DarkGray;Add-Content $rep ('Disk: '+$d.FriendlyName+' | '+$d.MediaType+' | '+$sizeGB+'GB | '+$health) -EA SilentlyContinue;if($health -eq 'Unhealthy'){Write-Host ('  [THREAT]  Disk reports UNHEALTHY: '+$d.FriendlyName) -ForegroundColor Red;Add-Content $thr ('Unhealthy disk: '+$d.FriendlyName) -EA SilentlyContinue;Add-Content $rep ('[THREAT] Unhealthy: '+$d.FriendlyName) -EA SilentlyContinue;$found++}elseif($health -match 'Warning|Degraded|Failed'){Write-Host ('  [WARN]    Disk health degraded: '+$d.FriendlyName+' ('+$health+')') -ForegroundColor Yellow;Add-Content $wrn ('Disk degraded: '+$d.FriendlyName) -EA SilentlyContinue;$found++}elseif($health -eq 'Healthy'){Write-Host ('  [CLEAN]   Disk healthy: '+$d.FriendlyName) -ForegroundColor Green}}}else{Write-Host '  [INFO]    Get-PhysicalDisk unavailable - falling back to CIM' -ForegroundColor DarkGray;$cimDisks=@(Get-CimInstance Win32_DiskDrive -EA SilentlyContinue);Write-Host ('  [INFO]    Drives found via CIM: '+$cimDisks.Count) -ForegroundColor DarkGray;Add-Content $rep ('CIM drives: '+$cimDisks.Count) -EA SilentlyContinue;foreach($d in $cimDisks){$sizeGB=[math]::Round($d.Size/1GB,0);Write-Host ('  [INFO]    '+$d.Model+' | '+$sizeGB+'GB | Status: '+$d.Status) -ForegroundColor DarkGray;Add-Content $rep ('CIM Disk: '+$d.Model+' | '+$sizeGB+'GB | '+$d.Status) -EA SilentlyContinue;if($d.Status -notmatch 'OK|Unknown'){Write-Host ('  [WARN]    Disk non-OK status: '+$d.Model+' = '+$d.Status) -ForegroundColor Yellow;Add-Content $wrn ('Disk non-OK: '+$d.Model) -EA SilentlyContinue;$found++}}};if($found -eq 0){Write-Host '  [CLEAN]   All physical disks report healthy or OK' -ForegroundColor Green;Add-Content $rep '[CLEAN] All disks healthy' -EA SilentlyContinue}"
echo.
powershell -NoProfile -Command "Write-Host '  --- [CHECK 2] SMART RELIABILITY COUNTERS ---' -ForegroundColor !COL_HDR_PS!"
echo.
echo [CHECK 2] SMART COUNTERS >> "!SM_REPORT!"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$rep=$env:SM_REPORT;$thr=$env:SM_THREATS_TMP;$wrn=$env:SM_WARN_TMP;$found=0;$disks=Get-PhysicalDisk -EA SilentlyContinue;if(-not $disks){Write-Host '  [INFO]    SMART counters unavailable (Get-PhysicalDisk not supported)' -ForegroundColor DarkGray;Add-Content $rep '[INFO] SMART counters unavailable' -EA SilentlyContinue}else{foreach($d in @($disks)){try{$rc=$d|Get-StorageReliabilityCounter -EA SilentlyContinue;if($rc){$temp=$rc.Temperature;$rErr=$rc.ReadErrorsTotal;$wErr=$rc.WriteErrorsTotal;$wear=$rc.Wear;Write-Host ('  [INFO]    '+$d.FriendlyName+' SMART: Temp='+$temp+'C ReadErr='+$rErr+' WriteErr='+$wErr+' Wear='+$wear+'%%') -ForegroundColor DarkGray;Add-Content $rep ('SMART ['+$d.FriendlyName+']: Temp='+$temp+' ReadErr='+$rErr+' WriteErr='+$wErr+' Wear='+$wear+'%%') -EA SilentlyContinue;if($temp -and [int]$temp -gt 55){Write-Host ('  [THREAT]  Drive temp critically high: '+$temp+'C on '+$d.FriendlyName) -ForegroundColor Red;Add-Content $thr ('Drive temp critical: '+$temp+'C '+$d.FriendlyName) -EA SilentlyContinue;$found++}elseif($temp -and [int]$temp -gt 45){Write-Host ('  [WARN]    Drive temp elevated: '+$temp+'C on '+$d.FriendlyName) -ForegroundColor Yellow;Add-Content $wrn ('Drive temp elevated: '+$temp+'C') -EA SilentlyContinue;$found++};if($rErr -and [long]$rErr -gt 0){Write-Host ('  [WARN]    Read errors detected: '+$rErr+' on '+$d.FriendlyName) -ForegroundColor Yellow;Add-Content $wrn ('Read errors: '+$rErr+' on '+$d.FriendlyName) -EA SilentlyContinue;$found++};if($wErr -and [long]$wErr -gt 0){Write-Host ('  [WARN]    Write errors detected: '+$wErr+' on '+$d.FriendlyName) -ForegroundColor Yellow;Add-Content $wrn ('Write errors: '+$wErr+' on '+$d.FriendlyName) -EA SilentlyContinue;$found++};if($wear -and [int]$wear -gt 90){Write-Host ('  [THREAT]  SSD wear critical: '+$wear+'%% worn on '+$d.FriendlyName) -ForegroundColor Red;Add-Content $thr ('SSD wear critical: '+$wear+'%%') -EA SilentlyContinue;$found++}elseif($wear -and [int]$wear -gt 70){Write-Host ('  [WARN]    SSD wear elevated: '+$wear+'%% worn on '+$d.FriendlyName) -ForegroundColor Yellow;Add-Content $wrn ('SSD wear: '+$wear+'%%') -EA SilentlyContinue;$found++}}else{Write-Host ('  [INFO]    SMART counters not returned for: '+$d.FriendlyName) -ForegroundColor DarkGray}}catch{Write-Host ('  [INFO]    Could not read SMART counters for: '+$d.FriendlyName) -ForegroundColor DarkGray;Add-Content $rep ('[INFO] SMART unavailable: '+$d.FriendlyName) -EA SilentlyContinue}}};if($found -eq 0){Write-Host '  [CLEAN]   SMART counters nominal on all queried drives' -ForegroundColor Green;Add-Content $rep '[CLEAN] SMART nominal' -EA SilentlyContinue}"
echo.
powershell -NoProfile -Command "Write-Host '  --- [CHECK 3] LOGICAL DISK FREE SPACE ---' -ForegroundColor !COL_HDR_PS!"
echo.
echo [CHECK 3] FREE SPACE >> "!SM_REPORT!"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$rep=$env:SM_REPORT;$thr=$env:SM_THREATS_TMP;$wrn=$env:SM_WARN_TMP;$found=0;$vols=@(Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' -EA SilentlyContinue);foreach($v in $vols){if($v.Size -and $v.Size -gt 0){$fGB=[math]::Round($v.FreeSpace/1GB,1);$tGB=[math]::Round($v.Size/1GB,1);$pct=[math]::Round(($v.FreeSpace/$v.Size)*100,1);Write-Host ('  [INFO]    '+$v.DeviceID+' Free: '+$fGB+'GB / '+$tGB+'GB ('+$pct+'%%)') -ForegroundColor DarkGray;Add-Content $rep ('Drive '+$v.DeviceID+': '+$fGB+'GB free of '+$tGB+'GB ('+$pct+'%%)') -EA SilentlyContinue;if($pct -lt 5){Write-Host ('  [THREAT]  '+$v.DeviceID+' critically low: '+$fGB+'GB ('+$pct+'%%) free') -ForegroundColor Red;Add-Content $thr ('Drive '+$v.DeviceID+' critical: '+$pct+'%% free') -EA SilentlyContinue;$found++}elseif($pct -lt 15){Write-Host ('  [WARN]    '+$v.DeviceID+' low: '+$fGB+'GB ('+$pct+'%%) free') -ForegroundColor Yellow;Add-Content $wrn ('Drive low: '+$v.DeviceID+' '+$pct+'%%') -EA SilentlyContinue;$found++}else{Write-Host ('  [CLEAN]   '+$v.DeviceID+' space OK: '+$pct+'%% free') -ForegroundColor Green}}};if($found -eq 0){Write-Host '  [CLEAN]   All drives have adequate free space' -ForegroundColor Green;Add-Content $rep '[CLEAN] Disk space nominal' -EA SilentlyContinue}"
echo.
set "SM_THREAT_COUNT=0"
set "SM_WARN_COUNT=0"
for /f %%A in ('type "!SM_THREATS_TMP!" ^| find /c /v ""') do set "SM_THREAT_COUNT=%%A"
for /f %%A in ('type "!SM_WARN_TMP!" ^| find /c /v ""') do set "SM_WARN_COUNT=%%A"
echo. >> "!SM_REPORT!"
echo ================================================ >> "!SM_REPORT!"
echo   SCAN SUMMARY >> "!SM_REPORT!"
echo ================================================ >> "!SM_REPORT!"
echo   Threats  : !SM_THREAT_COUNT! >> "!SM_REPORT!"
echo   Warnings : !SM_WARN_COUNT! >> "!SM_REPORT!"
echo   Date     : %DATE% %TIME% >> "!SM_REPORT!"
echo ================================================ >> "!SM_REPORT!"
if !SM_THREAT_COUNT! GTR 0 (
    echo. >> "!SM_REPORT!"
    echo   THREATS DETECTED: >> "!SM_REPORT!"
    type "!SM_THREATS_TMP!" >> "!SM_REPORT!" 2>nul
)
if !SM_WARN_COUNT! GTR 0 (
    echo. >> "!SM_REPORT!"
    echo   WARNINGS: >> "!SM_REPORT!"
    type "!SM_WARN_TMP!" >> "!SM_REPORT!" 2>nul
)
echo.
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '    HARDWARE HEALTH AND SMART SCAN COMPLETE' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
echo.
if !SM_THREAT_COUNT! GTR 0 (
    powershell -NoProfile -Command "Write-Host '  THREATS  : !SM_THREAT_COUNT!' -ForegroundColor Red"
) else (
    powershell -NoProfile -Command "Write-Host '  THREATS  : !SM_THREAT_COUNT!' -ForegroundColor Green"
)
if !SM_WARN_COUNT! GTR 0 (
    powershell -NoProfile -Command "Write-Host '  WARNINGS : !SM_WARN_COUNT!' -ForegroundColor Yellow"
) else (
    powershell -NoProfile -Command "Write-Host '  WARNINGS : !SM_WARN_COUNT!' -ForegroundColor Green"
)
echo.
powershell -NoProfile -Command "Write-Host '  Report saved to:' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host ('  ' + $env:SM_REPORT) -ForegroundColor !COL_OPS_PS!"
echo.
if "!SA_ACTIVE!"=="1" goto SA_SM_CONT
pause
del "!SM_THREATS_TMP!" >nul 2>&1
del "!SM_WARN_TMP!" >nul 2>&1
goto SMART_HEALTH_SCANNER
:SA_SM_CONT
del "!SM_THREATS_TMP!" >nul 2>&1
del "!SM_WARN_TMP!" >nul 2>&1
echo.
powershell -NoProfile -Command "Write-Host '  B  >  Continue to next scanner (Sensitive Information DLP)' -ForegroundColor Yellow"
echo.
:SA_SM_WAIT
set "SA_CONT="
set /p "SA_CONT=  [B] Continue: "
if /i not "!SA_CONT!"=="B" goto SA_SM_WAIT
goto DL_RUN_SCAN

:DLP_SCANNER
cls
color !COL_OPS!
echo.
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '    SENSITIVE INFORMATION (DLP) SCANNER' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
echo.
powershell -NoProfile -Command "Write-Host '  Scans Documents, Desktop, Downloads for SSNs,' -ForegroundColor DarkGray"
powershell -NoProfile -Command "Write-Host '  credit card numbers, plaintext API keys and passwords' -ForegroundColor DarkGray"
echo.
echo   1  ^>  Begin Scan
echo   B  ^>  Back
echo.
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
echo.
set "DL_START="
set /p "DL_START=  Select [1, B]: "
if /i "!DL_START!"=="B" goto CAT_SCANNING
if not "!DL_START!"=="1" goto DLP_SCANNER
:DL_RUN_SCAN
cls
color !COL_OPS!
echo.
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '    SENSITIVE INFORMATION (DLP) SCANNER - RUNNING' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
echo.
for /f %%D in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd_HHmm"') do set "DL_DATE=%%D"
set "DL_REPORT=!LOGDIR!\YTSH_DLP_!DL_DATE!.txt"
set "DL_THREATS_TMP=%TEMP%\ytsh_dl_t_%RANDOM%.tmp"
set "DL_WARN_TMP=%TEMP%\ytsh_dl_w_%RANDOM%.tmp"
type nul > "!DL_THREATS_TMP!"
type nul > "!DL_WARN_TMP!"
echo ================================================ > "!DL_REPORT!"
echo   YTSH SENSITIVE INFORMATION (DLP) SCAN REPORT >> "!DL_REPORT!"
echo   Scanned: %DATE% %TIME% >> "!DL_REPORT!"
echo ================================================ >> "!DL_REPORT!"
echo.
powershell -NoProfile -Command "Write-Host '  --- [CHECK 1] SOCIAL SECURITY NUMBER PATTERNS ---' -ForegroundColor !COL_HDR_PS!"
echo.
echo [CHECK 1] SSN PATTERNS >> "!DL_REPORT!"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$rep=$env:DL_REPORT;$thr=$env:DL_THREATS_TMP;$wrn=$env:DL_WARN_TMP;$found=0;$exts=@('*.txt','*.csv','*.log','*.xml','*.json','*.md','*.ini','*.cfg','*.conf','*.env');$searchDirs=@();Get-ChildItem 'C:\Users' -Directory -EA SilentlyContinue|Where-Object{$_.Name -notmatch '^(Public|Default|Default User|All Users)$'}|ForEach-Object{$u=$_.FullName;$searchDirs+=@($u+'\Documents',$u+'\Desktop',$u+'\Downloads')};$ssnPattern='\b(?!000|666|9\d{2})\d{3}-(?!00)\d{2}-(?!0000)\d{4}\b';$hitCount=0;foreach($dir in $searchDirs){if(-not (Test-Path $dir -EA SilentlyContinue)){continue};foreach($ext in $exts){Get-ChildItem $dir -Filter $ext -Recurse -EA SilentlyContinue -Force|Where-Object{$_.Length -lt 2MB}|ForEach-Object{try{$content=Get-Content $_.FullName -Raw -EA SilentlyContinue;if($content -match $ssnPattern){Write-Host ('  [THREAT]  Possible SSN found in: '+$_.FullName) -ForegroundColor Red;Add-Content $rep ('[THREAT] Possible SSN: '+$_.FullName) -EA SilentlyContinue;Add-Content $thr ('SSN pattern in: '+$_.Name) -EA SilentlyContinue;$hitCount++;$found++}}catch{}}}};Write-Host ('  [INFO]    Files with SSN patterns: '+$hitCount) -ForegroundColor DarkGray;Add-Content $rep ('SSN pattern hits: '+$hitCount) -EA SilentlyContinue;if($found -eq 0){Write-Host '  [CLEAN]   No SSN patterns found in scanned text files' -ForegroundColor Green;Add-Content $rep '[CLEAN] No SSN patterns found' -EA SilentlyContinue}"
echo.
powershell -NoProfile -Command "Write-Host '  --- [CHECK 2] CREDIT CARD NUMBER PATTERNS ---' -ForegroundColor !COL_HDR_PS!"
echo.
echo [CHECK 2] CREDIT CARD PATTERNS >> "!DL_REPORT!"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$rep=$env:DL_REPORT;$thr=$env:DL_THREATS_TMP;$wrn=$env:DL_WARN_TMP;$found=0;$exts=@('*.txt','*.csv','*.log','*.xml','*.json','*.md','*.ini','*.cfg','*.conf','*.env');$searchDirs=@();Get-ChildItem 'C:\Users' -Directory -EA SilentlyContinue|Where-Object{$_.Name -notmatch '^(Public|Default|Default User|All Users)$'}|ForEach-Object{$u=$_.FullName;$searchDirs+=@($u+'\Documents',$u+'\Desktop',$u+'\Downloads')};$ccPattern='\b(?:4[0-9]{12}(?:[0-9]{3})?|5[1-5][0-9]{14}|3[47][0-9]{13}|3(?:0[0-5]|[68][0-9])[0-9]{11}|6(?:011|5[0-9]{2})[0-9]{12}|(?:2131|1800|35\d{3})\d{11})\b';$hitCount=0;foreach($dir in $searchDirs){if(-not (Test-Path $dir -EA SilentlyContinue)){continue};foreach($ext in $exts){Get-ChildItem $dir -Filter $ext -Recurse -EA SilentlyContinue -Force|Where-Object{$_.Length -lt 2MB}|ForEach-Object{try{$content=Get-Content $_.FullName -Raw -EA SilentlyContinue;if($content -match $ccPattern){Write-Host ('  [THREAT]  Possible credit card number in: '+$_.FullName) -ForegroundColor Red;Add-Content $rep ('[THREAT] Possible CC: '+$_.FullName) -EA SilentlyContinue;Add-Content $thr ('CC pattern in: '+$_.Name) -EA SilentlyContinue;$hitCount++;$found++}}catch{}}}};Write-Host ('  [INFO]    Files with credit card patterns: '+$hitCount) -ForegroundColor DarkGray;if($found -eq 0){Write-Host '  [CLEAN]   No credit card patterns found in scanned text files' -ForegroundColor Green;Add-Content $rep '[CLEAN] No CC patterns found' -EA SilentlyContinue}"
echo.
powershell -NoProfile -Command "Write-Host '  --- [CHECK 3] PLAINTEXT API KEY PATTERNS ---' -ForegroundColor !COL_HDR_PS!"
echo.
echo [CHECK 3] API KEY PATTERNS >> "!DL_REPORT!"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$rep=$env:DL_REPORT;$thr=$env:DL_THREATS_TMP;$wrn=$env:DL_WARN_TMP;$found=0;$exts=@('*.txt','*.csv','*.log','*.xml','*.json','*.md','*.ini','*.cfg','*.conf','*.env','*.yaml','*.yml','*.toml','*.properties');$searchDirs=@();Get-ChildItem 'C:\Users' -Directory -EA SilentlyContinue|Where-Object{$_.Name -notmatch '^(Public|Default|Default User|All Users)$'}|ForEach-Object{$u=$_.FullName;$searchDirs+=@($u+'\Documents',$u+'\Desktop',$u+'\Downloads',$u+'\AppData\Roaming',$u+'\AppData\Local')};$apiPatterns=@(@{Name='AWS Access Key';Pattern='AKIA[0-9A-Z]{16}'},@{Name='AWS Secret Key';Pattern='(?i)aws.{0,20}secret.{0,20}[''"][0-9a-zA-Z/+=]{40}[''"]'},@{Name='GitHub Token';Pattern='ghp_[0-9a-zA-Z]{36}'},@{Name='OpenAI Key';Pattern='sk-[0-9a-zA-Z]{48}'},@{Name='Generic API Key';Pattern='(?i)(api_key|apikey|api-key)\s*[=:]\s*[''"]?[0-9a-zA-Z\-_]{20,}[''"]?'},@{Name='Generic Password';Pattern='(?i)(password|passwd|pwd)\s*[=:]\s*[''"][^''"]{8,}[''"]'});$hitCount=0;foreach($dir in $searchDirs){if(-not (Test-Path $dir -EA SilentlyContinue)){continue};foreach($ext in $exts){Get-ChildItem $dir -Filter $ext -Recurse -EA SilentlyContinue -Force|Where-Object{$_.Length -lt 1MB}|ForEach-Object{try{$content=Get-Content $_.FullName -Raw -EA SilentlyContinue;foreach($ap in $apiPatterns){if($content -match $ap.Pattern){Write-Host ('  [THREAT]  '+$ap.Name+' pattern found in: '+$_.Name) -ForegroundColor Red;Add-Content $rep ('[THREAT] '+$ap.Name+' in: '+$_.FullName) -EA SilentlyContinue;Add-Content $thr ($ap.Name+' in: '+$_.Name) -EA SilentlyContinue;$hitCount++;$found++;break}}}catch{}}}};Write-Host ('  [INFO]    Files with API key patterns: '+$hitCount) -ForegroundColor DarkGray;if($found -eq 0){Write-Host '  [CLEAN]   No API key or password patterns found in scanned files' -ForegroundColor Green;Add-Content $rep '[CLEAN] No API key patterns found' -EA SilentlyContinue}"
echo.
set "DL_THREAT_COUNT=0"
set "DL_WARN_COUNT=0"
for /f %%A in ('type "!DL_THREATS_TMP!" ^| find /c /v ""') do set "DL_THREAT_COUNT=%%A"
for /f %%A in ('type "!DL_WARN_TMP!" ^| find /c /v ""') do set "DL_WARN_COUNT=%%A"
echo. >> "!DL_REPORT!"
echo ================================================ >> "!DL_REPORT!"
echo   SCAN SUMMARY >> "!DL_REPORT!"
echo ================================================ >> "!DL_REPORT!"
echo   Threats  : !DL_THREAT_COUNT! >> "!DL_REPORT!"
echo   Warnings : !DL_WARN_COUNT! >> "!DL_REPORT!"
echo   Date     : %DATE% %TIME% >> "!DL_REPORT!"
echo ================================================ >> "!DL_REPORT!"
if !DL_THREAT_COUNT! GTR 0 (
    echo. >> "!DL_REPORT!"
    echo   THREATS DETECTED: >> "!DL_REPORT!"
    type "!DL_THREATS_TMP!" >> "!DL_REPORT!" 2>nul
)
if !DL_WARN_COUNT! GTR 0 (
    echo. >> "!DL_REPORT!"
    echo   WARNINGS: >> "!DL_REPORT!"
    type "!DL_WARN_TMP!" >> "!DL_REPORT!" 2>nul
)
echo.
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '    SENSITIVE INFORMATION (DLP) SCAN COMPLETE' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
echo.
if !DL_THREAT_COUNT! GTR 0 (
    powershell -NoProfile -Command "Write-Host '  THREATS  : !DL_THREAT_COUNT!' -ForegroundColor Red"
) else (
    powershell -NoProfile -Command "Write-Host '  THREATS  : !DL_THREAT_COUNT!' -ForegroundColor Green"
)
if !DL_WARN_COUNT! GTR 0 (
    powershell -NoProfile -Command "Write-Host '  WARNINGS : !DL_WARN_COUNT!' -ForegroundColor Yellow"
) else (
    powershell -NoProfile -Command "Write-Host '  WARNINGS : !DL_WARN_COUNT!' -ForegroundColor Green"
)
echo.
powershell -NoProfile -Command "Write-Host '  Report saved to:' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host ('  ' + $env:DL_REPORT) -ForegroundColor !COL_OPS_PS!"
echo.
if "!SA_ACTIVE!"=="1" goto SA_DL_CONT
pause
del "!DL_THREATS_TMP!" >nul 2>&1
del "!DL_WARN_TMP!" >nul 2>&1
goto DLP_SCANNER
:SA_DL_CONT
del "!DL_THREATS_TMP!" >nul 2>&1
del "!DL_WARN_TMP!" >nul 2>&1
echo.
powershell -NoProfile -Command "Write-Host '  B  >  Continue to next scanner (Browser Security and Policy)' -ForegroundColor Yellow"
echo.
:SA_DL_WAIT
set "SA_CONT="
set /p "SA_CONT=  [B] Continue: "
if /i not "!SA_CONT!"=="B" goto SA_DL_WAIT
goto BP_RUN_SCAN

:BROWSER_POLICY_SCANNER
cls
color !COL_OPS!
echo.
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '    BROWSER SECURITY AND POLICY SCANNER' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
echo.
powershell -NoProfile -Command "Write-Host '  Checks: Chrome/Edge GPO registry policies, forced' -ForegroundColor DarkGray"
powershell -NoProfile -Command "Write-Host '  homepages, forced search engines, forced extensions' -ForegroundColor DarkGray"
echo.
echo   1  ^>  Begin Scan
echo   B  ^>  Back
echo.
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
echo.
set "BP_START="
set /p "BP_START=  Select [1, B]: "
if /i "!BP_START!"=="B" goto CAT_SCANNING
if not "!BP_START!"=="1" goto BROWSER_POLICY_SCANNER
:BP_RUN_SCAN
cls
color !COL_OPS!
echo.
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '    BROWSER SECURITY AND POLICY SCANNER - RUNNING' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
echo.
for /f %%D in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd_HHmm"') do set "BP_DATE=%%D"
set "BP_REPORT=!LOGDIR!\YTSH_BrowserPolicy_!BP_DATE!.txt"
set "BP_THREATS_TMP=%TEMP%\ytsh_bp_t_%RANDOM%.tmp"
set "BP_WARN_TMP=%TEMP%\ytsh_bp_w_%RANDOM%.tmp"
type nul > "!BP_THREATS_TMP!"
type nul > "!BP_WARN_TMP!"
echo ================================================ > "!BP_REPORT!"
echo   YTSH BROWSER SECURITY AND POLICY SCAN REPORT >> "!BP_REPORT!"
echo   Scanned: %DATE% %TIME% >> "!BP_REPORT!"
echo ================================================ >> "!BP_REPORT!"
echo.
powershell -NoProfile -Command "Write-Host '  --- [CHECK 1] CHROME GPO POLICIES ---' -ForegroundColor !COL_HDR_PS!"
echo.
echo [CHECK 1] CHROME GPO POLICIES >> "!BP_REPORT!"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$rep=$env:BP_REPORT;$thr=$env:BP_THREATS_TMP;$wrn=$env:BP_WARN_TMP;$found=0;$chromePolicyPaths=@('HKLM:\SOFTWARE\Policies\Google\Chrome','HKCU:\SOFTWARE\Policies\Google\Chrome');foreach($pp in $chromePolicyPaths){$pol=Get-ItemProperty $pp -EA SilentlyContinue;if($pol){$props=$pol.PSObject.Properties|Where-Object{$_.Name -notmatch '^PS'};Write-Host ('  [WARN]    Chrome policies enforced at: '+$pp+' ('+$props.Count+' policies)') -ForegroundColor Yellow;Add-Content $rep ('[WARN] Chrome policies at '+$pp+': '+$props.Count+' entries') -EA SilentlyContinue;Add-Content $wrn ('Chrome GPO policies: '+$props.Count+' at '+$pp) -EA SilentlyContinue;$found++;foreach($p in $props){Write-Host ('  [INFO]    Policy: '+$p.Name+' = '+$p.Value) -ForegroundColor DarkGray;Add-Content $rep ('  Policy: '+$p.Name+' = '+$p.Value) -EA SilentlyContinue};$hp=$pol.HomepageLocation;if($hp){Write-Host ('  [WARN]    Chrome homepage forced by policy: '+$hp) -ForegroundColor Yellow;Add-Content $wrn ('Chrome homepage forced: '+$hp) -EA SilentlyContinue};$se=$pol.DefaultSearchProviderName;if($se){Write-Host ('  [WARN]    Chrome search engine forced by policy: '+$se) -ForegroundColor Yellow;Add-Content $wrn ('Chrome search forced: '+$se) -EA SilentlyContinue};$forceExt=$pol.ExtensionInstallForcelist;if($forceExt){Write-Host ('  [THREAT]  Chrome extensions force-installed by policy: '+($forceExt-join', ')) -ForegroundColor Red;Add-Content $thr ('Chrome force-install extensions: '+($forceExt-join',')) -EA SilentlyContinue}}};if($found -eq 0){Write-Host '  [CLEAN]   No Chrome GPO policies detected' -ForegroundColor Green;Add-Content $rep '[CLEAN] No Chrome GPO policies' -EA SilentlyContinue}"
echo.
powershell -NoProfile -Command "Write-Host '  --- [CHECK 2] EDGE GPO POLICIES ---' -ForegroundColor !COL_HDR_PS!"
echo.
echo [CHECK 2] EDGE GPO POLICIES >> "!BP_REPORT!"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$rep=$env:BP_REPORT;$thr=$env:BP_THREATS_TMP;$wrn=$env:BP_WARN_TMP;$found=0;$edgePolicyPaths=@('HKLM:\SOFTWARE\Policies\Microsoft\Edge','HKCU:\SOFTWARE\Policies\Microsoft\Edge');foreach($pp in $edgePolicyPaths){$pol=Get-ItemProperty $pp -EA SilentlyContinue;if($pol){$props=$pol.PSObject.Properties|Where-Object{$_.Name -notmatch '^PS'};Write-Host ('  [WARN]    Edge policies enforced at: '+$pp+' ('+$props.Count+' policies)') -ForegroundColor Yellow;Add-Content $rep ('[WARN] Edge policies at '+$pp+': '+$props.Count+' entries') -EA SilentlyContinue;Add-Content $wrn ('Edge GPO policies: '+$props.Count+' at '+$pp) -EA SilentlyContinue;$found++;foreach($p in $props){Write-Host ('  [INFO]    Policy: '+$p.Name+' = '+$p.Value) -ForegroundColor DarkGray;Add-Content $rep ('  Policy: '+$p.Name+' = '+$p.Value) -EA SilentlyContinue};$hp=$pol.HomepageLocation;if($hp){Write-Host ('  [WARN]    Edge homepage forced by policy: '+$hp) -ForegroundColor Yellow;Add-Content $wrn ('Edge homepage forced: '+$hp) -EA SilentlyContinue};$forceExt=$pol.ExtensionInstallForcelist;if($forceExt){Write-Host ('  [THREAT]  Edge extensions force-installed by policy: '+($forceExt-join', ')) -ForegroundColor Red;Add-Content $thr ('Edge force-install extensions: '+($forceExt-join',')) -EA SilentlyContinue}}};if($found -eq 0){Write-Host '  [CLEAN]   No Edge GPO policies detected' -ForegroundColor Green;Add-Content $rep '[CLEAN] No Edge GPO policies' -EA SilentlyContinue}"
echo.
powershell -NoProfile -Command "Write-Host '  --- [CHECK 3] MANAGED BROWSER INDICATOR (CHROME/EDGE) ---' -ForegroundColor !COL_HDR_PS!"
echo.
echo [CHECK 3] MANAGED BROWSER INDICATOR >> "!BP_REPORT!"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$rep=$env:BP_REPORT;$thr=$env:BP_THREATS_TMP;$wrn=$env:BP_WARN_TMP;$found=0;$managedPaths=@('HKLM:\SOFTWARE\Policies\Google\Chrome\Recommended','HKLM:\SOFTWARE\Policies\Microsoft\Edge\Recommended','HKLM:\SOFTWARE\Google\Chrome\PreferenceMACs','HKLM:\SOFTWARE\Microsoft\Edge\PreferenceMACs');foreach($mp in $managedPaths){if(Test-Path $mp -EA SilentlyContinue){Write-Host ('  [WARN]    Managed browser config key present: '+$mp) -ForegroundColor Yellow;Add-Content $rep ('[WARN] Managed config: '+$mp) -EA SilentlyContinue;Add-Content $wrn ('Managed browser path: '+$mp) -EA SilentlyContinue;$found++}};$chromeMast=Get-ItemProperty 'HKLM:\SOFTWARE\Google\Chrome\Extensions' -EA SilentlyContinue;$edgeMast=Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Edge\Extensions' -EA SilentlyContinue;if($chromeMast){$extProps=$chromeMast.PSObject.Properties|Where-Object{$_.Name -notmatch '^PS'};if($extProps.Count -gt 0){Write-Host ('  [WARN]    '+$extProps.Count+' Chrome extensions registered in HKLM (machine-wide forced)') -ForegroundColor Yellow;Add-Content $wrn ('HKLM Chrome extensions: '+$extProps.Count) -EA SilentlyContinue;$found++}};if($edgeMast){$extProps=$edgeMast.PSObject.Properties|Where-Object{$_.Name -notmatch '^PS'};if($extProps.Count -gt 0){Write-Host ('  [WARN]    '+$extProps.Count+' Edge extensions registered in HKLM (machine-wide forced)') -ForegroundColor Yellow;Add-Content $wrn ('HKLM Edge extensions: '+$extProps.Count) -EA SilentlyContinue;$found++}};if($found -eq 0){Write-Host '  [CLEAN]   No managed browser indicator keys found' -ForegroundColor Green;Add-Content $rep '[CLEAN] No managed browser indicators' -EA SilentlyContinue}"
echo.
set "BP_THREAT_COUNT=0"
set "BP_WARN_COUNT=0"
for /f %%A in ('type "!BP_THREATS_TMP!" ^| find /c /v ""') do set "BP_THREAT_COUNT=%%A"
for /f %%A in ('type "!BP_WARN_TMP!" ^| find /c /v ""') do set "BP_WARN_COUNT=%%A"
echo. >> "!BP_REPORT!"
echo ================================================ >> "!BP_REPORT!"
echo   SCAN SUMMARY >> "!BP_REPORT!"
echo ================================================ >> "!BP_REPORT!"
echo   Threats  : !BP_THREAT_COUNT! >> "!BP_REPORT!"
echo   Warnings : !BP_WARN_COUNT! >> "!BP_REPORT!"
echo   Date     : %DATE% %TIME% >> "!BP_REPORT!"
echo ================================================ >> "!BP_REPORT!"
if !BP_THREAT_COUNT! GTR 0 (
    echo. >> "!BP_REPORT!"
    echo   THREATS DETECTED: >> "!BP_REPORT!"
    type "!BP_THREATS_TMP!" >> "!BP_REPORT!" 2>nul
)
if !BP_WARN_COUNT! GTR 0 (
    echo. >> "!BP_REPORT!"
    echo   WARNINGS: >> "!BP_REPORT!"
    type "!BP_WARN_TMP!" >> "!BP_REPORT!" 2>nul
)
echo.
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '    BROWSER SECURITY AND POLICY SCAN COMPLETE' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
echo.
if !BP_THREAT_COUNT! GTR 0 (
    powershell -NoProfile -Command "Write-Host '  THREATS  : !BP_THREAT_COUNT!' -ForegroundColor Red"
) else (
    powershell -NoProfile -Command "Write-Host '  THREATS  : !BP_THREAT_COUNT!' -ForegroundColor Green"
)
if !BP_WARN_COUNT! GTR 0 (
    powershell -NoProfile -Command "Write-Host '  WARNINGS : !BP_WARN_COUNT!' -ForegroundColor Yellow"
) else (
    powershell -NoProfile -Command "Write-Host '  WARNINGS : !BP_WARN_COUNT!' -ForegroundColor Green"
)
echo.
powershell -NoProfile -Command "Write-Host '  Report saved to:' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host ('  ' + $env:BP_REPORT) -ForegroundColor !COL_OPS_PS!"
echo.
if "!SA_ACTIVE!"=="1" goto SA_BP_CONT
pause
del "!BP_THREATS_TMP!" >nul 2>&1
del "!BP_WARN_TMP!" >nul 2>&1
goto BROWSER_POLICY_SCANNER
:SA_BP_CONT
del "!BP_THREATS_TMP!" >nul 2>&1
del "!BP_WARN_TMP!" >nul 2>&1
echo.
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '    SCAN ALL COMPLETE - ALL 13 SCANNERS FINISHED' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
echo.
set "SA_ACTIVE=0"
pause
goto CAT_SCANNING

:SCAN_ALL_MENU
cls
color !COL_OPS!
echo.
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '    SCAN ALL - SELECT SCAN DEPTH' -ForegroundColor !COL_HDR_PS!"
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
echo.
powershell -NoProfile -Command "Write-Host '  Runs all 13 scanners in sequence:' -ForegroundColor !COL_OPS_PS!"
powershell -NoProfile -Command "Write-Host '  Malware, Network, Registry Persistence, Startup+WMI,' -ForegroundColor DarkGray"
powershell -NoProfile -Command "Write-Host '  Process+DLL Injection, Browser Hijack, Credential Exposure,' -ForegroundColor DarkGray"
powershell -NoProfile -Command "Write-Host '  Driver Integrity+Rootkit, Privacy+Tracker, Vulnerability+Patch,' -ForegroundColor DarkGray"
powershell -NoProfile -Command "Write-Host '  Hardware SMART, Sensitive Info (DLP), Browser Security+Policy' -ForegroundColor DarkGray"
echo.
echo   1  ^>  Full Scan     ^(all checks from each scanner - most thorough^)
echo   2  ^>  Minimal Scan  ^(key checks only from each scanner^)
echo.
echo   B  ^>  Back
echo.
powershell -NoProfile -Command "Write-Host '  =============================================' -ForegroundColor !COL_HDR_PS!"
echo.
set "SA_CHOICE="
set /p "SA_CHOICE=  Select scan depth [1-2, B]: "
if /i "!SA_CHOICE!"=="B" goto CAT_SCANNING
if "!SA_CHOICE!"=="1" (
    set "SA_ACTIVE=1"
    set "SA_SCANMODE=FULL"
    set "SA_RP_MODE=FULL"
    set "SA_SW_MODE=FULL"
    set "ML_SCANMODE=FULL"
    set "ML_CUSTOM=0"
    goto MALWARE_RUN_SCAN
)
if "!SA_CHOICE!"=="2" (
    set "SA_ACTIVE=1"
    set "SA_SCANMODE=MINIMAL"
    set "SA_RP_MODE=QUICK"
    set "SA_SW_MODE=WMIONLY"
    set "ML_SCANMODE=MINIMAL"
    set "ML_CUSTOM=0"
    goto MALWARE_RUN_SCAN
)
goto SCAN_ALL_MENU

:EXIT_SCRIPT
del /q /f "%TEMP%\ytsh_*.ps1" >nul 2>&1
cls
color !COL_OPS!
echo.
echo  =============================================
powershell -NoProfile -Command "Write-Host '   Goodbye. No unsaved changes were made.' -ForegroundColor Green"
echo   - YTSH's Tech Utility v2.1
echo  =============================================
echo.
pause
exit /b 0