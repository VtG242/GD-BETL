#!/bin/bash
# task states - RUNNING,PREPARED,ERROR,OK

# connection information - edit to fit your needs
source auth.sh

# Globalni promene
ETLTASKSTATUS="N/A"
ETL_TASK_ID="N/A"
ETLDATESTART=`date +"%Y-%m-%d %H:%M:%S"`
START=$(date +%s)
PID=$$

while getopts :hdp: option
do
  case $option
    in
    d) DEBUG="true";;
    h) HELP="true";;
    p) PROJECT=$OPTARG;;
    ?) echo "Unknown argument: -$OPTARG use -h for help, -d for turning on debug options and -p for changinging default project"
      exit
    ;;
  esac
done

echo "debug:$DEBUG"

function gettt() {
  curl --silent \
  --write-out "$(gettime) Step2 - INFO: GET /gdc/account/token --> %{http_code}\n" \
  --output step2.$PID \
  --include --header "Cookie: $SST_COOKIE" --header "Accept: application/json" --header "Content-Type: application/json" \
  --request GET $SERVER"/gdc/account/token"
}

function gdlogout() {
  curl --silent \
  --write-out "$(gettime) Step5 (Logout) - INFO: DELETE $USER_LOGIN_URL --> %{http_code}\n" \
  --output step5.$PID \
  --include --header "Accept: application/json" --header "Content-Type: application/json" \
  --header "Cookie: $SST_COOKIE" --header "Cookie: $TT_COOKIE" \
  --request DELETE "$SERVER$USER_LOGIN_URL"
}

function gettime()
{
  date +"%Y-%m-%d %H:%M:%S"
}

function disperror()
{
  echo -n "$(gettime) Step$1 - ERROR: " 1>&2;head -n1 step$1.$PID 1>&2
  echo -n "$(gettime) Step$1 - ERROR: " 1>&2;tail -n1 step$1.$PID 1>&2
  echo -e "\n" 1>&2
}

# Step0 - check if platform is available
# Step1 - login to platform
# Step2 - login to platform - obtaining TT token / check that TT token is valid - could happen repeatelly - validity of TT is 10 minutes
# Step3 - load to platform - etl/pull2
# Step4 - poll to state of etl task
# Step5 - logout

#platform availeability check at first
curl --silent \
--write-out "$(gettime) Step0 - INFO: GET /gdc/ping --> %{http_code}\n" \
--output "step0.$PID" \
--include --header "Accept: application/json" --header "Content-Type: application/json" \
--request GET $SERVER"/gdc/ping"

#check curl state after Step0 - /gdc/ping
if [ "$?" == "0" ];then

  if [ `cat step0.$PID | grep HTTP | awk {'print $2'}` == "204" ]; then
    #platform operates normaly - we can continue with login
    curl --silent\
    --write-out "$(gettime) Step1 - INFO: POST /gdc/account/login --> %{http_code}\n"\
    --output step1.$PID \
    --include --header "Accept: application/json" --header "Content-Type: application/json" \
    --request POST $SERVER"/gdc/account/login"\
    --data-binary "{\"postUserLogin\":{\"login\":\"$USER\",\"password\":\"$PASS\",\"remember\":1}}"
    
    #check curl state after step1 - login
    if [ "$?" == "0" ];then
      
      #curl skoncil normalne - zjistime cookie s SST
      if [ `cat step1.$PID | grep HTTP/1.1 | awk {'print $2'}` == "200" ];then
        
        USER_LOGIN_URL=`cat step1.$PID | grep "{\|}" | ./jq -r .userLogin.state`
        #pickup sst in following format GDCAuthSST=xxx;
        SST_COOKIE=`cat step1.$PID | grep "Set-Cookie:" | grep "GDCAuthSST" | awk {'print $2'}`
        if [ $DEBUG ];then
          echo "SST: "$SST_COOKIE;
          echo "User login URL: "$USER_LOGIN_URL;
        fi
        
        #pokracujene zadosti o TT - step2 - vzdy v pripade kdyz dostanu 401 zavolam si pro novy TT
        gettt
        
        #check curl state after step2
        if [ "$?" == "0" ];then
          
          TT_COOKIE=`cat step2.$PID | grep "Set-Cookie:" | grep "GDCAuthTT" | awk {'print $2'}`
          if [ $DEBUG ];then
            echo "TT: "$TT_COOKIE;
          fi
          
          #curl skoncil normalne - zjistime cookie s SST
          if [ `cat step2.$PID | grep HTTP/1.1 | awk {'print $2'}` == "200" ];then
            
            #ETL start
            
            #Autorizace hotova zde provedeme vlastni akci s API (ETL) - v pripade 401 opakujeme step2
            curl --silent\
            --write-out "$(gettime) Step3 - INFO: POST /gdc/md/$PROJECT/etl/pull --> %{http_code}\n"\
            --output step3.$PID \
            --include --header "Accept: application/json" --header "Content-Type: application/json" \
            --cookie "$TT_COOKIE" \
            --request POST \
            --data-binary "{\"pullIntegration\":\"$WEBDAVDIR\"}" \
            $SERVER"/gdc/md/$PROJECT/etl/pull2"
            
            #check curl state after step3 - vlastni API call
            if [ "$?" == "0" ];then
              
              #etl/pull2 je-li vse ok odpovi 201
              if [ `cat step3.$PID | grep HTTP/1.1 | awk {'print $2'}` == "201" ]; then
                
                #poll na etl task - dokud taskStatus == OK - vyzobneme jen uri ETL tasku
                ETL_TASK_URI=`cat step3.$PID | grep "{\|}" | ./jq -r .pull2Task.links.poll`
                if [ $DEBUG ];then
                  echo "ETL task ID: $ETL_TASK_URI"
                fi

                #counter pro opakovani datazu na stav tasku v pripade problemu
                ETLQUERYFAIL=1

                #TIME - Start ETL - na stav se dotazujeme pollovanim na ETL_TASK_URI 
                while :
                do
                  curl --silent\
                  --write-out "$(gettime) Step4 - INFO: GET $ETL_TASK_URI --> %{http_code}\n"\
                  --output step4.$PID \
                  --cookie "$TT_COOKIE"\
                  --include --header "Accept: application/json" --header "Content-Type: application/json" \
                  --request GET "$SERVER$ETL_TASK_URI"
                  
                  #provedeme kontrolu na navratovy status - pri 202 provedeme poll, pri 401 zazadame o novy TT a pri 200 je hotovo
                  case `cat step4.$PID | grep HTTP/1.1 | awk {'print $2'}` in
                    202)
                      ETLTASKSTATUS=`cat step4.$PID | grep "{\|}" | ./jq -r .wTaskStatus.status`
                      echo "$(gettime) Step4 - INFO: state of ETL task: $ETLTASKSTATUS"
                      sleep 3
                    ;;
                    200)#vypreparujeme z step4 odpovedi jen json
                      ETLQUERYFAIL=1
                      ETLTASKSTATUS=`cat step4.$PID | grep "{\|}" | ./jq -r .wTaskStatus.status`
                      if [ $ETLTASKSTATUS == "OK" ]; then
                        echo "$(gettime) Step4 - INFO: state of ETL task: $ETLTASKSTATUS"
                        gdlogout
                        break
                      elif [ $ETLTASKSTATUS == "ERROR" ]; then
                        echo "$(gettime) Step4 - ERROR: ETL task finished OK but with ERROR - see details below."
                        disperror 4
                        echo -e "More details can be found in upload_status.json file from WebDav.\n"
                        #TODO
                        #curl --user "vladimir.volcko%40gooddata.com:yyy" -G https://secure-di.gooddata.com/uploads/ETLTEST/upload_status.json
                        gdlogout
                        break
                      else
                        #assuming only OK or ERROR but who knows :-)
                        disperror 4
                        sleep 3;
                      fi
                    ;;
                    401)
                       echo "$(gettime) Step4 - INFO: sending of request for new TT"
                       #TODO - zde muzeme dostat chybu ze se curl call nepovede - zatim neresim predpokladam ze prvni check staci
                       gettt
                       TT_COOKIE=`cat step2.$PID | grep --only-matching --perl-regex "(?<=Set-Cookie\: ).*"`
                       if [ $DEBUG ];then
                         echo "TT: "$TT_COOKIE;
                       fi
                    ;;
                    *)  if [ $ETLQUERYFAIL == "10" ]; then
                        echo "Ten failed attempts to get a state of ETL ... I give it up:"
                        cat task.$PID;echo -e "\n";
                        break;
                      fi
                      echo "Problem with getting a state of ETL task ... retry in 30 second."
                      echo "FAIL: $ETLQUERYFAIL"
                      sleep 30;
                      let "ETLQUERYFAIL+=1";
                    ;;
                  esac
                  
                done
                #TIME - End of ETL here
                
              else
		disperror 3
		gdlogout
              fi
            else
              #step3 problem s parsovanim vystupu z curlu 
              echo "$(gettime) Step3 - ERROR: etl/pull - Curl ended with unexpected code $?" 1>&2
              gdlogout
            fi
            
          else
            #pro jiny navratovy kod nez 200 pri step2 (TT call) zobrazime vystup z curlu
            cat step2.$PID
          fi
          
        else
          #step2 problem s parsovanim vystupu z curlu 
          echo "$(gettime) Step2 - ERROR: - retrive TT token - Curl ended with unexpected code $?" 1>&2
        fi
        
      else
        #pro jiny navratovy kod nez 200 po step1 zobrazime vystup z curlu - autorizace se pravdepodobne nezdarila
	disperror 1
      fi
      
    else
      #step1 - problem s curlem ?
      echo "$(gettime) Step1 - ERROR: login attempt failed - curl ended with unexpected code $?" 1>&2
    fi
        
  else
    
    PINGRESPONSE=`tail -n1 step0.$PID`
    if [ "$PINGRESPONSE" == "Scheduled maintenance in progress. Please try again later." ]; then
      MAINTANENCE="Y"
    else
      MAINTANENCE="N"
    fi
    
    #konec platform checku
    echo "$PINGRESPONSE"
    
  fi
  
else
  #step0 - problem s curlem ?
  echo "$(gettime) Step0 - ERROR: Platform check - curl ended with unexpected code $?"
  exit
fi

#ETL END flag
END=$(date +%s)

# cleaning the mess in case we don't need temp stuff for debug
# in case that $DEBUG isn't empty is TRUE :-)
if [ $DEBUG ];then
  echo "Files for debuging:"
  ls step?.$PID
else
  rm -rf step?.$PID
fi
