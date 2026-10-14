%%%-------------------------------------------------------------------
%%% @doc Centralized realtime push notifications over websocket.
%%% Events: message, typing, receipt, presence, contact_request,
%%%         contact_accepted, new_status, group_updated,
%%%         reaction, message_deleted.
%%%-------------------------------------------------------------------
-module(tc_notify).
-export([members/2, user/2, contacts/2]).

%% Push Event (map, will be JSON-encoded) to WS sessions of Usernames.
-spec members([binary()], map()) -> ok.
members(Usernames, Event) ->
    Payload = jsx:encode(Event),
    [Pid ! {tc_push, Payload}
     || U <- lists:usort(Usernames),
        Pid <- pg:get_members({tc_ws, U})],
    ok.

-spec user(binary(), map()) -> ok.
user(Username, Event) ->
    members([Username], Event).

%% Push to all of Username's contacts (presence, status updates).
-spec contacts(binary(), map()) -> ok.
contacts(Username, Event) ->
    members(tc_contacts:list_contacts(Username), Event).
