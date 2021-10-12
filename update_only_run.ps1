function installupdates_only
{
	$Scriptblock = {
		param ($c,
			$cred,
			$InstallOnlyKB,
			$doRestartFinal)
		
		# variables
		$sys_temp = [System.Environment]::GetEnvironmentVariable('TEMP', 'Machine')
		$dir_processing = "$sys_temp\MitchPatch\processing"
		$dir_kb = "$sys_temp\MitchPatch\kb"
		$dir_update_progress = "$sys_temp\MitchPatch\update_progress"
		$dir_services = "$sys_temp\MitchPatch\services"
		$dir_module = "$sys_temp\MitchPatch\module"
		
		function WriteStatus
		{
			$CurrentStauts | Out-File "$dir_update_progress\$c.log"
			$update_progress = Get-Content "$dir_update_progress\$c.log"
			$update_progress_final = Import-Csv "$dir_processing\update_progress.csv"
			$RowIndex = [array]::IndexOf($update_progress_final.System, "$c")
			$update_progress_final[$RowIndex].Status = "$update_progress"
			$update_progress_final | Export-Csv -Path "$dir_processing\update_progress.csv" -NoTypeInformation
		}
		$do_update = $true

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
			$do_update = $false
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
			# Remove (if existing) previous Update-Log on Remote System
			if ($cred -eq "")
			{
				invoke-command -ComputerName $c -ScriptBlock { if (Test-Path "C:\PSWindowsUpdate.log") { Remove-Item "C:\PSWindowsUpdate.log" -Force } }
			}
			else
			{
				invoke-command -ComputerName $c -Credential $cred -ScriptBlock { if (Test-Path "C:\PSWindowsUpdate.log") { Remove-Item "C:\PSWindowsUpdate.log" -Force } }
			}
			# Get Updates on Remote System
			if ($cred -eq "")
			{
				$updates = invoke-command -ComputerName $c -scriptblock { Get-WindowsUpdate -KBArticleID $using:InstallOnlyKB -verbose }
			}
			else
			{
				$updates = invoke-command -ComputerName $c -Credential $cred -scriptblock { Get-WindowsUpdate -KBArticleID $using:InstallOnlyKB -verbose }
			}
			Start-Sleep -Seconds 10
			
			# counts how many updates are available
			$updatenumber = ($updates.kb).count
			$updatenumber | Out-File "$dir_update_progress\NR_$c.log"
			if ($updatenumber -ne '0')
			{
				# Write Status
				$CurrentStauts = "$updatenumber Update(s) found"
				WriteStatus
				Start-Sleep -Seconds 1
				do
				{
					# Write Status
					$CurrentStauts = "Download $updatenumber Update(s) ..."
					WriteStatus
					
						if ($cred -eq "")
						{
							invoke-command -ComputerName $c -ScriptBlock { Invoke-WUjob -RunNow -ComputerName localhost -Script "ipmo PSWindowsUpdate; Install-WindowsUpdate -KBArticleID $using:InstallOnlyKB -AcceptAll -IgnoreReboot | Out-File C:\PSWindowsUpdate.log" -Confirm:$false }
						}
						else
						{
							invoke-command -ComputerName $c -Credential $cred -ScriptBlock { Invoke-WUjob -RunNow -ComputerName localhost -Script "ipmo PSWindowsUpdate; Install-WindowsUpdate -KBArticleID $using:InstallOnlyKB -AcceptAll -IgnoreReboot | Out-File C:\PSWindowsUpdate.log" -Confirm:$false }
						}
					# Show update status until the amount of installed updates equals the same as the amount of updates available
					Start-Sleep -Seconds 5
					do
					{
						# remote command to install windows updates, creates a scheduled task on remote computer
						if ($cred -eq "")
						{
							$updatestatus = invoke-command -ComputerName $c -ScriptBlock { Get-Content "C:\PSWindowsUpdate.log" }
						}
						else
						{
							$updatestatus = invoke-command -ComputerName $c -Credential $cred -ScriptBlock { Get-Content "C:\PSWindowsUpdate.log" }
						}
						Start-Sleep -Seconds 1
						
						$ErrorActionPreference = 'SilentlyContinue'
						$installednumber = ([regex]::Matches($updatestatus, "Installed")).count
						$Failednumber = ([regex]::Matches($updatestatus, "Failed")).count
						$ErrorActionPreference = 'Continue'
						$updatetimeout++
						
						# Write Status
						$CurrentStauts = "Installing ... (Installed: $installednumber of $updatenumber, Failed: $Failednumber)"
						WriteStatus
					}
					until (($installednumber + $Failednumber) -eq $updatenumber -or $updatetimeout -ge 720)
					Start-Sleep -Seconds 3
					
					if ($doRestartFinal -eq $true)
					{
						# removes schedule task from computer
						if ($cred -eq "")
						{
							invoke-command -ComputerName $c -ScriptBlock { Unregister-ScheduledTask -TaskName PSWindowsUpdate -Confirm:$false }
						}
						else
						{
							invoke-command -ComputerName $c -Credential $cred -ScriptBlock { Unregister-ScheduledTask -TaskName PSWindowsUpdate -Confirm:$false }
						}
						# Write Status
						$CurrentStauts = "Restarting System ... (Please wait!)"
						WriteStatus
						
						# Remove Update-Log on Remote System
						if ($cred -eq "")
						{
							invoke-command -ComputerName $c -ScriptBlock { if (Test-Path "C:\PSWindowsUpdate.log") { Remove-Item "C:\PSWindowsUpdate.log" -Force } }
						}
						else
						{
							invoke-command -ComputerName $c -Credential $cred -ScriptBlock { if (Test-Path "C:\PSWindowsUpdate.log") { Remove-Item "C:\PSWindowsUpdate.log" -Force } }
						}
						
						# restarts the remote computer and waits till it starts up again
						if ($cred -eq "")
						{
							Restart-Computer -Wait -ComputerName $c -Force
						}
						else
						{
							Restart-Computer -Wait -ComputerName $c -Credential $cred -Force
						}
						if ($Failednumber -gt '0')
						{
							# Write Status
							$CurrentStauts = "$Failednumber Failed Update(s)! Try again or check the system ..."
							WriteStatus
							$do_update = $false
							Start-Sleep -Seconds 2
						}
						else
						{
							# Write Status
							$CurrentStauts = "All Updates installed!"
							WriteStatus
							$do_update = $false
							Start-Sleep -Seconds 2
							
						}
						# Check Services
						if ($cred -eq "")
						{
							invoke-command -ComputerName $c -ScriptBlock { Get-Service | Where-Object { $_.StartType -like "Auto*" -and $_.Status -ne "Running" } } | Select-Object -Property Name, DisplayName, Status | Export-Csv -Path "$dir_services\$c.csv" -NoTypeInformation
							$services = invoke-command -ComputerName $c -ScriptBlock { Get-Service | Where-Object { $_.StartType -like "Auto*" -and $_.Status -ne "Running" } }
							$service_number = ($services.Name).count
							$service_number | Out-File "$dir_services\NR_$c.log"
							if ($service_number -gt '0')
							{
								[pscustomobject] @{
									Chosen	   = '1'
									System	   = "$c"
									No_Services = "$service_number"
									Services   = ""
								} | Export-Csv "$dir_services\result.csv" -NoTypeInformation -Append
							}
						}
						else
						{
							invoke-command -ComputerName $c -Credential $cred -ScriptBlock { Get-Service | Where-Object { $_.StartType -like "Auto*" -and $_.Status -ne "Running" } } | Select-Object -Property Name, DisplayName, Status | Export-Csv -Path "$dir_services\$c.csv" -NoTypeInformation
							$services = invoke-command -ComputerName $c -Credential $cred -ScriptBlock { Get-Service | Where-Object { $_.StartType -like "Auto*" -and $_.Status -ne "Running" } }
							$service_number = ($services.Name).count
							$service_number | Out-File "$dir_services\NR_$c.log"
							if ($service_number -gt '0')
							{
								[pscustomobject] @{
									Chosen	   = '1'
									System	   = "$c"
									No_Services = "$service_number"
									Services   = ""
								} | Export-Csv "$dir_services\result.csv" -NoTypeInformation -Append
							}
						}
					}
					else
					{
						# removes schedule task from computer
						if ($cred -eq "")
						{
							invoke-command -ComputerName $c -ScriptBlock { Unregister-ScheduledTask -TaskName PSWindowsUpdate -Confirm:$false }
						}
						else
						{
							invoke-command -ComputerName $c -Credential $cred -ScriptBlock { Unregister-ScheduledTask -TaskName PSWindowsUpdate -Confirm:$false }
						}
						# Write Status
						$CurrentStauts = "No restart due to the selected option!"
						WriteStatus
						$do_update = $false
						
						# Close last Session on remote system
						if ($cred -eq "")
						{
							invoke-command -ComputerName $c -ScriptBlock { Stop-Process -Name "powershell" -force }
						}
						else
						{
							invoke-command -ComputerName $c -Credential $cred -ScriptBlock { Stop-Process -Name "powershell" -force }
						}
						# Remove Update-Log on Remote System
						if ($cred -eq "")
						{
							invoke-command -ComputerName $c -ScriptBlock { if (Test-Path "C:\PSWindowsUpdate.log") { Remove-Item "C:\PSWindowsUpdate.log" -Force } }
						}
						else
						{
							invoke-command -ComputerName $c -Credential $cred -ScriptBlock { if (Test-Path "C:\PSWindowsUpdate.log") { Remove-Item "C:\PSWindowsUpdate.log" -Force } }
						}
					}
					
					# Close last Session on remote system
					if ($cred -eq "")
					{
						invoke-command -ComputerName $c -ScriptBlock { Stop-Process -Name "powershell" -force }
					}
					else
					{
						invoke-command -ComputerName $c -Credential $cred -ScriptBlock { Stop-Process -Name "powershell" -force }
					}
					# Remove Update-Log on Remote System
					if ($cred -eq "")
					{
						invoke-command -ComputerName $c -ScriptBlock { if (Test-Path "C:\PSWindowsUpdate.log") { Remove-Item "C:\PSWindowsUpdate.log" -Force } }
					}
					else
					{
						invoke-command -ComputerName $c -Credential $cred -ScriptBlock { if (Test-Path "C:\PSWindowsUpdate.log") { Remove-Item "C:\PSWindowsUpdate.log" -Force } }
					}
				}
				until ($do_update -eq $false)
			}
			else
			{
				# Write Status
				$CurrentStauts = "No Updates to install"
				WriteStatus
				$do_update = $false
				
				# Close last Session on remote system
				if ($cred -eq "")
				{
					invoke-command -ComputerName $c -ScriptBlock { Stop-Process -Name "powershell" -force }
				}
				else
				{
					invoke-command -ComputerName $c -Credential $cred -ScriptBlock { Stop-Process -Name "powershell" -force }
				}
				# Remove Update-Log on Remote System
				if ($cred -eq "")
				{
					invoke-command -ComputerName $c -ScriptBlock { if (Test-Path "C:\PSWindowsUpdate.log") { Remove-Item "C:\PSWindowsUpdate.log" -Force } }
				}
				else
				{
					invoke-command -ComputerName $c -Credential $cred -ScriptBlock { if (Test-Path "C:\PSWindowsUpdate.log") { Remove-Item "C:\PSWindowsUpdate.log" -Force } }
				}
				Start-Sleep -Seconds 2
			}
		}
	}
	get_cred
	
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
		$PowerShell.AddScript($Scriptblock).AddArgument($c).AddArgument($cred).AddArgument($InstallOnlyKB).AddArgument($doRestartFinal).AddArgument($Configuration) | Out-Null
		
		$JobObj = New-Object -TypeName PSObject -Property @{
			Runspace   = $PowerShell.BeginInvoke()
			PowerShell = $PowerShell
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
