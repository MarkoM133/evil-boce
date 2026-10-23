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

$node = (Get-Command node -ErrorAction Stop).Source
$logDir = Join-Path $PSScriptRoot 'logs'
New-Item -ItemType Directory -Force $logDir | Out-Null
$log = Join-Path $logDir 'server.log'

# cmd preusmjeri izlaz servera u log; prozor skriva sam Task Scheduler (Hidden).
$arg = "/c `"`"$node`" `"$Repo\server\server.mjs`" >> `"$log`" 2>&1`""
$action = New-ScheduledTaskAction -Execute 'cmd.exe' -Argument $arg -WorkingDirectory $Repo
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
