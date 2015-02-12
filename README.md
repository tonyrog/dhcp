# dhcp

This is DHCP Server in Erlang for running on Linux.

The Linux dependency comes mostly from the use of a special ioctl to inject ARP information into the kernel. The alternative to that would be to use raw packet socket, but those are not supported in Erlang.

The bind-to-interface socket option is also Linux specific, but the server could work without it.

## Requirements

* Linux
* Erlang (>= R17, older probably works as well)
