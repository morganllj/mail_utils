#!/bin/sh
#
# $Id$

hosts="bxga3 bxga4"

log_base="/opt/zimbra/log"
log_path=${log_base}/????.??.??/dsmdc-mail-%%host%%/mail.log
output_path=${log_base}/check_mail_deliveries_%%host%%.out
bin_dir=/usr/local/sbin
time_period=60  # in minutes

for host in $hosts; do
    path=`echo $log_path|sed "s/%%host%%/$host/"`
    log_file=`ls -1trah $path|tail -1`
    output_file=`echo $output_path|sed "s/%%host%%/$host/"`

    cmd="${bin_dir}/check_mail_deliveries.pl -p $time_period -f ${log_file} -o ${output_file}"
    echo "$cmd" 
    $cmd
done
