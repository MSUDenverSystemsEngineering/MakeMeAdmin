﻿<#
.SYNOPSIS
	This script performs the installation or uninstallation of an application(s).
	# LICENSE #
	PowerShell App Deployment Toolkit - Provides a set of functions to perform common application deployment tasks on Windows.
	Copyright (C) 2017 - Sean Lillis, Dan Cunningham, Muhammad Mashwani, Aman Motazedian.
	This program is free software: you can redistribute it and/or modify it under the terms of the GNU Lesser General Public License as published by the Free Software Foundation, either version 3 of the License, or any later version. This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
	You should have received a copy of the GNU Lesser General Public License along with this program. If not, see <http://www.gnu.org/licenses/>.
.DESCRIPTION
	The script is provided as a template to perform an install or uninstall of an application(s).
	The script either performs an "Install" deployment type or an "Uninstall" deployment type.
	The install deployment type is broken down into 3 main sections/phases: Pre-Install, Install, and Post-Install.
	The script dot-sources the AppDeployToolkitMain.ps1 script which contains the logic and functions required to install or uninstall an application.
.PARAMETER DeploymentType
	The type of deployment to perform. Default is: Install.
.PARAMETER DeployMode
	Specifies whether the installation should be run in Interactive, Silent, or NonInteractive mode. Default is: Interactive. Options: Interactive = Shows dialogs, Silent = No dialogs, NonInteractive = Very silent, i.e. no blocking apps. NonInteractive mode is automatically set if it is detected that the process is not user interactive.
.PARAMETER AllowRebootPassThru
	Allows the 3010 return code (requires restart) to be passed back to the parent process (e.g. SCCM) if detected from an installation. If 3010 is passed back to SCCM, a reboot prompt will be triggered.
.PARAMETER TerminalServerMode
	Changes to "user install mode" and back to "user execute mode" for installing/uninstalling applications for Remote Destkop Session Hosts/Citrix servers.
.PARAMETER DisableLogging
	Disables logging to file for the script. Default is: $false.
.EXAMPLE
    powershell.exe -Command "& { & '.\Deploy-Application.ps1' -DeployMode 'Silent'; Exit $LastExitCode }"
.EXAMPLE
    powershell.exe -Command "& { & '.\Deploy-Application.ps1' -AllowRebootPassThru; Exit $LastExitCode }"
.EXAMPLE
    powershell.exe -Command "& { & '.\Deploy-Application.ps1' -DeploymentType 'Uninstall'; Exit $LastExitCode }"
.EXAMPLE
    Deploy-Application.exe -DeploymentType "Install" -DeployMode "Silent"
.NOTES
	Toolkit Exit Code Ranges:
	60000 - 68999: Reserved for built-in exit codes in Deploy-Application.ps1, Deploy-Application.exe, and AppDeployToolkitMain.ps1
	69000 - 69999: Recommended for user customized exit codes in Deploy-Application.ps1
	70000 - 79999: Recommended for user customized exit codes in AppDeployToolkitExtensions.ps1
.LINK
	http://psappdeploytoolkit.com
#>
[CmdletBinding()]
## Suppress PSScriptAnalyzer errors for not using declared variables during AppVeyor build
[Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseDeclaredVarsMoreThanAssignments", "", Justification="Suppresses AppVeyor errors on informational variables below")]
Param (
	[Parameter(Mandatory=$false)]
	[ValidateSet('Install','Uninstall')]
	[string]$DeploymentType = 'Install',
	[Parameter(Mandatory=$false)]
	[ValidateSet('Interactive','Silent','NonInteractive')]
	[string]$DeployMode = 'Interactive',
	[Parameter(Mandatory=$false)]
	[switch]$AllowRebootPassThru = $false,
	[Parameter(Mandatory=$false)]
	[switch]$TerminalServerMode = $false,
	[Parameter(Mandatory=$false)]
	[switch]$DisableLogging = $false
)

Try {
	## Set the script execution policy for this process
	Try { Set-ExecutionPolicy -ExecutionPolicy 'ByPass' -Scope 'Process' -Force -ErrorAction 'Stop' } Catch { Write-Error "Failed to set the execution policy to Bypass for this process." }

	##*===============================================
	##* VARIABLE DECLARATION
	##*===============================================
	## Variables: Application
	[string]$appVendor = 'MakeMeAdmin'
	[string]$appName = 'Make Me Admin'
	[string]$appVersion = '2.2.1'
	[string]$appArch = 'x64'
	[string]$appLang = 'EN'
	[string]$appRevision = '01'
	[string]$appScriptVersion = '3.7.0.1'
	[string]$appScriptDate = '08/23/2018'
	[string]$appScriptAuthor = 'MSU Denver'
	##*===============================================
	## Variables: Install Titles (Only set here to override defaults set by the toolkit)
	[string]$installName = ''
	[string]$installTitle = ''

	##* Do not modify section below
	#region DoNotModify

	## Variables: Exit Code
	[int32]$mainExitCode = 0

	## Variables: Script
	[string]$deployAppScriptFriendlyName = 'Deploy Application'
	[version]$deployAppScriptVersion = [version]'3.7.0'
	[string]$deployAppScriptDate = '02/13/2018'
	[hashtable]$deployAppScriptParameters = $psBoundParameters

	## Variables: Environment
	If (Test-Path -LiteralPath 'variable:HostInvocation') { $InvocationInfo = $HostInvocation } Else { $InvocationInfo = $MyInvocation }
	[string]$scriptDirectory = Split-Path -Path $InvocationInfo.MyCommand.Definition -Parent

	## Dot source the required App Deploy Toolkit Functions
	Try {
		[string]$moduleAppDeployToolkitMain = "$scriptDirectory\AppDeployToolkit\AppDeployToolkitMain.ps1"
		If (-not (Test-Path -LiteralPath $moduleAppDeployToolkitMain -PathType 'Leaf')) { Throw "Module does not exist at the specified location [$moduleAppDeployToolkitMain]." }
		If ($DisableLogging) { . $moduleAppDeployToolkitMain -DisableLogging } Else { . $moduleAppDeployToolkitMain }
	}
	Catch {
		If ($mainExitCode -eq 0){ [int32]$mainExitCode = 60008 }
		Write-Error -Message "Module [$moduleAppDeployToolkitMain] failed to load: `n$($_.Exception.Message)`n `n$($_.InvocationInfo.PositionMessage)" -ErrorAction 'Continue'
		## Exit the script, returning the exit code to SCCM
		If (Test-Path -LiteralPath 'variable:HostInvocation') { $script:ExitCode = $mainExitCode; Exit } Else { Exit $mainExitCode }
	}

	#endregion
	##* Do not modify section above
	##*===============================================
	##* END VARIABLE DECLARATION
	##*===============================================

	If ($deploymentType -ine 'Uninstall') {
		##*===============================================
		##* PRE-INSTALLATION
		##*===============================================
		[string]$installPhase = 'Pre-Installation'

		## Show Welcome Message, close Internet Explorer if needed, verify there is enough disk space to complete the install, and persist the prompt
		Show-InstallationWelcome -CloseApps 'makemeadmin' -CheckDiskSpace -PersistPrompt

		## Show Progress Message (with the default message)
		Show-InstallationProgress

		## <Perform Pre-Installation tasks here>
		$exitCode = Execute-MSI -Action 'Uninstall' -Path "{87EAC1A2-9DE1-4838-8093-74C2AA19ED27}"
        If (($exitCode.ExitCode -ne "0") -and ($mainExitCode -ne "3010")) { $mainExitCode = $exitCode.ExitCode }

		##*===============================================
		##* INSTALLATION
		##*===============================================
		[string]$installPhase = 'Installation'

		## Handle Zero-Config MSI Installations
		If ($useDefaultMsi) {
			[hashtable]$ExecuteDefaultMSISplat =  @{ Action = 'Install'; Path = $defaultMsiFile }; If ($defaultMstFile) { $ExecuteDefaultMSISplat.Add('Transform', $defaultMstFile) }
			Execute-MSI @ExecuteDefaultMSISplat; If ($defaultMspFiles) { $defaultMspFiles | ForEach-Object { Execute-MSI -Action 'Patch' -Path $_ } }
		}

		## <Perform Installation tasks here>

		$exitCode = Execute-MSI -Action 'Install' -Path "$dirFiles\MakeMeAdmin 2.2.1 x64.msi" -Parameters '/qn'
        If (($exitCode.ExitCode -ne "0") -and ($mainExitCode -ne "3010")) { $mainExitCode = $exitCode.ExitCode }

		##*===============================================
		##* POST-INSTALLATION
		##*===============================================
		[string]$installPhase = 'Post-Installation'

		## <Perform Post-Installation tasks here>

		$currentUserName = Get-CIMInstance -Class CIM_ComputerSystem | Select-Object -Expand UserName
		## $currentUserSID = (New-Object System.Security.Principal.NTAccount($currentUserName)).Translate([System.Security.Principal.SecurityIdentifier]).value
		$timeoutMinutes = '15'
		$removeAdminRightsOnLogout = '1'
		$MMAregistryPath = 'HKLM:\SOFTWARE\Sinclair Community College\Make Me Admin'
		$UACregistryPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'
		$enableUAC = '1'

		## New-ItemProperty -Path $MMAregistryPath -Name 'Allowed Entities' -Value $currentUserSID -PropertyType MultiString -Force
		New-ItemProperty -Path $MMAregistryPath -Name 'Admin Rights Timeout' -Value $timeoutMinutes -PropertyType DWord -Force
		New-ItemProperty -Path $MMAregistryPath -Name 'Remove Admin Rights On Logout' -Value $removeAdminRightsOnLogout -PropertyType Dword -Force

		<#
		#Remove current user from MakeMeAdmin AD group
		$account = 'winad\acinstaller'
		$accountkey = Get-Content "$dirSupportFiles\acinstaller_AES_KEY_FILE.key"
		$credential = New-Object System.Management.Automation.PSCredential($account,(Get-Content "$dirSupportFiles\acinstaller_AES_PASSWORD_FILE.txt" | ConvertTo-SecureString -Key $accountkey))
		$adgroup = 'MakeMeAdmin'
		Enable-PSRemoting –force
		Enable-WSManCredSSP -Role Client -DelegateComputer *.winad.msudenver.edu -Force
		Invoke-Command -Computer vmwas117.winad.msudenver.edu -Credential $credential -Authentication CredSSP -ScriptBlock {
			Remove-ADGroupMember -Identity $args[0] -Members $args[1] -Confirm:$false
		} -ArgumentList $adgroup,$currentUserSID
		#>

		# Update CM MakeMeAdmin User Collection

		<#
		# Construct web service proxy
		try {
		    $URI = "https://vmwas117.winad.msudenver.edu/ConfigMgrWebService/ConfigMgr.asmx"
		    $WebService = New-WebServiceProxy -Uri $URI -ErrorAction Stop
		}
		catch [System.Exception] {
		    Write-Warning -Message "An error occured while attempting to call the web service. Error message: $($_.Exception.Message)" ; exit 2
		}

		# Invoke Update CM Collection Membership
		# Read the secure password from a password file and decrypt it to a normal readable string
		$webservicekey = Get-Content "$dirSupportFiles\cmwebservice_AES_KEY_FILE.key"
		$SecurePassword = (Get-Content "$dirSupportFiles\cmwebservice_AES_PASSWORD_FILE.txt" | ConvertTo-SecureString -Key $webservicekey)
		$CollectionID = 'MS1001AB'
		$SecurePasswordInMemory = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecurePassword);             # Write the secure password to unmanaged memory (specifically to a binary or basic string)
		$PasswordAsString = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($SecurePasswordInMemory);              # Read the plain-text password from memory and store it in a variable
		[Runtime.InteropServices.Marshal]::ZeroFreeBSTR($SecurePasswordInMemory);                                     # Delete the password from the unmanaged memory (for security reasons)
		$WebService.UpdateCMCollectionMembership("$PasswordAsString","$CollectionID")

		Remove-Folder -Path $dirSupportFiles
		#>

		# renable UAC if disabled
		If ((Get-RegistryKey -Key $UACregistryPath -Value 'EnableLUA') -ne '1'){
			New-ItemProperty -Path $UACregistryPath -Name 'EnableLUA' -Value $enableUAC -PropertyType Dword -Force
			[int32]$mainExitCode = 3010
		}

		## Display a message at the end of the install
		If (-not $useDefaultMsi) {

		}

	}
	ElseIf ($deploymentType -ieq 'Uninstall')
	{
		##*===============================================
		##* PRE-UNINSTALLATION
		##*===============================================
		[string]$installPhase = 'Pre-Uninstallation'

		## Show Welcome Message, close Internet Explorer with a 60 second countdown before automatically closing
		Show-InstallationWelcome -CloseApps 'makemeadmin' -CloseAppsCountdown 60

		## Show Progress Message (with the default message)
		Show-InstallationProgress

		## <Perform Pre-Uninstallation tasks here>


		##*===============================================
		##* UNINSTALLATION
		##*===============================================
		[string]$installPhase = 'Uninstallation'

		## Handle Zero-Config MSI Uninstallations
		If ($useDefaultMsi) {
			[hashtable]$ExecuteDefaultMSISplat =  @{ Action = 'Uninstall'; Path = $defaultMsiFile }; If ($defaultMstFile) { $ExecuteDefaultMSISplat.Add('Transform', $defaultMstFile) }
			Execute-MSI @ExecuteDefaultMSISplat
		}

		# <Perform Uninstallation tasks here>

		$exitCode = Execute-MSI -Action 'Uninstall' -Path "{87EAC1A2-9DE1-4838-8093-74C2AA19ED27}"
        If (($exitCode.ExitCode -ne "0") -and ($mainExitCode -ne "3010")) { $mainExitCode = $exitCode.ExitCode }

		##*===============================================
		##* POST-UNINSTALLATION
		##*===============================================
		[string]$installPhase = 'Post-Uninstallation'

		## <Perform Post-Uninstallation tasks here>


	}

	##*===============================================
	##* END SCRIPT BODY
	##*===============================================

	## Call the Exit-Script function to perform final cleanup operations
	Exit-Script -ExitCode $mainExitCode
}
Catch {
	[int32]$mainExitCode = 60001
	[string]$mainErrorMessage = "$(Resolve-Error)"
	Write-Log -Message $mainErrorMessage -Severity 3 -Source $deployAppScriptFriendlyName
	Show-DialogBox -Text $mainErrorMessage -Icon 'Stop'
	Exit-Script -ExitCode $mainExitCode
}
