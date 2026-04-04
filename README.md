# YTSH-s-Tech-Utility

A Windows batch utility for debloating, optimizing registry settings, managing services, creating restore points, and cleaning up system junk, all from a single admin-run script.

## Features
- Debloat: Remove pre-installed Microsoft and OEM bloatware apps (90+ options)
- Revert: Restore anything the script has changed, individually or all at once
- Gaming & FPS Boost: Hardware-aware optimizations with SAFE / BALANCED / AGGRESSIVE risk labels
- Disk Cleanup: Safe removal of temp files, update cache, prefetch, dumps, and more
- Network Optimizations: DNS switching (Cloudflare, Google, Quad9, OpenDNS), Nagle's algorithm, throttling
- Windows Tweaks: Visual effects, pagefile sizing, Windows Update control, power plans, DNS benchmark
- Security: Firewall check, SMB1 disabler, startup entry scanner, restore point manager, driver check
- System Health Check: Scans your system and reports its optimization status
- Software Installer: Install 19 common apps via winget in one go
- Windows Activation: HWID digital license method
- Export Report: Generate a full machine report including logs, system info, DNS, and installed apps
- Debloat Modes: Default, Newbie, Student, and Gamer modes that filter options based on your use case
- Hardware Detection: Detects OS, CPU, RAM, GPU, disk type (NVMe/SATA SSD/HDD), and form factor (Laptop/Desktop) on launch
- 8 Color Themes: Default, Matrix, Amber, Ocean, Blood, Violet, Arctic, Gold, Midnight

## Requirements
- Windows 10 or Windows 11
- Must be run as Administrator (right-click → Run as administrator)
- PowerShell 5.0 or later (included with Windows 10/11)
- winget (App Installer); required for Software Installer and app restoration. Available from the Microsoft Store if not already installed.

## Usage
- Download the .bat file
- Right-click it and select Run as administrator
- Read the welcome screen before proceeding
- Navigate menus using the keyboard; Type the option label and press Enter

## Before You Start
- Create a manual System Restore Point before making any changes. The script creates one automatically before most operations, but having your own backup is strongly recommended.
- Save all open work before running any debloat or revert operations. The Full Debloat option will automatically restart your PC after completion (this can be disabled in Settings first).
- Read the welcome screen. Pressing D to never show it again is not recommended if you are new to Windows tweaking.
- This script makes real, system-level changes. While a full revert system is included, no tool can guarantee 100% reversibility on every hardware and OEM configuration.

## Specific Options With Real Risk
- Disabling WSearch (option 61) will break Start Menu search indexing. Searches will still work but will be noticeably slower with no index to rely on.
- Disabling SysMain / Superfetch (option 90) on an HDD will slow down app launch times. This option is safe and beneficial on SSDs. The script will warn you based on your detected disk type.
- High Performance Power Plan and disabling Power Throttling on a laptop can cause overheating and significant battery drain. The script detects your form factor and warns you before these options.
- Removing Mail and Calendar may affect the taskbar calendar flyout, this is a cosmetic issue only and does not affect system stability.
- Some removed AppX packages may silently reinstall via Windows Update. This is a Windows behavior outside the script's control.
- OEM stubs (options 40–48) are only removed if present on your machine. A silent skip occurs if they are not found; no errors will appear.

## Revert Limitations
- App restoration via the Revert menu requires winget. If winget is unavailable, apps must be reinstalled manually from the Microsoft Store.
- Removed provisioned AppX packages are harder to fully restore than regular installs. Winget restoration attempts are best-effort.
- Some service changes require a restart to fully take effect.

## Specific Features
- Windows Activation uses the HWID digital license method via massgrave.dev. This ties a license to your hardware and is considered legitimate for users who legally own a Windows license. Understand what this does before running it.
- The pagefile tweak uses wmic, which is deprecated on Windows 11 24H2 and newer. It may silently fail on the latest Windows builds without producing an error.
- DNS changes apply to all active network adapters simultaneously.
- Full Debloat auto-restarts the PC after a 15-second countdown by default. Disable Auto-Restart in Settings (S) before running if you want to stay in control of when you reboot.

## Windows Version Notes
This tool was developed and tested primarily on Windows 11. Windows 10 support is included, but some AppX package names differ between versions and certain options may silently skip if a package does not exist on your version.

## Risk Label System
Every option in the script is labeled with one of three risk levels:
- GREEN: [SAFE] - No meaningful downside. Recommended for all users.
- YELLOW: [BALANCED] - Minor tradeoffs worth being aware of. Read the description.
- RED: [AGGRESSIVE] - Hardware-dependent or potentially impactful. Shown in red on laptops where relevant.

## License & Copyright
© YTSH. All Rights Reserved.

This script is provided for personal use only. You are welcome to read the source code and learn from it.

Copying, forking, redistributing, reselling, or repackaging this script; in whole or in part; is strictly prohibited without explicit written permission from the author. Violations will be subject to legal action under applicable copyright law.

This is not open source. All rights are reserved by the original author.

## Disclaimer
This tool modifies Windows system settings, registry keys, services, and installed packages. While every effort has been made to ensure safety and reversibility, the author takes no responsibility for data loss, system instability, or any other damage resulting from the use of this tool. Use at your own risk. Always have a backup before making system-level changes.

This script is not perfect. Some operations may report [SUCCESS] even when the underlying change had no effect; for example, if a registry key already existed, a service was already disabled, or an AppX package was already absent. Conversely, some failures may be silently swallowed rather than surfaced as errors, particularly when removing OEM stubs or provisioned packages that behave differently across manufacturers. A [SUCCESS] message means the command executed without throwing an error. It does not always guarantee the intended system change was actually applied. If you are unsure whether a change took effect, use the Status report (option 9) or the Export Report feature (R) to verify the current state of your system.

## Work In Progress

YTSH's Tech Utility is still actively developed. While v1.0 is stable and ready for daily use, new features, fixes, and improvements are continuously being worked on.

All feedback is genuinely welcome — whether it's a bug report, a silent failure you noticed, a feature request, a new debloat option, or a suggestion for a new menu entirely. If you tested it on an unusual hardware setup or a specific OEM machine and something didn't work as expected, that information is valuable.

Feel free to open an Issue on GitHub to report bugs or suggest features. This tool was built for the community and your input directly shapes what gets added next.

## YTSH's Tech Utility v1.0
