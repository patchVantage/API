#!/bin/bash
#================================================================
# HEADER
#================================================================
#% SYNOPSIS
#+    backup.sh ...
#%
#% DESCRIPTION
#%    This script will backup an Oracle Database and send contents to AWS S3 Bucket
#%
#% Applications: - Regular Full RMAN backups for all your environments 
#
# Accelerate Innovation - Apply Infrastructure as Code
#
#================================================================
#- IMPLEMENTATION
#-    version         backup.sh  (www.patchvantage.com) 1.0.9
#-    author          David McNish(UK)/Rob Jopson(UK)   
#-    copyright       Copyright (c) http://www.patchvantage.com
#-    license         GNU General Public License
#-    script_id       3513 1.019
#-
#================================================================
#  HISTORY
#     2019/07/01 : dmmcnish : Script creation
#     2019/07/04 : jmendoza : S3 Bucket 
# 
#================================================================
#  GETTING STARTED 
#      Option 1 Login https://patchvantage.ai:8443/ords/f?p=101
#               An alert will direct you to download (a) Agent Install (b) Cliient Web Services
#      Option 2 Drop us an email at support@patchvantage.zendesk.com  
#  These scripts are available on github 
#  Please read the API Reference Manual and the Overview Document
#  Download and Install out agent to start patching from the Cloud  
#================================================================
#  NOTES 
#    1) Ensure ORDS has jdbc.statementTimeout=3600
#    2) Long Running Jobs apply
#    3) If the patch has not been uploaded to patchvantage.ai you must have attached 
#       a valid My Oracle Support with permissions to download patches 
#    4) For Debug : export PV_DEBUG=true
#                   export PV_CONSOLE=true  ( View Output on Screen )
#                   export PV_CONSOLE=false ( LogFile pv.log will be created )
#    5) To parse JSON in bash you must INSTALL jq 
#    6) For AWS Service Automation the patchVantage user attached to your ClientId must have configured the credentials
#================================================================
#   API USAGE 
#   is-aws_credentials-configured
#   is-ec2
#   ec2-instance-id
#   ec2-instance-type
#   ec2-instance-vcpu
#   ec2-instance-memory
#   aws
#   start-environments
#   get-load
#   ping-main
#   list-filesystems
#   backup-databases
#   send-message
#================================================================
# END_OF_HEADER
#================================================================

set_debug_on()
{
export PV_DEBUG=true
export PV_CONSOLE=true
}

set_debug_off()
{
export PV_DEBUG=false
export PV_CONSOLE=true
}

bold()
{
echo -e "\033[36m$1\033[0m"
}

set_vars()
{
# You can provide multiple environments seperated by comma or use an Environment Group
# 18c Database
RDBMS=ip-172-31-5-197.432.SALES
# Output is json or html
OUTPUT=json
# Wait for AWS Jobs to Complete before launching next step
WAIT=yes
# Full Path to web services
PV_PATH=pv
# Default patchVantage User(Messaging Only) - You must insert yours here !
PV_USER=dba1
# Start the AWS Based Instances attached to the Database
CONTROL_CLOUD=yes
# Start the Database(Not actually required for patching) 
START_DATABASE=no
# Web domain name of Cloud Server
MAIN_DB="patchvantage.ai"
# Turn on or off Debug Here(true or false) 
DEBUG_FLAG=false
#Send Alerts to the user of your choice
ALERTS=true 
export status=0
# Filesystem where backup to be placed,make this a real directory that exists if possible
# It must be owned by Oracle
#FS="/db.backup"
SUB_DIRECTORY=db.backup
# Send Backup to S3
S3=false
# Delay backup by set number of Hours
DELAY=0
# Wait for Backup to Finish
WAIT_DB=yes
}

success()       { str="" ;for i in $*; do str=$str" "$i; done; if [[ $str = *SUCCESS* ]]; then return 0; else return 1; fi               }
no_data()       { str="" ;for i in $*; do str=$str" "$i; done; if [[ $str = *No*Data* ]]; then return 0; else return 1; fi               }
applied()       { str="" ;for i in $*; do str=$str" "$i; done; if [[ $str = *APPLIED* ]]; then return 0; else return 1; fi               }
unapplied()     { str="" ;for i in $*; do str=$str" "$i; done; if [[ $str = *UNAPPLIED* ]]; then return 0; else return 1; fi             }
debug()         { str="" ;for i in $*; do str=$str" "$i; done; if [[ $str = *true* ]]; then set_debug_on; else set_debug_off; fi  }
job_succeeded() { str="" ;for i in $*; do str=$str" "$i; done; if [[ $str = *SUCCEEDED* ]]; then return 0; else return 1; fi             }
job_failed()    { str="" ;for i in $*; do str=$str" "$i; done; if [[ $str = *FAILED* ]]; then return 0; else return 1; fi                }
success()       { str="" ;for i in $*; do str=$str" "$i; done; if [[ $str = *SUCCESS* ]]; then return 0; else return 1; fi               }


AWS_Services()
{
if [[ $# < 1 ]] ;then  echo "Syntax error - AWS_Services . Abort!" ;exit 1 ; fi;
answer=`pv is-server-active --environment $2`
if [[ "$1" = "start" ]]
then
	if [[ "$answer" = "yes" ]] ;then  echo "EC2 Server is Active" ;return 0; fi;
fi
if [[ "$1" = "stop" ]]
then
	if [[ "$answer" = "no" ]] ;then  echo "EC2 Server is Down" ;return 0; fi;
fi

# Start Cloud EC2 Server 
if [ "${CONTROL_CLOUD}" = "yes" ]
then
	${PV_PATH} is-aws-credentials_configured;retcode=$?
	if [ ${retcode} -eq 0 ]
	then
		isEC2=`${PV_PATH} is-ec2 --environment $2`;retcode=$?
		if [ "${isEC2}" = "yes" -a ${retcode} -eq 0 ]
		then
			instanceID=`${PV_PATH} ec2-instance-id --environment $2`;retcode=$?
			if [ ${retcode} -eq 0 ]
			then
				aws_type=`${PV_PATH} ec2-instance-type --environment $2`;retcode=$?
				if [ ${retcode} -eq 0 ]
				then
					if [ "${aws_type}" = "none" ]
                                        then
                                                message="$1 $2 Server on Amazon instance-id=${instanceID}"
                                        else
                                                vcpu=`${PV_PATH} ec2-instance-vcpu --ec2-instance-type ${aws_type}`
                                                ram=`${PV_PATH} ec2-instance-memory --ec2-instance-type ${aws_type}`
                                                message="$1 $2 Server on Amazon instance-type=${aws_type} VCPU=${vcpu} RAM=${ram}Gb"
                                        fi
					if [ "${WAIT}" = "yes" ]
					then
						message=${message}"[Wait on Completion]"
					fi
					echo -e "\033[36m"$message"\033[0m"	
					${PV_PATH} aws --operation $1 --instance ${instanceID} --wait ${WAIT} 
					return $?
				fi
			else
				bold "Unable to acquire AWS InstanceId"
				return 1
			fi
		fi
	else
		bold "You have not applied your AWS credentials Setup in patchVantage correctly"
		return 1
	fi
else
	return 0
fi
}

start_Database()
{
if [ "${START_DATABASE}" = "yes" ]
then
	message="Start Database ${RDBMS}"
	if [ "${WAIT}" = "yes" ]
	then
		message=${message}"[Wait on Completion]"
	fi
	echo ${message} 
	json=`${PV_PATH} start-environments --environment-names [${RDBMS}] --wait yes`
	if [ $? -ne 0 ] ; then echo ${json};return 1; fi
	no_data ${json}
	retcode=$?
	if [ ${retcode} -eq 1 ]
	then
        	if [[ -n "${json/[ ]*\n/}" ]]
        	then
                	parsed=`echo $json| jq -r '.control_environment[] | .ENVIRONMENT + "#" + .STATUS'`
                	for pair in ${parsed}
                	do
                        	environment=`echo ${pair}|cut -d"#" -f1`
                        	status=`echo ${pair}|cut -d"#" -f2`
				if [ "${environment}" = "${RDBMS}" ]
				then
					job_succeeded ${status};retcode=$?
					if [ ${retcode} -eq 0 ]
					then
						echo "${RDBMS} was Started"
					else
						bold "${RDBMS} Failed to Start"
						return 1	
					fi
				fi
                	done
        	fi
	else
		bold "No concurrent jobs were located for ${RDBMS}"
		return 1
	fi
else
	return 0
fi

}

utils()
{
# Get dependencies
output=`command -v jq`
retcode=$?
if [ ${retcode} -ne 0 ]
then
        echo "Please install utility jq"
        exit 1
fi
output=`command -v python`
retcode=$?
if [ ${retcode} -ne 0 ]
then
        output=`command -v python2`
        retcode=$?
        if [ ${retcode} -ne 0 ]
        then
                echo "Please install utility python"
                exit 1
        fi
fi

}

db_load()
{
# Obtain on main Cloud Server
load=`${PV_PATH} get-load`
retcode=$?
if [ $retcode -ne 0 ]
then
        echo "*The Access Keys are Invalid or not prperly Configured"
        exit 1
fi
if [[ $load == *"Check Permissions"* ]]; then
        echo "The Access Keys are Invalid or not prperly Configured"
        exit 1
fi
if [ ${load} -le 0 ]
then
        echo "Unable to reach Cloud Server - Confirm Network and Access Credentials"
        exit 1
fi
if [ ${load} -lt 20 ]
then
        echo "${MAIN_DB} Load: LIGHT"
else
        if [ ${load} -lt 80 ]
        then
                echo "${MAIN_DB} Load: MODERATE"
        else
                bold "${MAIN_DB} Load: HEAVY"
        fi
fi
}

ping_server()
{
# Determine latency between you and Cloud Server

if [ -z "${PV_CLIENT_ID}" ]
then
        bold "Please configure PV_CLIENT_ID"
        exit 1
fi
if [ -z "${PV_CLIENT_KEY}" ]
then
        bold "Please configure PV_CLIENT_ID"
        exit 1
fi
if [ -z "${PV_WS_URL}" ]
then
        bold "Please configure PV_WS_URL"
        exit 1
fi


latency=`${PV_PATH} ping-main`
if [ -z "${latency}" ]
then
        bold "${MAIN_DB} Website is DOWN or you need to set PV_WS_URL"
else
        if (( $(echo "$latency > -1" | bc -l) )); then
        echo "${MAIN_DB} response time :"${latency}"(s)"
        db_load
        else
                bold "${MAIN_DB} Website is DOWN"
                exit 1
        fi
fi
}

is_filesystem_capacity()
{
if [[ $# < 2 ]] ;then  echo "Syntax error - is_filesystem_capacity . Abort!" ;exit 1 ; fi;

# Determine if Filesystem is big enough for Database 
# Will not work for /tmp and other root directories
# Size in Gb
json=`${PV_PATH} list-filesystems --environment $1`
if [ $? -ne 0 ] ; then echo ${json};return 1; fi
no_data ${json}
retcode=$?
if [ ${retcode} -eq 1 ]
then
	#mount_point=`findConcreteDirInPath $2`
	mount_point=$2
	echo "Mount Point="${mount_point}

        if [[ -n "${json/[ ]*\n/}" ]]
        then
                if jq -e . >/dev/null 2>&1 <<<"$json"; then
                        parsed=`echo $json| jq -r '.list_filesystems[] | .FILESYSTEM + "#" + .SIZE_GB'`
                        max_size=0
                        max_fs=none
                        for pair in ${parsed}
                        do
                                fs=`echo ${pair}|cut -d"#" -f1`
                                size=`echo ${pair}|cut -d"#" -f2`
				if [ "${fs}" = "${mount_point}" ]
				then
					#echo "Located Filesystem $fs"
					db_size=`${PV_PATH} database-size --environment $1`
                                	if (( $(echo "${size} >= ${db_size}" | bc -l) )); then
						echo "Operation can proceed : Mount Point Size=${size}Gb - Database Size=${db_size}Gb" 
						return 0
					else
						echo "Mount Point Size=${size}Gb which is not large enough(Database Size=${db_size}Gb)" 
						return 1
                                	fi
				fi
                        done
			# No match was found assume it works 
                        return 0 
                else
                        echo ${json}
                        return 1
                fi
        fi
else
        echo "No Data was returned from API"
        return 1
fi
}

get_max_fs()
{
if [[ $# < 1 ]] ;then  echo "Syntax error - get_largest_filesystem . Abort!" ;exit 1 ; fi;

# Check all the filesystems and obtain the one with most disk space for backup
# A second parameter can exclude certain filesystems such as ROOT
#
# Size in Gb
exclude=$2
json=`${PV_PATH} list-filesystems --environment $1`
if [ $? -ne 0 ] ; then echo ${json};return 1; fi
no_data ${json}
retcode=$?
if [ ${retcode} -eq 1 ]
then
	if [[ -n "${json/[ ]*\n/}" ]]
	then
		if jq -e . >/dev/null 2>&1 <<<"$json"; then
			parsed=`echo $json| jq -r '.list_filesystems[] | .FILESYSTEM + "#" + .SIZE_GB'`
			max_size=0
			max_fs=none
			for pair in ${parsed}
			do

				fs=`echo ${pair}|cut -d"#" -f1`
				size=`echo ${pair}|cut -d"#" -f2`
				#if [[ ! -z $2 ]]; then if [[ "$fs" -eq "x" ]]; then echo ROOT; fi; fi
			
				if [[ ! -z "$exclude" ]]; then if [[ "$fs" == "/" ]]; then continue; fi; fi


				if (( $(echo "${size} > ${max_size}" | bc -l) )); then
    					max_size=${size}
					max_fs=$fs	
				fi
			done
			echo ${max_fs}
			return 0
		else
			echo ${json}
			return 1 
		fi
	fi
else
	echo "No Data was returned from API"
	return 1 
fi
}

function findConcreteDirInPath() 
{
  local dirpath="$1"
  local stop="no"
  while [ $stop = "no" ] ; do
    if [ -d "$dirpath" ]; then
      local stop="yes"
    else
      local dirpath=$(dirname "$dirpath")
      if [ "$dirpath" = "" ] ; then
        local stop="yes"
        exit 1;
      fi
    fi
  done

  echo "$dirpath"
}

backup()
{
echo "Analyze Filesystems...."
if [[ $# < 1 ]] ;then  echo "Syntax error - backup . Abort!" ;exit 1 ; fi;

#
# Backups are removed to ensure continuity - conditions apply 
# 1) You must have either ADMIN privilge or be the owner 
# 2) Backups connected with Snap Shots are retained  
# 3) The existing database must still be present on patchVantage
#
last_date=`pv get-latest-backup --environment $1|cut -d"=" -f2`
set_name=`pv get-latest-backup --environment $1|cut -d"=" -f1`
echo "Latest Backup for $1 was created on: ${last_date}" 
if [ "${set_name}" !=  "none" ]
then
	echo "Removing any previous Backup ${set_name}" 
        pv remove-backup --set-name ${set_name}
	retcode=$?
	if [ $retcode -gt 0 ]
	then
		echo "No Existing Backups for your UID - Continue"
	fi
fi

[ -z "$FS" ] && default_fs=`get_max_fs $1 exclude_root` || default_fs=${FS}
retcode=$?
if [ ${retcode} -eq 0 ]
then
        # Does out filesystem contains enough space for backup ?
        is_filesystem_capacity $1 ${default_fs}
        retcode=$?
        if [ ${retcode} -eq 0 ]
        then
                if [ ${default_fs} == "/" ]
                then
                        default_fs=${default_fs}${SUB_DIRECTORY}
                fi
		if [ "${S3}" = "true" ]
          	then
			s3_copy=yes
 			${PV_PATH} is-aws-credentials_configured;retcode=$?
        		if [ ${retcode} -eq 0 ]
        		then
				message="[Apply S3 Bucket]"
			else
				bold "You have not applied your AWS credentials Setup in patchVantage correctly"
				exit 1	
			fi
		else
			s3_copy=no
			message="[No S3 Bucket]"
		fi
		message=$message"[Wait=${WAIT_DB}]"
		echo -e "\033[36m""Backup Database $1 to Filesystem ${default_fs}"${message}"\033[0m"
		if [ "${WAIT_DB}" = "yes" ]
		then
			json=`${PV_PATH} backup-databases --database-names $1 --type cold --stage ${default_fs} --s3 ${s3_copy} --wait yes`
		else
			json=`${PV_PATH} backup-databases --database-names $1 --type cold --stage ${default_fs} --s3 ${s3_copy} --delay ${DELAY}`
		fi
		retcode=$?
		echo "Backup Finished[Status=${retcode}]"
		if [ ${retcode} -eq 0 ]
		then
			echo ${json}
		else
			echo ${json}
			exit 1
		fi 
        else
                # You can also implement automated disk increases if EC2
                bold "There is not enough space on the server for this backup on mount point : ${default_fs}"
                exit 1
	fi
fi    
}

### BEGIN ###

set_vars
utils
debug ${DEBUG_FLAG}
ping_server
AWS_Services start ${RDBMS}
if [[ $? != 0  ]]; then exit 1 ;  fi
backup ${RDBMS}
json_tabular=`pv display-backups`
if [ "${json_tabular}" = "none" ]
then
	echo "Contact Support - No Record of Backup Exists"
else
	echo $json_tabular
fi
if [ "${WAIT_DB}" = "yes" ]
then
	AWS_Services stop ${RDBMS}
fi

### END ###
