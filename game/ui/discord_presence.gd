class_name DiscordPresence
extends RefCounted
## Discord Rich Presence (review item 32, Marko 2026-11-11): what friends see on Discord as "Playing Evil Boće":
## in the menu, or the match (mode, against whom: the bot, local, online, a replay) with the turn and the stages.
## Godot cannot open Discord's named pipe, so a small PowerShell helper (Windows has it) connects to the pipe and
## takes the activities as JSON lines on its stdin; without Discord running it just ends. Off in Settings
## (Discord status), and never in tests or recordings (GameSettings.in_memory) or headless runs.

const APP_ID: String = "1570190016020357150"

## The helper: connect to discord-ipc-0..9, handshake with the app id, then each stdin line is one frame.
## Discord's answers are read without waiting for them (code review 2026-11-13): the helper used to stand in a
## read after every frame, and with a Discord that did not answer it stopped taking its stdin, which in the end
## blocks the game's own write. Its pipe is opened for overlapped use so a read under way never holds a write.
const HELPER: String = """$ErrorActionPreference = 'Stop'
[Console]::InputEncoding = [Text.Encoding]::UTF8
$pipe = $null
for ($i = 0; $i -lt 10; $i++) {
  try { $p = New-Object System.IO.Pipes.NamedPipeClientStream('.', "discord-ipc-$i", [System.IO.Pipes.PipeDirection]::InOut, [System.IO.Pipes.PipeOptions]::Asynchronous); $p.Connect(300); $pipe = $p; break } catch {}
}
if (-not $pipe) { exit }
$buf = New-Object byte[] 65536
function Send($op, $json) {
  $b = [Text.Encoding]::UTF8.GetBytes($json)
  $h = [BitConverter]::GetBytes([int]$op) + [BitConverter]::GetBytes([int]$b.Length)
  $pipe.Write($h, 0, 8); $pipe.Write($b, 0, $b.Length); $pipe.Flush()
}
try {
  Send 0 '{"v":1,"client_id":"%s"}'
  $read = $pipe.ReadAsync($buf, 0, $buf.Length)
  if (-not $read.Wait(5000)) { throw 'no answer' }
  while (($line = [Console]::In.ReadLine()) -ne $null) {
    if ($read.IsCompleted) { if ($read.Result -le 0) { throw 'closed' }; $read = $pipe.ReadAsync($buf, 0, $buf.Length) }
    Send 1 $line
  }
} catch {}
$pipe.Dispose()
"""

## After the helper ended by itself (no Discord, or Discord closed) it is not started again for this long: without
## Discord every new status, one a turn, started a PowerShell that looked for it for three seconds.
const RETRY_MSEC: int = 60000

static var _io: FileAccess
static var _pid: int = 0
static var _last: String = ""
static var _nonce: int = 0
static var _retry_at: int = 0
static var _menu_shown: bool = false
## What the game last asked to show, so switching the setting back on shows it again.
static var _wanted: Array = ["In the menu", "", 0]


## Whether presence may run here at all.
static func enabled() -> bool:
	return GameSettings.discord() and OS.get_name() == "Windows" and not GameSettings.in_memory \
		and DisplayServer.get_name() != "headless"


## "In the menu", once when the game starts (the main menu's settings pass) and whenever a match is left.
static func menu(first_only: bool = false) -> void:
	if first_only and _menu_shown:
		return
	_menu_shown = true
	show("In the menu")


## Shows `details` (top line) and `state` (second line) with the logo; `since` (unix seconds) shows the time
## played. The same text again sends nothing.
static func show(details: String, state: String = "", since: int = 0) -> void:
	_wanted = [details, state, since]
	if not enabled():
		stop()
		return
	var activity: Dictionary = {"details": _fit(details), "assets": {"large_image": "logo", "large_text": "Evil Boće"}}
	if not state.is_empty():
		activity["state"] = _fit(state)
	if since > 0:
		activity["timestamps"] = {"start": since}
	var key: String = JSON.stringify(activity)
	if key == _last:
		return
	if not _start():
		# Not sent: the same text is tried again once the helper may start.
		_last = ""
		return
	_last = key
	_nonce += 1
	_io.store_line(JSON.stringify({"cmd": "SET_ACTIVITY", "args": {"pid": OS.get_process_id(), "activity": activity}, "nonce": str(_nonce)}))
	_io.flush()


## Shows again what the game last asked for (the setting switched back on).
static func refresh() -> void:
	_last = ""
	show(str(_wanted[0]), str(_wanted[1]), JsonUtil.as_int(_wanted[2]))


## The helper goes and Discord drops the status (it does when its pipe closes).
static func stop() -> void:
	if _pid > 0:
		OS.kill(_pid)
	_pid = 0
	_io = null
	_last = ""
	_retry_at = 0


static func _start() -> bool:
	if _io != null and _pid > 0 and OS.is_process_running(_pid):
		return true
	var now: int = Time.get_ticks_msec()
	if _pid > 0:
		# It was running and is gone.
		_pid = 0
		_io = null
		_retry_at = now + RETRY_MSEC
	if now < _retry_at:
		return false
	var script: String = HELPER % APP_ID
	var encoded: String = Marshalls.raw_to_base64(script.to_utf16_buffer())
	var run: Dictionary = OS.execute_with_pipe("powershell.exe",
		PackedStringArray(["-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-WindowStyle", "Hidden", "-EncodedCommand", encoded]), false)
	if run.is_empty():
		return false
	_io = run.get("stdio", null)
	_pid = JsonUtil.as_int(run.get("pid", 0))
	return _io != null


## Discord wants 2 to 128 characters.
static func _fit(s: String) -> String:
	var t: String = s.strip_edges()
	if t.length() < 2:
		t += "  "
	return t.substr(0, 128)
