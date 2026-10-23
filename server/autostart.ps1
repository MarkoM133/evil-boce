# Pokreće Evil Boće server pri prijavi u Windows (Task Scheduler, bez prozora).
#   powershell -ExecutionPolicy Bypass -File server\autostart.ps1            postavi i pokreni
#   powershell -ExecutionPolicy Bypass -File server\autostart.ps1 -Remove    ukloni
param([switch]$Remove)
$ErrorActionPreference = 'Stop'

$TaskName = 'Evil Boce server'
$Repo = Split-Path -Parent $PSScriptRoot

if ($Remove) {
    Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
    "Uklonjeno: $TaskName"
    return
}

# Stari server (i njegov prozor, ako je pokrenut starim načinom) se ugasi, pa ga zadatak digne iznova.
Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
Get-CimInstance Win32_Process -Filter "Name='node.exe'" | Where-Object { $_.CommandLine -like '*server.mjs*' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }

$node = (Get-Command node -ErrorAction Stop).Source
$logDir = Join-Path $PSScriptRoot 'logs'
New-Item -ItemType Directory -Force $logDir | Out-Null
$log = Join-Path $logDir 'server.log'

# Zadatak radi u prijavi korisnika, pa bi cmd.exe otvorio prazan prozor (-Hidden skriva samo zadatak u popisu).
# Zato ga pokreće start-hidden.vbs bez prozora; izlaz servera ide u log.
$arg = "`"$PSScriptRoot\start-hidden.vbs`" `"$node`""
$action = New-ScheduledTaskAction -Execute 'wscript.exe' -Argument $arg -WorkingDirectory $Repo
$user = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
$atLogon = New-ScheduledTaskTrigger -AtLogOn -User $user
# Čuvar: svakih 5 minuta. Ako server radi, nova instanca se ne pokreće (IgnoreNew); ako je stao, digne se.
$watch = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes 5)
$settings = New-ScheduledTaskSettingsSet -Hidden -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
    -ExecutionTimeLimit ([TimeSpan]::Zero) -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1) -MultipleInstances IgnoreNew
Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger @($atLogon, $watch) -Settings $settings `
    -Description 'Evil Boce: web app, karte i deckovi (localhost i Tailscale, port 5100)' -Force | Out-Null
Start-ScheduledTask -TaskName $TaskName
"Postavljeno i pokrenuto: $TaskName (log: $log)"
