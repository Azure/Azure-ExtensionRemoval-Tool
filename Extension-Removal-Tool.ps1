# Arthor: Steven from Microsoft Support
# Timeline: 4.5.2024 16:43
# Login into your account
Connect-AzAccount
 
# Subscription Id. The script run by each subscription
$subscriptionId = "Replace your subscription at line 7" # Only 1 subscription is accepted
 
# The VM Name which you may not want to uninstall extension. Keep the first comma.
$excludeVMNameList = @("", "", "") # Add more excluded VMs as needed
 
# The extension Name which you want to uninstall extension. Keep the first comma.
$uninstallExtensionNameList = @("MMAExtension", "MicrosoftMonitoringAgent", "OmsAgentForLinux", "DA-Extension")
 
# List of resource groups to search VMs in
$resourceGroupNames = @("", "") # Add more resource group names as needed, leave this blank if you wish to uninstall from VMs in all resource group(High risk)
# Example: $resourceGroupNames = @("zSteven", "che-rg-only-VM")
 
try {
    Select-AzSubscription -SubscriptionId $subscriptionId -ErrorAction Stop | Out-Null
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
    $resourceGroupNames = (Get-AzResourceGroup).ResourceGroupName
    Write-Host "Selected All ResourceGroups in subscription: $subscriptionId. " -ForegroundColor DarkGray
}
 
$jobs = @()
 
foreach ($resourceGroupName in $resourceGroupNames) {
    $resourceGroup = Get-AzResourceGroup -Name $resourceGroupName
 
    if ($resourceGroup -ne $null) {
        $vmList = Get-AzVM -ResourceGroupName $resourceGroupName
 
        foreach ($vm in $vmList) {
            $vmName = $vm.Name
            if ($excludeVMNameList -icontains $vmName) {
                Write-Host "VM: $vmName is in the excludeVMNameList, skip" -ForegroundColor DarkYellow
                Continue
            }
 
            $jobScriptBlock = {
                param($resourceGroupName, $vmName, $uninstallExtensionNameList, $excludeVMNameList)
                $vmExtensions = (Get-AzVM -ResourceGroupName $resourceGroupName -Name $vmName -Status).Extensions
                $isAnyExtensionProcessed = $false
 
                if (($null -ne $vmExtensions) -and ($vmExtensions.Count -gt 0)) {
                    foreach ($ext in $vmExtensions) {
                        if ($uninstallExtensionNameList -icontains $ext.Name) {
                            $isAnyExtensionProcessed = $true
                            # Write-Host "Removing Extension $($ext.Name) for VM: $vmName, from excludeVMNameList: $excludeVMNameList" -ForegroundColor Cyan
                            try {
                                Remove-AzVMExtension -ResourceGroupName $resourceGroupName -Name $ext.Name -VMName $vmName -Force -ErrorAction SilentlyContinue | Out-Null
                                Write-Host "Successfully removed Extension $($ext.Name) for VM: $vmName" -ForegroundColor Yellow
                            } catch {
                                Write-Host "Failed to remove Extension $($ext.Name) for VM: $vmName" -ForegroundColor Red
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
