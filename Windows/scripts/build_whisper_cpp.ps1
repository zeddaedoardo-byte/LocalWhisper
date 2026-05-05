param(
    [ValidateSet("cpu", "cuda", "vulkan", "openvino")]
    [string]$Backend = "cpu",
    [string]$InstallDir = "$env:LOCALAPPDATA\LocalWhisper\bin"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$WindowsRoot = Resolve-Path (Join-Path $ScriptDir "..")
$ExternalDir = Join-Path $WindowsRoot "external"
$WhisperRoot = Join-Path $ExternalDir "whisper.cpp"
$BuildDir = Join-Path $WhisperRoot "build-$Backend"

if (!(Test-Path $WhisperRoot)) {
    New-Item -ItemType Directory -Force -Path $ExternalDir | Out-Null
    git clone https://github.com/ggml-org/whisper.cpp.git $WhisperRoot
}

$cmakeArgs = @(
    "-S", $WhisperRoot,
    "-B", $BuildDir,
    "-G", "Visual Studio 17 2022",
    "-A", "x64",
    "-DBUILD_SHARED_LIBS=OFF",
    "-DWHISPER_BUILD_TESTS=OFF"
)

switch ($Backend) {
    "cuda" {
        $cmakeArgs += "-DGGML_CUDA=ON"
    }
    "vulkan" {
        $cmakeArgs += "-DGGML_VULKAN=ON"
    }
    "openvino" {
        $cmakeArgs += "-DGGML_OPENVINO=ON"
    }
}

cmake @cmakeArgs
cmake --build $BuildDir --config Release --target whisper-cli whisper-server

New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null

$candidateDirs = @(
    (Join-Path $BuildDir "bin\Release"),
    (Join-Path $BuildDir "bin"),
    (Join-Path $BuildDir "examples\cli\Release"),
    (Join-Path $BuildDir "examples\server\Release")
)

$cli = $candidateDirs | ForEach-Object { Join-Path $_ "whisper-cli.exe" } | Where-Object { Test-Path $_ } | Select-Object -First 1
$server = $candidateDirs | ForEach-Object { Join-Path $_ "whisper-server.exe" } | Where-Object { Test-Path $_ } | Select-Object -First 1

if (!$cli) {
    throw "whisper-cli.exe was not produced by the build."
}

if (!$server) {
    throw "whisper-server.exe was not produced by the build."
}

Copy-Item $cli (Join-Path $InstallDir "whisper-cli.exe") -Force
Copy-Item $server (Join-Path $InstallDir "whisper-server.exe") -Force

Write-Host "Installed whisper.cpp binaries to $InstallDir"
