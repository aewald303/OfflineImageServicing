#Requires -RunAsAdministrator
##DO THIS STUFF FIRST!###
#Install-Module -Name OSDBuilder -Force
#Import-Module -Name OSDBuilder -Force
#Get-OSDBuilder -Update
#Run Get-OSDBuilder to setup default folders to C:\OSDBuilder or use Get-OSDBuilder -SetPath <path> to specify a custom directory.
#To Import a new ISO, mount the ISO normally then run Import-OSMedia

#Use these commands to Modify and or create the OSD Build Task
#New-OSBuildTask -TaskName <TaskName> -CustomName <TaskName>
#New-OSBuildTask -TaskName <TaskName> -RemoveAppx     ###Not needed if you are NOT removing any .
#New-OSBuildTask -TaskName <TaskName> -ContentDrivers ###Not needed if you are NOT injecting drivers.
#New-OSBuildTask -TaskName <TaskName> -ContentScripts ###Not needed if you are NOT running scripts against the image.
#Change the Variables to below to match.
################ Vars edit these as needed ##################
$OS = "Win11" #Just used to quickly update OS version
$OSBuild = "23H2"  #Just used to quickly update OS Build version
$SCCMSiteCode = "<SiteCode>:" #Make sure to include the : at the end!
#$TaskName = "$($OS)_$($OSBuild)"
$TaskName = "<TaskName>" #Taskname OSDBuilder uses to apply your settings. Make sure you've created one first!
$SCCMWimDirectory = "E:\Source\OS\WIMS\$OS\$OSBuild" #Where the source directory for the install.wim is at. 
$SCCMWimBackupDirectory = "E:\Source\OS\WIMS\$OS\Backup\$OSBuild" #Where you want the backup .wim files to go.
$SCCMOSImageID = "<ImagePackageID>" #OS package ID of the operating sytem you want to update.
$SCCMPowerShellModule = "C:\Program Files (x86)\Microsoft Configuration Manager\AdminConsole\bin\ConfigurationManager.psd1" #Location of the SCCM powershell module.
$OSDBuilderDir = "C:\OSDBuilder" 
$MountDir = "E:\Mount" #Where you want the install.wim to be mounted for DISM
$WinREMountDir = "E:\WinreMount" #Where you want the winre.wim to be mounted for DISM. HAS TO BE Different from the other mount directory!!!
$DriverFolder = "C:\OSDBuilder\Content\Drivers\<DriverFolder>" #Drop Drivers into here will recursively go through the folder specified.
$LogPath = "$OSDBuilderDir\OfflineWimUpdate.log"
######################################################
Start-Transcript -Path "$LogPath" -Append
$StartDate = Get-date
Write-Output "Start timestamp: $StartDate"
try {
    #Prereq Checks
    if(!(Test-Path $MountDir)){
        Write-Host "Mount directory not found. Creating Directory at $MountDir"
        mkdir $MountDir -ErrorAction Stop
    }
    if(!(Test-Path $WinREMountDir)){
        Write-Host "Windows Recovery Mount directory not found. Creating Directory at $WinREMountDir"
        mkdir $WinREMountDir -ErrorAction Stop
    }
    if(!(Test-Path $SCCMWimBackupDirectory)){
        Write-Host "SCCM WIM Backup directory not found. Creating Directory at $SCCMWimBackupDirectory"
        mkdir $SCCMWimBackupDirectory -ErrorAction Stop
    }
    if(!(Test-Path $SCCMWimDirectory)){
        Write-Host "SCCM WIM directory not found. Creating Directory at $SCCMWimDirectory"
        mkdir $SCCMWimDirectory -ErrorAction Stop
    }
    if(!(Test-Path $SCCMPowerShellModule)){
        Write-Host "Error:"
        Write-Host "Couldn't find Configuration Manager powershell module at: $SCCMPowerShellModule"
        Write-Host "Please install or update path"
        $EndDate = get-date
        $ExecutionTime = New-TimeSpan -Start $StartDate -End $EndDate
        Write-Output "End timestamp: $EndDate"
        Write-Output "Script exectuion time: $ExecutionTime"
        Stop-Transcript
        exit 1
    }
    if (!(Get-ChildItem "$OSDBuilderDir\Tasks" | Where-Object{$_.Name -eq "OSBuild $TaskName.json"})){
        Write-Host "Error:"
        Write-host "No Task has been created for OSDBuilder. Please create task as described in the top comment section of this script or verify taskname is correct."
        $EndDate = get-date
        $ExecutionTime = New-TimeSpan -Start $StartDate -End $EndDate
        Write-Output "End timestamp: $EndDate"
        Write-Output "Script exectuion time: $ExecutionTime"
        Stop-Transcript
        exit 1
    }
}
catch {
    Write-Host "Error:"
    $_
    $EndDate = get-date
    $ExecutionTime = New-TimeSpan -Start $StartDate -End $EndDate
    Write-Output "End timestamp: $EndDate"
    Write-Output "Script exectuion time: $ExecutionTime"
    Stop-Transcript
    exit 1
}

#Lists the Imported OSMedia
#Get-OSMedia -Verbose
try {
    #Downloads the latest Updates for the Imported Media
    Get-OSDBuilder -Download OSMediaUpdates -Verbose

    #Applies The Updates
    $OSName = Get-OSMedia -ErrorAction Stop
    $OSName.Name
    Update-OSMedia -Name $($OSName.Name) -Execute -SkipUpdatesPE -Verbose -ErrorAction Stop

    #Builds the Image
    New-OSBuild -ByTaskName $TaskName -SkipUpdatesPE -Verbose -ErrorAction Stop
}
catch {
    Write-Host "Error:"
    $_
    #unmounts any images that may have been stuck. 
    dism.exe /Unmount-wim /mountdir:"$WinREMountDir" /discard
    dism.exe /Unmount-wim /mountdir:"$MountDir" /discard
    $EndDate = get-date
    $ExecutionTime = New-TimeSpan -Start $StartDate -End $EndDate
    Write-Output "End timestamp: $EndDate"
    Write-Output "Script exectuion time: $ExecutionTime"
    Stop-Transcript
    exit 1
}
try {
    #This Injects Drivers into the Recovery wim in the install wim(Mainly for Dells so reset this PC works). Comment this out if not needed.
    $LatestBuildDir = Get-ChildItem "$OSDBuilderDir\OSBuilds" | Sort-Object -Property LastWriteTime -Descending | Select-Object -First 1
    Write-Host "Mounting Install.Wim"
    dism.exe /mount-wim /wimfile:"$($LatestBuildDir.Fullname)\OS\sources\install.wim" /index:1 /mountdir:"$MountDir" -ErrorAction Stop
    Write-Host "Mounting WinRE.Wim"
    dism.exe /mount-wim /wimfile:"$MountDir\Windows\System32\Recovery\winre.wim" /index:1 /mountdir:"$WinREMountDir" -ErrorAction Stop
    Write-Host "Injecting Drivers to WinRE.wim"
    dism.exe /Image:"$WinREMountDir" /Add-Driver /Driver:$DriverFolder /Recurse 
    Write-Host "Unmounting and saving WinRE.wim"
    dism.exe /Unmount-wim /mountdir:"$WinREMountDir" /commit
    Write-Host "Unmounting and saving Install.wim"
    dism.exe /Unmount-wim /mountdir:"$MountDir" /commit
}
catch {
    Write-Host "Error:"
    $_
    #unmounts any images that may have been stuck. 
    dism.exe /Unmount-wim /mountdir:"$WinREMountDir" /discard
    dism.exe /Unmount-wim /mountdir:"$MountDir" /discard
    $EndDate = get-date
    $ExecutionTime = New-TimeSpan -Start $StartDate -End $EndDate
    Write-Output "End timestamp: $EndDate"
    Write-Output "Script exectuion time: $ExecutionTime"
    Stop-Transcript
    exit 1
}
try {
    #Does a backup of the current .wim file in the source directory then copies the new .wim file. 
    Write-Host "Starting Backup of Previous Wim File"
    Copy-Item "$($SCCMWimDirectory)\install.wim" $SCCMWimBackupDirectory -Force -Confirm:$false
    $OSBuildDir = Get-ChildItem -Path "$OSDBuilderDir\OSBuilds\" | Where-Object {$_.Name -like "*$($TaskName)*"}
    Write-Host "Copying Wim to SCCM Directory"
    Copy-Item "$OSDBuilderDir\OSBuilds\$($OSBuildDir.Name)\OS\sources\install.wim" $SCCMWimDirectory -Force
}
catch {
    Write-Host "Error:"
    $_
    $EndDate = get-date
    $ExecutionTime = New-TimeSpan -Start $StartDate -End $EndDate
    Write-Output "End timestamp: $EndDate"
    Write-Output "Script exectuion time: $ExecutionTime"
    Stop-Transcript
    exit 1
}
try {
    #Updates the distribution points for wim file in SCCM.
    Write-Host "Attempting to update SCCM distribution points"
    Import-Module $SCCMPowerShellModule -ErrorAction Stop
    Set-Location -Path $SCCMSiteCode -ErrorAction Stop
    Update-CMDistributionPoint -OperatingSystemImageId $SCCMOSImageID -ErrorAction Stop
    Set-Location $PSScriptRoot
}
catch {
    Write-Host "Error:"
    $_
    Set-Location $PSScriptRoot
    $EndDate = get-date
    $ExecutionTime = New-TimeSpan -Start $StartDate -End $EndDate
    Write-Output "End timestamp: $EndDate"
    Write-Output "Script exectuion time: $ExecutionTime"
    Stop-Transcript
    exit 1
}
$EndDate = get-date
$ExecutionTime = New-TimeSpan -Start $StartDate -End $EndDate
Write-Output "End timestamp: $EndDate"
Write-Output "Script exectuion time: $ExecutionTime"
Stop-Transcript
exit 0