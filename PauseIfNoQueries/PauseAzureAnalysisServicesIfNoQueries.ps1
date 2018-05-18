<#
.SYNOPSIS
    Azure Automation runbook to pause Azure Analysis Services if no queries are running
.DESCRIPTION
    From https://github.com/furmangg/automating-azure-analysis-services#pauseifnoqueries
	A PowerShell script that is designed to run in an Azure Automation runbook that runs on a schedule.
	The runbook will pause Azure Analysis Services if no queries are running.
	The script requires the following Modules be imported in your Azure Automation account:
	 AzureRM.AnalysisServices
	 PackageManagement
.PARAMETER serverName
    The name of your Azure Analysis Services instance. This is not the full asazure:// URI. This is just the final section saying the name of your server.
.PARAMETER resourceGroupName
    The name of your Azure resource group where your Azure AS server resides.
.NOTES
    Author: Greg Galloway
    Date:   5/17/2018   
#>
param(
	[Parameter(Mandatory=$true)]
    [string] $serverName,
	
	[Parameter(Mandatory=$true)]
    [string] $resourceGroupName
)


function InstallAndLoadAdomdNet {
    $null = Register-PackageSource -Name nuget.org -Location http://www.nuget.org/api/v2 -Force -Trusted -ProviderName NuGet;
    $install = Install-Package Microsoft.AnalysisServices.AdomdClient.retail.amd64 -ProviderName NuGet;
    $dllPath = $install.Payload.Directories[0].Location + "\" + $install.Payload.Directories[0].Name + "\lib\net45\Microsoft.AnalysisServices.AdomdClient.dll";
    $bytes = [System.IO.File]::ReadAllBytes($dllPath)
    $null = [System.Reflection.Assembly]::Load($bytes)
}

function RunningSsasQueryCount([string]$connStr) {
 
    #if it's already in the GAC just run: [System.Reflection.Assembly]::LoadWithPartialName('Microsoft.AnalysisServices.AdomdClient');
    #in Azure Automation you need to install it from Nuget and load the assembly
    InstallAndLoadAdomdNet

    $conn = New-Object -TypeName Microsoft.AnalysisServices.AdomdClient.AdomdConnection;
    $conn.ConnectionString = $connStr
    $conn.Open();
    $cmd = New-Object -TypeName Microsoft.AnalysisServices.AdomdClient.AdomdCommand;
    $cmd.Connection = $conn;
    $cmd.CommandText = 'select SESSION_ID from $SYSTEM.DISCOVER_SESSIONS WHERE SESSION_STATUS=1 AND SESSION_IDLE_TIME_MS = 0 AND SESSION_ID<>' + "'" + $conn.SessionID + "'";
    $reader = $cmd.ExecuteReader();
    $iRows = 0;
    while ($reader.Read())
    {
        $iRows++;
    }
    $reader.Close();
    $conn.Close();
    return $iRows;
}

$ErrorActionPreference = "Stop";

$runAsConnectionProfile = Get-AutomationConnection -Name "AzureRunAsConnection"      
Add-AzureRmAccount -ServicePrincipal -TenantId $runAsConnectionProfile.TenantId `
        -ApplicationId $runAsConnectionProfile.ApplicationId -CertificateThumbprint $runAsConnectionProfile.CertificateThumbprint | Out-Null

$asServer = Get-AzureRmAnalysisServicesServer -ResourceGroupName $resourceGroupName -Name $serverName

"Current Azure AS status: $($asServer.State)"

if ($asServer.State -eq "Succeeded")
{
    [string]$serverFullName = $asServer.ServerFullName;
    [string]$appID = $runAsConnectionProfile.ApplicationId;
    [string]$thumb = $runAsConnectionProfile.CertificateThumbprint;
    [string]$connectionStr = "Data Source=$serverFullName;User ID=app:$appID;Initial Catalog=AzureAsDemo;Provider=MSOLAP;Persist Security Info=True; Impersonation Level=Impersonate;Password=cert:$thumb";

    $runningQueries = RunningSsasQueryCount($connectionStr);
    "Running queries: $runningQueries"
    if ($runningQueries -eq 0)
    {
        $asServer | Suspend-AzureRmAnalysisServicesServer -Verbose
    }
}

