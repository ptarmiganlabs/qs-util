# backup_data_connection.ps1
#
# PowerShell script to backup/export all data connections from a 
# client-managed Qlik Sense Enterprise on Windows (QSEoW) system.
#
# Data connection definitions are stored in a JSON file, whose file
# name includes the date when the export was done.
# 
# Adapt the following variables before running the script:
# - UNC path to file share where files should be stored, in 
#   the $folderBase variable. This can be on the Sense server itself 
#   or on a remote file server.
# - Directory where the created JSON files should be stored, in the 
#   $folder variable. Note that this variable contains a reference to
#   the $folderBase variable!
# - The URL to the JWT-enabled virtual proxy that should be used, in
#   the $jwtVirtualProxyUrl variable.
# - The JWT that will be used to authenticate with Sense, in the 
#   $ApiKey variable.
#
# If the created JSON files should be stored on a remote file share
# that require authentication, a username and password can be 
# set in the $destFolderUser and $destFolderPwd variables.
# The "net use..." command should also be enabled in this case.
#
# The script can in theory be executed from any OS where Qlik CLI and 
# PowerShell is available (including macOS and Linux), but it's still 
# recommended to run the script from the Sense server itself. 
#
# The script can be scheduled using the standard Windows scheduler 
# if so desired.


# ---------------------------
# Config options
$folderBase = "\\winsrv19-1\c$"
$folder = "$folderBase\backup\data_connections"
$jwtVirtualProxyUrl = "https://winsrv19-1/jwt"
$ApiKey = "eyJhbGciOiJSUzI1NiIsInR5c....."

# Enable and configure the following lines if folderBase resides 
# on a Samba file share that requires authentication
#$destFolderUser = "domain\user"
#$destFolderPwd = "pwd"
# End config
# ---------------------------

# Authenticate to destination folder
#net use $folderBase /user:$destFolderUser $destFolderPwd

# Create backup destination path if it does not already exist
If(!(test-path "$folder")) {
    New-Item -ItemType Directory -Force -Path "$folder"
}


# Create temporary authentication to QSEoW JWT-enabled virtual proxy
.\qlik context create tmp_qseow_ds_export --server "$jwtVirtualProxyUrl" --server-type windows --api-key "$ApiKey" --insecure
.\qlik context use tmp_qseow_ds_export


# Get full info about all data connections. Store to JSON file.
.\qlik qrs dataconnection full | Out-File $folder\data_connections_$((Get-Date).ToString('yyyy-MM-dd')).json

# Delete temporary auth context
.\qlik context rm tmp_qseow_ds_export


# Write-Host "Removing files older than 90 Days"
Get-ChildItem $folder -Recurse -Force -ea 0 |
Where-Object {!$_.PsIsContainer -and $_.LastWriteTime -lt (Get-Date).AddDays(-90)} |
ForEach-Object {
   $_ | Remove-Item -Force
   $_.FullName | Out-File $folder\deletedlog.txt -Append
}