#!/bin/bash

# Define the file containing the list of IP addresses
IP_FILE="ip_list.txt"

# Check if the IP list file exists
if [ ! -f "$IP_FILE" ]; then
    echo "Error: The file '$IP_FILE' does not exist."
    echo "Please create a file named '$IP_FILE' and add one IP address per line."
    exit 1
fi

echo "Scanning IP addresses from '$IP_FILE'..."
echo "------------------------------------------------"

# Loop through each IP address in the file
while read -r ip_address; do
    # Skip empty lines
    if [ -z "$ip_address" ]; then
        continue
    fi
    echo "Scanning IP range '$ip_address'..."
    echo "------------------------------------------------"
    # Run nmap and parse the output
    nmap -sn "$ip_address" | grep "Nmap scan" | awk '{gsub(/[\(\)]/, "", $6); print "Hostname: " $5, "IP Address: " $6}'
    echo "------------------------------------------------"
done < "$IP_FILE"

echo "Scan complete."
