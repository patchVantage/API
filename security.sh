#!/bin/bash
#================================================================
# HEADER
#================================================================
#% SYNOPSIS
#+    security.sh ...
#%
#% DESCRIPTION
#%    This script applies the latest security patches to an Oracle Database 
#%
#% Applications: - Execute on a regular basis to automate security patching 
#
# Accelerate Innovation - Apply Infrastructure as Code
#
#================================================================
#- IMPLEMENTATION
#-    version         security.sh  (www.patchvantage.com) 1.0.28
#-    author          David McNish(UK)/Rob Jopson(UK)  
#-    copyright       Copyright (c) http://www.patchvantage.com
#-    license         GNU General Public License
#-    script_id       3513 1.0.29
#-
#================================================================
#  HISTORY
#     2019/07/01 : dmmcnish : Script creation
#     2019/07/04 : jmendoza : Added rollback
#     2019/09/03 : rjopson  : Testing and Review 
#     2019/09/19 : acohen   : Patch Timings 
#================================================================
#  GETTING STARTED 
#      Option 1 Login https://patchvantage.ai:8443/ords/f?p=101
#               An alert will direct you to download (a) Agent Install (b) Client Web Services
#      Option 2 Drop us an email at support@patchvantage.zendesk.com  
#  These scripts are available on github and their primary purpose is educational 
#  This script show 3 ways to apply security patches
#  a) Using the apply-security-patch method which applies the latest security bundle
#  b) Finding the latest security group and applying using the group method 
#  c) Find the latest  security group and applying each patch individually and waiting for result 
#
# Download and Install out agent to start patching from the Cloud
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
#    7) Patches are applied by force( --force yes ) by Default. Even if they have already been applied
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
#   apply-patches
#   describe-group-lines
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
RDBMS=ip-172-31-0-45.430.CRM
# Phase is apply or rollback
PHASE=apply
# Output is json or html
OUTPUT=json
# Wait for Jobs to Complete before launching next step
WAIT=yes
# Full Path to web services
PV_PATH=pv
# Default patchVantage User(Messaging Only) - You must insert yours here !
PV_USER=dba1
# Start the AWS Based Instances attached to the Database
CLOUD_CONTROL=yes
# Start the Database(Not actually required for patching) 
START_DATABASE=no
# Web domain name of Cloud Server
MAIN_DB="patchvantage.ai"
# Turn on or off Debug Here(true or false) 
DEBUG_FLAG=false
#Send Alerts to the user of your choice
ALERTS=true 
# Force Patch Application - Apply security patches even if they exist ( not advisable )
FORCE=true
# Apply Patches using Group command - not indivdually - this will be faster but no waiting is permitted
USER_GROUP_FUNCTION=true
export status=0
# Delay patching by set number of Hours
DELAY=0
# Apply Pre Checking - Takes longer but automatically upgrades opatch(yes or no )
PREREQ=no
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

# Start Cloud EC2 AWS Server
if [ "${CLOUD_CONTROL}" = "yes" ]
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
	bold ${message} 
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


read_patch_group()
{
if [[ $# < 1 ]] ;then  echo "Syntax error - apply_patch_group . Abort!" ;exit 1 ; fi;

# Extract patch or script components and apply patches as atomic transactions
# This is alternative to applying patches as a group within product
echo "Describe the elements in Group=${2}"
json=`${PV_PATH} describe-group-lines --group-name ${2}`

if [ $? -ne 0 ] ; then echo ${json};return 1; fi
no_data ${json}
retcode=$?
if [ ${retcode} -eq 1 ]
then
	if [[ -n "${json/[ ]*\n/}" ]]
	then
		if jq -e . >/dev/null 2>&1 <<<"$json"; then
			parsed=`echo $json| jq -r '.entities[] | .ACTION_CODE + "." + .ACTION_TYPE + "." + .PHASE  + "." + .ENABLED'`
			for pair in ${parsed}
			do
				operand=`echo ${pair}|cut -d"." -f1`
				entity=`echo ${pair}|cut -d"." -f2`
				phase=`echo ${pair}|cut -d"." -f3`
				enabled=`echo ${pair}|cut -d"." -f4`

				if [ "${enabled}" = "Y" ]
				then
					PHASE=${phase}
					PATCH=${entity}
					if [ "${operand}" = "opatch" ]
					then
						#
						# only apply if it does not already exist
						#
						is_applied=`${PV_PATH} is-patch-applied --environment $1  --patch ${PATCH}`
						if [ "${is_applied}" = "no" -o "${FORCE}" = "true" ]
						then
							# Apply each patch one at a time
							if [ "${ALERTS}" = "true" ]
        						then
								# Only alert user when a patch is going to be applied
								if [ "${PHASE}" = "apply" ]
								then
									echo "Applying Security Patch ${PATCH} to $1"
                        						json=`${PV_PATH} send-message --user ${PV_USER} --message "Applying Security Patch ${PATCH} to $1"`
								else
									"Removing Security Patch ${PATCH} from $1"
                        						json=`${PV_PATH} send-message --user ${PV_USER} --message "Removing Security Patch ${PATCH} from $1"`
								fi
								apply_patches $1 ${PATCH} ${PHASE};retcode=$?
								if [ ${retcode} -ne 0 ]
								then
                        						json=`${PV_PATH} send-message --user ${PV_USER} --message "Security Patch ${PATCH} Failed"`
								fi
							else	
								apply_patches $1 ${PATCH} ${PHASE};retcode=$1
							fi
						fi						
					fi
				fi	
			done
		else
			echo ${json}
			return 0
		fi
	fi
else
	echo "No Data was returned from API"
	return 1
fi
}

apply_patches()
{
if [[ $# < 2 ]] ;then  echo "Syntax error - apply_patches . Abort!" ;exit 1 ; fi;
if [ "${DEBUG_FLAG}" = "true" ]
then
	echo "Environment=$1"
	echo "Patch=$2"
	echo "Phase=$3"
	echo "Wait=${WAIT}"
fi

if [ "${PHASE}" = "apply" ]
then
	echo "Applying Patch $2 against Database $1"
else
	echo "Rolling Back Patch $2 against Database $1"
fi
json=`${PV_PATH} apply-patches --environment-names [$1] --phase $3 --patches [${2}] --wait ${WAIT} --output json`
if [ $? -ne 0 ] ; then echo ${json};return 1; fi
no_data ${json}
retcode=$?
jobsFailed=false
if [ ${retcode} -eq 1 ]
then
	if [[ -n "${json/[ ]*\n/}" ]]
	then
		if jq -e . >/dev/null 2>&1 <<<"$json"; then
			parsed=`echo $json| jq -r '.apply_patches[] | .JOB_NAME + "#" + .ENVIRONMENT + "#" + .STATUS + "#" + .ENTITY  '`
			for pair in ${parsed}
			do
				job=`echo ${pair}|cut -d"#" -f1`
				db=`echo ${pair}|cut -d"#" -f2`
				status=`echo ${pair}|cut -d"#" -f3`
				entity=`echo ${pair}|cut -d"#" -f4`
				if [ ! -z ${entity} ]
				then
					message="Patching RDBMS : ${db} JobID : ${job} Patch : ${entity} Status : ${status}"
					echo ${message}
				else
					message="Patching RDBMS : ${db} JobID : ${job} Status : ${status}"
					echo ${message}
				fi
				job_failed ${status};retcode=$?
                                if [ ${retcode} -eq 0 ]
                                then
                               		jobsFailed=true 
				fi
			done
			if [ "${jobsFailed}" = "true" ]
			then
				return 1
			fi
			return 0
		else
    			echo $json
			return 0 
		fi
	else
		return 1
	fi
else
	echo "No Data was returned from API"
	return 1

fi
return 1
}

latest_cpu()
{
# Get the latest CPU Group for the specific environment
CPU_GROUP=`${PV_PATH} get-latest-cpu --environment $1`
retcode=$?
if [ ${retcode} -eq  0 ]
then
	echo ${CPU_GROUP} 
else
 	if [ "${ALERTS}" = "true" ]
        then
		if [ "${CPU_GROUP}" = "none" ]
		then
        		json=`${PV_PATH} send-message --user ${PV_USER} --message "Important Notice : You need to configure an RDBMS Security group for $1"`
		else
			echo "Unable to locate Security Patches for Oracle"
			exit 1
		fi
	else
		if [ "${CPU_GROUP}" = "none" ]
		then
        		echo "Important Notice : You need to configure an RDBMS Security group for $1"
			exit 1
		else
			echo "Unable to locate Security Patches for Oracle"
			exit 1
		fi	
        fi
fi
}


is_group_applied()
{
if [[ $# < 1 ]] ;then  echo "Syntax error - is_group_applied . Abort!" ;exit 1 ; fi;
#Parameter1: Environment
#Paramater2: Group Name 
# Determine if any have NOT been applied from this Group
json=`${PV_PATH} describe-group-lines --group-name ${2}`
if [ $? -ne 0 ] ; then echo ${json};return 1; fi
no_data ${json}
retcode=$?
if [ ${retcode} -eq 1 ]
then
        if [[ -n "${json/[ ]*\n/}" ]]
        then
                if jq -e . >/dev/null 2>&1 <<<"$json"; then
                        parsed=`echo $json| jq -r '.entities[] | .ACTION_CODE + "." + .ACTION_TYPE + "." + .PHASE'`
                        for pair in ${parsed}
                        do
                                operand=`echo ${pair}|cut -d"." -f1`
                                entity=`echo ${pair}|cut -d"." -f2`
                                phase=`echo ${pair}|cut -d"." -f3`
                                if [ "${operand}" = "opatch" -a "${phase}" = "apply" ]
                                then
                                        PHASE=${phase}
                                        PATCH=${entity}
                                        if [ "${operand}" = "opatch" ]
                                        then
                                                #
                                                # only apply if it does not already exist
                                                #
                                                is_applied=`${PV_PATH} is-patch-applied --environment $1 --patch ${PATCH}`
                                                if [ "${is_applied}" = "no" ]
                                                then
							echo "true"
							return 0
                                                fi
                                        fi
                                fi
                        done
			echo "false"
			return 0
                else
			echo "false"
                        return 1 
                fi
        fi
else
	echo "false"
        return 1
fi
}

requestTier()
{
w_tier=`${PV_PATH} is-tier --environment $1`
if [ "${w_tier}" = "DB" ]
then
	echo "$1 is a Database"
fi
if [ "${w_tier}" = "HOST" ]
then
	echo "$1 is a Server"
fi
if [ "${w_tier}" = "APPS" ]
then
	echo "$1 is an Application"
fi
}

do_group()
{
RDBMS_SECURITY_GROUP=`latest_cpu ${RDBMS}`
retcode=$?
if [ "${RDBMS_SECURITY_GROUP}" = "None" -o "${retcode}" = "1" ]
then
        echo "No Security Group for this Environment Exists !"
else
	up_to_date=`is_group_applied  ${RDBMS} ${RDBMS_SECURITY_GROUP}`
        if [ "${up_to_date}" = "true" -a "${FORCE}" = "false" ]
        then
                echo "Latest Security Patches Confirmed"
        else
		if [ "${FORCE}" = "false" ]
                then
                	json=`${PV_PATH} apply_patch_group --environment-names ${RDBMS} --group-name  ${RDBMS_SECURITY_GROUP} --force no`;
                        echo $json
                else
                        json=`${PV_PATH} apply_patch_group --environment-names ${RDBMS} --group-name  ${RDBMS_SECURITY_GROUP} --force yes`;
                        echo $json
		fi
	fi
fi
}

do_patch()
{
RDBMS_SECURITY_GROUP=`latest_cpu ${RDBMS}`
retcode=$?
if [ "${RDBMS_SECURITY_GROUP}" = "None" -o "${retcode}" = "1" ]
then
        echo "No Security Group for this Environment Exists !"
else
        up_to_date=`is_group_applied  ${RDBMS} ${RDBMS_SECURITY_GROUP}`
        if [ "${up_to_date}" = "true" -a "${FORCE}" = "false" ]
        then
                echo "Latest Security Patches Confirmed"
        else
		# Apply one-at-atime and Wait for completion
                echo "Apply Each Patch one-at-a-time Wait for result - ${RDBMS_SECURITY_GROUP}"
                read_patch_group ${RDBMS} ${RDBMS_SECURITY_GROUP}
        fi
fi
}



### BEGIN ###

set_vars
utils
debug ${DEBUG_FLAG}
ping_server
requestTier ${RDBMS}
RDBMS_SECURITY_GROUP=`latest_cpu ${RDBMS}`
retcode=$?
if [ "${retcode}" = "1" ]
then
	echo "Unable to obtain a Security Groups for this Environment"
	exit 1 
fi
# Provide accurate information on DownTime
downtime=`pv patch-timing --entity  ${RDBMS_SECURITY_GROUP} --pre-process ${PREREQ}`
if [[ $downtime != none ]]; then echo "Duration ${downtime} Minutes"[Database will be Down]; fi
AWS_Services start ${RDBMS}
if [[ $? != 0  ]]; then exit 1 ;  fi
# Current default patch group for CRM is apr_cpu_2019_rdbms_18
# 
# DIRECT      = Use Security Patch api
# GROUP       = Use Security Group api
# PATCH       = Apply each patch element in Group 
API_METHOD=DIRECT
case ${API_METHOD} in

DIRECT)
	if  [ "${FORCE}" = "true" ]
	then
		# --force : reapply patches 
		json=`${PV_PATH} apply-security-patches --environment-names ${RDBMS} --force yes --delay ${DELAY} --prereq ${PREREQ}`
	else
		json=`${PV_PATH} apply-security-patches --environment-names ${RDBMS} --force no --delay ${DELAY} --prereq ${PREREQ}`
	fi
	echo -e "\033[36m"${json}"\033[0m"
	;;
GROUP)
	do_group
	;;
PATCH)
	do_patch 
        ;;
*)     echo "Invalid Patching Method"
esac

### END ###
