#!/bin/bash
# Private Nginx-only toolkit.

installDepsDebian() {
  echo "${CMSG}Installing dependencies packages...${CEND}"
  apt-get -y update
  apt-get -y autoremove
  apt-get -yf install
  export DEBIAN_FRONTEND=noninteractive
  grep security /etc/apt/sources.list > /tmp/security.sources.list 2>/dev/null || true
  [ -s /tmp/security.sources.list ] && apt-get -y upgrade -o Dir::Etc::SourceList=/tmp/security.sources.list
  pkgList="debian-keyring debian-archive-keyring build-essential gcc g++ make cmake autoconf pkg-config bison re2c patch perl libperl-dev openssl libssl-dev zlib1g zlib1g-dev libpcre2-dev libxml2 libxml2-dev libxslt1-dev libgd-dev libjpeg-dev libpng-dev libwebp-dev libfreetype6-dev libbz2-dev libzip-dev libreadline-dev libcurl4-openssl-dev libevent-dev libicu-dev libexpat1-dev libonig-dev libtirpc-dev libsqlite3-dev libsodium-dev ca-certificates curl wget gnupg python3-pip apt-transport-https software-properties-common tar gzip xz-utils bzip2 file less procps iproute2 iputils-ping dnsutils traceroute telnet socat net-tools sudo systemd cron logrotate rsyslog chrony git rsync lsof psmisc vim nano tmux screen htop bc dc expect unzip zip gawk debianutils util-linux ufw locales"
  for Package in ${pkgList}; do
    apt-get --no-install-recommends -y install ${Package}
  done
}

installDepsUbuntu() {
  installDepsDebian
}

installDepsRHEL() {
  [ -e '/etc/yum.conf' ] && sed -i 's@^exclude@#exclude@' /etc/yum.conf
  if [ "${RHEL_ver}" == '9' ]; then
    if [[ "${Platform}" =~ "rhel" ]]; then
      subscription-manager repos --enable codeready-builder-for-rhel-9-${ARCH}-rpms
    elif [[ "${Platform}" =~ "ol" ]]; then
      dnf config-manager --set-enabled ol9_codeready_builder
    else
      dnf -y --enablerepo=crb install chrony oniguruma-devel rpcgen
    fi
  elif [ "${RHEL_ver}" == '8' ]; then
    if [[ "${Platform}" =~ "rhel" ]]; then
      subscription-manager repos --enable codeready-builder-for-rhel-8-${ARCH}-rpms
    elif [[ "${Platform}" =~ "ol" ]]; then
      dnf config-manager --set-enabled ol8_codeready_builder
    else
      [ -z "`grep -w epel /etc/yum.repos.d/*.repo 2>/dev/null`" ] && yum -y install epel-release
      if grep -qw "^\[PowerTools\]" /etc/yum.repos.d/*.repo; then
        dnf -y --enablerepo=PowerTools install chrony oniguruma-devel rpcgen
      elif grep -qw "^\[powertools\]" /etc/yum.repos.d/*.repo; then
        dnf -y --enablerepo=powertools install chrony oniguruma-devel rpcgen
      fi
    fi
  elif [ "${RHEL_ver}" == '7' ]; then
    [ -z "`grep -w epel /etc/yum.repos.d/*.repo 2>/dev/null`" ] && yum -y install epel-release
  fi
  command -v systemctl >/dev/null 2>&1 && systemctl enable chronyd >/dev/null 2>&1 || true

  if [ "${RHEL_ver}" == '9' ]; then
    [ ! -e "/usr/lib64/libtinfo.so.5" ] && [ -e /usr/lib64/libtinfo.so.6 ] && ln -s /usr/lib64/libtinfo.so.6 /usr/lib64/libtinfo.so.5
    [ ! -e "/usr/lib64/libncurses.so.5" ] && [ -e /usr/lib64/libncurses.so.6 ] && ln -s /usr/lib64/libncurses.so.6 /usr/lib64/libncurses.so.5
  fi

  echo "${CMSG}Installing dependencies packages...${CEND}"
  pkgList="gcc gcc-c++ make cmake autoconf pkgconfig bison re2c patch perl perl-devel openssl openssl-devel zlib zlib-devel pcre2 pcre2-devel libxml2 libxml2-devel libxslt libxslt-devel gd gd-devel libjpeg libjpeg-devel libpng libpng-devel libwebp libwebp-devel freetype freetype-devel bzip2 bzip2-devel libzip libzip-devel readline readline-devel curl curl-devel libevent libevent-devel libicu libicu-devel expat expat-devel oniguruma oniguruma-devel libtirpc libtirpc-devel sqlite sqlite-devel libsodium libsodium-devel ca-certificates curl wget gnupg2 python3-pip tar gzip xz file less procps-ng iproute iputils bind-utils traceroute telnet socat net-tools sudo systemd cronie logrotate rsyslog chrony git rsync lsof psmisc vim-enhanced nano tmux screen htop bc expect unzip zip gawk grep sed findutils util-linux which libatomic firewalld"
  for Package in ${pkgList}; do
    yum -y install ${Package}
  done
  [ "${RHEL_ver}" -lt 8 ] 2>/dev/null && yum -y install cmake3
  yum -y update bash openssl glibc
}

installDepsBySrc() {
  if command -v lsof >/dev/null 2>&1; then
    echo 'already initialize' > ~/.oneinstack
  else
    echo "${CFAILURE}${PM} config error parsing file failed${CEND}"
    kill -9 $$; exit 1
  fi
}
