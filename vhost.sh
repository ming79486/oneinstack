#!/bin/bash
# Nginx-only virtual host helper.

export PATH=/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin
clear
printf "
#######################################################################
#                    Private Nginx vhost helper                       #
#######################################################################
"

[ "$(id -u)" != '0' ] && { echo "Error: You must be root to run this script"; exit 1; }

oneinstack_dir=$(dirname "$(readlink -f "$0")")
pushd "${oneinstack_dir}" > /dev/null
. ./options.conf
. ./lib/color.sh
. ./lib/check_dir.sh
. ./lib/check_os.sh
. ./lib/get_char.sh
. ./lib/openssl.sh

Show_Help() {
  echo
  echo "Usage: $0 [options]
  --help, -h                  Show this help message
  --quiet, -q                 Quiet operation
  --list, -l                  List Nginx virtual hosts
  --proxy                     Create reverse proxy virtual host
  --add                       Add virtual host
  --delete, --del             Delete virtual host
  --httponly                  Use HTTP only
  --selfsigned                Use self-signed SSL certificate
  --letsencrypt               Use Let's Encrypt HTTP validation
  --dnsapi                    Use acme.sh DNS API validation
  "
}

TEMP=`getopt -o hql --long help,quiet,list,proxy,add,delete,del,httponly,selfsigned,letsencrypt,dnsapi -- "$@" 2>/dev/null`
[ $? != 0 ] && echo "${CWARNING}ERROR: unknown argument! ${CEND}" && Show_Help && exit 1
eval set -- "${TEMP}"
while :; do
  [ -z "$1" ] && break
  case "$1" in
    -h|--help) Show_Help; exit 0 ;;
    -q|--quiet) quiet_flag=y; shift ;;
    -l|--list) list_flag=y; shift ;;
    --proxy) proxy_flag=y; shift ;;
    --add) add_flag=y; shift ;;
    --delete|--del) delete_flag=y; shift ;;
    --httponly) sslquiet_flag=y; httponly_flag=y; Domian_Mode=1; shift ;;
    --selfsigned) sslquiet_flag=y; selfsigned_flag=y; Domian_Mode=2; shift ;;
    --letsencrypt) sslquiet_flag=y; letsencrypt_flag=y; Domian_Mode=3; shift ;;
    --dnsapi) sslquiet_flag=y; dnsapi_flag=y; letsencrypt_flag=y; Domian_Mode=3; shift ;;
    --) shift ;;
    *) echo "${CWARNING}ERROR: unknown argument! ${CEND}" && Show_Help && exit 1 ;;
  esac
done

Require_Nginx() {
  . ./lib/check_dir.sh
  [ ! -e "${web_install_dir}/sbin/nginx" ] && { echo "${CFAILURE}Nginx not found!${CEND}"; exit 1; }
  [ ! -d "${web_install_dir}/conf/vhost" ] && mkdir -p "${web_install_dir}/conf/vhost"
  [ ! -d "${web_install_dir}/conf/ssl" ] && mkdir -p "${web_install_dir}/conf/ssl"
}

Prompt_SSL_Mode() {
  if [ "${sslquiet_flag}" != 'y' ]; then
    while :; do
      printf "
What Are You Doing?
\t${CMSG}1${CEND}. Use HTTP Only
\t${CMSG}2${CEND}. Use self-signed SSL Certificate and Key
\t${CMSG}3${CEND}. Use Let's Encrypt to Create SSL Certificate and Key
\t${CMSG}q${CEND}. Exit
"
      read -e -p "Please input the correct option: " Domian_Mode
      [[ "${Domian_Mode}" =~ ^[1-3,q]$ ]] && break
      echo "${CFAILURE}input error! Please only input 1~3 and q${CEND}"
    done
  fi
  [ "${Domian_Mode}" == 'q' ] && exit 1
  Domian_Mode=${Domian_Mode:-1}
}

Input_Domain() {
  while :; do
    read -e -p "Please input domain(example: www.example.com): " domain
    [ -n "$(echo "${domain}" | grep '.*\..*')" ] && break
    echo "${CWARNING}Your ${domain} is invalid! ${CEND}"
  done
  if [ -e "${web_install_dir}/conf/vhost/${domain}.conf" ]; then
    echo -e "${domain} already exists. Delete ${CMSG}${web_install_dir}/conf/vhost/${domain}.conf${CEND} and re-create."
    exit 1
  fi
  echo "domain=${domain}"

  read -e -p "Please input more domain name(example: example.com *.example.com): " moredomainame
  [ -n "${moredomainame}" ] && moredomainame=" ${moredomainame}"

  if [ "${proxy_flag}" == 'y' ]; then
    while :; do
      read -e -p "Please input proxy_pass URL(example: http://127.0.0.1:8080): " proxy_pass
      [ -n "${proxy_pass}" ] && break
      echo "${CWARNING}proxy_pass URL is empty.${CEND}"
    done
  else
    read -e -p "Please input the directory for ${domain}(Default: ${wwwroot_dir}/${domain}): " vhostdir
    vhostdir=${vhostdir:-${wwwroot_dir}/${domain}}
    [[ ! "${vhostdir}" =~ ^/ ]] && { echo "${CWARNING}vhost directory must be absolute.${CEND}"; exit 1; }
    mkdir -p "${vhostdir}"
    chown -R "${run_user}:${run_group}" "${vhostdir}"
    [ ! -e "${vhostdir}/index.html" ] && echo "${domain}" > "${vhostdir}/index.html"
  fi
}

Nginx_Log() {
  while :; do
    read -e -p "Do you want to enable access_log? [y/n]: " access_flag
    access_flag=${access_flag:-y}
    [[ "${access_flag}" =~ ^[y,n]$ ]] && break
    echo "${CWARNING}input error! Please only input 'y' or 'n'${CEND}"
  done
  if [ "${access_flag}" == 'n' ]; then
    Nginx_log="access_log off;"
  else
    Nginx_log="access_log ${wwwlogs_dir}/${domain}_nginx.log combined;"
  fi
}

Create_SSL() {
  PATH_SSL=${web_install_dir}/conf/ssl
  [ ! -d "${PATH_SSL}" ] && mkdir -p "${PATH_SSL}"
  if [ "${Domian_Mode}" == '2' ]; then
    openssl req -utf8 -new -newkey rsa:2048 -sha256 -nodes -out "${PATH_SSL}/${domain}.csr" -keyout "${PATH_SSL}/${domain}.key" -subj "/C=CN/ST=Shanghai/L=Shanghai/O=Private/OU=IT/CN=${domain}" > /dev/null 2>&1
    openssl x509 -req -days 36500 -sha256 -in "${PATH_SSL}/${domain}.csr" -signkey "${PATH_SSL}/${domain}.key" -out "${PATH_SSL}/${domain}.crt" > /dev/null 2>&1
  elif [ "${Domian_Mode}" == '3' ] || [ "${dnsapi_flag}" == 'y' ]; then
    CERT_KEYLENGTH=${CERT_KEYLENGTH:-2048}
    if [ ! -e ~/.acme.sh/acme.sh ]; then
      mkdir -p "${oneinstack_dir}/downloads"
      pushd "${oneinstack_dir}/downloads" > /dev/null || exit 1
      if [ ! -e acme.sh-master.tar.gz ]; then
        wget -qO acme.sh-master.tar.gz https://github.com/acmesh-official/acme.sh/archive/refs/heads/master.tar.gz || wget -qc "${mirror_link}/oneinstack/downloads/acme.sh-master.tar.gz"
      fi
      rm -rf acme.sh-master
      tar xzf acme.sh-master.tar.gz
      pushd acme.sh-master > /dev/null || exit 1
      ./acme.sh --install > /dev/null 2>&1
      popd > /dev/null
      popd > /dev/null
      ~/.acme.sh/acme.sh --set-default-ca --server letsencrypt > /dev/null 2>&1
    fi
    [ -e ~/.acme.sh/account.conf ] && sed -i '/^CERT_HOME=/d' ~/.acme.sh/account.conf
    if [ "${dnsapi_flag}" == 'y' ]; then
      read -e -p "Please enter your DNS provider(example: cf, ali): " DNS_PRO
      read -e -p "Please enter your dnsapi parameters: " DNS_PAR
      eval "${DNS_PAR}"
      moredomainame_D="$(for D in ${moredomainame}; do echo -d ${D}; done)"
      ~/.acme.sh/acme.sh --force --issue -k "${CERT_KEYLENGTH}" --dns "dns_${DNS_PRO}" -d "${domain}" ${moredomainame_D}
    else
      acme_webroot=${acme_webroot:-${vhostdir:-${wwwroot_dir}/${domain}_acme}}
      mkdir -p "${acme_webroot}"
      chown -R "${run_user}:${run_group}" "${acme_webroot}"
      ~/.acme.sh/acme.sh --force --issue -k "${CERT_KEYLENGTH}" -d "${domain}" -w "${acme_webroot}" $(for D in ${moredomainame}; do echo -d ${D}; done)
    fi
    if [ -d ~/.acme.sh/${domain}_ecc ]; then
      ~/.acme.sh/acme.sh --installcert --ecc -d "${domain}" --key-file "${PATH_SSL}/${domain}.key" --fullchain-file "${PATH_SSL}/${domain}.crt" --reloadcmd "${web_install_dir}/sbin/nginx -s reload"
    else
      ~/.acme.sh/acme.sh --installcert -d "${domain}" --key-file "${PATH_SSL}/${domain}.key" --fullchain-file "${PATH_SSL}/${domain}.crt" --reloadcmd "${web_install_dir}/sbin/nginx -s reload"
    fi
  fi
}

Server_SSL_Block() {
  [ "${Domian_Mode}" == '1' ] && return
  cat <<EOF

server {
  listen 443 ssl http2;
  server_name ${domain}${moredomainame};
  ssl_certificate ${web_install_dir}/conf/ssl/${domain}.crt;
  ssl_certificate_key ${web_install_dir}/conf/ssl/${domain}.key;
  ssl_protocols TLSv1.2 TLSv1.3;
  ssl_ciphers HIGH:!aNULL:!MD5;
  ${Nginx_log}
EOF
  if [ "${proxy_flag}" == 'y' ]; then
    cat <<EOF
  location / {
    proxy_pass ${proxy_pass};
    include proxy.conf;
  }
}
EOF
  else
    cat <<EOF
  root ${vhostdir};
  index index.html index.htm;
  location / {
    try_files \$uri \$uri/ /index.html;
  }
}
EOF
  fi
}

HTTP_Server_Block() {
  http_mode=$1
  cat <<EOF
server {
  listen 80;
  server_name ${domain}${moredomainame};
  ${Nginx_log}
EOF
  if [ "${http_mode}" == 'redirect' ]; then
    cat <<EOF
  location /.well-known/acme-challenge/ {
    root ${acme_webroot};
  }
  location / {
    return 301 https://\$host\$request_uri;
  }
}
EOF
  elif [ "${proxy_flag}" == 'y' ]; then
    if [ "${Domian_Mode}" == '3' ] && [ "${dnsapi_flag}" != 'y' ]; then
      cat <<EOF
  location /.well-known/acme-challenge/ {
    root ${acme_webroot};
  }
EOF
    fi
    cat <<EOF
  location / {
    proxy_pass ${proxy_pass};
    include proxy.conf;
  }
}
EOF
  else
    if [ "${Domian_Mode}" == '3' ] && [ "${dnsapi_flag}" != 'y' ]; then
      cat <<EOF
  location /.well-known/acme-challenge/ {
    root ${acme_webroot};
  }
EOF
    fi
    cat <<EOF
  root ${vhostdir};
  index index.html index.htm;
  location / {
    try_files \$uri \$uri/ /index.html;
  }
}
EOF
  fi
}

Write_Final_Nginx_Conf() {
  if [ "${Domian_Mode}" != '1' ]; then
    HTTP_Server_Block redirect
  else
    HTTP_Server_Block normal
  fi
  Server_SSL_Block
}

Test_And_Reload_Nginx() {
  "${web_install_dir}/sbin/nginx" -t
  if [ $? == 0 ]; then
    "${web_install_dir}/sbin/nginx" -s reload
  else
    rm -f "${web_install_dir}/conf/vhost/${domain}.conf"
    echo "${CFAILURE}Nginx config test failed. Virtualhost was not created.${CEND}"
    exit 1
  fi
}

Create_Nginx_Conf() {
  Nginx_Log
  acme_webroot=${vhostdir:-${wwwroot_dir}/${domain}_acme}
  if [ "${Domian_Mode}" == '3' ] && [ "${dnsapi_flag}" != 'y' ]; then
    mkdir -p "${acme_webroot}"
    chown -R "${run_user}:${run_group}" "${acme_webroot}"
    HTTP_Server_Block normal > "${web_install_dir}/conf/vhost/${domain}.conf"
    Test_And_Reload_Nginx
    Create_SSL
  elif [ "${Domian_Mode}" != '1' ]; then
    Create_SSL
  fi

  Write_Final_Nginx_Conf > "${web_install_dir}/conf/vhost/${domain}.conf"
  Test_And_Reload_Nginx
  echo "${CSUCCESS}Virtualhost created: ${domain}${CEND}"
  echo "$(printf "%-30s" "Nginx conf:")${CMSG}${web_install_dir}/conf/vhost/${domain}.conf${CEND}"
}

Add_Vhost() {
  Require_Nginx
  Prompt_SSL_Mode
  Input_Domain
  Create_Nginx_Conf
}

Del_Vhost() {
  Require_Nginx
  [ -d "${web_install_dir}/conf/vhost" ] && Domain_List=$(ls "${web_install_dir}/conf/vhost" | sed 's@.conf@@g')
  [ -z "${Domain_List}" ] && { echo "${CWARNING}Virtualhost was not exist! ${CEND}"; return; }
  echo
  echo "Virtualhost list:"
  echo ${CMSG}${Domain_List}${CEND}
  while :; do
    read -e -p "Please input a domain you want to delete: " domain
    [ -n "$(echo "${domain}" | grep '.*\..*')" ] && break
    echo "${CWARNING}Your ${domain} is invalid! ${CEND}"
  done
  if [ -e "${web_install_dir}/conf/vhost/${domain}.conf" ]; then
    Directory=$(grep '^  root' "${web_install_dir}/conf/vhost/${domain}.conf" | head -1 | awk -F'[ ;]' '{print $(NF-1)}')
    rm -f "${web_install_dir}/conf/vhost/${domain}.conf"
    rm -f "${web_install_dir}/conf/ssl/${domain}."{crt,key,csr}
    "${web_install_dir}/sbin/nginx" -s reload
    if [ -n "${Directory}" ] && [ -d "${Directory}" ]; then
      while :; do
        read -e -p "Do you want to delete Virtual Host directory? [y/n]: " Del_Vhost_wwwroot_flag
        [[ "${Del_Vhost_wwwroot_flag}" =~ ^[y,n]$ ]] && break
        echo "${CWARNING}input error! Please only input 'y' or 'n'${CEND}"
      done
      if [ "${Del_Vhost_wwwroot_flag}" == 'y' ]; then
        if [ "${quiet_flag}" != 'y' ]; then
          echo "Press Ctrl+c to cancel or Press any key to continue..."
          char=$(get_char)
        fi
        rm -rf "${Directory}"
      fi
    fi
    [ -d ~/.acme.sh/${domain} ] && ~/.acme.sh/acme.sh --force --remove -d "${domain}" > /dev/null 2>&1
    [ -d ~/.acme.sh/${domain}_ecc ] && ~/.acme.sh/acme.sh --force --remove --ecc -d "${domain}" > /dev/null 2>&1
    echo "${CSUCCESS}Domain: ${domain} has been deleted.${CEND}"
  else
    echo "${CWARNING}Virtualhost: ${domain} was not exist! ${CEND}"
  fi
}

List_Vhost() {
  Require_Nginx
  Domain_List=$(ls "${web_install_dir}/conf/vhost" 2>/dev/null | sed 's@.conf@@g')
  if [ -n "${Domain_List}" ]; then
    echo "Virtualhost list:"
    echo ${CMSG}${Domain_List}${CEND}
  else
    echo "${CWARNING}Virtualhost was not exist! ${CEND}"
  fi
}

if [ -z "${add_flag}${delete_flag}${list_flag}" ]; then
  Show_Help
  exit 0
fi
[ "${add_flag}" == 'y' ] && Add_Vhost
[ "${delete_flag}" == 'y' ] && Del_Vhost
[ "${list_flag}" == 'y' ] && List_Vhost
