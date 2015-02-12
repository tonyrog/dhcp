/*
 *
 *  Erlang ioctl wrapper to inject ARP entries to kernel
 *
 *  Copyright (c) 2011-2012 by Travelping GmbH <info@travelping.com>
 *  Copyright (C) <year>  <name of author>
 *
 *  This program is free software; you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation; either version 2 of the License, or
 *  (at your option) any later version.
 *
 *  This program is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License
 *  along with this program; if not, write to the Free Software
 *  Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA
 *
 */

#include <errno.h>
#include <string.h>
#include <sys/ioctl.h>
#include <arpa/inet.h>
#include <net/if.h>
#include <net/if_arp.h>
#include <netinet/in.h>

#include <erl_nif.h>
#include "erl_driver.h" // for erl_errno_id

static ERL_NIF_TERM atom_error;
static ERL_NIF_TERM atom_ok;

static ERL_NIF_TERM arp_inject_nif(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[])
{
	struct arpreq arp;
	struct sockaddr_in *in;

	ErlNifBinary ip;
	int htype;
	ErlNifBinary addr;
	ErlNifBinary ifname;
	int fd;

	if (!enif_inspect_binary(env, argv[0], &ifname)
	    || ifname.size > 16
	    || !enif_inspect_binary(env, argv[1], &ip)
	    || ip.size != 4
	    || !enif_get_int(env, argv[2], &htype)
	    || !enif_inspect_binary(env, argv[3], &addr)
	    || addr.size > 16
	    || !enif_get_int(env, argv[4], &fd))
		return enif_make_badarg(env);

	memset(&arp, 0, sizeof(arp));
	in = (struct sockaddr_in *)&arp.arp_pa;
	in->sin_family = AF_INET;
	memcpy(&in->sin_addr.s_addr, ip.data, 4);

	arp.arp_ha.sa_family = htype;
	memcpy(arp.arp_ha.sa_data, addr.data, addr.size);
	memcpy(arp.arp_dev, ifname.data, ifname.size);
	arp.arp_flags = ATF_COM;

	if (ioctl(fd, SIOCSARP, &arp) < 0) {
		return enif_make_tuple2(env, atom_error, enif_make_atom(env, erl_errno_id(errno)));
	}

	return atom_ok;
}

static ErlNifFunc nif_funcs[] = {
	{"arp_inject_nif", 5, arp_inject_nif}
};

static int load(ErlNifEnv* env, void** priv_data, ERL_NIF_TERM load_info)
{
	atom_error = enif_make_atom(env,"error");
	atom_ok = enif_make_atom(env,"ok");

	return 0;
}

ERL_NIF_INIT(dhcp_server, nif_funcs, load, NULL, NULL, NULL)
