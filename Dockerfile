# Copyright (c) 2024 Jakob Meng, <jakobmeng@web.de>
# 
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
# 
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
# 
# You should have received a copy of the GNU General Public License
# along with this program. If not, see <http://www.gnu.org/licenses/>.

FROM ubuntu:bionic

ARG DEBIAN_FRONTEND=noninteractive

# Fake sudo calls during container builds because sudo during container image builds for Ubuntu 18.04 LTS (Bionic
# Beaver) fails with an error:
#
#   sudo: unable to send audit message
#   sudo: pam_open_session: System error
#   sudo: policy plugin failed session initialization
#
RUN ln -s /usr/bin/env /usr/local/bin/sudo

RUN apt-get update && \
  apt-get install -y apt-utils git less locales patch procps tmux vim tcpdump

# Satisfy DPDK requirements [0]
# [0] https://git.launchpad.net/ubuntu/+source/dpdk/tree/debian/control?h=applied/ubuntu/bionic-updates
RUN apt-get install -y debhelper dh-python dkms doxygen graphviz inkscape libcap-dev libibverbs-dev libpcap-dev \
                       libnuma-dev python3 python3-sphinx python3-sphinx-rtd-theme

# dpdk-devbind.py requires the ip binary
RUN apt-get install -y iproute2

# Satisfy Open vSwitch requirements [0],[1] except DPDK which is build manually
# [0] https://git.launchpad.net/~ubuntu-server-dev/ubuntu/+source/openvswitch/tree/debian/control?h=ubuntu/bionic
# [1] https://github.com/openvswitch/ovs/blob/branch-2.11/utilities/ovs-ctl.in#L67
RUN apt-get install -y autoconf automake bzip2 debhelper dh-python graphviz libcap-ng-dev  libnuma-dev libpcap-dev \
            libssl-dev libtool openssl pkg-config procps python-all-dev python-setuptools python-six python3-all-dev \
            python3-setuptools python3-six python3-sphinx \
            uuid-runtime

# Satisfy ovs-nuevomatchup requirements [0], [1]
# [0] https://github.com/acsl-technion/ovs-nuevomatchup/blob/main/build-sut.sh
# [1] https://github.com/acsl-technion/ovs-nuevomatchup/blob/main/scripts/ovs-stop.sh
RUN apt-get install -y wget unzip pciutils intel-cmt-cat

# Satisfy simple-packet-gen requirements [0],[1]
# [0] https://github.com/alonrs/simple-packet-gen/blob/main/Makefile
# [1] https://github.com/alonrs/simple-packet-gen/blob/main/build.sh
RUN apt-get install -y pkg-config meson ninja-build libpcap-dev python3 pciutils

# Satisfy DPDK requirements for simple-packet-gen
#
# build.sh [0] (triggered from build-lgen.sh [1]) fails to build DPDK v19.11 because the latter raises an error on
# Ubuntu 18.04:
#
#  meson.build:4:0: ERROR: Meson version is 0.45.1 but project requires >= 0.47.1.
#
# Ubuntu 18.04 only provides meson 0.45.1, only newer Ubuntu releases offer meson versions >= 0.47.1. According to the
# authors [2] Ubuntu 18.04 was used for the producing the results [2] but the error message suggests that a custom meson
# version must have been used.
#
# [0] https://github.com/alonrs/simple-packet-gen/blob/main/build.sh
# [1] https://github.com/acsl-technion/ovs-nuevomatchup/blob/main/build-lgen.sh
# [2] https://www.usenix.org/system/files/nsdi22-paper-rashelbach.pdf
RUN apt install -y python3-pkg-resources wget && \
  cd /tmp && \
  wget http://ftp.de.debian.org/debian/pool/main/m/meson/meson_0.49.2-1_all.deb && \
  dpkg -i meson_0.49.2-1_all.deb

# USER=root is required because USER is not set by default but used when building simple-packet-gen [0]
# [0] https://github.com/alonrs/simple-packet-gen/blob/main/build.sh
ARG USER=root

RUN git clone https://github.com/acsl-technion/ovs-nuevomatchup.git /ovs-nuevomatchup
WORKDIR /ovs-nuevomatchup

# Prepare tools for system under test (sut)
#
# Speed up compilation
RUN sed -i -e 's/-j4/-j$(nproc)/g' build-sut.sh
#
# Drop sudo call because commands are executed as root
RUN sed -i -e 's/sudo make -C $ovs_dir install/make -C $ovs_dir -j$(nproc) install/g' build-sut.sh
#
# RTE_KERNEL dir is defined otherwise compilation would fail when host system is using a different kernel than the
# container.
RUN sed -i -e \
's/\(make -C $dpdk_dir [^c].*\)$/\1 "RTE_KERNELDIR=\$(find \/lib\/modules\/ -maxdepth 2 -name build -print -quit)"/g' \
  build-sut.sh
#
# Fail on build error
RUN sed -i -e 's/\(make .*\)$/\1 || exit 255/g' build-sut.sh
#
# The script scripts/dpdk-init.sh is replaced with a dummy because network devices are bound separately from OVS launch.
RUN (cd scripts && mv -v dpdk-init.sh dpdk-init.sh.orig && touch dpdk-init.sh && chmod a+x dpdk-init.sh;)

# Build tools for system under test (sut)
#
# An ephemeral scripts/.config is created in order to prevent build-sut.sh from asking for user input.
RUN touch scripts/.config && bash -x ./build-sut.sh && rm scripts/.config

# Install DPDK, in particular dpdk-testpmd
RUN cd /ovs-nuevomatchup/dpdk/build && make install

# Store full Open vSwitch logs on system under test (sut)
RUN echo 'cp -av "$ovs_log_file" "$log.log"' >> scripts/ovs-copy-log.sh

# Prepare tools for load-generating machine (lgen)
#
# simple-packet-gen uses PWD instead of CURDIR [0] which breaks make's -C/--directory argument.
# [0] https://github.com/alonrs/simple-packet-gen/blob/bfa6bbb84054db0c45ef4db642e6c3356bd6851f/Makefile#L28
RUN sed -i -e 's/make -C \$pgen_dir -j4$/\(set -x \&\& cd \$pgen_dir \&\& make -j\$\(nproc\)\)/g' build-lgen.sh
#
# Build only, no bind
RUN sed -i -e 's/^fi$/fi; exit/g' build-lgen.sh

# Build tools for load-generating machine (lgen)
RUN bash -x ./build-lgen.sh

RUN ln -s /ovs-nuevomatchup/dpdk/usertools/dpdk-devbind.py /usr/local/bin/dpdk-devbind.py
RUN cd /usr/local/bin && ln -s testpmd dpdk-testpmd

COPY config /ovs-nuevomatchup/scripts/.config
COPY entrypoint.sh /usr/local/bin/

# Allow ovs-tcpdump to find Open vSwitch Python libraries
ARG PYTHONPATH=/usr/local/share/openvswitch/python/

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]

CMD []
