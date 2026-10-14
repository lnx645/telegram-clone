#!/bin/bash
# Telegram Clone startup script (interactive mode workaround)
REL=/root/telegram_clone/backend/_build/default/rel/tc
export BINDIR=/usr/lib64/erlang/erts-14.2.5/bin
exec /usr/lib64/erlang/erts-14.2.5/bin/erlexec \
  -noshell -noinput \
  -name tc@127.0.0.1 -setcookie tc_secret_cookie \
  -pa $REL/lib/tc-0.1.0/ebin \
  -pa $REL/lib/cowboy-2.12.0/ebin \
  -pa $REL/lib/cowlib-2.13.0/ebin \
  -pa $REL/lib/ranch-1.8.0/ebin \
  -pa $REL/lib/jsx-3.1.0/ebin \
  -config $REL/releases/0.1.0/sys.config \
  -eval 'application:ensure_all_started(tc).' \
  -eval 'receive after infinity -> ok end.'
