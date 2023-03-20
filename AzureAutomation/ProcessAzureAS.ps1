<#
.SYNOPSIS
    Azure Automation runbook to process full an Azure Analysis Services database. It temporarily opens up the firewall to the current Azure Automation public IP.
.DESCRIPTION
    From https://github.com/furmangg/automating-azure-analysis-services#azureautomation
	A PowerShell script that is designed to run in an Azure Automation runbook that runs on a schedule.
	The runbook will process full the specified database. It will temporarily open the firewall to the current Azure Automation public IP.
	The Azure Automation runas account needs Contributor permissions on the Azure Analysis Services server and inside SSMS you need to grant that runas account server administrator permissions.
	The script requires the following Modules be imported in your Azure Automation account:
	 Az.AnalysisServices
	 PackageManagement
.PARAMETER serverName
    The name of your Azure Analysis Services instance. This is not the full asazure:// URI. This is just the final section saying the name of your server.
.PARAMETER resourceGroupName
    The name of your Azure resource group where your Azure AS server resides.
.PARAMETER CubeDatabaseName
    The name of your Azure AS database.
.NOTES
    Author: Greg Galloway
    Date:   11/19/2020
#>
param
(
    [Parameter (Mandatory = $true)]
    [string] $serverName,

    [Parameter (Mandatory = $true)]
    [string] $resourceGroupName,

    [Parameter (Mandatory = $true)]
    [string] $CubeDatabaseName
)

try
{
    "Logging in to Azure..."
    Connect-AzAccount -Identity
}
catch {
    Write-Error -Message $_.Exception
    throw $_.Exception
}

$asServer = Get-AzAnalysisServicesServer -ResourceGroupName $resourceGroupName -Name $serverName

"Current Azure AS status: $($asServer.State)"

if ($asServer.State -eq "Paused")
{
	$asServer | Resume-AzAnalysisServicesServer -Verbose
}

if ($asServer.FirewallConfig -ne $null)
{
    for ($i = 0; $i -lt $asServer.FirewallConfig.FirewallRules.Count; $i++)
    {
        $rule = $asServer.FirewallConfig.FirewallRules[$i];
        if ($rule.FirewallRuleName -eq "AzureAutomation")
        {
            $asServer.FirewallConfig.FirewallRules.Remove($rule);
            $i--;
        }
    }

    #backup the firewall rules
    $rulesBackup = $asServer.FirewallConfig.FirewallRules.ToArray()

    $ipinfo = Invoke-RestMethod http://ipinfo.io/json

    #add a new AzureAutomation firewall rule
    $newRule = New-AzAnalysisServicesFirewallRule -FirewallRuleName "AzureAutomation" -RangeStart $ipinfo.ip  -RangeEnd $ipinfo.ip
    $asServer.FirewallConfig.FirewallRules.Add($newRule)
    Set-AzAnalysisServicesServer -ResourceGroupName $resourceGroupName -Name $serverName -FirewallConfig $asServer.FirewallConfig

    "Updated Azure AS firewall to allow current Azure Automation Public IP: " + $ipinfo.ip
}
else
{
    "Azure AS Firewall is off"
}

function InstallAndLoadTOM {
    $null = Register-PackageSource -Name nuget.org -Location http://www.nuget.org/api/v2 -Force -Trusted -ProviderName NuGet;
    $install = Install-Package Microsoft.AnalysisServices.retail.amd64 -ProviderName NuGet;
    if ($install.Payload.Directories -ne $null)
    {
        $dllFolder = $install.Payload.Directories[0].Location + "\" + $install.Payload.Directories[0].Name + "\lib\net45\"
        Add-Type -Path ($dllFolder + "Microsoft.AnalysisServices.Core.dll")
        Add-Type -Path ($dllFolder + "Microsoft.AnalysisServices.Tabular.Json.dll")
        Add-Type -Path ($dllFolder + "Microsoft.AnalysisServices.Tabular.dll")
        $amoAzureASServer = New-Object -TypeName Microsoft.AnalysisServices.Tabular.Server 
        "Loaded Tabular Object Model assemblies"
    }
}

InstallAndLoadTOM

[string]$AzureAsServerFullName = $asServer.ServerFullName;
        
$amoAzureASServer = New-Object -TypeName Microsoft.AnalysisServices.Tabular.Server 
$amoAzureASServer.Connect("Data Source=$AzureAsServerFullName;User ID=app:" + $runAsConnectionProfile.ApplicationId + "@" + $runAsConnectionProfile.TenantId + ";Provider=MSOLAP;Persist Security Info=True;Impersonation Level=Impersonate;Password=cert:" + $runAsConnectionProfile.CertificateThumbprint)
"Connected to Azure AS"

$tmsl = '{
  "refresh": {
    "type": "full",
    "objects": [
      {
        "database": "' + $CubeDatabaseName + '"
      }
    ]
  }
}'

$results = $amoAzureASServer.Execute($tmsl);
foreach ($message in $results.Messages)
{
    if ($message.GetType().FullName -eq "Microsoft.AnalysisServices.XmlaError")
    {
        throw $message.Description
    }
    if ($message.GetType().FullName -eq "Microsoft.AnalysisServices.XmlaWarning")
    {
        "Warning $($message.Description)"
    }
}
"Done process full of database"

#restore old firewall config
if ($asServer.FirewallConfig -ne $null)
{
    #reset firewall to the state it was in before this script started
    $asServer.FirewallConfig.FirewallRules.Clear()
    $asServer.FirewallConfig.FirewallRules.AddRange($rulesBackup)
    Set-AzAnalysisServicesServer -ResourceGroupName $resourceGroupName -Name $serverName -FirewallConfig $asServer.FirewallConfig
    "Reset Azure AS firewall rules"
}
