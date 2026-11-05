param(
 [ValidateSet('Install','Check','PrepareRoot','ConnectWifi')][string]$Action='Install',
 [string]$Device='', [string]$Adb='', [string]$WifiIp='',
 [switch]$AcceptSdkLicense,[switch]$NonInteractive,[switch]$EnableWirelessAdb
)
$ErrorActionPreference='Stop'
$homeDir=$PSScriptRoot
if(Test-Path -LiteralPath (Join-Path $PSScriptRoot '..\standalone\install.ps1')){$homeDir=Split-Path -Parent $PSScriptRoot}
if(Test-Path -LiteralPath (Join-Path $homeDir 'installer-lib.ps1')){. (Join-Path $homeDir 'installer-lib.ps1')}
else{. (Join-Path $homeDir 'installer\installer-lib.ps1')}
try {
 $adbPath=Resolve-Adb $homeDir $Adb -AcceptSdkLicense:$AcceptSdkLicense -NonInteractive:$NonInteractive
 $serial=Resolve-Device $adbPath $Device
 $report=Get-DeviceReport $adbPath $serial
 $reportPath=Save-DeviceReport $homeDir $report
 Write-Host ($report.model+' / '+$report.build+' / Root='+$report.root)
 Write-Host ('Report: '+$reportPath)
 if($Action -eq 'Check'){exit 0}
 if($Action -eq 'ConnectWifi'){
  if(-not $EnableWirelessAdb){throw 'USE_ENABLEWIRELESSADB_TO_EXPOSE_ADB_ON_TRUSTED_LAN'}
  $ip=[Net.IPAddress]::Parse($WifiIp);$b=$ip.GetAddressBytes()
  if($b.Length -ne 4 -or -not($b[0] -eq 10 -or ($b[0] -eq 192 -and $b[1] -eq 168) -or ($b[0] -eq 172 -and $b[1] -ge 16 -and $b[1] -le 31))){throw 'PRIVATE_IPV4_REQUIRED'}
  $null=Invoke-Adb -Adb $adbPath -Arguments @('-s',$serial,'tcpip','5555')
  $r=Invoke-Adb -Adb $adbPath -Arguments @('connect',($WifiIp+':5555'));Write-Host $r.Text
  Write-Host 'Trusted LAN only. Disable with: adb -s DEVICE usb'
  exit 0
 }
 Assert-SupportedDevice $report
 if(-not $report.root){
  $m=Get-ResourceManifest $homeDir;$apk=Join-Path $homeDir $m.magisk.file
  $null=Get-VerifiedDownload $m.magisk.url $apk $m.magisk.sha256
  $installed=Invoke-Adb -Adb $adbPath -Arguments @('-s',$serial,'shell','pm','path','com.topjohnwu.magisk') -AllowFailure
  if($installed.Text -match 'package:'){Write-Host 'Existing Magisk app retained.'}
  else{$r=Invoke-Adb -Adb $adbPath -Arguments @('-s',$serial,'install','-r',$apk);Write-Host $r.Text}
  Write-Host 'Magisk app prepared. APK installation alone does not grant Root.'
  Write-Host 'Use the current device firmware image and the official procedure: https://topjohnwu.github.io/Magisk/install.html'
  Write-Host 'No bootloader unlock, partition flash, data wipe or device reboot was performed.'
  exit 30
 }
 if($Action -eq 'PrepareRoot'){Write-Host 'Existing Root retained; Magisk framework not upgraded.';exit 0}
 $install=Join-Path $homeDir 'install.ps1';if(-not(Test-Path -LiteralPath $install)){$install=Join-Path $homeDir 'standalone\install.ps1'}
 & $install -Device $serial -Adb $adbPath
 Write-Host 'https://192.168.0.1:9088/  |  Initial PIN: 2007'
 Write-Host 'Existing proxy/autostart state retained. No automatic proxy enable.'
 exit 0
} catch { Write-Error $_;exit 1 }
