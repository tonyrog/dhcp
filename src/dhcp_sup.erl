%%%-------------------------------------------------------------------
%%% File    : dhcp_sup.erl
%%% Author  : Ruslan Babayev <ruslan@babayev.com>
%%% Description : 
%%%
%%% Created : 20 Sep 2006 by Ruslan Babayev <ruslan@babayev.com>
%%%-------------------------------------------------------------------
-module(dhcp_sup).

-behaviour(supervisor).

%% API
-export([start_link/0]).

%% Supervisor callbacks
-export([init/1]).

-import(lists, [keysearch/3, filter/2]).

-include("dhcp_alloc.hrl").

-define(SERVER, ?MODULE).
-define(DHCP_LOGFILE, "/var/log/dhcp.log").
-define(DHCP_LEASEFILE, "/var/run/dhcp_leases.dets").

%%====================================================================
%% API functions
%%====================================================================
%%--------------------------------------------------------------------
%% Function: start_link() -> {ok,Pid} | ignore | {error,Error}
%% Description: Starts the supervisor
%%--------------------------------------------------------------------
start_link() ->
    supervisor:start_link({local, ?SERVER}, ?MODULE, []).

%%====================================================================
%% Supervisor callbacks
%%====================================================================
%%--------------------------------------------------------------------
%% Func: init(Args) -> {ok,  {SupFlags,  [ChildSpec]}} |
%%                     ignore                          |
%%                     {error, Reason}
%% Description: Whenever a supervisor is started using 
%% supervisor:start_link/[2,3], this function is called by the new process 
%% to find out about restart strategy, maximum restart frequency and child 
%% specifications.
%%--------------------------------------------------------------------
init([]) ->
    case get_config() of
        {ok, ServerId, NextServer, LogFile, LeaseFile, Subnets, Hosts} ->
            DHCPServer = {dhcp_server, {dhcp_server, start_link,
                                        [ServerId, NextServer, LogFile]},
                          permanent, 2000, worker, [dhcp_server]},
            DHCPAlloc = {dhcp_alloc, {dhcp_alloc, start_link,
                                      [LeaseFile, Subnets, Hosts]},
                         permanent, 2000, worker, [dhcp_alloc]},
            {ok, {{one_for_one, 0, 1}, [DHCPServer, DHCPAlloc]}};
        {error, Reason} ->
            {error, Reason}
    end.

%%====================================================================
%% Internal functions
%%====================================================================
get_config() ->
    ConfDir = case code:priv_dir(dhcp) of
		  PrivDir when is_list(PrivDir) -> PrivDir;
                  {error, _Reason} -> "."
              end,
    case file:consult(filename:join(ConfDir, "dhcp.conf")) of
        {ok, Terms} ->
            ServerId = case keysearch(server_id, 1, Terms) of
                           {value, {_, SId}} -> SId;
                           false -> {0, 0, 0, 0}
                       end,
            NextServer = case keysearch(next_server, 1, Terms) of
                             {value, {_, Next}} -> Next;
                             false -> {0, 0, 0, 0}
                         end,
            LogFile = case keysearch(logfile, 1, Terms) of
                          {value, {_, Log}} -> Log;
                          false -> ?DHCP_LOGFILE
                      end,
            LeaseFile = case keysearch(lease_file, 1, Terms) of
                            {value, {_, Lease}} -> Lease;
                            false -> ?DHCP_LEASEFILE
                        end,
            Subnets = filter(fun(#subnet{}) -> true;
                                (_) -> false
                             end, Terms),
            Hosts = filter(fun(#host{}) -> true;
                              (_) -> false
                           end, Terms),
            {ok, ServerId, NextServer, LogFile, LeaseFile, Subnets, Hosts};
        {error, Reason} ->
	    {error, Reason}
    end.
