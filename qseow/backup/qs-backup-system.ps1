
# Script should be executed on the server where the Postgres repository database is running.
# The script will connect to Sense servers as specified below, shutting down Sense services before doing the db backup.
# Once backup is done the Sense services will be started again.


# Automatic execution of this script assumes there is a pgpass.conf file present in the roaming profile of the user 
# executing the script. For user joewest this would mean 'C:\Users\joewest\AppData\Roaming\postgresql\pgpass.conf'
#
# To create that file, execute the following while in the C:\Users\joewest\AppData\Roaming\postgresql (in the case of user joewest) directory:
# "localhost:4432:$([char]42):postgres:ENTER_POSTGRES_PASSWORD_HERE" | set-content pgpass.conf -Encoding Ascii

# Regarding firewalls. The following ports must be allowed inbound on the various Sense servers, to allow for services to be stopped/started:
# TCP port: 80,139,443,445,5985,5986
# UDP port: 137,138
# Ephemeral ports: (TCP 1024-4999, 49152-65535)

# The script assumes a few things about the Qlik Sense environment that will be backed up:
# - Qlik Sense is installed in C:\Program Files\Qlik\Sense on all servers in the Sense cluster
# - Sense system data is stored in in C:\ProgramData\Qlik\Sense on all servers in the Sense cluster
# - There is a system file share c$ on all servers in the Sense cluster, and that the Windows user used to run the backup script has access to those file shares

# ------- Begin config -------

$Today = Get-Date -UFormat "%Y%m%d_%H%M"

# File share on which the target directory resides
# The target directory is where all backup files will be copied
$FileShare = "\\<IP, FQDN or host name>\<fileshare name>"

# User and password for connecting to the target file share.
# If the file share is on an Active Directory connected/enabled server 
# the DestFolderUser would be something like "domain\userid" 
$DestFolderUser = "<AD domain>\<user ID>"
$DestFolderPwd = "<password>"

# Top level folder of backups, within the target file share
$FolderRoot = "$FileShare\backup\qlik_sense_system"

# Location of Postgres binary files
$PostgresLocation = "C:\Program Files\Qlik\Sense\Repository\PostgreSQL\9.6\bin"

# Qlik Sense app related files, for example QVDs, CSVs, config files etc.
# Enable/disable depending on whether this set of files should be included or not
# $SenseAppFiles = "\\<IP, FQDN or host name for file server>\appdata"

# Qlik Sense system related files, for example app QVFs, search indexes etc.
$SenseSystemFiles = "\\<IP, FQDN or host name for file server>\sensedata"

# Cutoff for removal of old app indexing files. Index files older than this many days will be deleted.
$SearchIndexDaysCutoff = 30

# Cutoff for removal of old system log files. Log files older than this many days will be deleted.
$SystemLogFilesDaysCutoff = 400

# Servers where Qlik Sense services are running.
$servers = @(
  "<IP, FQDN hostname or host name of 1st Sense server>"
  "<IP, FQDN hostname or host name of 2nd Sense server>"
  "<IP, FQDN hostname or host name of 3rd Sense server>"
)

# ------- End config -------



# Directory where data from this particular backup run will be stored
# Each backup run is stored in its own date-named directory
$folder = "$FolderRoot\$((Get-Date).ToString('yyyy-MM-dd'))"

# Authenticate. May not be needed if backup destination is in same Windows domain as QS server.
# This auth gives the backup script access to the top folder or file share of $FolderRoot
net use $FileShare /user:$DestFolderUser $DestFolderPwd

# Create target directory if it does not exist
If(!(test-path "$folder")) {
    New-Item -ItemType Directory -Force -Path "$folder"
}


# Loop over all servers in the QSEoW cluster, shutting down all services on each.
foreach($server in $servers) {
    write-host "----------------------------------------------------"
    write-host "Copying certificates from $server...."
    Copy-Item -Path "\\$server\C$\ProgramData\Qlik\Sense\Repository\Exported Certificates" -Destination "$folder\$server" -Recurse -Force
    
    write-host "----------------------------------------------------"
    write-host "Copying custom config files from $server...."
    Copy-Item -Path "\\$server\C$\Program Files\Qlik\Sense\Repository\Repository.exe.config" -Destination "$folder\$server" -Force
    Copy-Item -Path "\\$server\C$\Program Files\Qlik\Sense\Proxy\Proxy.exe.config" -Destination "$folder\$server" -Force
    Copy-Item -Path "\\$server\C$\Program Files\Qlik\Sense\Scheduler\Scheduler.exe.config" -Destination "$folder\$server" -Force
    Copy-Item -Path "\\$server\C$\Program Files\Qlik\Sense\ServiceDispatcher\services.conf" -Destination "$folder\$server" -Force


    write-host ""   
    write-host "Stopping Qlik Services on $server...."

    # Suffix the Stop-Service command with "-WarningAction SilentlyContinue" to suppress warning messages when a service takes long to stop
    # Removing "-Verbose" will also reduce the amount of logging done.
    Get-Service -ComputerName $server -Name QlikSenseProxyService | Stop-Service -Verbose
    Get-Service -ComputerName $server -Name QlikSenseEngineService | Stop-Service -Verbose
    Get-Service -ComputerName $server -Name QlikSenseSchedulerService | Stop-Service -Verbose
    Get-Service -ComputerName $server -Name QlikSensePrintingService | Stop-Service -Verbose
    Get-Service -ComputerName $server -Name QlikSenseServiceDispatcher | Stop-Service -Verbose
    Get-Service -ComputerName $server -Name QlikSenseRepositoryService | Stop-Service -Verbose
    # Enable/disable as needed depending on whether log db is still in use or not
    # Get-Service -ComputerName $server -Name QlikLoggingService | Stop-Service -Verbose
}


Set-Location $PostgresLocation
write-host ""
write-host "Backing up PostgreSQL Repository Database ...."
.\pg_dump.exe -h localhost -p 4432 -U postgres -b -F t -f "$folder\QSR_backup_$Today.tar" QSR

# Enable/disable as needed depending on whether log db is still in use or not
# write-host "Backing up PostgreSQL Log Database ...."
# .\pg_dump.exe -h localhost -p 4432 -U postgres -b -F t -f "$folder\QLogs_backup_$Today.tar" QLogs


write-host "----------------------------------------------------"
write-host "Removing old search index files...."
$refDate = (Get-Date).AddDays(-$SearchIndexDaysCutoff)
Get-ChildItem -Path "$SenseSystemFiles\Apps\Search\" -Recurse -File | Where-Object { $_.LastWriteTime -lt $refDate } | Remove-Item -Force


write-host "----------------------------------------------------"
write-host "Removing old system log files...."
$refDate = (Get-Date).AddDays(-$SystemLogFilesDaysCutoff)
Get-ChildItem -Path "$SenseSystemFiles\ArchivedLogs\" -Recurse -File | Where-Object { $_.LastWriteTime -lt $refDate } | Remove-Item -Force


    
write-host ""
write-host "Backing up Qlik Sense files ...."

# Copy Sense system files, including app QVF files, search indexes etc.
robocopy $SenseSystemFiles $folder\sensedata /e

# Copy Sense application data, for example QVDs, CSVs, config files etc. 
# Enable/disable depending on whether this set of files should be included or not
# robocopy $SenseAppFiles $folder\appdata /e


# Loop over all servers in the QSEoW cluster, starting all services on each.
foreach($server in $servers) {
    write-host ""
    write-host "Starting Qlik Services on $server...."

    Get-Service -ComputerName $server -Name QlikSenseProxyService | Start-Service -Verbose
    Get-Service -ComputerName $server -Name QlikSenseEngineService | Start-Service -Verbose
    Get-Service -ComputerName $server -Name QlikSenseSchedulerService | Start-Service -Verbose
    Get-Service -ComputerName $server -Name QlikSensePrintingService | Start-Service -Verbose
    Get-Service -ComputerName $server -Name QlikSenseServiceDispatcher | Start-Service -Verbose
    Get-Service -ComputerName $server -Name QlikSenseRepositoryService | Start-Service -Verbose
    # Enable/disable as needed depending on whether log db is still in use or not
    # Get-Service -ComputerName $server -Name QlikLoggingService | Start-Service -Verbose
}


write-host "----------------------------------------------------"
write-host "Removing old backups...."

# Remove old backup folders
Get-ChildItem $FolderRoot -Force -ea 0 |
Where-Object {$_.PsIsContainer -and $_.LastWriteTime -lt (Get-Date).AddDays(-30)} |
ForEach-Object {
    write-host "Removing old directory $FolderRoot\$_ "

    Remove-Item –recurse -force –path "$FolderRoot\$_" 
    $_.FullName | Out-File $FolderRoot\deletedlog.txt -Append
}
