#!/bin/sh
#
# $Id$

log_base="/home/morgan/logs_for_dev"
log_file=`ls -1trah ${log_base}/????.??.??/dsmdc-mail-bxga3/mail.log|tail -1`
output="/usr/local/lib/check_mail_deliveries.out"

/usr/local/nagios/libexec/check_mail_deliveries.pl -p 20 -f ${log_file} > \
    ${output}
