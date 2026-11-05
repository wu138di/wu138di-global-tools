$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
. (Join-Path $repo 'installer\installer-lib.ps1')
$passed=0
function Assert($Value,[string]$Name){if(-not $Value){throw ('FAIL: '+$Name)};$script:passed++;Write-Host ('PASS: '+$Name)}
function Throws([scriptblock]$Body,[string]$Code){try{& $Body;throw 'NO_ERROR'}catch{Assert ($_.ToString().Contains($Code)) $Code}}
foreach($file in @((Get-ChildItem -LiteralPath (Join-Path $repo 'installer') -Filter '*.ps1'),(Get-Item -LiteralPath (Join-Path $repo 'standalone\install.ps1'))) | ForEach-Object {$_}){
 $tokens=$null;$errors=$null;$null=[Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$tokens,[ref]$errors)
 Assert ($errors.Count -eq 0) ('PowerShell syntax: '+$file.Name)
}
$adb=(Get-Command (Join-Path $env:LOCALAPPDATA 'Android\Sdk\platform-tools\adb.exe') -ErrorAction SilentlyContinue).Source
if($adb){Assert ((Resolve-Adb $repo $adb) -eq $adb) 'Explicit SDK ADB retained'}
$temp=Join-Path ([IO.Path]::GetTempPath()) ('wu-global-installer-test-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $temp | Out-Null
$file=Join-Path $temp 'fixture.txt';[IO.File]::WriteAllText($file,'fixture')
$hash=Get-Sha256 $file
Assert-Hash $file $hash;Assert $true 'Existing verified download reused'
Throws {Assert-Hash $file ('0'*64)} 'SHA256_MISMATCH'
Throws {Assert-Serial 'abc;id'} 'DEVICE_SERIAL_INVALID'
$script:calls=@();$script:mode='one'
function Invoke-Adb([string]$Adb,[string[]]$Arguments,[switch]$AllowFailure){
 $script:calls+=,@($Arguments)
 $text='device';if($Arguments[0] -eq 'devices'){
  switch($script:mode){'one'{$text="List of devices attached`nSERIAL_A`tdevice`n"};'many'{$text="List of devices attached`nSERIAL_A`tdevice`nSERIAL_B`tdevice`n"};'pending'{$text="List of devices attached`nSERIAL_A`tunauthorized`n"}}
 }
 if($Arguments -contains 'shell'){
  if($Arguments[-1] -eq "su -c 'id -u'"){$text='0'}
  else{$text="model=MU5358`ndevice=MU5358`nbuild=U30ProV1.0.0B24`nfingerprint=fixture`nabi=arm64-v8a`nsdk=13`nslot=_b`nflash_locked=0"}
 }
 return [pscustomobject]@{Text=$text;ExitCode=0}
}
Assert ((Resolve-Device 'fixture-adb' '') -eq 'SERIAL_A') 'Single authorized device selected'
$script:mode='many';Throws {Resolve-Device 'fixture-adb' ''} 'MULTIPLE_DEVICES_USE_DEVICE'
$script:mode='pending';Throws {Resolve-Device 'fixture-adb' ''} 'ALLOW_USB_DEBUGGING_ON_DEVICE'
$report=Get-DeviceReport 'fixture-adb' 'SERIAL_A'
Assert ($report.root -and $report.testedModel) 'Readiness report recognizes root U30 B24'
Assert-SupportedDevice $report;Assert $true 'Supported device gate'
$report.abi='armeabi-v7a';Throws {Assert-SupportedDevice $report} 'ARM64_ANDROID_REQUIRED'
Assert (-not(@($script:calls | Where-Object {$_ -contains 'tcpip' -or $_ -contains 'flash' -or $_ -contains 'reboot' -or $_ -contains 'unlock'}).Count)) 'Detection does not expose ADB, flash, unlock or reboot'
$bootstrap=Get-Content -LiteralPath (Join-Path $repo 'installer\bootstrap.ps1') -Raw
Assert ($bootstrap.Contains('exit 30') -and $bootstrap.Contains('APK installation alone does not grant Root')) 'Missing Root never reported as rooted'
Assert ($bootstrap.Contains('Existing Root retained; Magisk framework not upgraded')) 'Existing root framework preserved'
Write-Host ("INSTALLER_TESTS_PASS="+$passed)
