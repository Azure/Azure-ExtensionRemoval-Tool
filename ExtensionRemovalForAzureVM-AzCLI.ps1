# Arthor: Steven Li from Microsoft Azure Monitor team
# Timeline: 7.17.2024 12:04 PM
# Login into your account
az login
 
# Subscription Id. The script run by each subscription
$subscriptionId = "" # Only 1 subscription is accepted
 
# The VM Name which you may not want to uninstall extension. Keep the first comma.
$excludeVMNameList = @("", "", "") # Add more excluded VMs as needed
 
# The extension Name which you want to uninstall extension. Keep the first comma.
$uninstallExtensionNameList = @("MMAExtension", "MicrosoftMonitoringAgent", "OmsAgentForLinux", "DA-Extension")
 
# List of resource groups to search VMs in
$resourceGroupNames = @("", "") # Add more resource group names as needed, leave this blank if you wish to uninstall from VMs in all resource group(High risk)
# Example: $resourceGroupNames = @("zSteven", "che-rg-only-VM")
 
try {
    az account set --subscription $subscriptionId | Out-Null
    Write-Host "Select Subscription: $subscriptionId" -ForegroundColor DarkGray
} catch {
    Write-Host "Failed to reach target Subscription: $subscriptionId" -ForegroundColor Red
    exit 1
}
 
$resourceGroupNames = $resourceGroupNames | Where-Object { $_ -ne "" }
 
if ($resourceGroupNames.Count -eq 0) {
    $confirm = Read-Host "It seems like you don't add any ResourceGroup Name at line 14. Do you want to select all ResourceGroups in subscription: $subscriptionId ? (y/n)"
    if ($confirm -ne 'y') {
        Write-Host "Operation cancelled by user." -ForegroundColor Yellow
        exit 0
    }
    $resourceGroupNames = az group list --query "[].name" -o tsv
    Write-Host "Selected All ResourceGroups in subscription: $subscriptionId. " -ForegroundColor DarkGray
}
 
$jobs = @()
 
foreach ($resourceGroupName in $resourceGroupNames) {
    $resourceGroup = az group show --name $resourceGroupName

    if ($resourceGroup -ne $null) {
        $vmList = az vm list --resource-group $resourceGroupName --query "[].name" -o tsv
 
        foreach ($vmName in $vmList) {
            if ($excludeVMNameList -icontains $vmName) {
                Write-Host "VM: $vmName is in the excludeVMNameList, skip" -ForegroundColor DarkYellow
                Continue
            }
 
            $jobScriptBlock = {
                param($resourceGroupName, $vmName, $uninstallExtensionNameList, $excludeVMNameList)
                $vmExtensions = az vm extension list --resource-group $resourceGroupName --vm-name $vmName --query "[].name" -o tsv
                $isAnyExtensionProcessed = $false
 
                if (($null -ne $vmExtensions) -and ($vmExtensions.Count -gt 0)) {
                    foreach ($ext in $vmExtensions) {
                        if ($uninstallExtensionNameList -icontains $ext) {
                            $isAnyExtensionProcessed = $true
                            # Write-Host "Removing Extension $($ext) for VM: $vmName, from excludeVMNameList: $excludeVMNameList" -ForegroundColor Cyan
                            try {
                                # Write-Host "$resourceGroupName, $vmName, $ext"
                                az vm extension delete --no-wait 0 --resource-group $resourceGroupName --vm-name $vmName --name $ext 
                                az vm extension wait --deleted --timeout 600 --interval 10 --resource-group $resourceGroupName --vm-name $vmName --name $ext
                                Write-Host "Successfully removed Extension $($ext) for VM: $vmName" -ForegroundColor Yellow
                            } catch {
                                Write-Host "Failed to remove Extension $($ext) for VM: $vmName" -ForegroundColor Red
                                Write-Host $_
                            }
                        }
                    }
                    if ($isAnyExtensionProcessed -eq $false) {
                        Write-Host "VM: $vmName does not have any extension to be uninstalled by the uninstallExtensionNameList, skip." -ForegroundColor DarkCyan
                    }
                } else {
                    Write-Host "VM: $vmName does not have any extension or is not running, skip." -ForegroundColor DarkCyan
                }
            }
 
            $job = Start-Job -ScriptBlock $jobScriptBlock -ArgumentList $resourceGroupName, $vmName, $uninstallExtensionNameList
            $jobs += $job
        }
    } else {
        Write-Host "Resource group $resourceGroupName not found."  
    }
}
 
$jobs | Receive-Job -Wait -AutoRemoveJob
