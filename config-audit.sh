#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Configuration snapshot and drift-audit utility.
#
# Commands:
#
#   sudo config-audit.sh snapshot [label]
#       Create a timestamped configuration snapshot and manifest.
#       Does NOT change the accepted baseline.
#
#   sudo config-audit.sh check
#       Compare the live configuration with the accepted baseline.
#       Makes NO changes.
#
#   sudo config-audit.sh accept SNAPSHOT-ID
#       Explicitly designate an existing snapshot as the accepted baseline.
#
#   sudo config-audit.sh list [SNAPSHOT-ID]
#       List available snapshots, or inspect one snapshot.
#
#   sudo config-audit.sh uninstall
#       Display conservative manual uninstall information.
#       Does NOT delete anything.
#
# Configuration:
#   /etc/config-audit/config.conf
#   /etc/config-audit/paths.conf
#
# Storage:
#   /var/backups/config-audit/ by default; configurable on first run.

set -Eeuo pipefail

VERSION="1.0.0"

CONFIG_DIR="/etc/config-audit"
CONFIG_FILE="${CONFIG_DIR}/config.conf"
PATHS_FILE="${CONFIG_DIR}/paths.conf"
DEFAULT_BACKUP_PARENT="/var/backups"

HOST_LABEL=$(hostname -s)
STAMP=$(date +%Y-%m-%dT%H-%M-%S)

echo "Licence terms and disclaimer:"
echo "  /usr/local/share/doc/config-audit/"
echo "YOU USE THIS SOFTWARE AT YOUR OWN RISK."
echo

if [ "$(id -u)" -ne 0 ]; then
    echo "[-] ERROR: config-audit.sh must be run with sudo."
    echo
    echo "    Example:"
    echo "    sudo /usr/local/bin/config-audit.sh check"
    exit 2
fi

write_default_paths_file()
{
    cat > "$PATHS_FILE" <<'EOF'
# Paths included in configuration snapshots and drift audits.
# One absolute path per line.

/etc
EOF

    chown root:root "$PATHS_FILE"
    chmod 644 "$PATHS_FILE"
}

show_directory_state()
{
    local DIR="$1"

    echo "Existing directory:"
    echo "  $DIR"
    echo
    echo "Current ownership:"
    echo "  $(stat -c '%U:%G' -- "$DIR")"
    echo
    echo "Current mode:"
    echo "  $(stat -c '%a' -- "$DIR")"
}

confirm_secure_archive_directory()
{
    local DIR="$1"
    local PARENT="$2"
    local ANSWER

    echo
    echo "Proposed archive directory:"
    echo "  $DIR"
    echo
    echo "Parent directory:"
    echo "  $PARENT"
    echo
    echo "The parent directory will NOT have its ownership or permissions changed."
    echo

    if [ -e "$DIR" ] || [ -L "$DIR" ]; then
        if [ ! -d "$DIR" ] || [ -L "$DIR" ]; then
            echo "[-] ERROR: The proposed archive path already exists but is not"
            echo "    an ordinary directory:"
            echo "    $DIR"
            return 1
        fi

        show_directory_state "$DIR"
        echo

        CURRENT_OWNER=$(stat -c '%U:%G' -- "$DIR")
        CURRENT_MODE=$(stat -c '%a' -- "$DIR")

        if [ "$CURRENT_OWNER" = "root:root" ] && [ "$CURRENT_MODE" = "700" ]; then
            echo "Required ownership:"
            echo "  root:root"
            echo
            echo "Required mode:"
            echo "  0700"
            echo
            echo "The existing directory already has the required ownership and mode."
            printf "Use this directory? [y/N] "
            read -r ANSWER

            case "$ANSWER" in
                y|Y|yes|YES|Yes)
                    return 0
                    ;;
                *)
                    return 2
                    ;;
            esac
        fi

        echo "Required ownership:"
        echo "  root:root"
        echo
        echo "Required mode:"
        echo "  0700"
        echo
        echo "No changes have been made."
        printf "Apply these changes and use this directory? [y/N] "
        read -r ANSWER

        case "$ANSWER" in
            y|Y|yes|YES|Yes)
                if ! chown root:root -- "$DIR"; then
                    echo "[-] ERROR: Could not change ownership of:"
                    echo "    $DIR"
                    return 1
                fi
                if ! chmod 700 -- "$DIR"; then
                    echo "[-] ERROR: Could not change permissions of:"
                    echo "    $DIR"
                    return 1
                fi
                return 0
                ;;
            *)
                return 2
                ;;
        esac
    fi

    echo "config-audit proposes to create:"
    echo "  $DIR"
    echo
    echo "Ownership:"
    echo "  root:root"
    echo
    echo "Mode:"
    echo "  0700"
    echo
    printf "Create this directory and continue? [y/N] "
    read -r ANSWER

    case "$ANSWER" in
        y|Y|yes|YES|Yes)
            local ERROR_FILE
            ERROR_FILE=$(mktemp /tmp/config-audit-mkdir.XXXXXX)

            if ! mkdir -- "$DIR" 2>"$ERROR_FILE"; then
                echo
                echo "[-] ERROR: config-audit could not create:"
                echo "    $DIR"
                echo
                if [ -s "$ERROR_FILE" ]; then
                    echo "The operating system reported:"
                    sed 's/^/    /' "$ERROR_FILE"
                    echo
                fi
                echo "The parent directory has NOT been modified."
                rm -f "$ERROR_FILE"
                return 1
            fi

            rm -f "$ERROR_FILE"

            if ! chown root:root -- "$DIR" || ! chmod 700 -- "$DIR"; then
                echo "[-] ERROR: The directory was created but could not be secured:"
                echo "    $DIR"
                echo "    Please inspect it before continuing."
                return 1
            fi
            return 0
            ;;
        *)
            return 2
            ;;
    esac
}

normalise_existing_config_directory()
{
    local ANSWER
    local OWNER
    local MODE

    OWNER=$(stat -c '%U:%G' -- "$CONFIG_DIR")
    MODE=$(stat -c '%a' -- "$CONFIG_DIR")

    if [ "$OWNER" = "root:root" ] && [ "$MODE" = "755" ]; then
        return 0
    fi

    echo
    echo "Existing configuration directory:"
    echo "  $CONFIG_DIR"
    echo
    echo "Current ownership:"
    echo "  $OWNER"
    echo
    echo "Current mode:"
    echo "  $MODE"
    echo
    echo "Normal config-audit settings are:"
    echo "  Owner: root:root"
    echo "  Mode:  0755"
    echo
    echo "No changes have been made."
    printf "Apply these settings to /etc/config-audit? [y/N] "
    read -r ANSWER

    case "$ANSWER" in
        y|Y|yes|YES|Yes)
            chown root:root -- "$CONFIG_DIR"
            chmod 755 -- "$CONFIG_DIR"
            ;;
        *)
            echo
            echo "Setup cancelled. Existing directory permissions were not changed."
            exit 2
            ;;
    esac
}

normalise_existing_paths_file()
{
    local ANSWER
    local OWNER
    local MODE

    [ -f "$PATHS_FILE" ] || return 0

    if [ -L "$PATHS_FILE" ]; then
        echo "[-] ERROR: $PATHS_FILE is a symbolic link."
        echo "    Refusing to alter it automatically."
        exit 2
    fi

    OWNER=$(stat -c '%U:%G' -- "$PATHS_FILE")
    MODE=$(stat -c '%a' -- "$PATHS_FILE")

    if [ "$OWNER" = "root:root" ] && [ "$MODE" = "644" ]; then
        return 0
    fi

    echo
    echo "Existing path configuration:"
    echo "  $PATHS_FILE"
    echo
    echo "Current ownership: $OWNER"
    echo "Current mode:      $MODE"
    echo
    echo "Normal config-audit settings are:"
    echo "  Owner: root:root"
    echo "  Mode:  0644"
    echo
    echo "No changes have been made."
    printf "Apply these settings to paths.conf? [y/N] "
    read -r ANSWER

    case "$ANSWER" in
        y|Y|yes|YES|Yes)
            chown root:root -- "$PATHS_FILE"
            chmod 644 -- "$PATHS_FILE"
            ;;
        *)
            echo
            echo "Setup cancelled. paths.conf permissions were not changed."
            exit 2
            ;;
    esac
}

validate_control_directory()
{
    local DIR="$1"
    local LABEL="$2"
    local OWNER_UID
    local MODE
    local MODE_DEC

    if [ ! -d "$DIR" ] || [ -L "$DIR" ]; then
        echo "[-] ERROR: $LABEL is not an ordinary directory:"
        echo "    $DIR"
        exit 2
    fi

    OWNER_UID=$(stat -c '%u' -- "$DIR")
    MODE=$(stat -c '%a' -- "$DIR")
    MODE_DEC=$((8#$MODE))

    if [ "$OWNER_UID" -ne 0 ]; then
        echo "[-] ERROR: $LABEL is not owned by root:"
        echo "    $DIR"
        exit 2
    fi

    if (( MODE_DEC & 0022 )); then
        echo "[-] ERROR: $LABEL is writable by group or others:"
        echo "    $DIR (mode $MODE)"
        exit 2
    fi
}

validate_control_file()
{
    local FILE="$1"
    local LABEL="$2"
    local OWNER_UID
    local MODE
    local MODE_DEC

    if [ ! -f "$FILE" ] || [ -L "$FILE" ]; then
        echo "[-] ERROR: $LABEL is not a regular file:"
        echo "    $FILE"
        exit 2
    fi

    OWNER_UID=$(stat -c '%u' -- "$FILE")
    MODE=$(stat -c '%a' -- "$FILE")
    MODE_DEC=$((8#$MODE))

    if [ "$OWNER_UID" -ne 0 ]; then
        echo "[-] ERROR: $LABEL is not owned by root:"
        echo "    $FILE"
        exit 2
    fi

    if (( MODE_DEC & 0022 )); then
        echo "[-] ERROR: $LABEL is writable by group or others:"
        echo "    $FILE (mode $MODE)"
        exit 2
    fi
}

first_run_setup()
{
    local ANSWER
    local INPUT_PARENT
    local PARENT
    local PROPOSED_BACKUP_DIR
    local RESULT

    echo "=============================================="
    echo " CONFIG-AUDIT — FIRST-RUN SETUP"
    echo "=============================================="
    echo

    if [ ! -d "$CONFIG_DIR" ]; then
        echo "config-audit requires a small permanent configuration"
        echo "directory at:"
        echo
        echo "  $CONFIG_DIR"
        echo
        echo "This directory will contain the program's configuration,"
        echo "including paths.conf, which stores the locations that will"
        echo "be included in your configuration archive."
        echo
        echo "It will also contain config.conf, which records where your"
        echo "configuration archives will be saved."
        echo
        echo "The directory will be created with:"
        echo
        echo "  Owner: root:root"
        echo "  Mode:  0755"
        echo
        echo "No other directory under /etc will be modified."
        echo
        printf "Create /etc/config-audit and continue? [y/N] "
        read -r ANSWER

        case "$ANSWER" in
            y|Y|yes|YES|Yes)
                if ! mkdir -- "$CONFIG_DIR"; then
                    echo "[-] ERROR: Could not create $CONFIG_DIR."
                    exit 2
                fi
                chown root:root "$CONFIG_DIR"
                chmod 755 "$CONFIG_DIR"
                ;;
            *)
                echo
                echo "Installation cancelled."
                echo
                echo "config-audit requires /etc/config-audit in order to store"
                echo "its persistent configuration."
                echo
                echo "No changes have been made."
                exit 2
                ;;
        esac
    else
        if [ -L "$CONFIG_DIR" ]; then
            echo "[-] ERROR: $CONFIG_DIR is a symbolic link."
            echo "    Refusing to alter it automatically."
            exit 2
        fi

        if [ ! -d "$CONFIG_DIR" ]; then
            echo "[-] ERROR: $CONFIG_DIR exists but is not a directory."
            exit 2
        fi
    fi

    normalise_existing_config_directory
    normalise_existing_paths_file

    if [ ! -f "$PATHS_FILE" ]; then
        write_default_paths_file
        echo
        echo "[+] Created default audit path configuration:"
        echo "    $PATHS_FILE"
        echo "    Initial audited path: /etc"
    fi

    echo
    echo "Please supply the location where you want your configuration"
    echo "archives to be stored."
    echo
    echo "This should be a location to which you currently, in this"
    echo "session, have access permissions."
    echo
    echo "Press Enter to use the default parent directory:"
    echo "  $DEFAULT_BACKUP_PARENT"
    echo

    while true; do
        printf "Archive parent directory: "
        read -r INPUT_PARENT

        if [ -z "$INPUT_PARENT" ]; then
            PARENT="$DEFAULT_BACKUP_PARENT"
        else
            PARENT="${INPUT_PARENT%/}"
        fi

        if [[ "$PARENT" != /* ]]; then
            echo
            echo "[-] ERROR: Please enter an absolute path beginning with /."
            echo
            continue
        fi

        if [ ! -d "$PARENT" ]; then
            echo
            echo "[-] ERROR: The parent directory does not exist or is not a directory:"
            echo "    $PARENT"
            echo
            echo "Please choose another location."
            echo
            continue
        fi

        PROPOSED_BACKUP_DIR="${PARENT}/config-audit"

        set +e
        confirm_secure_archive_directory "$PROPOSED_BACKUP_DIR" "$PARENT"
        RESULT=$?
        set -e

        if [ "$RESULT" -eq 0 ]; then
            BACKUP_DIR="$PROPOSED_BACKUP_DIR"
            break
        elif [ "$RESULT" -eq 2 ]; then
            echo
            echo "That location was not selected. Please choose another location."
            echo
        else
            echo
            echo "Please choose another archive location."
            echo
        fi
    done

    cat > "$CONFIG_FILE" <<EOF
# config-audit persistent configuration
BACKUP_DIR="$BACKUP_DIR"
EOF

    chown root:root "$CONFIG_FILE"
    chmod 644 "$CONFIG_FILE"

    echo
    echo "[+] Configuration saved:"
    echo "    $CONFIG_FILE"
    echo
    echo "[+] Configuration archives will be stored in:"
    echo "    $BACKUP_DIR"
    echo
    echo "IMPORTANT: Local configuration snapshots are not a substitute"
    echo "for an independent off-machine backup."
}

load_config()
{
    local LINE
    local VALUE

    if [ ! -f "$CONFIG_FILE" ]; then
        first_run_setup
    fi

    validate_control_directory "$CONFIG_DIR" "Configuration directory"
    validate_control_file "$CONFIG_FILE" "Configuration file"
    validate_control_file "$PATHS_FILE" "Path configuration file"

    BACKUP_DIR=""

    while IFS= read -r LINE || [ -n "$LINE" ]; do
        LINE="${LINE%$'\r'}"
        LINE="${LINE#"${LINE%%[![:space:]]*}"}"
        LINE="${LINE%"${LINE##*[![:space:]]}"}"

        [ -z "$LINE" ] && continue
        [[ "$LINE" == \#* ]] && continue

        case "$LINE" in
            BACKUP_DIR=*)
                VALUE="${LINE#BACKUP_DIR=}"
                if [[ "$VALUE" == \"*\" ]] && [[ "$VALUE" == *\" ]]; then
                    VALUE="${VALUE:1:${#VALUE}-2}"
                fi
                BACKUP_DIR="$VALUE"
                ;;
            *)
                echo "[-] ERROR: Unrecognised setting in $CONFIG_FILE:"
                echo "    $LINE"
                exit 2
                ;;
        esac
    done < "$CONFIG_FILE"

    if [ -z "$BACKUP_DIR" ] || [[ "$BACKUP_DIR" != /* ]]; then
        echo "[-] ERROR: BACKUP_DIR in $CONFIG_FILE must be an absolute path."
        exit 2
    fi

    if [ ! -d "$BACKUP_DIR" ] || [ -L "$BACKUP_DIR" ]; then
        echo "[-] ERROR: The configured archive directory cannot be found:"
        echo
        echo "    $BACKUP_DIR"
        echo
        echo "This location is specified in:"
        echo
        echo "    $CONFIG_FILE"
        echo
        echo "The directory may have been deleted, renamed or moved."
        echo
        echo "Please confirm the correct archive location and update config.conf."
        echo
        echo "No archive or audit data has been written."
        echo
        echo "The current run cannot continue safely."
        echo

        while true; do
            printf "Enter Y to acknowledge this message and exit: [y/N] "
            if ! read -r ANSWER; then
                echo
                echo "config-audit cancelled. No changes have been made."
                exit 2
            fi
            case "$ANSWER" in
                y|Y|yes|YES|Yes)
                    echo
                    echo "config-audit cancelled. No changes have been made."
                    exit 2
                    ;;
                *)
                    echo "Please enter Y to acknowledge the error and exit."
                    ;;
            esac
        done
    fi

    if [ "$(stat -c '%u:%g' -- "$BACKUP_DIR")" != "0:0" ] || \
       [ "$(stat -c '%a' -- "$BACKUP_DIR")" != "700" ]; then
        echo "[-] ERROR: Configured archive directory does not have the required"
        echo "    root:root ownership and mode 0700:"
        echo "    $BACKUP_DIR"
        echo "    Refusing to change it automatically during a normal run."
        exit 2
    fi

    REPORT_DIR="${BACKUP_DIR}/reports"
    BASELINE_POINTER="${BACKUP_DIR}/accepted-baseline"

    if [ -e "$REPORT_DIR" ] || [ -L "$REPORT_DIR" ]; then
        if [ ! -d "$REPORT_DIR" ] || [ -L "$REPORT_DIR" ]; then
            echo "[-] ERROR: Reports path is not an ordinary directory:"
            echo "    $REPORT_DIR"
            exit 2
        fi
        if [ "$(stat -c '%u:%g' -- "$REPORT_DIR")" != "0:0" ] || \
           [ "$(stat -c '%a' -- "$REPORT_DIR")" != "700" ]; then
            echo "[-] ERROR: Reports directory must be root:root mode 0700:"
            echo "    $REPORT_DIR"
            exit 2
        fi
    else
        mkdir -- "$REPORT_DIR"
        chown root:root "$REPORT_DIR"
        chmod 700 "$REPORT_DIR"
    fi
}

load_config

if [ ! -f "$PATHS_FILE" ]; then
    echo "[-] ERROR: Configuration file not found:"
    echo "    $PATHS_FILE"
    exit 2
fi


load_paths()
{
    local SOURCE_FILE="$1"
    PATHS=()

    while IFS= read -r LINE || [ -n "$LINE" ]; do

        # Remove CR if a file has accidentally acquired DOS line endings.
        LINE="${LINE%$'\r'}"

        # Trim leading and trailing whitespace.
        LINE="${LINE#"${LINE%%[![:space:]]*}"}"
        LINE="${LINE%"${LINE##*[![:space:]]}"}"

        # Ignore blank lines and comments.
        [ -z "$LINE" ] && continue
        [[ "$LINE" == \#* ]] && continue

        if [[ "$LINE" != /* ]]; then
            echo "[-] ERROR: Audit path is not absolute:"
            echo "    $LINE"
            exit 2
        fi

        PATHS+=("$LINE")

    done < "$SOURCE_FILE"

    if [ "${#PATHS[@]}" -eq 0 ]; then
        echo "[-] ERROR: No audit paths are defined in:"
        echo "    $SOURCE_FILE"
        exit 2
    fi
}


generate_manifest()
{
    local SOURCE_PATHS="$1"
    local OUTPUT="$2"
    local TEMP="${OUTPUT}.unsorted"

    : > "$TEMP"

    load_paths "$SOURCE_PATHS"

    for ROOT_PATH in "${PATHS[@]}"; do

        if [ ! -e "$ROOT_PATH" ] && [ ! -L "$ROOT_PATH" ]; then
            printf '%q\tMISSING\t-\t-\t-\t-\n' \
                "$ROOT_PATH" >> "$TEMP"
            continue
        fi

        while IFS= read -r -d '' ITEM; do

            TYPE=$(stat -c '%F' -- "$ITEM")
            MODE=$(stat -c '%a' -- "$ITEM")
            FILE_UID=$(stat -c '%u' -- "$ITEM")
            FILE_GID=$(stat -c '%g' -- "$ITEM")

            if [ -L "$ITEM" ]; then

                TARGET=$(readlink -- "$ITEM")

                printf '%q\t%s\t%s\t%s\t%s\tLINK:%q\n' \
                    "$ITEM" \
                    "$TYPE" \
                    "$MODE" \
                    "$FILE_UID" \
                    "$FILE_GID" \
                    "$TARGET" >> "$TEMP"

            elif [ -f "$ITEM" ]; then

                HASH=$(sha256sum -- "$ITEM" | awk '{print $1}')

                printf '%q\t%s\t%s\t%s\t%s\tSHA256:%s\n' \
                    "$ITEM" \
                    "$TYPE" \
                    "$MODE" \
                    "$FILE_UID" \
                    "$FILE_GID" \
                    "$HASH" >> "$TEMP"

            else

                printf '%q\t%s\t%s\t%s\t%s\t-\n' \
                    "$ITEM" \
                    "$TYPE" \
                    "$MODE" \
                    "$FILE_UID" \
                    "$FILE_GID" >> "$TEMP"
            fi

        done < <(
            find -P "$ROOT_PATH" -xdev \
                \( -type f -o -type d -o -type l \) \
                -print0 2>/dev/null
        )

    done

    LC_ALL=C sort -u "$TEMP" > "$OUTPUT"
    rm -f "$TEMP"
}



run_with_progress()
{
    local MESSAGE="$1"
    shift

    printf "%s " "$MESSAGE"

    "$@" &
    local PID=$!

    while kill -0 "$PID" 2>/dev/null; do
        printf "."
        sleep 2
    done

    if wait "$PID"; then
        printf " done.\n"
        return 0
    else
        local STATUS=$?
        printf " FAILED.\n"
        return "$STATUS"
    fi
}


snapshot()
{
    local LABEL="${1:-}"

    if [ -n "$LABEL" ]; then
        if [[ ! "$LABEL" =~ ^[A-Za-z0-9._-]+$ ]]; then
            echo "[-] ERROR: Snapshot label may contain only:"
            echo "    letters, numbers, dot, underscore and hyphen."
            exit 2
        fi
        LABEL="-${LABEL}"
    fi

    local ID="${HOST_LABEL}-config-${STAMP}${LABEL}"
    local ARCHIVE="${BACKUP_DIR}/${ID}.tar.gz"
    local CHECKSUM="${ARCHIVE}.sha256"
    local MANIFEST="${BACKUP_DIR}/${ID}.manifest"
    local PATH_COPY="${BACKUP_DIR}/${ID}.paths"

    local PRE_MANIFEST
    local POST_MANIFEST

    PRE_MANIFEST=$(mktemp /tmp/config-audit-pre.XXXXXX)
    POST_MANIFEST=$(mktemp /tmp/config-audit-post.XXXXXX)

    cleanup_snapshot_temp()
    {
        rm -f "$PRE_MANIFEST" "$POST_MANIFEST"
    }

    trap cleanup_snapshot_temp RETURN

    echo "=== CONFIGURATION SNAPSHOT ==="
    echo
    echo "Snapshot ID:"
    echo "  ${BACKUP_DIR}/${ID}"
    echo

    echo "[+] Recording audit path definition..."

    cp -a "$PATHS_FILE" "$PATH_COPY"
    chown root:root "$PATH_COPY"
    chmod 600 "$PATH_COPY"

    run_with_progress         "[+] Building pre-archive manifest"         generate_manifest "$PATH_COPY" "$PRE_MANIFEST"

    load_paths "$PATH_COPY"

    RELATIVE_PATHS=()

    for ABS_PATH in "${PATHS[@]}"; do
        if [ ! -e "$ABS_PATH" ] && [ ! -L "$ABS_PATH" ]; then
            echo "[-] ERROR: A configured audit path cannot currently be found:"
            echo
            echo "    $ABS_PATH"
            echo
            echo "This path is specified in:"
            echo
            echo "    $PATHS_FILE"
            echo
            echo "The path may have been deleted, renamed or moved, or it may no"
            echo "longer need to be included in configuration snapshots."
            echo
            echo "Please confirm the intended audit scope and update paths.conf"
            echo "if necessary."
            echo
            echo "No snapshot has been created."
            rm -f "$ARCHIVE" "$CHECKSUM" "$MANIFEST" "$PATH_COPY"
            exit 1
        fi

        RELATIVE_PATHS+=("${ABS_PATH#/}")
    done

    echo "[+] Archive:"
    echo "    $ARCHIVE"

    run_with_progress         "[+] Creating archive"         tar         --acls         --xattrs         --numeric-owner         -czpf "$ARCHIVE"         -C /         "${RELATIVE_PATHS[@]}"

    chmod 600 "$ARCHIVE"

    echo "[+] Verifying tar archive..."

    tar -tzf "$ARCHIVE" >/dev/null

    echo "[+] Tar archive: OK"

    run_with_progress         "[+] Building post-archive manifest"         generate_manifest "$PATH_COPY" "$POST_MANIFEST"

    if ! cmp -s "$PRE_MANIFEST" "$POST_MANIFEST"; then

    INSTABILITY_REPORT="${REPORT_DIR}/${ID}-snapshot-instability.txt"

    {
        echo "CONFIGURATION SNAPSHOT INSTABILITY REPORT"
        echo "Generated: $(date --iso-8601=seconds)"
        echo "Host: $HOST_LABEL"
        echo "Snapshot ID: $ID"
        echo

        awk -F '\t' '
            NR==FNR {
                before[$1]=$0
                next
            }

            {
                after[$1]=$0
            }

            END {
                print "=== ADDED DURING SNAPSHOT ==="
                for (path in after)
                    if (!(path in before))
                        print path

                print ""
                print "=== DELETED DURING SNAPSHOT ==="
                for (path in before)
                    if (!(path in after))
                        print path

                print ""
                print "=== MODIFIED DURING SNAPSHOT ==="
                for (path in before)
                    if ((path in after) && before[path] != after[path])
                        print path
            }
        ' "$PRE_MANIFEST" "$POST_MANIFEST"

    } > "$INSTABILITY_REPORT"

    chmod 600 "$INSTABILITY_REPORT"

    echo
    echo "[-] CONFIGURATION CHANGED WHILE THE SNAPSHOT WAS BEING CREATED."
    echo
    echo "    This snapshot cannot be treated as a coherent configuration"
    echo "    checkpoint."
    echo
    echo "    One possible explanation is that the audit path includes a"
    echo "    LIVE or dynamically maintained file, for example:"
    echo
    echo "      - a database"
    echo "      - runtime state"
    echo "      - a cache"
    echo "      - an automatically generated file"
    echo
    echo "    Files that changed during the snapshot:"
    echo

    awk '
        /^=== MODIFIED DURING SNAPSHOT ===$/ { show=1; next }
        /^===/ { show=0 }
        show && NF { print "      " $0 }
    ' "$INSTABILITY_REPORT"

    echo
    echo "    Full instability report:"
    echo "      $INSTABILITY_REPORT"
    echo
    echo "    The archive has been retained as:"
    echo "      ${ARCHIVE}.unstable"
    echo
    echo "    The accepted baseline has NOT been changed."

    mv "$ARCHIVE" "${ARCHIVE}.unstable"
    mv "$PATH_COPY" "${PATH_COPY}.unstable"

    exit 1
fi

    cp "$POST_MANIFEST" "$MANIFEST"
    chown root:root "$MANIFEST"
    chmod 600 "$MANIFEST"

    echo "[+] Configuration remained stable during snapshot."

    echo "[+] Creating SHA-256 checksum..."

    sha256sum "$ARCHIVE" > "$CHECKSUM"
    chmod 600 "$CHECKSUM"

    echo "[+] Verifying SHA-256 checksum..."

    sha256sum -c "$CHECKSUM"

    echo
    echo "=============================================="
    echo " SNAPSHOT CREATED SUCCESSFULLY"
    echo "=============================================="
    echo
    echo "Your current configuration has been safely recorded."
    echo
    echo "Snapshot ID:"
    echo "  ${BACKUP_DIR}/${ID}"
    echo
    echo "Archive:"
    echo "  $ARCHIVE"
    echo
    echo "Manifest:"
    echo "  $MANIFEST"
    echo
    echo "IMPORTANT: These are local configuration snapshots. They are not"
    echo "a substitute for an independent off-machine backup."
    echo

    if [ -f "$BASELINE_POINTER" ]; then
        CURRENT_BASELINE=$(cat "$BASELINE_POINTER")

        echo "Current accepted baseline:"
        echo "  $CURRENT_BASELINE"
        echo
        echo "The existing accepted baseline has NOT been changed."
    else
        echo "There is currently NO accepted configuration baseline."
    fi

    echo
    echo "This is intentional: creating a snapshot does not automatically"
    echo "declare the current configuration to be trusted."
    echo
    echo "If you have reviewed the current configuration and want this"
    echo "snapshot to become the reference point for future audits, run:"
    echo
    echo "  sudo /usr/local/bin/config-audit.sh accept $ID"
    echo
    echo "Otherwise, do nothing."

    if [ -f "$BASELINE_POINTER" ]; then
        echo "Future checks will continue to compare the computer against:"
        echo "  $CURRENT_BASELINE"
    else
        echo "A baseline must be explicitly accepted before 'check' can be used."
    fi
}

check()
{
    local HOST_DISPLAY
    HOST_DISPLAY=$(printf '%s' "$HOST_LABEL" | tr '[:lower:]' '[:upper:]')

    #
    # FIRST RUN — no accepted baseline exists yet.
    #
    if [ ! -f "$BASELINE_POINTER" ]; then
        echo "=============================================="
        echo " CONFIG-AUDIT — FIRST RUN"
        echo "=============================================="
        echo
        echo "Host:"
        echo "  $HOST_LABEL"
        echo
        echo "No accepted configuration baseline exists yet."
        echo
        echo "config-audit records the configuration state of this computer"
        echo "and can later show you what has changed."
        echo
        echo "The files and directories included in each snapshot are defined in:"
        echo
        echo "  $PATHS_FILE"
        echo
        echo "For example, including:"
        echo
        echo "  /etc"
        echo
        echo "causes the files and directories beneath /etc to be backed up"
        echo "and included in the configuration audit."
        echo
        echo "You can add other configuration locations to paths.conf whenever"
        echo "you install software whose configuration you want to preserve"
        echo "and monitor."
        echo
        echo "To record the computer's current configuration state, run:"
        echo
        echo "  sudo /usr/local/bin/config-audit.sh snapshot initial"
        echo
        echo "This creates a timestamped configuration backup, manifest and"
        echo "checksum."
        echo
        echo "Creating a snapshot does NOT automatically declare that snapshot"
        echo "to be trusted."
        echo
        echo "You may continue configuring the computer and create further"
        echo "snapshots whenever useful."
        echo
        echo "When you are satisfied that the configuration is correct and"
        echo "ready to become the reference point for future audits, create"
        echo "a snapshot and explicitly accept it as the baseline."
        echo
        echo "The snapshot command will display the exact command required"
        echo "to accept it."
        echo
        echo "Until a baseline has been accepted, configuration drift checks"
        echo "cannot be performed."
        return 2
    fi

    BASELINE_ID=$(cat "$BASELINE_POINTER")

    BASELINE_MANIFEST="${BACKUP_DIR}/${BASELINE_ID}.manifest"
    BASELINE_PATHS="${BACKUP_DIR}/${BASELINE_ID}.paths"

    if [ ! -f "$BASELINE_MANIFEST" ] || [ ! -f "$BASELINE_PATHS" ]; then
        echo "[-] ERROR: The accepted baseline is incomplete."
        echo
        echo "Baseline:"
        echo "  ${BACKUP_DIR}/${BASELINE_ID}"
        echo
        echo "The baseline manifest or stored path definition is missing."
        echo "Do not accept another baseline until this has been investigated."
        return 2
    fi

    LIVE_MANIFEST=$(mktemp /tmp/config-audit-live.XXXXXX)
    ADDED_LIST=$(mktemp /tmp/config-audit-added.XXXXXX)
    DELETED_LIST=$(mktemp /tmp/config-audit-deleted.XXXXXX)
    MODIFIED_LIST=$(mktemp /tmp/config-audit-modified.XXXXXX)

    cleanup_check_temp()
    {
        rm -f "$LIVE_MANIFEST" "$ADDED_LIST" "$DELETED_LIST" "$MODIFIED_LIST"
    }

    trap cleanup_check_temp RETURN

    REPORT="${REPORT_DIR}/${HOST_LABEL}-drift-${STAMP}.txt"

    echo "=============================================="
    echo " ${HOST_DISPLAY} CONFIGURATION AUDIT"
    echo "=============================================="
    echo
    echo "Host:"
    echo "  $HOST_LABEL"
    echo
    echo "Accepted baseline:"
    echo "  ${BACKUP_DIR}/${BASELINE_ID}"
    echo
    echo "The current configuration will be compared with this"
    echo "accepted baseline."
    echo

    #
    # Deliberately use the path definition stored WITH the accepted
    # baseline. A later modification of the current paths.conf cannot
    # silently reduce the scope of an existing audit.
    #
    load_paths "$BASELINE_PATHS"
    MISSING_BASELINE_PATHS=0

    for ROOT_PATH in "${PATHS[@]}"; do
        if [ ! -e "$ROOT_PATH" ] && [ ! -L "$ROOT_PATH" ]; then
            if [ "$MISSING_BASELINE_PATHS" -eq 0 ]; then
                echo "WARNING: One or more paths included in the accepted baseline"
                echo "cannot currently be found:"
                echo
            fi
            echo "  $ROOT_PATH"
            MISSING_BASELINE_PATHS=1
        fi
    done

    if [ "$MISSING_BASELINE_PATHS" -ne 0 ]; then
        echo
        echo "The audit will continue so that the resulting configuration"
        echo "changes can be reported."
        echo
        echo "If a missing path was intentionally removed, renamed, or no"
        echo "longer needs to be included in the audit, review:"
        echo
        echo "  $PATHS_FILE"
        echo
        echo "When satisfied with the new configuration and audit scope, create"
        echo "and explicitly accept a new snapshot."
        echo
    fi

    printf "Building current configuration manifest "

    generate_manifest "$BASELINE_PATHS" "$LIVE_MANIFEST" &
    MANIFEST_PID=$!

    while kill -0 "$MANIFEST_PID" 2>/dev/null; do
        printf "."
        sleep 2
    done

    if wait "$MANIFEST_PID"; then
        printf " done.\n"
    else
        printf " FAILED.\n"
        echo
        echo "[-] ERROR: The current configuration manifest could not be built."
        return 2
    fi

    declare -A OLD
    declare -A NEW

    while IFS=$'\t' read -r PATHNAME TYPE MODE FILE_UID FILE_GID DATA; do
        OLD["$PATHNAME"]="${TYPE}"$'\t'"${MODE}"$'\t'"${FILE_UID}"$'\t'"${FILE_GID}"$'\t'"${DATA}"
    done < "$BASELINE_MANIFEST"

    while IFS=$'\t' read -r PATHNAME TYPE MODE FILE_UID FILE_GID DATA; do
        NEW["$PATHNAME"]="${TYPE}"$'\t'"${MODE}"$'\t'"${FILE_UID}"$'\t'"${FILE_GID}"$'\t'"${DATA}"
    done < "$LIVE_MANIFEST"

    for PATHNAME in "${!NEW[@]}"; do
        if [[ ! -v OLD["$PATHNAME"] ]]; then
            printf '%s\n' "$PATHNAME" >> "$ADDED_LIST"
        fi
    done

    for PATHNAME in "${!OLD[@]}"; do
        if [[ ! -v NEW["$PATHNAME"] ]]; then
            printf '%s\n' "$PATHNAME" >> "$DELETED_LIST"
        fi
    done

    for PATHNAME in "${!OLD[@]}"; do
        if [[ -v NEW["$PATHNAME"] ]] && \
           [ "${OLD[$PATHNAME]}" != "${NEW[$PATHNAME]}" ]; then

            OLD_VALUE="${OLD[$PATHNAME]}"
            NEW_VALUE="${NEW[$PATHNAME]}"

            IFS=$'\t' read -r OLD_TYPE OLD_MODE OLD_UID OLD_GID OLD_DATA <<< "$OLD_VALUE"
            IFS=$'\t' read -r NEW_TYPE NEW_MODE NEW_UID NEW_GID NEW_DATA <<< "$NEW_VALUE"

            CHANGES=()

            [ "$OLD_TYPE" != "$NEW_TYPE" ] && CHANGES+=("type")
            [ "$OLD_MODE" != "$NEW_MODE" ] && CHANGES+=("mode")
            [ "$OLD_UID" != "$NEW_UID" ] && CHANGES+=("owner")
            [ "$OLD_GID" != "$NEW_GID" ] && CHANGES+=("group")
            [ "$OLD_DATA" != "$NEW_DATA" ] && CHANGES+=("content/target")

            {
                printf '%s [' "$PATHNAME"
                printf '%s' "${CHANGES[0]}"

                for ((i=1; i<${#CHANGES[@]}; i++)); do
                    printf ', %s' "${CHANGES[$i]}"
                done

                printf ']\n'
            } >> "$MODIFIED_LIST"
        fi
    done

    LC_ALL=C sort -o "$ADDED_LIST" "$ADDED_LIST"
    LC_ALL=C sort -o "$DELETED_LIST" "$DELETED_LIST"
    LC_ALL=C sort -o "$MODIFIED_LIST" "$MODIFIED_LIST"

    ADDED=$(awk 'END { print NR+0 }' "$ADDED_LIST")
    DELETED=$(awk 'END { print NR+0 }' "$DELETED_LIST")
    MODIFIED=$(awk 'END { print NR+0 }' "$MODIFIED_LIST")

    {
        echo
        echo "=============================================="
        echo " ${HOST_DISPLAY} CONFIGURATION DRIFT REPORT"
        echo "=============================================="
        echo
        echo "Changes found since the accepted baseline."
        echo
        echo "Generated:"
        echo "  $(date --iso-8601=seconds)"
        echo
        echo "=== FILES ADDED ==="

        if [ -s "$ADDED_LIST" ]; then
            cat "$ADDED_LIST"
        else
            echo "None"
        fi

        echo
        echo "=== FILES DELETED ==="

        if [ -s "$DELETED_LIST" ]; then
            cat "$DELETED_LIST"
        else
            echo "None"
        fi

        echo
        echo "=== FILES MODIFIED ==="

        if [ -s "$MODIFIED_LIST" ]; then
            cat "$MODIFIED_LIST"
        else
            echo "None"
        fi

        echo
        echo "=== SUMMARY ==="
        echo "Added:     $ADDED"
        echo "Deleted:   $DELETED"
        echo "Modified:  $MODIFIED"

    } | tee "$REPORT"

    chmod 600 "$REPORT"

    echo
    echo "Full report saved:"
    echo "  $REPORT"

    if [ "$ADDED" -eq 0 ] && \
       [ "$DELETED" -eq 0 ] && \
       [ "$MODIFIED" -eq 0 ]; then

        echo
        echo "=============================================="
        echo " NO CONFIGURATION DRIFT DETECTED"
        echo "=============================================="
        echo
        echo "The current configuration matches the accepted baseline."
        echo
        echo "No action is required."
        return 0
    fi

    echo
    echo "=============================================="
    echo " CONFIGURATION DRIFT DETECTED"
    echo "=============================================="
    echo
    echo "The accepted baseline has NOT been changed."
    echo
    echo "Review the files listed above and determine whether the"
    echo "changes are expected."
    echo
    echo "If the changes are NOT expected:"
    echo
    echo "  Investigate or correct them as required, then run:"
    echo
    echo "    sudo /usr/local/bin/config-audit.sh check"
    echo
    echo "If the changes ARE expected and the current configuration"
    echo "is now known to be correct:"
    echo
    echo "  Create a new snapshot:"
    echo
    echo "    sudo /usr/local/bin/config-audit.sh snapshot"
    echo
    echo "  Review the resulting snapshot and follow the displayed"
    echo "  instruction to accept it as the new baseline."

    return 1
}


accept_snapshot() {
    if [ "$#" -ne 1 ]; then
        echo "Usage:"
        echo "  sudo $0 accept SNAPSHOT-ID"
        exit 2
    fi

    local ID="$1"

    if [[ ! "$ID" =~ ^[A-Za-z0-9._-]+$ ]]; then
        echo "[-] ERROR: Invalid snapshot ID."
        exit 2
    fi

    local ARCHIVE="${BACKUP_DIR}/${ID}.tar.gz"
    local CHECKSUM="${ARCHIVE}.sha256"
    local MANIFEST="${BACKUP_DIR}/${ID}.manifest"
    local PATH_COPY="${BACKUP_DIR}/${ID}.paths"

    for FILE in "$ARCHIVE" "$CHECKSUM" "$MANIFEST" "$PATH_COPY"; do
        if [ ! -f "$FILE" ]; then
            echo "[-] ERROR: Snapshot is incomplete:"
            echo "    Missing: $FILE"
            exit 1
        fi
    done

    echo "=== ACCEPT CONFIGURATION BASELINE ==="
    echo
    echo "Snapshot:"
    echo "  $ID"
    echo
    echo "[+] Verifying archive checksum..."

    sha256sum -c "$CHECKSUM"

    printf '%s\n' "$ID" > "${BASELINE_POINTER}.new"
    chown root:root "${BASELINE_POINTER}.new"
    chmod 600 "${BASELINE_POINTER}.new"

    mv "${BASELINE_POINTER}.new" "$BASELINE_POINTER"

    echo
    echo "[+] ACCEPTED BASELINE:"
    echo "    $ID"
}


list_snapshot_details()
{
    local ID="$1"
    local ARCHIVE="${BACKUP_DIR}/${ID}.tar.gz"
    local PATH_COPY="${BACKUP_DIR}/${ID}.paths"
    local MANIFEST="${BACKUP_DIR}/${ID}.manifest"
    local CHECKSUM="${ARCHIVE}.sha256"

    if [[ ! "$ID" =~ ^[A-Za-z0-9._-]+$ ]]; then
        echo "[-] ERROR: Invalid snapshot ID."
        exit 2
    fi

    for FILE in "$ARCHIVE" "$PATH_COPY" "$MANIFEST" "$CHECKSUM"; do
        if [ ! -f "$FILE" ]; then
            echo "[-] ERROR: Snapshot is incomplete or does not exist:"
            echo "    $ID"
            echo "    Missing: $FILE"
            exit 1
        fi
    done

    echo "=== CONFIGURATION SNAPSHOT ==="
    echo
    echo "Snapshot ID:"
    echo "  $ID"
    echo
    if [ -f "$BASELINE_POINTER" ] && [ "$(cat "$BASELINE_POINTER")" = "$ID" ]; then
        echo "Accepted baseline: YES"
    else
        echo "Accepted baseline: NO"
    fi
    echo
    echo "Configured paths recorded with this snapshot:"
    load_paths "$PATH_COPY"
    for ITEM in "${PATHS[@]}"; do
        echo "  $ITEM"
    done
    echo
    echo "Top-level contents actually present in the tar archive:"
    tar -tzf "$ARCHIVE" | awk -F/ '
        {
            path=$0
            sub(/^\.\//, "", path)
            sub(/^\//, "", path)
            if (path == "") next
            split(path, part, "/")
            if (!(part[1] in seen)) {
                seen[part[1]]=1
                print "  /" part[1]
            }
        }
    ' | LC_ALL=C sort
    echo
    echo "Archive:"
    echo "  $ARCHIVE"
    echo "Manifest:"
    echo "  $MANIFEST"
    echo "Checksum:"
    echo "  $CHECKSUM"
}

list_snapshots()
{
    if [ "$#" -eq 1 ]; then
        list_snapshot_details "$1"
        return
    fi

    if [ "$#" -ne 0 ]; then
        usage
        exit 2
    fi

    echo "=== CONFIGURATION SNAPSHOTS ==="
    echo

    if [ -f "$BASELINE_POINTER" ]; then
        echo "Accepted baseline:"
        echo "  $(cat "$BASELINE_POINTER")"
    else
        echo "Accepted baseline:"
        echo "  NONE"
    fi

    echo
    echo "Available snapshots:"

    FOUND=0

    while IFS= read -r FILE; do
        [ -z "$FILE" ] && continue
        FOUND=1
        basename "$FILE" .manifest
    done < <(
        find "$BACKUP_DIR" \
            -maxdepth 1 \
            -type f \
            -name "${HOST_LABEL}-config-*.manifest" \
            -print | LC_ALL=C sort
    )

    if [ "$FOUND" -eq 0 ]; then
        echo "  NONE"
    fi
}

uninstall_information()
{
    echo "=== CONFIG-AUDIT — UNINSTALL INFORMATION ==="
    echo
    echo "config-audit deliberately does not automatically delete its"
    echo "program, configuration, snapshots, baselines or reports."
    echo
    echo "Review these locations before deleting anything:"
    echo
    echo "Program:"
    echo "  /usr/local/bin/config-audit.sh"
    echo
    echo "Configuration:"
    echo "  $CONFIG_DIR"
    echo
    echo "Documentation, licence and disclaimer:"
    echo "  /usr/local/share/doc/config-audit"
    echo
    echo "Archive storage:"
    echo "  $BACKUP_DIR"
    echo
    echo "WARNING: The archive directory may contain configuration"
    echo "snapshots, accepted baselines and audit reports that remain"
    echo "valuable after the utility itself is removed."
    echo
    echo "If, after review, you choose to remove these manually:"
    echo
    echo "  Program only:"
    echo "    sudo rm /usr/local/bin/config-audit.sh"
    echo
    echo "  Program configuration:"
    echo "    sudo rm -rf -- $CONFIG_DIR"
    echo
    echo "  Documentation, licence and disclaimer:"
    echo "    sudo rm -rf -- /usr/local/share/doc/config-audit"
    echo
    echo "  Archived snapshots and reports:"
    echo "    sudo rm -rf -- $BACKUP_DIR"
    echo
    echo "No files have been removed."
}


usage()
{
    echo "Usage:"
    echo
    echo "  sudo $0 snapshot [label]"
    echo "  sudo $0 check"
    echo "  sudo $0 accept SNAPSHOT-ID"
    echo "  sudo $0 list [SNAPSHOT-ID]"
    echo "  sudo $0 uninstall"
    echo "  sudo $0 version"
}


COMMAND="${1:-}"

case "$COMMAND" in

    snapshot)
        shift
        if [ "$#" -gt 1 ]; then
            usage
            exit 2
        fi
        snapshot "${1:-}"
        ;;

    check)
        shift
        if [ "$#" -ne 0 ]; then
            usage
            exit 2
        fi
        check
        ;;

    accept)
        shift
        accept_snapshot "$@"
        ;;

    list)
        shift
        if [ "$#" -gt 1 ]; then
            usage
            exit 2
        fi
        list_snapshots "$@"
        ;;

    uninstall)
        shift
        if [ "$#" -ne 0 ]; then
            usage
            exit 2
        fi
        uninstall_information
        ;;

    version|--version|-V)
        shift
        if [ "$#" -ne 0 ]; then
            usage
            exit 2
        fi
        echo "config-audit $VERSION"
        ;;

    *)
        usage
        exit 2
        ;;
esac