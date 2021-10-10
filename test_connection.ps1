<#	
	.NOTES
	===========================================================================
	 Created with: 	SAPIEN Technologies, Inc., PowerShell Studio 2018 v5.5.150
	 Created on:   	25.08.2021 07:34
	 Created by:   	michel
	 Organization: 	
	 Filename:     	update_loop.ps1
	===========================================================================
	.DESCRIPTION
		A description of the file.
#>

################ CSV einlesen #######################
function test_connection
{
	$FileName = "$dir_processing\output.csv"
	$output_net = "$dir_processing\output_net.csv"
	test-path $output_net
	if (Test-Path $output_net)
	{
		Remove-Item $output_net
	}
	$row_count = @(Get-Content $FileName).Length - 1
	$progressbaroverlay1.Maximum = $row_count.Count * $row_count
	$progressbaroverlay1.Step = 1
	$progressbaroverlay1.Value = 0
	$progressbaroverlay1.TextOverlay = "Processing..."
	#Start-Sleep -Seconds 1
		
	Import-Csv "$dir_processing\output.csv" | Select-Object Chosen, System | ForEach-Object {
		$current_system = $_.System
		$local_system = (Get-WmiObject win32_computersystem).DNSHostName + "." + (Get-WmiObject win32_computersystem).Domain;

		try
		{
			$Computer = [system.net.dns]::resolve($_.System) | Select-Object HostName, AddressList
			$IP = ($Computer.AddressList).IPAddressToString
			$ping = Test-Connection $current_system -Quiet -Count 1
			if ($local_system -eq $Computer.HostName)
			{
				New-Object PSObject -Property @{ Chosen = "0"; IPAddress = (@($IP) -join ' - '); System = $Computer.HostName; Info = "This Host! (Skip)" } | Export-Csv "$dir_processing\output_net.csv" -NoTypeInformation -Append
			}
			elseif ($ping -eq $false)
			{
				New-Object PSObject -Property @{ Chosen = "0"; IPAddress = "System inaccessible!"; System = $Computer.HostName; Info = "Skip" } | Export-Csv "$dir_processing\output_net.csv" -NoTypeInformation -Append
			}
			else
			{
				New-Object PSObject -Property @{ Chosen = '1'; IPAddress = (@($IP) -join ' - '); System = $Computer.HostName; Info = "OK" } | Export-Csv "$dir_processing\output_net.csv" -NoTypeInformation -Append
			}
		}
		catch
		{
			New-Object PSObject -Property @{ Chosen = "0"; IPAddress = "System not resolvable!"; System = $current_system; Info = "Skip" } | Export-Csv "$dir_processing\output_net.csv" -NoTypeInformation -Append
		}
		$progressbaroverlay1.Step = 1
		$progressbaroverlay1.PerformStep()
	}
	$progressbaroverlay1.TextOverlay = "Done!";
}