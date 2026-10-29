#!/usr/bin/env bash
set -euo pipefail
: "${RESTORE_CONFIRM:?Defina RESTORE_CONFIRM=ISOLATED_DATABASE somente para um banco isolado vazio}"
if [[ "$RESTORE_CONFIRM" != ISOLATED_DATABASE ]]; then printf 'Restauração bloqueada: destino precisa ser isolado.\n' >&2;exit 1;fi
: "${PGHOST:?Configure o host do banco de teste}"
: "${PGUSER:?Configure o usuário do banco de teste}"
: "${PGPASSWORD:?Configure a senha do banco de teste}"
: "${BACKUP_PASSPHRASE:?Configure a senha de descriptografia}"
archive="${1:?Informe o arquivo .dump.enc}"
export PGDATABASE="${PGDATABASE:-postgres}" PGPORT="${PGPORT:-5432}" PGSSLMODE="${PGSSLMODE:-require}"
python3 scripts/backup-auth.py check "$archive"
sha256sum --check "$archive.sha256"
if [[ "$(psql -X -At -c "select exists(select 1 from pg_namespace where nspname='app_private')")" == t ]]; then printf 'Destino já contém o aplicativo. Use um banco isolado vazio.\n' >&2;exit 1;fi
# Não usa --clean: nenhum objeto existente é apagado.
openssl enc -d -aes-256-cbc -pbkdf2 -iter 600000 -pass env:BACKUP_PASSPHRASE -in "$archive" \
 | pg_restore --no-owner --no-acl --exit-on-error --single-transaction
psql -X --set=ON_ERROR_STOP=1 --file=supabase/restore-grants.sql >/dev/null
psql -X --set=ON_ERROR_STOP=1 --file=tests/sql/integrity.sql
printf 'Restauração e verificações SQL concluídas no ambiente isolado. Valide também Auth e os quatro fluxos antes de qualquer corte.\n'
