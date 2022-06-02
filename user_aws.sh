#!/bin/bash
source $(dirname "$0")/__utils_aws__.sh
source $(dirname "$0")/__utils_yaml__.sh

## parse arguments
readonly aws_region="us-east-1"
#log "user_aws_region=" "${aws_region}"
#log "user_aws_service" "${aws_service}"

readonly timestamp=${timestamp-$(date -u +"%Y%m%dT%H%M%SZ")} #$(date -u +"%Y%m%dT%H%M%SZ") #"20171226T112335Z"
readonly today=${today-$(date -u +"%Y%m%d")}  # $(date -u +"%Y%m%d") #20171226
suffix=""
#log "timestamp=" "${timestamp}"
#log "today=" "${today}"

readonly algorithm="AWS4-HMAC-SHA256"

readonly signed_headers="content-type;host;x-amz-date"
readonly header_x_amz_date="x-amz-date:${timestamp}"
readonly content_type="application/json"
readonly header_content_type="content-type:${content_type}"
#readonly 

usage() {                                 # Function: Print a help message.
  echo "Usage: $0 [ -h ] | -f yamlconf.file " 1>&2 
  exit 1
}

function invoke_it() {
    local method="$1"
    local aws_service=$2
    local api_url="$3"
    local body_payload="$4"
    local api_host=$(printf ${api_url} | awk -F/ '{print $3}')
    local api_uri=$(printf ${api_url} | grep / | cut -d/ -f4- | cut -d? -f1 )
    # TODO: the order of the query values needs to be in alphabetic order
    local api_query=$(printf ${api_url} | grep / | cut -d/ -f4- | cut -d? -f2- )
    local credential_scope="${today}/${aws_region}/${aws_service}/aws4_request"
    local authorization_header=$(sign_it "${method}")
    curl -s -X ${method} ${api_url} -H "${authorization_header}" -H "${header_x_amz_date}"  -H "Content-Type: ${content_type}" -d "${body_payload}"
}

function xmlextract() {
    local xmlresponse="$1"
    local xmlparse=$2
    local aws_error_parse=$(echo ${xmlresponse} | xmllint --xpath "//*[local-name()='Error']/*[local-name()='Message']/text()" --nowarning - 2>/dev/null;)
    if [ -z "${aws_error_parse}" ]; then 
	printf $(echo $xmlresponse | xmllint --xpath ${xmlparse} -)
    	return 0
    else 
	echo "ERROR $0: request failed with - ${aws_error_parse}"
    	return 1
   fi
}


no_args="true"
while getopts hbf: flag
do
    case "${flag}" in
        f) filename=${OPTARG};;
        b) backup=true;;
        h) usage;;
	:) echo "Argument is required" && usage;;
	\?) usage;;
    esac
    no_args="false"
done
[[ "$no_args" == "true" ]] && { usage; exit 1; }

eval $(parse_yaml $filename "" )
aws_access_key=$Access_key
aws_secret_key=$Secret_key
__debug__=true log "aws_access_key=" "${aws_access_key}"
[ "${aws_access_key}" = "${aws_secret_key}" ] &&  echo "Error $0: Something is wrong with the key"
awsuser_req=$(invoke_it "POST" "sts" "https://sts.amazonaws.com/?Action=GetCallerIdentity&Version=2011-06-15" "" ) 
awsuser=$(xmlextract "${awsuser_req}" "//*[local-name()='GetCallerIdentityResult']/*[local-name()='Arn']/text()" )
if [ $? -ne 0 ]; then echo ${awsuser}; exit -1; fi
echo "Changing keys for user ${awsuser}"
awskeys_req=$(invoke_it "GET" "iam" "https://iam.amazonaws.com/?Action=ListAccessKeys&Version=2010-05-08" "")
awskeys=$(xmlextract "${awskeys_req}" "//*[local-name()='member']/*[local-name()='AccessKeyId']/text()" )
if [ $? -ne 0 ]; then echo ${awsuser}; exit -1; fi
if [ "${awskeys}" != "${aws_access_key}" ]; then
# more than one key exists lets remove the incorrect key and start the rotation
   echo "More than 1 key is present: ${awskeys} for ${awsuser}" 
   key_to_remove=${awskeys#${aws_access_key}}
   echo "Removing offending key ${key_to_remove}"
   deleteid=$(invoke_it "GET" "iam" "https://iam.amazonaws.com/?AccessKeyId=${key_to_remove}&Action=DeleteAccessKey&Version=2010-05-08" "")
fi

echo "Rotating keys for ${awsuser}"
newkey_xml=$(invoke_it "GET" "iam" "https://iam.amazonaws.com/?Action=CreateAccessKey&Version=2010-05-08" "")
new_aws_access_key=$(xmlextract "${newkey_xml}" "//*[local-name()='AccessKey']/*[local-name()='AccessKeyId']/text()" | sed -e 's/[\/&]/\\&/g') 
if [ $? -ne 0 ]; then echo ${awsuser}; exit -1; fi
new_aws_secret_key=$(xmlextract "${newkey_xml}" "//*[local-name()='AccessKey']/*[local-name()='SecretAccessKey']/text()" | sed -e 's/[\/&]/\\&/g')
if [ $? -ne 0 ]; then echo ${awsuser}; exit -1; fi
__debug__=false log "newkey_xml=" "${newkey_xml}"
echo "New key created ${new_aws_access_key}/${new_aws_secret_key}"
__debug__=false log "new_aws_secret_key=" "${new_aws_secret_key}"
${backup} && suffix=${today}
/usr/bin/sed -i${suffix} -e "s|${aws_access_key}|${new_aws_access_key}|g" -e "s|${aws_secret_key}|${new_aws_secret_key}|g" ${filename} && (
    echo "Removing old key ${aws_access_key}"
    result=$(invoke_it "GET" "iam" "https://iam.amazonaws.com/?AccessKeyId=${aws_access_key}&Action=DeleteAccessKey&Version=2010-05-08" "")
    if [ $? -ne 0 ]; then echo ${result}; exit -1; fi
    echo "Done"
)
