#!/bin/bash
# Private Nginx-only toolkit.

export PATH=/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin
clear
printf "
#######################################################################
#                  Private Nginx-only upgrade helper                  #
#                    Upgrade installed Nginx safely                   #
#######################################################################
"
# Check if user is root
[ $(id -u) != "0" ] && { echo "${CFAILURE}Error: You must be root to run this script${CEND}"; exit 1; }

oneinstack_dir=$(dirname "`readlink -f $0`")
pushd ${oneinstack_dir} > /dev/null
. ./versions.txt
. ./options.conf
. ./lib/color.sh
. ./lib/check_os.sh
. ./lib/check_dir.sh
. ./lib/download.sh
. ./lib/get_char.sh
. ./lib/upgrade_web.sh

Show_Help() {
  echo
  echo "Usage: $0 [--nginx version]
  --help, -h                  Show this help message
  --nginx        [version]    Upgrade Nginx. If version is empty, use latest stable from nginx.org.
  "
}

ARG_NUM=$#
if [ ${ARG_NUM} == 0 ]; then
  nginx_flag=y
else
  while [ $# -gt 0 ]; do
    case "$1" in
      -h|--help)
        Show_Help; exit 0
        ;;
      --nginx)
        nginx_flag=y
        if [ -n "$2" ] && [[ "$2" != --* ]]; then
          NEW_nginx_ver=$2
          shift 2
        else
          shift
        fi
        ;;
      --nginx=*)
        nginx_flag=y
        NEW_nginx_ver=${1#*=}
        shift
        ;;
      *)
        echo "${CWARNING}ERROR: unknown argument! ${CEND}" && Show_Help && exit 1
        ;;
    esac
  done
fi

[ "${nginx_flag}" == 'y' ] && Upgrade_Nginx
