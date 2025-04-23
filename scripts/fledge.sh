#!/bin/bash

##### rsyslogd #####
# introduced by rob 
# Unprivileged Docker containers do not have access to the kernel log. This prevents an error when starting rsyslogd.
sed -i '/imklog/s/^/#/' /etc/rsyslog.conf

pid_file=/run/rsyslogd.pid
if [[ -f $pid_file ]]; then
    echo "Removing old rsyslog pid file"
    rm $pid_file
fi
service rsyslog start

##### Cron  #####
service cron start

##### Postgresql #####
# this could be done by fledge.. by setting the storage to 'managed'
service postgresql start

##### fledge #####
#! After a hard restart of the old pid file prevents fledge from starting.
pid_file=$FLEDGE_DATA/var/run/fledge.core.pid
if [[ -f $pid_file ]]; then
    echo "Removing old fledge pid file"
    rm $pid_file
fi

/usr/local/fledge/bin/fledge start

# Dump the log
tail -f /var/log/syslog