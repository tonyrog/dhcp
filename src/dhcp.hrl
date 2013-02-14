-ifndef(_DHCP).
-define(_DHCP, true).

%%% BOOTP (rfc951) message types
-define(BOOTREQUEST, 1).
-define(BOOTREPLY,   2).

%%% Possible values for flags field
-define(BOOTP_BROADCAST, 16#8000).

%%% Possible values for hardware type (htype) field
-define(HTYPE_ETHER,   1).    %% Ethernet 10Mbps
-define(HTYPE_IEEE802, 6).    %% IEEE 802.2 Token Ring
-define(HTYPE_FDDI,    8).    %% FDDI

%%% Magic cookie validating dhcp options and bootp vendor extensions field
-define(DHCP_OPTIONS_COOKIE, [99, 130, 83, 99]).

-record(dhcp, {
	  op,                       %% Message opcode
	  htype   = ?HTYPE_ETHER,   %% Hardware addr type
	  hlen    = 6,              %% Hardware addr length
	  hops    = 0,              %% Number of relay agent hops from client
	  xid     = 0,              %% Transaction ID
	  secs    = 0,              %% Seconds since client started looking
	  flags   = 0,              %% Flag bits
	  ciaddr  = {0,0,0,0},      %% Client IP address (if already in use)
	  yiaddr  = {0,0,0,0},      %% Client IP address
	  siaddr  = {0,0,0,0},      %% IP address of next server to talk to
	  giaddr  = {0,0,0,0},      %% DHCP relay agent IP address
	  chaddr  = {0,0,0,0,0,0},  %% Client hardware address
	  sname   = [],             %% Server name
	  file    = [],             %% Boot filename
	  options = []              %% Optional parameters
	 }).

%%% DHCP Option codes
-define(DHO_PAD,                          0).
-define(DHO_SUBNET_MASK,                  1).
-define(DHO_TIME_OFFSET,                  2).
-define(DHO_ROUTERS,                      3).
-define(DHO_TIME_SERVERS,                 4).
-define(DHO_NAME_SERVERS,                 5).
-define(DHO_DOMAIN_NAME_SERVERS,          6).
-define(DHO_LOG_SERVERS,                  7).
-define(DHO_COOKIE_SERVERS,               8).
-define(DHO_LPR_SERVERS,                  9).
-define(DHO_IMPRESS_SERVERS,             10).
-define(DHO_RESOURCE_LOCATION_SERVERS,   11).
-define(DHO_HOST_NAME,                   12).
-define(DHO_BOOT_SIZE,                   13).
-define(DHO_MERIT_DUMP,                  14).
-define(DHO_DOMAIN_NAME,                 15).
-define(DHO_SWAP_SERVER,                 16).
-define(DHO_ROOT_PATH,                   17).
-define(DHO_EXTENSIONS_PATH,             18).
-define(DHO_IP_FORWARDING,               19).
-define(DHO_NON_LOCAL_SOURCE_ROUTING,    20).
-define(DHO_POLICY_FILTER,               21).
-define(DHO_MAX_DGRAM_REASSEMBLY,        22).
-define(DHO_DEFAULT_IP_TTL,              23).
-define(DHO_PATH_MTU_AGING_TIMEOUT,      24).
-define(DHO_PATH_MTU_PLATEAU_TABLE,      25).
-define(DHO_INTERFACE_MTU,               26).
-define(DHO_ALL_SUBNETS_LOCAL,           27).
-define(DHO_BROADCAST_ADDRESS,           28).
-define(DHO_PERFORM_MASK_DISCOVERY,      29).
-define(DHO_MASK_SUPPLIER,               30).
-define(DHO_ROUTER_DISCOVERY,            31).
-define(DHO_ROUTER_SOLICITATION_ADDRESS, 32).
-define(DHO_STATIC_ROUTES,               33).
-define(DHO_TRAILER_ENCAPSULATION,       34).
-define(DHO_ARP_CACHE_TIMEOUT,           35).
-define(DHO_IEEE802_3_ENCAPSULATION,     36).
-define(DHO_DEFAULT_TCP_TTL,             37).
-define(DHO_TCP_KEEPALIVE_INTERVAL,      38).
-define(DHO_TCP_KEEPALIVE_GARBAGE,       39).
-define(DHO_NIS_DOMAIN,                  40).
-define(DHO_NIS_SERVERS,                 41).
-define(DHO_NTP_SERVERS,                 42).
-define(DHO_VENDOR_ENCAPSULATED_OPTIONS, 43).
-define(DHO_NETBIOS_NAME_SERVERS,        44).
-define(DHO_NETBIOS_DD_SERVERS,          45).
-define(DHO_NETBIOS_NODE_TYPE,           46).
-define(DHO_NETBIOS_SCOPE,               47).
-define(DHO_FONT_SERVERS,                48).
-define(DHO_X_DISPLAY_MANAGERS,          49).
-define(DHO_DHCP_REQUESTED_ADDRESS,      50).
-define(DHO_DHCP_LEASE_TIME,             51).
-define(DHO_DHCP_OPTION_OVERLOAD,        52).
-define(DHO_DHCP_MESSAGE_TYPE,           53).
-define(DHO_DHCP_SERVER_IDENTIFIER,      54).
-define(DHO_DHCP_PARAMETER_REQUEST_LIST, 55).
-define(DHO_DHCP_MESSAGE,                56).
-define(DHO_DHCP_MAX_MESSAGE_SIZE,       57).
-define(DHO_DHCP_RENEWAL_TIME,           58).
-define(DHO_DHCP_REBINDING_TIME,         59).
-define(DHO_VENDOR_CLASS_IDENTIFIER,     60).
-define(DHO_DHCP_CLIENT_IDENTIFIER,      61).
-define(DHO_NWIP_DOMAIN_NAME,            62).
-define(DHO_NWIP_SUBOPTIONS,             63).
-define(DHO_NIS_PLUS_DOMAIN,             64).
-define(DHO_NIS_PLUS_SERVERS,            65).
-define(DHO_MOBILE_IP_HOME_AGENTS,       68).
-define(DHO_SMTP_SERVERS,                69).
-define(DHO_POP3_SERVERS,                70).
-define(DHO_NNTP_SERVERS,                71).
-define(DHO_WWW_SERVERS,                 72).
-define(DHO_FINGER_SERVERS,              73).
-define(DHO_IRC_SERVERS,                 74).
-define(DHO_STREETTALK_SERVERS,          75).
-define(DHO_STDA_SERVERS,                76).
-define(DHO_USER_CLASS,                  77). %% rfc3004
-define(DHO_FQDN,                        81). %% draft-ietf-dhc-fqdn-option-10
-define(DHO_DHCP_AGENT_OPTIONS,          82). %% rfc3046
-define(DHO_NDS_SERVERS,                 85). %% rfc2241
-define(DHO_NDS_TREE_NAME,               86). %% rfc2241
-define(DHO_NDS_CONTEXT,                 87). %% rfc2241
-define(DHO_UAP,                         98). %% rfc2485
-define(DHO_AUTO_CONFIGURE,             116). %% rfc2563
-define(DHO_NAME_SERVICE_SEARCH,        117). %% rfc2937
-define(DHO_SUBNET_SELECTION,           118). %% rfc3011
-define(DHO_END,                        255).

%%% DHCP Message types
-define(DHCPDISCOVER, 1).
-define(DHCPOFFER,    2).
-define(DHCPREQUEST,  3).
-define(DHCPDECLINE,  4).
-define(DHCPACK,      5).
-define(DHCPNAK,      6).
-define(DHCPRELEASE,  7).
-define(DHCPINFORM,   8).

%%% Relay Agent Information option subtypes
-define(RAI_CIRCUIT_ID, 1).
-define(RAI_REMOTE_ID,  2).
-define(RAI_AGENT_ID,   3).

%%% FQDN suboptions
-define(FQDN_NO_CLIENT_UPDATE, 1).
-define(FQDN_SERVER_UPDATE,    2).
-define(FQDN_ENCODED,          3).
-define(FQDN_RCODE1,           4).
-define(FQDN_RCODE2,           5).
-define(FQDN_HOSTNAME,         6).
-define(FQDN_DOMAINNAME,       7).
-define(FQDN_FQDN,             8).
-define(FQDN_SUBOPTION_COUNT,  8).

-endif.
