%%%-------------------------------------------------------------------
%%% File    : dhcp_server.erl
%%% Author  : Ruslan Babayev <ruslan@babayev.com>
%%% Description : DHCP server
%%%
%%% Created : 20 Sep 2006 by Ruslan Babayev <ruslan@babayev.com>
%%%-------------------------------------------------------------------
-module(dhcp_server).

-behaviour(gen_server).

%% API
-export([start_link/3]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
	 terminate/2, code_change/3]).

-include("dhcp.hrl").

-define(SERVER, ?MODULE).
-define(DHCP_SERVER_PORT, 67).
-define(DHCP_CLIENT_PORT, 68).

-record(state, {socket, server_id, next_server}).

%%====================================================================
%% API
%%====================================================================
%%--------------------------------------------------------------------
%% Function: start_link() -> {ok,Pid} | ignore | {error,Error}
%% Description: Starts the server
%%--------------------------------------------------------------------
start_link(ServerId, NextServer, LogFile) ->
    gen_server:start_link({local, ?SERVER}, ?MODULE,
			  [ServerId, NextServer, LogFile], []).

%%====================================================================
%% gen_server callbacks
%%====================================================================

%%--------------------------------------------------------------------
%% Function: init(Args) -> {ok, State} |
%%                         {ok, State, Timeout} |
%%                         ignore               |
%%                         {stop, Reason}
%% Description: Initiates the server
%%--------------------------------------------------------------------
init([ServerId, NextServer, LogFile]) ->
    error_logger:logfile({open, LogFile}),
    Options = get_sockopt(),
    case gen_udp:open(?DHCP_SERVER_PORT, Options) of
	{ok, Socket} ->
	    error_logger:info_msg("Starting DHCP server..."),
	    {ok, #state{socket = Socket,
			server_id = ServerId,
			next_server = NextServer}};
	{error, Reason} ->
	    error_logger:error_msg("Cannot open udp port ~w",
				   [?DHCP_SERVER_PORT]),
	    {stop, Reason}
    end.

%%--------------------------------------------------------------------
%% Function: %% handle_call(Request, From, State) -> {reply, Reply, State} |
%%                                      {reply, Reply, State, Timeout} |
%%                                      {noreply, State} |
%%                                      {noreply, State, Timeout} |
%%                                      {stop, Reason, Reply, State} |
%%                                      {stop, Reason, State}
%% Description: Handling call messages
%%--------------------------------------------------------------------
handle_call(_Request, _From, State) ->
    Reply = ok,
    {reply, Reply, State}.

%%--------------------------------------------------------------------
%% Function: handle_cast(Msg, State) -> {noreply, State} |
%%                                      {noreply, State, Timeout} |
%%                                      {stop, Reason, State}
%% Description: Handling cast messages
%%--------------------------------------------------------------------
handle_cast(_Msg, State) ->
    {noreply, State}.

%%--------------------------------------------------------------------
%% Function: handle_info(Info, State) -> {noreply, State} |
%%                                       {noreply, State, Timeout} |
%%                                       {stop, Reason, State}
%% Description: Handling all non call/cast messages
%%--------------------------------------------------------------------
handle_info({udp, Socket, _IP, _Port, Packet}, State) ->
    DHCP = dhcp_lib:decode(Packet),
    case optsearch(?DHO_DHCP_MESSAGE_TYPE, DHCP) of
	{value, MsgType} ->
	    handle_dhcp(MsgType, DHCP, Socket, State);
	false ->
	    ok
    end,
    {noreply, State};
handle_info(_Info, State) ->
    {noreply, State}.

%%--------------------------------------------------------------------
%% Function: terminate(Reason, State) -> void()
%% Description: This function is called by a gen_server when it is about to
%% terminate. It should be the opposite of Module:init/1 and do any necessary
%% cleaning up. When it returns, the gen_server terminates with Reason.
%% The return value is ignored.
%%--------------------------------------------------------------------
terminate(_Reason, State) ->
    error_logger:logfile(close),
    gen_udp:close(State#state.socket),
    ok.

%%--------------------------------------------------------------------
%% Func: code_change(OldVsn, State, Extra) -> {ok, NewState}
%% Description: Convert process state when code is changed
%%--------------------------------------------------------------------
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%--------------------------------------------------------------------
%%% Internal functions
%%--------------------------------------------------------------------

%%%-------------------------------------------------------------------
%%% The DHCP message handler
%%%-------------------------------------------------------------------
handle_dhcp(?DHCPDISCOVER, D, Socket, State) ->
    error_logger:info_msg("DHCPDISCOVER from ~s ~s ~s",
			  [fmt_clientid(D), fmt_hostname(D), fmt_gateway(D)]),
    ClientId = get_client_id(D),
    Gateway = D#dhcp.giaddr,
    RequestedIP = get_requested_ip(D),
    case dhcp_alloc:reserve(ClientId, Gateway, RequestedIP) of
	{ok, IP, Options} ->
	    send_offer(State, Socket, D, IP, Options);
	{error, Reason} ->
	    error_logger:error_msg(Reason)
    end;
handle_dhcp(?DHCPREQUEST, D, Socket, State) ->
    ClientId = get_client_id(D),
    error_logger:info_msg("DHCPREQUEST from ~s ~s ~s",
			  [fmt_clientid(D), fmt_hostname(D), fmt_gateway(D)]),
    case client_state(D) of
	{selecting, ServerId} ->
	    case {ServerId, State#state.server_id} of
		{X, X} ->
		    IP = get_requested_ip(D),
		    case dhcp_alloc:allocate(ClientId, IP) of
			{ok, IP, Options} ->
			    send_ack(State, Socket, D, IP, Options);
			{error, Reason} ->
			    error_logger:error_msg(Reason)
		    end;
		_ ->
		    %% Client selected someone else, do nothing
		    ok
	    end;
	{init_reboot, RequestedIP} ->
	    Gateway = D#dhcp.giaddr,
	    case dhcp_alloc:verify(ClientId, Gateway, RequestedIP) of
		{ok, IP, Options} ->
		    send_ack(State, Socket, D, IP, Options);
		noclient ->
		    error_logger:error_msg("Client ~s has no current bindings",
					   [fmt_clientid(D)]);
		{error, Reason} ->
		    send_nak(State, Socket, D, Reason)
	    end;
	{ClientIs, IP} when ClientIs == renewing; ClientIs == rebinding ->
	    case dhcp_alloc:extend(ClientId, IP) of
		{ok, IP, Options} ->
		    send_ack(State, Socket, D, IP, Options);
		{error, Reason} ->
		    send_nak(State, Socket, D, Reason)
	    end
    end;
handle_dhcp(?DHCPDECLINE, D, _Socket, _State) ->
    IP = get_requested_ip(D),
    error_logger:info_msg("DHCPDECLINE of ~s from ~s ~s",
			  [fmt_ip(IP), fmt_clientid(D), fmt_hostname(D)]),
    dhcp_alloc:decline(IP);
handle_dhcp(?DHCPRELEASE, D, _Socket, _State) ->
    ClientId = get_client_id(D),
    error_logger:info_msg("DHCPRELEASE of ~s from ~s ~s ~s",
			  [fmt_ip(D#dhcp.ciaddr), fmt_clientid(D),
			   fmt_hostname(D), fmt_gateway(D)]),
    dhcp_alloc:release(ClientId, D#dhcp.ciaddr);
handle_dhcp(?DHCPINFORM, D, Socket, State) ->
    Gateway = D#dhcp.giaddr,
    IP = D#dhcp.ciaddr,
    error_logger:info_msg("DHCPINFORM from ~s", [fmt_ip(IP)]), 
    case dhcp_alloc:local_conf(Gateway) of
	{ok, Opts} ->
	    %% No Lease Time (RFC2131 sec. 4.3.5)
	    OptsSansLease = lists:keydelete(?DHO_DHCP_LEASE_TIME, 1, Opts),
	    send_ack(State, Socket, D, IP, OptsSansLease);
	{error, Reason} ->
	    error_logger:error_msg(Reason)
    end;
handle_dhcp(MsgType, _D, _Socket, _State) ->
    error_logger:error_msg("Invalid DHCP message type ~p", [MsgType]).

client_state(D) when record(D, dhcp) ->
    case optsearch(?DHO_DHCP_SERVER_IDENTIFIER, D) of
	{value, ServerId} ->
	    {selecting, ServerId};
	false ->
	    case optsearch(?DHO_DHCP_REQUESTED_ADDRESS, D) of
		{value, RequestedIP} ->
		    {init_reboot, RequestedIP};
		false ->
		    case is_broadcast(D) of
			false ->
			    {renewing, D#dhcp.ciaddr};
			_ ->
			    {rebinding, D#dhcp.ciaddr}
		    end
	    end
    end.

send_offer(S, Socket, D, IP, Options) ->
    DHCPOffer = D#dhcp{
		  op = ?BOOTREPLY,
		  hops = 0,
		  secs = 0,
		  ciaddr = {0, 0, 0, 0},
		  yiaddr = IP,
		  siaddr = S#state.next_server,
		  options = [{?DHO_DHCP_MESSAGE_TYPE, ?DHCPOFFER},
			     {?DHO_DHCP_SERVER_IDENTIFIER, S#state.server_id} |
			     Options]},
    error_logger:info_msg("DHCPOFFER on ~s to ~s ~s ~s",
			  [fmt_ip(IP), fmt_clientid(D),
			   fmt_hostname(D), fmt_gateway(D)]),
    {IP, Port} = get_dest(DHCPOffer),
    gen_udp:send(Socket, IP, Port, dhcp_lib:encode(DHCPOffer)).  

send_ack(S, Socket, D, IP, Options) ->
    DHCPAck = D#dhcp{
		op = ?BOOTREPLY,
		hops = 0,
		secs = 0,
		yiaddr = IP,
		siaddr = S#state.next_server,
		options = [{?DHO_DHCP_MESSAGE_TYPE, ?DHCPACK},
			   {?DHO_DHCP_SERVER_IDENTIFIER, S#state.server_id} |
			   Options]},
    error_logger:info_msg("DHCPACK on ~s to ~s ~s ~s",
			  [fmt_ip(IP), fmt_clientid(D),
			   fmt_hostname(D), fmt_gateway(D)]),
    {IP, Port} = get_dest(DHCPAck),
    gen_udp:send(Socket, IP, Port, dhcp_lib:encode(DHCPAck)).

send_nak(S, Socket, D, Reason) ->
    DHCPNak = D#dhcp{
		op = ?BOOTREPLY,
		hops = 0,
		secs = 0,
		ciaddr = {0, 0, 0, 0},
		yiaddr = {0, 0, 0, 0},
		siaddr = {0, 0, 0, 0},
		flags = D#dhcp.flags bor 16#8000, %% set broadcast bit
		options = [{?DHO_DHCP_MESSAGE_TYPE, ?DHCPNAK},
			   {?DHO_DHCP_SERVER_IDENTIFIER, S#state.server_id},
			   {?DHO_DHCP_MESSAGE, Reason}]},
    error_logger:info_msg("DHCPNAK to ~s ~s ~s. ~s",
			  [fmt_clientid(D), fmt_hostname(D),
			   fmt_gateway(D), Reason]),
    {IP, Port} = get_dest(D),
    gen_udp:send(Socket, IP, Port, dhcp_lib:encode(DHCPNak)).

%%% Behaviour is described in RFC2131 sec. 4.1
get_dest(D) when record(D, dhcp) ->
    IP = case D#dhcp.giaddr of
	     {0, 0, 0, 0} ->
		 case D#dhcp.ciaddr of
		     {0, 0, 0, 0} ->
			 case is_broadcast(D) of
			     true -> {255, 255, 255, 255};
			     _    -> D#dhcp.yiaddr
			 end;
		     CiAddr -> CiAddr
		 end;
	     GiAddr -> GiAddr
	 end,
    Port = case D#dhcp.giaddr of
	       {0, 0, 0, 0} -> ?DHCP_CLIENT_PORT;
	       _            -> ?DHCP_SERVER_PORT
	   end,
    {IP, Port}.

is_broadcast(D) when record(D, dhcp) ->
    (D#dhcp.flags bsr 15) == 1.

optsearch(Option, D) when record(D, dhcp) ->
    case lists:keysearch(Option, 1, D#dhcp.options) of
	{value, {Option, Value}} ->
	    {value, Value};
	false ->
	    false
    end.
    
get_client_id(D) when record(D, dhcp) ->
    case optsearch(?DHO_DHCP_CLIENT_IDENTIFIER, D) of
        {value, ClientId} ->
	    ClientId;
	false ->
	    D#dhcp.chaddr
    end.

get_requested_ip(D) when record(D, dhcp) ->
    case optsearch(?DHO_DHCP_REQUESTED_ADDRESS, D) of
        {value, IP} ->
	    IP;
	false ->
	    {0, 0, 0, 0}
    end.

fmt_clientid(D) when record(D, dhcp) ->
    fmt_clientid(get_client_id(D));
fmt_clientid([_T, E1, E2, E3, E4, E5, E6]) ->
    fmt_clientid({E1, E2, E3, E4, E5, E6});
fmt_clientid({E1, E2, E3, E4, E5, E6}) ->
    lists:flatten(
      io_lib:format("~2.16.0b:~2.16.0b:~2.16.0b:~2.16.0b:~2.16.0b:~2.16.0b",
	     [E1, E2, E3, E4, E5, E6])).

fmt_gateway(D) when record(D, dhcp) ->
    case D#dhcp.giaddr of
	{0, 0, 0, 0} -> [];
	IP           -> lists:flatten(io_lib:format("via ~s", [fmt_ip(IP)]))
    end.

fmt_hostname(D) when record(D, dhcp) ->
    case optsearch(?DHO_HOST_NAME, D) of
        {value, Hostname} ->
            lists:flatten(io_lib:format("(~s)", [Hostname]));
	false ->
	    []
    end.

fmt_ip({A1, A2, A3, A4}) ->
    io_lib:format("~w.~w.~w.~w", [A1, A2, A3, A4]).

get_sockopt() ->
    case init:get_argument(fd) of
	{ok, [[FD]]} ->
	    [binary, {broadcast, true}, {fd, list_to_integer(FD)}];
	error ->
	    [binary, {broadcast, true}]
    end.
