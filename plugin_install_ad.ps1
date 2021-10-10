<#	
	.NOTES
	===========================================================================
	 Created with: 	SAPIEN Technologies, Inc., PowerShell Studio 2018 v5.5.150
	 Created on:   	31.08.2021 17:09
	 Created by:   	michel
	 Organization: 	
	 Filename:     	plugin_install_ad.ps1
	===========================================================================
	.DESCRIPTION
		A description of the file.
#>

function Load-Module_RSAT-AD-PowerShell
{
	$mod = "RSAT-AD-PowerShell"
	
	#Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force
	# If module is imported say that and do nothing
	if (Get-WindowsFeature | Where-Object { $_.Name -eq "RSAT-AD-PowerShell" -and $_."Install State" -eq "Installed" })
	{
		Import-Module ActiveDirectory
		write-host "Feature $mod installed."
	}
	elseif (Get-WindowsFeature | Where-Object { $_.Name -eq "RSAT-AD-PowerShell" -and $_."Install State" -ne "Installed" })
	{
		# If the module is not imported, not available and not in the online gallery then abort
		Install-WindowsFeature RSAT-AD-PowerShell
		Import-Module ActiveDirectory
		write-host "Feature $mod has been installed."
		$load_module = $true
	}
	else
	{
		write-host "Feature $mod has not been installed!."
	}
}
#Load-Module_RSAT-AD-PowerShell "$mod" # Load Module
$load_module = $true