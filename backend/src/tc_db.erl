%%%-------------------------------------------------------------------
%%% @doc Mnesia persistence layer.
%%% Tables:
%%%   users            {username, pass_hash, salt}
%%%   tokens           {token, username}
%%%   pins             {username, pin}                 (BBM-style PIN)
%%%   contacts         {owner, contact}                (bag, mutual)
%%%   contact_requests {from, to, ts}                  (bag)
%%%   chats            {id, type, name, visibility, user1, user2, updated_at}
%%%                    type = direct | group
%%%                    visibility = private | public (groups)
%%%   chat_members     {chat_id, username, role}       (bag)
%%%                    role = admin | moderator | member
%%%   messages         {id, chat_id, from_user, kind, text, media_url,
%%%                     reply_to, ts}                 (ordered_set)
%%%   reactions        {msg_id, username, emoji}       (bag)
%%%   receipts         {msg_id, username, status}      (bag)
%%%   hidden           {msg_id, username}              (bag)
%%%   status_posts     {id, username, kind, text, media_url,
%%%                     bg_color, ts, expires}        (ordered_set)
%%%   status_views     {status_id, viewer}             (bag)
%%%   profiles         {username, bio}
%%%   presence         {username, online, last_seen}   (ram_copies)
%%%-------------------------------------------------------------------
-module(tc_db).
-export([init/0, txn/1]).

init() ->
    Node = node(),
    %% Only (re)create schema if Mnesia isn't already running with our tables.
    case mnesia:system_info(is_running) of
        yes -> ok;
        _ ->
            _ = mnesia:stop(),
            case mnesia:create_schema([Node]) of
                ok -> ok;
                {error, {_, {already_exists, _}}} -> ok
            end,
            ok = mnesia:start()
    end,
    %% Wait for disc tables to load before any dirty operations.
    Tables = [T || T <- mnesia:system_info(tables), T =/= schema],
    case mnesia:wait_for_tables(Tables, 30000) of
        ok -> ok;
        {timeout, _} -> ok %% proceed; ensure_table will create missing ones
    end,
    ok = ensure_table(users, [{attributes, [username, pass_hash, salt]},
                              {disc_copies, [Node]}]),
    ok = ensure_table(tokens, [{attributes, [token, username]},
                               {disc_copies, [Node]}]),
    ok = ensure_table(pins, [{attributes, [username, pin]},
                             {disc_copies, [Node]}]),
    ok = ensure_table(contacts, [{attributes, [owner, contact]},
                                 {type, bag},
                                 {disc_copies, [Node]}]),
    ok = ensure_table(contact_requests, [{attributes, [from, to, ts]},
                                         {type, bag},
                                         {disc_copies, [Node]}]),
    ok = ensure_chats_table(Node),
    ok = ensure_members_table(Node),
    ok = ensure_messages_table(Node),
    ok = ensure_table(reactions, [{attributes, [msg_id, username, emoji]},
                                  {type, bag},
                                  {disc_copies, [Node]}]),
    ok = ensure_table(receipts, [{attributes, [msg_id, username, status]},
                                 {type, bag},
                                 {disc_copies, [Node]}]),
    ok = ensure_table(hidden, [{attributes, [msg_id, username]},
                               {type, bag},
                               {disc_copies, [Node]}]),
    ok = ensure_table(status_posts,
                      [{attributes, [id, username, kind, text, media_url,
                                     bg_color, ts, expires]},
                       {type, ordered_set},
                       {disc_copies, [Node]}]),
    ok = ensure_table(status_views, [{attributes, [status_id, viewer]},
                                     {type, bag},
                                     {disc_copies, [Node]}]),
    ok = ensure_table(profiles, [{attributes, [username, bio]},
                                 {disc_copies, [Node]}]),
    ok = ensure_table(presence, [{attributes, [username, online, last_seen]},
                                 {ram_copies, [Node]}]),
    ok = ensure_pins_for_existing(),
    ok.

txn(Fun) ->
    case mnesia:transaction(Fun) of
        {atomic, Res} -> Res;
        {aborted, Reason} -> {error, Reason}
    end.

ensure_table(Name, Opts) ->
    case mnesia:create_table(Name, Opts) of
        {atomic, ok} -> ok;
        {aborted, {already_exists, Name}} -> ok;
        {aborted, Reason} -> {error, Reason}
    end.

%% Chats: migrate to 8-attribute format with visibility.
%% Handles the original 5-tuple and the v2.0 7-tuple formats.
ensure_chats_table(Node) ->
    ok = ensure_table(chats,
                      [{attributes, [id, type, name, visibility,
                                     user1, user2, updated_at]},
                       {disc_copies, [Node]}]),
    ok = mnesia:wait_for_tables([chats], 30000),
    case mnesia:table_info(chats, attributes) of
        [id, user1, user2, updated_at] ->
            transform_chats(
                fun({chats, Id, U1, U2, Ts}) ->
                    {chats, Id, direct, undefined, private, U1, U2, Ts}
                end);
        [id, type, name, user1, user2, updated_at] ->
            transform_chats(
                fun({chats, Id, Type, Name, U1, U2, Ts}) ->
                    Vis = case Type of group -> private; direct -> private end,
                    {chats, Id, Type, Name, Vis, U1, U2, Ts}
                end);
        _ ->
            ok
    end.

transform_chats(Fun) ->
    {atomic, ok} = mnesia:transform_table(
        chats, Fun,
        [id, type, name, visibility, user1, user2, updated_at]),
    ok.

%% chat_members: migrate 3-tuple to 4-tuple with role (default member).
ensure_members_table(Node) ->
    ok = ensure_table(chat_members,
                      [{attributes, [chat_id, username, role]},
                       {type, bag},
                       {disc_copies, [Node]}]),
    ok = mnesia:wait_for_tables([chat_members], 30000),
    case mnesia:table_info(chat_members, attributes) of
        [chat_id, username] ->
            {atomic, ok} = mnesia:transform_table(
                chat_members,
                fun({chat_members, Cid, U}) ->
                    {chat_members, Cid, U, member}
                end,
                [chat_id, username, role]),
            ok;
        _ ->
            ok
    end.

%% Messages: migrate to 9-tuple (kind/media_url/reply_to).
ensure_messages_table(Node) ->
    ok = ensure_table(messages,
                      [{attributes, [id, chat_id, from_user, kind, text,
                                     media_url, reply_to, ts]},
                       {type, ordered_set},
                       {disc_copies, [Node]}]),
    ok = mnesia:wait_for_tables([messages], 30000),
    case mnesia:table_info(messages, attributes) of
        [id, chat_id, from_user, text, ts] ->
            {atomic, ok} = mnesia:transform_table(
                messages,
                fun({messages, Id, ChatId, From, Text, Ts}) ->
                    {messages, Id, ChatId, From, text, Text, undefined,
                     undefined, Ts}
                end,
                [id, chat_id, from_user, kind, text, media_url, reply_to, ts]),
            ok;
        [id, chat_id, from_user, kind, text, media_url, ts] ->
            {atomic, ok} = mnesia:transform_table(
                messages,
                fun({messages, Id, ChatId, From, Kind, Text, MediaUrl, Ts}) ->
                    {messages, Id, ChatId, From, Kind, Text, MediaUrl,
                     undefined, Ts}
                end,
                [id, chat_id, from_user, kind, text, media_url, reply_to, ts]),
            ok;
        _ ->
            ok
    end.

%% Backfill PINs for users registered before the PIN feature.
ensure_pins_for_existing() ->
    Users = mnesia:dirty_all_keys(users),
    lists:foreach(
        fun(U) ->
            case mnesia:dirty_read(pins, U) of
                [] -> mnesia:dirty_write({pins, U, tc_contacts:gen_pin()});
                [_] -> ok
            end
        end, Users),
    ok.
