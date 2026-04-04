#
# spec file for package apache-cf-remoteip
#
# Copyright (c) 2026 Rumen Damyanov
# SPDX-License-Identifier: Apache-2.0

%global debug_package %{nil}

Name:           apache-cf-remoteip
Version:        0.1.0
Release:        1%{?dist}
Summary:        apache-cf-remoteip Apache module

License:        Apache-2.0
URL:            https://github.com/RumenDamyanov/apache-cf-remoteip
Source0:        %{name}-%{version}.tar.gz

BuildRequires:  gcc
BuildRequires:  make
BuildRequires:  rust
BuildRequires:  cargo
BuildRequires:  httpd-devel

Requires:       httpd >= 2.4.0

%description
Apache httpd module. See project README for details.

%prep
%setup -q

%build
export CARGO_HOME=$(pwd)/target/cargo_home
cargo build --release
apxs -c -Wc,-Wall -Wc,-std=c99 \
    -Wl,target/release/libcf_remoteip.a \
    -lpthread -ldl -lm \
    src/mod_cf_remoteip.c

%install
%if 0%{?suse_version}
MODULES_DIR=%{_usr}/lib64/apache2
%else
MODULES_DIR=%{_libdir}/httpd/modules
%endif

install -d %{buildroot}${MODULES_DIR}
install -m 0644 src/.libs/mod_cf_remoteip.so %{buildroot}${MODULES_DIR}/

%files
%license LICENSE.md
%doc README.md
%if 0%{?suse_version}
%dir %{_usr}/lib64/apache2
%{_usr}/lib64/apache2/mod_cf_remoteip.so
%else
%dir %{_libdir}/httpd
%dir %{_libdir}/httpd/modules
%{_libdir}/httpd/modules/mod_cf_remoteip.so
%endif

%changelog
* Sat Apr 04 2026 Rumen Damyanov <contact@rumenx.com> - 0.1.0-1
- Initial release
