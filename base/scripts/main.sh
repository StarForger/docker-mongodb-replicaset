#!/usr/bin/env bash
set -e

#global vars
HOST_FILE=$CONFIG_DIR/hosts.conf

#method for processing mongo replica configuration
addToReplica(){
    for host in $(cat $MY_TEMP_FILE);
    do
       if [ ! -z $host ]; then
           echo $host
           isMaster=$(mongo --host $host --eval "db.isMaster()"| grep 'ismaster' | awk '{print $NF}' | sed  s'/.$//')
           if [ $isMaster == 'true' ];then
             count=0
             while [ $(mongo --host $host --eval "rs.add('$HOSTNAME')"|grep 'ok'| awk '{print $NF}' | sed  s'/.$//') == '0' ]
             do
                sleep 3
                echo $count
                if [ $count -eq $TRY_TIMES ];then
                    break;
                fi
                count=`expr $count + 1`
             done
             break;
           fi
       fi
    done

}


#start mongod process
echo Starting mongod process...
mongod --fork --logpath $LOG_FILE --replSet $REPLICA_NAME $@
echo 'waiting for child process to start...'
sleep 5
#create temporary file for managing container list
echo Creating temporary file...
MY_TEMP_FILE=$(mktemp /tmp/tempFile.XXXX)
#get list of containers
echo Getting containers...
if [ ! -z $SOURCE ] && [ $SOURCE == 'cloud' ]; then
    # use docker-cloud to process container list
    echo From data cloud...
    if [ ! -z $SERVICE ]; then
        docker-cloud container ps --service $SERVICE | awk 'NR>1 {print $1}' > $MY_TEMP_FILE
    else
        echo Failed to get containers, no service name provided...
        exit 1
    fi
else
    # use local docker to process container list
    echo From local containers...
    echo $HOST_FILE

    if [ ! -e  $HOST_FILE ];then
    echo Creating host file which does not exist...
        touch $HOST_FILE
    fi
    echo Copying host file contents...
    cp $HOST_FILE  $MY_TEMP_FILE

fi
echo "Adding container to replica set..."
if [ ! -e  $MY_TEMP_FILE ] || [ ! -s $MY_TEMP_FILE ]; then
    mongo --host $HOSTNAME --eval "rs.initiate()"
else
    addToReplica
fi

#update host file
echo Updating host file...
if [  -z  $(cat $HOST_FILE | grep $HOSTNAME) ] && [ -e $HOST_FILE ];then
    echo $HOSTNAME >> $HOST_FILE
fi

#clean up
rm  $MY_TEMP_FILE

#keep container running
tail -f -n0 $LOG_FILE