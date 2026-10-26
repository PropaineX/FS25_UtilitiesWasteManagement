$ErrorActionPreference = 'Stop'
$depotRoot = Split-Path $PSScriptRoot -Parent
$helperRoot = Join-Path (Split-Path $depotRoot -Parent) 'Library/_FS25Knowledge/tools/ge10'
. "$helperRoot/ui.ps1"
$previewProcessId = [int](Get-Content "$depotRoot/previews/depot_editor_pid.txt")
$previewProcess = Get-Process -Id $previewProcessId
$previewHandle = $previewProcess.MainWindowHandle
if ($previewHandle -eq [IntPtr]::Zero) { throw 'Preview editor has no window' }
[void][U]::ShowWindow($previewHandle, 3)
[void][U]::SetForegroundWindow($previewHandle)
Start-Sleep -Seconds 2
function Preview-Console([string]$command) {
    if ([U]::GetForegroundWindow() -ne $previewHandle) { throw 'Preview editor is not foreground' }
    Click 1000 1320
    Send '^a'
    Paste $command
    Send '+{ENTER}'
    Start-Sleep -Seconds 3
}
try {
    $luaPath = ($depotRoot -replace '\\', '/') + '/source/preview_depot_layout.lua'
    Preview-Console ('source("' + $luaPath + '")')
    Preview-Console 'depotLayoutView(false)'
    Start-Sleep -Seconds 3
    & "$helperRoot/mockup/cap.ps1" "$depotRoot/previews/depot_layout_actual_front.png"
    Preview-Console 'depotLayoutView(true)'
    & "$helperRoot/mockup/cap.ps1" "$depotRoot/previews/depot_layout_actual_overhead.png"
} finally {
    [void][U]::ShowWindow($previewHandle, 6)
}
