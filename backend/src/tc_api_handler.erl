%%%-------------------------------------------------------------------
%%% @doc REST API handler.
%%% Auth:  Authorization: Bearer <token>  (or ?token= for convenience)
%%%-------------------------------------------------------------------
-module(tc_api_handler).
-behaviour(cowboy_handler).

-export([init/2]).

-define(UPLOAD_LIMIT, 31457280). % 30 MB
-define(ALLOWED_EXTS, [<<".jpg">>, <<".jpeg">>, <<".png">>, <<".gif">>,
                        <<".webp">>, <<".mp4">>, <<".webm">>, <<".mov">>,
                        <<".ogg">>, <<".oga">>, <<".mp3">>, <<".m4a">>,
                        <<".wav">>, <<".pdf">>, <<".txt">>, <<".zip">>]).

init(Req0, State) ->
    Method = cowboy_req:method(Req0),
    Path = cowboy_req:path_info(Req0),
    {Code, Resp} = handle(Method, Path, Req0),
    Req = cowboy_req:reply(Code,
                           #{<<"content-type">> => <<"application/json">>},
                           jsx:encode(Resp), Req0),
    {ok, Req, State}.

%%-------------------------------------------------------------------
%% Routing: auth & profile
%%-------------------------------------------------------------------
handle(<<"POST">>, [<<"register">>], Req) ->
    with_json_body(Req, fun(#{<<"username">> := U, <<"password">> := P}, _) ->
        case tc_auth:register(U, P) of
            {ok, Token} ->
                {200, #{ok => true, token => Token, username => U,
                        pin => tc_contacts:get_pin(U)}};
            {error, username_taken} ->
                {409, err(<<"username_taken">>)};
            {error, invalid_input} ->
                {400, err(<<"invalid_input">>)}
        end
    end);

handle(<<"POST">>, [<<"login">>], Req) ->
    with_json_body(Req, fun(#{<<"username">> := U, <<"password">> := P}, _) ->
        case tc_auth:login(U, P) of
            {ok, Token} ->
                {200, #{ok => true, token => Token, username => U}};
            {error, bad_credentials} ->
                {401, err(<<"bad_credentials">>)}
        end
    end);

handle(<<"POST">>, [<<"logout">>], Req) ->
    with_auth(Req, fun(Token, _) ->
        tc_auth:logout(Token),
        {200, #{ok => true}}
    end);

handle(<<"GET">>, [<<"me">>], Req) ->
    with_auth(Req, fun(_, Username) ->
        {200, #{ok => true,
                username => Username,
                pin => tc_contacts:ensure_pin(Username),
                bio => tc_profile:get_bio(Username)}}
    end);

handle(<<"PUT">>, [<<"profile">>], Req) ->
    with_auth(Req, fun(_, Username) ->
        with_json_body(Req, fun(#{<<"bio">> := Bio}, _) ->
            case tc_profile:set_bio(Username, Bio) of
                ok -> {200, #{ok => true}};
                {error, invalid_input} -> {400, err(<<"invalid_input">>)}
            end
        end)
    end);

%%-------------------------------------------------------------------
%% Routing: contacts (BBM-style PIN)
%%-------------------------------------------------------------------
handle(<<"GET">>, [<<"contacts">>], Req) ->
    with_auth(Req, fun(_, Username) ->
        Cs = tc_contacts:list_contacts(Username),
        {200, #{ok => true,
                contacts => [#{username => C,
                               presence => tc_presence:get(C),
                               bio => tc_profile:get_bio(C)} || C <- Cs]}}
    end);

handle(<<"GET">>, [<<"contacts">>, <<"requests">>], Req) ->
    with_auth(Req, fun(_, Username) ->
        In = tc_contacts:list_requests(Username),
        Out = tc_contacts:list_sent_requests(Username),
        {200, #{ok => true,
                incoming => [#{username => F, ts => Ts} || {F, Ts} <- In],
                outgoing => Out}}
    end);

handle(<<"POST">>, [<<"contacts">>, <<"requests">>], Req) ->
    with_auth(Req, fun(_, Username) ->
        with_json_body(Req, fun(#{<<"pin">> := Pin}, _) ->
            case tc_contacts:send_request(Username, Pin) of
                {ok, To} ->
                    tc_notify:user(To, #{type => <<"contact_request">>,
                                        from => Username}),
                    {200, #{ok => true}};
                {error, unknown_pin} -> {404, err(<<"unknown_pin">>)};
                {error, cannot_add_self} -> {400, err(<<"cannot_add_self">>)};
                {error, already_contacts} -> {409, err(<<"already_contacts">>)};
                {error, request_pending} -> {409, err(<<"request_pending">>)}
            end
        end)
    end);

handle(<<"POST">>, [<<"contacts">>, <<"requests">>, From, <<"accept">>], Req) ->
    with_auth(Req, fun(_, Username) ->
        case tc_contacts:accept_request(Username, From) of
            ok ->
                tc_notify:user(From, #{type => <<"contact_accepted">>,
                                       by => Username}),
                {200, #{ok => true}};
            {error, not_found} -> {404, err(<<"not_found">>)}
        end
    end);

handle(<<"POST">>, [<<"contacts">>, <<"requests">>, From, <<"decline">>], Req) ->
    with_auth(Req, fun(_, Username) ->
        ok = tc_contacts:decline_request(Username, From),
        {200, #{ok => true}}
    end);

handle(<<"DELETE">>, [<<"contacts">>, Username], Req) ->
    with_auth(Req, fun(_, Me) ->
        ok = tc_contacts:remove_contact(Me, Username),
        {200, #{ok => true}}
    end);

handle(<<"GET">>, [<<"users">>], Req) ->
    with_auth(Req, fun(_, Username) ->
        Qs = cowboy_req:parse_qs(Req),
        Q = proplists:get_value(<<"q">>, Qs, <<>>),
        Users = search_users(Q, Username),
        {200, #{ok => true,
                users => [#{username => U,
                            presence => tc_presence:get(U)} || U <- Users]}}
    end);

%%-------------------------------------------------------------------
%% Routing: chats & groups
%%-------------------------------------------------------------------
handle(<<"GET">>, [<<"chats">>], Req) ->
    with_auth(Req, fun(_, Username) ->
        {200, #{ok => true, chats => tc_chat:list_chats(Username)}}
    end);

handle(<<"POST">>, [<<"chats">>], Req) ->
    with_auth(Req, fun(_, Username) ->
        with_json_body(Req, fun(#{<<"username">> := Peer}, _) ->
            case tc_chat:get_or_create_chat(Username, Peer) of
                {ok, Id} -> {200, #{ok => true, chat_id => Id}};
                {error, cannot_chat_with_self} -> {400, err(<<"cannot_chat_with_self">>)};
                {error, _} -> {500, err(<<"server_error">>)}
            end
        end)
    end);

handle(<<"POST">>, [<<"groups">>], Req) ->
    with_auth(Req, fun(_, Username) ->
        with_json_body(Req, fun(Body, _) ->
            Name = maps:get(<<"name">>, Body, <<>>),
            Members = maps:get(<<"members">>, Body, []),
            case tc_chat:create_group(Username, Name, Members) of
                {ok, Id} -> {200, #{ok => true, chat_id => Id}};
                {error, unknown_user} -> {400, err(<<"unknown_user">>)};
                {error, invalid_input} -> {400, err(<<"invalid_input">>)};
                {error, _} -> {500, err(<<"server_error">>)}
            end
        end)
    end);

handle(<<"GET">>, [<<"groups">>, <<"public">>], Req) ->
    with_auth(Req, fun(_, _) ->
        {200, #{ok => true, groups => tc_chat:list_public_groups()}}
    end);

handle(<<"GET">>, [<<"groups">>, IdBin], Req) ->
    with_auth(Req, fun(_, Username) ->
        case parse_id(IdBin) of
            {ok, Id} ->
                case tc_chat:get_group_info(Id, Username) of
                    {ok, Info} -> {200, #{ok => true, group => Info}};
                    {error, forbidden} -> {403, err(<<"forbidden">>)};
                    {error, not_found} -> {404, err(<<"not_found">>)}
                end;
            error -> {400, err(<<"invalid_input">>)}
        end
    end);

handle(<<"PUT">>, [<<"groups">>, IdBin], Req) ->
    with_auth(Req, fun(_, Username) ->
        with_json_body(Req, fun(Body, _) ->
            case parse_id(IdBin) of
                {ok, Id} ->
                    Name = maps:get(<<"name">>, Body, undefined),
                    Vis = case maps:get(<<"visibility">>, Body, undefined) of
                              <<"public">> -> public;
                              <<"private">> -> private;
                              _ -> undefined
                          end,
                    case tc_chat:update_group(Id, Username, Name, Vis) of
                        ok ->
                            push_group_updated(Id, Username),
                            {200, #{ok => true}};
                        {error, forbidden} -> {403, err(<<"forbidden">>)};
                        {error, not_found} -> {404, err(<<"not_found">>)}
                    end;
                error -> {400, err(<<"invalid_input">>)}
            end
        end)
    end);

handle(<<"DELETE">>, [<<"groups">>, IdBin], Req) ->
    with_auth(Req, fun(_, Username) ->
        case parse_id(IdBin) of
            {ok, Id} ->
                case tc_chat:delete_group(Id, Username) of
                    ok -> {200, #{ok => true}};
                    {error, forbidden} -> {403, err(<<"forbidden">>)};
                    {error, not_found} -> {404, err(<<"not_found">>)}
                end;
            error -> {400, err(<<"invalid_input">>)}
        end
    end);

handle(<<"POST">>, [<<"groups">>, IdBin, <<"join">>], Req) ->
    with_auth(Req, fun(_, Username) ->
        case parse_id(IdBin) of
            {ok, Id} ->
                case tc_chat:join_group(Id, Username) of
                    ok -> {200, #{ok => true, chat_id => Id}};
                    {error, already_member} -> {409, err(<<"already_member">>)};
                    {error, private_group} -> {403, err(<<"private_group">>)};
                    {error, not_found} -> {404, err(<<"not_found">>)}
                end;
            error -> {400, err(<<"invalid_input">>)}
        end
    end);

handle(<<"POST">>, [<<"groups">>, IdBin, <<"leave">>], Req) ->
    with_auth(Req, fun(_, Username) ->
        case parse_id(IdBin) of
            {ok, Id} ->
                case tc_chat:leave_group(Id, Username) of
                    ok -> {200, #{ok => true}};
                    {error, not_found} -> {404, err(<<"not_found">>)}
                end;
            error -> {400, err(<<"invalid_input">>)}
        end
    end);

handle(<<"POST">>, [<<"groups">>, IdBin, <<"members">>], Req) ->
    with_auth(Req, fun(_, Username) ->
        with_json_body(Req, fun(#{<<"username">> := Peer}, _) ->
            case parse_id(IdBin) of
                {ok, Id} ->
                    case tc_chat:add_member(Id, Username, Peer) of
                        ok ->
                            push_group_updated(Id, Username),
                            {200, #{ok => true}};
                        {error, forbidden} -> {403, err(<<"forbidden">>)};
                        {error, unknown_user} -> {400, err(<<"unknown_user">>)};
                        {error, already_member} -> {409, err(<<"already_member">>)};
                        {error, not_found} -> {404, err(<<"not_found">>)}
                    end;
                error -> {400, err(<<"invalid_input">>)}
            end
        end)
    end);

handle(<<"DELETE">>, [<<"groups">>, IdBin, <<"members">>, Peer], Req) ->
    with_auth(Req, fun(_, Username) ->
        case parse_id(IdBin) of
            {ok, Id} ->
                case tc_chat:remove_member(Id, Username, Peer) of
                    ok ->
                        push_group_updated(Id, Username),
                        tc_notify:user(Peer, #{type => <<"removed_from_group">>,
                                               chat_id => Id}),
                        {200, #{ok => true}};
                    {error, forbidden} -> {403, err(<<"forbidden">>)};
                    {error, use_leave} -> {400, err(<<"use_leave">>)};
                    {error, not_found} -> {404, err(<<"not_found">>)}
                end;
            error -> {400, err(<<"invalid_input">>)}
        end
    end);

handle(<<"PUT">>, [<<"groups">>, IdBin, <<"members">>, Peer, <<"role">>], Req) ->
    with_auth(Req, fun(_, Username) ->
        with_json_body(Req, fun(#{<<"role">> := RoleBin}, _) ->
            Role = case RoleBin of
                       <<"admin">> -> admin;
                       <<"moderator">> -> moderator;
                       <<"member">> -> member;
                       _ -> invalid
                   end,
            case parse_id(IdBin) of
                {ok, Id} when Role =/= invalid ->
                    case tc_chat:set_role(Id, Username, Peer, Role) of
                        ok ->
                            push_group_updated(Id, Username),
                            {200, #{ok => true}};
                        {error, forbidden} -> {403, err(<<"forbidden">>)};
                        {error, not_found} -> {404, err(<<"not_found">>)};
                        {error, invalid_input} -> {400, err(<<"invalid_input">>)}
                    end;
                _ -> {400, err(<<"invalid_input">>)}
            end
        end)
    end);

%%-------------------------------------------------------------------
%% Routing: messages
%%-------------------------------------------------------------------
handle(<<"GET">>, [<<"chats">>, IdBin, <<"messages">>], Req) ->
    with_auth(Req, fun(_, Username) ->
        case parse_id(IdBin) of
            {ok, Id} ->
                case tc_chat:list_messages(Id, Username) of
                    {ok, Msgs, Senders} ->
                        push_receipts(Id, Senders),
                        {200, #{ok => true, messages => Msgs}};
                    {error, forbidden} -> {403, err(<<"forbidden">>)};
                    {error, not_found} -> {404, err(<<"not_found">>)}
                end;
            error ->
                {400, err(<<"invalid_input">>)}
        end
    end);

handle(<<"POST">>, [<<"chats">>, IdBin, <<"messages">>], Req) ->
    with_auth(Req, fun(_, Username) ->
        with_json_body(Req, fun(Body, _) ->
            Kind = parse_kind(maps:get(<<"kind">>, Body, <<"text">>)),
            Text = maps:get(<<"text">>, Body, <<>>),
            MediaUrl = maps:get(<<"media_url">>, Body, undefined),
            ReplyTo = maps:get(<<"reply_to">>, Body, undefined),
            case {parse_id(IdBin), Kind} of
                {{ok, Id}, invalid} ->
                    {400, err(<<"invalid_input">>)};
                {{ok, Id}, _} ->
                    case tc_chat:send_message(Id, Username, Kind, Text,
                                              MediaUrl, ReplyTo) of
                        {ok, Msg, Members} ->
                            notify_new_message(Members, Msg),
                            {200, #{ok => true, message => Msg}};
                        {error, forbidden} -> {403, err(<<"forbidden">>)};
                        {error, not_found} -> {404, err(<<"not_found">>)};
                        {error, invalid_input} -> {400, err(<<"invalid_input">>)}
                    end;
                _ ->
                    {400, err(<<"invalid_input">>)}
            end
        end)
    end);

handle(<<"POST">>, [<<"chats">>, IdBin, <<"read">>], Req) ->
    with_auth(Req, fun(_, Username) ->
        case parse_id(IdBin) of
            {ok, Id} ->
                case tc_chat:get_chat(Id, Username) of
                    {ok, _} ->
                        {ok, Senders} = tc_chat:mark_read(Id, Username),
                        push_receipts(Id, Senders),
                        {200, #{ok => true}};
                    {error, forbidden} -> {403, err(<<"forbidden">>)};
                    {error, not_found} -> {404, err(<<"not_found">>)}
                end;
            error ->
                {400, err(<<"invalid_input">>)}
        end
    end);

handle(<<"DELETE">>, [<<"chats">>, IdBin, <<"messages">>, MsgBin], Req) ->
    with_auth(Req, fun(_, Username) ->
        Qs = cowboy_req:parse_qs(Req),
        Mode = case proplists:get_value(<<"mode">>, Qs, <<"me">>) of
                   <<"everyone">> -> everyone;
                   _ -> me
               end,
        case {parse_id(IdBin), parse_id(MsgBin)} of
            {{ok, Id}, {ok, MsgId}} ->
                case tc_chat:delete_message(Id, MsgId, Username, Mode) of
                    ok ->
                        case Mode of
                            everyone ->
                                Members = tc_chat:chat_members(Id) -- [Username],
                                tc_notify:members(
                                    Members,
                                    #{type => <<"message_deleted">>,
                                      chat_id => Id,
                                      message_id => MsgId});
                            me -> ok
                        end,
                        {200, #{ok => true}};
                    {error, forbidden} -> {403, err(<<"forbidden">>)};
                    {error, not_found} -> {404, err(<<"not_found">>)}
                end;
            _ ->
                {400, err(<<"invalid_input">>)}
        end
    end);

handle(<<"POST">>, [<<"messages">>, MsgBin, <<"reactions">>], Req) ->
    with_auth(Req, fun(_, Username) ->
        with_json_body(Req, fun(#{<<"emoji">> := Emoji}, _) ->
            case parse_id(MsgBin) of
                {ok, MsgId} ->
                    case find_chat_of_message(MsgId) of
                        {ok, ChatId} ->
                            case tc_chat:add_reaction(ChatId, MsgId, Username, Emoji) of
                                ok ->
                                    Members = tc_chat:chat_members(ChatId) -- [Username],
                                    tc_notify:members(
                                        Members,
                                        #{type => <<"reaction">>,
                                          chat_id => ChatId,
                                          message_id => MsgId}),
                                    {200, #{ok => true}};
                                {error, forbidden} -> {403, err(<<"forbidden">>)};
                                {error, not_found} -> {404, err(<<"not_found">>)};
                                {error, invalid_input} -> {400, err(<<"invalid_input">>)}
                            end;
                        error -> {404, err(<<"not_found">>)}
                    end;
                error -> {400, err(<<"invalid_input">>)}
            end
        end)
    end);

handle(<<"DELETE">>, [<<"messages">>, MsgBin, <<"reactions">>], Req) ->
    with_auth(Req, fun(_, Username) ->
        case parse_id(MsgBin) of
            {ok, MsgId} ->
                ok = tc_chat:remove_reaction(MsgId, Username),
                case find_chat_of_message(MsgId) of
                    {ok, ChatId} ->
                        Members = tc_chat:chat_members(ChatId) -- [Username],
                        tc_notify:members(
                            Members,
                            #{type => <<"reaction">>,
                              chat_id => ChatId,
                              message_id => MsgId});
                    error -> ok
                end,
                {200, #{ok => true}};
            error ->
                {400, err(<<"invalid_input">>)}
        end
    end);

%%-------------------------------------------------------------------
%% Routing: status
%%-------------------------------------------------------------------
handle(<<"POST">>, [<<"status">>], Req) ->
    with_auth(Req, fun(_, Username) ->
        with_json_body(Req, fun(Body, _) ->
            Kind = parse_kind(maps:get(<<"kind">>, Body, <<"text">>)),
            Text = maps:get(<<"text">>, Body, <<>>),
            MediaUrl = maps:get(<<"media_url">>, Body, undefined),
            BgColor = maps:get(<<"bg_color">>, Body, undefined),
            case Kind of
                text ->
                    case tc_status:post(Username, text, Text, undefined, BgColor) of
                        {ok, Id} ->
                            tc_notify:contacts(Username,
                                               #{type => <<"new_status">>,
                                                 username => Username}),
                            {200, #{ok => true, id => Id}};
                        {error, invalid_input} -> {400, err(<<"invalid_input">>)}
                    end;
                image ->
                    post_status_media(Username, image, MediaUrl);
                video ->
                    post_status_media(Username, video, MediaUrl);
                _ ->
                    {400, err(<<"invalid_input">>)}
            end
        end)
    end);

handle(<<"GET">>, [<<"status">>, <<"feed">>], Req) ->
    with_auth(Req, fun(_, Username) ->
        {200, #{ok => true,
                mine => tc_status:my_status(Username),
                feed => tc_status:feed(Username)}}
    end);

handle(<<"DELETE">>, [<<"status">>, IdBin], Req) ->
    with_auth(Req, fun(_, Username) ->
        case parse_id(IdBin) of
            {ok, Id} ->
                case tc_status:delete(Username, Id) of
                    ok -> {200, #{ok => true}};
                    {error, forbidden} -> {403, err(<<"forbidden">>)};
                    {error, not_found} -> {404, err(<<"not_found">>)}
                end;
            error -> {400, err(<<"invalid_input">>)}
        end
    end);

handle(<<"POST">>, [<<"status">>, IdBin, <<"view">>], Req) ->
    with_auth(Req, fun(_, Username) ->
        case parse_id(IdBin) of
            {ok, Id} ->
                ok = tc_status:mark_viewed(Id, Username),
                {200, #{ok => true}};
            error -> {400, err(<<"invalid_input">>)}
        end
    end);

%%-------------------------------------------------------------------
%% Routing: upload
%%-------------------------------------------------------------------
handle(<<"POST">>, [<<"upload">>], Req) ->
    with_auth(Req, fun(_, _Username) ->
        handle_upload(Req)
    end);

handle(_, _, _Req) ->
    {404, err(<<"not_found">>)}.

%%-------------------------------------------------------------------
%% Upload (multipart/form-data, single file part)
%%-------------------------------------------------------------------
handle_upload(Req) ->
    case cowboy_req:read_part(Req) of
        {ok, Headers, Req2} ->
            case parse_filename(Headers) of
                {ok, Filename} ->
                    case read_upload_body(Req2, <<>>, ?UPLOAD_LIMIT) of
                        {ok, Data, _Req3} -> save_upload(Filename, Data);
                        {error, too_large} -> {413, err(<<"too_large">>)}
                    end;
                error ->
                    {400, err(<<"invalid_input">>)}
            end;
        {done, _} ->
            {400, err(<<"invalid_input">>)}
    end.

read_upload_body(Req, Acc, Limit) ->
    case cowboy_req:read_part_body(Req) of
        {ok, Data, Req2} ->
            check_size(<<Acc/binary, Data/binary>>, Limit, Req2);
        {more, Data, Req2} ->
            case byte_size(Acc) + byte_size(Data) > Limit of
                true -> {error, too_large};
                false -> read_upload_body(Req2, <<Acc/binary, Data/binary>>, Limit)
            end
    end.

check_size(Bin, Limit, Req) ->
    case byte_size(Bin) > Limit of
        true -> {error, too_large};
        false -> {ok, Bin, Req}
    end.

parse_filename(Headers) when is_map(Headers) ->
    case maps:get(<<"content-disposition">>, Headers, undefined) of
        undefined -> error;
        Disp -> extract_filename(Disp)
    end;
parse_filename(Headers) when is_list(Headers) ->
    case lists:keyfind(<<"content-disposition">>, 1, Headers) of
        {_, Disp} -> extract_filename(Disp);
        false -> error
    end.

extract_filename(Disp) ->
    case binary:split(Disp, <<"filename=\"">>) of
        [_, Rest] ->
            case binary:split(Rest, <<"\"">>) of
                [Name, _] when byte_size(Name) > 0 -> {ok, Name};
                _ -> error
            end;
        _ -> error
    end.

save_upload(Filename, Data) ->
    Ext = string:lowercase(file_extension(Filename)),
    case lists:member(Ext, ?ALLOWED_EXTS) of
        true ->
            Unique = integer_to_binary(erlang:unique_integer([monotonic, positive])),
            SafeName = <<Unique/binary, Ext/binary>>,
            Dir = filename:join(code:priv_dir(tc), "www/uploads"),
            ok = filelib:ensure_dir(filename:join(Dir, "dummy")),
            case file:write_file(filename:join(Dir, SafeName), Data) of
                ok ->
                    {200, #{ok => true,
                            url => <<"/uploads/", SafeName/binary>>}};
                {error, _} ->
                    {500, err(<<"server_error">>)}
            end;
        false ->
            {400, err(<<"invalid_file_type">>)}
    end.

file_extension(Filename) ->
    case binary:split(Filename, <<".">>, [global]) of
        Parts when length(Parts) > 1 ->
            <<".", (lists:last(Parts))/binary>>;
        _ ->
            <<>>
    end.

%%-------------------------------------------------------------------
%% Helpers
%%-------------------------------------------------------------------
post_status_media(Username, Kind, MediaUrl) ->
    case tc_status:post(Username, Kind, <<>>, MediaUrl, undefined) of
        {ok, Id} ->
            tc_notify:contacts(Username, #{type => <<"new_status">>,
                                           username => Username}),
            {200, #{ok => true, id => Id}};
        {error, invalid_input} -> {400, err(<<"invalid_input">>)}
    end.

%% Push read receipts to senders.
push_receipts(ChatId, Senders) ->
    [tc_notify:user(S, #{type => <<"receipt">>, chat_id => ChatId})
     || S <- Senders],
    ok.

%% Notify group members (except actor) that the group changed.
push_group_updated(ChatId, Actor) ->
    Members = tc_chat:chat_members(ChatId) -- [Actor],
    tc_notify:members(Members, #{type => <<"group_updated">>,
                                 chat_id => ChatId}),
    ok.

err(Code) -> #{ok => false, error => Code}.

with_auth(Req, Fun) ->
    case auth_user(Req) of
        {ok, Username} ->
            Token = auth_token(Req),
            Fun(Token, Username);
        {error, unauthorized} ->
            {401, err(<<"unauthorized">>)}
    end.

auth_user(Req) ->
    tc_auth:verify(auth_token(Req)).

auth_token(Req) ->
    case cowboy_req:header(<<"authorization">>, Req) of
        <<"Bearer ", Token/binary>> -> Token;
        _ ->
            Qs = cowboy_req:parse_qs(Req),
            proplists:get_value(<<"token">>, Qs, <<>>)
    end.

with_json_body(Req, Fun) ->
    case cowboy_req:read_body(Req) of
        {ok, Body, _} ->
            try jsx:decode(Body, [return_maps]) of
                Map when is_map(Map) -> Fun(Map, Req);
                _ -> {400, err(<<"invalid_json">>)}
            catch
                _:_ -> {400, err(<<"invalid_json">>)}
            end;
        _ ->
            {400, err(<<"invalid_json">>)}
    end.

parse_id(Bin) ->
    try {ok, binary_to_integer(Bin)}
    catch _:_ -> error
    end.

parse_kind(<<"text">>) -> text;
parse_kind(<<"sticker">>) -> sticker;
parse_kind(<<"image">>) -> image;
parse_kind(<<"video">>) -> video;
parse_kind(<<"voice">>) -> voice;
parse_kind(_) -> invalid.

search_users(Query, Self) ->
    Q = string:lowercase(Query),
    Keys = mnesia:dirty_all_keys(users),
    Users = [U || U <- Keys, U =/= Self],
    case Q of
        <<>> -> Users;
        _ -> [U || U <- Users,
                   binary:match(string:lowercase(U), Q) =/= nomatch]
    end.

find_chat_of_message(MsgId) ->
    case mnesia:dirty_read(messages, MsgId) of
        [{messages, MsgId, ChatId, _, _, _, _, _, _}] -> {ok, ChatId};
        [] -> error
    end.

notify_new_message(Members, Msg) ->
    MsgId = maps:get(id, Msg),
    lists:foreach(
        fun(Member) ->
            Pids = pg:get_members({tc_ws, Member}),
            case Pids of
                [] -> ok;
                _ ->
                    tc_notify:user(Member, #{type => <<"message">>,
                                             message => Msg}),
                    tc_chat:mark_delivered(MsgId, Member)
            end
        end, Members),
    ok.
