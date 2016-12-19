#!/bin/bash
# Get list of mail accounts and reindex each one

# 161219: This is the script I got from Zimbra support.  Don't use this, use
# reindex_zimbra_mailboxes.pl instead

for i in `zmprov -l gaa -s server-name`; do
    echo -n "Reindexing $i"

    # Start reindexing
    zmprov rim $i start >/dev/null
    # Check if the rendix is still running for this account
    while [ `zmprov rim $i status|wc -l` != 1 ]; do
	# Sleep for 2 seconds before checking status again
	echo -n . && sleep 2
    done
    echo .
done
