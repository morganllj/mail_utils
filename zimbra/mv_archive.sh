#!/bin/sh
#

acct="${1}@domain.org"
old="${2}@domain.org.archive"
new="${3}@domain.org.archive"

cmd1="zmprov ma $acct amavisarchivequarantineto $new zimbraarchiveaccount $new"
cmd2="zmprov ra $old $new"

echo $cmd1
`$cmd1`
echo

echo $cmd2
`$cmd2`
echo
