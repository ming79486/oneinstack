#!/bin/bash
# Private Nginx-only toolkit.

checkDownload() {
  mkdir -p "${oneinstack_dir}/downloads"
  pushd "${oneinstack_dir}/downloads" > /dev/null

  echo "Download OpenSSL..."
  src_url=https://www.openssl.org/source/openssl-${openssl11_ver}.tar.gz && Download_src

  echo "Download jemalloc..."
  src_url=https://github.com/jemalloc/jemalloc/releases/download/${jemalloc_ver}/jemalloc-${jemalloc_ver}.tar.bz2 && Download_src

  echo "Download PCRE2..."
  src_url=https://github.com/PCRE2Project/pcre2/releases/download/pcre2-${pcre2_ver}/pcre2-${pcre2_ver}.tar.gz && Download_src

  echo "Download Nginx..."
  src_url=https://nginx.org/download/nginx-${nginx_ver}.tar.gz && Download_src

  popd > /dev/null
}
