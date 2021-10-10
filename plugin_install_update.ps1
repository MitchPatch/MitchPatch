<#	
	.NOTES
	===========================================================================
	 Created with: 	SAPIEN Technologies, Inc., PowerShell Studio 2018 v5.5.150
	 Created on:   	24.08.2021 09:22
	 Created by:   	michel
	 Organization: 	
	 Filename:     	check_plugin_install.ps1
	===========================================================================
	.DESCRIPTION
		Import PowerShell-Module: "PSWindowsUpdate"
#>
function Load-Module_PSWindowsUpdate
{
	$Global:mod = "PSWindowsUpdate"
	
	Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force
	# If module is imported say that and do nothing
	if (Get-Module | Where-Object { $_.Name -eq $mod })
	{
		write-host "Module $mod is already imported."
	}
	else
	{
		# If module is not imported, but available on disk then import
		if (Get-Module -ListAvailable | Where-Object { $_.Name -eq $mod })
		{
			Import-Module $mod
			write-host "Module $mod has been imported."
		}
		else
		{
			# If module is not imported, not available on disk, but is in online gallery then install and import
			if (Find-Module -Name $mod | Where-Object { $_.Name -eq $mod })
			{
				Install-Module -Name $mod -Force -Verbose -Scope CurrentUser
				Import-Module $mod
				write-host "Module $mod has been downloaded and imported."
			}
			else
			{
				# If the module is not imported, not available and not in the online gallery then abort
				write-host "Module $mod not imported, not available and not in an online gallery, exiting."
				$load_module = $false
			}
		}
	}
}
#Load-Module "$mod" # Load Module
$load_module = $true