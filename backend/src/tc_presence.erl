%%%-------------------------------------------------------------------
%%% @doc Presence tracking (online / last seen), backed by a
%%% ram_copies Mnesia table. Updated on websocket connect/disconnect.
%%%-------------------------------------------------------------------
-module(tc_presence).
-export([online/1, offline/1, get/1]).

-spec online(binary()) -> ok.
online(Username) ->
    mnesia:dirty_write({presence, Username, true, erlang:system_time(second)}),
    ok.

-spec offline(binary()) -> ok.
offline(Username) ->
    mnesia:dirty_write({presence, Username, false, erlang:system_time(second)}),
    ok.

%% Returns #{online => bool()} plus last_seen (unix ts) when offline.
%% last_seen is null when never seen.
-spec get(binary()) -> map().
get(Username) ->
    case mnesia:dirty_read(presence, Username) of
        [{presence, Username, true, _}] ->
            #{online => true};
        [{presence, Username, false, Ts}] ->
            #{online => false, last_seen => Ts};
        [] ->
            #{online => false, last_seen => null}
    end.
