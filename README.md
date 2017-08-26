# GD-BETL
Bash client for load data to GoodData project using etl/pull2 API call

prerequisities: jq instaled (https://stedolan.github.io/jq/)
usage:
gd-betl.sh -p xxxxx -w /dir/on/GD/WebDav

optional parameters: -d debug messages
                     -h help(this text)

other parameters set in file auth.sh:

#!/bin/bash
USER="gooddataUser@domain.com"
PASS="topSectetPassword"
SERVER="https://secure.gooddata.com"
