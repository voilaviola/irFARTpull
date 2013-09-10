<#  
.SYNOPSIS  
    IR Forensic ARTifact pull (irFArtpull)

.DESCRIPTION
irFARTpull is a PowerShell script utilized to pull several forensic artifacts from a live WinXP-Win7 system on your network. It DOES NOT utilize WinRM capabilities.

Artifacts it grabs:
	- Disk Information
	- System Information
	- User Information
	- Network Configuration
	- Netstat info
	- Route Table, ARP Table, DNS Cache, HOSTS file
	- Running Processes
	- Services
	- Event Logs (System, Security, Application)
	- Prefetch Files
	- MFT$
	- Registry Files
	- User NTUSER.dat files
	- Java IDX files
	- Internet History Files (IE, Firefox, Chrome)
	
When done collecting the artifacts, it will 7zip the data and pull the info off the box for offline analysis. 
		
NOTEs:  
    
	All testing done on PowerShell v3
	Requires RawCopy64.exe for the extraction of MFT$ and NTUSER.DAT files.
	Requires 7za.exe (7zip cmd line) for compression w/ password protection
	
	Assumed Directories:
	c:\tools\resp\ - where the RawCopy64.exe and 7za.exe exist
	c:\windows\temp\IR - Where the work will be done
		
	Must be ran as a user that will have Admin creds on the remote system. The assumption is that the target system is part of a domain.
	
LINKs:  
	
	irFARTpull main - https://github.com/n3l5/irFARTpull
	
	Links to required tools:
	mft2csv - Part of the mft2csv suite, RawCopy can be downloaded here: https://code.google.com/p/mft2csv/
	7-Zip - Part of the 7-Zip archiver, 7za can be downloaded from here: http://www.7-zip.org/
	
	Various tools for analysis of the artifacts:
	RegRipper - Tool for extracting data from Registry and NTUSER.dat files. https://code.google.com/p/regripper/
	WinPrefetchView - utility to read Prefetch files. http://www.nirsoft.net/utils/win_prefetch_view.html
	MFTDump - tool to dump the contents of the $MFT. http://malware-hunters.net/2012/09/

FUTURE Enhancements:

	PowerShell v4 testing and enhancements
	Credential Request

#>

echo "=============================================="
echo "=============================================="
Write-Host -Fore Magenta "

  _      ______           _               _ _ 
 (_)    |  ____/\        | |             | | |
  _ _ __| |__ /  \   _ __| |_ _ __  _   _| | |
 | | '__|  __/ /\ \ | '__| __| '_ \| | | | | |
 | | |  | | / ____ \| |  | |_| |_) | |_| | | |
 |_|_|  |_|/_/    \_\_|   \__| .__/ \__,_|_|_|
                             | |              
                             |_|              

 "
echo "=============================================="
Write-Host -Fore Yellow "Run as administrator/elevated privileges!!!"
Write-Host -ForegroundColor Cyan "Replace DOMAIN\USER with your creds..."
echo "=============================================="
echo ""
Write-Host -Fore Cyan ">>>>> Press a key to begin...."
[void][System.Console]::ReadKey($TRUE)
echo ""
echo ""
$cred = Get-Credential DOMAIN\USER
$target = read-host ">>>>> Please enter a HOSTNAME or IP..."
$targetName = Get-WMIObject Win32_ComputerSystem -ComputerName $target -Credential $cred | ForEach-Object Name
$transLog = $targetName + "_irfartpull_log.txt"
$irFolder = "c:\Windows\Temp\IR\"
if (!(Test-Path $irFolder)) {
New-Item -Path $irFolder -ItemType Directory | Out-Null }
else {
Start-Transcript -Path "$irFolder\$transLog" | Out-Null }
echo ""
Write-Host -Fore Yellow ">>>>> pinging $target...."
echo ""

##Test Connection (simple ping; PS4 will have a nicer test function##
if(!(Test-Connection -ComputerName $target -BufferSize 16 -Count 1 -ea 0 -quiet)){
   Write-Host -Fore Red "Problem connecting to $target"
   Write-Host -Fore Yellow "  Flushing DNS"
   ipconfig /flushdns | out-null
   Write-Host -Fore Yellow "  Registering DNS"
   ipconfig /registerdns | out-null
   Write-Host -Fore Yellow "  doing a NSLookup for $target"
   nslookup $target
   Write-Host -Fore Yellow "  Re-pinging $target"
     if(!(Test-Connection -ComputerName $target -BufferSize 16 -Count 1 -ea 0 -quiet)){
	 	Write-Host -Fore Red ">>>>> System appears to be OFF LINE"
	  	Stop-Transcript | Out-Null
	  	echo ""
	  	Write-Host -ForegroundColor Cyan "Press any key to exit..."
	  	[void][System.Console]::ReadKey($TRUE)
	  	Break
	  	}
		}
Else { 
	 	Write-Host -Fore Green ">>>>> System Is ON LINE. Connecting to $target."
	}
echo ""
echo "=============================================="
Write-Host -ForegroundColor Magenta "==[ $targetName - $target ]=="

################
##Set up environment on remote system. IR folder for tools and art folder for artifacts.##
################
##For consistency, the working directory will be located in the "c:\windows\temp\IR" folder on both the target and initiator system.
##Tools will stored directly in the "IR" folder for use. Artifacts collected on the local environment of the remote system will be dropped in the workingdir.

##Determine x32 or x64
$arch = Get-WmiObject -Class Win32_Processor -ComputerName $target -Credential $cred | foreach {$_.AddressWidth}

#Determine XP or Win7
$OSvers = Get-WMIObject -Class Win32_OperatingSystem -ComputerName $target -Credential $cred | foreach {$_.Version}
	if ($OSvers -like "5*"){
	Write-Host -ForegroundColor Magenta "==[ Host OS: Windows XP $arch  ]=="
	}
	if ($OSvers -like "6*"){
	Write-Host -ForegroundColor Magenta "==[ Host OS: Windows 7 $arch    ]=="
	}
echo "=============================================="
echo ""
##Set up PSDrive mapping to remote drive
New-PSDrive -Name X -PSProvider filesystem -Root \\$target\c$ -Credential $cred | Out-Null

$remoteIRfold = "X:\windows\Temp\IR"
$date = Get-Date -format yyyy-MM-dd_HHmm_
$irFolder = "c:\Windows\Temp\IR\"
$artFolder = $date + $targetName
$workingDir = $irFolder + $artFolder
$dirList = ("$remoteIRfold\$artFolder\logs","$remoteIRfold\$artFolder\network","$remoteIRfold\$artFolder\prefetch","$remoteIRfold\$artFolder\reg")
New-Item -Path $dirList -ItemType Directory | Out-Null

##connect and move software to target client
Write-Host -Fore Green "Copying tools...."
$tools = "c:\tools\resp\*.*"
Copy-Item $tools $remoteIRfold -recurse

##SystemInformation
Write-Host -Fore Green "Pulling system information...."
Get-WMIObject Win32_LogicalDisk -ComputerName $target -Credential $cred | Select DeviceID,DriveType,@{l="Drive Size";e={$_.Size / 1GB -join ""}},@{l="Free Space";e={$_.FreeSpace / 1GB -join ""}} | Export-CSV $remoteIRfold\$artFolder\diskInfo.csv -NoTypeInformation | Out-Null
Get-WMIObject Win32_ComputerSystem -ComputerName $target -Credential $cred | Select Name,UserName,Domain,Manufacturer,Model,PCSystemType | Export-CSV $remoteIRfold\$artFolder\systemInfo.csv -NoTypeInformation | Out-Null
Get-WmiObject Win32_UserProfile -ComputerName $target -Credential $cred | select Localpath,SID,LastUseTime | Export-CSV $remoteIRfold\$artFolder\users.csv -NoTypeInformation | Out-Null

##gather network  & adapter info
Write-Host -Fore Green "Pulling network information...."
Get-WMIObject Win32_NetworkAdapterConfiguration -ComputerName $target -Filter "IPEnabled='TRUE'" -Credential $cred | select DNSHostName,ServiceName,MacAddress,@{l="IPAddress";e={$_.IPAddress -join ","}},@{l="DefaultIPGateway";e={$_.DefaultIPGateway -join ","}},DNSDomain,@{l="DNSServerSearchOrder";e={$_.DNSServerSearchOrder -join ","}},Description | Export-CSV $remoteIRfold\$artFolder\network\netinfo.csv -NoTypeInformation | Out-Null

$netstat = "cmd /c c:\windows\system32\netstat.exe -anob > $workingDir\network\netstats.txt"
InVoke-WmiMethod -class Win32_process -name Create -ArgumentList $netstat -ComputerName $target -Credential $cred | Out-Null
$netroute = "cmd /c c:\windows\system32\netstat.exe -r > $workingDir\network\routetable.txt"
InVoke-WmiMethod -class Win32_process -name Create -ArgumentList $netroute -ComputerName $target -Credential $cred | Out-Null
$dnscache = "cmd /c c:\windows\system32\ipconfig /displaydns > $workingDir\network\dnscache.txt"
InVoke-WmiMethod -class Win32_process -name Create -ArgumentList $dnscache -ComputerName $target -Credential $cred | Out-Null
$arpdata =  "cmd /c c:\windows\system32\arp.exe -a > $workingDir\network\arpdata.txt"
InVoke-WmiMethod -class Win32_process -name Create -ArgumentList $arpdata -ComputerName $target -Credential $cred | Out-Null
Copy-Item x:\windows\system32\drivers\etc\hosts $remoteIRfold\$artFolder\network\hosts 

##gather Process info
Write-Host -Fore Green "Pulling process info...."
Get-WMIObject Win32_Process -Computername $target -Credential $cred | select name,parentprocessid,processid,executablepath,commandline | Export-CSV $remoteIRfold\$artFolder\procs.csv -NoTypeInformation | Out-Null

##gather Services info
Write-Host -Fore Green "Pulling service info...."
Get-WMIObject Win32_Service -Computername $target -Credential $cred | Select processid,name,state,displayname,pathname,startmode | Export-CSV $remoteIRfold\$artFolder\services.csv -NoTypeInformation | Out-Null

##Copy Log Files
Write-Host -Fore Green "Pulling event logs...."
$logLoc = "x:\windows\system32\Winevt\Logs"
$loglist = @("$logLoc\application.evtx","$logLoc\security.evtx","$logLoc\system.evtx")
Copy-Item -Path $loglist -Destination $remoteIRfold\$artFolder\logs\ -Force

##Copy Prefetch files
Write-Host -Fore Green "Pulling prefetch files...."
Copy-Item x:\windows\prefetch\*.pf $remoteIRfold\$artFolder\prefetch -recurse

##Copy $MFT
Write-Host -Fore Green "Pulling the MFT...."
if ($arch –like “5*”) 
{
InVoke-WmiMethod -class Win32_process -name Create -ArgumentList "cmd /c $irFolder\RawCopy.exe c:0 $workingDir" -ComputerName $target -Credential $cred | Out-Null
}
if ($arch –like “6*”) 
{
InVoke-WmiMethod -class Win32_process -name Create -ArgumentList "cmd /c $irFolder\RawCopy64.exe c:0 $workingDir" -ComputerName $target -Credential $cred | Out-Null
}
do {(Write-Host -ForegroundColor Yellow "  waiting for MFT copy to complete..."),(Start-Sleep -Seconds 5)}
until ((Get-WMIobject -Class Win32_process -Filter "Name='RawCopy64.exe'" -ComputerName $target -Credential $cred | where {$_.Name -eq "RawCopy64.exe"}).ProcessID -eq $null)
Write-Host "  [done]"

##Copy Reg files
Write-Host -Fore Green "Pulling registry files...."
$regLoc = "c:\windows\system32\config\"
if ($arch –like “5*”) 
{
InVoke-WmiMethod -class Win32_process -name Create -ArgumentList "cmd /c $irFolder\RawCopy.exe $regLoc\SOFTWARE $workingDir\reg" -ComputerName $target -Credential $cred | Out-Null
InVoke-WmiMethod -class Win32_process -name Create -ArgumentList "cmd /c $irFolder\RawCopy.exe $regLoc\SYSTEM $workingDir\reg" -ComputerName $target -Credential $cred | Out-Null
InVoke-WmiMethod -class Win32_process -name Create -ArgumentList "cmd /c $irFolder\RawCopy.exe $regLoc\SAM $workingDir\reg" -ComputerName $target -Credential $cred | Out-Null
InVoke-WmiMethod -class Win32_process -name Create -ArgumentList "cmd /c $irFolder\RawCopy.exe $regLoc\SECURITY $workingDir\reg" -ComputerName $target -Credential $cred | Out-Null
do {(Write-Host -ForegroundColor Yellow "  waiting for Reg Files copy to complete..."),(Start-Sleep -Seconds 5)}
until ((Get-WMIobject -Class Win32_process -Filter "Name='RawCopy.exe'" -ComputerName $target -Credential $cred | where {$_.Name -eq "RawCopy.exe"}).ProcessID -eq $null)
}
if ($arch –like “6*”) 
{
InVoke-WmiMethod -class Win32_process -name Create -ArgumentList "cmd /c $irFolder\RawCopy64.exe $regLoc\SOFTWARE $workingDir\reg" -ComputerName $target -Credential $cred | Out-Null
InVoke-WmiMethod -class Win32_process -name Create -ArgumentList "cmd /c $irFolder\RawCopy64.exe $regLoc\SYSTEM $workingDir\reg" -ComputerName $target -Credential $cred | Out-Null
InVoke-WmiMethod -class Win32_process -name Create -ArgumentList "cmd /c $irFolder\RawCopy64.exe $regLoc\SAM $workingDir\reg" -ComputerName $target -Credential $cred | Out-Null
InVoke-WmiMethod -class Win32_process -name Create -ArgumentList "cmd /c $irFolder\RawCopy64.exe $regLoc\SECURITY $workingDir\reg" -ComputerName $target -Credential $cred | Out-Null
do {(Write-Host -ForegroundColor Yellow "  waiting for Reg Files copy to complete..."),(Start-Sleep -Seconds 5)}
until ((Get-WMIobject -Class Win32_process -Filter "Name='RawCopy64.exe'" -ComputerName $target -Credential $cred | where {$_.Name -eq "RawCopy64.exe"}).ProcessID -eq $null)
}
Write-Host "  [done]"

##Copy Symantec Quarantine Files (default location)##
$symQ = "x:\ProgramData\Symantec\Symantec Endpoint Protection\*\Data\Quarantine"
if (Test-Path -Path "$symQ\*.vbn") {
	Write-Host -Fore Green "Pulling Symantec Quarantine files...."
	New-Item -Path $remoteIRfold\$artFolder\SymantecQuarantine -ItemType Directory  | Out-Null
	Copy-Item -Path "$symQ\*.vbn" $remoteIRfold\$artFolder\SymantecQuarantine -Force -Recurse
}
else
{
Write-Host -Fore Red "No Symantec Quarantine files...."
}

##Copy Symantec Log Files (default location)##
$symLog = "x:\ProgramData\Symantec\Symantec Endpoint Protection\*\Data\Logs"
if (Test-Path -Path "$symLog\*.log") {
	Write-Host -Fore Green "Pulling Symantec Log files...."
	New-Item -Path $remoteIRfold\$artFolder\SymantecLogs -ItemType Directory  | Out-Null
	Copy-Item -Path "$symLog\*.Log" $remoteIRfold\$artFolder\SymantecLogs -Force -Recurse
}
else
{
Write-Host -Fore Red "No Symantec Log files...."
}

##Copy McAfee Quarantine Files (default location)##
$mcafQ = "x:\Quarantine"
if (Test-Path -Path "$symQ\*.bup") {
	Write-Host -Fore Green "Pulling McAfee Quarantine files...."
	New-Item -Path $remoteIRfold\$artFolder\McAfeeQuarantine -ItemType Directory  | Out-Null
	Copy-Item -Path "$symQ\*.bup" $remoteIRfold\$artFolder\McAfeeQuarantine -Force -Recurse
}
else
{
Write-Host -Fore Red "No McAfee Quarantine files...."
}
##Copy McAfee Log Files (default location)##
$mcafLog = "x:\ProgramData\McAfee\DesktopProtection"
if (Test-Path -Path "$mcafLog\*.txt") {
	Write-Host -Fore Green "Pulling McAfee Log files...."
	New-Item -Path $remoteIRfold\$artFolder\McAfeeAVLogs -ItemType Directory  | Out-Null
	Copy-Item -Path "$symQ\*.bup" $remoteIRfold\$artFolder\McAfeeAVLogs -Force -Recurse
}
else
{
Write-Host -Fore Red "No McAfee Log files...."
}

###################
##Perform Operations on user files
###################
echo ""
echo "=============================================="
Write-Host -Fore Magenta ">>>[Pulling items from user profiles]<<<"
echo "=============================================="
echo ""
$localprofiles = Get-WMIObject Win32_UserProfile -filter "Special != 'true'" -ComputerName $target -Credential $cred | Where {$_.LocalPath -and ($_.ConvertToDateTime($_.LastUseTime)) -gt (get-date).AddDays(-15) }
foreach ($localprofile in $localprofiles){
	$temppath = $localprofile.localpath
	$source = $temppath + "\ntuser.dat"
	$eof = $temppath.Length
	$last = $temppath.LastIndexOf('\')
	$count = $eof - $last
	$user = $temppath.Substring($last,$count)
	$destination = "$workingDir\users" + $user
	Write-Host -ForegroundColor Magenta "Pulling items for >> [ $user ]"
	Write-Host -Fore Green "  Pulling NTUSER.DAT file for $user...."
	New-Item -Path $remoteIRfold\$artFolder\users\$user -ItemType Directory  | Out-Null
	InVoke-WmiMethod -class Win32_process -name Create -ArgumentList "cmd /c $irFolder\RawCopy64.exe $source $destination" -ComputerName $target -Credential $cred | Out-Null
if ($temppath –like “C:\documents and settings\*")
{
$XPpath = "x:\documents and settings"
}
if ($temppath –like “C:\Users\*”)
{
$W7path = "x:\users"
}

##Pull IDX files##
$XPidxpath = "$XPpath\$user\Application Data\Sun\Java\Deployment\cache\"
$W7idxpath = "$W7path\$user\AppData\LocalLow\Sun\Java\Deployment\cache\"
if ($OSvers -like "5*" -and (Test-Path -Path $XPidxpath -PathType Container)) {
		Write-Host -Fore Green "  Pulling IDX files for $user....(XP)"
		$idxFiles = Get-ChildItem -Path $XPidxpath -Filter "*.idx" -Force -Recurse | Where-Object {$_.Length -gt 0 -and $_.LastWriteTime -gt (get-date).AddDays(-15)} | foreach {$_.Fullname}
		Write-Host -Fore Yellow "    pulling IDX files...."
		foreach ($idx in $idxFiles){
		Copy-Item -Path $idx -Destination $remoteIRfold\$artFolder\users\$user
		}
		}
elseif ($OSvers -like "6*" -and (Test-Path $W7idxpath -PathType Container)) {
		Write-Host -Fore Green "  Pulling IDX files for $user....(W7)"
		New-Item -Path $remoteIRfold\$artFolder\users\$user\idx -ItemType Directory  | Out-Null
		$idxFiles = Get-ChildItem -Path $W7idxpath -Filter "*.idx" -Force -Recurse | Where-Object {$_.Length -gt 0 -and $_.LastWriteTime -gt (get-date).AddDays(-15)} | foreach {$_.Fullname}
		Write-Host -Fore Yellow "    pulling IDX files...."
		foreach ($idx in $idxFiles){
		Copy-Item -Path $idx -Destination $remoteIRfold\$artFolder\users\$user\idx\
		}
	}
else {
	 	 Write-Host -Fore Red "  No IDX files newer than 15 days for $user...."
	 	 }

##Copy Internet History files##	
$XPinet = "$XPpath\$user\Local Settings\History\"
$Win7inet = "$W7path\$user\AppData\Local\Microsoft\Windows\History\"
Write-Host -Fore Green "  Pulling Internet Explorer History files for $user...."
	if ($OSvers -like "5*") {
		New-Item -Path $remoteIRfold\$artFolder\users\$user\InternetHistory\IE -ItemType Directory | Out-Null
		$inethist = Get-ChildItem -Path $XPinet -ReCurse -Force | foreach {$_.Fullname}
		foreach ($inet in $inethist) {
		Copy-Item -Path $inet -Destination $remoteIRfold\$artFolder\users\$user\InternetHistory\IE -Force -Recurse
		}
	}	
	if ($OSvers -like "6*"){
		New-Item -Path $remoteIRfold\$artFolder\users\$user\InternetHistory\IE -ItemType Directory | Out-Null
		$inethist = Get-ChildItem -Path $Win7inet -ReCurse -Force | foreach {$_.Fullname}
		foreach ($inet in $inethist) {
		Copy-Item -Path $inet -Destination $remoteIRfold\$artFolder\users\$user\InternetHistory\IE -Force -Recurse
		}
	}
##Copy FireFox History files##
$XPfoxpath = "$XPpath\$user\Application Data\Mozilla\Firefox\profiles"
$w7foxpath = "$W7path\$user\AppData\Roaming\Mozilla\Firefox\profiles"
if ($OSvers -like "5*" -and (Test-Path -Path $XPfoxpath -PathType Container)) {
		Write-Host -Fore Green "  Pulling FireFox Internet History files (XP) for $user...."
		New-Item -Path $remoteIRfold\$artFolder\users\$user\InternetHistory\Firefox -ItemType Directory  | Out-Null
		$ffinet = Get-ChildItem $XPfoxpath -Filter "places.sqlite" -Force -Recurse | foreach {$_.Fullname}
		Foreach ($ffi in $ffinet) {
		Copy-Item -Path $ffi -Destination $remoteIRfold\$artFolder\users\$user\InternetHistory\Firefox
		$ffdown = Get-ChildItem $XPfoxpath -Filter "downloads.sqlite" -Force -Recurse | foreach {$_.Fullname}
		}
		Foreach ($ffd in $ffdown) {
		Copy-Item -Path $ffd -Destination $remoteIRfold\$artFolder\users\$user\InternetHistory\Firefox
		}
		}
elseif ($OSvers -like "6*" -and (Test-Path -Path $w7foxpath -PathType Container)) {
		Write-Host -Fore Green "  Pulling FireFox Internet History files for $user....(W7)"
		New-Item -Path $remoteIRfold\$artFolder\users\$user\InternetHistory\Firefox -ItemType Directory  | Out-Null
		$ffinet = Get-ChildItem $w7foxpath -Filter "places.sqlite" -Force -Recurse | foreach {$_.Fullname}
		Foreach ($ffi in $ffinet) {
		Copy-Item -Path $ffi -Destination $remoteIRfold\$artFolder\users\$user\InternetHistory\Firefox
		$ffdown = Get-ChildItem $w7foxpath -Filter "downloads.sqlite" -Force -Recurse | foreach {$_.Fullname}
		}
Foreach ($ffd in $ffdown) {
		Copy-Item -Path $ffd -Destination $remoteIRfold\$artFolder\users\$user\InternetHistory\Firefox
		}
		}
else {
		 Write-Host -Fore Red "  No FireFox Internet History files for $user...."
	 	 }

##Copy Chrome History files##
$XPchromepath = "$XPpath\$user\Local Settings\Application Data\Google\Chrome\User Data\Default"
$W7chromepath = "$W7path\$user\AppData\Local\Google\Chrome\User Data\Default"
if ($OSvers -like "5*" -and (Test-Path -Path $XPchromepath -PathType Container)) {
		Write-Host -Fore Green "  Pulling Chrome Internet History files for $user....(XP)"
		New-Item -Path $remoteIRfold\$artFolder\users\$user\InternetHistory\Chrome -ItemType Directory  | Out-Null
		$chromeInet = Get-ChildItem $XPchromepath -Filter "History" -Force -Recurse | foreach {$_.Fullname}
		Foreach ($chrmi in $chromeInet) {
		Copy-Item -Path $chrmi -Destination $remoteIRfold\$artFolder\users\$user\InternetHistory\Chrome
		}
	}
elseif ($OSvers -like "6*" -and (Test-Path -Path $W7chromepath -PathType Container)) {
		Write-Host -Fore Green "  Pulling Chrome Internet History files for $user....(W7)"
		New-Item -Path $remoteIRfold\$artFolder\users\$user\InternetHistory\Chrome -ItemType Directory  | Out-Null
		$chromeInet = Get-ChildItem $W7chromepath -Filter "History" -Force -Recurse | foreach {$_.Fullname}
		Foreach ($chrmi in $chromeInet) {
		Copy-Item -Path $chrmi -Destination $remoteIRfold\$artFolder\users\$user\InternetHistory\Chrome
		}
	}
else {
		 Write-Host -Fore Red "  No Chrome Internet History files $user...."
		 }
}

###################
##Package up the data and pull
###################
echo ""
echo "=============================================="
Write-Host -Fore Magenta ">>>[Packaging the collection]<<<"
echo "=============================================="
echo ""
Get-ChildItem $remoteIRfold -Force -Recurse | Export-CSV $remoteIRfold\$artFolder\FileReport.csv

##7zip the artifact collection##
$passwd = read-host ">>>>> Please supply a password"
echo ""
$7z = "cmd /c $irFolder\7za.exe a $workingDir.7z -p$passwd -mhe $workingDir"
InVoke-WmiMethod -class Win32_process -name Create -ArgumentList $7z -ComputerName $target -Credential $cred | Out-Null
do {(Write-Host -ForegroundColor Yellow "  packing the collected artifacts..."),(Start-Sleep -Seconds 10)}
until ((Get-WMIobject -Class Win32_process -Filter "Name='7za.exe'" -ComputerName $target -Credential $cred | where {$_.Name -eq "7za.exe"}).ProcessID -eq $null)
Write-Host "Packing complete..."

##size it up
Write-Host -ForegroundColor Cyan "  [Package Stats]"
$dirsize = "{0:N2}" -f ((Get-ChildItem $remoteIRfold\$artFolder | Measure-Object -property length -sum ).Sum / 1MB) + " MB"
Write-Host -ForegroundColor Cyan "  Working Dir: $dirsize "
$7zsize = "{0:N2}" -f ((Get-ChildItem $remoteIRfold\$artfolder.7z | Measure-Object -property length -sum ).Sum / 1MB) + " MB"
Write-Host -ForegroundColor Cyan "  Package size: $7zsize "

Write-Host -Fore Green "Transfering the package...."
Move-Item $remoteIRfold\$artfolder.7z $irFolder
Write-Host -Fore Yellow "  [done]"

###Delete the IR folder##
Write-Host -Fore Green "Removing the working environment...."
Remove-Item $remoteIRfold -Recurse -Force 

##Disconnect the PSDrive X mapping##
Remove-PSDrive X

##Ending##
echo "=============================================="
Write-Host -ForegroundColor Magenta ">>>>>>>>>>[[ irFArtPull complete ]]<<<<<<<<<<<"
echo "=============================================="
Stop-Transcript | Out-Null