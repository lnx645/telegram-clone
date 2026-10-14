%%%-------------------------------------------------------------------
%%% @doc Chat domain logic: direct chats, group chats (roles:
%%% admin > moderator > member), messages, reactions, receipts.
%%%-------------------------------------------------------------------
-module(tc_chat).
-export([list_chats/1,
         get_or_create_chat/2,
         create_group/3,
         get_chat/2,
         get_group_info/2,
         chat_members/1,
         chat_member_roles/1,
         get_role/2,
         list_public_groups/0,
         join_group/2,
         update_group/4,
         add_member/3,
         remove_member/3,
         set_role/4,
         leave_group/2,
         delete_group/2,
         list_messages/2,
         send_message/6,
         delete_message/4,
         add_reaction/4,
         remove_reaction/2,
         mark_read/2,
         mark_delivered/2,
         message_status/2]).

%% All chats of Username (direct + groups), newest first.
-spec list_chats(binary()) -> [map()].
list_chats(Username) ->
    DirectMatch = [{{chats, '$1', direct, '_', '_', '$2', '$3', '$4'},
                    [{'orelse', {'=:=', '$2', Username},
                               {'=:=', '$3', Username}}],
                    ['$_']}],
    Directs = mnesia:dirty_select(chats, DirectMatch),
    GroupIds = lists:usort(
        [Cid || {chat_members, Cid, U, _}
                <- mnesia:dirty_match_object({chat_members, '_', Username, '_'}),
                U =:= Username]),
    Groups = lists:filtermap(
        fun(Cid) ->
            case mnesia:dirty_read(chats, Cid) of
                [C] -> {true, C};
                [] -> false
            end
        end, GroupIds),
    Sorted = lists:reverse(lists:keysort(8, Directs ++ Groups)),
    [chat_to_map(C, Username) || C <- Sorted].

%% Find the direct chat between A and B, creating it when missing.
-spec get_or_create_chat(binary(), binary()) -> {ok, integer()} | {error, atom()}.
get_or_create_chat(A, A) ->
    {error, cannot_chat_with_self};
get_or_create_chat(A, B) ->
    {U1, U2} = if A < B -> {A, B}; true -> {B, A} end,
    tc_db:txn(fun() ->
        Match = [{{chats, '$1', direct, '_', '_', U1, U2, '_'}, [], ['$1']}],
        case mnesia:select(chats, Match) of
            [Id | _] -> {ok, Id};
            [] ->
                Id = erlang:unique_integer([monotonic, positive]),
                Ts = erlang:system_time(second),
                mnesia:write({chats, Id, direct, undefined, private, U1, U2, Ts}),
                {ok, Id}
        end
    end).

%% Create a group chat. Creator becomes admin.
-spec create_group(binary(), binary(), [binary()])
        -> {ok, integer()} | {error, atom()}.
create_group(Creator, Name, Members)
        when is_binary(Name), byte_size(Name) > 0, byte_size(Name) =< 60,
             is_list(Members) ->
    Clean = lists:usort([M || M <- [Creator | Members],
                              is_binary(M), M =/= <<>>]),
    case length(Clean) >= 2 of
        false -> {error, invalid_input};
        true ->
            case lists:all(fun(U) -> mnesia:dirty_read(users, U) =/= [] end, Clean) of
                false -> {error, unknown_user};
                true ->
                    tc_db:txn(fun() ->
                        Id = erlang:unique_integer([monotonic, positive]),
                        Ts = erlang:system_time(second),
                        mnesia:write({chats, Id, group, Name, private,
                                      <<>>, <<>>, Ts}),
                        mnesia:write({chat_members, Id, Creator, admin}),
                        [mnesia:write({chat_members, Id, U, member})
                         || U <- Clean, U =/= Creator],
                        {ok, Id}
                    end)
            end
    end;
create_group(_, _, _) ->
    {error, invalid_input}.

%% Chat info for a member.
-spec get_chat(integer(), binary()) -> {ok, map()} | {error, atom()}.
get_chat(ChatId, Username) ->
    case mnesia:dirty_read(chats, ChatId) of
        [C] ->
            case is_member(C, Username) of
                true -> {ok, chat_to_map(C, Username)};
                false -> {error, forbidden}
            end;
        [] -> {error, not_found}
    end.

%% Full group info with member roles (for the group info screen).
-spec get_group_info(integer(), binary()) -> {ok, map()} | {error, atom()}.
get_group_info(ChatId, Username) ->
    case mnesia:dirty_read(chats, ChatId) of
        [{chats, ChatId, group, Name, Visibility, _, _, UpdatedAt}] ->
            case get_role(ChatId, Username) of
                none -> {error, forbidden};
                MyRole ->
                    Members = chat_member_roles(ChatId),
                    {ok, #{id => ChatId, type => <<"group">>, name => Name,
                           visibility => Visibility, my_role => MyRole,
                           members => Members, updated_at => UpdatedAt}}
            end;
        [_] -> {error, not_found};
        [] -> {error, not_found}
    end.

%% All usernames in a chat.
-spec chat_members(integer()) -> [binary()].
chat_members(ChatId) ->
    case mnesia:dirty_read(chats, ChatId) of
        [{chats, _, direct, _, _, U1, U2, _}] -> [U1, U2];
        [{chats, _, group, _, _, _, _, _}] ->
            [U || {chat_members, _, U, _}
                  <- mnesia:dirty_match_object({chat_members, ChatId, '_', '_'})];
        [] -> []
    end.

%% Members with roles: [#{username, role}].
-spec chat_member_roles(integer()) -> [map()].
chat_member_roles(ChatId) ->
    Objs = mnesia:dirty_match_object({chat_members, ChatId, '_', '_'}),
    Sorted = lists:sort(
        fun({_, _, _, R1}, {_, _, _, R2}) ->
            role_rank(R1) =< role_rank(R2)
        end, Objs),
    [#{username => U, role => R} || {chat_members, _, U, R} <- Sorted].

role_rank(admin) -> 1;
role_rank(moderator) -> 2;
role_rank(member) -> 3.

%% Role of Username in a group chat (none if not a member).
-spec get_role(integer(), binary()) -> admin | moderator | member | none.
get_role(ChatId, Username) ->
    case mnesia:dirty_match_object({chat_members, ChatId, Username, '_'}) of
        [{chat_members, _, _, Role}] -> Role;
        [] -> none
    end.

%% Public groups joinable by anyone.
-spec list_public_groups() -> [map()].
list_public_groups() ->
    Match = [{{chats, '$1', group, '$2', public, '_', '_', '_'},
              [], ['$_']}],
    Groups = mnesia:dirty_select(chats, Match),
    [#{id => Id, name => Name,
       member_count => length(chat_members(Id))}
     || {chats, Id, group, Name, public, _, _, _} <- Groups].

%% Join a public group.
-spec join_group(integer(), binary()) -> ok | {error, atom()}.
join_group(ChatId, Username) ->
    case mnesia:dirty_read(chats, ChatId) of
        [{chats, ChatId, group, _, public, _, _, _}] ->
            case get_role(ChatId, Username) of
                none ->
                    mnesia:dirty_write({chat_members, ChatId, Username, member}),
                    ok;
                _ -> {error, already_member}
            end;
        [{chats, ChatId, group, _, private, _, _, _}] ->
            {error, private_group};
        _ -> {error, not_found}
    end.

%% Update group name/visibility (admin only).
-spec update_group(integer(), binary(), binary() | undefined,
                   private | public | undefined)
        -> ok | {error, atom()}.
update_group(ChatId, By, Name, Visibility) ->
    case mnesia:dirty_read(chats, ChatId) of
        [{chats, ChatId, group, OldName, OldVis, U1, U2, Ts}] ->
            case get_role(ChatId, By) of
                admin ->
                    NewName = case Name of
                        undefined -> OldName;
                        N when is_binary(N), byte_size(N) > 0,
                               byte_size(N) =< 60 -> N;
                        _ -> OldName
                    end,
                    NewVis = case Visibility of
                        public -> public;
                        private -> private;
                        undefined -> OldVis
                    end,
                    mnesia:dirty_write(
                        {chats, ChatId, group, NewName, NewVis, U1, U2, Ts}),
                    ok;
                _ -> {error, forbidden}
            end;
        _ -> {error, not_found}
    end.

%% Add a member (admin/moderator).
-spec add_member(integer(), binary(), binary()) -> ok | {error, atom()}.
add_member(ChatId, By, Username) ->
    case mnesia:dirty_read(chats, ChatId) of
        [{chats, ChatId, group, _, _, _, _, _}] ->
            case get_role(ChatId, By) of
                admin -> do_add_member(ChatId, Username);
                moderator -> do_add_member(ChatId, Username);
                _ -> {error, forbidden}
            end;
        _ -> {error, not_found}
    end.

do_add_member(ChatId, Username) ->
    case mnesia:dirty_read(users, Username) of
        [] -> {error, unknown_user};
        [_] ->
            case get_role(ChatId, Username) of
                none ->
                    mnesia:dirty_write({chat_members, ChatId, Username, member}),
                    ok;
                _ -> {error, already_member}
            end
    end.

%% Remove a member. Admin can remove anyone (except self via this route);
%% moderator can only remove regular members.
-spec remove_member(integer(), binary(), binary()) -> ok | {error, atom()}.
remove_member(ChatId, By, Username) when By =:= Username ->
    {error, use_leave};
remove_member(ChatId, By, Username) ->
    case mnesia:dirty_read(chats, ChatId) of
        [{chats, ChatId, group, _, _, _, _, _}] ->
            ByRole = get_role(ChatId, By),
            TargetRole = get_role(ChatId, Username),
            case {ByRole, TargetRole} of
                {admin, admin} -> {error, forbidden};
                {admin, _} when TargetRole =/= none ->
                    do_remove_member(ChatId, Username);
                {moderator, member} ->
                    do_remove_member(ChatId, Username);
                _ -> {error, forbidden}
            end;
        _ -> {error, not_found}
    end.

do_remove_member(ChatId, Username) ->
    Objs = mnesia:dirty_match_object({chat_members, ChatId, Username, '_'}),
    [mnesia:dirty_delete_object(O) || O <- Objs],
    ok.

%% Change a member's role (admin only). Cannot change own role or
%% another admin's role through this route.
-spec set_role(integer(), binary(), binary(), admin | moderator | member)
        -> ok | {error, atom()}.
set_role(ChatId, By, Username, Role)
        when Role =:= admin; Role =:= moderator; Role =:= member ->
    case mnesia:dirty_read(chats, ChatId) of
        [{chats, ChatId, group, _, _, _, _, _}] ->
            case get_role(ChatId, By) of
                admin when By =/= Username ->
                    case get_role(ChatId, Username) of
                        none -> {error, not_found};
                        admin -> {error, forbidden};
                        _ ->
                            do_remove_member(ChatId, Username),
                            mnesia:dirty_write({chat_members, ChatId, Username, Role}),
                            ok
                    end;
                _ -> {error, forbidden}
            end;
        _ -> {error, not_found}
    end;
set_role(_, _, _, _) ->
    {error, invalid_input}.

%% Leave a group. If the last admin leaves, the oldest member is promoted.
-spec leave_group(integer(), binary()) -> ok | {error, atom()}.
leave_group(ChatId, Username) ->
    case mnesia:dirty_read(chats, ChatId) of
        [{chats, ChatId, group, _, _, _, _, _}] ->
            case get_role(ChatId, Username) of
                none -> {error, not_found};
                Role ->
                    do_remove_member(ChatId, Username),
                    case Role of
                        admin -> ensure_admin(ChatId);
                        _ -> ok
                    end,
                    ok
            end;
        _ -> {error, not_found}
    end.

ensure_admin(ChatId) ->
    Admins = [U || {chat_members, _, U, admin}
                   <- mnesia:dirty_match_object({chat_members, ChatId, '_', admin})],
    case Admins of
        [] ->
            case mnesia:dirty_match_object({chat_members, ChatId, '_', '_'}) of
                [{chat_members, _, U, _} | _] ->
                    do_remove_member(ChatId, U),
                    mnesia:dirty_write({chat_members, ChatId, U, admin}),
                    ok;
                [] -> ok % empty group
            end;
        _ -> ok
    end.

%% Delete a group entirely (admin only).
-spec delete_group(integer(), binary()) -> ok | {error, atom()}.
delete_group(ChatId, By) ->
    case mnesia:dirty_read(chats, ChatId) of
        [{chats, ChatId, group, _, _, _, _, _}] ->
            case get_role(ChatId, By) of
                admin ->
                    tc_db:txn(fun() ->
                        mnesia:delete({chats, ChatId}),
                        Msgs = mnesia:match_object(
                                 {messages, '_', ChatId, '_', '_', '_',
                                  '_', '_', '_'}),
                        [begin
                             Id = element(2, M),
                             mnesia:delete({messages, Id}),
                             [mnesia:delete_object(O)
                              || O <- mnesia:match_object({reactions, Id, '_', '_'})],
                             [mnesia:delete_object(O)
                              || O <- mnesia:match_object({receipts, Id, '_', '_'})],
                             [mnesia:delete_object(O)
                              || O <- mnesia:match_object({hidden, Id, '_'})]
                         end || M <- Msgs],
                        [mnesia:delete_object(O)
                         || O <- mnesia:match_object({chat_members, ChatId, '_', '_'})],
                        ok
                    end);
                _ -> {error, forbidden}
            end;
        _ -> {error, not_found}
    end.

%% Full history of a chat, oldest first. Marks peer messages as read.
%% Returns {ok, Messages, ReadSenders} for receipt push.
-spec list_messages(integer(), binary())
        -> {ok, [map()], [binary()]} | {error, atom()}.
list_messages(ChatId, Username) ->
    case mnesia:dirty_read(chats, ChatId) of
        [C] ->
            case is_member(C, Username) of
                true ->
                    {ok, Senders} = mark_read(ChatId, Username),
                    Msgs = visible_messages(ChatId, Username),
                    {ok, [msg_to_map(M, Username) || M <- Msgs], Senders};
                false -> {error, forbidden}
            end;
        [] -> {error, not_found}
    end.

%% Store a message; returns the message map plus members to notify.
-spec send_message(integer(), binary(), text | sticker | image | voice | video,
                   binary() | undefined, binary() | undefined,
                   integer() | undefined)
        -> {ok, map(), [binary()]} | {error, atom()}.
send_message(ChatId, From, Kind, Text, MediaUrl, ReplyTo) ->
    case mnesia:dirty_read(chats, ChatId) of
        [C] ->
            case is_member(C, From) of
                false -> {error, forbidden};
                true ->
                    case valid_message(Kind, Text, MediaUrl)
                         andalso valid_reply(ChatId, ReplyTo) of
                        true -> do_send(ChatId, From, Kind, Text, MediaUrl, ReplyTo);
                        false -> {error, invalid_input}
                    end
            end;
        [] -> {error, not_found}
    end.

%% Delete a message: 'me' hides it for the requester, 'everyone'
%% replaces it with a tombstone (sender only).
-spec delete_message(integer(), integer(), binary(), me | everyone)
        -> ok | {error, atom()}.
delete_message(ChatId, MsgId, Username, Mode) ->
    case mnesia:dirty_read(chats, ChatId) of
        [C] ->
            case is_member(C, Username) of
                false -> {error, forbidden};
                true -> do_delete(ChatId, MsgId, Username, Mode)
            end;
        [] -> {error, not_found}
    end.

%% Toggle an emoji reaction on a message (one per user).
-spec add_reaction(integer(), integer(), binary(), binary())
        -> ok | {error, atom()}.
add_reaction(ChatId, MsgId, Username, Emoji) ->
    case valid_emoji(Emoji) of
        false -> {error, invalid_input};
        true ->
            case mnesia:dirty_read(messages, MsgId) of
                [{messages, MsgId, ChatId, _, _, _, _, _, _}] ->
                    case mnesia:dirty_read(chats, ChatId) of
                        [C] ->
                            case is_member(C, Username) of
                                true ->
                                    Old = mnesia:dirty_match_object(
                                            {reactions, MsgId, Username, '_'}),
                                    [mnesia:dirty_delete_object(O) || O <- Old],
                                    mnesia:dirty_write(
                                        {reactions, MsgId, Username, Emoji}),
                                    ok;
                                false -> {error, forbidden}
                            end;
                        [] -> {error, not_found}
                    end;
                _ -> {error, not_found}
            end
    end.

-spec remove_reaction(integer(), binary()) -> ok.
remove_reaction(MsgId, Username) ->
    Objs = mnesia:dirty_match_object({reactions, MsgId, Username, '_'}),
    [mnesia:dirty_delete_object(O) || O <- Objs],
    ok.

%% Mark all messages in a chat (not from Username) as read by Username.
%% Returns the unique senders whose messages were marked (for receipt push).
-spec mark_read(integer(), binary()) -> {ok, [binary()]}.
mark_read(ChatId, Username) ->
    Msgs = mnesia:dirty_match_object(
             {messages, '_', ChatId, '_', '_', '_', '_', '_', '_'}),
    ToMark = [{Id, From}
              || {messages, Id, _, From, _, _, _, _, _} <- Msgs,
                 From =/= Username,
                 not already_read(Id, Username)],
    lists:foreach(
        fun({Id, _}) ->
            tc_db:txn(fun() ->
                mnesia:delete_object({receipts, Id, Username, delivered}),
                mnesia:delete_object({receipts, Id, Username, read}),
                mnesia:write({receipts, Id, Username, read})
            end)
        end, ToMark),
    {ok, lists:usort([From || {_, From} <- ToMark])}.

already_read(Id, Username) ->
    mnesia:dirty_match_object({receipts, Id, Username, read}) =/= [].

%% Record that a message reached a recipient's device.
-spec mark_delivered(integer(), binary()) -> ok.
mark_delivered(MsgId, Username) ->
    case mnesia:dirty_match_object({receipts, MsgId, Username, read}) of
        [_] -> ok;
        [] ->
            case mnesia:dirty_match_object({receipts, MsgId, Username, delivered}) of
                [_] -> ok;
                [] -> mnesia:dirty_write({receipts, MsgId, Username, delivered}), ok
            end
    end.

%% Delivery status of a message from the sender's perspective.
-spec message_status(integer(), binary()) -> binary().
message_status(MsgId, _Sender) ->
    Receipts = mnesia:dirty_match_object({receipts, MsgId, '_', '_'}),
    HasRead = lists:any(fun({receipts, _, _, read}) -> true;
                           (_) -> false end, Receipts),
    HasDelivered = lists:any(fun({receipts, _, _, delivered}) -> true;
                                (_) -> false end, Receipts),
    if HasRead -> <<"read">>;
       HasDelivered -> <<"delivered">>;
       true -> <<"sent">>
    end.

%%-------------------------------------------------------------------
%% Internal
%%-------------------------------------------------------------------
is_member({chats, _, direct, _, _, U1, U2, _}, Username) ->
    U1 =:= Username orelse U2 =:= Username;
is_member({chats, Id, group, _, _, _, _, _}, Username) ->
    mnesia:dirty_match_object({chat_members, Id, Username, '_'}) =/= [].

valid_message(text, Text, _) ->
    is_binary(Text) andalso byte_size(Text) > 0 andalso byte_size(Text) =< 4096;
valid_message(sticker, _, Url) ->
    is_binary(Url) andalso binary:match(Url, <<"/stickers/">>) =:= {0, 10};
valid_message(image, _, Url) ->
    is_binary(Url) andalso binary:match(Url, <<"/uploads/">>) =:= {0, 9};
valid_message(video, _, Url) ->
    is_binary(Url) andalso binary:match(Url, <<"/uploads/">>) =:= {0, 9};
valid_message(voice, _, Url) ->
    is_binary(Url) andalso binary:match(Url, <<"/uploads/">>) =:= {0, 9};
valid_message(_, _, _) ->
    false.

valid_reply(_, undefined) -> true;
valid_reply(ChatId, ReplyTo) when is_integer(ReplyTo) ->
    case mnesia:dirty_read(messages, ReplyTo) of
        [{messages, ReplyTo, ChatId, _, _, _, _, _, _}] -> true;
        _ -> false
    end;
valid_reply(_, _) -> false.

valid_emoji(E) when is_binary(E) ->
    byte_size(E) > 0 andalso byte_size(E) =< 12;
valid_emoji(_) -> false.

do_send(ChatId, From, Kind, Text, MediaUrl, ReplyTo) ->
    tc_db:txn(fun() ->
        Id = erlang:unique_integer([monotonic, positive]),
        Ts = erlang:system_time(second),
        Msg = {messages, Id, ChatId, From, Kind, Text, MediaUrl, ReplyTo, Ts},
        mnesia:write(Msg),
        [C] = mnesia:read(chats, ChatId),
        {chats, _, Type, Name, Vis, U1, U2, _} = C,
        mnesia:write({chats, ChatId, Type, Name, Vis, U1, U2, Ts}),
        Members = case Type of
            direct -> if U1 =:= From -> [U2]; true -> [U1] end;
            group ->
                [U || {chat_members, _, U, _}
                      <- mnesia:match_object({chat_members, ChatId, '_', '_'}),
                      U =/= From]
        end,
        {ok, msg_to_map(Msg, From), Members}
    end).

do_delete(ChatId, MsgId, Username, me) ->
    case mnesia:dirty_read(messages, MsgId) of
        [{messages, MsgId, ChatId, _, _, _, _, _, _}] ->
            mnesia:dirty_write({hidden, MsgId, Username}),
            ok;
        _ -> {error, not_found}
    end;
do_delete(ChatId, MsgId, Username, everyone) ->
    case mnesia:dirty_read(messages, MsgId) of
        [{messages, MsgId, ChatId, From, _, _, _, ReplyTo, Ts}] when From =:= Username ->
            Tombstone = {messages, MsgId, ChatId, From, text,
                         <<"Pesan ini telah dihapus">>, undefined, ReplyTo, Ts},
            mnesia:dirty_write(Tombstone),
            ok;
        [{messages, MsgId, ChatId, _, _, _, _, _, _}] ->
            {error, forbidden};
        _ -> {error, not_found}
    end.

visible_messages(ChatId, Username) ->
    Msgs = mnesia:dirty_match_object(
             {messages, '_', ChatId, '_', '_', '_', '_', '_', '_'}),
    Hidden = [Id || {hidden, Id, U}
                    <- mnesia:dirty_match_object({hidden, '_', Username}),
                    U =:= Username],
    Sorted = lists:keysort(9, Msgs),
    [M || {messages, Id, _, _, _, _, _, _, _} = M <- Sorted,
          not lists:member(Id, Hidden)].

chat_to_map({chats, Id, direct, _, _, U1, U2, UpdatedAt}, Username) ->
    Peer = if U1 =:= Username -> U2; true -> U1 end,
    #{id => Id,
      type => <<"direct">>,
      name => null,
      visibility => <<"private">>,
      peer => Peer,
      peer_presence => tc_presence:get(Peer),
      member_count => 2,
      updated_at => UpdatedAt,
      last_message => last_message(Id, Username)};
chat_to_map({chats, Id, group, Name, Visibility, _, _, UpdatedAt}, Username) ->
    Members = [U || {chat_members, _, U, _}
                    <- mnesia:dirty_match_object({chat_members, Id, '_', '_'})],
    #{id => Id,
      type => <<"group">>,
      name => Name,
      visibility => Visibility,
      peer => null,
      peer_presence => null,
      member_count => length(Members),
      my_role => get_role(Id, Username),
      updated_at => UpdatedAt,
      last_message => last_message(Id, Username)}.

last_message(ChatId, Username) ->
    Msgs = visible_messages(ChatId, Username),
    case Msgs of
        [] -> null;
        _ -> msg_to_map(lists:last(Msgs), Username)
    end.

msg_to_map({messages, Id, ChatId, From, Kind, Text, MediaUrl, ReplyTo, Ts},
           Viewer) ->
    Base = #{id => Id,
             chat_id => ChatId,
             from => From,
             kind => atom_to_binary(Kind, utf8),
             text => Text,
             media_url => case MediaUrl of undefined -> null; _ -> MediaUrl end,
             reply_to => reply_summary(ReplyTo),
             reactions => reaction_summary(Id, Viewer),
             ts => Ts},
    case Viewer =:= From of
        true -> Base#{status => message_status(Id, Viewer)};
        false -> Base
    end.

reply_summary(undefined) -> null;
reply_summary(MsgId) ->
    case mnesia:dirty_read(messages, MsgId) of
        [{messages, MsgId, _, From, Kind, Text, _, _, _}] ->
            #{from => From,
              kind => atom_to_binary(Kind, utf8),
              text => case Kind of
                          text -> snippet(Text);
                          image -> <<"Foto">>;
                          video -> <<"Video">>;
                          voice -> <<"Pesan suara">>;
                          sticker -> <<"Stiker">>
                      end};
        [] -> null
    end.

snippet(T) when is_binary(T), byte_size(T) > 60 ->
    <<(binary:part(T, 0, 60))/binary, "...">>;
snippet(T) -> T.

reaction_summary(MsgId, Viewer) ->
    Objs = mnesia:dirty_match_object({reactions, MsgId, '_', '_'}),
    Grouped = lists:foldl(
        fun({reactions, _, U, E}, Acc) ->
            maps:update_with(E,
                fun({C, Mine}) -> {C + 1, Mine orelse U =:= Viewer} end,
                {1, U =:= Viewer}, Acc)
        end, #{}, Objs),
    [#{emoji => E, count => C, by_me => Mine}
     || {E, {C, Mine}} <- maps:to_list(Grouped)].
