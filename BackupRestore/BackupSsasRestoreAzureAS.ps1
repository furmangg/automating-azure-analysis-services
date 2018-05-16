<#
	.SYNOPSIS
	Performs backups of one or more SQL Server Analysis Services Databases on a specified instance, uploads the backup to blob storage, then restores to Azure Analysis Services.

	.DESCRIPTION
	This script uses SQL Server Analysis Management Objects (AMO) to perform a native compressed backup of one or more databases on a SQL Server Analysis Services instance.

	Windows Authentication is used to connect to the Analysis Server.

	After backups are complete backup files older than the specified cleanup time (in hours) are removed from the backup directory. If no time is specified then no files are removed.

	Remoting is used to create backup directories and cleanup old backups if the script targets a computer that is not the local machine and the backup path is not a UNC path (i.e. the backup path is a drive leter). 

	For more information on how to enable PowerShell Remoting see http://technet.microsoft.com/en-us/library/hh849694.aspx

    Once backups are complete, the backups are uploaded to blob storage. Then blobs older than the specified retention period are deleted.

    Finally, the backup is restored to Azure Analysis Services from blob storage. The storage account specified for the upload of backups must match the storage account and container used for Azure Analysis Services' backup settings.
    
    Requires AMO v15 or higher. Download the AMO installer from https://docs.microsoft.com/en-us/azure/analysis-services/analysis-services-data-providers 

    Script from from http://1drv.ms/1EGqtUC
    from Kendal Van Dyke
    enhanced by Greg Galloway to encrypt backup and to upload to blob storage then delete local file then trim blob storage retention then restore to Azure Analysis Services
    from: https://github.com/furmangg/automating-azure-analysis-services

	.PARAMETER Instance
	Specifies the SQL Server Analysis Services instance name containing the database you want to copy. The default (non-named) instance is the default.

	.PARAMETER Database
	A comma delimited list of database names to backup. If not specified, all databases will be backed up. If no value is specified then no files are removed.

	.PARAMETER Directory
	The location where the backup file will be written. This should be accessible by the SQL Server Analysis Services instance where backups are taking place.

	Subdirectories will be created for the instance name (or computer name if using the default instance) and name of each database being backed up.

	If this parameter is not specified the backup directory specified in the Analysis Service instance's settings will be used.

    .PARAMETER BackupFilePassword
    The password for encrypting the SSAS backup

	.PARAMETER CleanupTimeHours
	The number of hours after which old backups of the specified database(s) will be deleted from the local folder. 

    .PARAMETER storageAccount
    The name of the Azure blob storage account to upload the backups into. Must match the account name used in the Azure Analysis Services backup settings.

    .PARAMETER storageKey
    The Azure blob storage account key

    .PARAMETER blobContainer
    The name of the container in Azure blob storage. Must match the container name used in the Azure Analysis Services backup settings.

    .PARAMETER BlobRetentionDays
    The number of days to retain backup files in Azure Blob storage before deletion

    .PARAMETER AzureASServer
    The server name for your Azure Analysis Services. In the format asazure://<region>.asazure.windows.net/<server>

    .PARAMETER aadAppID
    The Azure Active Directory application (service principal) application ID. Create this AAD application using these instructions: https://docs.microsoft.com/en-us/azure/azure-resource-manager/resource-group-create-service-principal-portal

    .PARAMETER aadAppSecret
    The Azure Active Directory application (service principal) secret key.

	.EXAMPLE
	.\BackupSsasRestoreAzureAS.ps1 -Instance TABULAR -Database 'Sales,Inventory' -CleanupTimeHours 48 -storageAccount storageaccthere -storageKey 'base64==' -blobContainer containername -BlobRetentionDays 7 -AzureASServer asazure://<region>.asazure.windows.net/<server> -aadAppID <clientID> -aadAppSecret '<secret>' -BackupFilePassword passwordHere

	This command backs up the Sales and Inventory databases on the TABULAR instance on localhost to the default backup directory and deletes backups older than 48 hours. It then uploads to the specified blob storage then trims any backups in blob storage older than 7 days. Finally it restores to the specified Azure Analysis Services.
#>
[cmdletBinding()]
param(
	[Parameter(Mandatory = $false)]
	[alias('Server')]
	[System.String]
	$Instance = $null
	,
	[Parameter(Mandatory = $false)]
	[System.String]
	$Database = $null
	,
	[Parameter(Mandatory = $false)]
	[alias('Path')]
	[System.String]
	$Directory = $null
	,
	[Parameter(Mandatory = $false)]
	[ValidateRange(1,2147483647)]
	[alias('CleanupTime')]
	[System.Int32]
	$CleanupTimeHours = $null
	,
	[Parameter(Mandatory = $false)]
	[System.String]
	$BackupFilePassword = $null
    ,
    [Parameter(Mandatory=$true)]
    [string]$storageAccount
    ,
    [Parameter(Mandatory=$true)]
    [string]$storageKey
    ,
    [Parameter(Mandatory=$true)]
    [string]$blobContainer
    ,
    [Parameter(Mandatory=$true)]
    [int]$BlobRetentionDays
    ,
    [Parameter(Mandatory=$true)]
    [string]$AzureASServer
    ,
    [Parameter(Mandatory=$true)]
    [string]$aadAppID
    ,
    [Parameter(Mandatory=$true)]
    [string]$aadAppSecret

)

$ErrorActionPreference = "Stop";

# Load AMO assembly
$assembly = [System.Reflection.Assembly]::LoadWithPartialName('Microsoft.AnalysisServices.Tabular');
$version = $assembly.GetName().Version.Major;
if ($version -lt 15)
{
    throw "AMO version 15 is required. The newest version installed is $version"
}

$BackupInfo = $null
$BackupPath = $null
$FileName = $null
$SafeDatabaseName = $null
$ComputerName = $env:COMPUTERNAME
$InstanceName = if ($Instance) { "$ComputerName\$Instance" } else { $ComputerName }
$DatabaseCollection = @()
$ErrorCount = 0

# Connect to the server
$Server = New-Object -TypeName Microsoft.AnalysisServices.Tabular.Server 
$Server.Connect($InstanceName)

# If a directory was not supplied then retrieve it from the Analysis server configuration
if (-not $Directory) {
	$Server.ServerProperties | Where-Object { $_.Name -ieq 'BackupDir' } | ForEach-Object {
		$Directory = $_.Value
	}
} else {
    # Append the instance name to the directory unless it's the default backup directory
    $Directory = [String]::Join([System.IO.Path]::DirectorySeparatorChar, @($Directory, $InstanceName))
}

# Build a collection of databases to backup based on parameters passed to script
if ($Database) {
	$DatabaseCollection += $Server.Databases | Where-Object { $Database.Split(",").Contains($_.Name) }
} else {
	$DatabaseCollection = $Server.Databases
}

# Iterate through each database that we want to backup and write a backup to the backup directory
$DatabaseCollection | Where-Object { $_.ID } | ForEach-Object {

	$SafeDatabaseName = $_.Name

	# Replace invalid filename characters with an underscore
	[System.IO.Path]::GetInvalidFileNameChars() | ForEach-Object {
		$SafeDatabaseName = $SafeDatabaseName.Replace($_, '_')
	}

	# Create the filename based on the current time
	$FileName = [String]::Join('_', @($SafeDatabaseName, 'FULL', [System.DateTime]::Now.ToString('yyyy_MM_dd_HH_mm')))

	# Build the backup directory path
	#$BackupPath = [System.IO.Path]::Combine($Directory, $_) #don't build folders by database name
    $BackupPath = $Directory;

	# Replace invalid backup path characters with an underscore
	[system.IO.Path]::GetInvalidPathChars() | ForEach-Object {
		$BackupPath = $BackupPath.Replace($_, '_')
	}


	try {

		# If the backup directory doesn't exist then try to create it.
		# If this script is not running on $ComputerName and the backup path is not a UNC path
		# then use remoting to check since $BackupPath could be a local on the target computer.
		if (($ComputerName -ieq $env:COMPUTERNAME) -or ($BackupPath -ilike '\\*')) {
			if ((Test-Path -Path $BackupPath) -ne $true) {
				New-Item -ItemType Directory -Path $BackupPath
			}
		} else {
			Invoke-Command -ComputerName $ComputerName -ArgumentList $BackupPath -ScriptBlock {
				$BackupPath = $args[0]
				if ((Test-Path -Path $BackupPath) -ne $true) {
					New-Item -ItemType Directory -Path $BackupPath
				}
			}
		}

		# Setup parameters to do the backup
		$BackupInfo = New-Object -TypeName Microsoft.AnalysisServices.BackupInfo
		$BackupInfo.AllowOverwrite = $true
		$BackupInfo.ApplyCompression = $true
		#$BackupInfo.BackupRemotePartitions = $true #comment this out if Tabular
		$BackupInfo.File = [System.IO.Path]::Combine($BackupPath, [System.IO.Path]::ChangeExtension($FileName, 'abf'))

        if ($BackupFilePassword)
        {
            $BackupInfo.Password = $BackupFilePassword; #encrypt
        }

		# Do the backup
		$_.Backup($BackupInfo)

        $storageAssemblyPath = $PSScriptRoot + "\Microsoft.WindowsAzure.Storage.dll"

        # Load the storage assembly without locking the file for the duration of the PowerShell session
        $bytes = [System.IO.File]::ReadAllBytes($storageAssemblyPath)
        $null = [System.Reflection.Assembly]::Load($bytes)

        $storageConnectionString = "DefaultEndpointsProtocol=https;AccountName=$storageAccount;AccountKey=$storageKey;EndpointSuffix=core.windows.net";
        $account = [Microsoft.WindowsAzure.Storage.CloudStorageAccount]::Parse($storageConnectionString)
        $client = $account.CreateCloudBlobClient()


        $cred = New-Object 'Microsoft.WindowsAzure.Storage.Auth.StorageCredentials' $storageAccount, $storageKey

        $bro = New-Object 'Microsoft.WindowsAzure.Storage.Blob.BlobRequestOptions'
        $bro.SingleBlobUploadThresholdInBytes = 1024 * 1024; #1MB, the minimum
        $bro.ParallelOperationThreadCount = 20;

        #$client = New-Object 'Microsoft.WindowsAzure.Storage.Blob.CloudBlobClient' "https://$storageAccount.blob.core.windows.net", $cred;
        $client.DefaultRequestOptions = $bro;
        #$client.SingleBlobUploadThresholdInBytes = 1024 * 1024; #1MB, the minimum
        #$client.ParallelOperationThreadCount = 20;

        $container = $client.GetContainerReference($blobContainer);
        $container.CreateIfNotExists();


        $blob = $container.GetBlockBlobReference([System.IO.Path]::GetFileName($BackupInfo.File));
        #$blob.StreamWriteSizeInBytes = 256 * 1024; #256 k

        $reader = [System.IO.File]::Open($BackupInfo.File, [System.IO.FileMode]"Open");
        $blob.UploadFromStream($reader);
        $reader.Close()

        #if successfully uploaded then delete the local file
        Remove-Item -Path $BackupInfo.File;

        $allBlobs = $container.ListBlobs();
        foreach($blob2 in $allBlobs)
        {
            if($blob2.Name.EndsWith(".abf") -and $blob2.Name.StartsWith($SafeDatabaseName))
            {
                $blobProperties = $blob2.Properties 
                if($blobProperties.LastModified.AddDays($BlobRetentionDays) -lt (Get-Date))
                {
                    echo "Deleting $($blob.Uri)";
                    $blob2.Delete();
                }
            }
        }

		try {

			# Cleanup old backups of this database - Delete ABF files older than the specified cleanup time
			# If this script is not running on $ComputerName the use remoting 
			# since $BackupPath could be a local on the target computer.
			if ($CleanupTimeHours) {
				if (($ComputerName -ieq $env:COMPUTERNAME) -or ($BackupPath -ilike '\\*')) {
					Get-ChildItem -Path $BackupPath -Filter "$SafeDatabaseName*.abf"| Where-Object { $_.LastWriteTime.AddHours($CleanupTimeHours).CompareTo($(Get-Date)) -le 0 } | Remove-Item
				} else {
					Invoke-Command -ComputerName $ComputerName -ArgumentList @($BackupPath, $SafeDatabaseName, $CleanupTimeHours) -ScriptBlock {
						$BackupPath = $args[0]
						$SafeDatabaseName = $args[1]
						$CleanupTimeHours = $args[2]
						Get-ChildItem -Path $BackupPath -Filter "$SafeDatabaseName*.abf"| Where-Object { $_.LastWriteTime.AddHours($CleanupTimeHours).CompareTo($(Get-Date)) -le 0 } | Remove-Item
					}
				}
			}
		}
		catch {
			$ErrorCount++
			Write-Error -ErrorRecord $_ -ErrorAction Continue
		}

		$RestoreInfo = New-Object -TypeName Microsoft.AnalysisServices.RestoreInfo
		$RestoreInfo.AllowOverwrite = $true
        $RestoreInfo.DatabaseName = $SafeDatabaseName
        $RestoreInfo.File = [System.IO.Path]::GetFileName($BackupInfo.File)

        if ($BackupFilePassword)
        {
            $RestoreInfo.Password = $BackupFilePassword; #encrypt
        }


        $amoAzureASServer = New-Object -TypeName Microsoft.AnalysisServices.Tabular.Server 
        $amoAzureASServer.Connect("Data Source=$AzureASServer;User ID=app:$aadAppID;Provider=MSOLAP;Persist Security Info=True;Impersonation Level=Impersonate;Password=$aadAppSecret")
        $amoAzureASServer.Restore($RestoreInfo);
        $null = $amoAzureASServer.Disconnect();
	}
	catch {
		$ErrorCount++
		Write-Error -ErrorRecord $_ -ErrorAction Continue
	}

}

# Disconnect from the server
$null = $Server.Disconnect

Remove-Variable -Name BackupInfo, BackupPath, FileName, SafeDatabaseName, InstanceName, DatabaseCollection

# If there were errors then throw a terminating error
if ($ErrorCount -gt 0) {
	throw "Experienced $ErrorCount errors during script processing"
}