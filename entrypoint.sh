#!/bin/bash
# vim:set tabstop=8 shiftwidth=4 expandtab:
# kate: space-indent on; indent-width 4;
#
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
#

set -euo pipefail

# Environment variables
DEBUG=${DEBUG:=no}

if [ "$DEBUG" = "yes" ] || [ "$DEBUG" = "true" ]; then
    set -x
fi

error() {
    echo "ERROR: $*" 1>&2
}

warn() {
    echo "WARNING: $*" 1>&2
}

if [ "$(id -u)" -ne 0 ]; then
    error "Please run as root"
    exit 125
fi

if [ -z "$(ls -l /sys/class/iommu/*)" ]; then
    error "IOMMU device(s) not found."
    warn "For example, enable Intel IOMMU driver with kernel arguments 'intel_iommu=on iommu=pt'."
    exit 125
fi

if grep '^HugePages_Free: *0$' /proc/meminfo; then
    error "Free huge pages not found."
    warn "For example, enable huge pages with kernel arguments 'hugepagesz=2M hugepages=512 hugepagesz=1G hugepages=1'."
    exit 124
fi

if [ ! -d /dev/hugepages ]; then
    error "No access to huge pages, ensure /dev/hugepages is available in the container."
    exit 123
fi

if [ $# -eq 0 ]; then
    # List network devices but suppress error "lspci: Unable to load libkmod resources: error -12"
    echo "List of available network devices"
    dpdk-devbind.py --status-dev net 2>/dev/null

    bash --login
else
    env -- "$@"
fi
