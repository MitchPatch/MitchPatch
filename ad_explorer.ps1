
# Greg Toombs, November 2013

set-strictmode -version latest

add-type -a (
	'System.DirectoryServices',
	'System.DirectoryServices.AccountManagement',
	'System.Drawing',
	'System.Windows.Forms'
)

function GetConnDlg()
{
	$label = new-object Windows.Forms.Label -pr @{
		AutoSize  = $true
		Dock	  = [Windows.Forms.DockStyle]::Top
		Text	  = 'Hostname'
	}
	$text = new-object Windows.Forms.TextBox -pr @{
		Anchor  = [Windows.Forms.AnchorStyles] 'Left, Right, Top'
		MinimumSize = new-object Drawing.Size -a 120, 20
	}
	$ok = new-object Windows.Forms.Button -pr @{
		DialogResult  = [Windows.Forms.DialogResult]::OK
		Text		  = '&Connect'
	}
	$cancel = new-object Windows.Forms.Button -pr @{
		DialogResult  = [Windows.Forms.DialogResult]::Cancel
		Text		  = 'C&ancel'
	}
	$flowh = new-object Windows.Forms.FlowLayoutPanel -pr @{
		AutoSize  = $true
		Dock	  = [Windows.Forms.DockStyle]::Bottom
		FlowDirection = [Windows.Forms.FlowDirection]::RightToLeft
	}
	$flowh.Controls.AddRange(($cancel, $ok))
	$flowv = new-object Windows.Forms.FlowLayoutPanel -pr @{
		AutoSize  = $true
		Dock	  = [Windows.Forms.DockStyle]::Fill
		FlowDirection = [Windows.Forms.FlowDirection]::TopDown
	}
	$flowv.Controls.AddRange(($label, $text))
	$conndlg = new-object Windows.Forms.Form -pr @{
		AcceptButton  = $ok
		CancelButton  = $cancel
		MaximizeBox   = $false
		MinimizeBox   = $false
		Padding	      = new-object Windows.Forms.Padding -a 5
		Size		  = new-object Drawing.Size -a 230, 130
		StartPosition = [Windows.Forms.FormStartPosition]::CenterParent
		Text		  = 'Connect'
	}
	$conndlg.Controls.AddRange(($flowv, $flowh))
	$ok.Add_Click({
			$conndlg.Tag = $text.Text
			$text.Text = ''
		}.GetNewClosure())
	$conndlg
}

function GetProp($obj, $prop)
{
	$obj.GetType().InvokeMember(
		$prop, [Reflection.BindingFlags]::GetProperty, $null, $obj, $null)
}

function IsSaneDate($dt)
{
	$dt.Year -ge 1800 -and $dt.Year -lt 2200
}

function ByteProp($propname, $val, $add, $expand)
{
	if ($val -is [Byte[]])
	{
		$tname = $val.GetType().FullName
		if ($val.Length -eq 16)
		{
			&$add $propname "$tname (GUID)" (new-object Guid -a ( ,$val))
		}
		elseif ($val.Length -eq 28)
		{
			&$add $propname "$tname (SID)" (new-object Security.Principal.SecurityIdentifier -a ($val, 0))
		}
		elseif ($val.Length -gt 28 -and -not $expand)
		{
			&$add $propname $tname $val $true
		}
		else
		{
			&$add $propname $tname $([BitConverter]::ToString($val))
		}
		$true
	}
}

function I64Prop($propname, $val, $add, $expand)
{
	if ($val -is [__ComObject])
	{
		try
		{
			[int64]$hi = GetProp $val 'HighPart'
			[int64]$lo = GetProp $val 'LowPart'
			[int64]$qword = ($hi -shl 32) -bor $lo
			$valstr = '{0} = 0x{0:X16}' -f $qword
			try
			{
				$dt = [DateTime]::FromFileTime($qword)
				if (IsSaneDate $dt)
				{
					$valstr = '{0} = {1}' -f $valstr, $dt
				}
			}
			catch { }
			try
			{
				if ('lockoutDuration', 'forceLogoff', 'lockOutObservationWindow',
					'maxPwdAge', 'minPwdAge' -contains $propname `
					-and $qword -ne 0x8000000000000000)
				{
					$ts = [TimeSpan]::FromTicks([math]::abs($qword))
					$valstr = '{0} = {1}' -f $valstr, $ts
				}
			}
			catch { }
			&$add $propname 'ActiveDs.LargeInteger' $valstr
			$true
		}
		catch [Management.Automation.MethodInvocationException] { }
	}
}

function AccessControlProp($propname, $val, $add, $expand)
{
	if ($val -is [__ComObject])
	{
		try
		{
			$valstr = @'
AccessMask = {0} = 0x{0:X8}
AceFlags = {1} = 0x{1:X8}
AceType = {2} = 0x{2:X8}
Flags = {3} = 0x{3:X8}
InheritedObjectType = {4}
ObjectType = {5}
Trustee = {6}
'@ -f $(@(
					'AccessMask',
					'AceFlags',
					'AceType',
					'Flags',
					'InheritedObjectType',
					'ObjectType',
					'Trustee'
				) | %{ GetProp $val $_ })
			&$add $propname 'ActiveDs.AccessControlEntry' $valstr
			$true
		}
		catch [Management.Automation.MethodInvocationException] { }
	}
}

function SecDescProp($propname, $val, $add, $expand)
{
	if ($val -is [__ComObject])
	{
		try
		{
			$valstr = @'
Control = {0} = 0x{0:X8}
DaclDefaulted = {1}
Group = {2}
GroupDefaulted = {3}
Owner = {4}
OwnerDefaulted = {5}
Revision = {6}
SaclDefaulted = {7}
'@ -f $(@(
					'Control'
					'DaclDefaulted'
					'Group'
					'GroupDefaulted'
					'Owner'
					'OwnerDefaulted'
					'Revision'
					'SaclDefaulted'
				) | %{ GetProp $val $_ })
			&$add $propname 'ActiveDs.SecurityDescriptor' $valstr
			&$add "$propname.DiscretionaryAcl" 'ActiveDs.AccessControlEntry[]' `
				  $(GetProp $val 'DiscretionaryAcl') $true
			$(GetProp $val 'SystemAcl') | %{
				AccessControlProp "$propname.SystemAcl" $_ $add
			}
			$true
		}
		catch [Management.Automation.MethodInvocationException] { }
	}
}

function DNProp($propname, $val, $add, $expand)
{
	if ($val -is [__ComObject])
	{
		try
		{
			$valstr = "BinaryValue = {0}`nDNString = {1}" -f
			$(new-object Guid -a ( ,[byte[]]$(GetProp $val 'BinaryValue'))),
			$(GetProp $val 'DNString')
			&$add $propname 'ActiveDs.DNWithBinary' $valstr
			$true
		}
		catch [Management.Automation.MethodInvocationException] { }
	}
}

function IntProp($propname, $val, $add, $expand)
{
	if ($val -is [int])
	{
		&$add $propname $($val.GetType().FullName) `
			  $('{0} = 0x{0:X8}' -f $val)
		$true
	}
}

#function DateTimeProp($propname, $val, $add, $expand) {
#	if ($val -is [DateTime] -and -not(IsSaneDate $val)) {
#		&$add $propname $($val.GetType().FullName) `
#			$('{0} = 0x{0:X16}' -f $val.ToFileTime())
#		$true
#	}
#}

function AddRowsFor($details, $propname, $val, $expand)
{
	if ($val -is [Collections.IEnumerable] -and `
		$val -isnot [string] -and $val -isnot [byte[]])
	{
		$val.GetEnumerator() | %{ AddRowsFor $details $propname $_ }
		return
	}
	$add = {
		param ($pname,
			$typestr,
			$valstr,
			$delayload)
		if ($delayload)
		{
			$rindex = $details.Rows.Add($pname, $typestr, '[Double-click to show]')
			$details.Rows[$rindex].Tag = $valstr
		}
		else
		{
			$details.Rows.Add($pname, $typestr, $valstr)
		}
	}.GetNewClosure()
	if (ByteProp $propname $val $add $expand) { return }
	if (I64Prop $propname $val $add $expand) { return }
	if (SecDescProp $propname $val $add $expand) { return }
	if (AccessControlProp $propname $val $add $expand) { return }
	if (DNProp $propname $val $add $expand) { return }
	if (IntProp $propname $val $add $expand) { return }
	#if (DateTimeProp $propname $val $add $expand) { return }
	&$add $propname $val.GetType().FullName $val `
		  $($propname -eq 'gPLink' -and -not $expand)
}

function NewNode($direntry)
{
	$node = new-object Windows.Forms.TreeNode -a $direntry.Name -pr @{
		Tag  = $direntry
	}
	[void]$node.Nodes.Add($(new-object Windows.Forms.TreeNode `
									   -a 'Loading...' -pr @{ Name = 'LoadingNode' }))
	$node
}

function GetWindow()
{
	$AddRowsFor = gi function:AddRowsFor
	$NewNode = gi function:NewNode
	$conndlg = GetConnDlg
	
	$connectcmd = new-object Windows.Forms.ToolStripMenuItem -pr @{
		ShortcutKeys  = [Windows.Forms.Keys] 'Control, O'
		Text		  = '&Open'
	}
	$quitcmd = new-object Windows.Forms.ToolStripMenuItem -pr @{
		ShortcutKeys  = [Windows.Forms.Keys] 'Alt, F4'
		Text		  = '&Quit'
	}
	$filemenu = new-object Windows.Forms.ToolStripMenuItem -pr @{
		Text  = '&File'
	}
	$filemenu.DropDownItems.AddRange(($connectcmd, $quitcmd))
	$menu = new-object Windows.Forms.MenuStrip
	$menu.Items.AddRange(($filemenu))
	
	$window = new-object Windows.Forms.Form -pr @{
		ClientSize  = new-object Drawing.Size -a 600, 400
		MainMenuStrip = $menu
		Text	    = 'AD-Explorer'
	}
	$quitcmd.Add_Click({ $window.Close() }.GetNewClosure())
	
	$details = new-object Windows.Forms.DataGridView -pr @{
		AllowUserToAddRows	   = $false
		AllowUserToDeleteRows  = $false
		AutoSizeRowsMode	   = [Windows.Forms.DataGridViewAutoSizeRowsMode]::AllCells
		AutoSizeColumnsMode    = [Windows.Forms.DataGridViewAutoSizeColumnsMode]::AllCells
		Dock				   = [Windows.Forms.DockStyle]::Fill
		ReadOnly			   = $true
	}
	'Name', 'Type', 'Value' | %{
		[void]$details.Columns.Add(
			$(new-object Windows.Forms.DataGridViewTextBoxColumn -pr @{
					HeaderText  = $_
					Name	    = $_
				})
		)
	}
	$details.Columns['Value'].DefaultCellStyle = new-object Windows.Forms.DataGridViewCellStyle -pr @{
		WrapMode  = [Windows.Forms.DataGridViewTriState]::True
	}
	$details.Add_CellDoubleClick({
			param ($sender,
				$e)
			if ($e.ColumnIndex -eq 2)
			{
				$data = $details.Rows[$e.RowIndex].Tag
				if ($data -ne $null)
				{
					&$AddRowsFor $details $details[0, $e.RowIndex].Value $data $true
					$details.Rows.RemoveAt($e.RowIndex)
					$details.Sort($details.Columns['Name'], [ComponentModel.ListSortDirection]::Ascending)
				}
			}
		}.GetNewClosure())
	
	$tree = new-object Windows.Forms.TreeView -pr @{
		Dock  = [Windows.Forms.DockStyle]::Fill
	}
	$tree.Add_AfterSelect({
			param ($sender,
				$e)
			[Windows.Forms.Application]::UseWaitCursor = $true
			$details.Rows.Clear()
			$e.Node.Tag.Properties.GetEnumerator() | %{
				[Windows.Forms.Application]::DoEvents()
				&$AddRowsFor $details $_.PropertyName $_.Value
			}
			$details.Sort($details.Columns['Name'], [ComponentModel.ListSortDirection]::Ascending)
			[Windows.Forms.Application]::UseWaitCursor = $false
		}.GetNewClosure())
	$tree.Add_AfterExpand({
			param ($sender,
				$e)
			if ($e.Node.Nodes.Count -eq 1 -and $e.Node.Nodes[0].Name -eq 'LoadingNode')
			{
				[Windows.Forms.Application]::UseWaitCursor = $true
				$e.Node.Tag.Children | %{
					[Windows.Forms.Application]::DoEvents()
					[void]$e.Node.Nodes.Add($(NewNode $_))
				}
				$e.Node.Nodes.RemoveByKey('LoadingNode')
				[Windows.Forms.Application]::UseWaitCursor = $false
			}
		})
	
	$Connect = {
		param ($to)
		[Windows.Forms.Application]::UseWaitCursor = $true
		[Windows.Forms.Application]::DoEvents()
		$node = &$NewNode $(new-object DirectoryServices.DirectoryEntry -a "LDAP://$to")
		$tree.Nodes.Add($node)
		[Windows.Forms.Application]::DoEvents()
		$tree.SelectedNode = $node
		[Windows.Forms.Application]::UseWaitCursor = $false
	}.GetNewClosure()
	$connectcmd.Add_Click({
			if ($conndlg.ShowDialog() -eq [Windows.Forms.DialogResult]::OK)
			{
				&$Connect $conndlg.Tag
			}
		}.GetNewClosure())
	$window.Add_Shown({
			$connserv = [Environment]::GetEnvironmentVariable('logonserver')
			if ($connserv)
			{
				if ($connserv.StartsWith('\\'))
				{
					$connserv = $connserv.Substring(2)
				}
				&$Connect $connserv
			}
		}.GetNewClosure())
	
	$split = new-object Windows.Forms.SplitContainer -pr @{
		Dock  = [Windows.Forms.DockStyle]::Fill
	}
	$split.Panel1.Controls.Add($tree)
	$split.Panel2.Controls.Add($details)
	$window.Controls.AddRange(($split, $menu))
	$window
}

[void] (GetWindow).ShowDialog()
