# GD-BETL
Bash client for load of data to GoodData project using etl/pull2 API call

Upload is done in following steps:

 Step0 - check if platform is available
 Step1 - login to platform
 Step2 - login to platform - obtaining TT token / check that TT token is valid - could happen repeatelly - validity of TT is 10 minutes
 Step3 - load to platform - etl/pull2
 Step4 - poll to state of etl task
 Step5 - logout

prerequisities: 

 jq instaled (https://stedolan.github.io/jq/) - used for parsing JSONs from API response
 data for project uploaded on GoodData WebDav - assuming upload.zip exists on GoodData WebDav storage (https://help.gooddata.com/display/developer/User+Specific+Data+Storage)

usage:

 gd-betl.sh -p xxxxx -w /dir/on/GD/WebDav

optional parameters:

 -d debug messages
 -h help(this text)

other parameters set directly in file auth.sh:

#!/bin/bash
USER="gooddataPlatformUser@domain.com"
PASS="topSecretPass"
SERVER="https://secure.gooddata.com"
PROJECT="bu3iujh7qihft0lipmz8oci6qzhrpe1e"
WEBDAVDIR="ETLDATADIR"
