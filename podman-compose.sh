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

help() {
    cmd=$(basename "$0")
    cat << ____EOF
Usage: $cmd [OPTIONS] COMMAND
       $cmd [ --help ]

Start, stop or remove Podman container.

OPTIONS:
    -h, --help      Print usage

COMMANDS:
    up        Create and start container.
    stop      Stop container.
    down      Stop and remove container.
    help      Print usage

Run '$cmd COMMAND --help' for more information on each command.
____EOF
}

up() {
    help() {
        cmd=$(basename "$0")
        cat << ________EOF
Usage:  $cmd up [OPTIONS] [COMMAND] [ARGS...]

Create and start container and run COMMAND ARGS in the container. If COMMAND is not specified, then a shell is run.

OPTIONS:
    -d, --detach                  Detached mode.
    --project DIR                 Directory where rulesets are stored and results will be written to.
                                  Defaults to the current working directory.
    --project-name NAME           Name to label and find containers, images and volumes with.
                                  Defaults to '$project_name_default'.
    -h, --help                    Print usage.
________EOF
    }

    cmd_args=()
    detach="no"
    project=""
    project_name=""
    project_name_default="nuevomatchup"

    while [ $# -ne 0 ]; do
        case "$1" in
            "-d"|"--detach")
                detach="yes"
                ;;
            "-h"|"--help")
                help
                return 0
                ;;
            "--project")
                if [ -z "$2" ]; then
                    error "flag is missing arg: --project"
                    return 255
                fi

                project="$2"
                shift
                ;;
            "--project-name")
                if [ -z "$2" ]; then
                    error "flag is missing arg: --project-name"
                    return 255
                fi

                project_name="$2"
                shift
                ;;
            -*)
                error "Unknown flag: $1"
                return 255
                ;;
            *)
                cmd_args=("$@")
                set -- 'FOR_NEXT_SHIFT_ONLY'
                ;;
        esac
        shift
    done

    [ -n "$project_name" ] || project_name=$project_name_default

    # Locate script directory
    # NOTE: Symbolic links are followed first in order to always resolve to
    #       the script's directory even if called through a symbolic link.
    cmd_dir=$(dirname "$(readlink -f "$0")")

    # Locate project directory
    if [ -n "$project" ]; then
        project_dir=$(readlink -f "$project")
    else
        project_dir=$(readlink -f "$PWD")
    fi

    # Load kernel modules for DPDK used by ovs-nuevomatchup [0] and simple-packet-gen [1]
    #
    # Kernel modules uio and uio_pci_generic are part of the Linux kernel. However, kernel module igb_uio is part of an
    # external repository [2]. Some distributions such as Debian provide packages [3] for building this module.
    #
    # [0] https://github.com/acsl-technion/ovs-nuevomatchup/blob/main/scripts/dpdk-init.sh
    # [1] https://github.com/alonrs/simple-packet-gen/blob/main/bind.sh
    # [2] https://git.dpdk.org/dpdk-kmods/
    # [3] https://packages.debian.org/source/sid/dpdk-kmods
    modprobe vfio enable_unsafe_noiommu_mode=1
    for kmod in vfio-pci uio igb_uio uio_pci_generic; do
        if modprobe "$kmod"; then
            echo "Loaded kernel module '$kmod'."
        else
            warn "Loading kernel module '$kmod' failed."
        fi
    done

    # Load kernel module for Open vSwitch
    modprobe openvswitch

    if podman container exists "${project_name}"; then
        # Container exists
        if [ -z "$(podman container ls -a -q "--filter=name=^${project_name}\$" --filter=status=running)" ]
        then
            warn "Stopped container ${project_name} will be (re)started, but not rebuild."\
                 "Remove container first to force rebuild."
            podman start "${project_name}"

            if [ "$detach" != "yes" ]; then
                podman attach "${project_name}"
            fi
        fi
    else # Container does not exist
        if ! podman image exists "${project_name}:latest"; then
            (cd "$cmd_dir" && podman image build -f "Dockerfile" -t "${project_name}:latest" .)
        fi

        podman_args=()

        # Disable SELinux separation for the container
        podman_args+=(--security-opt label=disable)

        # Allow direct access to network devices
        podman_args+=(--privileged --network host)

        # Allow access to huge pages
        podman_args+=(-v /dev/hugepages:/dev/hugepages)

        # Grant access to rulesets and provide place to store results
        podman_args+=(-v "$project_dir/data/:/ovs-nuevomatchup/data/")

        # Allow access to uio devices
        for dev in /dev/uio*; do
            if [ -e "$dev" ]; then
                podman_args+=(--device "$dev:$dev")
            fi
        done

        # Unauthenticated and unencrypted RPC from load-generating (LGEN) machine to system-under-test (SUT) machine
        # NOTE: Required on system-under-test (SUT) machine only.
        podman_args+=(--publish '2001:2001/tcp')

        # For development only
        podman_args+=(-v "$cmd_dir/entrypoint.sh:/usr/local/bin/entrypoint.sh:ro")

        if [ "$detach" = "yes" ]; then
            podman_args+=(--detach)
        fi

        podman run \
            --init \
            --interactive \
            --tty \
            --name "${project_name}" \
            -e "DEBUG=${DEBUG:=no}" \
            "${podman_args[@]}" \
            "${project_name}:latest" "${cmd_args[@]}"
    fi
}

stop() {
    help() {
        cmd=$(basename "$0")
        cat << ________EOF
Usage:  $cmd stop [OPTIONS]

Stop container.

OPTIONS:
    --project-name NAME   Name to label and find the container with.
                          Defaults to '$project_name_default'.
    -h, --help            Print usage
________EOF
    }

    project_name=""
    project_name_default="nuevomatchup"

    while [ $# -ne 0 ]; do
        case "$1" in
            "-h"|"--help")
                help
                return 0
                ;;
            "--project-name")
                if [ -z "$2" ]; then
                    error "flag is missing arg: --project-name"
                    return 255
                fi

                project_name="$2"
                shift
                ;;
            -*)
                error "Unknown flag: $1"
                return 255
                ;;
            *)
                error "Unknown command: $1"
                return 255
                ;;
        esac
        shift
    done

    [ -n "$project_name" ] || project_name=$project_name_default

    podman stop --ignore "${project_name}"
}

down() {
    help() {
        cmd=$(basename "$0")
        cat << ________EOF
Usage:  $cmd down [OPTIONS]

Stop and remove container.

OPTIONS:
    --project-name NAME   Name to label and find the container with.
                          Defaults to '$project_name_default'.
    -h, --help            Print usage
________EOF
    }

    project_name=""
    project_name_default="nuevomatchup"

    while [ $# -ne 0 ]; do
        case "$1" in
            "-h"|"--help")
                help
                return 0
                ;;
            "--project-name")
                if [ -z "$2" ]; then
                    error "flag is missing arg: --project-name"
                    return 255
                fi

                project_name="$2"
                shift
                ;;
            -*)
                error "Unknown flag: $1"
                return 255
                ;;
            *)
                error "Unknown command: $1"
                return 255
                ;;
        esac
        shift
    done

    [ -n "$project_name" ] || project_name=$project_name_default


    podman stop --ignore "${project_name}"
    podman rm --force --ignore "${project_name}"
    podman image rm --force "${project_name}:latest" || true
}

if [ $# -eq 0 ]; then
    help
    exit 1
fi

if [ "$(id -u)" -ne 0 ]; then
    error "Please run as root"
    exit 125
fi

for cmd in modprobe podman; do
    if ! command -v "$cmd" >/dev/null; then
        error "$cmd not found"
        exit 255
    fi
done

while [ $# -ne 0 ]; do
    case "$1" in
        "up"|"stop"|"down"|"help")
            ("$@")
            exit
            ;;
        "-h"|"--help")
            help
            exit 0
            ;;
        -*)
            error "Unknown flag: $1"
            exit 1
            ;;
        *)
            error "Unknown command: $1"
            exit 1
            ;;
    esac
    shift
done
