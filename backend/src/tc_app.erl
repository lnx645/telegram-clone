%%%-------------------------------------------------------------------
%%% @doc tc application entry point.
%%% Boots Mnesia, then starts the Cowboy HTTP listener which serves
%%% the REST API (/api/*), the websocket (/ws) and the React SPA.
%%%-------------------------------------------------------------------
-module(tc_app).
-behaviour(application).

-export([start/2, stop/1]).

start(_StartType, _StartArgs) ->
    ok = tc_db:init(),
    %% pg is used to fan out realtime messages to websocket sessions.
    _ = case pg:start_link() of
        {ok, _} -> ok;
        {error, {already_started, _}} -> ok
    end,
    Port = application:get_env(tc, port, 8080),
    Dispatch = cowboy_router:compile([{'_', [
        {"/ws", tc_ws_handler, []},
        {"/api/[...]", tc_api_handler, []},
        {"/", cowboy_static, {priv_file, tc, "www/index.html"}},
        {"/assets/[...]", cowboy_static, {priv_dir, tc, "www/assets"}},
        {"/stickers/[...]", cowboy_static, {priv_dir, tc, "www/stickers"}},
        {"/uploads/[...]", cowboy_static, {priv_dir, tc, "www/uploads"}},
        %% SPA fallback: React Router client-side routes serve index.html
        {"/[...]", tc_spa_handler, []}
    ]}]),
    {ok, _} = cowboy:start_clear(tc_http_listener,
                                 [{port, Port}],
                                 #{env => #{dispatch => Dispatch}}),
    tc_sup:start_link().

stop(_State) ->
    ok.
