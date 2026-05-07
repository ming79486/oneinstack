#!/bin/bash
# Private Nginx-only toolkit.

Install_Nginx() {
  mkdir -p "${oneinstack_dir}/downloads"
  pushd "${oneinstack_dir}/downloads" > /dev/null
  id -g ${run_group} >/dev/null 2>&1
  [ $? -ne 0 ] && groupadd ${run_group}
  id -u ${run_user} >/dev/null 2>&1
  [ $? -ne 0 ] && useradd -g ${run_group} -M -s /sbin/nologin ${run_user}

  tar xzf pcre2-${pcre2_ver}.tar.gz
  tar xzf nginx-${nginx_ver}.tar.gz
  tar xzf openssl-${openssl11_ver}.tar.gz
  pushd nginx-${nginx_ver} > /dev/null
  # Modify Nginx version
  #sed -i 's@#define NGINX_VERSION.*$@#define NGINX_VERSION      "1.2"@' src/core/nginx.h

  # close debug
  sed -i 's@CFLAGS="$CFLAGS -g"@#CFLAGS="$CFLAGS -g"@' auto/cc/gcc

  [ ! -d "${nginx_install_dir}" ] && mkdir -p ${nginx_install_dir}
  ./configure --prefix=${nginx_install_dir} --user=${run_user} --group=${run_group} --with-http_stub_status_module --with-http_sub_module --with-http_v2_module --with-http_v3_module --with-http_ssl_module --with-stream --with-stream_ssl_preread_module --with-stream_ssl_module --with-http_gzip_static_module --with-http_realip_module --with-http_flv_module --with-http_mp4_module --with-http_stub_status_module --with-openssl=../openssl-${openssl11_ver} --with-pcre=../pcre2-${pcre2_ver} --with-pcre-jit --with-ld-opt='-ljemalloc' ${nginx_modules_options}
  make -j ${THREAD} && make install
  if [ -e "${nginx_install_dir}/conf/nginx.conf" ]; then
    popd > /dev/null
    #rm -rf pcre2-${pcre2_ver}* openssl-${openssl11_ver}* nginx-${nginx_ver}* ${nginx_install_dir}*
    echo "${CSUCCESS}Nginx installed successfully! ${CEND}"
  else
    rm -rf pcre2-${pcre2_ver}* openssl-${openssl11_ver}* nginx-${nginx_ver}* ${nginx_install_dir}*
    echo "${CFAILURE}Nginx install failed, Please Contact the author! ${CEND}"
    kill -9 $$; exit 1;
  fi

  [ -z "`grep ^'export PATH=' /etc/profile`" ] && echo "export PATH=${nginx_install_dir}/sbin:\$PATH" >> /etc/profile
  [ -n "`grep ^'export PATH=' /etc/profile`" -a -z "`grep ${nginx_install_dir} /etc/profile`" ] && sed -i "s@^export PATH=\(.*\)@export PATH=${nginx_install_dir}/sbin:\1@" /etc/profile
  . /etc/profile

  /bin/cp ../services/nginx.service /lib/systemd/system/
  sed -i "s@/usr/local/nginx@${nginx_install_dir}@g" /lib/systemd/system/nginx.service
  systemctl enable nginx

  mv ${nginx_install_dir}/conf/nginx.conf{,_bk}
  /bin/cp ../templates/nginx/nginx.conf ${nginx_install_dir}/conf/nginx.conf
  cat > ${nginx_install_dir}/conf/proxy.conf << EOF
proxy_connect_timeout 300s;
proxy_send_timeout 900;
proxy_read_timeout 900;
proxy_buffer_size 32k;
proxy_buffers 4 64k;
proxy_busy_buffers_size 128k;
proxy_redirect off;
proxy_hide_header Vary;
proxy_set_header Accept-Encoding '';
proxy_set_header Referer \$http_referer;
proxy_set_header Cookie \$http_cookie;
proxy_set_header Host \$host;
proxy_set_header X-Real-IP \$remote_addr;
proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
proxy_set_header X-Forwarded-Proto \$scheme;
EOF
  sed -i "s@/data/wwwroot/default@${wwwroot_dir}/default@" ${nginx_install_dir}/conf/nginx.conf
  sed -i "s@/data/wwwlogs@${wwwlogs_dir}@g" ${nginx_install_dir}/conf/nginx.conf
  sed -i "s@^user www www@user ${run_user} ${run_group}@" ${nginx_install_dir}/conf/nginx.conf

  # logrotate nginx log
  cat > /etc/logrotate.d/nginx << EOF
${wwwlogs_dir}/*nginx.log {
  daily
  rotate 5
  missingok
  dateext
  compress
  notifempty
  sharedscripts
  postrotate
    [ -e /var/run/nginx.pid ] && kill -USR1 \`cat /var/run/nginx.pid\`
  endscript
}
EOF
  popd > /dev/null
  ldconfig
  systemctl start nginx
}
