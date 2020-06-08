#!/usr/bin/env bash

# ref: https://github.com/thuehlinger/daemons
# 
# * where <command> is one of:
#   start         start an instance of the application
#   stop          stop all instances of the application
#   restart       stop all instances and restart them afterwards
#   reload        send a SIGHUP to all instances of the application
#   run           run the application in the foreground (same as start -t)
#   zap           set the application to a stopped state
#   status        show status (PID) of application instances

path="$( cd "$( dirname "$0" )" && pwd )"

# default command
command="status" 

if [ $# -gt 0 ]; then
	command=$1
fi

if [[ $command == "start" ]]; then
	if [ $# -lt 2 ]; then
		echo "Filter ID required"
		exit 1
	fi

	# remove old logs
	rm $path/jira.log &> /dev/null
	rm $path/jira.exception &> /dev/null

	# required to start
	filter_id=$2

	# optional
	polling_period=$3
	browser=$4

	# test flag, enables short polling period than minimum value
	test_mode=$5

	logfilename="jira-$filter_id.exception"
	output_logfilename="jira-$filter_id.log"

	# run
	$path/manage-jira.rb $command -l --logfilename $logfilename --output_logfilename $output_logfilename --log_dir $path -- $filter_id $polling_period $browser $test_mode
else
	$path/manage-jira.rb $command
fi
