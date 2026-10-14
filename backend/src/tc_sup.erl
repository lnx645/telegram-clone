%%%-------------------------------------------------------------------
%%% @doc Top-level supervisor (currently a placeholder for future
%%% supervised workers; the HTTP listener is owned by cowboy).
%%%-------------------------------------------------------------------
-module(tc_sup).
-behaviour(supervisor).

-export([start_link/0, init/1]).

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->
    SupFlags = #{strategy => one_for_one, intensity => 5, period => 10},
    {ok, {SupFlags, []}}.
