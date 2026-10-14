%%%-------------------------------------------------------------------
%%% @doc User profiles: bio/status text shown on the profile page.
%%%-------------------------------------------------------------------
-module(tc_profile).
-export([get_bio/1, set_bio/2]).

-spec get_bio(binary()) -> binary().
get_bio(Username) ->
    case mnesia:dirty_read(profiles, Username) of
        [{profiles, Username, Bio}] -> Bio;
        [] -> <<>>
    end.

-spec set_bio(binary(), binary()) -> ok | {error, invalid_input}.
set_bio(Username, Bio) when is_binary(Bio), byte_size(Bio) =< 160 ->
    mnesia:dirty_write({profiles, Username, Bio}),
    ok;
set_bio(_, _) ->
    {error, invalid_input}.
