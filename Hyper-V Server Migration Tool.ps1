# Set The credential variables
# Local Administrator - Make sure each virtual machine you create has the same username and password when you run OOBE
$localAdminUsername = "Administrator"
$localAdminPassword = ConvertTo-SecureString "Replace with your local admin password" -AsPlainText -Force

# Domain Administrator - Make sure that this matches your domain administrator credentials must be domain\username format for the username variable
$domainAdminUsername = "mydomain.com\Administrator"
$domainAdminPassword = ConvertTo-SecureString "replace with your domain admin password" -AsPlainText -Force
$domainJoinName = "mydomain.com"

# Creates Local Admin Credential Object
$localAdminCredential = New-Object System.Management.Automation.PSCredential ($localAdminUsername, $localAdminPassword)

# Creates Domain Admin Credential Object
$domainAdminCredential = New-Object System.Management.Automation.PSCredential ("$domainAdminUsername", $domainAdminPassword)

<#
.SYNOPSIS
Provision Hyper-V Virtual Machines and Configure Services
Author: eskote
.DESCRIPTION
Long description

.EXAMPLE
An example

.NOTES
This script is designed to be run from a Hyper-V host. The functions are designed to be run in the order they are presented in the list.
#>##

### Begin Nested Functions

# Choose ISO Function
function chooseISO {
    # Define the location of the bootable .iso file
    Write-Host "Pick the virtual machines's bootable .iso file."
    Add-Type -AssemblyName System.Windows.Forms
    $FileDialog = New-Object System.Windows.Forms.OpenFileDialog
    $FileDialog.Filter = "ISO Files (*.iso)|*.iso|All Files (*.*)|*.*"  # Set file filter (modify if needed)
    $null = $FileDialog.ShowDialog()
    $vmISO = $FileDialog.FileName
    if ($null -ne $vmISO) {
        # Returns $vmISO as a variable when run
        Write-Host "Selected file: $vmISO." -ForegroundColor Yellow
        return $vmISO
    }else{
        # Recursive loop that will run if a selection is not made
        Write-Host "No selection made, please pick the virtual machine's bootable .iso file." -ForegroundColor DarkRed
        chooseISO
    }
}

# Set VM Name Function
function getVMName {
    $vm = Read-Host "Enter the hostname of your new VM"
    if ([string]::IsNullOrEmpty($vm)) {
        # Recursive loop that will run if a selection is not made
        Write-Host "No selection made, please enter the hostname of your VM." -ForegroundColor DarkRed
        getVMName
    }else{
        # Returns $vm as a variable when run
        Write-Host "Your VM will be named: $vm." -ForegroundColor Yellow
        return $vm
    }
}

# Get VM Function
function getVM {
    # Pick virtual machine and store in variable
    $vm = @(Get-VM) | Select-Object name | Out-GridView -Title "Select the virtual machine you wish to perform an action on." -OutputMode Single
    if ($null -ne $vm) {
        # convert array to string and return $vm as a variable
        $vm = $vm.Name
        return $vm
    }else{
        # Recursive loop that will run if a selection is not made
        Write-Host "No selection made, please select the VM you wish to perform an action on." -ForegroundColor DarkRed
        getVM
    }
}

# Enable VM Integration Function
function enableVMIntegration {
    # Attempt to enable VMIntegration
    try {
        Enable-VMIntegrationService -Name Shutdown -VMName $vm
        Enable-VMIntegrationService -VMName $vm -Name "Guest Service Interface"
        if ((Get-VMIntegrationService -VMName $vm -Name "Guest Service Interface").Enabled -eq $true) {
            # Script output that will run if VM Integration service was enabled
            Write-Host "VMIntegration shutdown service is enabled." -ForegroundColor Green
        } else {
            # Script output that will run if VM Integration service failed to enable
            Write-Host "VMIntegration Service is not running." -ForegroundColor Yellow
        }
    }
    catch {
        # Script output that will run if VM Integration service failed to enable
        Write-Host "Failed to enable VM Integration service. Continuing Script." -ForegroundColor DarkRed
    }
}

# Select RAM Function
function selectRAM {
    # Select RAM
    $selectedRAM = @("2 GB", "4 GB", "8 GB", "16 GB", "32 GB", "64 GB", "128 GB", "256 GB") | Out-GridView -Title "Select RAM" -OutputMode Single
    Write-Host "You selected: $selectedRAM GBs of RAM." -ForegroundColor Yellow

    if ($null -ne $selectedRAM) {
        # Extract numeric part and convert to bytes
        $ramInGB = [int]($selectedRAM -replace ' GB')
        $ramInBytes = $ramInGB * 1GB
        Write-Host "You selected: $selectedRAM, which is $ramInBytes bytes." -ForegroundColor Yellow
        return $ramInBytes
    } else {
        # Recursive loop that will run if a selection is not made
        Write-Host "No selection made. Please select the desired amount of RAM." -ForegroundColor DarkRed
        selectRAM
    }
}

# Create VM Switch Function
function createVMSwitch {
    # Checks for a VM Switch and will prompt you to select if one does not exist
    # Select one or more adapters, if more than 1 adapter is selected, the script block will create a team
    if ((Get-VMSwitch ).name -eq 'HYPER-V-SWITCH') {
    Write-Host "HYPER-V-SWITCH exists, skipping." -ForegroundColor Yellow
    $hyperVAdapter = "HYPER-V-SWITCH"
    }elseif ($null -eq (Get-VMSwitch)) {
        # If a Hyper-V switch named "HYPER-V-SWITCH" is not detected, allow the user to select multiple adapters and create
        # one with the same name
        $hyperVAdapter = Get-NetAdapter | Out-GridView -OutputMode Multiple -Title "Select the Adapter(s) For the HyperV VM Switch."
        Disable-NetAdapterVmq -Name $hyperVAdapter.Name
        New-VMSwitch -Name "HYPER-V-SWITCH" -NetAdapterName $hyperVAdapter.Name -AllowManagementOS $false
    }else{
        # This will run if a Hyper-V switch already exists and will rename to "HYPER-V-SWITCH"
        $hyperVAdapter = Get-VMSwitch | Out-GridView -OutputMode Multiple -Title "Select the existing Hyper-V switch."
        $hyperVAdapter = $hyperVAdapter.name
        Rename-VMSwitch -Name "$hyperVAdapter" -NewName "HYPER-V-SWITCH"
        Set-VMSwitch -name "HYPER-V-SWITCH" -AllowManagementOS $false
    }
}

# Pick VHDx Size Function
function Get-vmVHD1Input {
    # Select OS disk size
    # Prompt the user to enter the number of GB for the OS Disk in GB
    $inputGB = Read-Host "Please enter the number of GB for the OS Disk in GB"

    # Validate the input
    if ($inputGB -match '^\d+$' -and [int]$inputGB -gt 0) {
        return [int]$inputGB
    } else {
        # Validation that will rerun the function if a valid selection is not made
        Write-Host "Invalid input. Please enter a positive integer." -ForegroundColor DarkRed
        Get-vmVHD1Input
    }
}

# Choose CPU Cores Function
function chooseCPUCores {
    # Select number of CPU cores
    $selectedCores = @("1", "2", "4", "5", "6", "7", "8", "9", "10", "11", "12", "13", "14", "15", "16") | Out-GridView -Title "Select number of CPU cores." -OutputMode Single
    Write-Host "You selected: $selectedCores CPU cores." -ForegroundColor Yellow
    if ($null -ne $selectedCores) {
        # Returns $selectedCores as a variable when run
        return $selectedCores
    } else {
        # Recursive loop to re-run function if no selection is made
        Write-Host "No selection made, please select the desired number of CPU cores." -ForegroundColor DarkRed
        chooseCPUCores
    }
}

# Function that allows the uses to choose -Dynamic or -Fixed
function selectDriveType {
    $driveType = @("-Dynamic", "-Fixed") | Out-GridView -Title "Choose either -Dynamic or -Fixed for the drive type." -OutputMode Single
    if($null -ne $driveType){
        # Script message that confirms input selection
        Write-Host "You've chosen to create a $driveType disk." -ForegroundColor Yellow
        return $driveType
    }else{
        # Script message that will run if a selection is not made
        Write-Host "No selection made, please choose either -Dynamic or -Fixed." -ForegroundColor DarkRed

        # Recursively call selectDriveType function
        selectDriveType
    }
}

# Enable Secure Boot Function
function secureBootEnabled {
    # Pops open Out-GridView and allows user to select Yes or No
    $secureBootEnabled = @("On", "Off") | Out-GridView -Title "Set VM Secure boot On/Off." -OutputMode Single
    if ($null -eq $secureBootEnabled) {
        # Recursive loop to re-run function if no selection is made
        Write-Host "Please choose Yes or No to proceed with script." -ForegroundColor DarkRed
        secureBootEnabled
    }elseif($null -ne $secureBootEnabled){
        # Script output that returns whether secure boot was enabled
        Write-Host "Secure boot is $secureBootEnabled." -ForegroundColor Green
    }
}

# Enable VM TPM Function
function enableVMTPM {
    # Out grid view select yes or no
    $enableTPM = @("Yes", "No") | Out-GridView -Title "Enable VM TPM?" -OutputMode Single
    if ($null -eq $enableTPM) {
        # Recursive loop to re-run function if no selection is made
        Write-Host "No selection made. Please select Yes or No." -ForegroundColor DarkRed
        enableVMTPM
    }elseif($enableTPM -eq "Yes"){
        try {
            # If yes is selected, set-VMKeyProtector and enable VMTPM
            Set-VMKeyProtector -VMName $vm -NewLocalKeyProtector
            if($?){
                # If Previous command succeedeeds, then enable VM TPM
                Enable-VMTPM -VMName $vm
                Write-Host "Successfully enabled VM TPM on $vm." -ForegroundColor Green
            }else{
                # Script output that will run if Enable-VPMTPM fails
                Write-Host "Failed to enable VM TPM on $vm." -ForegroundColor DarkRed
            }       
        }
        catch {
            # Script out that will run if Set-VMKeyProtector fails
            Write-Host "Failed to Set VM key protector on $vm." -ForegroundColor DarkRed
        }
    }elseif($enableTPM -eq "No"){
        # Script output that will run if "No" is selected at the beginning of the function
        Write-Host "Did not enable VM TPM on $vm." -ForegroundColor Yellow
    } 
}

# Pick MSI Function
function pickMSI {
    # Open up file dialog and allow the user to pick an .msi file
    Write-Host "Pick the .msi you want to copy to the VM." -ForegroundColor Green
    Add-Type -AssemblyName System.Windows.Forms
    $FileDialog = New-Object System.Windows.Forms.OpenFileDialog
    $FileDialog.Filter = "MSI Files (*.msi)|*.msi|All Files (*.*)|*.*"  # Set file filter
    $null = $FileDialog.ShowDialog()
    $installerFile = $FileDialog.FileName

    # Recursive loop that will run if a selection is not made
    if ([string]::IsNullOrEmpty($installerFile)) {
        Write-Host "You did not pick a file, please pick a file to proceed." -ForegroundColor DarkRed
        return pickMSI  # Recursively call again
    }

    # Extract the file name without path
    $fileName = Split-Path -Path $installerFile -Leaf
    Write-Host "You picked: $installerFile." -ForegroundColor Yellow
    Write-Host "File name is: $fileName." -ForegroundColor Yellow

    # Return both values as a hashtable
    return @{ installerFile = $installerFile; fileName = $fileName }
}

# Wait until VM is fully booted
function Wait-VMFullyBooted {
    param (
        [string]$vm,
        [int]$TimeoutSeconds = 600,
        [datetime]$StartTime = $(Get-Date)
    )

    $elapsed = (Get-Date) - $StartTime
    if ($elapsed.TotalSeconds -ge $TimeoutSeconds) {
        Write-Warning "Timeout reached. VM '$vm' is not fully booted."
        return $false
    }

    if ($vm.State -ne 'Running') {
        Write-Host "[$vm] VM is not running yet. Waiting..." -ForegroundColor Cyan
        Start-Sleep -Seconds 5
        return Wait-VMFullyBooted -VMName $vm -TimeoutSeconds $TimeoutSeconds -StartTime $StartTime
    }

    $heartbeat = (Get-VMIntegrationService -VMName $vm -Name "Heartbeat").PrimaryStatusDescription

    if ($heartbeat -ne "OK" -and $heartbeat -ne "OKApplicationHealthy") {
        Write-Host "[$vm] Heartbeat not ready: $heartbeat. Waiting..." -ForegroundColor Cyan
        Start-Sleep -Seconds 5
        return Wait-VMFullyBooted -VMName $vm -TimeoutSeconds $TimeoutSeconds -StartTime $StartTime
    }

    try {
        $output = Invoke-Command -VMName $vm -Credential $domainAdminCredential -ScriptBlock { "pong" } -ErrorAction Stop
        if ($output -eq "pong") {
            Write-Host "[$vm] VM is fully booted and responsive!" -ForegroundColor Green
            return $true
        }
    }
    catch {
        Write-Host "[$vm] OS not responsive yet. Waiting..." -ForegroundColor Cyan
    }

    Start-Sleep -Seconds 5
    return Wait-VMFullyBooted -VMName $vm -TimeoutSeconds $TimeoutSeconds -StartTime $StartTime
}

# Function to set time zone
function getTimeZone {
    $timeZone = @("Eastern Standard Time", "Central Standard Time", "Mountain Standard Time", "Pacific Standard Time") | Out-GridView -Title "Select the time zone." -OutputMode Single
    if ($null -ne $timeZone) {
        # Script output to confirm selection
        Write-Host "You've selected the $timeZone." -ForegroundColor DarkYellow
        return $timeZone
    }else {
        # Recursive call if nothing is selected
        Write-Host "Nothing selected. Please make a selection."
        getTimeZone
    }
}

# Choose vhd or vhdx
function selectVHDType {
    # Choose vhd or vhdx
    $vhdType = @("vhd", "vhdx") | Out-GridView -Title "Choose the VHD Type" -OutputMode Single
    if (!($null -eq $vhdType)) {
        <# Action to perform if the condition is true #>
        Write-Host "You've choosen $vhdType." -ForegroundColor Yellow
        return $vhdType
    }else {
        # Recursively run selection if a choice is not made
        selectVHDType
    }
}

### END NESTED FUNCTIONS
# Convert a Windows ISO to a bootable VM and set a local admin password using $localAdminPassword variable
# Tested using Windows Server 2025, Windows 11 .iso files
function Build-Hyper-ConvertImage {
    # Check to see if Hyper-ConvertImage Is already installed
    if (Get-Module -ListAvailable -Name Hyper-ConvertImage) {
        # Action to perform if the module is installed
        Write-Host "Hyper-ConvertImage module is already installed." -ForegroundColor Green
    }
    else {
        # Optional: handle case where the module is not installed
        Write-Host "Hyper-ConvertImage not installed."
        try {
            Install-Module Hyper-ConvertImage -Scope CurrentUser
        }
        catch {
            <#Do this if a terminating exception happens#>
            Write-Host "Failed to install Hyper-ConvertImage." -ForegroundColor Red
        }
    }

    function CreateVirtualMachineStore2 {
        # Create Folder to store virtual machine, and let user choose if default location is not available
        $vmStore = "D:\VMs"
        if (Test-Path $vmStore\$vm) {
            Write-Host "Default VM store exists, creating folder for the vm..." -ForegroundColor Yellow
            Remove-Item -Path $vmStore\$vm -Recurse -Force
            mkdir $vmStore\$vm -Force
        }
        else {
            Write-Host "Default location not detected." -ForegroundColor DarkRed
            try {
                Write-Host "Trying to create $vmStore\$vm directory." -ForegroundColor Yellow
                mkdir $vmStore\$vm
            }
            catch {
                Write-Host "Unable to create $vmStore\$vm directory, please select a location for the virtual machine files." -ForegroundColor DarkRed
                #Pick Folder to Store virtual machine VHDX
                Write-Host "Select the Folder where you want to store the $vm VHDX files. NOTE THIS MAY OPEN A WINDOW BEHIND THE ACTIVE WINDOW." -ForegroundColor DarkBlue
                $vmDiskLocation = New-Object System.Windows.Forms.FolderBrowserDialog
                $null = $vmDiskLocation.ShowDialog()
                $vmStore = $vmDiskLocation.SelectedPath
                $vmStore = "$vmStore\$vm"
            }
        }
    }

    # Select server edition Core/Desktop Experience
    function Select-Edition {
        # Allows user to select either Server Core or Server Desktop Experience
        $edition = @("Core", "Desktop Experience") | Out-GridView -Title "Select the Windows Server Edition" -OutputMode Single
        if ($edition -eq "Core") {
            <# Action to perform if the condition is true #>
            Write-Host "You selected $edition." -ForegroundColor Yellow
            $edition = 1
            return $edition
        }
        elseif ($edition -eq "Desktop Experience") {
            <# Action when this condition is true #>
            Write-Host "You selected $edition." -ForegroundColor Yellow
            $edition = 2
            return $edition
        }
        else {
            # Recursively re-run script is $edition is $null
            Write-Host "Please make a selection." -ForegroundColor Red
            Select-Edition
        }
    }

    # Define Hostname
    $vm = getVMName

    # Define default vm store
    $vmStore = CreateVirtualMachineStore2

    # Run Select VHD type
    $vhdType = selectVHDType

    # Test $vmStore variable
    Write-Host "the path is $vmStore."

    $unattendXML = @"
<?xml version="1.0" encoding="utf-8"?>
<unattend xmlns="urn:schemas-microsoft-com:unattend">

  <settings pass="windowsPE">
    <component name="Microsoft-Windows-International-Core-WinPE" processorArchitecture="amd64"
               publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS"
               xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State"
               xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
      <SetupUILanguage>
        <UILanguage>en-US</UILanguage>
      </SetupUILanguage>
      <InputLocale>en-US</InputLocale>
      <SystemLocale>en-US</SystemLocale>
      <UILanguage>en-US</UILanguage>
      <UserLocale>en-US</UserLocale>
    </component>

    <component name="Microsoft-Windows-Setup" processorArchitecture="amd64"
               publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS"
               xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State"
               xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">

      <DiskConfiguration>
        <Disk wcm:action="add">
          <CreatePartitions>
            <CreatePartition wcm:action="add">
              <Type>EFI</Type>
              <Size>512</Size>
              <Order>1</Order>
            </CreatePartition>
            <CreatePartition wcm:action="add">
              <Type>MSR</Type>
              <Size>128</Size>
              <Order>2</Order>
            </CreatePartition>
            <CreatePartition wcm:action="add">
              <Type>Primary</Type>
              <Extend>true</Extend>
              <Order>3</Order>
            </CreatePartition>
          </CreatePartitions>
          <ModifyPartitions>
            <ModifyPartition wcm:action="add">
              <PartitionID>1</PartitionID>
              <Format>FAT32</Format>
              <Order>1</Order>
            </ModifyPartition>
            <ModifyPartition wcm:action="add">
              <PartitionID>2</PartitionID>
              <Order>2</Order>
            </ModifyPartition>
            <ModifyPartition wcm:action="add">
              <PartitionID>3</PartitionID>
              <Format>NTFS</Format>
              <Label>Windows</Label>
              <Order>3</Order>
            </ModifyPartition>
          </ModifyPartitions>
          <DiskID>0</DiskID>
          <WillWipeDisk>true</WillWipeDisk>
        </Disk>
      </DiskConfiguration>

      <ImageInstall>
        <OSImage>
          <InstallImageIndex>2</InstallImageIndex>
          <InstallTo>
            <DiskID>0</DiskID>
            <PartitionID>3</PartitionID>
          </InstallTo>
          <WillShowUI>OnError</WillShowUI>
          <InstallToAvailablePartition>false</InstallToAvailablePartition>
        </OSImage>
      </ImageInstall>

      <UserData>
        <AcceptEula>true</AcceptEula>
        <ProductKey>
          <WillShowUI>Never</WillShowUI>
          <Key>TVRH6-WHNXV-R9WG3-9XRFY-MY832</Key>
        </ProductKey>
      </UserData>
    </component>
  </settings>

  <settings pass="specialize">
    <component name="Microsoft-Windows-International-Core" processorArchitecture="amd64"
               publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS"
               xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State"
               xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
      <InputLocale>en-US</InputLocale>
      <SystemLocale>en-US</SystemLocale>
      <UILanguage>en-US</UILanguage>
      <UserLocale>en-US</UserLocale>
    </component>

    <component name="Microsoft-Windows-Shell-Setup" processorArchitecture="amd64"
               publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS"
               xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State"
               xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
      <TimeZone>Central Standard Time</TimeZone>
    </component>

    <component name="Microsoft-Windows-Deployment" processorArchitecture="amd64"
               publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS"
               xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State"
               xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
      <RunSynchronous>
        <RunSynchronousCommand wcm:action="add">
          <Description>Disable product key request</Description>
          <Order>1</Order>
          <Path>reg add "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Setup\OOBE" /v SetupDisplayedProductKey /t REG_DWORD /d 1 /f</Path>
        </RunSynchronousCommand>
      </RunSynchronous>
    </component>

    <component name="Microsoft-Windows-TerminalServices-LocalSessionManager" processorArchitecture="amd64"
               publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS"
               xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State"
               xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
      <fDenyTSConnections>true</fDenyTSConnections>
    </component>

    <component name="Microsoft-Windows-ServerManager-SvrMgrNc" processorArchitecture="amd64"
               publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS"
               xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State"
               xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
      <DoNotOpenServerManagerAtLogon>true</DoNotOpenServerManagerAtLogon>
    </component>
  </settings>

  <settings pass="oobeSystem">
    <component name="Microsoft-Windows-Shell-Setup" processorArchitecture="amd64"
               publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS"
               xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State"
               xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
      <AutoLogon>
        <Enabled>false</Enabled>
      </AutoLogon>

      <FirstLogonCommands>
        <SynchronousCommand wcm:action="add">
          <Order>1</Order>
          <CommandLine>powershell -ExecutionPolicy Bypass -File a:\setup.ps1</CommandLine>
          <Description>Enable WinRM service</Description>
          <RequiresUserInput>true</RequiresUserInput>
        </SynchronousCommand>
      </FirstLogonCommands>

      <UserAccounts>
        <AdministratorPassword>
          <Value>$localAdminPassword</Value>
          <PlainText>true</PlainText>
        </AdministratorPassword>
      </UserAccounts>

      <OOBE>
        <HideEULAPage>true</HideEULAPage>
        <HideLocalAccountScreen>true</HideLocalAccountScreen>
        <HideOEMRegistrationScreen>true</HideOEMRegistrationScreen>
        <HideOnlineAccountScreens>true</HideOnlineAccountScreens>
      </OOBE>
    </component>
  </settings>

  <cpi:offlineImage cpi:source="wim:c:/wims/install.wim#2" xmlns:cpi="urn:schemas-microsoft-com:cpi" />

</unattend>
"@

    # Dynamically Creates Unattend.xml file
    $unattendXML | Out-File -FilePath "$vmStore\unattend.xml" -Force -Encoding utf8

    # Run Functions to Define $params
    $vmISO = chooseISO
    $edition = Select-Edition
    $driveType = selectDriveType
    $driveType = $driveType.Trim("-")
    $vhdPath = "$vmStore\$vm-C.$vhdType"
    $disk1InGB = Get-vmVHD1Input

    # Convert the input GB amount to bytes
    $disk1InBytes = $disk1InGB * 1GB

    $params = @{
        SourcePath   = $vmISO
        Edition      = $edition
        VhdType      = $driveType
        VhdFormat    = "$vhdType"
        VhdPath      = $vhdPath
        DiskLayout   = "UEFI"
        SizeBytes    = $disk1InBytes
        UnattendPath = "$vmStore\unattend.xml"
    }

    # Runs Hyper-ConvertImage Function with defined params
    Convert-WindowsImage @params

    # Determines if secure boot will be enabled
    secureBootEnabled

    # Runs createVMSwitch function
    createVMSwitch

    # Select RAM
    $ramInBytes = selectRAM

    # Run chooseCPUCores function
    $selectedCores = $(chooseCPUCores)

    # Define New-VM Params
    $newVMParams = @{
        Name               = $vm
        MemoryStartupBytes = $ramInBytes
        SwitchName         = "HYPER-V-SWITCH"
        Generation         = 2
        BootDevice         = "VHD"
    }

    # Create the VM
    New-VM @newVMParams

    # Attach existing VHD
    Add-VMHardDiskDrive -VMName $vm -Path $vhdPath

    # Set VM to boot from the hard drive
    Set-VMFirmware -VMName $vm -FirstBootDevice (Get-VMHardDiskDrive -VMName $vm)

    # Configure Secure Boot for Generation 2 VM
    Set-VMFirmware -VMName $vm -EnableSecureBoot On -SecureBootTemplate "Microsoft Windows"

    # Sets the CPU cores setting
    Set-VMProcessor -VMName $vm -Count $selectedCores

    # Ensure the VM starts automatically when the host reboots
    Set-VM -Name $vm -AutomaticStartAction Start

    # Determines whether secure boot will be enabled
    enableVMTPM

    # Starts virtual machine
    Start-VM -Name $vm
    Start-Sleep -Seconds 20

    # Run enable vm integration function
    enableVMIntegration

    # Clean up unattend.xml
    Remove-Item $vmStore\unattend.xml -Force
}

# Create Generation 1 virtual machine 
# Can be Windows, Linux, etc - does not import unattend.xml - you must complete OOBE etc
function createVMGen1 {
    # Define Hostname of the virtual machine
    $vm = getVMName

    # Define default vm store
    $vmStore = "D:\VMs"

    # Define the location of the bootable .iso file
    $vmISO = $(chooseISO)

    # Create Folder to store virtual machine, and let user choose if default location is not available
    if (Test-Path $vmStore\$vm) {
        Write-Host "Default VM store exists, creating folder for the vm..." -ForegroundColor Yellow
        Remove-Item -Path $vmStore\$vm -Recurse -Force
        mkdir $vmStore\$vm -Force
    }else{
        Write-Host "Default location not detected." -ForegroundColor DarkRed
        try {
            Write-Host "Trying to create $vmStore\$vm directory." -ForegroundColor Yellow
            mkdir $vmStore\$vm
        }
        catch {
            Write-Host "Unable to create $vmStore\$vm directory, please select a location for the virtual machine files." -ForegroundColor DarkRed
            #Pick Folder to Store virtual machine VHDX
            Write-Host "Select the Folder where you want to store the $vm VHDX files. NOTE THIS MAY OPEN A WINDOW BEHIND THE ACTIVE WINDOW." -ForegroundColor DarkBlue
            $vmDiskLocation = New-Object System.Windows.Forms.FolderBrowserDialog
            $null = $vmDiskLocation.ShowDialog()
            $vmStore = $vmDiskLocation.SelectedPath
            $vmStore = "$vmStore\$vm"
        }
    }

    # Runs createVMSwitch function
    createVMSwitch

    # Runs select RAM function
    $ramInBytes = $(selectRAM)

    # Get the user's input
    $disk1InGB = $(Get-vmVHD1Input)

    # Convert the input GB amount to bytes
    $disk1InBytes = $disk1InGB * 1GB

    # Output the result
    Write-Host "You entered: $disk1InGB GB which is $disk1InBytes bytes." -ForegroundColor Yellow

    # Run chooseCPUCores function
    $selectedCores = $(chooseCPUCores)

    # Define New-VMParams
    $NewVMParams = @{
        Name               = $vm
        MemoryStartupBytes = $ramInBytes
        BootDevice         = "CD"
        SwitchName         = "HYPER-V-SWITCH"
        NewVHDPath         = "$vmStore\$vm\$vm.vhdx"
        NewVHDSizeBytes    = $disk1InBytes
    }

    # Creates the Virtual Machine Using Inputs defined earlier in the script
    New-VM @NewVMParams
    Set-VMDvdDrive -VMName $vm -Path "$vmISO"
    Set-VMProcessor -VMName $vm -Count $selectedCores

    # Ensure the VM starts automatically when the host reboots
    Set-VM -Name $vm -AutomaticStartAction Start

    # Starts virtual machine
    Start-VM -Name $vm
    Wait-VMFullyBooted

    # Run enable vm integration function
    enableVMIntegration
}

# Creates Generation 2 virtual machine
# Can be Windows, Linux, etc - does not import unattend.xml - you must complete OOBE etc
function createVMGen2 {
    # Define Hostname of the virtual machine
    $vm = getVMName

    # Define default vm store
    $vmStore = "D:\VMs"

    # Define the location of the bootable .iso file
    $vmISO = $(chooseISO)

    # Create Folder to store virtual machine, and let user choose if default location is not available
    if (Test-Path $vmStore\$vm) {
        Write-Host "Default VM store exists, creating folder for the vm." -ForegroundColor Yellow
        Remove-Item -Path $vmStore\$vm -Recurse -Force
        mkdir $vmStore\$vm -Force
    }else{
        # If default vm store is not detected, create
        Write-Host "Default location not detected." -ForegroundColor Red
        try {
            Write-Host "Trying to create $vmStore\$vm directory." -ForegroundColor Yellow
            mkdir $vmStore\$vm
        }
        catch {
            # Script message that will run if script was unable to create default directory and allow user to choose a location to store VM files
            Write-Host "Unable to create $vmStore\$vm directory, please select a location for the virtual machine files." -ForegroundColor DarkRed
            #Pick Folder to Store virtual machine VHDX
            Write-Host "Select the Folder where you want to store the $vm VHDX files. NOTE THIS OPENS A WINDOW BEHIND THE ACTIVE WINDOW." -ForegroundColor Red
            $vmDiskLocation = New-Object System.Windows.Forms.FolderBrowserDialog
            $null = $vmDiskLocation.ShowDialog()
            $vmStore = $vmDiskLocation.SelectedPath
            $vmStore = "$vmStore\$vm"
        }
    }

    # Determines if secure boot will be enabled
    secureBootEnabled

    # Runs createVMSwitch function
    createVMSwitch

    # Runs select RAM function
    $ramInBytes = $(selectRAM)

    # Get the user's input
    $disk1InGB = $(Get-vmVHD1Input)

    # Convert the input GB amount to bytes
    $disk1InBytes = $disk1InGB * 1GB

    # Output the result
    Write-Host "You entered: $disk1InGB GB which is $disk1InBytes bytes." -ForegroundColor Yellow

    # Run chooseCPUCores
    $selectedCores = $(chooseCPUCores)

    # Define New-VMParams
    $NewVMParams = @{
        Name               = $vm
        MemoryStartupBytes = $ramInBytes
        SwitchName         = "HYPER-V-SWITCH"
        NewVHDPath         = "$vmStore\$vm\$vm.vhdx"
        NewVHDSizeBytes    = $disk1InBytes
        Generation         = 2
    }

    # Creates the Virtual Machine Using Inputs defined earlier in the script
    New-VM @NewVMParams

    # Ensure the VM was created successfully before proceeding
    if (-not (Get-VM -Name $vm -ErrorAction SilentlyContinue)) {
    Write-Host "Failed to create VM. Exiting script." -ForegroundColor DarkRed
    }

    # Add a SCSI Controller for the DVD Drive (Required for Gen 2)
    Add-VMDvdDrive -VMName $vm -Path "$vmISO"

    # Configure Secure Boot for Generation 2 VM
    Set-VMFirmware -VMName $vm -EnableSecureBoot On -SecureBootTemplate "MicrosoftWindows"

   # Ensure the VM boots from the DVD (ISO) instead of the VHDX
    $dvdDrive = Get-VMDvdDrive -VMName $vm
    Set-VMFirmware -VMName $vm -FirstBootDevice $dvdDrive -EnableSecureBoot $secureBootEnabled

    # Sets the CPU cores setting
    Set-VMProcessor -VMName $vm -Count $selectedCores

    # Ensure the VM starts automatically when the host reboots
    Set-VM -Name $vm -AutomaticStartAction Start

    # Determines whether secure boot will be enabled
    enableVMTPM

    # Starts virtual machine
    Start-VM -Name $vm
    Start-Sleep -Seconds 20

    # Run enable vm integration function
    enableVMIntegration

    # Script output to remind user that OOBE needs to be completed before additional scripts can be run
    Write-Host "In order to run addtional scripts on this Windows virtual machine, complete OOBE first." -ForegroundColor Green
}

# Create Additional Virtual Disk Function
function createVHDX {
    # Allows the user to select a VM
    $vm = getVM

    # Function that allows the user to choose .vhd or .vhdx format
    function selectVHDType{
        $vhdType = @("vhd", "vhdx") | Out-GridView -Title "Select the virtual disk type." -OutputMode Single
        if ($null -ne $vhdType) {
            # Script message that confirms the input selection
            Write-Host "You've selected $vhdType for the new virtual disk type." -ForegroundColor Yellow
            if ($vhdType -eq "vhdx") {
                # This function will run if VHDX is selected
            }
            return $vhdType
        }else{
            # Script message that will run if a selection is not made
            Write-Host "No selection made, please select either vhd or vhdx." -ForegroundColor DarkRed

            # Recursively call selectVHDType if nothing was selected
            selectVHDType
        }
    }
    
    # Run selectVHDType function
    $vhdType = selectVHDType

    # Runs selectDriveType function
    $driveType = selectDriveType
    
    # Run selectDriveType function
    $driveType = selectDriveType

    function Get-vmVHD2Input {
        # Select OS disk size
        # Prompt the user to enter the number of GB for the OS Disk in GB
        $inputGB = Read-Host "Please enter the number of GBs you'd like the new vhd/vhdx to be"
    
        # Validate the input
        if ($inputGB -match '^\d+$' -and [int]$inputGB -gt 0) {
            # Script message to validate input from $inputGB and return size in GB
            Write-Host "You've entered ${inputGB}GB." -ForegroundColor Yellow
            $inputBytes = [int]$inputGB * 1GB
            Write-Host "Your disk will be $inputBytes bytes in length." -ForegroundColor Yellow
            return $inputBytes
        } else {
            # Validation that will rerun the function if a valid selection is not made
            Write-Host "Invalid input. Please enter a positive integer." -ForegroundColor DarkRed

            # Recursively call function again
            Get-vmVHD2Input
        }
    }

    function selectVHDPath {
        # Will check for the default path and if not will allow the user to select the path where the VHD/VHDX will be created in.
        if (Test-Path "D:\VMs\$vm"){
            # Script message that will run if Test-Path was successful
            $vhdPath = "D:\VMs\$vm"
            return $vhdPath
        }else{
            # Script message that will run if Test-Path was unsuccessful
            $vhdPath = New-Object System.Windows.Forms.FolderBrowserDialog
            $null = $vhdPath.ShowDialog()
            $vhdPath = $vhdPath.SelectedPath
            return $vhdPath
        }    
    }
    
    # Run selectVHDPath function
    $vhdPath = selectVHDPath

    # Runs the Get-vmVHD2Input Function and stores size in $vhdSize
    $inputBytes = Get-vmVHD2Input

    # Validates the path where the vhd/vhx will be saved
    if (Test-Path "$vhdPath") {
        # Script message that will run if vhd/vhx path is valid
        Write-Host "The path where the VHD/VHDX will be saved is: $vhdPath\." -ForegroundColor Yellow
        Write-Host "Checking to see if there is already an existing data .vhd or .vhdx disk." -ForegroundColor Yellow
        
        # Define intial dataInt value
        $dataInt = 1

        # Function to create VHD or VHDX
        function Get-NextAvailableDataVHD {
            param (
                [string]$vm,
                [string]$vhdType
            )
            # Define recommended base path
            $basePath = "$vhdPath"
            
            # while loop to increment $dataInt if disk exists
            while ($true) {
                $vhdName = "$vm-DATA$dataInt.$vhdType"
                $fullPath = Join-Path $basePath $vhdName
        
                if (-not (Test-Path $fullPath)) {
                    # Found the first available slot
                    Write-Host "No existing VHD found for $vhdName. Script will now create a $vhdType disk." -ForegroundColor Green
                    return $dataInt
                } else {
                    Write-Host "$vhdName already exists. Incrementing..." -ForegroundColor Yellow
                    $dataInt++
                }
            }
        }

        # Call the function
        $dataInt = Get-NextAvailableDataVHD -vm $vm -vhdType $vhdType
        Write-Host "Next available DATA $vhdType will be: $vm-DATA$dataInt.$vhdType"

        # Create the VHD/VHDX
        # Build dynamic parameter set
        $createVHDParams = @{
            Path      = "$vhdPath\$vm-DATA$dataInt.$vhdType"
            SizeBytes = $inputBytes
            $driveType = $true  # Dynamically adds -Fixed or -Dynamic
        }

        # Create the VHD using dynamic switch
        try {
            # Script will try to mount the VHD/VHDX to the virtual machine
            New-VHD @createVHDParams
            if ($?) {
                # Script message that will run if the disk creation was successful
                Write-Host "Successfully created $vhdType at $vhdPath\$vm-DATA$dataInt.$vhdType. Now attampting to attach the $vhdType to $vm." -ForegroundColor Green
                try {
                    Add-VMHardDiskDrive -VMName $vm -Path $vhdPath\$vm-DATA$dataInt.$vhdType
                    if ($?) {
                        # Script message that will run if Add-VMHardDiskDrive was successful
                        Write-Host "Successfully attached $vhdType to $vm." -ForegroundColor Green

                        # Starts Invoke command and attempts to mount the disk as a new volume inside the virtual machine
                        Invoke-Command -VMName $vm -Credential $domainAdminCredential -ScriptBlock{
                            # Get the disk number(s) of any disk with RAW partition style
                            $rawDisks = Get-Disk | Where-Object PartitionStyle -eq 'RAW'
                            $diskNumber = $rawDisks.Number

                            # Check if any RAW disks are found
                            if (-not $diskNumber) {
                                # No RAW disks detected
                                Write-Host "No RAW disks detected on this virtual machine." -ForegroundColor Red
                            }
                            else {
                                # RAW disks found, proceed with setup
                                Write-Host "The script detected disk number(s): $diskNumber with partition style: RAW." -ForegroundColor Yellow

                                foreach ($disk in $rawDisks) {
                                    $currentDiskNumber = $disk.Number
                                    try {
                                        # Attempt to bring the disk online
                                        Set-Disk -Number $currentDiskNumber -IsOffline $false
                                        if ($?) {
                                            Write-Host "Disk number $currentDiskNumber was set online." -ForegroundColor Green
                                            try {
                                                # Attempt to disable read-only
                                                Set-Disk -Number $currentDiskNumber -IsReadOnly $false
                                                if ($?) {
                                                    Write-Host "Successfully set IsReadOnly to false on disk number $currentDiskNumber." -ForegroundColor Green

                                                    # Assign an available drive letter to the RAW disk
                                                    function Set-DriveLetter {
                                                        param ([int]$diskNumber)
                                                    
                                                        # Check if the disk is already initialized and has a volume
                                                        $disk = Get-Disk -Number $diskNumber
                                                        
                                                        # Get all existing volume labels
                                                        $existingLabels = Get-Volume | Select-Object -ExpandProperty FileSystemLabel

                                                        # Base label name
                                                        $baseLabel = "DATA"
                                                        $label = $baseLabel
                                                        $counter = 1

                                                        # Loop to find an available label
                                                        while ($existingLabels -contains $label) {
                                                            $label = "$baseLabel$counter"
                                                            $counter++
                                                        }

                                                        # Proceed with partitioning and formatting
                                                        if ($disk.PartitionStyle -eq 'RAW') {
                                                            Initialize-Disk -Number $diskNumber -PartitionStyle GPT -PassThru |
                                                                New-Partition -UseMaximumSize -AssignDriveLetter |
                                                                Format-Volume -FileSystem NTFS -NewFileSystemLabel $label -Confirm:$false
                                                        }                       

                                                        # Get the partition and current drive letter (if any)
                                                        $partition = Get-Partition -DiskNumber $diskNumber | Where-Object DriveLetter
                                                    
                                                        if ($partition) {
                                                            Write-Host "Disk $diskNumber already has drive letter: $($partition.DriveLetter)" -ForegroundColor Yellow
                                                            return
                                                        }
                                                    
                                                        # Assign a new, available drive letter
                                                        $driveLetter = 'D'
                                                        while ($true) {
                                                            if (-not (Get-Volume | Where-Object DriveLetter -EQ $driveLetter)) {
                                                                Write-Host "Assigning available drive letter: $driveLetter" -ForegroundColor Cyan
                                                                $partition = Get-Partition -DiskNumber $diskNumber | Where-Object { -not $_.DriveLetter }
                                                                if ($partition) {
                                                                    Set-Partition -DriveLetter $partition.DriveLetter -NewDriveLetter $driveLetter
                                                                    Write-Host "Drive letter $driveLetter assigned to disk $diskNumber." -ForegroundColor Green
                                                                }
                                                                break
                                                            }
                                                            $driveLetter = [char]([int][char]$driveLetter + 1)
                                                        }
                                                    }
                                                    
                                                    # Call the function
                                                    Set-DriveLetter -diskNumber $currentDiskNumber
                                                }
                                            }
                                            catch {
                                                Write-Host "Failed to set IsReadOnly to false on disk number $currentDiskNumber." -ForegroundColor DarkRed
                                            }
                                        }
                                    }
                                    catch {
                                        Write-Host "Disk number $currentDiskNumber was not able to be set online." -ForegroundColor DarkRed
                                    }
                                }
                            }
                        }
                    }
                }
                catch {
                    # Script message that will run if unable to add newly-created disk to VM
                    Write-Host "Failed to attach $vhdType at path: $vhdPath\$vm-DATA$dataInt.$vhdType to $vm." -ForegroundColor DarkRed
                }
            }        
        }
        catch {
            # Script message that will run if New-VHD failed to run
            Write-Host "Failed to create $vhdType at path: $vhdPath\$vm-DATA$dataInt.$vhdType." -ForegroundColor DarkRed
        }
    }else{
        # script message that will run if default location is not detected
        Write-Host "Default VM store location not detected. Please select the folder where you'd like to save the VHD/VHDX files." -ForegroundColor DarkRed

        # Runs selectVHDPath again
        selectVHDPath
    }

    # Allows the script to be run again
    function createAnotherDisk {
        # Allows the user to select yes or no
        $createAnotherDisk = @("Yes", "No") | Out-GridView -Title "Would You Like to Create Another Disk?" -OutputMode Single
        if ($createAnotherDisk -eq "Yes") {
            # Script message that will run if Yes is selected
            Write-Host "You have selected $createAnotherDisk, the create disk function will run again." -ForegroundColor Yellow
            
            # Call function again
            createVHDX
        }elseif ($createAnotherDisk -eq "No") {
            # Script message that will run if No is selected
            Write-Host "You have selected not to create another virtual disk. The script will return to the main menu." -ForegroundColor Yellow
        }else{
            # Script message that will run if invalid input was entered and run createAnotherDisk function again
            Write-Host "You have entered invalid input. Please try again." -ForegroundColor DarkRed
            createAnotherDisk
        }
    }
    # Call createAnotherDisk function
    createAnotherDisk
}

# Apply General Settings (This is a work in progress)
function generalSettings{
    # Select VM
    $vm = getVM

    function getTimeZone {
        $timeZone = @("Eastern Standard Time", "Central Standard Time", "Mountain Standard Time", "Pacific Standard Time") | Out-GridView -Title "Select the time zone." -OutputMode Single
        if ($null -ne $timeZone) {
            # Script output to confirm selection
            Write-Host "You've selected the $timeZone." -ForegroundColor DarkYellow
            return $timeZone
        }else {
            # Recursive call if nothing is selected
            Write-Host "Nothing selected. Please make a selection."
            getTimeZone
        }
    }

    # Runs getTimeZone Function
    $timeZone = getTimeZone

    # Removes VM DVD Drive
    Remove-VMDvdDrive -VMName $vm -ControllerNumber 0 -ControllerLocation 1

    Invoke-Command -VMName $vm -Credential $domainAdminCredential -ScriptBlock{
        param($timeZone)
        # Update Help
        Update-Help
        Write-Host "Successfully updated help." -ForegroundColor Green

        # Sets Time Zone
        Set-TimeZone -Name "$timeZone"
        Write-Host "Set time zone to $timeZone." -ForegroundColor Green

        # Enables Dark Mode
        $path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize"
        New-ItemProperty -Path $path -Name AppsUseLightTheme -Value 0 -PropertyType DWord -Force
        New-ItemProperty -Path $path -Name SystemUsesLightTheme -Value 0 -PropertyType DWord -Force

        # Restarts Explorer to make changes take effect
        Stop-Process -Name explorer -Force
        Start-Process explorer
        Write-Host "Successfully enabled dark mode system-wide." -ForegroundColor Green

        # Disable IE ESC for both Admin and Non-Admin users
        function Disable-IEESC {
            $AdminKey = "HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components\{A509B1A7-37EF-4b3f-8CFC-4F3A74704073}"
            $UserKey = "HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components\{A509B1A8-37EF-4b3f-8CFC-4F3A74704073}"
            Set-ItemProperty -Path $AdminKey -Name "IsInstalled" -Value 0
            Set-ItemProperty -Path $UserKey -Name "IsInstalled" -Value 0
            Stop-Process -Name Explorer
            Write-Host "IE Enhanced Security Configuration (ESC) has been disabled." -ForegroundColor Green
        }
        # Runs Disable IE ESC Function
        Disable-IEESC

        # SET DISPLAY to 1920x1080 here
        try {
            Set-DisplayResolution -Width 1920 -Height 1080 -Force
            if ($?) {
                # Script message that will run if display resolution changes were successful.
                Write-Host "Successfully set display resolution on $vm to 1920x1080." -ForegroundColor Green
            }
        }
        catch {
            # Will run if display resolution changes were not successful.
            Write-Host "Failed to change display resolution to 1920x1080 on $vm." -ForegroundColor DarkRed
        }

    } -ArgumentList $timeZone
}

# Renames computer not applicable on Windows 11
# WORKING
function renameComputer {
    # Run getVM function to set the global $vm variable
    $vm = getVM

    # Runs
    Invoke-Command -VMName $vm -Credential $localAdminCredential -ScriptBlock{
        try {
            Rename-Computer -NewName $using:vm -Restart
            Write-Host "Successfully renamed virtual machine, rebooting." -ForegroundColor Green
        }
        catch {
            Write-Host "Failed to rename virtual machine." -ForegroundColor DarkRed
        }       
    }
}

# Joins windows VM to the domain
# WORKING
function joinDomain {
    # Run getVM function to get the VM name
    $vm = getVM

    # Convert SecureString to plain text for secure transmission
    $plainPassword = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
        [Runtime.InteropServices.Marshal]::SecureStringToBSTR($domainAdminPassword)
    )

    # Run the join command inside the VM
    Invoke-Command -VMName $vm -Credential $localAdminCredential -ScriptBlock {
        param ($domainJoinName, $domainAdminUsername, $plainPassword)

        # Script output to verify that the $domainJoinName variable was passed correctly via Invoke-Command
        Write-Host "Preparing to join $domainJoinName." -ForegroundColor Yellow

        try {
            # Convert plain text password back to SecureString inside the VM
            $securePassword = ConvertTo-SecureString -String $plainPassword -AsPlainText -Force

            # Recreate the credential object inside the VM
            $domainAdminCredential = New-Object System.Management.Automation.PSCredential ($domainAdminUsername, $securePassword)

            # Join the domain
            Add-Computer -DomainName $domainJoinName -Credential $domainAdminCredential -Restart -Force
            if ($?) {
                # Script output that will run if computer was successfully joined to the domain
                Write-Host "Successfully joined $env:COMPUTERNAME to the domain $domainJoinName." -ForegroundColor Green
            }  
        }
        catch {
            # Script output that will run if the computer failed to join the domain
            Write-Host "Failed to join $env:COMPUTERNAME to the domain: $_." -ForegroundColor DarkRed
        }
    } -ArgumentList $domainJoinName, $domainAdminUsername, $plainPassword  # Pass plain password for re-encryption
}

# Install MSI Function
# WORKING
function installMSI {
    # Get VM
    $vm = getVM

    # Sets the path where the .msi files will be copied to
    $destinationPath = "C:\temp"

    # Ensure the destination folder exists on the VM
    Invoke-Command -VMName $vm -Credential $domainAdminCredential -ScriptBlock {
        param ($destinationPath)

        try {
            # Creates destination path if it doesn't already exist
            if (-not (Test-Path -Path $destinationPath)) {
                Write-Host "Creating $destinationPath on VM."
                mkdir $destinationPath -Force
            } else {
                # Script output that will run if destination path already exists.
                Write-Host "$destinationPath already exists." -ForegroundColor Yellow
            }
        }
        catch {
            # Script output that will run if script fails to create destination path on VM
            Write-Host "Failed to create $destinationPath on VM." -ForegroundColor DarkRed
        }
    } -ArgumentList $destinationPath  

    # Run Pick MSI Function and capture return values
    $msiData = pickMSI
    $installerFile = $msiData["installerFile"]
    $fileName = $msiData["fileName"]

    # Not Sure if this is needed
    # Ensure variables are set
    if (-not $installerFile -or -not $fileName) {
        Write-Host "No file was selected. Exiting."
        return
    }

    # Check if the file already exists on the VM using Invoke-Command
    $fileExists = Invoke-Command -VMName $vm -Credential $domainAdminCredential -ScriptBlock {
        param ($destinationPath, $fileName, $domainAdminCredential)
        Test-Path -Path "$destinationPath\$fileName"
    } -ArgumentList $destinationPath, $fileName

    if ($fileExists) {
        Write-Host "$fileName already exists at $destinationPath on VM, skipping copy." -ForegroundColor Yellow
    } else {
        # Copy the file to the VM
        try {
            Copy-VMFile -VMName $vm -SourcePath $installerFile -DestinationPath "$destinationPath\$fileName" -FileSource Host -CreateFullPath -Force
            Write-Host "Successfully copied $fileName to $destinationPath on $vm." -ForegroundColor Green
        }
        catch {
            # Script output that will run if script fails to copy file to VM
            Write-Host "Failed to copy $fileName to $destinationPath on $vm." -ForegroundColor DarkRed
            return
        }
    }

    # Install MSI on the VM
    Invoke-Command -VMName $vm -Credential $domainAdminCredential -ScriptBlock {
        param ($destinationPath, $fileName, $domainAdminCredential)

        try {
            # Script message to validate that $fileName is being passed correctly inside Invoke-Command session
            Write-Host "Installing $fileName." -ForegroundColor Yellow
            # Attemps to run the .msi
            Start-Process -FilePath "msiexec.exe" -ArgumentList "/i `"$destinationPath\$fileName`" /qn /norestart" -Wait -NoNewWindow
            if ($?) {
                # Script message that will run if the .msi was successfully installed
                Write-Host "$fileName installed successfully." -ForegroundColor Green
            }
            # Cleanup: Delete the MSI file after installation
            Remove-Item -Path "$destinationPath\$fileName" -Force -ErrorAction SilentlyContinue
            Write-Host "$fileName has been deleted from $destinationPath after installation." -ForegroundColor Green
        }
        catch {
            # Script message that will run if the .msi package failed to install on the VM
            Write-Host "Failed to install $fileName on $env:COMPUTERNAME." -ForegroundColor DarkRed
        }
    } -ArgumentList $destinationPath, $fileName, $domainAdminCredential
}

# Function to change IP Address
# WORKING
function changeIPAddress {
    # Run getVM function
    $vm = getVM

    # Out-Grid view to select server role
    $serverRole = @("Domain Controller", "File Server", "Application Server", "Other") | Out-GridView -Title "Select $vm 's role." -OutputMode Single

    if ($serverRole -eq "Domain Controller") {
        # The default octet for a domain controller is .201
        $lastOctet = "201"
    } 
    elseif ($serverRole -eq "File Server") {
        # The default octet for a file server is .202
        $lastOctet = "202"
    } 
    elseif ($serverRole -eq "Application Server") {
        # The default octet for a web server is .203
        $lastOctet = "203"
    } 
    else {
        # If the server is "Other" then return $null
        $lastOctet = "210"
    }

    # Start of Invoke Command on selected VM
    Invoke-Command -VMName $vm -Credential $domainAdminCredential -ScriptBlock{
        param (
            $lastOctet, $serverRole
        )
        function getIPAddress {
            # Gets IP address of the server on the current network in Invoke-Command session
            $ipAddress = (Get-NetIPAddress -InterfaceAlias Ethernet -AddressFamily IPv4).IPv4Address
            return $ipAddress
        }

        # This code block will attempt to set the Ethernet adapter to DHCP if a static IP address is alredy configured
        if ([bool]((Get-NetIPConfiguration -InterfaceAlias "Ethernet").IPv4Address | Where-Object { $_.PrefixOrigin -eq 'Dhcp' })) {
            # Script message that will run if the VM adapter is already in DHCP mode
            Write-Host "$env:COMPUTERNAME does not have a static IP address." -ForegroundColor Yellow
        }else{
            # Script message that will run if the VM adapter has a static IP address
            Write-Host "$env:COMPUTERNAME has a static IP address." -ForegroundColor Yellow
            # Removes the current IP Address
            Remove-NetIPAddress -InterfaceAlias Ethernet -Confirm:$false
            Remove-NetRoute -InterfaceAlias Ethernet -Confirm:$false
            Set-NetIPInterface -InterfaceAlias "Ethernet" -Dhcp Enabled
            if($?){
                # Script message that will run if script was able to enable DHCP on the VM adapter
                Restart-NetAdapter -Name "Ethernet" -Confirm:$false
                Write-Host "Successfully set $env:COMPUTERNAME's Ethernet adapter to DHCP." -ForegroundColor Green
                Start-Sleep -Seconds 10
            }else{
                # Script Message that will run if script failed to enable DHCP mode on the VM adapter
                Write-Host "Unable to change $env:COMPUTERNAME's Ethernet interfce to DHCP mode." -ForegroundColor DarkRed
            }
        }
        
        # Runs function and returns IP Address as $ipAddress
        $ipAddress = getIPAddress
        Write-Host "$env:COMPUTERNAME's IP address is: $ipAddress." -ForegroundColor Yellow

        function Get-SubnetMask {
            # Gets the subnet prefix length of the Ethernet interface
            $prefixLength = (Get-NetIPAddress -InterfaceAlias Ethernet -AddressFamily IPv4).PrefixLength
        
            # Convert prefix length to binary mask
            $binaryMask = ("1" * $prefixLength).PadRight(32, "0")
        
            # Split binary mask into 8-bit octets and convert to decimal
            $octets = $binaryMask -split "(.{8})" | Where-Object { $_ -match "^\d{8}$" } | ForEach-Object { [convert]::ToInt32($_, 2) }
        
            # Join octets to form subnet mask
            $subnetMask = $octets -join "."
            return @($prefixLength, $subnetMask)
        } 
        
        # Runs the getIPAddress function and returns output as $prefixLength and $subnetMask
        $prefixLength, $subnetMask = Get-SubnetMask
        Write-Host "Your subnet mask is: $subnetMask." -ForegroundColor Yellow
        Write-Host "Your prefix length is $prefixLength." -ForegroundColor Yellow

        function getDefaultGateway {
            $defaultGateway = Get-NetRoute -DestinationPrefix "0.0.0.0/0" | Select-Object -ExpandProperty "NextHop"
            return $defaultGateway
        }

        # Runs the getDefaultGateway function and returns output as $defaultGateway
        $defaultGateway = getDefaultGateway
        Write-Host "Your default gateway is: $defaultGateway." -ForegroundColor Yellow

        function getSubnetID {
            param (
                [string]$ipAddress,
                [string]$subnetMask
            )
        
            # Convert IP Address and Subnet Mask into arrays of integers
            $ipBytes = $ipAddress -split '\.' | ForEach-Object {[int]$_}
            $maskBytes = $subnetMask -split '\.' | ForEach-Object {[int]$_}
        
            # Perform bitwise AND operation to get the Subnet ID
            $subnetID = @()
            for ($i = 0; $i -lt 4; $i++) {
                $subnetID += $ipBytes[$i] -band $maskBytes[$i]
            }
        
            # Join the result into a dotted decimal format
            return ($subnetID -join ".")
        }
        
        # Get DNS Server Address
        function getDNSServerAddress {
            # Gets the DNS server and stores as $dnsServerAddress
            $dnsServerAddress = (Get-DnsClientServerAddress -InterfaceAlias Ethernet -AddressFamily IPv4).ServerAddresses
            return $dnsServerAddress
        }

        # Runs getDNSServerAddress and stores as $dnsServerAddress
        $dnsServerAddress = getDNSServerAddress
        Write-Host "The DNS server address is $dnsServerAddress." -ForegroundColor Yellow

        # Runs the getSubnetID function and returns output as $subnetID
        $subnetID = getSubnetID -ipAddress $ipAddress -subnetMask $subnetMask
        Write-Host "Your subnet ID is: $subnetID." -ForegroundColor Yellow

        # Add the selected last octet to the subnet ID
        $setIPAddress = ($subnetID -replace '\.\d+$', '') + "." + $lastOctet
        Write-Host "Recommended IP Address for the $serverRole is $setIPAddress." -ForegroundColor Yellow

        # Add the fall back IP Address to start pinging if the recommended IP Address is in use
        $fallbackIPAddress = ($subnetID -replace '\.\d+$', '') + "." + "210"

        function autoSetIPAddress {
                # Attempts to ping the recommended IP Address based on the selected server role
                if((Test-NetConnection -ComputerName $setIPAddress).PingSucceeded){
                    # Script message that will run if the recommended IP address for the selected server type is already in use by another device
                    Write-Host "$setIPAddress is already in use by another device, checking for the next available IP Address." -ForegroundColor Yellow
                    function findAvailableIPAddress {
                        
                        # Script will now try to ping $fallbackIPAddress
                        Write-Host "Pinging $fallbackIPAddress." -ForegroundColor Yellow
                    
                        if(!(Test-NetConnection -ComputerName $fallbackIPAddress).PingSucceeded) {
                            # Script output that will run if the ping to $fallbackIPAddress succeeded
                            Write-Host "$fallbackIPAddress appears to be available." -ForegroundColor Yellow
        
                            # Script message that will run if the recommended IP address is not responding to ping and is available
                            Write-Host "The recommended IP address: $fallbackIPAddress for server role: $serverRole is not responding to ping and appears to be available, setting IP Address to $fallbackIPAddress on $env:COMPUTERNAME now." -ForegroundColor Yellow

                            # Sets IP Address on the server
                            New-NetIPAddress -InterfaceAlias Ethernet -IPAddress $fallbackIPAddress -PrefixLength $prefixLength -DefaultGateway $defaultGateway
                            Set-DnsClientServerAddress -InterfaceAlias Ethernet -ServerAddresses ($dnsServerAddress)

                            # Sets $fallbackIPAddress back to set IP Address so the recursive ping starts where it left off
                            #$fallbackIPAddress = $setIPAddress
                            return $fallbackIPAddress
        
                        } elseif((Test-NetConnection -ComputerName $fallbackIPAddress).PingSucceeded) {
                            # Script output that will run if the ping to $fallbackIPAddress failed
                            Write-Host "A device exists at $fallbackIPAddress, attempting to ping the next IP address in the subnet." -ForegroundColor Red
                    
                            # Increment the last octet of the IP address
                            $octets = $fallbackIPAddress -split "\."
                            $octets[3] = [int]$octets[3] + 1
                            $fallbackIPAddress = $octets -join "."
        
                            # Verify that the $fallbackIPAddress variable was updated
                            Write-Host "The next IP address in the block is: $fallbackIPAddress." -ForegroundColor Yellow
        
                            # Recursively call the function with the updated IP
                            findAvailableIPAddress
                            return $fallbackIPAddress
                        } -ArgumentList $fallbackIPAddress, $setIPAddress
                    } 
                    
                    # Call function with the initial fallback IP
                    $fallbackIPAddress = findAvailableIPAddress
                    
                }else{
                    # Script message that will run if the recommended IP address is not responding to ping and is available
                    Write-Host "The recommended IP address: $setIPAddress for the $serverRole is not responding to ping and appears to be available, setting IP Address to
                    $setIPAddress on $env:COMPUTERNAME now." -ForegroundColor Yellow

                    # Sets IP Address on the server
                    New-NetIPAddress -InterfaceAlias Ethernet -IPAddress $setIPAddress -PrefixLength $prefixLength -DefaultGateway $defaultGateway
                    Set-DnsClientServerAddress -InterfaceAlias Ethernet -ServerAddresses ($dnsServerAddress)

                    # Sets $fallbackIPAddress back to set IP Address so the recursive ping starts where it left off
                    #$fallbackIPAddress = $setIPAddress
                    return $fallbackIPAddress
                } 
        }
        autoSetIPAddress
    } -ArgumentList $lastOctet, $serverRole
} 

# Install AD DS and DHCP Server Roles
# WORKING
function install_ADDS_DHCP {
    # Get VM selection
    $vm = getVM

    # Convert SecureString to plain text for secure transmission
    $plainPassword = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
        [Runtime.InteropServices.Marshal]::SecureStringToBSTR($domainAdminPassword)
    )

    # Execute command inside VM with correct argument passing
    Invoke-Command -VMName $vm -Credential $domainAdminCredential -ScriptBlock {
        param($domainJoinName, $domainAdminUsername, $plainPassword)

        # Checks to see if DHCP is enabled and if it is, the function will end
        if ((Get-NetIPConfiguration | Select-Object -ExpandProperty NetIPv4Interface | Select-Object InterfaceAlias,DHCP).DHCP -eq "Disabled") {
            Write-Host "Trying to promote $env:COMPUTERNAME to a Domain Controller in the $domainJoinName domain." -ForegroundColor Yellow
            try {
                # Install AD DS and DHCP roles
                Install-WindowsFeature -Name AD-Domain-Services, DHCP -IncludeManagementTools
                if ($?) {
                    # Script message that will run if AD-Domain-Services and DHCP were installed
                    Write-Host "Installed AD Domain Services and DHCP." -ForegroundColor Green
                    # Promote the server to a domain controller
                    Import-Module ADDSDeployment
                    Write-Host "Imported ADDSDeployment module." -ForegroundColor Green
                    if ($?) {
                        # Authorize the DHCP server in AD
                        Add-DhcpServerInDC
                        Write-Host "Authorized DHCP server in Active Directory." -ForegroundColor Green
                        if ($?) {
                            # Promote the server to a domain controller
                            # Convert plain text password back to SecureString inside the VM
                            $securePassword = ConvertTo-SecureString -String $plainPassword -AsPlainText -Force

                            # Recreate the credential object inside the VM
                            $domainAdminCredential = New-Object System.Management.Automation.PSCredential ($domainAdminUsername, $securePassword)
                            
                            # Attempt to promote server to domain controller
                            Install-ADDSDomainController -Credential $domainAdminCredential -InstallDns -DomainName $domainJoinName -Confirm:$false -Force
                            if ($?) {
                                # Script message will run if server was successfully promoted to a domain controller
                                Write-Host "$env:COMPUTERNAME is now promoted to a Domain Controller and will reboot." -ForegroundColor Yellow
                            }
                        }else{
                            # Script message will run if unable to promote server to domain controller
                            Write-Host "Failed to install ADDS, DHCP and promote to domain controller. Error: $_." -ForegroundColor DarkRed
                        }
                    }else{
                        # Script message will run if unable to authorize DHCP server in AD
                        Write-Host "Unable to authorize $env:COMPUTERNAME as DHCP server in $domainJoinName Active Directory." -ForegroundColor DarkRed
                    }
                }else{
                    # Script message that will run if AD DS and DHCP roles were not installed
                    Write-Host "Unable to install AD DS and DHCP server roles." -ForegroundColor DarkRed
                }
            }
            catch {
                Write-Host "Failed to install ADDS, DHCP and promote to domain controller. Error: $_." -ForegroundColor DarkRed
            }
        }else{
            # Script output that will run if DHCP is not enabled
            Write-Host "DHCP is enabled on $vm, try running the setStaticIPAddress function first." -ForegroundColor DarkRed
        }    
    } -ArgumentList $domainJoinName, $domainAdminUserName, $plainPassword
}

# Copy DHCP Scope settings from old DHCP server
# NOT WORKING
function copy_DHCP_Scope {
    
    # runs getVM function
    $vm = getVM

    Invoke-Command -VMName $vm -Credential $domainAdminCredential -ScriptBlock{
        function copyDHCPScope {
            # Authorize the DHCP server in AD
            Add-DhcpServerInDC
        
            # Query an existing DHCP server for active scopes
            $sourceDhcpServer = Read-Host "Enter the hostname of the existing DHCP server"
            $scopes = Get-DhcpServerv4Scope -ComputerName $sourceDhcpServer
        
            # Ensure at least one scope exists
            if ($scopes.Count -eq 0) {
            Write-Host "No active scopes found on $sourceDhcpServer. Exiting." -ForegroundColor Red
            exit
            }
        
            Write-Host "Copying DHCP scopes from $sourceDhcpServer."
        
            # Loop through each scope and recreate it on the new server
            foreach ($scope in $scopes) {
            Add-DhcpServerv4Scope -Name $scope.Name `
                                  -StartRange $scope.StartRange `
                                  -EndRange $scope.EndRange `
                                  -SubnetMask $scope.SubnetMask `
                                  -State Inactive
        
            Write-Host "Created DHCP scope: $($scope.Name) ($($scope.StartRange) - $($scope.EndRange))."
            
            # Copy options from the existing DHCP scope
            $options = Get-DhcpServerv4OptionValue -ComputerName $sourceDhcpServer -ScopeId $scope.ScopeId
            foreach ($option in $options) {
                Set-DhcpServerv4OptionValue -ScopeId $scope.ScopeId `
                                            -OptionId $option.OptionId `
                                            -Value $option.Value
                }   
            }
            # Copy DHCP reservations
            Write-Host "Copying DHCP reservations for scope: $($scope.Name)."
            $reservations = Get-DhcpServerv4Reservation -ComputerName $sourceDhcpServer -ScopeId $scope.ScopeId
            foreach ($reservation in $reservations) {
                Add-DhcpServerv4Reservation -ComputerName $sourceDhcpServer `
                                            -ScopeId $scope.ScopeId `
                                            -IPAddress $reservation.IPAddress `
                                            -ClientId $reservation.ClientId `
                                            -Description $reservation.Description `
                                            -Name $reservation.Name `
                                            -Type $reservation.Type
                Write-Host "Created DHCP reservation: $($reservation.Name) - $($reservation.IPAddress)."
                
            Write-Host "DHCP scopes copied and applied successfully."
        
            # Disable (Deactivate) the DHCP scope
            Set-DhcpServerv4Scope -ScopeId $scope.ScopeId -State Inactive
            Write-Host "DHCP scope $($scope.Name) has been disabled." 
            }
        }
    } -ArgumentList $domainJoinName
}
# Provision file server function
function Copy-EnumerateFileShares {
    # Run getVM function
    $vm = getVM

    # Start invoke command on vm
    Invoke-Command -VMName $vm -Credential $domainAdminCredential -ScriptBlock{
        param ($vm)
        # Check to see if File-Services role is installed
        if ((Get-WindowsFeature -Name File-Services).Installed) {
            # Script message that will run if File-Services role is already installed
            Write-Host "File-Services are already installed on $vm." -ForegroundColor Yellow
        }else {
            # Script message that will run if File-Services is not installed
            Write-Host "File-Services are not installed on $vm." -ForegroundColor Yellow
            $fileServerFeatures = @("File-Services", "FS-DFS-Namespace", "FS-DFS-REPLICATION")
            function installFileServicesRoles {
                try {
                    foreach ($service in $fileServerFeatures){
                        Install-WindowsFeature $service
                        # Script message that will run if services were successfully installed
                        Write-Host "Successfully installed $service on $vm." -ForegroundColor Green
                    }
                }
                catch {
                    # Script message that will run if $service failed to install
                    Write-Host "Unable to install $service on $vm." -ForegroundColor DarkRed
                }
                
            }
            # Run installFileServicesRoles
            installFileServicesRoles
        }
        function pickOldFileServer {
            $oldFileServer = Read-Host "Enter the FQDN of the old file server."
            if ($null -eq $oldFileServer) {
                # Script message that will run if nothing was entered
                Write-Host "You have not provided any input. Please try again." -ForegroundColor Red
    
                # Recursively call pickOldFileServer function
                pickOldFileServer
            }else{
                if((Test-NetConnection -ComputerName $oldFileServer).PingSucceeded){
                    # Script message that will run if Test-NetConnection to the old file server succeeded
                    Write-Host "Test-NetConnection to $oldFileServer succeeded." -ForegroundColor Green
                    return $oldFileServer
                }else{
                    # Script message that will run if Test-NetConnection to the old file server failed
                    Write-Host "Test-NetConnection to $oldFileServer failed. Please check hostname and/or networking." -ForegroundColor DarkRed
    
                    # Recursively call pickOldFileServerFunction
                    pickOldFileServer
                }
            }
        }

        # Runs pickOldFileServer
        $oldFileServer = pickOldFileServer

        Write-Host "Testing variable $oldFileServer."

        # STEP 1: Get share info and NTFS ACLs from the source server
        $shareInfo = Invoke-Command -ComputerName $oldFileServer -Credential $using:domainAdminCredential -ScriptBlock {
            Get-SmbShare | Where-Object { $_.Name -notlike '*$' } | ForEach-Object {
                $acl = Get-Acl $_.Path
                [PSCustomObject]@{
                    Name         = $_.Name
                    Path         = $_.Path
                    Description  = $_.Description
                    FullAccess   = $_.FullAccess
                    ChangeAccess = $_.ChangeAccess
                    ReadAccess   = $_.ReadAccess
                    NtfsAcl      = $acl
                }
            }
        }
        
        # STEP 2: Process each share locally
        $systemShares = @('NETLOGON', 'SYSVOL')
        
        foreach ($share in $shareInfo) {
            $shareName = $share.Name.ToUpper()
        
            if ($systemShares -contains $shareName) {
                Write-Host "Skipping system share '$shareName' (auto-detected)." -ForegroundColor Yellow
                continue
            }
        
            $create = Read-Host "Do you want to create the share '$shareName' on this server? (yes/no)"
            if ($create.ToLower() -ne 'yes') {
                Write-Host "Skipping share '$shareName'" -ForegroundColor Yellow
                continue
            }
        
            $customPath = Read-Host "Enter the local path where you'd like the share '$shareName' to be created (leave blank for default: D:\$shareName)"
            if ([string]::IsNullOrWhiteSpace($customPath)) {
                $customPath = "D:\$shareName"
            }
        
            # Ensure the destination folder exists
            if (-not (Test-Path -Path $customPath)) {
                New-Item -Path $customPath -ItemType Directory -Force | Out-Null
            }
        
            # Apply NTFS ACL
            try {
                Set-Acl -Path $customPath -AclObject $share.NtfsAcl
                Write-Host "Applied NTFS permissions to '$customPath'" -ForegroundColor Cyan
        
                # Optional: Verify
                $appliedAcl = Get-Acl -Path $customPath
                Write-Host "`nVerified ACL for '$customPath':" -ForegroundColor Magenta
                $appliedAcl.Access | Format-Table IdentityReference, FileSystemRights, AccessControlType -AutoSize
                Write-Host ""
            } catch {
                Write-Host "Failed to set NTFS ACL for '$shareName': $_" -ForegroundColor Red
            }
        
            # Create the share with original SMB permissions
            $params = @{
                Name        = $share.Name
                Path        = $customPath
                Description = $share.Description
            }
        
            if ($share.FullAccess)   { $params.FullAccess   = $share.FullAccess }
            if ($share.ChangeAccess) { $params.ChangeAccess = $share.ChangeAccess }
            if ($share.ReadAccess)   { $params.ReadAccess   = $share.ReadAccess }
        
            try {
                New-SmbShare @params | Out-Null
                Write-Host "Created share '$shareName' at '$customPath' with original permissions." -ForegroundColor Green
            } catch {
                Write-Host "Failed to create share '$shareName': $_" -ForegroundColor Red
            }
        
            # STEP 3: Use robocopy to copy data from old file server to new path
            $sourcePath = Join-Path "\\$oldFileServer" $share.Name
            $robocopyLog = "$env:TEMP\robocopy-$($share.Name).log"
        
            Write-Host "Starting data copy from $sourcePath to $customPath..."
            robocopy $sourcePath $customPath /E /COPYALL /R:2 /W:5 /LOG:$robocopyLog
        
            Write-Host "Data copy complete. Log saved to: $robocopyLog"
        }

        
    } -ArgumentList $vm
}

# Delete VM Function
function deleteVM {
    # Select VM and power off
    $vm = getVM
    if($null -eq $vm){
        Write-Host "You did not select a virtual machine, please make a selection" -ForegroundColor DarkRed
        deleteVM
    }

    function cleanupFiles {
        Stop-VM -Name $vm -TurnOff -Force
        Write-Host "Powering off $vm, start 15 second sleep..." -ForegroundColor Yellow
        Start-Sleep -Seconds 15

        # Clean up VM files
        if (Test-Path -Path D:\VMs\$vm) {
            Write-Host "$vm directory detected, deleting now..." -ForegroundColor Green
            try {
                Remove-Item -Path D:\VMs\$vm -Recurse -Force
                try{
                Remove-VM -Name $vm -Force
                Write-Host "Deleted $vm from Hyper-V Management" -ForegroundColor Green
                }
                catch{
                    Write-Host "Unable to remove $vm from Hyper-V management" -ForegroundColor DarkRed
                }
            }
            catch {
                Write-Host "Failed to delete $vm from this Hyper-V host. Please check $vm state." -ForegroundColor DarkRed
            }   
        }else{
            Write-Host "$vm not located in default store. Please select folder where the $vm files are located." -ForegroundColor Red
            $deleteVMFolder = New-Object System.Windows.Forms.FolderBrowserDialog
            $null = $deleteVMFolder.ShowDialog()
            $deleteVMFolder = $deleteVMFolder.SelectedPath
            Write-Host "You've selected $deleteVMFolder" -ForegroundColor Yellow
            try {
                Remove-Item -LiteralPath $deleteVMFolder -Recurse -Force
                Write-Host "Successfully deleted $vm from $deleteVMFolder." -ForegroundColor Green
                try{
                Remove-VM -Name $vm -Force
                Write-Host "Deleted $vm from Hyper-V Management." -ForegroundColor Green
                }
                catch{
                    Write-Host "Unable to remove $vm from Hyper-V management." -ForegroundColor Green
                }
            }
            catch {
                Write-Host "Unable to delete $vm VM files from $deletedVMFolder." -ForegroundColor Green
            }
        }   
    }

    # Confirm if you want to delete the VM
    function Choose{
        $choice = Read-Host "Do you really want to delete $vm? (yes/no)" 
        if ($choice -eq "yes") {
            <# Action to perform if the condition is true #>
            Write-Host "You've selected $choice." -ForegroundColor Cyan
            cleanupFiles
        }elseif ($choice -eq "no") {
            <# Action to perform if the condition is true #>
            Write-Host "You've selected $choice." -ForegroundColor Red
        }else {
            <# Action when all if and elseif conditions are false #>
            Write-Host "Invalid or no selection made. Please enter your choice." -ForegroundColor DarkRed
            Choose
        }
    }
    # Run Choose Function
    Choose
}

## End Functions

## Start Script

# Begin Pre-Script Message
Write-Host "This script assumes you have your Windows and Linux server .iso images, and your RMM agent and .msi files on the local disk.

If you do not have both of these items in order, choose No at the prompt and the script will exit.

Make sure you create any Windows server VM as a GEN 2 VM, Gen 1 is mainly deprecated or used when creating Linux servers

This script is designed to run in Powershell ISE as an Administrator.

When you create each windows VM, make the local administrator credentials the same on each VM or this script will break.

Feel free to make a simple username and password, the cleanup script will change it afterward" -ForegroundColor Red
# End Pre Script Message

function chooseFunction {
    $choice = Read-Host "Would you like to run a script? Yes/No"
    # This function keeps running as long as you choose "yes"
    if ($choice -eq "Yes") {
        # Select the function | Each of the available functions needs to be listed in this array
        $selectedFunction = @(
        "Build-Hyper-ConvertImage",
        "createVMGen1",
        "createVMGen2",
        "renameComputer",
        "joinDomain",
        "createVHDX",
        "generalSettings",
        "changeIPAddress",
        "installMSI",
        "install_ADDS_DHCP",
        "copy_DHCP_Scope",
        "Copy-EnumerateFileShares",
        "deleteVM"
        ) | Out-GridView -Title "Select the script you'd like to run" -OutputMode Single
        # Dynamically call the selected function
        if ($selectedFunction) {
            Invoke-Expression $selectedFunction
        }
    } elseif ($choice -eq "No") {
        # Script message that will run if No is selected
        Write-Host "You selected no, exiting script." -ForegroundColor DarkGreen
    } else {
        # Script message that wil run if Yes or No is not selected
        Write-Host "Invalid input, please enter 'Yes' or 'No'." -ForegroundColor Red
    }
    return $choice
}

# Will call the choose function function as long as "Yes" is selected
$choice = chooseFunction

# Will recursively call chooseFunction if yes is selected
while ($choice -eq "Yes") {
    $choice = chooseFunction
}
