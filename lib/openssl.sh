#!/bin/bash
# Private Nginx-only toolkit.

Install_openSSL() {
  if [ ! -e "${openssl_install_dir}/lib/libssl.a" ]; then
    mkdir -p "${oneinstack_dir}/downloads"
    pushd "${oneinstack_dir}/downloads" > /dev/null
    tar xzf openssl-${openssl_ver}.tar.gz
    pushd openssl-${openssl_ver} > /dev/null
    make clean
    ./config -Wl,-rpath=${openssl_install_dir}/lib -fPIC --prefix=${openssl_install_dir} --openssldir=${openssl_install_dir}
    make depend
    make -j ${THREAD} && make install
    popd > /dev/null
    if [ -f "${openssl_install_dir}/lib/libcrypto.a" ]; then
      echo "${CSUCCESS}openSSL installed successfully! ${CEND}"
      [ -f cacert.pem ] && /bin/cp cacert.pem ${openssl_install_dir}/cert.pem
      rm -rf openssl-${openssl_ver}
    else
      echo "${CFAILURE}openSSL install failed.${CEND}" && grep -Ew 'NAME|ID|ID_LIKE|VERSION_ID|PRETTY_NAME' /etc/os-release
      kill -9 $$; exit 1
    fi
    popd > /dev/null
  fi
}
