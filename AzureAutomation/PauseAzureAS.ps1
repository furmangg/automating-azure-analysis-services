param(

	[Parameter(Mandatory=$true)]
    [string] $ServerName,

	[Parameter(Mandatory=$true)]
    [string] $ResourceGroupName

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



 # Get old status 
$OldAsSetting = Get-AzAnalysisServicesServer -ResourceGroupName $ResourceGroupName -Name $ServerName
$OldStatus = $OldAsSetting.State



if($OldStatus -eq "Paused")
 {
    Write-Output "Already Paused $($ServerName). Current status: $($OldStatus)" 

 }
 else
 {
   $null = Suspend-AzAnalysisServicesServer -ResourceGroupName $ResourceGroupName -Name $ServerName
   Write-Output "Pausing $($ServerName) Completed. Current status: $($OldStatus)" 

 }


