# Reproducer for NuevoMatchUP

This repository helps reproducing the test bed and benchmark results from [Scaling Open vSwitch with a Computational
Cache][Rashelbach et al. (2022)] by Alon Rashelbach, Ori Rottenstreich and Mark Silberstein (2022). Basically, it wraps
their code for Open vSwitch from [ovs-nuevomatchup] and their packet generator from [simple-packet-gen] in a
[Podman][podman] container. The container is based on Ubuntu 18.04 LTS (Bionic Beaver) and provides an environment which
resembles the original software setup closely.

## Prepare

[Rashelbach et al. (2022)] describes the test bed for conducting the experiments as follows:

> We use two machines connected back-to-back via Intel X540-AT2 10Gb Ethernet NICs with DPDK-compatible driver. All our
> tests stress the OVS logic thus the workload is CPU-bound and the network is not saturated.
> The system-under-test machine (SUT) runs Ubuntu 18.04, Linux 5.4, OVS 2.13 with DPDK 19.11, on Intel Xeon Sliver
> 4116 CPU @ 2.1GHz with 32KB L1 cache, 1024KB L2 cache, and 16.5MB LLC. The load-generating machine (LGEN) runs a
> native DPDK application that generates packets on-the-fly according to a predefined policy, and records the responses
> from the SUT.
> We configure both machines to use DPDK with four 1GB huge pages for maximum performance. We disable hyper-threading
> and set the CPU governor to maximum performance for stable results.

The authors code for Open vSwitch ([ovs-nuevomatchup]) states:

> Connect two machines back-to-back using DPDK supported NICs. The machines should also be connected to a shared LAN
> (e.g., via another NIC). This is essential for running the scripts. The *System Under Test* (SUT) machine must have an
> Intel CPU that supports both the AVX and POPCNT extensions. You must have a Linux OS with root permissions in both
> machines for building the environment. Contact me for a link to the ruleset artifacts, or create one of your own using
> [these tools](https://alonrashelbach.com/2021/12/20/benchmarking-packet-classification-algorithms/).

Basically, two servers are required, each with three network devices. Two network devices must be supported by DPDK, the
third is required for ip connectivity between both nodes.

The paper and code does not provide instructions on how to reproduce the rulesets. Hence, contact Alon Rashelbach
<alonrs@gmail.com> first and ask him for a link to the ruleset artifacts.

**NOTE:** The packet generator ([simple-packet-gen]) which runs on load-generating (LGEN) machine generates packets
where [both the source and destination mac addresses are `00:00:00:00:00:00`](
https://github.com/alonrs/simple-packet-gen/blob/d8044276b360db38a0bc17a4ae0c05d2afb5af05/lib/packet.c#L59).
Packets with such a mac address will often be dropped by switches. When using a switch to connect both machines ensure
that those packets will be transmitted correctly. One workaround for Juniper switches such as EX4600 switches is to use
[traffic mirroring][junos-port-mirroring]:
Place the DPDK network devices on both machines in distinct VLANs, i.e. a total of four VLANs will be used for the DPDK
traffic. Traffic mirroring will then be set up from the first port of the load-generating (LGEN) machine to the first
port of the system-under-test (SUT) machine. It will also be configured from the second port of latter to the second
port of the former. (Bidirectional traffic mirroring is not supported).

## Build, deploy and test

Install `git` and [Podman][podman] on two bare-metal servers. One server will be the load-generating (LGEN) machine and
the other will be the system-under-test (SUT) machine. This guide uses Fedora CoreOS 39 as the operating system for the
servers but other Linux distributions like Debian 11 (Bullseye), CentOS Stream 8, Ubuntu 22.04 LTS (Jammy Jellyfish) or
newer will work as well.

Ensure both servers have huge pages allocated and the Intel IOMMU driver enabled. For Fedora CoreOS use the following
commands or adapt them to your Linux distribution accordingly:

```sh
sudo -s

# Allocate huge pages
# Ref.:
# [0] https://docs.openvswitch.org/en/latest/intro/install/dpdk/
# [1] https://www.kernel.org/doc/html/latest/admin-guide/mm/hugetlbpage.html
# [2] https://docs.fedoraproject.org/en-US/fedora-coreos/kernel-args/
rpm-ostree kargs --append=hugepagesz=1G --append=hugepages=4

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
Connecting to "10.6.38.122"...
Connected; sending "./scripts/ovs-config.sh --default"...
Waiting for the server to finish executing the command...
Performing experiment cores
Experiment cores-2 exists for ruleset ipc1-1k
Performing on ruleset ipc1-1k
Connecting to "10.6.38.122"...
Connected; sending "./scripts/ovs-start.sh --autorun --cores 3"...
Waiting for the server to finish executing the command...
Loading packet generator...
/ovs-nuevomatchup/simple-packet-gen/run.sh --tx 1 --rx 0 --eal "-w 0000:01:00.0 -w 0000:01:00.1" --p-mapping --file1 /ovs-nuevomatchup/data/generated/ipc1-1k/mapping.txt --file2 /ovs-nuevomatchup/data/timestamp/caida-3m-diff --file3 /ovs-nuevomatchup/data/locality/caida-3m --n1 0 --rxq 4 --txq 4 --signal 29 --time-limit 120
EAL: Detected 12 lcore(s)
EAL: Detected 1 NUMA nodes
EAL: Multi-process socket /var/run/dpdk/rte/mp_socket
EAL: Selected IOVA mode 'VA'
EAL: No available hugepages reported in hugepages-1048576kB
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
Lgen set options with status 0
Set constant TX rate with TX 7000 Kpps
Connecting to "10.6.38.122"...
Connected; sending "./scripts/ovs-load.sh --emc --ruleset ipc1-1k --ovs-orig --n-handler 1 --n-revalidator 1 --n-rxq 2"...
Waiting for the server to finish executing the command...
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
Signal sent to PID 29
Sending 't 7000' to LGEN
What would you wish to do? Continue [C]; Stop [S]; Reset with rate limiter [T]; Restart [R]; Echo [E]; Set adaptive rate multiplier (0 disables adaptive) [A] :Enter message:  Reloading OVS with ruleset ipc1-1k method '--ovs-orig' options '--n-handler 1 --n-revalidator 1 --n-rxq 2'
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
Created mempool8 with 2048 elements each of 2048 bytes on socket 0.
Created mempool7 with 2048 elements each of 2048 bytes on socket 0.
Created mempool6 with 2048 elements each of 2048 bytes on socket 0.
RX 0.3539 Mpps, errors: 0, avg. latency 11258558.4 usec, drops: 94.914 %
TX 6.9850 Mpps
RX 0.4644 Mpps, errors: 0, avg. latency 11752906.5 usec, drops: 93.352 %
TX 6.9848 Mpps
RX 0.6906 Mpps, errors: 0, avg. latency 12094556.0 usec, drops: 90.113 %
TX 6.9850 Mpps
RX 0.9094 Mpps, errors: 0, avg. latency 12419215.9 usec, drops: 86.980 %
TX 6.9849 Mpps
RX 1.2626 Mpps, errors: 0, avg. latency 12852536.6 usec, drops: 81.921 %
TX 6.9840 Mpps
RX 1.6917 Mpps, errors: 0, avg. latency 13286100.1 usec, drops: 75.780 %
TX 6.9849 Mpps
RX 1.9040 Mpps, errors: 0, avg. latency 13631604.6 usec, drops: 72.741 %
TX 6.9849 Mpps
RX 1.9621 Mpps, errors: 0, avg. latency 14042296.3 usec, drops: 71.910 %
TX 6.9848 Mpps
RX 2.6274 Mpps, errors: 0, avg. latency 14492602.8 usec, drops: 62.385 %
TX 6.9849 Mpps
RX 2.6291 Mpps, errors: 0, avg. latency 14959126.3 usec, drops: 62.360 %
TX 6.9847 Mpps
RX 1.4836 Mpps, errors: 0, avg. latency 15430274.3 usec, drops: 78.760 %
TX 6.9851 Mpps
RX 2.4684 Mpps, errors: 0, avg. latency 16104370.0 usec, drops: 64.662 %
TX 6.9848 Mpps
RX 2.9283 Mpps, errors: 0, avg. latency 16759928.0 usec, drops: 58.077 %
TX 6.9848 Mpps
RX 3.1013 Mpps, errors: 0, avg. latency 17255439.1 usec, drops: 55.582 %
TX 6.9822 Mpps
Signal sent to PID 29
Lgen set options with status 1
Drop percent of last experiment: 65.810 (status: -1)
Set constant TX rate with TX 3500 Kpps
Connecting to "10.6.38.122"...
Connected; sending "./scripts/ovs-copy-log.sh ipc1-1k cores ovs-orig t 7000 cores-3 n-handler-1-n-revalidator-1-n-rxq-2"...
Waiting for the server to finish executing the command...
```

**NOTE:** When `ovs-vswitchd`'s log file at `/usr/local/var/log/openvswitch/ovs-vswitchd.log` or the output of
`scripts/run-experiments.sh lgen` has errors like `EAL: Failed to open group 20`, `EAL: Error - exiting with code: 1` or
`Cause: Error: number of ports is not 2. Use the EAL -w option to filter PCI addresses.`, then `exit` the container,
rerun `sudo DEBUG=yes ./podman-compose.sh up` and execute the corresponding `scripts/run-experiments.sh` command again.

**NOTE:** Initially, a drop rate of 100% might be observed when the load-generating (LGEN) machine crushes the
system-under-test (SUT) machine, i.e. Open vSwitch not being able to handle the amount of packets being sent. However,
the drop rate should drop below 100% in most cases after a while.

For each experiment, ovs-vswitchd will be started on the system-under-test (SUT) machine, followed by
[simple-packet-gen] on the load-generating (LGEN) machine. ovs-vswitchd will print extended statistics once a second on
the system-under-test (SUT) machine. ovs-vswitchd's log file will be stored separately for each experiment and used
later for the performance analysis and comparison between OVS-ORIG, OVS-CCACHE and OVS-CFLOWS. The results, i.e.
ovs-vswitchd's log files, can be found in the `data` folder on the system-under-test (SUT) machine.

[ovs-nuevomatchup-cores]: https://github.com/acsl-technion/ovs-nuevomatchup/blob/06b0b607529d390c7fee3e12061458789b047e06/scripts/run-experiments.sh#L321
[ovs-nuevomatchup-thr-caida-3m]: https://github.com/acsl-technion/ovs-nuevomatchup/blob/06b0b607529d390c7fee3e12061458789b047e06/scripts/run-experiments.sh#L441
[ovs-nuevomatchup-run-experiments]: https://github.com/acsl-technion/ovs-nuevomatchup/blob/06b0b607529d390c7fee3e12061458789b047e06/scripts/run-experiments.sh

By default, i.e. without further arguments, `scripts/run-experiments.sh lgen` will run the `cores` and `thr-caida-3m`
experiments. The [`cores` experiment][ovs-nuevomatchup-cores] will evaluate OVS-ORIG, OVS-CCACHE and OVS-CFLOWS with 2
to 10 cores. It will create 277 output files (ovs-vswitchd logs) in directory `data/generated/ipc1-1k` with names like
`cores-ovs-*-t-*-cores-*-n-handler-1-n-revalidator-1-n-rxq-*`. For each file, there is another file with the same
basename and a `.log` postfix which contains the untruncated log from `ovs-vswitchd`.
The [`thr-caida-3m` experiment][ovs-nuevomatchup-thr-caida-3m] will evaluate the throughput for OVS-ORIG, OVS-CCACHE and
OVS-CFLOWS with 2 cores. It will create 946 output files in various subdirectories of `data/generated` with names like
`thr-caida-3m-ovs-*-t-*-cores-2-n-handler-1-n-revalidator-1-n-rxq-1`. For each file, there is another file with the same
basename and a `.log` postfix which contains the untruncated log from `ovs-vswitchd`.

The following arguments can be passed to [`scripts/run-experiments.sh lgen`][ovs-nuevomatchup-run-experiments] to choose
experiments:
* `manual`
* `llc`
* `cores`
* `megaflow`
* `update`
* `thr-caida-3m`
* `thr-mawi-15`
* `thr-zipf-0.9`
* `thr-zipf-0.6`

**NOTE:** The last three throughput commands require additional rulesets!

To analyse the experiments, grep for `Extended stats` in the ovs-vswitchd logs. For example, ovs-vswitchd's output
should be similar to:

```
2024-03-23T09:10:03.210Z|00007|dpif_netdev(pmd-c00/id:9)|INFO|Extended stats: insertions: 5809 deletions: 0 total-flows: 30985 packets: 27584 subtables: 101.427475 upcalls: 5809 upcall-avg-us: 9.71 dfc-us: 2398.60 fastpath-us: 994327.60 execute-us: 1002.49 dpcls-us: 168921.32 lookup-us: 1187.31
```

Alon Rashelbach explains:

> These stats should be printed once a second. You could see the:
> 1. Megaflow cache statistics (subtables, flows, insertions, deletions)
> 2. Number of processed packets.
> 3. Upcall statistics (#upcalls, avg usec per upcall)
> 4. Time breakdown of various components.
>
> We would like to compare between two experiments w/ the same LGEN throughput, but one with ovs-orig and the second
> with ovs-ccache. Then see how the Megaflow cache behaves.

[ovs-nuevomatchup] provides additional scripts to partially automate the analysis:
* [scripts/analyze-log.sh](https://github.com/acsl-technion/ovs-nuevomatchup/blob/main/scripts/analyze-log.sh) helps
  with printing the throughput rates.
* [scripts/analyze-ovs.sh](https://github.com/acsl-technion/ovs-nuevomatchup/blob/main/scripts/analyze-ovs.sh) will
  output the "Number of subtable lookups for flow table hits." divided by "Packets that matched in the flow table." for
  a given experiment (e.g. thr-caida-3m), size category (e.g. 500K rules) and method (e.g. ovs-orig) and packet
  generator speeds per ruleset (e.g. 7000 Kpps).
* [scripts/analyze-update.sh](https://github.com/acsl-technion/ovs-nuevomatchup/blob/main/scripts/analyze-update.sh)
  helps with postprocessing the data for the OpenFlow rule update rate charts.

Afterwards exit the Bash shell to stop the container.

Finally, remove the Podman container with:

```sh
sudo DEBUG=yes ./podman-compose.sh down
```

## Observations

The code in [ovs-nuevomatchup] is based on Open vSwitch 2.13 ([2.13.0 was released on 2020-02-14](
http://www.openvswitch.org/releases/NEWS-2.13.0)) and DPDK 19.11
([19.11.0 was released on 2019-11-28](http://fast.dpdk.org/rel/)).

The Open vSwitch module `lib/dpif-netdev-nmu.{c,h}` in [ovs-nuevomatchup] depends on a shared library [libnuevomatchup]
which is distributed as a binary only without source code.

Alon Rashelbach does provide ruleset artifacts on demand. Neither [Rashelbach et al. (2022)] nor [ovs-nuevomatchup]
provide instructions on how to reproduce the rulesets. In particular, the exact parameters for [ClassBench][classbench]
to reproduce the synthetic OpenFlow rules are unknown. The commands to generate rulesets for load-generating, i.e.
[build-lgen.sh](https://github.com/acsl-technion/ovs-nuevomatchup/blob/main/build-lgen.sh) from traffic traces like
[CAIDA][caida] and [MAWI][mawi] are also not available.

An earlier article [A Computational Approach to Packet Classification (2020)][Rashelbach et al. (2020)] from the
same authors proves the correctness of the underlying RQ-RMI model in the appendix (this section is not peer-reviewed).
Understanding and reproducing the NuevoMatch and NuevoMatchUP algorithms as well as understanding and verifying their
theoretical foundation requires knowledge of machine-learning, in particular neural networks.

The NuevoMatchUP module for OVS ([ovs-nuevomatchup]) does not provide tests. During development it was tested by Alon
Rashelbach using the following approach:

> 1. Connect two machines back to back, one with a DPDK-based packet generator, other with OVS.
> 2. The packet generator generates packets that match the OF rules while marking them with the OF rule ID inside the
>    IPv4 payload.
> 3. Each OF rule has an action that sets the dst IP to the rule's ID and then sends the packet back to the packet 
>    generator.
>
> 4. When the packet returns, the packet generator compares the payload tag with the modified dst IP.
>
> The problem with this approach is that OVS throughput drops significantly due to Megaflow fragmentation that
> originates in the unique action per OF rule. In the end, I measured the correctness for all of these rulesets, then
> measured the performance in different tests w/o the unique action per OF rule.

## Questions and answers

* What is `lgen_txq=` in `scripts/.config` aka `LGEN number of TXQs` in [ovs-nuevomatchup] supposed to be?

  The number of TX queues used for generating packets at the load-generating (LGEN) machine. Alon Rashelbach recommends
  using at least 4.

* Why is [simple-packet-gen], i.e.`client.exe`, reporting `drops: 100.000 %`? Why is it not sending packets from the
  load-generating (LGEN) machine to the system-under-test (SUT) machine?

  When using a switch between both the load-generating (LGEN) machine and the system-under-test (SUT) machine, the
  switch might drop packets from the packet generator ([simple-packet-gen]) because the latter generates packets where
  [both the source and destination mac addresses are `00:00:00:00:00:00`](
  https://github.com/alonrs/simple-packet-gen/blob/d8044276b360db38a0bc17a4ae0c05d2afb5af05/lib/packet.c#L59). Read the
  preparation chapter above for workarounds.

  It could also be an artifact of the load-generating (LGEN) machine crushing the system-under-test (SUT) machine, i.e.
  Open vSwitch not being able to handle the amount of packets being sent. The drop rate should drop below 100% in most
  cases after a while.

* `scripts/run-experiments.sh lgen` prints the following error messages:

  ```
  Loading packet generator...
  /ovs-nuevomatchup/simple-packet-gen/run.sh --tx 1 --rx 0 --eal "-w 0000:01:00.0 -w 0000:01:00.1" --p-mapping --file1 /ovs-nuevomatchup/data/generated/ipc1-1k/mapping.txt --file2 /ovs-nuevomatchup/data/timestamp/caida-3m-diff --file3 /ovs-nuevomatchup/data/locality/caida-3m --n1 0 --rxq 4 --txq 4 --signal 59 --time-limit 120
  EAL: Detected 12 lcore(s)
  EAL: Detected 1 NUMA nodes
  EAL: Multi-process socket /var/run/dpdk/rte/mp_socket
  EAL: Selected IOVA mode 'VA'
  EAL: No available hugepages reported in hugepages-1048576kB
  Packet generator has stopped
  scripts/run-experiments.sh: line 238:    96 Terminated              tail -f $lgen_output
  Loading packet generator...
  EAL: PCI device 0000:01:00.0 on NUMA socket 0
  EAL:   probe driver: 8086:1572 net_i40e
  EAL: Failed to open group 19
  EAL:  0000:01:00.0 not managed by VFIO driver, skipping
  EAL: PCI device 0000:01:00.1 on NUMA socket 0
  EAL:   probe driver: 8086:1572 net_i40e
  EAL: Failed to open group 20
  EAL:  0000:01:00.1 not managed by VFIO driver, skipping
  EAL: Error - exiting with code: 1
    Cause: Error: number of ports is not 2. Use the EAL -w option to filter PCI addresses.
  ```

  In this case, `exit` the container, rerun `sudo DEBUG=yes ./podman-compose.sh up` and execute
  `scripts/run-experiments.sh lgen` again.

* `ovs-vswitchd` prints the following error message in `/usr/local/var/log/openvswitch/ovs-vswitchd.log`:

  ```
  EAL: PCI device 0000:01:00.0 on NUMA socket 0
  EAL:   probe driver: 8086:1572 net_i40e
  EAL: Failed to open group 19
  EAL:  0000:01:00.0 not managed by VFIO driver, skipping
  EAL: PCI device 0000:01:00.1 on NUMA socket 0
  EAL:   probe driver: 8086:1572 net_i40e
  EAL: Failed to open group 20
  EAL:  0000:01:00.1 not managed by VFIO driver, skipping
  EAL: Error - exiting with code: 1
    Cause: Error: number of ports is not 2. Use the EAL -w option to filter PCI addresses.
  ```

  In this case, `exit` the container, rerun `sudo DEBUG=yes ./podman-compose.sh up` and execute
  `scripts/run-experiments.sh sut` again.

## Open questions

* Why does `ovs-vswitchd` keep crashing with the following error message ([ovs-nuevomatchup])?

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

* Why do ovs-vswitchd's log files for OVS-CFLOWS report that NuevoMatchUP is disabled while reporting
  `cflows_enabled=true` at the same time?

  Example from `data/generated/fw1-500k/thr-caida-3m-ovs-cflows-t-7000-cores-2-n-handler-1-n-revalidator-1-n-rxq-1`:

  ```
  2024-03-23T02:37:09.574Z|00990|dpif_netdev_nmu(ovs-vswitchd)|INFO|NuevoMatchUp is disabled
  ```

* Why do experiments for OVS-CFLOWS show upcalls in extended statistics although OVS-CFLOWS avoids upcalls according to
  [Rashelbach et al. (2022)]?

  For example, `data/generated/fw2-500k/thr-caida-3m-ovs-cflows-t-7000-cores-2-n-handler-1-n-revalidator-1-n-rxq-1`
  shows:

  ```
  2024-03-23T04:51:15.326Z|00017|dpif_netdev(pmd-c00/id:9)|INFO|Extended stats: insertions: 7523 deletions: 0 total-flows: 153720 packets: 27232 subtables: 21.175840 upcalls: 7523 upcall-avg-us: 10.16 dfc-us: 2630.83 fastpath-us: 994427.51 execute-us: 1128.26 dpcls-us: 150492.99 lookup-us: 1927.69
  ```

* Why do both experiments `cores` and `thr-caida-3m` show similar extended statistics for OVS-ORIG and OVS-CFLOWS, even
  with high number of flows (e.g. 500K)?

  Example for OVS-CFLOWS with 500K flows, ruleset fw1 and 7000 Kpps from
  `data/generated/fw1-500k/thr-caida-3m-ovs-cflows-t-7000-cores-2-n-handler-1-n-revalidator-1-n-rxq-1`:

  ```
  2024-03-23T02:37:39.865Z|00017|dpif_netdev(pmd-c00/id:9)|INFO|Extended stats: insertions: 3848 deletions: 0 total-flows: 57409 packets: 15488 subtables: 87.879395 upcalls: 3848 upcall-avg-us: 12.15 dfc-us: 1485.05 fastpath-us: 997078.11 execute-us: 696.67 dpcls-us: 164651.69 lookup-us: 929.22
  ```

  Versus example for OVS-ORIG with 500K flows, ruleset fw1 and 7000 Kpps from
  `data/generated/fw1-500k/thr-caida-3m-ovs-orig-t-7000-cores-2-n-handler-1-n-revalidator-1-n-rxq-1`:

  ```
  2024-03-23T02:06:25.214Z|00017|dpif_netdev(pmd-c00/id:9)|INFO|Extended stats: insertions: 3805 deletions: 0 total-flows: 57296 packets: 15520 subtables: 88.337568 upcalls: 3805 upcall-avg-us: 12.23 dfc-us: 1406.60 fastpath-us: 997938.16 execute-us: 674.24 dpcls-us: 165588.50 lookup-us: 963.40 
  ```

  According to [Rashelbach et al. (2022)], OVS-CFLOWS should outperform OVS-ORIG, in particular with higher number of
  flows.

* Why does [scripts/analyze-log.sh](https://github.com/acsl-technion/ovs-nuevomatchup/blob/main/scripts/analyze-log.sh)
  print error `awk: cmd. line:31: (FILENAME=- FNR=1) fatal: division by zero attempted` for every ovs-vswitchd log file?

  The script tries to extract data from log files with `grep -Pi "reloading|tx rate|^tx|^rx" $logfile`. However, none of
  the log files have any matching lines?!

* [Rashelbach et al. (2020)] (p. 547):
  > Thus, to find the match to a query with multiple fields, we query all RQ-RMIs (in parallel), each over the field on
  > which it was trained.

  How is parallelism in "Query all the RQ-RMIs" controlled in OVS-CCACHE and OVS-CFLOWS? For example, is there a maximum
  for the number of threads?

  According to the article, two cores were used for some benchmarks. How are RQ-RMIs queried in parallel with two cores?
  Multiple threads per core? One thread per RQ-RMI?

* What is the size of the "single remainder set" as mentioned in [Rashelbach et al. (2020)] (p. 547)? What is the
  absolute number of entries and its percentage of the complete ruleset?

* How exactly does the iSet partitioning algorithm work in [Rashelbach et al. (2020)]?

* Is the iSet partitioning algorithm, i.e. "greedy heuristic" in [Rashelbach et al. (2020)] (p. 547), applied in each
  training session?

* [Rashelbach et al. (2020)] (p. 548):

  > Both iSet partitioning algorithms and RQ-RMI models map the inputs into single-precision floating-point numbers. This
  > allows the packing of more scalars in vector operations, resulting in faster inference. While enough for 32-bit
  > fields, doing so might cause poor performance for fields of 64-bits and 128-bits.

  How are long fields (48bits mac addresses, 128bits ipv6 addresses) handled by NuevoMatchUP? Does NuevoMatchUP differ
  from NuevoMatch?

* With an increasing number of iSets the memory consumption increases, causing NuevoMatchUP to loose its performance
  benefits because iSets no longer fit in a CPU's L1/L2 cache. Authors write in [Rashelbach et al. (2020)] (p. 547):

  > Each iSet contains rules that do not overlap in one specific dimension. We refer to the coverage of an iSet as the
  > fraction of the rules it holds out of those in the input. One iSet may cover all the rules if they do not overlap
  > in at least one dimension, whereas the same dimension with many overlapping ranges may require multiple iSets.

  How does a ruleset, which causes a high number of iSets, look like? Would it be likely that OpenShift or OpenStack
  environments would face a huge number of iSets?

* Table 2 in [Rashelbach et al. (2020)] (p. 552) shows that iSet coverage decreases with a decreasing number of rules.
  For 10K rules, the best iSet coverage of 65%+-35% is with 4 iSets. Figure 14 in [Rashelbach et al. (2020)] (p. 552)
  shows that execution time of NuevoMatch with 4 iSets is already higher than when using CutSplit without NuevoMatch.
  With 3 iSets execution time is slightly lower of NuevoMatch, best is with 1 or 2 iSets.

  Does this mean that NuevoMatch plus CutSplit or NeuroCuts (for remainder) is best used for cases with >=100K flow
  rules (using 1 or 2 iSets)? Or is it better to use NeuvoMatch with TupleMerge (for remainder) using 4 iSets?
  Would it be better to use CutSplit or NeuroCuts or TupleMerge without NuevoMatch for less than 100K flows?

* What training time and target rate for the prediction error was used when creating figure 14 in
  [Rashelbach et al. (2020)] (p. 552)?

* Figure 8 in [Rashelbach et al. (2020)] (p. 550) shows a throughput speedup for NuevoMatch (NM) compared to
  TupleMerge (TM) and others when using 2 cores and the ClassBench rulesets. NM has a thr. speedup of 1.2x over TM.
  Figure 9 (p. 551) shows a thr. speedup for 1.6x when using 1 core only. Figure 12 (p. 551) shows thr. speedup of
  0.89x to 1.16x for NM over TM for 500K ClassBench rules, skewed Zipf traffic and (skewed?) CAIDA traffic and an
  unknown number of cores.

  What has the absolut throughput been for the original non-NuevoMatch implementation in OVS? Did OVS scale down
  properly from 2 to 1 core during benchmarks, in particular considering that `ovs-vswitchd`'s config variables
  `other_config:n-revalidator-threads` and `other_config:n-handler-threads` have not been updated to reflect the lower
  number of cores available to OVS in [Rashelbach et al. (2022)] / [ovs-nuevomatchup]?

* Figure 11 in [Rashelbach et al. (2020)] (p. 551) shows a thr. speedup of 2x for NuevoMatch over TupleMerge with 100K
  rules and more. However, the thr. axis omits most of thr. below 2M pps, the thr. speedup shown is ~1.6x for 100K rules
  and 1.4x for 1M rules. The thr. speedup numbers suggest that a single core has been used for figure 11 similar to
  figure 9. What ruleset, traffic traces and number of cores were used for figure 11?

* Figures 11 and 13 and section "5.2.1 memory footprint comparison" in [Rashelbach et al. (2020)] (p. 551f) suggests
  that NuevoMatch's thr. gains stem from more memory efficient representation, where the RQ-RMI models and the remainder
  classifier fit into L1 and L2 while TupleMerge spills over to L2 and L3. Authors write in [Rashelbach et al. (2020)]:

  > The memory footprint includes only the index data structures but not the rules themselves.

  How does cache usage look like when rules are taken into account? What shares do RQ-RMI models, remainder classifier,
  rules, code and other data take from L1, L2, L3 caches? Is it reasonable to assume that more efficient CPU cache usage
  is responsible for NuevoMatch's thr. speedups?

* Figure 15 in [Rashelbach et al. (2020)] (p. 553) shows that the training time decreases heavily for search distance
  bounds of 128 but it does not improve significantly for higher bounds. In paragraph about "Training time and secondary
  search range." on p. 553 the authors write:

  > We conclude that training with larger bounds [than 128? 256?] is likely to have a minor eﬀect on the end-to-end
  > performance, but significantly accelerate training.

  How have maximum search distance bounds be defined during RQ-RMI training? Is maximum search range bound a hard bound
  or affected/impacted by a probability?

* Will a increasing number of fields affect NeuvoMatch ([Rashelbach et al. (2020)]) worse than the default packet
  classification algorithm used in OVS? Will it be worse than CutSplit or TupleMerge?

* How has the breakdown in packet processing times in the datapath for different number of OpenFlow rules, shown in
  figure 3 in [Rashelbach et al. (2022)] (p. 1361), been determined? Based on 36 ClassBench OpenFlow rulesets and the
  Caida-short packet trace? How and where has OVS been instrumented? Are the tools and scripts available, which were
  used for doing the experiments?

* Figure 3 in [Rashelbach et al. (2022)] (p. 1361) breaks down packet processing time into time spent at the Megaflow
  cache, the exact-match cache and applying actions. Are upcalls accounted for in the "Megaflow cache" category?

* What traffic trace has been used to determine the OVS throughput during control-path upcalls in figure 4 in
  [Rashelbach et al. (2022)] (p. 1362)? How is OVS throughput affected by the other traffic traces and rulesets? How has
  this sampling every 100ms been implemented? Are the tools and scripts available, which were used for the experiments?

* Throughput in figure 4 in [Rashelbach et al. (2022)] (p. 13629 maxes out at 0,9 Mpps for minimum-size 64 bytes
  packets. This is about 460MBit/s although the network devices are able to do 10GBit/s. Is such a low throughput to be
  expected for small-size packets? How does OVS perform without being sampled? How has sampling been done (statistics to
  stdout, instrumentation, ..)?

  (0,9 * 1000^2) p/s * 64 b/p * 1/1000^2 = 57,6 Mb/s (~460MBit/s)

* Throughput in figure 5 in [Rashelbach et al. (2022)] (p. 1362) maxes out at 3 Mpps for 64b packets. This corresponds
  to 192 Mb/s or 1536 MBit/s for a 10GBit/s link. Has OVS been sampled/instrumented during the tests? What OpenFlow
  rules were present, what traffic traces have been used?

  3*1000^2*64/^(1000^2)

* [Rashelbach et al. (2022)] (p. 1361):

  > RQ-RMI learns the distribution of ranges represented by the rules and outputs the estimated index of the matching
  > rule within an array. At the inference time, this estimation is used as a starting index to search for the matching
  > rule within the array. Crucially, the RQ-RMI training algorithm guarantees a tight bound on the maximum error of the
  > estimated index, which in turn bounds the search and ensures lookup correctness.

  Where to find the proof for the maximum error bounds guarantee?

* Authors write in [Rashelbach et al. (2022)] (p. 1361):

  > RQ-RMI learns the distribution of ranges represented by the rules and outputs the estimated index of the matching
  > rule within an array. At the inference time, this estimation is used as a starting index to search for the matching
  > rule within the array. Crucially, the RQ-RMI training algorithm guarantees a tight bound on the maximum error of the
  > estimated index, which in turn bounds the search and ensures lookup correctness. During the search, the candidate
  > rules are validated by matching over all fields of the incoming packet. Finally, the highest priority rule is
  > selected out of all the matching rules from all the iSets and the remainder.

  And (p. 1363):

  > When new megaflows are added to the data-path, they are first inserted into the original megaflow cache. The RQ-RMI
  > model is periodically re-trained in a separate thread by pulling the added megaflows from the megaflow cache. When
  > the training finishes, the old RQ-RMI models are replaced with the newly trained ones that already incorporate the
  > new megaflows, and the megaflow cache is emptied.

  The OVS-CCACHE implementation of NuevoMatch keeps its own array with rules and actions, otherwise the megaflow cache
  could not be emptied because NuevoMatchUP serves as a lookup accelerator only. This means there is memory allocated
  for:
  - NuevoMatchUP's neural nets. They consume 35 KB for 500K ClassBench rules according to
    [Rashelbach et al. (2020)] (p. 543). How much memory do they use for OVS-CCACHE and OVS-CFLOWS?
  - An array to store the cached Megaflow cache rules and on which NuevoMatchUP will do the lookup.
    (The control path is unmodified.)
  - The existing Megaflow cache which stores megaflow updates and is emptied after retraining.

  What of these datastructures are the neural nets retrained on? The previous megaflow cache is emptied, so the
  retraining must be done on the array? But the array is in use by the NN for the lookup, so it cannot be changed under
  the hood with updated rules? Do we have one array in use for the lookup and a shadow array for the training? Since
  lookup and training are running in parallel, does this mean we have cache trashing for rulesets with higher number
  of rules?

  How much memory all these datastructures consume in total and in comparison to the default OVS implementation?

* [Rashelbach et al. (2022)] (p. 1364):

  > The update rate of OpenFlow rules varies between 400 to 338K updates per second [12, 13].

  Where do these update numbers come from? Reference `[12]` mentions 338K updates but does not explain how it derived
  the number from the cited source.

* RQ-RMI models in NuevoMatchUP ([Rashelbach et al. (2022)]) learn the distribution of buckets instead of the
  distribution of the rules like in NuevoMatch ([Rashelbach et al. (2020)]). [Rashelbach et al. (2022)] (p. 1364):

  > Since the number of buckets is smaller by up to a factor of l than the number of rules, RQ-RMI models in
  > NuevoMatchUP are smaller and train faster than in NuevoMatch (see Table 1). Of course, the cost of this optimization
  > is a slower lookup: all the rules in the same bucket must be validated via a linear scan. This trade-off, however,
  > turned out to be beneficial to accelerate training with a negligible slowdown for the lookup.

  How does this affect the guaranteed maximum error bound for the estimated index? Does it turn into a maximum error
  bound for the estimated bucket? Hence a lookup could have to search in multiple adjacent buckets?

  Considering the constraint of at most l rules per bucket, is it guaranteed that multiple matching rules with different
  priorities always end up in the same bucket? Or will the lookup always look in adjacent buckets to find other matching
  rules with higher priority?

* How does training via approximate sampling [Rashelbach et al. (2022)] (p. 1365) affect the model accuracy? Does the
  training algorithm still guarantee a tight bound on the maximum error of the estimated index when using approximate
  sampling instead of uniform sampling?

* How has training time and lookup time for different bucket sizes and the training time for uniform vs approximate
  sampling been measured in [Rashelbach et al. (2022)]? With the TensorFlow implementation ([Rashelbach et al. (2020)])
  or with the NuevoMatchUP implementation written in C++ ([libnuevomatchup])? Are the scripts and evaluation tools of
  the experiments available?

* [Rashelbach et al. (2022)] (p. 1365):

  > In this experiment we disable all algorithmic optimizations, highlighting the speedup due to the implementation.

  What kind of algorithmic optimizations has been disabled?

* Why do "megaflows frequently migrate between the megaflow cache and the RQ-RMI models" in OVS-CCACHE
  ([Rashelbach et al. (2022)] (p. 1365))? Isn't the megaflow cache only used for megaflow updates used during training
  and then emptied afterwards? Why/How do megaflows migrate from RQ-RMI models to megaflow cache?

* [Rashelbach et al. (2022)] (p. 1366) applied three traffic traces (CAIDA-short, MAWI and CAIDA-long) to 36 synthetic
  OpenFlow rulesets generated with ClassBench (12 rulesets x {1K, 100K, 500K rules}). The figures either explictly show
  results for CAIDA-short only or do not mention which traffic trace has been used.

  How did OVS-CFLOWS and OVS-CCACHE and OVS-ORIG perform against MAWI and CAIDA-long? Are all figures for CAIDA-short
  only? Or have results for all three traffic traces been combined in some figures and how if so? Where to get the
  non-CAIDA-short traces (not part of the ruleset artifacts) and how to reproduce the results?

  What are the CDFs (cumulative distribution functions) of flow length (in packets) for all three traffic traces?

* `caida-3m` in [ovs-nuevomatchup] is CAIDA-short? `caida-3m` has ~96M entries and 6,8M unique entries which roughly
  matches the 100M/6M for CAIDA-short.

* [Rashelbach et al. (2022)] (p. 1366) adjusted traces to rules the following way:

  > Specifically, we modify the packet headers in the trace to match the evaluated ClassBench rule-sets, as follows. For
  > each unique 5-tuple we uniformly select a rule, and modify the packet header to match it. We also set all TCP
  > packets to have a SYN flag. This method preserves the temporal locality of the original trace while consistently
  > covering all the rules.

  According to table 3 in [Rashelbach et al. (2022)] (p. 1366) CAIDA-short, the traffic traces shown in most (all?)
  figures, has 100M packets and 6M unique 5-tuples. It is tested against rulesets with 1K, 100K and 500K rules. Does
  this mean that 6000 packets will apply to a ruleset with 1K rules? For 500K rules, only 12 packets will be received
  (and apply) per rule?

  How do experimental results change when the SYN flag is not set?

* [Rashelbach et al. (2022)] (p. 1367):

  > We use the default OVS configuration [22] both for the baseline and our designs: revalidator threads support up to
  > 200K flows, flows with no traffic are removed after 10 seconds, and the signature-match-cache (SMC) is disabled. The
  > EMC insertion probability is 20%. Connection tracking is not used.

  How do experimental results change when number of revalidator threads and flow limits are adopted to the 500K ruleset
  properly?

* Why is connection tracking not used in [Rashelbach et al. (2022)] (p. 1367)? Is connection tracking supported by
  [libnuevomatchup]?

* [Rashelbach et al. (2022)] (p. 1367):

  > Unless stated otherwise, all experiments use a single NUMA node with one core dedicated to a PMD (poll mode driver)
  > thread and another core dedicated to all other threads. Thus, the baseline OVS, OVS-CCACHE, and OVS-CFLOWS always use
  > the same number of CPU cores.

  [scripts/ovs-start.sh](
  https://github.com/acsl-technion/ovs-nuevomatchup/blob/06b0b607529d390c7fee3e12061458789b047e06/scripts/ovs-start.sh#L91)
  uses `taskset -cp "1-$cores" $(pgrep "ovs-vswi")` to set `ovs-vswitchd`'s CPU affinity. When using a OVS release prior
  to 2.16 ([ovs-nuevomatchup] is based on OVS 2.13), both config variables `other_config:n-revalidator-threads` and
  `other_config:n-handler-threads` be set for optimal performance. With OVS 2.16 and later, these options are ignored by
  `ovs-vswitchd` on modern kernels due to [per-CPU upcall dispatch](
  https://github.com/openvswitch/ovs/commit/b1e517bd2f818fc7c0cd43ee0b67db4274e6b972).

  Might OVS-ORIG suffer from too many threads running in parallel when `ovs-vswitchd`'s affinity is updated but not the
  number of threads? How huge is the impact of context switching, resource contention, lock contention, cache trashing
  etc due to this (mis)configuration?

  Crashes of `ovs-vswitchd`, which happen frequently (several times per log file), does not seem to affect CPU affinity.

* [Rashelbach et al. (2022)] (p. 1367) uses the following NuevoMatchUP configuration for the benchmarks:

  > We use iSets with minimum 45% coverage, and train RQ-RMI neural nets with 4K samples.
  > Similar to [26], we repeat the training until the RQ-RMI maximal error is lower than 128, and stop after 6
  > unsuccessful ones. We set l = 40 , namely, each iSet bucket has at most 40 overlapping rules.

  How have these limits, like at most 40 overlapping rules, been choosen? RQ-RMI maximal error of <128 probably is
  related to figure 14 in [Rashelbach et al. (2020)] (p.552)? Should these limits be set dynamically based on some
  indicators like number of flows? What formulas could be defined to dynamically set these limits?

  What is the target coverage used during training for OVS-CFLOWS? 45%? Or 75% or 90% like shown in figure 15 in
  [Rashelbach et al. (2022)] (p. 1370)?

* What does a 3x / 5x delay mean in figure 13 in [Rashelbach et al. (2022)] (p. 1369)?
* How many cores where available to OVS in figures 14 and 15 in [Rashelbach et al. (2022)] (p. 1369f)?

* [Rashelbach et al. (2022)] states that OVS-CCACHE is compatible with offloading to NVIDIA NICs and DPUs using NVIDIA's
  Accelerated Switching and Packet Processing (ASAP2). The latter ["offloads OVS data-plane tasks to specialized
  hardware, like the embedded switch (eSwitch) within the NIC subsystem, while maintaining an unmodified OVS control-
  plane"](https://docs.nvidia.com/doca/sdk/openvswitch+offload/). The authors write in
  [Rashelbach et al. (2022)] (p. 1371):

  > OVS-CCACHE is compatible with the OVS ecosystem, and can be used with in-NIC OVS offloads [20]. In particular, it
  > may accelerate the CPU handling of misses to the hardware OVS cache.

  How could OVS-CCACHE be used on the CPU side when the data-plane is offloaded to the DPU's or NIC's eSwitch?

* Regarding how [ovs-nuevomatchup] has been tested Alon Rashelbach wrote:

  > at the time I did end-to-end correctness tests as follows:
  > 1. Connect two machines back to back, one with a DPDK-based packet generator, other with OVS.
  > 2. The packet generator generates packets that match the OF rules while marking them with the OF rule ID inside the
  >    IPv4 payload.
  > 3. Each OF rule has an action that sets the dst IP to the rule's ID and then sends the packet back to the packet
  >    generator.
  > 4. When the packet returns, the packet generator compares the payload tag with the modified dst IP.
  >
  > The problem with this approach is that OVS throughput drops significantly due to Megaflow fragmentation that
  > originates in the unique action per OF rule. In the end, I measured the correctness for all of these rulesets, then
  > measured the performance in different tests w/o the unique action per OF rule.

  What OpenFlow rule has been used instead? How much did this tweak to measure without unique actions per OpenFlow rule
  impact the performance? Do the experiments still resemble realistic production scenarios when applying this tweak?

## Future work

* The library [libnuevomatchup], which the [NuevoMatchUP module for OVS][ovs-nuevomatchup] is based on, has to be
  published as [FOSS][foss] before both can be integrated into the Open vSwitch codebase. The RQ-RMI model, the
  NuevoMatch(UP) algorithms and related code should be free of patents and other restrictions. Ensuring both should
  predate any further steps mentioned below.

* The [NuevoMatchUP module for OVS][ovs-nuevomatchup] has to be ported to the development branches of Open vSwitch and
  DPDK. Its current code is based on Open vSwitch 2.13 and DPDK 19.11.

* [ovs-nuevomatchup] has to adhere to Open vSwitch's [coding style guide][ovs-coding-style]. Especially due to its
  novelty, i.e. it introduces a machine-learning algorithm to the OVS codebase, comprehensive tests should be added.
  This is important for gaining trust in the implementation when it is [submitted upstream][ovs-submitting-patches].

* Open vSwitch's kernel datapath has caught up to its DPDK counterpart recently ([centos-stream-9-mr-3862]).
  Experimental results from [Rashelbach et al. (2022)] could be compared to results for OVS' kernel datapath (with
  `openvswitch` kernel module) on a recent Linux kernel.

* With recent kernel versions it is possible to [configure the masks cache size for the `openvswitch` kernel module][
  linux-9bf24f5]. Experimental results from [Rashelbach et al. (2022)] could be compared to OVS' kernel datapath with
  different masks cache sizes.

* How does the iSet partitioning with relaxed iSet constraints work in [Rashelbach et al. (2022)]? Investigate the Open
  vSwitch patch in [ovs-nuevomatchup].

* [Rashelbach et al. (2020)] (p. 547):

  > Each iSet adds to the total memory consumption and computational requirements of NuevoMatch.

  What hardware requirements will show for rulesets in production environments or scale tests?

* Figure 13 in [Rashelbach et al. (2020)] (p. 552) shows a compression of memory footprint for NuevoMatch in comparison
  to CutSplit and TupleMerge. What is the memory footprint compared to OVS' default tuple space search classifier in
  [Pfaff et al. (2015)]?

* How does NuevoMatch from [Rashelbach et al. (2020)] compare to alternative packet classification algorithms mentioned
  in [Pfaff et al. (2015)] like HiCuts, SAX-PAC and EffiCuts?

* [Pfaff et al. (2015)] (p. 3f):

  > While the lookup complexity of tuple space search is far from the state of the art [8, 18, 38], it performs well
  > with the flow tables we see in practice and has three attractive properties over decision tree classification
  > algorithms.
  > First, it supports efficient constant-time updates (an update translates to a single hash table operation), which
  > makes it suitable for use with virtualized environments where a centralized controller may add and remove flows
  > often, sometimes multiple times per second per hypervisor, in response to changes in the whole datacenter.
  > Second, tuple space search generalizes to an arbitrary number of packet header fields, without any algorithmic
  > change. Finally, tuple space search uses memory linear in the number of flows.
  > The relative cost of a packet classification is further amplified by the large number of flow tables that
  > sophisticated SDN controllers use. For example, flow tables installed by the VMware network virtualization
  > controller [19] use a minimum of about 15 table lookups per packet in its packet processing pipeline. Long pipelines
  > are driven by two factors: reducing stages through cross-producting would often significantly increase the flow
  > table sizes and developer preference to modularize the pipeline design. Thus, even more important than the 
  > performance of a single classifier lookup, it is to reduce the number of flow table lookups a single packet
  > requires, on average.

  How does NuevoMatchUP ([Rashelbach et al. (2022)], [libnuevomatchup]) perform when multiple flows are updated each
  second for several hypervisors?

* Considering the fluctating thr. speedup of NuevoMatchUP, as shown in figures 8, 9 and 12 in
  [Rashelbach et al. (2020)] (p. 550ff), and the fact that NuevoMatchUP uses TupleMerge for the remainder, would
  it be reasonable to implement TupleMerge without NuevoMatchUP first, to realize the biggest gains with less amount of
  code changes?

* How do OVS-CCACHE and OVS-CFLOWS ([Rashelbach et al. (2022)], [libnuevomatchup]) perform with 1500b packets instead of
  64b packets?

* What number of flows / OpenFlow rules are characteristical for production environments?

* What update rates for megaflows and OpenFlow rules are seen in production environments? Do they vary between 400 and
  338K updates per second for OpenFlow rules as mentioned in [Rashelbach et al. (2022)] (p. 1364)?

* Will a delayed update policy for OVS-CFLOWS have any significant effect in production environments?

* Section "6.1 Updates in OVS-CFLOWS" in [Rashelbach et al. (2022)] (p. 1366) introduces a delayed update policy for
  OVS-CFLOWS where new OpenFlow rules are not immediately applied to the data-path, not even by pushing them into the
  remainder. Instead, a shadow model will be trained on the new rules in a temporary structure not visible to the
  classifier first and only when training has been finished will the data-path be updated.

  Is the delayed update policy in OVS-CFLOWS feasible for production environments? Are delayed updates feasible in
  OpenShift or OpenStack deployments? Is it a security problem when Openflows are not updated instantly? How does it
  compare to OVS's current update strategy where "the acknowledgement to the controller is sent when the rules are
  installed in the control-path [and the] data-path pulls the rules on demand via upcalls"
  ([Rashelbach et al. (2022)] (p. 1366))?

* Run experiments again with proper values for variables `other_config:n-revalidator-threads` and
  `other_config:n-handler-threads` in order to properly compare OVS-ORIG to OVS-CCACHE and OVS-CFLOWS.

* Figure 10 in [Rashelbach et al. (2022)] (p. 1368) suggests a maximum throughput of ~5.5M pps (~2,8GB/s) for OVS-ORIG
  using 64 byte sized packets, 10GBit/s network, 10 cores, CAIDA-short trace, constant TX settings, and 1K OpenFlow
  rules ("3-1K" is ACL3?). Only when sending packets which always hit the EMC (8K entries) OVS is able to saturate the
  10GBit/s network with 13.8Mpps.

  > For a 10Gb NIC, the performance saturates at 13.8Mpps, 93% of the line-rate³.
  > [...]
  > ³14.88Mpps for 64B packets on a 10Gb NIC, considering bytes of Ethernet preamble and 9.6ns of inter-frame gap.

  Rerun experiments with latest OVS using both the kernel datapath as well as the userspace datapath (DPDK).

* [Rashelbach et al. (2020)] and [Rashelbach et al. (2022)] use 64 byte sized packets for benchmarks. How do OVS-CCACHE
  and OVS-CFLOWS compare to OVS-ORIG when using packet sizes that happen in production environments?

  Investigate performance of OVS-CCACHE, OVS-CFLOWS and OVS-ORIG when using different packet sizes.

* Investigate and compare other packet classification algorithms like TupleMerge, CutSplit, NeuroCuts, HiCuts,
  HyperCuts, SAX-PAC, EffiCuts, [HybridTSS](https://dl.acm.org/doi/abs/10.1145/3542637.3542644).



[Pfaff et al. (2015)]: https://www.openvswitch.org/support/papers/nsdi2015.pdf
[Rashelbach et al. (2020)]: https://arxiv.org/abs/2002.07584
[Rashelbach et al. (2022)]: https://www.usenix.org/conference/nsdi22/presentation/rashelbach
[libnuevomatchup]: https://alonrashelbach.com/libnuevomatchup/
[ovs-nuevomatchup]: https://github.com/acsl-technion/ovs-nuevomatchup
[foss]: https://en.wikipedia.org/wiki/Free_and_open-source_software
[ovs-coding-style]: https://docs.openvswitch.org/en/latest/internals/contributing/coding-style/
[ovs-submitting-patches]: https://docs.openvswitch.org/en/latest/internals/contributing/submitting-patches/
[centos-stream-9-mr-3862]: https://gitlab.com/redhat/centos-stream/src/kernel/centos-stream-9/-/merge_requests/3862
[linux-9bf24f5]: https://github.com/torvalds/linux/commit/9bf24f594c6acf676fb8c229f152c21bfb915ddb
[rhel-9-series-c219a1662276668a7b93afd]: http://kerneloscope.usersys.redhat.com/series/c219a1662276668a7b93afd/
[simple-packet-gen]: https://github.com/alonrs/simple-packet-gen
[junos-port-mirroring]: https://www.juniper.net/documentation/us/en/software/junos/network-mgmt/topics/topic-map/port-mirroring-and-analyzers-configuring.html
[podman]: https://podman.io/docs/installation
[caida]: https://www.caida.org/catalog/datasets/passive_dataset/
[mawi]: http://mawi.wide.ad.jp/mawi/
[classbench]: https://www.arl.wustl.edu/classbench/
