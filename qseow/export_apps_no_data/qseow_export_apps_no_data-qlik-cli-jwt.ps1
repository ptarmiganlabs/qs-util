# PowerShell script that uses Qlik CLI (https://qlik.dev/libraries-and-tools/qlik-cli) to export all apps 
# in a client-managed Qlik Sense Enterprise on Windows (QSEoW) environment to disk.

# Apps are exported without data into date-named directories. 
# This means that two runs of the script on two different days will result in two separate snapshots
# off all apps in the Sense environment.

# Unpublished apps are stored in the top level folder.
# Separate sub-folders are created for each Sense stream.
# In these subfolders all apps published to each stream is then stored.
# 
# Apps are exported without data using a naming template of 
# <app name>_<app id>_<app owner user ID>.qvf

# The script deletes all app exports older than X days.
# All deleted folders are stored to a deletelog.txt file for traceability

# Metadata in JSON format for all apps is stored to a file called apps_metadata_<date>.json

# This script assumes a few things
# - Qlik CLI is available in the path
# - A JWT enabled QSEoW virtual proxy is available
# - There is a valid JWT that can be used to authenticate with QSEoW
# - There is a target file share on which the apps can be stored

# Ideas for future work
# - Take configuration from environment variables rather than hard coding it in the script.



# ------- Begin config -------

# File share on which the target directory resides
# The target directory is where all backup files will be copied
$FileShare = "\\<host, IP or FQDN of destination file share>\<file share name>"

# User and password for connecting to the target file share.
# If the file share is on an Active Directory connected/enabled server 
# the DestFolderUser would be something like "domain\userid" 
$DestFolderUser = "<AD domain>\<AD user>"
$DestFolderPwd = "<AD password>"

# Top level folder of backups, within the target file share
$FolderRoot = "$FileShare\backup\apps_no_data"

# Qlik Sense virtual proxy URL with JWT authentication
$JwtVirtualProxyUrl = "https://<host, IP or FQDN of Sense server>/<name of jwt enabled virtual proxy>"

# JWT used by Qlik CLI to authenticate with Qlik Sense
$ApiKey = "<JWT with access to the virtual proxy>"

# Cutoff for removal of old app indexing files. Index files older than this many days will be deleted.
$RemoveOldExportsDaysCutoff = 30

# ------- End config -------



# Directory where exported apps will be stored
# Each run is stored in its own date-named directory
$Folder = "$FolderRoot\$((Get-Date).ToString('yyyy-MM-dd'))"

# Authenticate. May not be needed if backup destination is in same Windows domain as QS server.
# This auth gives the script access to the top folder or file share of $FolderRoot
net use $FileShare /user:$DestFolderUser $DestFolderPwd

# Create path if it does not exist
If(!(test-path "$Folder")) {
    New-Item -ItemType Directory -Force -Path "$Folder"
}


# Create temporary authentication to QSEoW JWT-enabled virtual proxy
qlik context create tmp_qseow_app_export --server "$JwtVirtualProxyUrl" --server-type windows --api-key "$ApiKey" --insecure
qlik context use tmp_qseow_app_export

# Extract apps
$counter = 0
$appsJson = qlik qrs app full
$apps = $appsJson | ConvertFrom-Json

foreach($app in $apps) {
    ++$counter

    # Debug output
    # Write-Output $app

    if ($app.published -and $app.stream.name) {             
        # App is published, create folder and store app there
        $streamFolder = $app.stream.name
        If(!(test-path "$Folder\$streamFolder")) {
            # Create a folder if it does not exists
            New-Item -ItemType Directory -Force -Path "$Folder\$streamFolder"
        }
    } else {
        $streamFolder = ""
    }

    # Export app without data
    qlik qrs app export create $app.id --output-file "$($Folder)\$($streamFolder)\$($app.name)_$($app.id)_$($app.owner.userId).qvf" --skipdata
    
    Write-Host "$($counter) of $($apps.Count) Exported"
}

# Store full metadata to JSON file
Write-Host Store app metadata to JSON file $$Folder\apps_metadata_$((Get-Date).ToString('yyyy-MM-dd')).json
Write-Output $appsJson | Out-File $Folder\apps_metadata_$((Get-Date).ToString('yyyy-MM-dd')).json


# Delete temporary auth
qlik context rm tmp_qseow_app_export

# Removing old directories
Write-Host "Removing old folders"

Get-ChildItem $FolderRoot -Force -ea 0 |
Where-Object {$_.PsIsContainer -and $_.Name -match '^\d{4}\-(0[1-9]|1[012])\-(0[1-9]|[12][0-9]|3[01])$'} | 
ForEach-Object {
    if ([Datetime]::ParseExact($_, 'yyyy-MM-dd', $null) -lt (Get-Date).AddDays(-$RemoveOldExportsDaysCutoff) ) {
        Write-Host Removing $_...
        $_ | Remove-Item -Recurse -Force
    }
}
