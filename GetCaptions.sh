#!/bin/bash

#   Add this to the crontab to run automatically
#   Make sure to edit to refelct where you've installed this script
#
#   0  0 * * * bash /mnt/Downloads/GetPics.sh > /mnt/Downloads/logs/GetPics.`date "+%Y%m%d%H%M%S"`.log 2>&1
#   0 12 * * * bash /mnt/Downloads/GetPics.sh > /mnt/Downloads/logs/GetPics.`date "+%Y%m%d%H%M%S"`.log 2>&1

#   The working directory to download files to
#   Sub-directories will be made under this
CWD="/mnt/Downloads"

#   ID file to parse
#   format should be
#   <ID> # Descriptor_to_add_to_directory
IDF="${CWD}/IDs.list"

#   Username to login with
USER="username"

#   Password to login with
PASS="password"

#   Base URL of the site
URL="www.URL.com"

#   Location of the PicRip.pl script
PICRIP="/opt/PicRip/PicRip.pl"

#   Location of PERL
PERL="/usr/local/bin/perl"


cd $CWD
date > last.ran
while read LINE; do
  ID=${LINE% # *}
  FD=${LINE#* # }
  DIR="${ID}-_-${FD}"
  if ! test -d "${CWD}/${DIR}"; then 
    echo "Creating directory ${CWD}/${DIR}"
    mkdir "${CWD}/${DIR}"
  fi
  cd ${CWD}/${DIR}
  date > last.ran
  CMD="${PERL} ${PICRIP} -r 2 -u ${USER} -p ${DIR} -url \"http://${URL}/${ID}_1.html\""
  #echo $CMD
  $CMD
  cd ${CWD}
done < ${IDF}