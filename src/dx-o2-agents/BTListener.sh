#!/bin/bash
# this script runs BT Listener

if [ "$JAVA_HOME" == "" ]; then
    echo "JAVA_HOME is not set.  Please set the environment variable JAVA_HOME to point to your JRE (1.8 or higher) root folder."
    exit
fi


collect_javaenv_vars() {
    local combined_content
    # env: lists all current environment variables (KEY=value format)
    # grep: filters strictly for variables starting with JAVAENV_
    # cut: drops the key name and retains only the value (everything after the first '=')
    # tr: converts newlines into spaces to combine all values into a single string
    # sed: strips the trailing space at the end of the string
    combined_content=$(env | grep '^JAVAENV_' | cut -d= -f2- | tr '\n' ' ' | sed 's/ *$//')
    
    echo "$combined_content"
}

# Example usage: Assign the function's output to your target variable
# ALL_JAVA_ARGS=$(collect_javaenv_vars)

PRG="$0"

while [ -h "$PRG" ]; do
  ls=`ls -ld "$PRG"`
  link=`expr "$ls" : '.*-> \(.*\)$'`
  if expr "$link" : '/.*' > /dev/null; then
    PRG="$link"
  else
    PRG=`dirname "$PRG"`/"$link"
  fi
done

PRGDIR=`dirname "$PRG"`
cd $PRGDIR

javaExe=$JAVA_HOME/bin/java
class_dir=../btlistener.jar 
java_vm_args="-Dlogback.configurationFile=../conf/logback.xml -Daum.home=../ $(collect_javaenv_vars)"

start() {
    echo "Starting BT Listener..."
    if [ -x "$javaExe" ]; then
        nohup "$javaExe" -server -XX:+HeapDumpOnOutOfMemoryError -XX:+UseG1GC -XX:MaxGCPauseMillis=20 -XX:InitiatingHeapOccupancyPercent=35 -XX:+DisableExplicitGC -Djava.awt.headless=true -DSERVICE=CA_BTListener -Xms2048M -Xmx2048M $java_vm_args -jar $class_dir > /dev/null 2>&1 &
    else
    echo "$javaExe does not exist.  Please check that JAVA_HOME is pointing to the correct directory."
    fi
}

encrypt() {
    echo "BT Listener encrypting the password ..."
    if [ -x "$javaExe" ]; then
    	if [ "$1" == "encrypt" ]; then
        	"$javaExe" -cp $class_dir com.ca.apm.eum.btlistener.Application "$1" "$2"
        else
        	echo "Password text required to encrypt"
        fi
    else
        echo "$javaExe does not exist.  Please check that JAVA_HOME is pointing to the correct directory."
    fi
}

stop() {
    PID=`ps -ef  | grep -i BTListener  | grep -v grep | awk '{ print $2 }'`
    ADDR=($PID)
    len=${#ADDR[@]}
    if [ $len -ne 3 ]; then
        echo "BT Listener not running"
        exit 0
    fi
    echo "Stopping BT Listener..."
    kill -9 ${ADDR[0]}
    echo "Stopped successfully"
}

status() {
    PID=`ps -ef  | grep -i BTListener  | grep -v grep | awk '{ print $2 }'`
    ADDR=($PID)
    len=${#ADDR[@]}
    if [ $len -ne 3 ]; then
        echo "BT Listener not running"
    else
        echo "BT Listener is running"
    fi
}


case "$1" in
  start)
        start
        ;;
  encrypt)
        encrypt $1 $2
        ;;  
  status)
        status
        ;;
  stop)
        stop
        ;;
  restart)
        start
        stop
        ;;
  *)
        echo $"Usage: $0 {start|stop|encrypt}"
        exit 1
esac
