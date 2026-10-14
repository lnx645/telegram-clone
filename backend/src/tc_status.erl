%%%-------------------------------------------------------------------
%%% @doc WhatsApp-style Status: ephemeral posts (24h) visible to
%%% the poster's contacts. Kinds: text (with bg color), image, video.
%%%-------------------------------------------------------------------
-module(tc_status).
-export([post/5,
         feed/1,
         my_status/1,
         delete/2,
         mark_viewed/2]).

-define(TTL, 86400). % 24 hours
-define(BG_COLORS, [<<"#2aabee">>, <<"#7b5cff">>, <<"#e13c5a">>,
                    <<"#1faa6b">>, <<"#f59e0b">>, <<"#0e1621">>]).

%% Post a status. Returns {ok, Id}.
-spec post(binary(), text | image | video, binary() | undefined,
           binary() | undefined, binary() | undefined)
        -> {ok, integer()} | {error, atom()}.
post(Username, text, Text, _, BgColor)
        when is_binary(Text), byte_size(Text) > 0, byte_size(Text) =< 500 ->
    Bg = case lists:member(BgColor, ?BG_COLORS) of
             true -> BgColor;
             false -> hd(?BG_COLORS)
         end,
    do_post(Username, text, Text, undefined, Bg);
post(Username, Kind, _, MediaUrl, _)
        when (Kind =:= image orelse Kind =:= video),
             is_binary(MediaUrl) ->
    case binary:match(MediaUrl, <<"/uploads/">>) =:= {0, 9} of
        true -> do_post(Username, Kind, <<>>, MediaUrl, undefined);
        false -> {error, invalid_input}
    end;
post(_, _, _, _, _) ->
    {error, invalid_input}.

do_post(Username, Kind, Text, MediaUrl, BgColor) ->
    Id = erlang:unique_integer([monotonic, positive]),
    Ts = erlang:system_time(second),
    mnesia:dirty_write({status_posts, Id, Username, Kind, Text, MediaUrl,
                        BgColor, Ts, Ts + ?TTL}),
    {ok, Id}.

%% Feed for Username: contacts' statuses grouped by user, unviewed first.
%% Expired posts are cleaned up lazily.
-spec feed(binary()) -> [map()].
feed(Username) ->
    Now = erlang:system_time(second),
    prune_expired(Now),
    Contacts = tc_contacts:list_contacts(Username),
    Users = lists:filtermap(
        fun(C) ->
            Posts = live_posts(C, Now),
            case Posts of
                [] -> false;
                _ ->
                    Viewed = lists:all(
                        fun(P) -> has_viewed(element(2, P), Username) end,
                        Posts),
                    {true, #{username => C,
                             presence => tc_presence:get(C),
                             statuses => [status_to_map(P, Username)
                                          || P <- Posts],
                             all_viewed => Viewed}}
            end
        end, Contacts),
    %% Unviewed first, then by latest post.
    lists:sort(
        fun(#{all_viewed := V1}, #{all_viewed := V2}) ->
            {V1, V2} =:= {false, true}
        end, Users).

%% Username's own live statuses.
-spec my_status(binary()) -> [map()].
my_status(Username) ->
    Now = erlang:system_time(second),
    prune_expired(Now),
    [status_to_map(P, Username) || P <- live_posts(Username, Now)].

%% Delete own status.
-spec delete(binary(), integer()) -> ok | {error, atom()}.
delete(Username, Id) ->
    case mnesia:dirty_read(status_posts, Id) of
        [{status_posts, Id, Username, _, _, _, _, _, _}] ->
            mnesia:dirty_delete(status_posts, Id),
            Views = mnesia:dirty_match_object({status_views, Id, '_'}),
            [mnesia:dirty_delete_object(V) || V <- Views],
            ok;
        [_] -> {error, forbidden};
        [] -> {error, not_found}
    end.

%% Record that Viewer saw a status.
-spec mark_viewed(integer(), binary()) -> ok.
mark_viewed(Id, Viewer) ->
    case mnesia:dirty_read(status_posts, Id) of
        [{status_posts, Id, Owner, _, _, _, _, _, _}] when Owner =/= Viewer ->
            case tc_contacts:are_contacts(Owner, Viewer) of
                true ->
                    mnesia:dirty_write({status_views, Id, Viewer}),
                    ok;
                false -> ok
            end;
        _ -> ok
    end.

%%-------------------------------------------------------------------
%% Internal
%%-------------------------------------------------------------------
live_posts(Username, Now) ->
    All = mnesia:dirty_match_object(
            {status_posts, '_', Username, '_', '_', '_', '_', '_', '_'}),
    Live = [P || {status_posts, _, _, _, _, _, _, _, Exp} = P <- All,
                 Exp > Now],
    lists:reverse(lists:keysort(8, Live)). % ts is element 8

prune_expired(Now) ->
    Match = [{{status_posts, '$1', '_', '_', '_', '_', '_', '_', '$2'},
              [{'<', '$2', Now}],
              ['$1']}],
    Ids = mnesia:dirty_select(status_posts, Match),
    lists:foreach(
        fun(Id) ->
            mnesia:dirty_delete(status_posts, Id),
            Views = mnesia:dirty_match_object({status_views, Id, '_'}),
            [mnesia:dirty_delete_object(V) || V <- Views]
        end, Ids).

has_viewed(Id, Viewer) ->
    mnesia:dirty_match_object({status_views, Id, Viewer}) =/= [].

status_to_map({status_posts, Id, Username, Kind, Text, MediaUrl, BgColor,
               Ts, Expires},
              Viewer) ->
    Views = mnesia:dirty_match_object({status_views, Id, '_'}),
    #{id => Id,
      username => Username,
      kind => atom_to_binary(Kind, utf8),
      text => Text,
      media_url => case MediaUrl of undefined -> null; _ -> MediaUrl end,
      bg_color => case BgColor of undefined -> null; _ -> BgColor end,
      ts => Ts,
      expires => Expires,
      views => length(Views),
      viewed_by_me => has_viewed(Id, Viewer)}.
