
# Created for Sensible Business Solutions
#
# Read custom properties added to N-Central by Matt's related AMP
# Custom properties:
#   - "Serial Number"
#   - "Hardware ID Hash"
#
# Create CSV files (headerless) of format [Serial Number],$null,[Device Hardware Hash]
# Output to .\scripts\output\autopilot01\[client].csv
#
# NOTE: Generic wildcards filters are present here, but that logic is
#       designed for use in future projects, not to be changed.

# Required module
Import-Module ".\PS-NCentral"

#! ==== Constants below ====
[String]$api_username = "paul.gummerson+api-ncentral-readonly@sensible.com.au"
[String]$out_dir_main = ".\scripts\output\autopilot01\"






#! ==== Configuration below ====
#? Which client are we looking for? (*? wildcards available)
$customer_name_matching = "*"

#? What name should the endpoint match? (*? wildcards available)
$asset_name_matching = "*"

#? Which classes of endpoint are we looking for? (*? wildcards available)
$asset_classes_matching    = "*" # Whitelist (default = *)
$asset_classes_notmatching = ""  # Blacklist (default = "" to not blacklist any)






# Get password in a temporary, secure-ish manner (fix this up for future modules...)
Write-Host "Enter API key for $($api_username): "
[SecureString]$api_key = Read-Host -AsSecureString


# Create 'out' dir if necessary
if ($false -eq (Test-Path -Path $out_dir_main)) {
    New-Item -Path $out_dir_main -ItemType Directory
}


# Connect to the server
[PSCredential]$creds = New-Object System.Management.Automation.PSCredential($api_username, $api_key)
Write-Host "Attempting to connect to N-Central..."
$NC = New-NCentralConnection -ServerFQDN "ncentral.sensible.com.au" -PSCredential $creds -ErrorAction Break



# Prepare hash tables
[Int]$CLIENT_MASTER = 50 # Sensible top-level client ID
[HashTable]$map_clients_parent_to_children = @{}  # $var[id_of_parent_client] = (client1,client2,...)
[HashTable]$map_clients_id_to_name = @{}          # $var$this_parent] = "client name"
#?Not implemented---> [HashTable]$map_client_to_devices = @{}           # $var$this_parent]["device_serial_no"] = "device hardware hash"




# Get list of customer(s) filtered by name
Write-Host "Now building all clients tree"
Get-NCCustomerList
| Select-Object -Property customerid,customername,parentid
| ForEach-Object {
    $child_id   = $_.customerid
    $child_name = $_.customername
    $parent_id  = $_.parentid
    #?Write-Host "DEBUG: Encountered childid/childname/parentid $($child_id)/$($child_name)/$($parent_id)"
    # Add name to client table, if not already present
    if ($child_id -inotin $map_clients_id_to_name.Keys) {
        $map_clients_id_to_name[$child_id] = $child_name
        #?Write-Host "DEBUG: Added name to list"
    }
    # Add as new or additional child of parent (or add as a parent, if it has no parent or is a child of $CLIENT_MASTER)
    # Do this by setting parent=child if they are top-level, then either append or add the child to the parent's child list
    if ($CLIENT_MASTER -eq $parent_id) {
        $parent_id = $child_id
        #?Write-Host "DEBUG: Determined to be parent instead of child"
    }
    if ($parent_id -iin $map_clients_parent_to_children.Keys) {
        #?Write-Host "DEBUG: Parent ID ($($parent_id)) found in map"
        # Only append if not already present in child list
        if ($child_id -inotin $map_clients_parent_to_children[$parent_id]) {
            #?Write-Host "DEBUG: Determined to be not in child list for parent ID ($($parent_id))"
            $map_clients_parent_to_children[$parent_id] = $map_clients_parent_to_children[$parent_id] + @($child_id)
        }
        #?else { Write-Host "DEBUG: Determined to already be present in child list for parent ($($parent_id))"}
    }
    else {
        #?Write-Host "DEBUG: Determined first time parent entry ($($parent_id))"
        $map_clients_parent_to_children[$parent_id] = @($child_id)
    }
    #?Write-Host "DEBUG: New map path $($parent_id) => $($map_clients_parent_to_children[$parent_id])"
}
# DEBUG OUTPUT
#Write-Host "`n`n`nCustomers found matching filter '$($customer_name_matching)': $($map_clients_id_to_name.Keys.Count)"
#Write-Host "Parent clients found: $($map_clients_parent_to_children.Keys.Count)"
#Write-Host "`nDisplaying parent->child tree"
#Write-Host "Sensible (top level client #$($CLIENT_MASTER))"
#foreach ($key in $map_clients_parent_to_children.Keys) {
#    Write-Host "|"
#    Write-Host "|--$($map_clients_id_to_name[$key])"
#    $map_clients_parent_to_children[$key] | ForEach-Object {
#        # Don't write the child if it is the same as the parent!
#        if ($_ -ne $key) { Write-Host "|--|--$($map_clients_id_to_name[$_])" }
#    }
#}






#! Get devices for all identified clients here
[Array]$filtered_parent_clients = ($map_clients_parent_to_children.Keys | Where-Object { $map_clients_id_to_name[$_] -ilike $customer_name_matching })
Write-Host "DEBUG: Identified $($filtered_parent_clients.Count) parent clients who match filter '$($customer_name_matching)'"
foreach ($this_parent in $filtered_parent_clients) {
    #?Write-Host "DEBUG: Parent client ID ($($this_parent)) => '$($map_clients_id_to_name[$this_parent])' => ($($map_clients_parent_to_children[$this_parent]))"
    #?$combined_client_ids = $combined_client_ids + $map_clients_parent_to_children[$this_parent]
    $this_parent_children = $map_clients_parent_to_children[$this_parent]
    # Get the 2x custom properties per device, for all devices for all sub-clients of the current parent
    $this_parent_children_assets = (
        $this_parent_children | ForEach-Object {
            $this_child = $_
            $NC.DeviceList($this_child)
            | Select-Object -Property deviceid
        }
    )
    # Get all relevant devices (under this parent client) custom props, then store them to $assets_with_props
    $count_current = 0
    $count_total = $this_parent_children_assets.Count
    Write-Host "Downloading custom properties for $($count_total) devices under parent $($this_parent) ($($map_clients_id_to_name[$this_parent]))"
    $assets_with_props = (
        $this_parent_children_assets.deviceid | ForEach-Object {
            $count_current += 1
            $percent_completed = [math]::Round(($count_current/$count_total)*100,2)
            Write-Progress -Activity "Downloading" -Status "$($percent_completed)% Complete:" -PercentComplete $percent_completed
            $NC.DevicePropertyList($PSItem, $null, $null, $null, $false)
            #! Changed to auto-output the stupid way
            #| Select-Object -Property "DeviceID",@{Name="SerialNumber";Expression={$_."Serial Number"}},@{Name="HardwareHash";Expression={$_."Hardware ID Hash"}}
            | Select-Object -Property @{Name="SerialNumber";Expression={$_."Serial Number"}},@{Name="DUMMY_ENTRY_HERE";Expression={""}},@{Name="HardwareHash";Expression={$_."Hardware ID Hash"}}
            | Where-Object { `
                ($_.SerialNumber.length -gt 0 -and $_.HardwareHash.length -gt 0) `
                -and ($_.SerialNumber -ne "PCSerialNumber" -or $_.HardwareHash -ne "HardwareIDHash") `
            }
        }
    )
    # Clear the progress bar...
    Write-Progress -Activity "Downloading" -Status "Ready" -Completed
    Write-Host "DEBUG: Identified $($assets_with_props.Count) assets with desired properties populated, under parent $($this_parent)"
    # Output as CSV if >0 results!
    if ($assets_with_props.Count -gt 0) {
        Write-Host "DEBUG: Exporting CSV for $($map_clients_id_to_name[$this_parent])"
        #$assets_with_props | Export-Csv -Path "$($out_dir_main)$($map_clients_id_to_name[$this_parent]).csv" -NoTypeInformation
        $assets_with_props | ConvertTo-Csv -UseQuotes Never | Select-Object -Skip 1 | Out-File "$($out_dir_main)$($map_clients_id_to_name[$this_parent]).csv"
    }
}
























