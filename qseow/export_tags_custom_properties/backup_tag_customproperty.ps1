# backup_tag_customproperty.ps1
#
# PowerShell script used to export all Qlik Sense tags and 
# custom properties to JSON and structured text files.
#
# The created files are date-stamped in the file name.
#
# Adapt the following fields before running on the Qlik Sense 
# server itself while logged in as the QS service account user:
# - UNC path to file share where files should be stored, in 
#   the $folderBase variable. This can be on the Sense server itself 
#   or on a remote file server.
# - Directory where the created tag files should be stored, in the 
#   $folderTags variable. Note that this variable contains a reference to
#   the $folderBase variable!
# - Directory where the created custom property files should be stored, 
#   in the $folderCustomProperties variable. Note that this variable 
#   contains a reference to the $folderBase variable!
# - Host name of Sense server, in the $host variable. Easiest way to 
#   get this is from the QMC: Nodes > Host name
#
# Running the script somewhere else (on Linux, macOS or a Windows server
# where the QlikClient certificate is not present) or as some other
# user will not work as the script looks for the QlikClient certificate
# in the current user's Windows repository.
#
# If the created files should be stored on a remote file share
# that require authentication, a username and password can be 
# set in the $destFolderUser and $destFolderPwd variables.
# The "net use..." command should also be enabled in this case.
#
# The script can be scheduled using the standard Windows scheduler 
# if so desired.

# ---------------------------
# Config options
$folderBase = "\\winsrv19-1\c$"
$folderTags = "$folderBase\backup\tags"
$folderCustomProperties = "$folderBase\backup\custom_properties"

# Note: the $hostName variable should contain the same host name that the 
# is used in Sense's self-signed certificate.
# Easiest way to find this is in the QMC: Nodes > Host name.
$hostName = "winsrv19-1.shared"

# Enable and configure the following lines if folderBase resides 
# on a Samba file share that requires authentication
#$destFolderUser = "domain\user"
#$destFolderPwd = "pwd"
# End config
# ---------------------------


# Authenticate to destination folder
#net use $folderBase /user:$destFolderUser $destFolderPwd

# Create paths if they do not exist
If(!(test-path "$folderTags")) {
    New-Item -ItemType Directory -Force -Path "$folderTags"
}
If(!(test-path "$folderCustomProperties")) {
    New-Item -ItemType Directory -Force -Path "$folderCustomProperties"
}


$hdrs = @{}
$hdrs.Add("X-Qlik-xrfkey","12345678qwertyui")
$hdrs.Add("X-Qlik-User","UserDirectory=Internal;UserId=sa_api")
$hdrs.Add("User-Agent","Windows")
$cert = Get-ChildItem -Path "Cert:\CurrentUser\My" | Where-Object {$_.Subject -like '*QlikClient*'}

# Tags
$url = "https://$($hostName):4242/qrs/tag/full?xrfkey=12345678qwertyui"
Invoke-RestMethod -Uri $url -Method Get -Headers $hdrs -Certificate $cert | Out-File $folderTags\tags_$((Get-Date).ToString('yyyy-MM-dd')).txt
Invoke-RestMethod -Uri $url -Method Get -Headers $hdrs -Certificate $cert | ConvertTo-Json | Out-File $folderTags\tags_$((Get-Date).ToString('yyyy-MM-dd')).json
 
# Custom properties
$url = "https://$($hostName):4242/qrs/custompropertydefinition/full?xrfkey=12345678qwertyui"
Invoke-RestMethod -Uri $url -Method Get -Headers $hdrs -Certificate $cert | Out-File $folderCustomProperties\custom_properties_$((Get-Date).ToString('yyyy-MM-dd')).txt
Invoke-RestMethod -Uri $url -Method Get -Headers $hdrs -Certificate $cert | ConvertTo-Json | Out-File $folderCustomProperties\custom_properties_$((Get-Date).ToString('yyyy-MM-dd')).json


# If you are using PowerShell >= 6.0 .0 you can add a parameter
# -SkipCertificateCheck to disregard any certificate errors
# when connecting to the Sense server. You can then use any host name or
# IP that resolves to the Sense server, i.e. no need for the
# host name in the $url variable to match the host name in the 
# QlikClient certificate.


# Write-Host "Removing files older than 30 Days"
Get-ChildItem $folderTags -Recurse -Force -ea 0 |
Where-Object {!$_.PsIsContainer -and $_.LastWriteTime -lt (Get-Date).AddDays(-30)} |
ForEach-Object {
   $_ | Remove-Item -Force
   $_.FullName | Out-File $folderTags\deletedlog.txt -Append
}

Get-ChildItem $folderCustomProperties -Recurse -Force -ea 0 |
Where-Object {!$_.PsIsContainer -and $_.LastWriteTime -lt (Get-Date).AddDays(-30)} |
ForEach-Object {
   $_ | Remove-Item -Force
   $_.FullName | Out-File $folderCustomProperties\deletedlog.txt -Append
}