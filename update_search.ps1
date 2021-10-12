

function receiveupdates
{
	$Scriptblock = {
		param ($c,
			$cred)
		
		# variables
		$sys_temp = [System.Environment]::GetEnvironmentVariable('TEMP', 'Machine')
		$dir_processing = "$sys_temp\MitchPatch\processing"
		$dir_kb = "$sys_temp\MitchPatch\kb"
		$dir_update_progress = "$sys_temp\MitchPatch\update_progress"
		$dir_module = "$sys_temp\MitchPatch\module"
		
		function WriteStatus
		{
			$CurrentStauts | Out-File "$dir_update_progress\$c.log"
			$update_progress = Get-Content "$dir_update_progress\$c.log"
			$update_progress_final = Import-Csv "$dir_processing\update_progress.csv"
			$RowIndex = [array]::IndexOf($update_progress_final.System, "$c")
			$update_progress_final[$RowIndex].Status = "$update_progress"
			$update_progress_final | Export-Csv -Path "$dir_processing\update_progress.csv" -NoTypeInformation
			$do_update = $false
		}
		Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force
		#starts up a remote powershell session to the computer
		if ($cred -eq "")
		{
			$session = invoke-command -ComputerName $c -ScriptBlock { Get-Date }
		}
		else
		{
			$session = invoke-command -ComputerName $c -Credential $cred -ScriptBlock { Get-Date }
		}
		if (!($session))
		{
			$CurrentStauts = "Access Denied - Check Credentials!"
			WriteStatus
		}
		else
		{
			# Installing Prerequisites on Remote-System
			if ($cred -eq "")
			{
				invoke-command -ComputerName $c -ScriptBlock { Stop-Process -Name "powershell" -force }
			}
			else
			{
				invoke-command -ComputerName $c -Credential $cred -ScriptBlock { Stop-Process -Name "powershell" -force }
			}
			# Create PsSession and copy PsWindowsUpdate-Module to the destination system
			if ($cred -eq "")
			{
				$pssession = New-PSSession –ComputerName $c
			}
			else
			{
				$pssession = New-PSSession –ComputerName $c -Credential $cred
			}
			Copy-Item "$dir_module\PSWindowsUpdate" -Destination "$env:programfiles\windowspowershell\modules" -ToSession $pssession -Recurse
			$pssession | Remove-PSSession
			if ($cred -eq "")
			{
				invoke-command -ComputerName $c -ScriptBlock { Import-Module PSWindowsUpdate -force }
			}
			else
			{
				invoke-command -ComputerName $c -Credential $cred -ScriptBlock { Import-Module PSWindowsUpdate -force }
			}
			do
			{
				# Remove (if existing) previous Update-Log on Remote System
				if ($cred -eq "")
				{
					invoke-command -ComputerName $c -ScriptBlock { if (Test-Path "C:\PSWindowsUpdate.log") { Remove-Item "C:\PSWindowsUpdate.log" -Force } }
				}
				else
				{
					invoke-command -ComputerName $c -Credential $cred -ScriptBlock { if (Test-Path "C:\PSWindowsUpdate.log") { Remove-Item "C:\PSWindowsUpdate.log" -Force } }
				}
				#Checking for new updates available on Remote-System
				if ($cred -eq "")
				{
					$updates = invoke-command -ComputerName $c -scriptblock { Get-WindowsUpdate -verbose }
				}
				else
				{
					$updates = invoke-command -ComputerName $c -Credential $cred -scriptblock { Get-WindowsUpdate -verbose }
				}
				
				$kb_list = $updates | Select-Object @{ Name = 'Update'; Expression = { $_.kb } }, @{ Name = 'Description'; Expression = { $_.title } }, @{ Name = 'Size'; Expression = { $_.size } }
				$kb_list | Export-Csv "$dir_kb\$c.csv" -NoTypeInformation -Encoding UTF8
				
				#counts how many updates are available
				$updatenumber = ($updates.kb).count
				$updatenumber | Out-File "$dir_update_progress\NR_$c.log"
				if ($updates -eq $null)
				{
					# Write Status
					$CurrentStauts = "No updates available"
					WriteStatus
				}
				else
				{
					# Write Status
					$CurrentStauts = "$updatenumber Update(s) found"
					WriteStatus
				}
			}
			until ($session -or $connectiontimeout -ge 10)
		}
	}
	get_cred
	[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
	Save-Module -Name "PsWindowsUpdate" -Path "$dir_module"
	
	$to_update = Import-Csv "$dir_processing\output_to_update.csv" | Select-Object -ExpandProperty System
	
	ForEach ($c in $to_update)
	{
		# Write Status
		"Searching for Updates ..." | Out-File "$dir_update_progress\$c.log"
		$update_progress = Get-Content "$dir_update_progress\$c.log"
		$update_progress_final = Import-Csv "$dir_processing\update_progress.csv"
		$RowIndex = [array]::IndexOf($update_progress_final.System, "$c")
		$update_progress_final[$RowIndex].Status = "$update_progress"
		$update_progress_final | Export-Csv -Path "$dir_processing\update_progress.csv" -NoTypeInformation
	}
	$datagridview2.DataSource = [System.Collections.ArrayList]$update_progress_final = [array](Import-Csv -Path "$dir_processing\update_progress.csv")
	##############################################################################################################################
	# Run the Scriptblock in parallel
	$Configuration = [hashtable]::Synchronized(@{ })
	$Configuration.CreatedFiles = @()
	
	if ($MaxRunspaces -eq $null)
	{
		$MaxRunspaces = $threads
	}
	
	$SessionState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
	$RunspacePool = [RunspaceFactory]::CreateRunspacePool(1, $MaxRunspaces, $SessionState, $Host)
	$RunspacePool.Open()
	
	$Jobs = New-Object System.Collections.ArrayList
	
	foreach ($c in $to_update)
	{
		Write-Host "Creating runspace for $c"
		$PowerShell = [powershell]::Create()
		$PowerShell.RunspacePool = $RunspacePool
		$PowerShell.AddScript($Scriptblock).AddArgument($c).AddArgument($cred).AddArgument($Configuration) | Out-Null
		
		$JobObj = New-Object -TypeName PSObject -Property @{
			Runspace    = $PowerShell.BeginInvoke()
			PowerShell  = $PowerShell
		}
		
		$Jobs.Add($JobObj) | Out-Null
	}
	
	while ($Jobs.Runspace.IsCompleted -contains $false)
	{
		$datagridview2.DataSource = [System.Collections.ArrayList]$update_progress_final = [array](Import-Csv -Path "$dir_processing\update_progress.csv")
		Start-Sleep -Seconds 1
	}
	$PowerShell.RunspacePool.Dispose()
	# Collect Status and show the result
	$datagridview2.DataSource = [System.Collections.ArrayList]$update_progress_final = [array](Import-Csv -Path "$dir_processing\update_progress.csv")
}