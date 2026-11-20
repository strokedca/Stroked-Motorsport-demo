#!/bin/sh
# An empty, offline cluster: deliberately bypass the image's Supabase defaults.
set -eu
umask 077
mkdir -p /tmp/stroked-pg
initdb -D /tmp/stroked-pg -U supabase_admin --auth-local=trust --auth-host=reject --encoding=UTF8 --locale=C >/dev/null
printf '#!/bin/sh\ncat /restore/vault-root-key.txt\nprintf "\\n"\n' > /tmp/stroked-getkey
chmod 700 /tmp/stroked-getkey
exec postgres -D /tmp/stroked-pg \
  -c listen_addresses='' -c unix_socket_directories=/tmp \
  -c shared_preload_libraries=supabase_vault,pg_cron \
  -c vault.getkey_script=/tmp/stroked-getkey \
  -c cron.database_name=postgres -c cron.launch_active_jobs=off \
  -c max_connections=20 -c shared_buffers=128MB \
  -c log_statement=none -c log_min_error_statement=panic
