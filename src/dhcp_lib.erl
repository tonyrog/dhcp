%%%-------------------------------------------------------------------
%%% File    : dhcp_lib.erl
%%% Author  : Ruslan Babayev <ruslan@babayev.com>
%%% Description : 
%%%
%%% Created : 17 Apr 2006 by Ruslan Babayev <ruslan@babayev.com>
%%%-------------------------------------------------------------------
-module(dhcp_lib).

%% API
-export([decode/1, encode/1]).
-import(lists, [keymember/3, keysearch/3, keyreplace/4]).
-include("dhcp.hrl").

%%====================================================================
%% API
%%====================================================================
%%--------------------------------------------------------------------
%% Function: 
%% Description:
%%--------------------------------------------------------------------
decode(<<Op, Htype, Hlen, Hops,  Xid:32, Secs:16, Flags:16,
	Ciaddr:4/binary, Yiaddr:4/binary, Siaddr:4/binary, Giaddr:4/binary,
	Chaddr:6/binary, _:10/binary, Sname:64/binary, File:128/binary,
	Options/binary>>) ->
    OptsList = case Options of
		   <<99, 130, 83, 99, Opts/binary>> ->
		       binary_to_options(Opts);
		   _ -> %% return empty list if the MAGIC is not there
		       []
	       end,
    #dhcp{op      = Op,
	  htype   = Htype,
	  hlen    = Hlen,
	  hops    = Hops,
	  xid     = Xid,
	  secs    = Secs,
	  flags   = Flags,
	  ciaddr  = binary_to_ip(Ciaddr),
	  yiaddr  = binary_to_ip(Yiaddr),
	  siaddr  = binary_to_ip(Siaddr),
	  giaddr  = binary_to_ip(Giaddr),
	  chaddr  = binary_to_eth(Chaddr),
	  sname   = binary_to_list(Sname),
	  file    = binary_to_list(File),
	  options = OptsList}.

encode(D) when record(D, dhcp) ->
    Op      = D#dhcp.op,
    Htype   = D#dhcp.htype,
    Hlen    = D#dhcp.hlen,
    Hops    = D#dhcp.hops,
    Xid     = D#dhcp.xid,
    Secs    = D#dhcp.secs,
    Flags   = D#dhcp.flags,
    Ciaddr  = ip_to_binary(D#dhcp.ciaddr),
    Yiaddr  = ip_to_binary(D#dhcp.yiaddr),
    Siaddr  = ip_to_binary(D#dhcp.siaddr),
    Giaddr  = ip_to_binary(D#dhcp.giaddr),
    Chaddr  = pad(eth_to_binary(D#dhcp.chaddr), 16),
    Sname   = pad(list_to_binary(D#dhcp.sname), 64),
    File    = pad(list_to_binary(D#dhcp.file), 128),
    Opts    = options_to_binary(D#dhcp.options),
    <<Op, Htype, Hlen, Hops, Xid:32, Secs:16, Flags:16,
     Ciaddr/binary, Yiaddr/binary, Siaddr/binary, Giaddr/binary,
     Chaddr/binary, Sname/binary, File/binary, Opts/binary>>.

%%====================================================================
%% Internal functions
%%====================================================================
binary_to_ip(<<A, B, C, D>>) ->
    {A, B, C, D}.

eth_to_binary({A, B, C, D, E, F}) ->
    <<A, B, C, D, E, F>>.

binary_to_eth(<<A, B, C, D, E, F>>) ->
    {A, B, C, D, E, F}.

binary_to_iplist(<<A, B, C, D, T/binary>>) ->
    [{A, B, C, D} | binary_to_iplist(T)];
binary_to_iplist(<<>>) ->
    [].

binary_to_shortlist(<<H:16, T/binary>>) ->
    [H | binary_to_shortlist(T)];
binary_to_shortlist(<<>>) ->
    [].

ip_to_binary({A, B, C, D}) ->
    <<A, B, C, D>>.

pad(X, Size) when binary(X) ->
    Len  = size(X),
    Plen = Size - Len,
    <<X/binary, 0:Plen/integer-unit:8>>.

binary_to_options(Binary) ->
    binary_to_options(Binary, []).

binary_to_options(<<?DHO_END, _/binary>>, Acc) ->
    Acc;
binary_to_options(<<Tag, Rest/binary>>, Acc) ->
    Value = case type(Tag) of
		byte ->
		    <<1, Byte, T/binary>> = Rest,
		    Byte;
		short ->
		    <<2, Short:16, T/binary>> = Rest,
		    Short;
		shortlist ->
		    <<N, Binary:N/binary, T/binary>> = Rest,
		    binary_to_shortlist(Binary);
		integer ->
		    <<4, Integer:32, T/binary>> = Rest,
		    Integer;
		string ->
		    <<N, String:N/binary, T/binary>> = Rest,
		    binary_to_list(String);
		ip ->
		    <<4, A, B, C, D, T/binary>> = Rest,
		    {A, B, C, D};
		iplist ->
		    <<N, Binary:N/binary, T/binary>> = Rest,
		    binary_to_iplist(Binary);
		vendor ->
		    <<N, Binary:N/binary, T/binary>> = Rest,
		    binary_to_options(Binary);
		unknown ->
		    <<N, Binary:N/binary, T/binary>> = Rest,
		    Binary
	    end,
    binary_to_options(T, [{Tag, Value} | Acc]).

options_to_binary(Options) ->
    L = [<<(option_to_binary(Tag, Val))/binary>> || {Tag, Val} <- Options],
    list_to_binary(?DHCP_OPTIONS_COOKIE ++ L ++ [?DHO_END]).
   
option_to_binary(Tag, Val) ->
    case type(Tag) of
	byte ->
	    <<Tag, 1, Val>>;
	short ->
	    <<Tag, 2, Val:16/big>>;
	shortlist ->
	    B = list_to_binary([<<S:16/big>> || S <- Val]),
	    <<Tag, (size(B)), B/binary>>;
	integer ->
	    <<Tag, 4, Val:32/big>>;
	string ->
	    B = list_to_binary(Val),
	    <<Tag, (size(B)), B/binary>>;
	ip ->
	    <<Tag, 4, (ip_to_binary(Val))/binary>>;
	iplist ->
	    B = list_to_binary([ip_to_binary(IP) || IP <- Val]),
	    <<Tag, (size(B)), B/binary>>;
	vendor ->
	    B = list_to_binary([<<T, (size(V)), V/binary>> || {T, V} <- Val]),
	    <<Tag, (size(B)), B/binary>>
    end.

%%% DHCP Option types
type(?DHO_SUBNET_MASK)                 -> ip;
type(?DHO_TIME_OFFSET)                 -> integer;
type(?DHO_ROUTERS)                     -> iplist;
type(?DHO_TIME_SERVERS)                -> iplist;
type(?DHO_NAME_SERVERS)                -> iplist;
type(?DHO_DOMAIN_NAME_SERVERS)         -> iplist;
type(?DHO_LOG_SERVERS)                 -> iplist;
type(?DHO_COOKIE_SERVERS)              -> iplist;
type(?DHO_LPR_SERVERS)                 -> iplist;
type(?DHO_IMPRESS_SERVERS)             -> iplist;
type(?DHO_RESOURCE_LOCATION_SERVERS)   -> iplist;
type(?DHO_HOST_NAME)                   -> string;
type(?DHO_BOOT_SIZE)                   -> short;
type(?DHO_MERIT_DUMP)                  -> string;
type(?DHO_DOMAIN_NAME)                 -> string;
type(?DHO_SWAP_SERVER)                 -> ip;
type(?DHO_ROOT_PATH)                   -> string;
type(?DHO_EXTENSIONS_PATH)             -> string;
type(?DHO_IP_FORWARDING)               -> byte;
type(?DHO_NON_LOCAL_SOURCE_ROUTING)    -> byte;
type(?DHO_POLICY_FILTER)               -> iplist;
type(?DHO_MAX_DGRAM_REASSEMBLY)        -> short;
type(?DHO_DEFAULT_IP_TTL)              -> byte;
type(?DHO_PATH_MTU_AGING_TIMEOUT)      -> integer;
type(?DHO_PATH_MTU_PLATEAU_TABLE)      -> integer;
type(?DHO_INTERFACE_MTU)               -> short;
type(?DHO_ALL_SUBNETS_LOCAL)           -> byte;
type(?DHO_BROADCAST_ADDRESS)           -> ip;
type(?DHO_PERFORM_MASK_DISCOVERY)      -> byte;
type(?DHO_MASK_SUPPLIER)               -> byte;
type(?DHO_ROUTER_DISCOVERY)            -> byte;
type(?DHO_ROUTER_SOLICITATION_ADDRESS) -> ip;
type(?DHO_STATIC_ROUTES)               -> iplist;
type(?DHO_TRAILER_ENCAPSULATION)       -> byte;
type(?DHO_ARP_CACHE_TIMEOUT)           -> integer;
type(?DHO_IEEE802_3_ENCAPSULATION)     -> byte;
type(?DHO_DEFAULT_TCP_TTL)             -> byte;
type(?DHO_TCP_KEEPALIVE_INTERVAL)      -> integer;
type(?DHO_TCP_KEEPALIVE_GARBAGE)       -> byte;
type(?DHO_NIS_DOMAIN)                  -> string;
type(?DHO_NIS_SERVERS)                 -> iplist;
type(?DHO_NTP_SERVERS)                 -> iplist;
type(?DHO_VENDOR_ENCAPSULATED_OPTIONS) -> vendor;
type(?DHO_NETBIOS_NAME_SERVERS)        -> iplist;
type(?DHO_NETBIOS_DD_SERVERS)          -> iplist;
type(?DHO_NETBIOS_NODE_TYPE)           -> byte;
type(?DHO_NETBIOS_SCOPE)               -> string;
type(?DHO_FONT_SERVERS)                -> iplist;
type(?DHO_X_DISPLAY_MANAGERS)          -> iplist;
type(?DHO_DHCP_REQUESTED_ADDRESS)      -> ip;
type(?DHO_DHCP_LEASE_TIME)             -> integer;
type(?DHO_DHCP_OPTION_OVERLOAD)        -> byte;
type(?DHO_DHCP_MESSAGE_TYPE)           -> byte;
type(?DHO_DHCP_SERVER_IDENTIFIER)      -> ip;
type(?DHO_DHCP_PARAMETER_REQUEST_LIST) -> string;
type(?DHO_DHCP_MESSAGE)                -> string;
type(?DHO_DHCP_MAX_MESSAGE_SIZE)       -> short;
type(?DHO_DHCP_RENEWAL_TIME)           -> integer;
type(?DHO_DHCP_REBINDING_TIME)         -> integer;
type(?DHO_VENDOR_CLASS_IDENTIFIER)     -> string;
type(?DHO_DHCP_CLIENT_IDENTIFIER)      -> string;
type(?DHO_NWIP_DOMAIN_NAME)            -> string;
type(?DHO_NIS_PLUS_DOMAIN)             -> string;
type(?DHO_NIS_PLUS_SERVERS)            -> iplist;
type(?DHO_MOBILE_IP_HOME_AGENTS)       -> iplist;
type(?DHO_SMTP_SERVERS)                -> iplist;
type(?DHO_POP3_SERVERS)                -> iplist;
type(?DHO_WWW_SERVERS)                 -> iplist;
type(?DHO_FINGER_SERVERS)              -> iplist;
type(?DHO_IRC_SERVERS)                 -> iplist;
type(?DHO_STREETTALK_SERVERS)          -> iplist;
type(?DHO_STDA_SERVERS)                -> iplist;
type(?DHO_USER_CLASS)                  -> string;
type(?DHO_FQDN)                        -> string;
type(?DHO_DHCP_AGENT_OPTIONS)          -> string;
type(?DHO_NDS_SERVERS)                 -> iplist;
type(?DHO_NDS_TREE_NAME)               -> string;
type(?DHO_NDS_CONTEXT)                 -> string;
type(?DHO_UAP)                         -> string;
type(?DHO_AUTO_CONFIGURE)              -> byte;
type(?DHO_NAME_SERVICE_SEARCH)         -> shortlist;
type(?DHO_SUBNET_SELECTION)            -> ip;
type(_)                                -> unknown.
