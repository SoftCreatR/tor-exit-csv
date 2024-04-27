#!/bin/bash

output_txt="tor-exit.txt"
output_csv="tor-exit.csv"
geoip_dir="/opt/geoip"

db_json_url="https://softcreatr.dev/geo-lite2-database-list"
tor_list_url="https://api.softcreatr.dev/tor-exit-nodes.txt"

user_agent="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/123.0.0.0 Safari/537.36"

mkdir -p "$geoip_dir" || { echo "Failed to create directory $geoip_dir"; exit 1; }

echo "Fetching database URLs..."
response=$(curl -s -A "$user_agent" $db_json_url)
echo "Response from server: $response"

db_urls=$(echo $response | jq -r '.[] | select(.url != null) | .url')
if [ $? -ne 0 ] || [ -z "$db_urls" ]; then
    echo "Failed to download or parse database list from $db_json_url"
    exit 1
fi

echo "Downloading and extracting databases..."
echo "$db_urls" | while read url; do
    if [ -z "$url" ]; then continue; fi
    echo "Processing URL: $url"
    curl -s -A "$user_agent" -o "$geoip_dir/tmp_file.tar.gz" "$url"
    tar -xzvf "$geoip_dir/tmp_file.tar.gz" -C "$geoip_dir" --strip-components=1 --wildcards '*/GeoLite2-*.mmdb' || {
        echo "Failed to download or extract files from $url"
        exit 1
    }
    rm "$geoip_dir/tmp_file.tar.gz"
done

echo "Checking if database files are present..."
ls -l $geoip_dir

if [ ! -f "$geoip_dir/GeoLite2-City.mmdb" ] || [ ! -f "$geoip_dir/GeoLite2-ASN.mmdb" ]; then
    echo "Required database files not found in $geoip_dir."
    exit 1
fi

echo "IP,Network Prefix,ASN,Organization,City Name,Continent Code,Continent Name,Country ISO Code,Country Name,Is Country in European Union,Location Accuracy Radius,Location Latitude,Location Longitude,Location Time Zone,Postal Code,Registered Country ISO Code,Registered Country Name,Is Registered Country in European Union,Subdivision ISO Code,Subdivision Name" > "$output_csv"

sorted_ips=$(curl -s -A $user_agent $tor_list_url | sort -V)

echo "$sorted_ips" > "$output_txt"

echo "$sorted_ips" | while read ip; do
    if [[ -z "$ip" ]]; then continue; fi
    city_json=$(mmdbinspect -db "$geoip_dir/GeoLite2-City.mmdb" "$ip")
    asn_json=$(mmdbinspect -db "$geoip_dir/GeoLite2-ASN.mmdb" "$ip")
    
    echo $city_json | jq -r --arg ip "$ip" --argjson asn "$asn_json" '.[0].Records[0] | [
        $ip,
        .Network,
        ($asn[0].Records[0].Record.autonomous_system_number // 0),
        "\"\($asn[0].Records[0].Record.autonomous_system_organization // "")\"",
        (.Record.city.names.en // ""),
        (.Record.continent.code // ""),
        (.Record.continent.names.en // ""),
        (.Record.country.iso_code // ""),
        (.Record.country.names.en // ""),
        (.Record.country.is_in_european_union // false),
        (.Record.location.accuracy_radius // 0),
        (.Record.location.latitude // 0),
        (.Record.location.longitude // 0),
        (.Record.location.time_zone // ""),
        (.Record.postal.code // ""),
        (.Record.registered_country.iso_code // ""),
        (.Record.registered_country.names.en // ""),
        (.Record.registered_country.is_in_european_union // false),
        (.Record.subdivisions[0].iso_code // ""),
        (.Record.subdivisions[0].names.en // "")
    ] | @csv' | sed -e 's/"\([^"]*\)"/"\1"/g' >> "$output_csv"
done

exit 0
