%%%-------------------------------------------------------------------
%%% File    : dhcp_alloc.erl
%%% Author  : Ruslan Babayev <ruslan@babayev.com>
%%% Description : The allocation module of the DHCP server
%%%
%%% Created : 20 Sep 2006 by Ruslan Babayev <ruslan@babayev.com>
%%%-------------------------------------------------------------------
-module(dhcp_alloc).

-behaviour(gen_server).

%% API
-export([start_link/3, reserve/3, allocate/2, release/2, verify/3,
	 extend/2, decline/2, local_conf/1]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
	 terminate/2, code_change/3]).

-include("dhcp.hrl").
-include("dhcp_alloc.hrl").

-define(SERVER, ?MODULE).
-define(ADDRESS, dhcp_address).
-define(LEASE, dhcp_lease).

-define(DHCPOFFER_TIMEOUT, 3*60*1000).

-define(IS_ALLOCATED(A), A#address.status == allocated). 
-define(IS_OFFERED(A), A#address.status == offered). 
-define(IS_AVAILABLE(A), A#address.status == available). 
-define(IS_DECLINED(A), A#address.status == declined).

-define(IS_NOT_EXPIRED(L, Now), L#lease.expires > Now).

-record(state, {subnets, hosts}).

%%====================================================================
%% API
%%====================================================================
%%--------------------------------------------------------------------
%% Function: start_link() -> {ok,Pid} | ignore | {error,Error}
%% Description: Starts the server
%%--------------------------------------------------------------------
start_link(LeaseFile, Subnets, Hosts) ->
    gen_server:start_link({local, ?SERVER}, ?MODULE,
			  [LeaseFile, Subnets, Hosts], []).

reserve(ClientId, Gateway, IP) ->
    gen_server:call(?SERVER, {reserve, ClientId, Gateway, IP}).

allocate(ClientId, IP) ->
    gen_server:call(?SERVER, {allocate, ClientId, IP}).

release(ClientId, IP) ->
    gen_server:call(?SERVER, {release, ClientId, IP}).

verify(ClientId, Gateway, IP) ->
    gen_server:call(?SERVER, {verify, ClientId, Gateway, IP}).

extend(ClientId, IP) ->
    gen_server:call(?SERVER, {extend, ClientId, IP}).
    
local_conf(Gateway) ->
    gen_server:call(?SERVER, {local_conf, Gateway}).

decline(ClientId, IP) ->    
    gen_server:call(?SERVER, {decline, ClientId, IP}).

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
init([LeaseFile, Subnets, Hosts]) ->
    ets:new(?ADDRESS, [named_table, public, {keypos, #address.ip}]),
    dets:open_file(?LEASE, [{keypos, #lease.clientid}, {file, LeaseFile}]),
    lists:foreach(fun init_subnet/1, Subnets),
    {ok, #state{subnets = Subnets, hosts = Hosts}}.

%%--------------------------------------------------------------------
%% Function: %% handle_call(Request, From, State) -> {reply, Reply, State} |
%%                                      {reply, Reply, State, Timeout} |
%%                                      {noreply, State} |
%%                                      {noreply, State, Timeout} |
%%                                      {stop, Reason, Reply, State} |
%%                                      {stop, Reason, State}
%% Description: Handling call messages
%%--------------------------------------------------------------------
handle_call({reserve, ClientId, Gateway, IP}, _From, State) ->
    case select_subnet(Gateway, State#state.subnets) of
	{ok, Subnet} ->
	    case select_address(ClientId, IP, Subnet) of
		{ok, Address} ->
		    {reply, reserve_address(Address, ClientId), State};
		{error, Reason} ->
		    {reply, {error, Reason}, State}
	    end;
	{error, Reason} ->
	    {reply, {error, Reason}, State}
    end;
handle_call({allocate, ClientId, IP}, _From, State) ->
    case ets:lookup(?ADDRESS, IP) of
	[A] when ?IS_OFFERED(A) ->
	    {reply, allocate_address(A, ClientId), State};
	_ ->
	    {reply, {error, "Address is not offered."}, State}
    end;
handle_call({release, ClientId, IP}, _From, State) ->
    {reply, release_address(ClientId, IP), State};
handle_call({verify, ClientId, Gateway, IP}, _From, State) ->
    case select_subnet(Gateway, State#state.subnets) of
	{ok, Subnet} ->
	    {reply, verify_address(ClientId, IP, Subnet), State};
	{error, Reason} ->
	    {reply, {error, Reason}, State}
    end;
handle_call({extend, ClientId, IP}, _From, State) ->
    case ets:lookup(?ADDRESS, IP) of
	[A] when ?IS_ALLOCATED(A) ->
	    {reply, allocate_address(A, ClientId), State};
	_ ->
	    {reply, {error, "Address is not allocated."}, State}
    end;
handle_call({local_conf, Gateway}, _From, State) ->
    case select_subnet(Gateway, State#state.subnets) of
	{ok, Subnet} ->
	    {reply, {ok, Subnet#subnet.options}, State};
	{error, Reason} ->
	    {reply, {error, Reason}, State}
    end;
handle_call({decline, ClientId, IP}, _From, State) ->
    case ets:lookup(?ADDRESS, IP) of
	[A] when ?IS_ALLOCATED(A) ->
	    {reply, decline_address(A, ClientId), State};
	_ ->
	    {reply, {error, "Address not allocated."}, State}
    end.

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
handle_info({expired, IP}, State) ->
    Address = #address{ip = IP, status = available},
    ets:insert(?ADDRESS, Address),
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
terminate(_Reason, _State) ->
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
select_subnet(_, []) ->
    {error, "No subnet."};
select_subnet({0, 0, 0, 0}, [First | _]) ->
    {ok, First};
select_subnet(IP, [S|T]) ->
    case belongs_to_subnet(IP, S) of
	true ->
	    {ok, S};
	false ->
	    select_subnet(IP, T)
    end.

belongs_to_subnet(IP, S) ->
    ip_to_int(S#subnet.network) ==
	ip_to_int(IP) band ip_to_int(S#subnet.netmask).

ip_to_int(IP) ->
    <<Int:32>> = list_to_binary(inet:ip_to_bytes(IP)),
    Int.

int_to_ip(Int) ->
    list_to_tuple(binary_to_list(<<Int:32>>)).

select_address(_ClientId, {0, 0, 0, 0}, S) ->
    F = fun(A, false) when ?IS_AVAILABLE(A) ->
		case belongs_to_subnet(A#address.ip, S) of
		    true  -> A;
		    false -> false
		end;
	   (_, Acc) -> Acc
	end,
    case ets:foldl(F, false, ?ADDRESS) of
	false -> {error, "No available addresses in this subnet."};
	A     -> {ok, A#address{options = S#subnet.options}}
    end;
select_address(ClientId, IP, S) ->
    Options = S#subnet.options,
    Now = calendar:datetime_to_gregorian_seconds({date(), time()}),
    case belongs_to_subnet(IP, S) of
	true ->
	    case dets:lookup(?LEASE, ClientId) of
		[L] when ?IS_NOT_EXPIRED(L, Now) ->
		    {ok, #address{ip = L#lease.ip, options = Options}};
		[L] ->
		    case ets:lookup(?ADDRESS, L#lease.ip) of
			[A] when ?IS_AVAILABLE(A) ->
			    {ok, A#address{options = Options}};
			_ ->
			    dets:delete(?LEASE, ClientId),
			    select_address(ClientId, IP, S)
		    end;
		[] ->
		    case ets:lookup(?ADDRESS, IP) of
			[A] when ?IS_AVAILABLE(A) ->
			    {ok, A#address{options = Options}};
			[A] when ?IS_OFFERED(A) ->
			    {error, "Already offered"};
			_ ->
			    select_address(ClientId, {0,0,0,0}, S)
		    end
	    end;
	false ->
	    select_address(ClientId, {0,0,0,0}, S)
    end.

verify_address(ClientId, IP, S) ->
    case belongs_to_subnet(IP, S) of
	true ->
	    DateTime = {date(), time()},
	    Now = calendar:datetime_to_gregorian_seconds(DateTime),
	    case dets:lookup(?LEASE, ClientId) of
		[L] when ?IS_NOT_EXPIRED(L, Now), L#lease.ip == IP ->
		    allocate_address(ClientId, IP, S#subnet.options),
		    {ok, IP, S#subnet.options};
		[_] ->
		    {error, "Address is not currently allocated to lease."};
		[] ->
		    nolease
	    end;
	false ->
	    release_address(ClientId, IP),
	    {error, "Wrong network."}
    end.

reserve_address(A, ClientId) ->
    cancel_timer(A#address.timer),
    Timer = erlang:send_after(?DHCPOFFER_TIMEOUT, ?SERVER,
			      {expired, A#address.ip}),
    ets:insert(?ADDRESS, A#address{status = offered, timer = Timer}),
    DateTime = {date(), time()},
    Now = calendar:datetime_to_gregorian_seconds(DateTime),
    Expires = Now + ?DHCPOFFER_TIMEOUT,
    Lease = #lease{clientid = ClientId, ip = A#address.ip, expires = Expires},
    dets:insert(?LEASE, Lease),
    {ok, A#address.ip, A#address.options}.

allocate_address(ClientId, IP, Options) ->
    allocate_address(#address{ip = IP, options = Options}, ClientId).

allocate_address(A, ClientId) ->
    IP = A#address.ip,
    Options = A#address.options,
    cancel_timer(A#address.timer),
    case lists:keysearch(?DHO_DHCP_LEASE_TIME, 1, Options) of
	{value, {?DHO_DHCP_LEASE_TIME, LeaseTime}} ->
	    DateTime = {date(), time()},
	    Gregorian = calendar:datetime_to_gregorian_seconds(DateTime),
	    Expires = Gregorian + LeaseTime,
	    Lease = #lease{clientid = ClientId, ip = IP, expires = Expires},
	    dets:insert(?LEASE, Lease),
	    T = erlang:send_after(LeaseTime * 1000, ?SERVER, {expired, IP}),
	    ets:insert(?ADDRESS, A#address{status = allocated, timer = T}),
	    {ok, IP, Options};
	false ->
	    {error, "Lease time not configured."}
    end.

release_address(ClientId, IP) ->
    case ets:lookup(?ADDRESS, IP) of
	[A] when ?IS_ALLOCATED(A) ->
	    IP = A#address.ip,
	    case dets:lookup(?LEASE, ClientId) of
		[L] when L#lease.ip == IP ->
		    cancel_timer(A#address.timer),
		    Address = #address{ip = IP, status = available},
		    ets:insert(?ADDRESS, Address),
		    DateTime = {date(), time()},
		    Now = calendar:datetime_to_gregorian_seconds(DateTime),
		    dets:insert(?LEASE, L#lease{expires = Now}),
		    ok;
		_ ->
		    {error, "Allocated to someone else."}
	    end;
	_ ->
	    {error, "Address not allocated."}
    end.

decline_address(A, ClientId) ->
    IP = A#address.ip,
    case dets:lookup(?LEASE, ClientId) of
	[L] when L#lease.ip == IP ->
	    cancel_timer(A#address.timer),
	    ets:insert(?ADDRESS, #address{ip = IP, status = declined}),
	    dets:delete(?LEASE, L#lease.clientid),
	    ok;
	_ ->
	    {error, "Allocated to other lease."}
    end.

cancel_timer(Timer) when is_reference(Timer) ->
    erlang:cancel_timer(Timer);
cancel_timer(_Timer) ->
    ok.

init_subnet(Subnet) ->
    init_available(Subnet#subnet.range),
    init_allocated(Subnet).

init_available({X, X}) ->
    ets:insert(?ADDRESS, #address{ip = X, status = available});
init_available({Low, High}) ->
    ets:insert(?ADDRESS, #address{ip = Low, status = available}),
    NextIP = int_to_ip(ip_to_int(Low) + 1),
    init_available({NextIP, High}).

init_allocated(#subnet{options = Options}) ->
    DateTime = {date(), time()},
    Now = calendar:datetime_to_gregorian_seconds(DateTime),
    Allocate = fun(L, Acc) when ?IS_NOT_EXPIRED(L, Now) ->
		       allocate_address(L#lease.clientid, L#lease.ip, Options),
		       [L#lease.clientid | Acc];
		  (_, Acc) ->
		       Acc
	       end,
    dets:foldl(Allocate, [], ?LEASE).
