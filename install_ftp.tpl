<powershell>
Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled False
cd ../../../..
mkdir FTPRoot
Install-WindowsFeature Web-FTP-Server -IncludeAllSubFeature
Install-WindowsFeature Web-Server -IncludeAllSubFeature  -IncludeManagementTools
Import-Module WebAdministration
$FTPSiteName = 'Default FTP Site'
$FTPRootDir = 'C:\FTPRoot'
$FTPPort = 21
New-WebFtpSite -Name $FTPSiteName -Port $FTPPort -PhysicalPath $FTPRootDir -Force
$FTPUserGroupName = "FTP Users"
$ADSI = [ADSI]"WinNT://$env:ComputerName"
$FTPUserGroup = $ADSI.Create("Group", "$FTPUserGroupName")
$FTPUserGroup.SetInfo()
$FTPUserGroup.Description = "Members of this group can connect through FTP"
$FTPUserGroup.SetInfo()
$FTPUserName = "FTPUser"
$FTPPassword = 'P@ssword123'
$CreateUserFTPUser = $ADSI.Create("User", "$FTPUserName")
$CreateUserFTPUser.SetInfo()
$CreateUserFTPUser.SetPassword("$FTPPassword")
$CreateUserFTPUser.SetInfo()
$UserAccount = New-Object System.Security.Principal.NTAccount("$FTPUserName")
$SID = $UserAccount.Translate([System.Security.Principal.SecurityIdentifier])
$Group = [ADSI]"WinNT://$env:ComputerName/$FTPUserGroupName,Group"
$User = [ADSI]"WinNT://$SID"
$Group.Add($User.Path)
$FTPSitePath = "IIS:\Sites\$FTPSiteName"
$BasicAuth = 'ftpServer.security.authentication.basicAuthentication.enabled'
Set-ItemProperty -Path $FTPSitePath -Name $BasicAuth -Value $True
# Add an authorization read rule for FTP Users.
$Param = @{
    Filter   = "/system.ftpServer/security/authorization"
    Value    = @{
        accessType  = "Allow"
        roles       = "$FTPUserGroupName"
        permissions = 3
    }
    PSPath   = 'IIS:\'
    Location = $FTPSiteName
}
Add-WebConfiguration @param
$SSLPolicy = @(
    'ftpServer.security.ssl.controlChannelPolicy',
    'ftpServer.security.ssl.dataChannelPolicy'
)
Set-ItemProperty -Path $FTPSitePath -Name $SSLPolicy[0] -Value $false
Set-ItemProperty -Path $FTPSitePath -Name $SSLPolicy[1] -Value $false
$UserAccount = New-Object System.Security.Principal.NTAccount("$FTPUserGroupName")
$AccessRule = [System.Security.AccessControl.FileSystemAccessRule]::new($UserAccount,
    'ReadAndExecute',
    'ContainerInherit,ObjectInherit',
    'None',
    'Allow'
)
$ACL = Get-Acl -Path $FTPRootDir
$ACL.SetAccessRule($AccessRule)
$ACL | Set-Acl -Path $FTPRootDir
Restart-WebItem "IIS:\Sites\$FTPSiteName" -Verbose

$directoryPath = "C:\FTPRoot"

# Create a FileSystemWatcher to monitor the directory
$watcher = New-Object System.IO.FileSystemWatcher
$watcher.Path = $directoryPath
$watcher.Filter = "*.*"  # Monitor all files, you can adjust the filter if needed
$watcher.EnableRaisingEvents = $true

# Event handler for when a new file is created
$onCreated = Register-ObjectEvent $watcher "Created" -Action {
    $filePath = $Event.SourceEventArgs.FullPath

    # Determine the application to use based on the file extension
    $fileExtension = [System.IO.Path]::GetExtension($filePath)

    if ($fileExtension -eq ".docx" -or $fileExtension -eq ".doc") {
        $appName = "WINWORD.EXE"
    } elseif ($fileExtension -eq ".xlsx" -or $fileExtension -eq ".xls") {
        $appName = "EXCEL.EXE"
    } else {
        Write-Host "Unsupported file type: $fileExtension"
        return
    }

    # Launch the application with the new file
    Start-Process $appName $filePath
}

# Keep the script running
try {
    Write-Host "Monitoring directory: $directoryPath"
    Write-Host "Press Ctrl+C to stop..."
    while ($true) {
        Start-Sleep -Seconds 1
    }
} finally {
    # Clean up event subscriptions when exiting
    Unregister-Event -SourceIdentifier $onCreated.Name
    $watcher.Dispose()
}

</powershell>
