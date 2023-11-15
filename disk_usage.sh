#!/bin/bash
if [ "$1" = "" ]; then
	echo "Please specify compartment name as argument"
else
	echo "COMPARTMENT NAME IS $1"
	DISK_USAGE_CHECK="disk_usage_check.py"
	DATE_VAL=$(date +"%Y-%m-%dT%H:%M:%SZ")
	echo $DATE_VAL
	COMPARTMENT_ID=$(oci iam compartment list --name $1 --compartment-id-in-subtree true | jq '.data[0].id' | tr -d \")
	echo $COMPARTMENT_ID
	if [ "$COMPARTMENT_ID" != "" ]; then
		echo "compartment found"
		COMPUTE_LIST=$(oci compute instance list -c $COMPARTMENT_ID | jq '.data')
		COMPUTE_COUNT=$(jq -n "$COMPUTE_LIST" | jq length)
		echo $COMPUTE_COUNT
		if [ $COMPUTE_COUNT -gt 0 ]; then
			for ((i = 0 ; i <= ($COMPUTE_COUNT - 1) ; i++)); do
				COMPUTE_NAME=$(jq -n "$COMPUTE_LIST" | jq .["$i"] | jq '."display-name"' | tr -d \")
				COMPUTE_OCID=$(jq -n "$COMPUTE_LIST" | jq .["$i"] | jq '.id' | tr -d \")
				COMPUTE_IP=$(oci compute instance list-vnics --instance-id $COMPUTE_OCID | jq -r '.data[]."public-ip"')
				PSUTIL_STATUS=$(ssh -o StrictHostKeyChecking=no opc@$COMPUTE_IP pip list | grep -F psutil)
				if [ "$PSUTIL_STATUS" = "" ]; then
					echo "PSUTIL NOT AVAILABLE"
					echo "INSTALLING PS UTIL"
					ssh opc@$COMPUTE_IP sudo python3 -m pip install --upgrade pip
					ssh opc@$COMPUTE_IP sudo python3 -m pip install -U psutil
					PSUTIL_STATUS=$(ssh -o StrictHostKeyChecking=no opc@$COMPUTE_IP pip list | grep -F psutil)
				fi
				if [ "$PSUTIL_STATUS" != "" ]; then
					DISK_USAGE_VAL=$(cat $DISK_USAGE_CHECK | ssh -o StrictHostKeyChecking=no opc@$COMPUTE_IP python3 -)
					echo "DISK USAGE IS:"
					echo $DISK_USAGE_VAL
				fi
				echo $COMPUTE_NAME
				echo $COMPUTE_OCID
				echo $COMPUTE_IP
				echo $PSUTIL_STATUS
				echo "------"
				METRIC_JSON=$(jq -n --arg dateVal "$DATE_VAL" --arg compId "$COMPARTMENT_ID" --arg diskUsage "$DISK_USAGE_VAL" --arg computeName "$COMPUTE_NAME" '[{"namespace": "custom_metrics","compartmentId": $compId,"name": "disk_usage","dimensions": {"serverName": $computeName},"datapoints": [{"timestamp": $dateVal,"value": $diskUsage}]}]')
				echo $METRIC_JSON
				oci monitoring metric-data post --metric-data "$METRIC_JSON" --endpoint https://telemetry-ingestion.ap-hyderabad-1.oraclecloud.com
			done
		else
			echo "no compute instances found"
		fi
	else
		echo "compartment not found"
	fi
fi
