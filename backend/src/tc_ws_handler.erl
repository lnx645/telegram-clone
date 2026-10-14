%%%-------------------------------------------------------------------
%%% @doc Websocket handler for realtime messaging.
%%% Connect:  GET /ws?token=<token>   (101 Switching Protocols)
%%% The session joins the pg group {tc_ws, Username}; tc_api_handler
%%% pushes {tc_push, Payload} to group members on new messages.
%%%-------------------------------------------------------------------
-module(tc_ws_handler).
-behaviour(cowboy_websocket).

-export([init/2,
         websocket_init/1,
         websocket_handle/2,
         websocket_info/2,
         terminate/3]).

init(Req, State) ->
    Qs = cowboy_req:parse_qs(Req),
    Token = proplists:get_value(<<"token">>, Qs, <<>>),
    case tc_auth:verify(Token) of
        {ok, Username} ->
            {cowboy_websocket, Req, #{username => Username}};
        {error, _} ->
            Req2 = cowboy_req:reply(401, #{}, <<"unauthorized">>, Req),
            {ok, Req2, State}
    end.

websocket_init(State = #{username := Username}) ->
    ok = pg:join({tc_ws, Username}, self()),
    ok = tc_presence:online(Username),
    {ok, State}.

%% Client frames:
%%   {"type":"typing","chat_id":123} -> broadcast to chat members
%%   ping/pong keepalive; everything else is ignored.
websocket_handle(ping, State) ->
    {reply, pong, State};
websocket_handle({text, Data}, State = #{username := Username}) ->
    handle_client_msg(Data, Username),
    {ok, State};
websocket_handle(_Frame, State) ->
    {ok, State}.

websocket_info({tc_push, Payload}, State) ->
    {reply, {text, Payload}, State};
websocket_info(_Info, State) ->
    {ok, State}.

%%-------------------------------------------------------------------
%% Internal
%%-------------------------------------------------------------------
handle_client_msg(Data, Username) ->
    try jsx:decode(Data, [return_maps]) of
        #{<<"type">> := <<"typing">>, <<"chat_id">> := ChatId}
                when is_integer(ChatId) ->
            case tc_chat:get_chat(ChatId, Username) of
                {ok, _} ->
                    Members = tc_chat:chat_members(ChatId) -- [Username],
                    Payload = jsx:encode(#{type => <<"typing">>,
                                           chat_id => ChatId,
                                           from => Username}),
                    [Pid ! {tc_push, Payload}
                     || M <- Members, Pid <- pg:get_members({tc_ws, M})],
                    ok;
                _ ->
                    ok
            end;
        _ ->
            ok
    catch _:_ ->
        ok
    end.

terminate(_Reason, _Req, #{username := Username}) ->
    ok = pg:leave({tc_ws, Username}, self()),
    ok = tc_presence:offline(Username),
    ok;
terminate(_Reason, _Req, _State) ->
    ok.
