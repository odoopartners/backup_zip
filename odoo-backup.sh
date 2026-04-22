#!/bin/bash


### Enviroment Variables needed to run the odoo-backup script ###
### that most of them are found in the .env file of the project ###
if [ -z "$DB_ENV_POSTGRES_USER" ]; then
    echo "ERROR: Instalation error, DB_ENV_POSTGRES_USER is not defined"
    exit 1
fi
if [ -z "$HOME" ]; then
    echo "ERROR: Instalation error, HOME is not defined"
    exit 1
fi
if [ -z "$DB_PORT_5432_TCP_ADDR" ]; then
    echo "ERROR: Instalation error, DB_PORT_5432_TCP_ADDR is not defined"
    exit 1
fi
if [ -z "$ODOO_DATA_DIR" ]; then
    echo "ERROR: Instalation error, ODOO_DATA_DIR is not defined"
    exit 1
fi

if [ -z "$DB_ENV_POSTGRES_PASSWORD" ]; then
    echo "ERROR: Instalation error, DB_ENV_POSTGRES_PASSWORD is not defined"
    exit 1
fi

python_bin="$(command -v python3 || command -v python || true)"
if [ -z "$python_bin" ]; then
    echo "ERROR: Instalation error, python3 or python is required"
    exit 1
fi


### Setting date value for the construct name of the backup files ###
NOW=`date '+%Y-%m-%d_%H%M%S'`


### Database name parameter that must be given to the script to generate the backup files of the database given ###
database="$1"
if [ -z "$database" ]; then
    echo "ERROR: No database"
    echo "Usage: $0 <database>"
    exit 1
fi


### Setting logfile value for the backup.log file generated ###
logfile="${database}_${NOW}-backup.log"
backup_name="${database}_${NOW}.zip"
workdir="$HOME/backup/${database}_${NOW}_odoo_sh"

cleanup() {
    if [ -n "${workdir:-}" ] && [ -d "$workdir" ]; then
        rm -rf "$workdir"
    fi
}
trap cleanup EXIT


### Placing us on the backup directory and sending data to the logfile ###
mkdir -p "$HOME/backup"
mkdir -p "$workdir"
cd "$HOME/backup"
echo "BACKUP: DATABASE = $database, TIME = $NOW" > "$logfile"


### Setting the postgress password value ###
db_password=$DB_ENV_POSTGRES_PASSWORD
echo


### Validating the database name given exists for the given postgres user ###
if ! PGPASSWORD="$db_password" /usr/bin/psql -h $DB_PORT_5432_TCP_ADDR -U "$DB_ENV_POSTGRES_USER" -l -F'|' -A "template1" | grep "|$DB_ENV_POSTGRES_USER|" | cut -d'|' -f1 | egrep -q "^$database\$"; then
    echo "ERROR: Database '$database' not found for user '$DB_ENV_POSTGRES_USER'"
    exit 2
fi


### Validating the path for the database name given exists ###
if [ ! -d "$ODOO_DATA_DIR/filestore/$database" ]; then
    echo "ERROR: Filestore '$ODOO_DATA_DIR/filestore/$database' not found"
    exit 3
fi


### Generating the .dump backup file for the given database name ###
echo -n "Backup database: $database ... "
PGPASSWORD="$db_password" /usr/bin/pg_dump --no-owner -v -U "$DB_ENV_POSTGRES_USER" --host "$DB_PORT_5432_TCP_ADDR" -f "$workdir/dump.sql" "$database" >> "$logfile" 2>&1
error=$?
if [ $error -eq 0 ]; then echo "OK"; else echo "ERROR: $error"; exit 4; fi


### Generating Odoo backup metadata when possible ###
echo -n "Backup manifest: $database ... "
PGPASSWORD="$db_password" /usr/bin/psql -h "$DB_PORT_5432_TCP_ADDR" -U "$DB_ENV_POSTGRES_USER" -d "$database" -t -A -o "$workdir/manifest.json" <<'SQL' >> "$logfile" 2>&1
WITH version_data AS (
    SELECT COALESCE(
        (SELECT value FROM ir_config_parameter WHERE key = 'web.base.version' LIMIT 1),
        (SELECT latest_version FROM ir_module_module WHERE name = 'base' LIMIT 1),
        ''
    ) AS version
),
module_data AS (
    SELECT COALESCE(json_object_agg(name, latest_version ORDER BY name), '{}'::json) AS modules
    FROM ir_module_module
    WHERE state = 'installed'
)
SELECT json_build_object(
    'odoo_dump', '1',
    'db_name', current_database(),
    'version', version_data.version,
    'major_version', split_part(version_data.version, '+', 1),
    'pg_version', current_setting('server_version'),
    'modules', module_data.modules
)::text
FROM version_data, module_data;
SQL
error=$?
if [ $error -eq 0 ]; then echo "OK"; else echo "WARNING: manifest.json could not be generated"; rm -f "$workdir/manifest.json"; fi


### Compressing the database dump and filestore using Odoo's zip backup layout ###
echo -n "Compressing Odoo.sh backup: $backup_name ... "
BACKUP_WORKDIR="$workdir" BACKUP_FILESTORE="$ODOO_DATA_DIR/filestore/$database" BACKUP_OUTPUT="$HOME/backup/$backup_name" "$python_bin" <<'PY' >> "$logfile" 2>&1
import os
import zipfile

workdir = os.environ["BACKUP_WORKDIR"]
filestore = os.environ["BACKUP_FILESTORE"]
output = os.environ["BACKUP_OUTPUT"]

with zipfile.ZipFile(output, "w", compression=zipfile.ZIP_DEFLATED, allowZip64=True) as archive:
    for filename in ("dump.sql", "manifest.json"):
        path = os.path.join(workdir, filename)
        if os.path.exists(path):
            archive.write(path, filename)

    archive.write(filestore, "filestore")
    for root, dirs, files in os.walk(filestore):
        dirs.sort()
        files.sort()
        rel_root = os.path.relpath(root, filestore)
        archive_root = "filestore" if rel_root == "." else os.path.join("filestore", rel_root)

        for dirname in dirs:
            archive.write(os.path.join(root, dirname), os.path.join(archive_root, dirname))

        for filename in files:
            archive.write(os.path.join(root, filename), os.path.join(archive_root, filename))
PY
error=$?
if [ $error -eq 0 ]; then echo "OK"; else echo "ERROR: $error"; exit 5; fi
echo "$backup_name"
