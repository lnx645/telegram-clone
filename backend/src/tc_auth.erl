%%%-------------------------------------------------------------------
%%% @doc Authentication: registration, login, token verification.
%%% Passwords are stored as salted SHA-256 hashes. Tokens are random
%%% 24-byte values mapped to usernames in the tokens table.
%%%-------------------------------------------------------------------
-module(tc_auth).
-export([register/2, login/2, verify/1, logout/1]).

-spec register(binary(), binary()) -> {ok, binary()} | {error, atom()}.
register(Username, Password) ->
    case valid_cred(Username, Password) of
        false ->
            {error, invalid_input};
        true ->
            Salt = crypto:strong_rand_bytes(16),
            Hash = hash_password(Password, Salt),
            tc_db:txn(fun() ->
                case mnesia:read(users, Username) of
                    [] ->
                        Token = new_token(),
                        mnesia:write({users, Username, Hash, Salt}),
                        mnesia:write({tokens, Token, Username}),
                        mnesia:write({pins, Username, tc_contacts:gen_pin()}),
                        {ok, Token};
                    [_] ->
                        {error, username_taken}
                end
            end)
    end.

-spec login(binary(), binary()) -> {ok, binary()} | {error, atom()}.
login(Username, Password) ->
    tc_db:txn(fun() ->
        case mnesia:read(users, Username) of
            [{users, Username, Hash, Salt}] ->
                case hash_password(Password, Salt) =:= Hash of
                    true ->
                        Token = new_token(),
                        mnesia:write({tokens, Token, Username}),
                        {ok, Token};
                    false ->
                        {error, bad_credentials}
                end;
            [] ->
                {error, bad_credentials}
        end
    end).

-spec verify(binary()) -> {ok, binary()} | {error, unauthorized}.
verify(Token) when is_binary(Token), byte_size(Token) > 0 ->
    case mnesia:dirty_read(tokens, Token) of
        [{tokens, Token, Username}] -> {ok, Username};
        [] -> {error, unauthorized}
    end;
verify(_) ->
    {error, unauthorized}.

-spec logout(binary()) -> ok.
logout(Token) ->
    mnesia:dirty_delete(tokens, Token),
    ok.

%%-------------------------------------------------------------------
%% Internal
%%-------------------------------------------------------------------
hash_password(Password, Salt) ->
    crypto:hash(sha256, <<Salt/binary, Password/binary>>).

new_token() ->
    base64:encode(crypto:strong_rand_bytes(24)).

valid_cred(U, P) when is_binary(U), is_binary(P) ->
    byte_size(U) >= 3 andalso byte_size(U) =< 32 andalso
    byte_size(P) >= 4 andalso byte_size(P) =< 128;
valid_cred(_, _) ->
    false.
