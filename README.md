# Reproducer for NuevoMatchUP

This repository helps reproducing the test bed and benchmark results from [Scaling Open vSwitch with a Computational
Cache](https://www.usenix.org/conference/nsdi22/presentation/rashelbach) by Alon Rashelbach, Ori Rottenstreich and Mark
Silberstein (2022). Basically, it wraps their code for Open vSwitch from [acsl-technion/ovs-nuevomatchup](
https://github.com/acsl-technion/ovs-nuevomatchup) and their packet generator from [alonrs/simple-packet-gen](
https://github.com/alonrs/simple-packet-gen) in a Podman container. The container is based on Ubuntu 18.04 LTS (Bionic
Beaver) and provides an environment which resembles the original software setup closely.

## Prepare

In the [paper](https://www.usenix.org/conference/nsdi22/presentation/rashelbach) the authors describe their setup as
follows:

> We use two machines connected back-to-back via Intel X540-AT2 10Gb Ethernet NICs with DPDK-compatible driver. All our
> tests stress the OVS logic thus the workload is CPU-bound and the network is not saturated.
> The system-under-test machine (SUT) runs Ubuntu 18.04, Linux 5.4, OVS 2.13 with DPDK 19.11, on Intel Xeon Sliver
> 4116 CPU @ 2.1GHz with 32KB L1 cache, 1024KB L2 cache, and 16.5MB LLC. The load-generating machine (LGEN) runs a
> native DPDK application that generates packets on-the-fly according to a predefined policy, and records the responses
> from the SUT.
> We configure both machines to use DPDK with four 1GB huge pages for maximum performance. We disable hyper-threading
> and set the CPU governor to maximum performance for stable results.

Their code for Open vSwitch in [acsl-technion/ovs-nuevomatchup](https://github.com/acsl-technion/ovs-nuevomatchup)
states:

> Connect two machines back-to-back using DPDK supported NICs. The machines should also be connected to a shared LAN
> (e.g., via another NIC). This is essential for running the scripts. The *System Under Test* (SUT) machine must have an
> Intel CPU that supports both the AVX and POPCNT extensions. You must have a Linux OS with root permissions in both
> machines for building the environment. Contact me for a link to the ruleset artifacts, or create one of your own using
> [these tools](https://alonrashelbach.com/2021/12/20/benchmarking-packet-classification-algorithms/).

Basically, two servers are required, each with three network devices. Two network devices must be supported by DPDK, the
third is required for ip connectivity between both nodes.

The paper and code does not provide instructions on how to reproduce the rulesets. Hence, contact Alon Rashelbach
<alonrs@gmail.com> first and ask him for a link to the ruleset artifacts.

**NOTE:** The packet generator ([alonrs/simple-packet-gen](https://github.com/alonrs/simple-packet-gen)) which runs on
load-generating (LGEN) machine generates packets where [both the source and destination mac addresses are
`00:00:00:00:00:00`](https://github.com/alonrs/simple-packet-gen/blob/d8044276b360db38a0bc17a4ae0c05d2afb5af05/lib/packet.c#L59).
Packets with such a mac address will often be dropped by switches. When using a switch to connect both machines ensure
that those packets will be transmitted correctly. One workaround for Juniper switches such as EX4600 switches is to use
[traffic mirroring](https://www.juniper.net/documentation/us/en/software/junos/network-mgmt/topics/topic-map/port-mirroring-and-analyzers-configuring.html):
Place the DPDK network devices on both machines in distinct VLANs, i.e. a total of four VLANs will be used for the DPDK
traffic. Traffic mirroring will then be set up from the first port of the load-generating (LGEN) machine to the first
port of the system-under-test (SUT) machine. It will also be configured from the second port of latter to the second
port of the former. (Bidirectional traffic mirroring is not supported).

## Build, deploy and test

Install `git` and [Podman](https://podman.io/docs/installation) on two bare-metal servers. One server will be the
load-generating (LGEN) machine and the other will be the system-under-test (SUT) machine. This guide uses Fedora
CoreOS 39 as the operating system for the servers but other Linux distributions like Debian 11 (Bullseye), CentOS
Stream 8, Ubuntu 22.04 LTS (Jammy Jellyfish) or newer will work as well.

Ensure both servers have huge pages allocated and the Intel IOMMU driver enabled. For Fedora CoreOS use the following
commands or adapt them to your Linux distribution accordingly:

```sh
sudo -s

# Allocate huge pages
# Ref.:
# [0] https://docs.openvswitch.org/en/latest/intro/install/dpdk/
# [1] https://www.kernel.org/doc/html/latest/admin-guide/mm/hugetlbpage.html
# [2] https://docs.fedoraproject.org/en-US/fedora-coreos/kernel-args/
rpm-ostree kargs --append=hugepagesz=2M --append=hugepages=4096

# Enable Intel IOMMU driver
# Ref.:
# [0] https://www.kernel.org/doc/html/latest/admin-guide/kernel-parameters.html
# [1] https://docs.fedoraproject.org/en-US/fedora-coreos/kernel-args/
rpm-ostree kargs --append=intel_iommu=on --append=iommu=pt

# Reboot to apply changes
reboot
```

After both servers have been rebooted open a shell on each server and run:

```sh
git clone https://github.com/JM1/ovs-nuevomatchup-reproducer.git
cd ovs-nuevomatchup-reproducer/
```

Ask Alon Rashelbach for the ruleset artifacts. Copy his archive `ovs-nmu-lgen-artifacts-1.tar.gz` to the load-generating
(LGEN) machine and `ovs-nmu-data-sut.tar.gz` to the system-under-test (SUT) machine. This example assumes both archives
have been copied to folder `~/nsdi2022` on the relevant machines.

At the load-generating (LGEN) machine, extract the ruleset artifacts into the recently created
`ovs-nuevomatchup-reproducer` folder with:

```sh
tar -xvf ~/nsdi2022/ovs-nmu-lgen-artifacts-1.tar.gz
```

The `data` folder on the load-generating (LGEN) machine should list four directories:

```
generated
locality
rulesets
timestamp
```

At the system-under-test (SUT) machine, extract the ruleset artifacts into the recently created
`ovs-nuevomatchup-reproducer` folder with:

```sh
tar -xvf ~/nsdi2022/ovs-nmu-data-sut.tar.gz
```

The `data` folder on the system-under-test (SUT) machine should list one directory:

```
generated
```

Then run the following command to create a Podman container named `nuevomatchup` and attach to it:

**NOTE:** Beware, the container is running with extended privileges, i.e. `--privileged`, has access to the host
network, i.e. `--network host`, and disables SELinux separation for the container, i.e. `--security-opt label=disable`.

**NOTE:** The system-under-test (SUT) machine will listen for commands from load-generating (LGEN) machine on TCP port
2001 without any authentication or encryption. Ensure that nobody has network access to the system-under-test (SUT)
machine!

```sh
sudo DEBUG=yes ./podman-compose.sh up
```

Inside this container a Bash shell will be spawned for user `root`. From this shell, print the network devices and their
status on both systems with:

```sh
dpdk-devbind.py --status-dev net
```

Ignore error messages `lspci: Unable to load libkmod resources: error -12`.

In this example, the output for the load-generating (LGEN) machine is:

```
Network devices using kernel driver
===================================
0000:03:00.0 'MT27520 Family [ConnectX-3 Pro] 1007' if=enxe41d2d123db0,enxe41d2d123db1 drv=mlx4_core unused=vfio-pci,uio_pci_generic
0000:07:00.0 'I350 Gigabit Network Connection 1521' if=enxf8bc121412c0 drv=igb unused=vfio-pci,uio_pci_generic *Active*
0000:07:00.1 'I350 Gigabit Network Connection 1521' if=enxf8bc121412c1 drv=igb unused=vfio-pci,uio_pci_generic

Other Network devices
=====================
0000:01:00.0 'Ethernet Controller X710 for 10GbE SFP+ 1572' unused=vfio-pci,uio_pci_generic
0000:01:00.1 'Ethernet Controller X710 for 10GbE SFP+ 1572' unused=vfio-pci,uio_pci_generic
```

Both `Ethernet Controller X710 for 10GbE SFP+ 1572` devices is what will be used throughout this guide.

Next, unbind both network devices:

```sh
dpdk-devbind.py -u 0000:01:00.0 0000:01:00.1
```

On success, the tool will report back that both devices are not managed by any driver:

```
Notice: 0000:01:00.0 Ethernet Controller X710 for 10GbE SFP+  is not currently managed by any driver
Notice: 0000:01:00.1 Ethernet Controller X710 for 10GbE SFP+  is not currently managed by any driver
```

Bind both network devices to a new driver, in this case `vfio-pci`:

```sh
dpdk-devbind.py -b vfio-pci 0000:01:00.0 0000:01:00.1
```

Verify that both network devices have been bound to the new driver with:

```sh
dpdk-devbind.py --status-dev net
```

In this example, the output for the load-generating (LGEN) machine will be:

```
Network devices using DPDK-compatible driver
============================================
0000:01:00.0 'Ethernet Controller X710 for 10GbE SFP+ 1572' drv=vfio-pci unused=uio_pci_generic
0000:01:00.1 'Ethernet Controller X710 for 10GbE SFP+ 1572' drv=vfio-pci unused=uio_pci_generic

Network devices using kernel driver
===================================
0000:03:00.0 'MT27520 Family [ConnectX-3 Pro] 1007' if=enxe41d2d123db0,enxe41d2d123db1 drv=mlx4_core unused=vfio-pci,uio_pci_generic
0000:07:00.0 'I350 Gigabit Network Connection 1521' if=enxf8bc121412c0 drv=igb unused=vfio-pci,uio_pci_generic *Active*
0000:07:00.1 'I350 Gigabit Network Connection 1521' if=enxf8bc121412c1 drv=igb unused=vfio-pci,uio_pci_generic
```

Before running the experiments, the connectivity between both systems will be tested with `dpdk-testpmd`. At the
system-under-test (SUT) machine run:

```sh
dpdk-testpmd -w 0000:01:00.0 -w 0000:01:00.1 -- --forward-mode=macswap --auto-start --stats-period 1
```

At the load-generating (LGEN) machine run:

```sh
dpdk-testpmd -w 0000:01:00.0 -w 0000:01:00.1 -- --forward-mode=macswap -i
```

Inside the `testpmd>` shell at the load-generating (LGEN) machine start packet forwarding after sending an initial 
packet first with:

```sh
start tx_first
```

To verify that this initial packet is forward infinitely between both machines, view the port statistics at the 
load-generating (LGEN) machine with:

```sh
show port stats all
```

The system-under-test (SUT) machine will output similar port statistics every second. Afterwards, run `quit` at the
load-generating (LGEN) machine to exit the `dpdk-testpmd` application. Also terminate `dpdk-testpmd` at the other
machine.

Configure both network devices and the ip address which the benchmark tooling should use on both systems, the
load-generating (LGEN) machine and system-under-test (SUT) machine:

```sh
vi /ovs-nuevomatchup/scripts/.config
```

Example for the load-generating (LGEN) machine:

```sh
# RX PCI bus
pci_rx=0000:01:00.0

# TX PCI bus
pci_tx=0000:01:00.1

# SUT ip address
sut_ip=192.168.0.3

# LGEN number of TXQs
lgen_txq=4

pci_0=$(echo -e "$pci_rx\n$pci_tx" | sort | head -1)
if [ "$pci_0" = "$pci_rx" ]; then
    rxport=0
    txport=1
else
    rxport=1
    txport=0
fi
```

Example for the system-under-test (SUT) machine:

```sh
# RX PCI bus
pci_rx=0000:01:00.1

# TX PCI bus
pci_tx=0000:01:00.0
```

On the system-under-test (SUT) machine, start the RPC service with:

```sh
scripts/run-experiments.sh sut
```

On the load-generating (LGEN) machine, start the experiments with:

```sh
scripts/run-experiments.sh lgen
```

The last command will begin printing output similar to:

```
Got experiment list: 'cores thr-caida-3m'
Connecting to "192.168.0.3"...
Connected; sending "./scripts/ovs-config.sh --default"...
Waiting for the server to finish executing the command...
Performing experiment cores
Performing on ruleset ipc1-1k
Connecting to "192.168.0.3"...
Connected; sending "./scripts/ovs-start.sh --autorun --cores 2"...
Waiting for the server to finish executing the command...
Loading packet generator...
/ovs-nuevomatchup/simple-packet-gen/run.sh --tx 1 --rx 0 --eal "-w 0000:01:00.0 -w 0000:01:00.1" --p-mapping --file1 /ovs-nuevomatchup/data/generated/ipc1-1k/mapping.txt --file2 /ovs-nuevomatchup/data/timestamp/caida-3m-diff --file3 /ovs-nuevomatchup/data/locality/caida-3m --n1 0 --rxq 4 --txq 4 --signal 30 --time-limit 120
EAL: Detected 12 lcore(s)
EAL: Detected 1 NUMA nodes
EAL: Multi-process socket /var/run/dpdk/rte/mp_socket
EAL: Selected IOVA mode 'VA'
EAL: 1 hugepages of size 1073741824 reserved, but no mounted hugetlbfs found for that size
Printing stats to stdout every 1000 msec
Using mapping policy.
Reading mapping from "/ovs-nuevomatchup/data/generated/ipc1-1k/mapping.txt"...
Reading locality from "/ovs-nuevomatchup/data/locality/caida-3m"...
Reading timestamps from "/ovs-nuevomatchup/data/timestamp/caida-3m-diff"...
Allocating 6925.395 MB for packet data...
Waiting for 8 generator workers to generate packet data...
EAL arguments: [-w] [0000:01:00.0] [-w] [0000:01:00.1]
EAL: Probing VFIO support...
EAL: VFIO support initialized
EAL: PCI device 0000:01:00.0 on NUMA socket 0
EAL:   probe driver: 8086:1572 net_i40e
EAL:   using IOMMU type 1 (Type 1)
EAL: PCI device 0000:01:00.1 on NUMA socket 0
EAL:   probe driver: 8086:1572 net_i40e
Created mempool0 with 2048 elements each of 2048 bytes on socket 0.
Port 1 with 1 RX queues (64 descs) and 4 TX queus (256 descs) initialized on socket 0
Getting port 1 status... link up, speed 10000 Mpps - full-duplex
Created mempool1 with 2048 elements each of 2048 bytes on socket 0.
Created mempool2 with 2048 elements each of 2048 bytes on socket 0.
Created mempool3 with 2048 elements each of 2048 bytes on socket 0.
Created mempool4 with 2048 elements each of 2048 bytes on socket 0.
Port 0 with 4 RX queues (256 descs) and 1 TX queus (64 descs) initialized on socket 0
Getting port 0 status... link up, speed 10000 Mpps - full-duplex
Signal sent to PID 30
Lgen set options with status 0
Set constant TX rate with TX 7000 Kpps
Connecting to "192.168.0.3"...
Connected; sending "./scripts/ovs-load.sh --emc --ruleset ipc1-1k --ovs-orig --n-handler 1 --n-revalidator 1 --n-rxq 1"...
Waiting for the server to finish executing the command...
Sending 't 7000' to LGEN
What would you wish to do? Continue [C]; Stop [S]; Reset with rate limiter [T]; Restart [R]; Echo [E]; Set adaptive rate multiplier (0 disables adaptive) [A] :Enter message:  Reloading OVS with ruleset ipc1-1k method '--ovs-orig' options '--n-handler 1 --n-revalidator 1 --n-rxq 1'
What would you wish to do? Continue [C]; Stop [S]; Reset with rate limiter [T]; Restart [R]; Echo [E]; Set adaptive rate multiplier (0 disables adaptive) [A] :Enter new rate in Kpps:
Reset with constant TX rate of 7000 Kpps
Starting TX worker on core 1
Starting TX worker on core 2
Starting TX worker on core 3
Starting RX worker on core 4
Starting RX worker on core 5
Starting RX worker on core 6
Starting RX worker on core 7
Starting TX worker on core 0
Created mempool5 with 2048 elements each of 2048 bytes on socket 0.
Created mempool7 with 2048 elements each of 2048 bytes on socket 0.
Created mempool8 with 2048 elements each of 2048 bytes on socket 0.
Created mempool6 with 2048 elements each of 2048 bytes on socket 0.
RX 0.0000 Mpps, errors: 1, avg. latency 0.0 usec, drops: 100.000 %
TX 6.9849 Mpps
RX 0.0000 Mpps, errors: 0, avg. latency 0.0 usec, drops: 100.000 %
TX 6.9848 Mpps
RX 0.0000 Mpps, errors: 0, avg. latency 0.0 usec, drops: 100.000 %
TX 6.9849 Mpps
RX 0.0000 Mpps, errors: 0, avg. latency 0.0 usec, drops: 100.000 %
TX 6.9847 Mpps
RX 0.0000 Mpps, errors: 0, avg. latency 0.0 usec, drops: 100.000 %
TX 6.9848 Mpps
RX 0.0000 Mpps, errors: 0, avg. latency 0.0 usec, drops: 100.000 %
TX 6.9847 Mpps
RX 0.0000 Mpps, errors: 0, avg. latency 0.0 usec, drops: 100.000 %
TX 6.9851 Mpps
RX 0.0000 Mpps, errors: 0, avg. latency 0.0 usec, drops: 100.000 %
TX 6.9848 Mpps
RX 0.0000 Mpps, errors: 0, avg. latency 0.0 usec, drops: 100.000 %
TX 6.9851 Mpps
RX 0.0000 Mpps, errors: 0, avg. latency 0.0 usec, drops: 100.000 %
TX 6.9849 Mpps
RX 0.0000 Mpps, errors: 0, avg. latency 0.0 usec, drops: 100.000 %
TX 6.9850 Mpps
RX 0.0000 Mpps, errors: 0, avg. latency 0.0 usec, drops: 100.000 %
TX 6.9850 Mpps
RX 0.0000 Mpps, errors: 0, avg. latency 0.0 usec, drops: 100.000 %
TX 6.9852 Mpps
RX 0.0000 Mpps, errors: 0, avg. latency 0.0 usec, drops: 100.000 %
TX 6.9849 Mpps
Lgen set options with status 1
Drop percent of last experiment: 100.000 (status: -1)
Set constant TX rate with TX 3500 Kpps
Connecting to "192.168.0.3"...
Connected; sending "./scripts/ovs-copy-log.sh ipc1-1k cores ovs-orig t 7000 cores-2 n-handler-1-n-revalidator-1-n-rxq-1"...
Waiting for the server to finish executing the command...
```

Afterwards the results can be found in the `data` folder on both machines.

Exit the Bash shell to stop the container.

Finally, remove the Podman container with:

```sh
sudo DEBUG=yes ./podman-compose.sh down
```

## Questions

* What is `lgen_txq=` in `scripts/.config` aka `LGEN number of TXQs` supposed to be?
* Why is `simple-packet-gen`, i.e.`client.exe`, reporting `drops: 100.000 %`? Why is it not sending packets from the
  load-generating (LGEN) machine to the system-under-test (SUT) machine?
* Why does `ovs-vswitchd` keep crashing with the following error message?
  ```
  2024-03-13T08:50:45.404Z|00002|dpif_netdev(pmd-c00/id:24)|INFO|Extended stats: insertions: 0 deletions: 0 total-flows: 1 packets: 1 subtables: 1.000000 upcalls: 0 upcall-avg-us: -nan dfc-us: 0.35 fastpath-us: 1.51 execute-us: 0.42 dpcls-us: 0.94 lookup-us: 0.00
  2024-03-13T08:51:10.632Z|00190|bridge|INFO|bridge br1: deleted interface port-2 on port 2
  2024-03-13T08:51:10.632Z|00191|bridge|INFO|bridge br1: deleted interface br1 on port 65534
  2024-03-13T08:51:10.633Z|00192|bridge|INFO|bridge br1: deleted interface port-1 on port 1
  2024-03-13T08:51:10.633Z|00193|dpif_netdev|INFO|Core 1 on numa node 0 assigned port 'port-1' rx queue 0 (measured processing cycles 297253).
  2024-03-13T08:51:10.633Z|00194|dpif_netdev|INFO|Core 2 on numa node 0 assigned port 'port-1' rx queue 1 (measured processing cycles 0).
  2024-03-13T08:51:10.633Z|00195|dpif_netdev|INFO|Core 0 on numa node 0 assigned port 'port-1' rx queue 2 (measured processing cycles 0).
  2024-03-13T08:51:10.652Z|00196|dpif_netdev|INFO|PMD thread on numa_id: 0, core id:  2 destroyed.
  2024-03-13T08:51:10.653Z|00197|dpif_netdev|INFO|PMD thread on numa_id: 0, core id:  0 destroyed.
  2024-03-13T08:51:10.654Z|00198|dpif_netdev|INFO|PMD thread on numa_id: 0, core id:  1 destroyed.
  2024-03-13T08:51:10.729Z|00001|util(urcu2)|EMER|lib/dpif-netdev.c:8295: assertion cmap_count(&subtable->rules) == 0 failed in dpcls_destroy()
   * nmu-cool-down-time-ms=0
   * nmu-error-threshold=128
   * nmu-train-threshold=90
   * nmu-garbage-collection-ms=0
   * nmu-max-collision=40
   * nmu-minimal-coverage=45
   * nmu-instant-remainder=true
   * log-interval-ms=1000
  *** Configuration:
  *** emc_enabled=true
  *** smc_enabled=false
  *** ccache_enabled=false
  *** cflows_enabled=false
  2024-03-13T08:51:11.736Z|00002|backtrace(monitor)|WARN|Backtrace using libunwind not supported.
  2024-03-13T08:51:11.736Z|00003|daemon_unix(monitor)|ERR|1 crashes: pid 2895 died, killed (Aborted), core dumped, restarting
  ```
