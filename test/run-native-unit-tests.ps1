param([string]$BuildDirectory = '')

$ErrorActionPreference = 'Stop'
if (-not $BuildDirectory) { $BuildDirectory = Join-Path $PSScriptRoot '../build/windows/x64' }
$buildRoot = (Resolve-Path -LiteralPath $BuildDirectory).Path
$cache = Get-Content -LiteralPath (Join-Path $buildRoot 'CMakeCache.txt')
$command = @($cache | Where-Object { $_.StartsWith('CMAKE_COMMAND:INTERNAL=') })
if ($command.Count -ne 1) { throw 'Build Windows before running native unit tests' }
$cmake = $command[0].Substring('CMAKE_COMMAND:INTERNAL='.Length)
& $cmake --build $buildRoot --config Release --target desktop_window_focus_test desktop_window_focus_baseline window_layout_test window_layout_baseline companion_window_test virtual_file_data_test secret_fill_test desktop_notice_layout_test desktop_notice_surface_test desktop_notice_lifecycle_test project_process_arguments_test project_process_test
if ($LASTEXITCODE -ne 0) { throw 'Native unit build failed' }

$previousPath = $env:PATH
try {
    $runtime = Join-Path $buildRoot 'runner/Release'
    $env:PATH = "$runtime;$env:PATH"
    & (Join-Path $runtime 'desktop_notice_lifecycle_test.exe')
    if ($LASTEXITCODE -ne 0) { throw 'Notification engine teardown check failed' }
    & (Join-Path $runtime 'project_process_test.exe')
    if ($LASTEXITCODE -ne 0) { throw 'Project process lifecycle checks failed' }
    & (Join-Path $runtime 'project_process_arguments_test.exe')
    if ($LASTEXITCODE -ne 0) { throw 'Project process argument checks failed' }
    & (Join-Path $runtime 'desktop_notice_layout_test.exe')
    if ($LASTEXITCODE -ne 0) { throw 'Desktop notification placement checks failed' }
    & (Join-Path $runtime 'desktop_notice_surface_test.exe')
    if ($LASTEXITCODE -ne 0) { throw 'Desktop notification border checks failed' }
    & (Join-Path $runtime 'secret_fill_test.exe')
    if ($LASTEXITCODE -ne 0) { throw 'Secret fill unit checks failed' }
    & (Join-Path $runtime 'virtual_file_data_test.exe')
    if ($LASTEXITCODE -ne 0) { throw 'Virtual file transfer unit checks failed' }
    & (Join-Path $runtime 'companion_window_test.exe')
    if ($LASTEXITCODE -ne 0) { throw 'Companion movement regression failed' }
    $baseline = Join-Path $buildRoot 'Release/desktop_window_focus_baseline.exe'
    & $baseline
    if ($LASTEXITCODE -ne 1) { throw 'Original hidden-window focus failure was not reproduced' }
    & $baseline --activation
    if ($LASTEXITCODE -ne 2) { throw 'Original inactive-window focus failure was not reproduced' }
    $fixed = Join-Path $buildRoot 'Release/desktop_window_focus_test.exe'
    & $fixed
    if ($LASTEXITCODE -ne 0) { throw 'Native focus regression failed' }
    & $fixed --activation
    if ($LASTEXITCODE -ne 0) { throw 'Native activation regression failed' }
    foreach ($mode in @('', '--frame', '--topmost')) {
        $layoutBaseline = Join-Path $buildRoot 'Release/window_layout_baseline.exe'
        & $layoutBaseline $mode
        if ($LASTEXITCODE -ne 1) { throw 'Original layout activation failure was not reproduced' }
        $layoutFixed = Join-Path $buildRoot 'Release/window_layout_test.exe'
        & $layoutFixed $mode
        if ($LASTEXITCODE -ne 0) { throw 'Window layout focus regression failed' }
    }
    & (Join-Path $buildRoot 'Release/window_layout_test.exe') --close
    if ($LASTEXITCODE -ne 0) { throw 'Companion close must not quit the application message loop' }
    & (Join-Path $buildRoot 'Release/window_layout_test.exe') --inactive
    if ($LASTEXITCODE -ne 0) { throw 'Inactive show must preserve foreground' }
} finally {
    $env:PATH = $previousPath
}
