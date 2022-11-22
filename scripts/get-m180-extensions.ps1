#! Set throttling configuration here
$LIMIT_DEVICES = 500 # Less than or equal to 500 devices, otherwise don't pull huge amounts of data on them




Import-Module ".\PS-NCentral"
[String]$api_username = "paul.gummerson+api-ncentral-readonly@sensible.com.au"

# Get password in a temporary, secure-ish manner (fix this up when calling less often!)
Write-Host "Enter API key for $($api_username): "
[SecureString]$api_key = Read-Host -AsSecureString







# Connect to the server
[PSCredential]$creds = New-Object System.Management.Automation.PSCredential($api_username, $api_key)
Write-Host "Attempting to connect to N-Central..."
$NC = New-NCentralConnection -ServerFQDN "ncentral.sensible.com.au" -PSCredential $creds -ErrorAction Break



if ($NC.IsConnected) {
    Write-Host "Connection successful! Continuing..."
}
else {
    # This never actually triggers, because the try-catch block I had attempted was overridden by the module apparently, so it is removed.
    Write-Host "Connection failed! Exiting..."
    exit
}


#Get-NCVersion -Full
#Get-NCDeviceLocal
#Get-NCDeviceID "ComputerName" | Get-NCDeviceStatus | Out-GridView






#! ===============================
#! ==== Configure search here ====
#! ===============================

#? Which client are we looking for?
#? (*? wildcards available)
$filter_customers = "Marist*"
#$filter_customers = "Sensible*H*O*"

#? What name should the endpoint match?
#? (*? wildcards available)
$filter_endpoint_name = "*"
#$filter_endpoint_name = "*NOR*"

#? Which classes of endpoint are we looking for?
#? (array list of desired classes)
# NOTE: Not yet functional
$filter_asset_classes = @(
    '0'
    '1'
)

#? Which custom properties should be returned?
#? (array list of desired properties)
$filter_custom_properties = @(
    "Browser Extension"
)
# KNOWN OPTIONS:
# "Browser Extension"
# "Serial Number"
# "Hardware ID Hash"










#! Configure which devices and properties to receive
[String]$PROPERTY_NAME = "Browser Extension"
[Int]$DEVICE_SINGLE_MARIST = 1488102797
[Int[]]$DEVICES_SINGLE_MARIST = @(1488102797)
[Int[]]$DEVICES_MULTIPLE_MARIST = @(1809450812,1488102797)


















# List devices (ID array, showProgress)
Write-Host "`n`n`nNC.DeviceGet(device IDs, showProgress)"
$NC.DeviceGet($DEVICES_SINGLE_MARIST, $true) | Format-List


# Device PSObject serialised information, various (last option is showProgress)
Write-Host "`n`n`nNC.DeviceAssetInfoExportDeviceWithSettings(device IDs,,,,,,ShowProgress)"
$NC.DeviceAssetInfoExportDeviceWithSettings($DEVICES_SINGLE_MARIST,$null,$null,$null,$null,$null,$true) | Format-List


# Single device - all services status
#! Takes a long time!
#       Write-Host "`n`n`nDeviceGetStatus(single device ID)"
#       $NC.DeviceGetStatus($DEVICE_SINGLE_MARIST) | Format-Table


# Device
Write-Host "`n`n`nNC.DevicePropertyList(Device IDs,,,,ShowProgress)"
$NC.DevicePropertyList($DEVICES_SINGLE_MARIST,$null,$null,$null,$true) | Format-List






$all_data = @()
ForEach ($id in $DEVICES_MULTIPLE_MARIST) {
    Write-Host "Device: $($id)"
    $property_id_number = $NC.DevicePropertyID($id, $PROPERTY_NAME)
    Write-Host "Property name '$($PROPERTY_NAME)' for device ID '$($id)' is number $($property_id_number)"
}
#$all_data | Format-Table -Property name,extensions
#$all_data | Export-Csv -Path ".\scripts\output\m180-extensions.csv"









$NC.CustomerList()
# NC.
# NC.DeviceGet(Device IDs, [Bool]ShowProgress)                                  => customerid, deviceid, deviceclass
# NC.DevicePropertyList(Device IDs, $null, $null, $null, [Bool]ShowProgress)    => DeviceID, "Browser Extension" => {{The data we require}}








































# Prepare empty hash table, which will be of the format $customers[customerID] = @{each data here}
[HashTable]$customers = @{}
# Prepare empty hash table, which will be of the format $assets[deviceID] = @{each data here}
[HashTable]$assets = @{}



# 1. Get list of customer(s) filtered by name
$customers_filtered = (
    Get-NCCustomerList
    | Where-Object { $_.customername -like $filter_customers }
    | Select-Object -Property customerid,customername,parentid,parentcustomername
    | ForEach-Object {
        $customers[$_.customerid] = [PSCustomObject]@{
            ID         = $_.customerid
            Name       = $_.customername
            ParentID   = $_.parentid
            ParentName = $_.parentcustomername
        }
    }
)
# DEBUG OUTPUT
Write-Host "`n`n`nCustomers found matching filter '$($filter_customers)': $($customers_filtered.Count) UNIQUE FOUND: $($customers.Count)"
$customers_filtered | Select-Object -First 2 | Format-Table



# 2. For each client, get list of endpoint(s) filtered by name
$devices_filtered_by_name = (
    Get-NCDeviceList -CustomerIDs ($customers_filtered.customerid)
    | Where-Object { ( `
        $_.longname -like $filter_endpoint_name `
        -or $_.uri -like $filter_endpoint_name `
        -or $_.discoveredname -like $filter_endpoint_name `
        ) }
    | Select-Object -Property deviceid,discoveredname,deviceclass,deviceclasslabel,licensemode,lastloggedinuser,stillloggedin,osid,supportedos,supportedoslabel
    | ForEach-Object {
        #! Come back here to add filtering by class...
        #!if ([Array]$list_of_classes -eq $_.deviceclasslabel) << This will whitelist. Consider blacklist approach instead?
        $assets[$_.deviceid] = [PSCustomObject]@{
            ID        = $_.deviceid
            Name      = $_.discoveredname
            Class     = $_.deviceclasslabel
            Licence   = $_.licensemode
            OS        = $_.supportedoslabel
            JSON_DUMP = $null
        }
    }
)
#! POSSIBLY ADD AGAIN TO SELECT-OBJECT ABOVE, ORIGINALS HERE: deviceid,sitename,longname,uri,discoveredname,deviceclass,deviceclasslabel,isprobe,licensemode,sourceuri,lastloggedinuser,stillloggedin,osid,supportedos,supportedoslabel,customerid,customername
# DEBUG OUTPUT
Write-Host "`n`n`Devices found matching filter '$($filter_endpoint_name)': $($devices_filtered_by_name.Count) UNIQUE FOUND: $($assets.Count)"
$devices_filtered_by_name | Select-Object -First 2 | Format-Table



# 3. For each device, acquire custom properties and save the "Browser Extension" property to the asset object
foreach ($asset in $assets)











#! CANCEL ALL BELOW OPERATIONS
exit
# 1. Get list of customer(s) filtered by name
$customers_filtered = (
    Get-NCCustomerList
    | Where-Object { $_.customername -like $filter_customers }
    | Select-Object -Property customerid,customername,externalid,externalid2,parentcustomername,parentid,programlevelid
)
# DEBUG OUTPUT
Write-Host "`n`n`nCustomers found: $($customers_filtered.Count)"
$customers_filtered | Select-Object -First 2 | Format-Table


# 2. For each client, get list of endpoint(s) filtered by name
$devices_filtered_by_name = (
    Get-NCDeviceList -CustomerIDs ($customers_filtered.customerid)
    | Where-Object { ( `
        $_.longname -like $filter_endpoint_name `
        -or $_.uri -like $filter_endpoint_name `
        -or $_.discoveredname -like $filter_endpoint_name `
        ) }
    | Select-Object -Property deviceid,sitename,longname,uri,discoveredname,deviceclass,deviceclasslabel,isprobe,licensemode,sourceuri,lastloggedinuser,stillloggedin,osid,supportedos,supportedoslabel
)
#! POSSIBLY ADD AGAIN TO SELECT-OBJECT ABOVE: customerid,customername
# DEBUG OUTPUT
Write-Host "`n`n`Devices found: $($devices_filtered_by_name.Count)"
$devices_filtered_by_name | Select-Object -First 2 | Format-Table






















#! CANCEL ALL BELOW OPERATIONS
exit

#3. For each device, get full info except for custom properties
$properties_per_device = @()
if ($devices_filtered_by_name.Count -le $LIMIT_DEVICES) {
    $properties_per_device = (
        Get-NCDeviceInfo -DeviceIDs ($devices_filtered_by_name.deviceid) -ShowProgress
    )
    # DEBUG OUTPUT
    Write-Host "`n`n`Devices with specified properties (not yet implemented) found: $($properties_per_device.Count)"
    $properties_per_device | Select-Object -First 2 | Format-List
}


# 4. For each device, extract the custom properties
$custom_properties_per_device = @()
if ($devices_filtered_by_name.Count -le $LIMIT_DEVICES) {
    $custom_properties_per_device = (
        Get-NCDevicePropertyList -DeviceIDs ($devices_filtered_by_name.deviceid) -ShowProgress
        | Select-Object -Property (@("deviceid","sitename","longname","uri","discoveredname")+$filter_custom_properties)
    )
    # DEBUG OUTPUT
    Write-Host "`n`n`Devices with specified custom properties found: $($custom_properties_per_device.Count)"
    $custom_properties_per_device | Select-Object -First 2 | Format-List
}


# 5. For each device, extract the service properties ("device status")
#Write-Host "Finding status of device(s)"
#$status_per_device = @()
#if ($devices_filtered_by_name.Count -le $LIMIT_DEVICES) {
#    $status_per_device = Get-NCDeviceStatus -DeviceIDs @(1488102797)
#
#    # DEBUG OUTPUT
#    Write-Host "`n`n`Devices with specified status (not yet implemented) found: $($status_per_device.Count)"
#    $status_per_device | Select-Object -First 10 | Format-List
#}

# 6. Get devices as asset objects
Write-Host "Getting asset object of device(s)"
$devices_as_objects = Get-NCDeviceObject -DeviceIDs @(1488102797)
$devices_as_objects | Format-List











