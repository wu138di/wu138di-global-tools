param([string]$Device='',[string]$Adb='',[switch]$AcceptSdkLicense,[switch]$NonInteractive)
$ErrorActionPreference='Stop'
$here=$PSScriptRoot
$lib=Join-Path $here 'installer-lib.ps1'
if(-not(Test-Path -LiteralPath $lib)){$lib=Join-Path (Split-Path -Parent $here) 'installer\installer-lib.ps1'}
. $lib
$Adb=Resolve-Adb $here $Adb -AcceptSdkLicense:$AcceptSdkLicense -NonInteractive:$NonInteractive
$Device=Resolve-Device $Adb $Device
function Run-Adb([string[]]$Arguments) {
 & $Adb @Arguments
 if($LASTEXITCODE -ne 0){throw "ADB failed (exit $LASTEXITCODE)"}
}
if($Device -match '^[0-9.]+:[0-9]+$'){Run-Adb -Arguments @('connect',$Device)}
Run-Adb -Arguments @('-s',$Device,'get-state')
$root=& $Adb -s $Device shell -T "su -c 'id -u'"
if($LASTEXITCODE -ne 0 -or ($root -join '').Trim() -ne '0'){throw 'Root required.'}
$stage='/data/local/tmp/wu-global-transfer-'+(Get-Date -Format 'yyyyMMddTHHmmss')+'-'+$PID
Run-Adb -Arguments @('-s',$Device,'shell','mkdir','-p',$stage)
foreach($name in @('global-manager-arm64','manager.sh','install-device.sh','root-env.sh','DEVICE-SHA256SUMS.txt')){
 if(-not(Test-Path -LiteralPath (Join-Path $here $name))){throw "Package incomplete: $name"}
 Run-Adb -Arguments @('-s',$Device,'push',(Join-Path $here $name),"$stage/$name")
}
Run-Adb -Arguments @('-s',$Device,'shell','-T',"su -c '/system/bin/sh $stage/install-device.sh $stage'")
Write-Host 'Manager: https://192.168.0.1:9088' -ForegroundColor Green
Write-Host 'Proxy state unchanged. Manager/proxy autostart not enabled by this installer.'
