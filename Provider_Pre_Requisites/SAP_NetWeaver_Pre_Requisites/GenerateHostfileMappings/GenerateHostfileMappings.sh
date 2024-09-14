# <copyright file="GenerateHostfileMappings.sh" company="Microsoft Corporation">
# Copyright (c) Microsoft Corporation. All rights reserved.
# </copyright>

#!/bin/bash

# Replace instance number with the instance number of the Central Server instance
instanceNumber=$1

# Set the path to the SAP hostctrl executable
if [ -d "/usr/sap/hostctrl/exe" ]
then
    cd "/usr/sap/hostctrl/exe"
else
    echo "SAP hostctrl directory not found" >&2
    exit 1
fi

# Get the hostnames of the SAP system instance
if [ -x "./sapcontrol" ]
then
	hosts=$(./sapcontrol -prot PIPE -nr $instanceNumber -format script -function GetSystemInstanceList)
else
    echo "sapcontrol executable not found" >&2
    exit 1
fi

# Handle known errors
if [[ -z "$hosts" ]]
then
    echo "Failed to get SAP system instances" >&2
	exit 1
elif [[ "$hosts" == *"NIECONN_REFUSED"* ]]
then
    echo "Wrong Instance Number" >&2
	exit 1
elif [[ "$hosts" == *"LD_LIBRARY_PATH"* ]]
then
    echo "Sapcontrol not executable" >&2
	exit 1
fi

# Filter the list of hosts to get the hostnames, instance numbers, features and display_statuses
hostnames=($(echo "$hosts" | grep "hostname" | cut -d " " -f 3))
instance_nos=($(echo "$hosts" | grep "instanceNr" | cut -d " " -f 3))
host_features=($(echo "$hosts" | grep "features" | cut -d " " -f 3))
display_statuses=($(echo "$hosts" | grep "dispstatus" | cut -d " " -f 3))

# Get the fully qualified domain name
fqdn=$(./sapcontrol -prot PIPE -nr $instanceNumber -format script -function ParameterValue | grep "SAPFQDN" | cut -d "=" -f 2 | tr -d '\r')
if [[ -z "$fqdn" ]]
then
    echo "Failed to get the FQDN" >&2
    exit 1
fi

# Declare an array to store the host file entries
hostfile_entries=()

# Declare an array to store already seen hosts
seen_hosts=()

get_ip_from_hostname () {
    ping_response=$(ping -c 1 -W 2 -q $1 2>&1)
	ping_return_code=$?
    if [[ $ping_return_code == 1 ]]
    then
        ping_response=$(ping -c 1 -W 2 -q $1 2>&1)
	    ping_return_code=$?
    fi
    if [[ $ping_return_code != 0 ]]
    then
        return 1
    fi
    echo $ping_response | cut -d "(" -f 2 | cut -d ")" -f 1
}

# Loop through the host features we have extracted
for i in "${!host_features[@]}"
do
    features=${host_features[$i]}
    hostname=${hostnames[$i]}
	display_status=${display_statuses[$i]}

    # If the current host is not an active app server, get the IP address by pinging the host and add it to the host file entries
    if [[ $features != *"ABAP"* || ( $features == *"ABAP"* && $display_status != "GREEN" ) ]]
    then
        ip=$(get_ip_from_hostname $hostname)
		if [[ $? == 1 ]]
		then
			echo "Failed to ping host: $hostname" >&2
        	exit 1
		fi
        host_key="$ip^$hostname"

        # Check that we don't add the same host twice
        if [[ ! " ${seen_hosts[*]} " =~ [[:space:]]${host_key}[[:space:]] ]]
        then
            seen_hosts+=("$host_key")
            hostfile_entries+="$ip $hostname.$fqdn $hostname,"
        fi
    fi

    # If the current host is the message server, construct the URI to get the list of app servers
    if [[ $features == *"MESSAGESERVER"* ]]
    then
        instance_no=${instance_nos[$i]}

        # Add a leading zero to the instance number if it is less than 10
        if [ $instance_no -lt 10 ]
        then
            instance_no="0$instance_no"
        fi

        app_server_list_uri="http://$hostname:81$instance_no/msgserver/xml/aslist"
    fi
done

# If there is no message server, throw error
if [[ -z "$app_server_list_uri" ]]
then
    echo "No message server found" >&2
    exit 1
fi

# Call the app server list API
app_servers_response=$(curl -s -w "http_code=%{http_code}\n" "$app_server_list_uri")
http_response_code=$(echo "$app_servers_response" | grep -oP "(?<=http_code=).*")

# If the API call was successful, extract the hostnames and IP addresses of the app servers and add them to the host file entries
if [[ "$http_response_code" == "200" ]]
then
    app_hostnames=($(echo "$app_servers_response" | grep -oP "(?<=<HOST>)[^<]+"))
    app_ips=($(echo "$app_servers_response" | grep -oP "(?<=<HOSTADR>)[^<]+"))

    # Loop over the extracted app server hostnames and IP addresses
    for i in "${!app_hostnames[@]}"
    do
        hostname=${app_hostnames[$i]}
        ip=${app_ips[$i]}
        host_key="$ip^$hostname"

        # Check that we don't add the same host twice
        if [[ ! " ${seen_hosts[*]} " =~ [[:space:]]${host_key}[[:space:]] ]]
        then
            seen_hosts+=("$host_key")
            hostfile_entries+="$ip $hostname.$fqdn $hostname,"
        fi
    done
# If the API call was not successful, fall back to pinging the app server hosts to get the IP addresses
else
    for i in "${!hostnames[@]}"
    do
        features=${host_features[$i]}
        hostname=${hostnames[$i]}
        display_status=${display_statuses[$i]}

        # Filter to get only the active app servers
        if  [[ $features == *"ABAP"* && $display_status == "GREEN" ]]
        then
            ip=$(get_ip_from_hostname $hostname)
            if [[ $? == 1 ]]
            then
                echo "Failed to ping host: $hostname" >&2
                exit 1
            fi
            host_key="$ip^$hostname"

            # Check that we don't add the same host twice
            if [[ ! " ${seen_hosts[*]} " =~ [[:space:]]${host_key}[[:space:]] ]]
            then
                seen_hosts+=("$host_key")
                hostfile_entries+="$ip $hostname.$fqdn $hostname,"
            fi
        fi
    done
fi

# Print the host file entries separated by commas
hostfile_entries=${hostfile_entries%?}
IFS=","
echo "${hostfile_entries[*]}"
