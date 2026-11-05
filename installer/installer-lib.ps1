$ErrorActionPreference='Stop'
function Get-ResourceManifest([string]$AppHome) {
 $file=Join-Path $AppHome 'resources.json'
 if(-not(Test-Path -LiteralPath $file)){$file=Join-Path $AppHome 'installer\resources.json'}
 return (Get-Content -LiteralPath $file -Raw -Encoding UTF8 | ConvertFrom-Json)
}
function Get-Sha256([string]$Path) {
 $stream=[IO.File]::OpenRead($Path);$hash=[Security.Cryptography.SHA256]::Create()
 try{return ([BitConverter]::ToString($hash.ComputeHash($stream))).Replace('-','').ToLowerInvariant()}
 finally{$stream.Dispose();$hash.Dispose()}
}
function Assert-Hash([string]$Path,[string]$Expected) {
 if(-not(Test-Path -LiteralPath $Path -PathType Leaf)){throw "FILE_MISSING: $Path"}
 if((Get-Sha256 $Path) -ne $Expected.ToLowerInvariant()){throw 'SHA256_MISMATCH'}
}
function Get-VerifiedDownload([string]$Url,[string]$Path,[string]$Hash) {
 if(Test-Path -LiteralPath $Path){Assert-Hash $Path $Hash;return $Path}
 if(([uri]$Url).Scheme -ne 'https'){throw 'HTTPS_REQUIRED'}
 $parent=Split-Path -Parent $Path;New-Item -ItemType Directory -Path $parent -Force | Out-Null
 $part=$Path+'.part'
 [Net.ServicePointManager]::SecurityProtocol=[Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
 Invoke-WebRequest -Uri $Url -OutFile $part -UseBasicParsing
 Assert-Hash $part $Hash
 Move-Item -LiteralPath $part -Destination $Path
 return $Path
}
function Resolve-Adb([string]$AppHome,[string]$Given,[switch]$AcceptSdkLicense,[switch]$NonInteractive) {
 if($Given){$c=Get-Command $Given -ErrorAction SilentlyContinue;if(-not $c){throw 'ADB_PATH_INVALID'};return $c.Source}
 $c=Get-Command 'adb.exe' -ErrorAction SilentlyContinue;if($c){return $c.Source}
 $cache=Join-Path $env:LOCALAPPDATA 'wu138di-global-tools\platform-tools'
 $candidates=@((Join-Path $AppHome 'tools\platform-tools\adb.exe'),(Join-Path $env:LOCALAPPDATA 'Android\Sdk\platform-tools\adb.exe'),(Join-Path $cache 'adb.exe'))
 if($env:ANDROID_HOME){$candidates+=Join-Path $env:ANDROID_HOME 'platform-tools\adb.exe'}
 foreach($p in $candidates){if(Test-Path -LiteralPath $p -PathType Leaf){return $p}}
 $m=Get-ResourceManifest $AppHome
 if(-not $AcceptSdkLicense){
  if($NonInteractive){throw 'ADB_MISSING_ACCEPT_SDK_LICENSE_OR_PASS_ADB'}
  Write-Host ('Android Platform-Tools license: '+$m.platformTools.license)
  if((Read-Host 'Read and accept the SDK license to download? Type YES') -cne 'YES'){throw 'SDK_DOWNLOAD_CANCELLED'}
 }
 $zip=Join-Path $env:LOCALAPPDATA ('wu138di-global-tools\downloads\platform-tools-'+$m.platformTools.version+'.zip')
 $null=Get-VerifiedDownload $m.platformTools.url $zip $m.platformTools.sha256
 $target=Split-Path -Parent $cache
 # The signed-in user's local tool cache only; no driver or system PATH change.
 Expand-Archive -LiteralPath $zip -DestinationPath $target -Force
 $adb=Join-Path $cache 'adb.exe';if(-not(Test-Path -LiteralPath $adb)){throw 'ADB_ARCHIVE_INVALID'}
 return $adb
}
function Invoke-Adb([string]$Adb,[string[]]$Arguments,[switch]$AllowFailure) {
 $lines=@(& $Adb @Arguments 2>&1 | ForEach-Object {"$_"});$code=$LASTEXITCODE
 if($code -ne 0 -and -not $AllowFailure){throw "ADB_EXIT_$code"}
 return [pscustomobject]@{Text=($lines -join "`n");ExitCode=$code}
}
function Assert-Serial([string]$Serial){if($Serial -notmatch '^[A-Za-z0-9._:-]{1,128}$'){throw 'DEVICE_SERIAL_INVALID'}}
function Resolve-Device([string]$Adb,[string]$Given) {
 if($Given){Assert-Serial $Given;if($Given -match '^[0-9.]+:[0-9]+$'){$null=Invoke-Adb -Adb $Adb -Arguments @('connect',$Given) -AllowFailure};$r=Invoke-Adb -Adb $Adb -Arguments @('-s',$Given,'get-state');if($r.Text.Trim() -ne 'device'){throw 'DEVICE_NOT_READY'};return $Given}
 $r=Invoke-Adb -Adb $Adb -Arguments @('devices');$ready=@();$pending=$false
 foreach($line in ($r.Text -split "`r?`n")){if($line -match '^(\S+)\s+device\s*$'){$ready+=$Matches[1]};if($line -match '\sunauthorized\s*$'){$pending=$true}}
 if($ready.Count -eq 1){return $ready[0]};if($ready.Count -gt 1){throw ('MULTIPLE_DEVICES_USE_DEVICE: '+($ready -join ', '))};if($pending){throw 'ALLOW_USB_DEBUGGING_ON_DEVICE'}
 $null=Invoke-Adb -Adb $Adb -Arguments @('connect','192.168.0.1:5555') -AllowFailure
 $r=Invoke-Adb -Adb $Adb -Arguments @('devices');foreach($line in ($r.Text -split "`r?`n")){if($line -match '^(192\.168\.0\.1:5555)\s+device\s*$'){return $Matches[1]}}
 throw 'CONNECT_USB_AND_ENABLE_DEBUGGING_OR_ENABLE_WIRELESS_ADB'
}
function Get-DeviceReport([string]$Adb,[string]$Device) {
 Assert-Serial $Device
 $script='printf "model=%s\ndevice=%s\nbuild=%s\nfingerprint=%s\nabi=%s\nsdk=%s\nslot=%s\nflash_locked=%s\n" "$(getprop ro.product.model)" "$(getprop ro.product.device)" "$(getprop ro.build.display.id)" "$(getprop ro.build.fingerprint)" "$(getprop ro.product.cpu.abi)" "$(getprop ro.build.version.sdk)" "$(getprop ro.boot.slot_suffix)" "$(getprop ro.boot.flash.locked)"'
 $escaped=$script.Replace("'","'\''")
 $r=Invoke-Adb -Adb $Adb -Arguments @('-s',$Device,'shell','-T',("/system/bin/sh -c '"+$escaped+"'"))
 $v=[ordered]@{};foreach($l in ($r.Text -split "`r?`n")){if($l -match '^([a-z_]+)=(.*)$'){$v[$Matches[1]]=$Matches[2]}}
 $root=Invoke-Adb -Adb $Adb -Arguments @('-s',$Device,'shell','-T',"su -c 'id -u'") -AllowFailure
 $v['root']=($root.ExitCode -eq 0 -and $root.Text.Trim() -eq '0')
 $v['testedModel']=($v['model'] -eq 'MU5358' -and $v['build'] -eq 'U30ProV1.0.0B24')
 $v['candidateModel']=($v['model'] -eq 'F50' -and $v['device'] -eq 'MU300' -and $v['build'] -eq 'F50SPV1.0.0B08')
 return [pscustomobject]$v
}
function Assert-SupportedDevice($Report) {
 if($Report.abi -ne 'arm64-v8a'){throw 'ARM64_ANDROID_REQUIRED'}
 if(-not($Report.testedModel -or $Report.candidateModel)){throw 'DEVICE_BUILD_NOT_SUPPORTED'}
}
function Save-DeviceReport([string]$AppHome,$Report) {
 $d=Join-Path $AppHome 'reports';New-Item -ItemType Directory -Path $d -Force | Out-Null
 $path=Join-Path $d ('device-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'.json')
 $Report | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $path -Encoding UTF8
 return $path
}
