%%%-------------------------------------------------------------------
%%% @doc BBM-style contacts: each user has a unique PIN. Contacts are
%%% added via PIN through a request/accept flow (mutual contacts).
%%%-------------------------------------------------------------------
-module(tc_contacts).
-export([gen_pin/0,
         ensure_pin/1,
         get_pin/1,
         find_by_pin/1,
         list_contacts/1,
         list_requests/1,
         list_sent_requests/1,
         send_request/2,
         accept_request/2,
         decline_request/2,
         remove_contact/2,
         are_contacts/2]).

%% Generate an 8-char uppercase hex PIN, unique across users.
-spec gen_pin() -> binary().
gen_pin() ->
    Pin = string:uppercase(binary:encode_hex(crypto:strong_rand_bytes(4))),
    case mnesia:dirty_match_object({pins, '_', Pin}) of
        [] -> Pin;
        [_] -> gen_pin() % collision: retry (astronomically rare)
    end.

-spec ensure_pin(binary()) -> binary().
ensure_pin(Username) ->
    case mnesia:dirty_read(pins, Username) of
        [{pins, Username, Pin}] -> Pin;
        [] ->
            Pin = gen_pin(),
            mnesia:dirty_write({pins, Username, Pin}),
            Pin
    end.

-spec get_pin(binary()) -> binary() | undefined.
get_pin(Username) ->
    case mnesia:dirty_read(pins, Username) of
        [{pins, Username, Pin}] -> Pin;
        [] -> undefined
    end.

-spec find_by_pin(binary()) -> {ok, binary()} | error.
find_by_pin(Pin) ->
    Normal = string:uppercase(string:trim(Pin)),
    case mnesia:dirty_match_object({pins, '_', Normal}) of
        [{pins, Username, _}] -> {ok, Username};
        [] -> error
    end.

%% Usernames in Username's contact list.
-spec list_contacts(binary()) -> [binary()].
list_contacts(Username) ->
    [C || {contacts, O, C} <- mnesia:dirty_match_object({contacts, Username, '_'}),
          O =:= Username].

%% Incoming pending requests: [{from, ts}].
-spec list_requests(binary()) -> [{binary(), integer()}].
list_requests(Username) ->
    [{F, Ts} || {contact_requests, F, T, Ts}
                <- mnesia:dirty_match_object({contact_requests, '_', Username, '_'}),
                T =:= Username].

%% Outgoing pending requests: [username].
-spec list_sent_requests(binary()) -> [binary()].
list_sent_requests(Username) ->
    [T || {contact_requests, F, T, _}
          <- mnesia:dirty_match_object({contact_requests, Username, '_', '_'}),
          F =:= Username].

-spec are_contacts(binary(), binary()) -> boolean().
are_contacts(A, B) ->
    mnesia:dirty_match_object({contacts, A, B}) =/= [].

%% Send a contact request to the user owning Pin.
%% Returns {ok, To} for realtime notification.
-spec send_request(binary(), binary())
        -> {ok, binary()} | {error, atom()}.
send_request(From, Pin) ->
    case find_by_pin(Pin) of
        error -> {error, unknown_pin};
        {ok, From} -> {error, cannot_add_self};
        {ok, To} ->
            case are_contacts(From, To) of
                true -> {error, already_contacts};
                false ->
                    case has_pending(From, To) orelse has_pending(To, From) of
                        true -> {error, request_pending};
                        false ->
                            Ts = erlang:system_time(second),
                            mnesia:dirty_write({contact_requests, From, To, Ts}),
                            {ok, To}
                    end
            end
    end.

has_pending(From, To) ->
    mnesia:dirty_match_object({contact_requests, From, To, '_'}) =/= [].

%% Accept an incoming request: request is removed, contacts are mutual.
-spec accept_request(binary(), binary()) -> ok | {error, atom()}.
accept_request(To, From) ->
    case has_pending(From, To) of
        false -> {error, not_found};
        true ->
            Objs = mnesia:dirty_match_object({contact_requests, From, To, '_'}),
            [mnesia:dirty_delete_object(O) || O <- Objs],
            mnesia:dirty_write({contacts, From, To}),
            mnesia:dirty_write({contacts, To, From}),
            ok
    end.

-spec decline_request(binary(), binary()) -> ok.
decline_request(To, From) ->
    Objs = mnesia:dirty_match_object({contact_requests, From, To, '_'}),
    [mnesia:dirty_delete_object(O) || O <- Objs],
    ok.

-spec remove_contact(binary(), binary()) -> ok.
remove_contact(A, B) ->
    [mnesia:dirty_delete_object(O)
     || O <- mnesia:dirty_match_object({contacts, A, B})],
    [mnesia:dirty_delete_object(O)
     || O <- mnesia:dirty_match_object({contacts, B, A})],
    ok.
