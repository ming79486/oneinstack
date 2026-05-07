#!/bin/bash
# Private Nginx-only toolkit.

Upgrade_Nginx() {
  mkdir -p "${oneinstack_dir}/downloads"
  pushd "${oneinstack_dir}/downloads" > /dev/null
  [ ! -e "${nginx_install_dir}/sbin/nginx" ] && echo "${CWARNING}Nginx is not installed on your system! ${CEND}" && exit 1
  OLD_nginx_ver_tmp=`${nginx_install_dir}/sbin/nginx -v 2>&1`
  OLD_nginx_ver=${OLD_nginx_ver_tmp##*/}
  Latest_nginx_ver=${nginx_ver}
  echo
  echo "Current Nginx Version: ${CMSG}${OLD_nginx_ver}${CEND}"
  while :; do echo
    [ "${nginx_flag}" != 'y' ] && read -e -p "Please input upgrade Nginx Version(default: ${Latest_nginx_ver}): " NEW_nginx_ver
    NEW_nginx_ver=${NEW_nginx_ver:-${Latest_nginx_ver}}
    [ ! -e "nginx-${NEW_nginx_ver}.tar.gz" ] && wget --no-check-certificate -c https://nginx.org/download/nginx-${NEW_nginx_ver}.tar.gz > /dev/null 2>&1
    if [ -e "nginx-${NEW_nginx_ver}.tar.gz" ]; then
      src_url=https://www.openssl.org/source/openssl-${openssl11_ver}.tar.gz && Download_src
      src_url=https://github.com/PCRE2Project/pcre2/releases/download/pcre2-${pcre2_ver}/pcre2-${pcre2_ver}.tar.gz && Download_src
      rm -rf openssl-${openssl11_ver} pcre2-${pcre2_ver} nginx-${NEW_nginx_ver}
      tar xzf openssl-${openssl11_ver}.tar.gz
      tar xzf pcre2-${pcre2_ver}.tar.gz
      echo "Download [${CMSG}nginx-${NEW_nginx_ver}.tar.gz${CEND}] successfully! "
      break
    else
      echo "${CWARNING}Nginx version does not exist! ${CEND}"
    fi
  done

  echo "[${CMSG}nginx-${NEW_nginx_ver}.tar.gz${CEND}] found"
  if [ "${nginx_flag}" != 'y' ]; then
    echo "Press Ctrl+c to cancel or Press any key to continue..."
    char=`get_char`
  fi
  nginx_version_out=$(${nginx_install_dir}/sbin/nginx -V 2>&1)
  nginx_configure_args=$(printf '%s
' "${nginx_version_out}" | sed -n 's/^configure arguments: //p')
  nginx_configure_args=$(printf '%s
' "${nginx_configure_args}" | sed -E "s@--with-openssl=[^ ]+@--with-openssl=../openssl-${openssl11_ver}@g" | sed -E "s@--with-pcre=[^ ]+@--with-pcre=../pcre2-${pcre2_ver}@g")
  if ! echo "${nginx_configure_args}" | grep -q -- '--with-openssl='; then
    nginx_configure_args="${nginx_configure_args} --with-openssl=../openssl-${openssl11_ver}"
  fi
  if ! echo "${nginx_configure_args}" | grep -q -- '--with-pcre='; then
    nginx_configure_args="${nginx_configure_args} --with-pcre=../pcre2-${pcre2_ver} --with-pcre-jit"
  fi
  if ! echo "${nginx_configure_args}" | grep -q -- '--with-http_v3_module'; then
    nginx_configure_args="${nginx_configure_args} --with-http_v3_module"
  fi
  echo "Reusing Nginx configure arguments: ${nginx_configure_args}"

  tar xzf nginx-${NEW_nginx_ver}.tar.gz
  pushd nginx-${NEW_nginx_ver} > /dev/null
  make clean
  sed -i 's@CFLAGS="$CFLAGS -g"@#CFLAGS="$CFLAGS -g"@' auto/cc/gcc
  ./configure ${nginx_configure_args}
  make -j ${THREAD}
  if [ -f "objs/nginx" ]; then
    ./objs/nginx -t -c ${nginx_install_dir}/conf/nginx.conf
    if [ $? != 0 ]; then
      echo "${CFAILURE}New Nginx binary config test failed.${CEND}"
      exit 1
    fi
    nginx_bin=${nginx_install_dir}/sbin/nginx
    backup_nginx=${nginx_bin}.$(date +%Y%m%d%H%M%S)
    staged_nginx=${nginx_bin}.new.$$
    /bin/cp objs/nginx ${staged_nginx} || { echo "${CFAILURE}Failed to stage new Nginx binary.${CEND}"; exit 1; }
    chmod 755 ${staged_nginx}
    ${staged_nginx} -t -c ${nginx_install_dir}/conf/nginx.conf
    if [ $? != 0 ]; then
      rm -f ${staged_nginx}
      echo "${CFAILURE}Staged Nginx binary failed config test.${CEND}"
      exit 1
    fi
    /bin/mv ${nginx_bin} ${backup_nginx} || { rm -f ${staged_nginx}; echo "${CFAILURE}Failed to backup old Nginx binary.${CEND}"; exit 1; }
    if ! /bin/mv ${staged_nginx} ${nginx_bin}; then
      /bin/mv ${backup_nginx} ${nginx_bin}
      echo "${CFAILURE}Failed to install new Nginx binary. Rolled back to ${backup_nginx}.${CEND}"
      exit 1
    fi
    ${nginx_bin} -t
    if [ $? != 0 ]; then
      rm -f ${nginx_bin}
      /bin/mv ${backup_nginx} ${nginx_bin}
      echo "${CFAILURE}Installed Nginx binary failed config test. Rolled back to ${backup_nginx}.${CEND}"
      exit 1
    fi
    if [ -s /var/run/nginx.pid ]; then
      old_nginx_pid=$(cat /var/run/nginx.pid)
      if ! kill -USR2 ${old_nginx_pid}; then
        rm -f ${nginx_bin}
        /bin/mv ${backup_nginx} ${nginx_bin}
        echo "${CFAILURE}Failed to start new Nginx binary. Rolled back to ${backup_nginx}.${CEND}"
        exit 1
      fi
      sleep 1
      [ -f /var/run/nginx.pid.oldbin ] && kill -QUIT `cat /var/run/nginx.pid.oldbin`
    else
      if ! systemctl restart nginx; then
        rm -f ${nginx_bin}
        /bin/mv ${backup_nginx} ${nginx_bin}
        systemctl restart nginx
        echo "${CFAILURE}Failed to restart Nginx with new binary. Rolled back to ${backup_nginx}.${CEND}"
        exit 1
      fi
    fi
    popd > /dev/null
    echo "You have ${CMSG}successfully${CEND} upgrade from ${CWARNING}${OLD_nginx_ver}${CEND} to ${CWARNING}${NEW_nginx_ver}${CEND}"
    rm -rf nginx-${NEW_nginx_ver} openssl-${openssl11_ver} pcre2-${pcre2_ver}
  else
    echo "${CFAILURE}Upgrade Nginx failed! ${CEND}"
    exit 1
  fi
  popd > /dev/null
}
