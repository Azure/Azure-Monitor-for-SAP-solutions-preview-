# <copyright file="GenerateHostfileMappings.ps1" company="Microsoft Corporation">
# Copyright (c) Microsoft Corporation. All rights reserved.
# </copyright>

param(
#[Parameter(Mandatory=$true)]]
[int]$instanceNumber
)

# Set the path to the SAP hostctrl executable
Set-Location -Path "C:\Program Files\SAP\hostctrl\exe"

# Get the hosts of the SAP system instance
$hosts = .\sapcontrol -prot NI_HTTP -nr $instanceNumber -format script -function GetSystemInstanceList
if (!$hosts)
{
    Write-Output "Failed to get SAP system instances"
    Exit 1
}

# Filter the list of hosts to get the hostnames, instance numbers and features
$hostnames = $hosts | Select-String -Pattern "hostname" | ForEach-Object {$_.Line.Split()[2]}
$instance_nos = $hosts | Select-String -Pattern "instanceNr" | ForEach-Object {$_.Line.Split()[2]}
$host_features = $hosts | Select-String -Pattern "features" | ForEach-Object {$_.Line.Split()[2]}

# Get the fully qualified domain name
$fqdn = .\sapcontrol -prot NI_HTTP -nr $instanceNumber -format script -function ParameterValue | Select-String -Pattern "SAPFQDN" | ForEach-Object {$_.Line.Split("=")[1]}
if (!$fqdn)
{
    Write-Output "Failed to get the FQDN"
    Exit 1
}

# Declare a set to store the host file entries
$hostfile_entries = New-Object System.Collections.Generic.HashSet[string]

# Loop through the host features we have extracted
for ($i=0; $i -lt $host_features.Length; $i++)
{
    $features = $host_features[$i]
    $hostname = $hostnames[$i]

    # If the current host is not an app server, get the IP address by pinging the host and add it to the host file entries
    if (-not($features -match "ABAP"))
    {
        $ping = Test-Connection -ComputerName $hostname -Count 1
        $ip = $ping.IPV4Address.IPAddressToString
        $hostfile_entries.add("$($ip) $($hostname).$($fqdn) $($hostname)")
    }

    # If the current host is the message server, construct the URI to get the list of app servers
    if ($features -match "MESSAGESERVER")
    {
        $instance_no = $instance_nos[$i]

        # Add a leading zero to the instance number if it is less than 10
        if ($instance_no -lt 10)
        {
            $instance_no = "0$($instance_no)"
        }
        $app_server_list_api = "http://$($hostname):81$($instance_no)/msgserver/xml/aslist"
    }
}

# Call the app server list API
try
{
    $app_server_response = Invoke-WebRequest -Uri $app_server_list_api
    $http_response_code = $app_server_response.StatusCode

}
catch
{
    $http_response_code = $_.Exception.Response.StatusCode.value__
}

# If the API call was successful, extract the hostnames and IP addresses of the app servers and add them to the host file entries
if ($http_response_code -eq "200")
{
    app_servers = ([xml]$app_server_response.Content).APPLICATION_SERVER.SERVER_LIST
    foreach ($app_server in $app_servers.item)
    {
        $hostfile_entries.add("$($app_server.HOSTADR) $($app_server.HOST).$($fqdn) $($app_server.HOST)")
    }
}
# If the API call was not successful, fall back to pinging the app server hosts to get the IP addresses
else
{
    for ($i=0; $i -lt $hostnames.Length; $i++)
    {
        $features = $host_features[$i]
        $hostname = $hostnames[$i]

        # Filter to get only the app servers
        if ($features -match "ABAP")
        {
            $ping = Test-Connection -ComputerName $hostname -Count 1
            $ip = $ping.IPV4Address.IPAddressToString
            $hostfile_entries.add("$($ip) $($hostname).$($fqdn) $($hostname)")
        }
    }
}
# Print the host file entries
$hostfile_entries -join ", "
