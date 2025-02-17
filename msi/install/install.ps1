﻿Set-StrictMode -Version 3

. "$PSScriptRoot\_common.ps1"

$distroname = $InstallConfig.distroname
$wsl_import_to = Join-Path -Path $InstallConfig.local_base -ChildPath "wsl"
$wsl_import_from = (Resolve-Path -Path "$PSScriptRoot\..\image.tar").Path

$TempDir = Join-Path $env:LOCALAPPDATA -ChildPath "Temp"
$LogFilePath = Join-Path $TempDir -ChildPath "dockerinwsl-install.log"
$ErrFilePath = Join-Path $TempDir -ChildPath "dockerinwsl-install.$((Get-Date).Ticks).err.log"
$OutFilePath = Join-Path $TempDir -ChildPath "dockerinwsl-install.$((Get-Date).Ticks).out.log"

"`n--- $(Get-Date)`n" | Out-File -FilePath $LogFilePath -Append

Start-Transcript -Path $LogFilePath -Append

try {
    if (-not (Test-Command wsl)) {
        throw "No WSL installed. Please install Microsoft-Windows-Subsystem-Linux (version 2)."
    }

    $wslList = wsl --list
    if (!$wslList) {
        throw "Failed to execute wsl command (error: $LASTEXITCODE)."
    }
    # Hotfix for https://github.com/microsoft/WSL/issues/7767
    $wslList = (($wslList -join ' ').ToCharArray() | % {$result = ""} { $result += ($_ | Where-Object { $_ -imatch "[ a-z_]" }) } { $result })

    New-Item -ItemType Directory -Force -Path $wsl_import_to

    if ($wslList -match $distroname) {
        Write-Warning "WSL distro '$distroname' already installed. Updating ..."

        & wsl "--shutdown" "$distroname"
        if($LASTEXITCODE -ne 0){
            throw "Unable to shutdown WSL distro '$distroname'!"
        }
        Write-Host "WSL distro stopped"

        Push-Location $InstallConfig.local_base
        & wsl -d "$distroname" tar -czpf backup.tar.gz /var/lib/docker
        if($LASTEXITCODE -ne 0){
            throw "Backup of existing WSL distro '$distroname' failed!"
        }
        Write-Host "WSL distro backup done"
        Pop-Location

        & wsl "--unregister" "$distroname"
        if($LASTEXITCODE -ne 0){
            throw "Unable to remove existing WSL distro '$distroname'"
        } else {
            Write-Host "WSL distro deleted"
        }
    }

    Write-Host "Importing WSL distro '$distroname' from '$wsl_import_from' to '$wsl_import_to' ..."
    $p1 = Start-Process -FilePath "wsl" -ArgumentList @("--import", """$distroname""", """$wsl_import_to""", """$wsl_import_from""", "--version", "2") `
                        -NoNewWindow -PassThru -Wait -RedirectStandardError $ErrFilePath -RedirectStandardOutput $OutFilePath
    if($p1.ExitCode -ne 0){
        throw "Unable to import WSL distro from '$wsl_import_from' to '$wsl_import_to'"
    }
    Write-Host "WSL Distro '$distroname' imported"

    if (Test-Path ( Join-Path -Path $InstallConfig.local_base -ChildPath "backup.tar.gz" )) {
        Write-Host "Existing Docker backup found! Restoring ..."
        Push-Location $InstallConfig.local_base
        & wsl -d "$distroname" 'BACKUPDIR=$(pwd);' cd / '&&' tar -xpzf '$BACKUPDIR/backup.tar.gz' -C /
        if($LASTEXITCODE -ne 0){
            Write-Warning "Restore Docker on WSL distro '$distroname' failed! Please inspect the backup-file at $($InstallConfig.local_base)\backup.tar.gz and apply it manually to /var/lib/docker inside WSL"
        }
        Pop-Location
        Write-Host "Docker restored"
    }

    . "$PSScriptRoot\..\scripts\docker-wsl.ps1" -Command "start" -NoTranscript
} finally {
    Stop-Transcript
}