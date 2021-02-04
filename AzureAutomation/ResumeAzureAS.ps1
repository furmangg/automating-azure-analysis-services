param(

	[Parameter(Mandatory=$true)]
    [string] $ServerName,

	[Parameter(Mandatory=$true)]
    [string] $ResourceGroupName

)



$connectionName = "AzureRunAsConnection"
try
{
    # Get the connection "AzureRunAsConnection "
    $servicePrincipalConnection=Get-AutomationConnection -Name $connectionName         

    "Logging in to Azure..."
    Add-AzureRmAccount `
        -ServicePrincipal `
        -TenantId $servicePrincipalConnection.TenantId `
        -ApplicationId $servicePrincipalConnection.ApplicationId `
        -CertificateThumbprint $servicePrincipalConnection.CertificateThumbprint 
}
catch {
    if (!$servicePrincipalConnection)
    {
        $ErrorMessage = "Connection $connectionName not found."
        throw $ErrorMessage
    } else{
        Write-Error -Message $_.Exception
        throw $_.Exception
    }
}
$ErrorActionPreference = "Stop";




 # Get old status 
$OldAsSetting = Get-AzureRmAnalysisServicesServer -ResourceGroupName $ResourceGroupName -Name $ServerName
$OldStatus = $OldAsSetting.State



if($OldStatus -eq "Succeeded")
 {
    Write-Output "Already Online $($ServerName). Current status: $($OldStatus)" 

 }
 else
 {
   $null = Resume-AzureRmAnalysisServicesServer -ResourceGroupName $ResourceGroupName -Name $ServerName
   Write-Output "Resuming $($ServerName) Completed. Current status: $($OldStatus)" 

 }


