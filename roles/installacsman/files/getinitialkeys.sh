#!/bin/bash

CONFIGFILE="/root/.cloudmonkey/config.nokeys"

cloudmonkey -c $CONFIGFILE set display default
#obtain the domain id
ADMINID=`cloudmonkey -c $CONFIGFILE list users admin filter=id | grep ^id | awk '{print $3}'`

#Check if the apikey exists
APIKEY=`cloudmonkey -c $CONFIGFILE list users admin filter=apikey | grep ^apikey | awk '{print $3}'`

if [[ -z $APIKEY ]]; then
    #echo "keys not set. Create"
    APIKEY=`cloudmonkey -c $CONFIGFILE register userkeys id=${ADMINID} | grep ^apikey | awk '{print $3}'`
    SECRETKEY=`cloudmonkey -c $CONFIGFILE list users admin filter=secretkey | grep ^secretkey | awk '{print $3}'`
    echo "$APIKEY:$SECRETKEY:$ADMINID"
else
    #echo "keys exist"
    SECRETKEY=`cloudmonkey -c $CONFIGFILE list users admin filter=secretkey | grep ^secretkey | awk '{print $3}'`
    echo "$APIKEY:$SECRETKEY:$ADMINID"
fi
