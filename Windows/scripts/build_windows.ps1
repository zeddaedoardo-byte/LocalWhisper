param(
    [string]$Configuration = "Release",
    [string]$Runtime = "win-x64"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$WindowsRoot = Resolve-Path (Join-Path $ScriptDir "..")
$Project = Join-Path $WindowsRoot "LocalWhisper.Windows\LocalWhisper.Windows.csproj"
$Output = Join-Path $WindowsRoot "artifacts\LocalWhisper-$Runtime"

dotnet restore $Project
dotnet publish $Project `
    --configuration $Configuration `
    --runtime $Runtime `
    --self-contained true `
    -p:PublishSingleFile=false `
    -p:PublishReadyToRun=true `
    --output $Output

Write-Host "Published LocalWhisper to $Output"
