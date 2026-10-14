%%%-------------------------------------------------------------------
%%% @doc SPA fallback: serve index.html for client-side routes
%%% (React Router). Real files are handled by cowboy_static routes
%%% defined before this catch-all in the dispatch.
%%%-------------------------------------------------------------------
-module(tc_spa_handler).
-behaviour(cowboy_handler).
-export([init/2]).

init(Req0, State) ->
    PrivDir = code:priv_dir(tc),
    Index = filename:join([PrivDir, "www", "index.html"]),
    {ok, Data} = file:read_file(Index),
    Req = cowboy_req:reply(200,
        #{<<"content-type">> => <<"text/html; charset=utf-8">>,
          <<"cache-control">> => <<"no-cache">>},
        Data, Req0),
    {ok, Req, State}.
