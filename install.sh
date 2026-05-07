#!/bin/bash
# Private Nginx-only installer.

export PATH=/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin
clear
printf "
#######################################################################
#                    Private Nginx-only installer                     #
#######################################################################
"

[ "$(id -u)" != "0" ] && { echo "Error: You must be root to run this script"; exit 1; }

oneinstack_dir=$(dirname "$(readlink -f "$0")")
pushd "${oneinstack_dir}" > /dev/null
. ./versions.txt
. ./options.conf
. ./lib/color.sh
. ./lib/check_os.sh
. ./lib/check_dir.sh
. ./lib/download.sh
. ./lib/get_char.sh
. ./lib/ip.sh

version() {
  echo "version: nginx-only"
  echo "updated date: 2026-05-07"
}

Show_Help() {
  version
  echo "Usage: $0 [options]
  --help, -h                  Show this help message
  --version, -v               Show version info
  --nginx_option [1]          Install standard Nginx only
  --ssh_port [No.]            SSH port
  --firewall                  Enable firewall
  --md5sum                    Check source md5sum when available
  --reboot                    Restart the server after installation
  "
}

ARG_NUM=$#
TEMP=`getopt -o hvV --long help,version,nginx_option:,ssh_port:,firewall,md5sum,reboot -- "$@" 2>/dev/null`
[ $? != 0 ] && echo "${CWARNING}ERROR: unknown argument! ${CEND}" && Show_Help && exit 1
eval set -- "${TEMP}"
while :; do
  [ -z "$1" ] && break
  case "$1" in
    -h|--help)
      Show_Help; exit 0
      ;;
    -v|-V|--version)
      version; exit 0
      ;;
    --nginx_option)
      nginx_option=$2; shift 2
      [[ ! ${nginx_option} =~ ^1$ ]] && { echo "${CWARNING}nginx_option input error! Only option 1 is supported.${CEND}"; exit 1; }
      ;;
    --ssh_port)
      ssh_port=$2; shift 2
      ;;
    --firewall)
      firewall_flag=y; shift 1
      ;;
    --md5sum)
      md5sum_flag=y; shift 1
      ;;
    --reboot)
      reboot_flag=y; shift 1
      ;;
    --)
      shift
      ;;
    *)
      echo "${CWARNING}ERROR: unknown argument! ${CEND}" && Show_Help && exit 1
      ;;
  esac
done

nginx_option=1
[ -e "${nginx_install_dir}/sbin/nginx" ] && { echo "${CWARNING}Nginx already installed! ${CEND}"; exit 1; }

if [ -n "${ssh_port}" ]; then
  if [ "${ssh_port}" -eq 22 ] 2>/dev/null || { [ "${ssh_port}" -gt 1024 ] 2>/dev/null && [ "${ssh_port}" -lt 65535 ] 2>/dev/null; }; then
    if grep -qE '^#?Port ' /etc/ssh/sshd_config; then
      sed -i "s@^#\?Port .*@Port ${ssh_port}@" /etc/ssh/sshd_config
    else
      echo "Port ${ssh_port}" >> /etc/ssh/sshd_config
    fi
  else
    echo "${CWARNING}input error! ssh_port must be 22 or 1025~65534.${CEND}"
    exit 1
  fi
fi

[ ! -d "${wwwroot_dir}/default" ] && mkdir -p "${wwwroot_dir}/default"
[ ! -d "${wwwlogs_dir}" ] && mkdir -p "${wwwlogs_dir}"
[ -d /data ] && chmod 755 /data

if [ ! -e ~/.oneinstack ]; then
  downloadDepsSrc=1
  [ "${PM}" == 'apt-get' ] && apt-get -y update > /dev/null
  [ "${PM}" == 'yum' ] && yum clean all > /dev/null
  ${PM} -y install wget gcc curl > /dev/null
fi

IPADDR=$(get_ipaddr)

. ./lib/openssl.sh
. ./lib/check_download.sh
checkDownload 2>&1 | tee -a "${oneinstack_dir}/install.log"

. ./lib/memory.sh

if [ ! -e ~/.oneinstack ]; then
  . ./lib/check_sw.sh
  case "${Family}" in
    "rhel")
      installDepsRHEL 2>&1 | tee "${oneinstack_dir}/install.log"
      . lib/init_RHEL.sh 2>&1 | tee -a "${oneinstack_dir}/install.log"
      ;;
    "debian")
      installDepsDebian 2>&1 | tee "${oneinstack_dir}/install.log"
      . lib/init_Debian.sh 2>&1 | tee -a "${oneinstack_dir}/install.log"
      ;;
    "ubuntu")
      installDepsUbuntu 2>&1 | tee "${oneinstack_dir}/install.log"
      . lib/init_Ubuntu.sh 2>&1 | tee -a "${oneinstack_dir}/install.log"
      ;;
  esac
  installDepsBySrc 2>&1 | tee -a "${oneinstack_dir}/install.log"
fi

startTime=`date +%s`

Install_openSSL | tee -a "${oneinstack_dir}/install.log"

. lib/jemalloc.sh
Install_Jemalloc | tee -a "${oneinstack_dir}/install.log"

. lib/nginx.sh
Install_Nginx 2>&1 | tee -a "${oneinstack_dir}/install.log"

. lib/check_dir.sh

endTime=`date +%s`
((installTime=($endTime-$startTime)/60))
echo "####################Congratulations########################"
echo "Total Nginx Install Time: ${CQUESTION}${installTime}${CEND} minutes"
echo -e "\n$(printf "%-32s" "Nginx install dir":)${CMSG}${web_install_dir}${CEND}"
[ -n "${IPADDR}" ] && echo -e "\n$(printf "%-32s" "Index URL:")${CMSG}http://${IPADDR}/${CEND}"

if [ ${ARG_NUM} == 0 ]; then
  while :; do echo
    echo "${CMSG}Please restart the server and see if the services start up fine.${CEND}"
    read -e -p "Do you want to restart OS ? [y/n]: " reboot_flag
    if [[ ! "${reboot_flag}" =~ ^[y,n]$ ]]; then
      echo "${CWARNING}input error! Please only input 'y' or 'n'${CEND}"
    else
      break
    fi
  done
fi
[ "${reboot_flag}" == 'y' ] && reboot
