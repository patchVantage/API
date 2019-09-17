#!/bin/bash
#================================================================
# HEADER
#================================================================
#% SYNOPSIS
#+    clone.sh ...
#%
#% DESCRIPTION
#%    This script will clone data in minutes using dNFS feature of Oracle Databases
#%
#% Applications: - Create copies of large databases (+Data Masking) using fractional disk space in minutes
#                - Production Support Databases
#                - Provide Third party developers with data(GDPR compliant) 
#                - Sales Analytics 
#                - Agile sprint multiple copies of data
#
#  Accelerate Innovation - Apply Infrastructure as Code
#
#  Overview:
# 
#  Enterprise Edition contains a feature that enables rapid copies of large databases. The product also combines
#  this with data-masking to deliver secure versions. It requires a full backup (hot or cold) of the Oracle Databases
#  The backup must reside on the target host and this host must also have enough memory for each databases. 
#  You can easily configure a target host by running the script RDBMS_centOS7_AWS_nfs.sh - it can run on low cost Linux servers
#  Onnce the target has an NFS(3 or above) mount point and the patchVantage backup is in place a template is created. This will be used
#  many times to duplicate the data.
#  Large multi terrabyte backups can be created nightly using SSD such as ExaDrive from Nimbus
#
#  Memory:
# 
#  Checks are made based on the SGA of the target Databases to ensure enough memory
#  In future these could be combined with AWS to increase memory automatically by setting the instance type
#  For example ec2-instance-type and  ec2-instance-memory can be used to determine configuration 
#   
#  What this script does :
#
#  This script will make a clone of the HR databases ( see backup.sh )
#  Send message to users on a blackout list when done - these are fired according to each user(s) customized timezone 
#================================================================
#- IMPLEMENTATION
#-    version         clone.sh  (www.patchvantage.com) 1.0.3
#-    author          David McNish(UK)/Rob Jopson(UK)   
#-    copyright       Copyright (c) http://www.patchvantage.com
#-    license         GNU General Public License
#-    script_id       3513
#-
#================================================================
#  HISTORY
#     2019/07/01 : dmmcnish : Script creation
#     2019/07/04 : jmendoza : Linked Database Discovery with agent after Database is created 
# 
#================================================================
#  GETTING STARTED 
#      Option 1 Login https://patchvantage.ai:8443/ords/f?p=101
#               An alert will direct you to download (a) Agent Install (b) Cliient Web Services
#      Option 2 Drop us an email at support@patchvantage.zendesk.com  
#  These scripts are available on github 
#  please read the API Reference Manual and the Overview Document
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
# This is the 18c database from which the Clone was derived  
RDBMS=ip-172-31-22-213.311.HR
# Wait for AWS Jobs to Complete before launching next step
WAIT=yes
# Full Path to web services
PV_PATH=pv
# Start the AWS Based Instances attached to the Database
CONTROL_CLOUD=yes
# Web domain name of Cloud Server
MAIN_DB="patchvantage.ai"
# Turn on or off Debug Here(true or false) 
DEBUG_FLAG=false
# Wait for Clone to Finish
WAIT_CLONE=yes
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
if [[ $# < 2 ]] ;then  echo "Syntax error - AWS_Services . Abort!" ;exit 1 ; fi;
answer=`pv is-server-active --environment $2`
if [[ "$1" = "start" ]]
then
        if [[ $answer = "yes" ]] ;then  echo "EC2 Server is Active" ;return 0; fi;
fi
if [[ "$1" = "stop" ]]
then
        if [[ $answer = "no" ]] ;then  echo "EC2 Server is Down" ;return 0; fi;
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
                                                message="$1 Server on AWS instance-id=${instanceID}"
                                        else
                                                vcpu=`${PV_PATH} ec2-instance-vcpu --ec2-instance-type ${aws_type}`
                                                ram=`${PV_PATH} ec2-instance-memory --ec2-instance-type ${aws_type}`
                                                message="$1 Server on AWS instance-type=${aws_type} VCPU=${vcpu} RAM=${ram}Gb"
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
        echo "Please install utility python"
        exit 1
fi

}

db_load()
{
# Obtain on main Cloud Server
load=`${PV_PATH} get-load`
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
latency=`${PV_PATH} ping-main`

if (( $(echo "$latency > -1" | bc -l) )); then
    echo "${MAIN_DB} response time :"${latency}"(s)"
    db_load
else
    bold "${MAIN_DB} Website is DOWN"
    exit 1
fi
}

is_filesystem_capacity()
{
if [[ $# < 2 ]] ;then  echo "Syntax error - get_largest_filesystem . Abort!" ;exit 1 ; fi;

# Determine if Filesystem is big enough for Database 
# Will not work for /tmp and other root directories
# Size in Gb
json=`${PV_PATH} list-filesystems --environment $1`
if [ $? -ne 0 ] ; then echo ${json};return 1; fi
no_data ${json}
retcode=$?
if [ ${retcode} -eq 1 ]
then
	mount_point=`findConcreteDirInPath $2`
	#echo "Mount Point="${mount_point}

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
# Size in Gb
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

clone()
{
echo "Perform Pre-Checks...."
if [[ $# < 1 ]] ;then  echo "Syntax error - clone . Abort!" ;exit 1 ; fi;
echo "Snap Clone will be created from backup of $1 - Estimated time 10 Minutes"
# Obtain Template
clone_template=`${PV_PATH} get-latest-snap-config  --environment ${1}`
retcode=$?
if [ ${retcode} -eq 0 ]
then
        # Is there enough Memory for Clone ?
	sga_size=`${PV_PATH} snap-sga_size --configuration ${clone_template}`
        available_memory=`${PV_PATH} get-avail-memory --environment $1`	
	if (( $(echo "$available_memory > $sga_size" | bc -l) ))
        then
		if [ "${WAIT_CLONE}" = "yes" ]
		then
			json=`${PV_PATH} create-snap-clone  --snap-configurations  [${clone_template}] --wait yes --oratab no`
			retcode=$?
			# This time only send a message to nominated users on a Blackout List
	        	# The blackout list determines the times messages can be send
	        	# A user must subscribe to a list to receive notifications
			if [ ${retcode} -eq 0 ]
			then
				snapDB=`${PV_PATH} get-latest-snap  --snap-configuration ${clone_template}` 
				message="Created Snap Clone ${snapDB}"	
			else
				message="Unable to create Snap Clone using template ${clone_template}"	
				exit 1
			fi
			#echo ${message}
			${PV_PATH} send-message-blackout --message "${message}"
		else
			json=`create-snap-clone  --snap-configurations  [${clone_template}] --wait yes --oratab no`
			echo $json
		fi
        else
                # You can also implement automated disk increases if EC2
                echo "There is not enough memory on the server to complete Clone Operation"
                exit 1
	fi
else
	echo "Unable to locate an Clone Template for ${RDBMS}"
	exit 1
fi    
}

### BEGIN ###

set_vars
utils
debug ${DEBUG_FLAG}
ping_server
# Obtain latest Clone template and the Server(HOST) that we need to boot
# We are looking for the HR Template 
clone_template=`${PV_PATH} get-latest-snap-config  --environment ${RDBMS}`
retcode=$?
if [ $retcode -eq 0 ]
then
	# The Server used to create the clone does not necessarily reside with HR database
	Server=`${PV_PATH} get-snap-server  --snap-configuration ${clone_template}`
	retcode=$?
	if [ $retcode -eq 0 ]
	then
		echo "Start the EC2 Server ${Server}"
		AWS_Services start ${Server}
		if [[ $? != 0  ]]; then exit 1 ;  fi
		# Remove any previous Clones and create a new one
		# Wait for completion of this task
		echo "de-allocate previous Clone incarnations"
		response=`${PV_PATH} deallocate-snap  --snap-configuration ${clone_template}`
		# Create Snap Clone from HR
		clone ${RDBMS} 
	else
		echo "Unable to Locate the Server for ${clone_template} Configuration"
		exit 1 
	fi
else
	echo "Unable to locate an Clone Template for ${RDBMS}"
	exit 1
fi

### END ###
