#--------------------------------------------
# Declare Global Variables and Functions here
#--------------------------------------------

################################################################################################################
#																											   #
#													Start													   #
#																											   #
################################################################################################################
##############################################---- Create temporary Processing-Directories ----##################################
function dir_temp
{
	$sys_temp = [System.Environment]::GetEnvironmentVariable('TEMP', 'Machine')
	$Global:proc_files = "$sys_temp\MitchPatch"
	if (Test-Path $proc_files)
	{
		Remove-Item $proc_files -Recurse -Force
	}
	$Global:dir_root = New-Item -Path "$sys_temp" -Name "MitchPatch" -ItemType "directory"
	$Global:dir_processing = New-Item -Path "$sys_temp\MitchPatch" -Name "processing" -ItemType "directory"
	$Global:dir_kb = New-Item -Path "$sys_temp\MitchPatch" -Name "kb" -ItemType "directory"
	$Global:dir_update_progress = New-Item -Path "$sys_temp\MitchPatch" -Name "update_progress" -ItemType "directory"
	$Global:dir_tmp_cred = New-Item -Path "$sys_temp\MitchPatch" -Name "credentials" -ItemType "directory"
	$Global:dir_troubleshoot = New-Item -Path "$sys_temp\MitchPatch" -Name "troubleshoot" -ItemType "directory"
	$Global:dir_services = New-Item -Path "$sys_temp\MitchPatch" -Name "services" -ItemType "directory"
}

##############################################---- Create persistent Processing-Directories ----##################################
function dir_persistent
{
	$dir_appdata_root_test = "$env:LOCALAPPDATA\MitchPatch"
	if (!(Test-Path $dir_appdata_root_test))
	{
		$Global:dir_appdata_root = New-Item -Path "$env:LOCALAPPDATA" -Name "MitchPatch" -ItemType "directory"
	}
	else
	{
		$Global:dir_appdata_root = "$env:LOCALAPPDATA\MitchPatch"
	}
	
	
	$dir_credentials_test = "$dir_appdata_root\credentials"
	if (!(Test-Path $dir_credentials_test))
	{
		$Global:dir_credentials = New-Item -Path "$dir_appdata_root" -Name "credentials" -ItemType "directory"
	}
	else
	{
		$Global:dir_credentials = "$dir_appdata_root\credentials"
	}
}

################################################################################################################
#																											   #
#												1. File-Import												   #
#																											   #
################################################################################################################
##############################################---- Validate Path ----###########################################
function CheckCsvPath
{
	if ($textboxFile.Text.Length -ne $null)
	{
		$csv_import.Enabled = $true
	}
	else
	{
		$csv_import.Enabled = $false
	}
}

##############################################---- Import CSV ----############################################
function CheckGridView
{
	if ($datagridview1.DataSource.System -like "")
	{
		$check_systems.Enabled = $false
		$ExportList.Enabled = $false
		$checkbox_ex_All.Enabled = $false
		$checkbox_ex_selected.Enabled = $false
	}
	else
	{
		$check_systems.Enabled = $true
		$ExportList.Enabled = $true
		$checkbox_ex_All.Enabled = $true
		$checkbox_ex_All.Checked = $true
		$checkbox_ex_selected.Enabled = $true
	}
}


################################################################################################################
#																											   #
#												3. Start Patching											   #
#																											   #
################################################################################################################
##############################################---- Export persistent Credentials ----############################################
function export_credentials
{
	$textboxUser.Text | Out-File "$dir_credentials\cred_username.txt"
	$textboxPassword.Text | ConvertTo-SecureString -AsPlainText -Force | ConvertFrom-SecureString | out-file "$dir_credentials\cred_password.txt"
}

##############################################---- Export temporary Credentials ----############################################
function export_credentials_tmp
{
	$textboxUser.Text | Out-File "$dir_tmp_cred\cred_username_tmp.txt"
	$textboxPassword.Text | ConvertTo-SecureString -AsPlainText -Force | ConvertFrom-SecureString | out-file "$dir_tmp_cred\cred_password_tmp.txt"
}

##############################################---- Get Credentials ----############################################
function get_cred
{
	$cred_username = "$dir_credentials\cred_username.txt"
	$cred_password = "$dir_credentials\cred_password.txt"
	$cred_username_tmp = "$dir_tmp_cred\cred_username_tmp.txt"
	$cred_password_tmp = "$dir_tmp_cred\cred_password_tmp.txt"
	
	if ((Test-Path $cred_username) -and (Test-Path $cred_password))
	{
		$username = Get-Content "$dir_credentials\cred_username.txt"
		$password = Get-Content "$dir_credentials\cred_password.txt" | ConvertTo-SecureString
		$Global:cred = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $username, $password
	}
	elseif ((Test-Path $cred_username_tmp) -and (Test-Path $cred_password_tmp))
	{
		$username = Get-Content "$dir_tmp_cred\cred_username_tmp.txt"
		$password = Get-Content "$dir_tmp_cred\cred_password_tmp.txt" | ConvertTo-SecureString
		$Global:cred = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $username, $password
	}
	else
	{
		$Global:cred = ""
	}
}

##############################################---- Test for Troubleshooting ----############################################
function testtroubleshoot
{
	foreach ($Row in $datagridview2.Rows)
	{
		if (($Row.Cells[2].Value -like "Access Denied*") -or ($Row.Cells[2].Value -like "*Failed*"))
		{
			$buttonFixIssues.Enabled = $true
			$buttonFixIssues.BackColor = "DarkGoldenrod"
		}
	}
}

##############################################---- Test for Autostart Services ----############################################
function testservices
{
	
	if (Test-Path "$dir_services\result.csv")
	{
		$service_check = Import-Csv "$dir_services\result.csv" | Select-Object No_Services
		foreach ($check in $service_check)
		{
			if ($check -ne '0')
			{
				$buttonServices.Enabled = $true
				$buttonServices.BackColor = "DarkGoldenrod"
			}
			else
			{
				$buttonServices.Enabled = $false
				$buttonServices.BackColor = [System.Drawing.Color]::FromArgb(48, 52, 61)
			}
		}
	}
	else
	{
		$buttonServices.Enabled = $false
		$buttonServices.BackColor = [System.Drawing.Color]::FromArgb(48, 52, 61)
	}
}