#!/bin/sh

OLDIFS="$IFS"

SCRIPT_NAME="integrityChk.sh"
scriptPath=`echo ${0} | awk -v scriptName=$SCRIPT_NAME '{matchLoc=match($0, scriptName); if (matchLoc > 0) {print substr ($0, 0, matchLoc - 1);}}'`
scriptPath=${scriptPath:-"./"}

GENERATE=0
VALIDATE=0
SHOW_HELP=0
MASTER_CHKSUM_ARCHIVE=

CHKDIRLIST="/bin /sbin /usr/bin /usr/sbin /usr/local/bin /etc /usr/local/etc"

SEED_KEY=
OPENSSL_BIN=`which openssl`
OPENSSL_0_X=`$OPENSSL_BIN version | openssl version | awk '{split($0, a, " "); if (match(a[2], /^0\./) != 0) print 1; else print 0;}' | tr -d " "`

DEFAULT_MASTER_CHKSUM_PATH="/tmp/os_chk_master"
DEFAULT_MASTER_CHKSUMHASH_PATH="hash"
DEFAULT_MASTER_CHKSUM_EXT="_hash.dir"
DEFAULT_MASTER_CHKSUMCOMP_NAME="composite.hash"
DEFAULT_MASTER_ARCHIVE_PATH="/tmp"
DEFAULT_MASTER_ARCHIVE_NAME="osChk.tgz"

DEFAULT_DIFF_CHKSUM_PATH="/tmp/os_chk_diff"
DEFAULT_DIFF_CHKSUM_EXT="_hash.diff"
DEFAULT_DIFF_CHKSUMCOMP_NAME="composite.hash"

displayHelp()
{
   printf "Usage: integrityChk.sh [mode]"
   printf "\nAvailable options:"
   printf "\n -h | --help\n  Show this help screen and exit"
   printf "\n -g | --generate\n  Generate and save base report for the system"
   printf "\n -v | --validate\n  Validate saved base reports for the system against the systems current state"
   printf "\n\n The following paths are checked:"
   for chkDir in $CHKDIRLIST; do
      printf "\n   $chkDir"
   done
   printf "\n\nReturn Values:"
   printf "\n   Returns 0 if no errors\n\n"
   printf "  In order to reduce the risk of the OS integrity process being compromised, this tool repackages itself into the archive generated by the -g|--generate command.\n"
   printf "  As such, -g|--generate should only be run once from the system itself to bootstrap the process.\n"
   printf "  The -v|--verify should only be run with the repackaged script include in the generated archive.\n"
   printf "  Furthermore, all future regenerations of the OS integrity checksums should be done with the repackaged script.\n\n"
}

setupKey()
{
   local key
   local hexkey
   IFS=
   printf "Please enter the secret key: "
   stty -echo
   read key
   if [ $OPENSSL_0_X = 1 ]; then
      hexkey=`echo "$key" | $OPENSSL_BIN dgst -sha256 | awk '{split($0, a, " "); print toupper(a[1]);}' | tr -d " "`
   else
      hexkey=`echo "$key" | $OPENSSL_BIN dgst -sha256 | awk '{split($0, a, " "); print toupper(a[2]);}' | tr -d " "`
   fi
   SEED_KEY=`echo "$hexkey" | bc`
   stty echo
   printf "\n"
   IFS="$OLDIFS"
}

archiveChksums()
{
   local archivePath=$1
   local savePath=$2

   if [ -z $SEED_KEY ]; then
      setupKey
   fi

   if [ -e "$savePath/$DEFAULT_MASTER_ARCHIVE_NAME" ]; then
      printf "Another system master checksum archive exists.\nDelete and replace (if you say no, the script will exit and you will have to regenerate the checksums): "
      while read -r userInput; do
         if [ "$userInput" = "yes" ]; then
            rm -f $savePath/$DEFAULT_MASTER_ARCHIVE_NAME
            break
         elif [ "$userInput" = "no" ]; then
            return 1
         else
            printf "Please type 'yes' or 'no': "
            continue
         fi
      done
   fi

   printf "Staging script for later verification.\nYou should only verify this system with the staged script.\n"
   cp -f "$scriptPath/$SCRIPT_NAME" $archivePath

   printf "Archiving system master checksums; checksums will be removed from disk after this operation completes.\n\n***NOTE: This archive will be encrypted with the secret you entered earlier!\n"
   tar -C $archivePath -zcf $savePath/$DEFAULT_MASTER_ARCHIVE_NAME $SCRIPT_NAME $DEFAULT_MASTER_CHKSUMHASH_PATH 2> /dev/null

   printf "Cleaning up...\n"
   rm -f $archivePath/$DEFAULT_MASTER_CHKSUMHASH_PATH/*$DEFAULT_MASTER_CHKSUM_EXT $archivePath/$DEFAULT_MASTER_CHKSUMHASH_PATH/$DEFAULT_MASTER_CHKSUMCOMP_NAME $archivePath/$SCRIPT_NAME

   return 0
}

generateChksums()
{
   local savePath=$1

   if [ -z $SEED_KEY ]; then
      setupKey
   fi

   printf "\n\n***NOTE: Remember the secret key you typed!\nYou will need it to verify the generated/saved checksums later!\n\n"

   # Make sure the diff location is setup and clear
   if [ ! -d "$savePath/$DEFAULT_MASTER_CHKSUMHASH_PATH" ]; then
      printf "Creating %s/%s\n" $savePath $DEFAULT_MASTER_CHKSUMHASH_PATH
      mkdir -p $savePath/$DEFAULT_MASTER_CHKSUMHASH_PATH
   fi

   #make sure we clear the existing composite hash file...
   if [ -e "$savePath/$DEFAULT_MASTER_CHKSUMHASH_PATH/$shaFilename$DEFAULT_MASTER_CHKSUMCOMP_NAME" ]; then
      printf "Clearing %s\n" $savePath/$DEFAULT_MASTER_CHKSUMHASH_PATH/$DEFAULT_MASTER_CHKSUMCOMP_NAME
      rm -f $savePath/$DEFAULT_MASTER_CHKSUMHASH_PATH/$DEFAULT_MASTER_CHKSUMCOMP_NAME
   fi

   for chkDir in $CHKDIRLIST; do
      printf "Calculating checksum for %s\n" $chkDir
      shaFilename=`echo "$chkDir" | awk '{ gsub(/\//, "_") }1'`

      # I'm dumping the "seed" generated portion of mtree now (composite checksum) because I ran into a compatibility issue
      # recently so I'm going to switch to using openssl to generate the composite hash
      mtree -c -K cksum,sha256digest -s $SEED_KEY -p $chkDir > $savePath/$DEFAULT_MASTER_CHKSUMHASH_PATH/$shaFilename$DEFAULT_MASTER_CHKSUM_EXT 2> /dev/null
      $OPENSSL_BIN dgst -sha256 -hmac $SEED_KEY $chkDir >> $savePath/$DEFAULT_MASTER_CHKSUMHASH_PATH/$DEFAULT_MASTER_CHKSUMCOMP_NAME
   done
}

verifyChksums()
{
   local validatePath=$1
   local diffPath=$2

   if [ -z $SEED_KEY ]; then
      setupKey
   fi

   if [ ! -e "$validatePath/$DEFAULT_MASTER_CHKSUMHASH_PATH/$DEFAULT_MASTER_CHKSUMCOMP_NAME" ]; then
      printf "Could not find a valid composite checksum at %s. You may need to regenerate the checksum archive.\n" "$validatePath/$DEFAULT_MASTER_CHKSUMHASH_PATH/"
      return 1
   fi

   # Make sure the diff location is setup and clear
   if [ ! -d "$diffPath" ]; then
      printf "Creating %s\n" $diffPath
      mkdir -p $diffPath
   fi

   #make sure we clear the existing composite hash file...
   if [ -e "$diffPath/$DEFAULT_DIFF_CHKSUMCOMP_NAME" ]; then
      printf "Clearing %s\n" $diffPath/$DEFAULT_DIFF_CHKSUMCOMP_NAME
      rm -f $diffPath/$DEFAULT_DIFF_CHKSUMCOMP_NAME
   fi

   # Calculate the differences with mtree and dump them to the diff location
   for chkDir in $CHKDIRLIST; do
      shaFilename=`echo "$chkDir" | awk '{ gsub(/\//, "_") }1'`

      # I'm dumping the "seed" generated portion of mtree now (composite checksum) because I ran into a compatibility issue
      # recently so I'm going to switch to using openssl to generate the composite hash
      printf "Calculating checksum for %s\n" $chkDir
      mtree -s $SEED_KEY -p $chkDir < $validatePath/$DEFAULT_MASTER_CHKSUMHASH_PATH/$shaFilename$DEFAULT_MASTER_CHKSUM_EXT > $diffPath/$shaFilename$DEFAULT_DIFF_CHKSUM_EXT 2> /dev/null
      $OPENSSL_BIN dgst -sha256 -hmac $SEED_KEY $chkDir >> $diffPath/$DEFAULT_DIFF_CHKSUMCOMP_NAME
   done

   return 0
}

showDiff()
{
   local validatePath=$1 
   local diffPath=$2
   local diffFound=0

   # Shortcut and check the composite hashes first
   diff -q $validatePath/$DEFAULT_MASTER_CHKSUMHASH_PATH/$DEFAULT_MASTER_CHKSUMCOMP_NAME $diffPath/$DEFAULT_DIFF_CHKSUMCOMP_NAME >/dev/null
   if [ $? -ne 0 ]; then
      printf "Differences found! Checking individual hashes...\n"

      for diffFile in `ls -A $diffPath`; do

         #avoid our composite hash files
         if [ "$diffFile" = "$DEFAULT_DIFF_CHKSUMCOMP_NAME" ]; then
            continue
         fi

         dirName=`echo "$diffFile" | awk -v diffExt=$DEFAULT_DIFF_CHKSUM_EXT '{ path=substr($1,2); gsub(diffExt, "", path); gsub(/_/, "/", path);print path }'`
         printf "Examining file hashes for %s\n" $dirName

         if [ -e "$diffPath/$diffFile" -a -s "$diffPath/$diffFile" ]; then
            printf "Showing diff for directory %s:\n" $dirName
            more $diffPath/$diffFile
            diffFound=1
         fi
      done

      if [ $diffFound -eq 0 ]; then
         printf "No differences found in individual files. Did you use the wrong secret key?\n"
      fi
   else
      printf "No differences found.\n"
   fi
}

# MAIN
if [ $# -lt 1 ]; then
   displayHelp
   exit 0
fi

for arg in "$@"; do
   case $arg in
      '-g' | '--generate')
         GENERATE=1
      ;;
      '-v' | '--validate')
         VALIDATE=1
      ;;
      '-h' | '--help')
         SHOW_HELP=1
      ;;
      *)
      ;;
   esac
done

# These are mutually exclusive arguements
if [ $GENERATE -eq 1 -a $VALIDATE -eq 1 ]; then
   printf "Only -g/--generate /or/ -v/--valdiate may be specified per run.  Exiting...\n"
   displayHelp
   exit 1
fi

if [ $GENERATE -eq 1 ];then
   generateChksums $DEFAULT_MASTER_CHKSUM_PATH
   archiveChksums $DEFAULT_MASTER_CHKSUM_PATH $DEFAULT_MASTER_ARCHIVE_PATH
   if [ $? -ne 0 ]; then
      printf "Archiving master checksums did not complete. Please re-run the generate command to try again\n"
      exit 2
   fi
elif [ $VALIDATE -eq 1 ]; then
   verifyChksums $scriptPath $DEFAULT_DIFF_CHKSUM_PATH
   if [ $? -ne 0 ]; then
      printf "Validation process failed.  We're files moved around or was the secret input incorrectly?\n"
      exit 3
   fi
   showDiff $scriptPath $DEFAULT_DIFF_CHKSUM_PATH
fi

if [ $SHOW_HELP -eq 1 ]; then
   displayHelp
fi

exit 0
