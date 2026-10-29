#!/usr/bin/env bash
set -euo pipefail
# PGHOST, PGPORT, PGUSER, PGDATABASE e PGPASSWORD devem vir do gerenciador de segredos.
: "${PGHOST:?Configure PGHOST (host direto ou Session Pooler)}"
: "${PGUSER:?Configure PGUSER}"
: "${PGPASSWORD:?Configure PGPASSWORD}"
: "${BACKUP_PASSPHRASE:?Configure BACKUP_PASSPHRASE}"
export PGDATABASE="${PGDATABASE:-postgres}" PGPORT="${PGPORT:-5432}" PGSSLMODE=require
output="${1:-portaria-$(date -u +%Y%m%dT%H%M%SZ).dump.enc}"
umask 077
trap 'rm -f "$output.partial"' EXIT
# Somente esquema/dados do produto e autenticação. Nenhum token de sessão é preservado.
pg_dump --format=custom --no-owner --no-acl --schema=public --schema=app_private --schema=auth \
 --exclude-table-data=auth.sessions --exclude-table-data=auth.refresh_tokens \
 --exclude-table-data=auth.flow_state --exclude-table-data=auth.one_time_tokens \
 --exclude-table-data=auth.audit_log_entries --exclude-table-data=auth.schema_migrations \
 | openssl enc -aes-256-cbc -pbkdf2 -iter 600000 -salt -pass env:BACKUP_PASSPHRASE -out "$output.partial"
mv "$output.partial" "$output"
python3 scripts/backup-auth.py create "$output"
sha256sum "$output" > "$output.sha256"
psql -X --set=ON_ERROR_STOP=1 --command="insert into app_private.backup_runs(status,note) values('success','Cópia criptografada externa gerada; valide a restauração periodicamente.');" >/dev/null
printf 'Backup criptografado criado: %s\n' "$output"
