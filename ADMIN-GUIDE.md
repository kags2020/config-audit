# config-audit Administrator's Guide

This guide provides detailed installation, configuration, security and operational information for `config-audit`.

For a quick introduction, installation summary and basic usage, see the [README](README.md).

## Requirements

- Bash
- GNU/Linux utilities used by the script, including `tar`, `find`, `stat`, `sha256sum`, `awk`, `sort`, `cmp`, `readlink` and `mktemp`
- root privileges for normal operation
- GNU `tar` with ACL and extended-attribute support

## Installation

Download and extract the `config-audit-v1.0.0.tar.gz` release archive, then change into the extracted directory.

Install with:

```text
sudo sh install.sh
```

The installer explains what it will install and requires explicit confirmation. It installs:

```text
/usr/local/bin/config-audit.sh
/usr/local/share/doc/config-audit/README.md
/usr/local/share/doc/config-audit/LICENSE
```

The documentation directory includes the licence and disclaimer. The installer sets the installed program to `root:root` mode `0755`, the documentation directory to `root:root` mode `0755`, and the documentation files to `root:root` mode `0644`.

The installer does **not** create or alter `/etc/config-audit` or any configuration archive directory. These are created and configured as part of the first run. After installation, start the utility with:

```text
sudo /usr/local/bin/config-audit.sh
```

On first run, `config-audit` explains and asks permission before creating its permanent configuration directory:

```text
/etc/config-audit
```

Normal configuration permissions are:

```text
/etc/config-audit             root:root 0755
/etc/config-audit/config.conf root:root 0644
/etc/config-audit/paths.conf  root:root 0644
```

The default archive parent is `/var/backups`, producing `/var/backups/config-audit`. The archive location is configurable during first-run setup. If an alternative parent directory is supplied, `config-audit` creates a `config-audit` directory **inside** that parent and does not change ownership or permissions on the supplied parent.

Before a new archive directory is created or an existing one is secured, the proposed path, ownership and mode are displayed and confirmation is required. Existing directories are inspected before ownership or permissions are changed.

The private archive directory and reports directory are maintained as `root:root` mode `0700`. Snapshot archives, manifests, stored path definitions, checksums and reports are written with restrictive permissions.

## Configuration

`/etc/config-audit/config.conf` sets the directory in which configuration archives are stored. This can be changed to a location of your choice. The default setting is:

```text
BACKUP_DIR="/var/backups/config-audit"
```

When choosing an alternative location during first-run setup, specify the **parent directory**. `config-audit` creates and uses a `config-audit` directory inside it and does not change the ownership or permissions of the parent directory.

`/etc/config-audit/paths.conf` defines what is included in snapshots and drift audits. It contains one absolute path per line. Blank lines and lines beginning with `#` are ignored.

A fresh installation starts with:

```text
/etc
```

Add other configuration locations deliberately when required. The path definition stored with an accepted snapshot is used for future drift checks, preventing a later edit to the current `paths.conf` from silently reducing the scope of an established baseline.

If the archive directory recorded in `config.conf` is later missing, renamed or moved, `config-audit` refuses to recreate it silently or write elsewhere. It identifies the configured location, asks the user to acknowledge the condition, and exits without writing archive or audit data.

If a path included in a new snapshot is missing, snapshot creation is refused until the intended audit scope is reviewed. During `check`, however, a path missing from the accepted baseline scope is reported as a warning and the audit continues so that the resulting drift can be shown. Editing the current `paths.conf` alone does not rewrite the scope of an already accepted baseline.

## Commands

Create a snapshot without changing the accepted baseline:

```text
sudo /usr/local/bin/config-audit.sh snapshot [label]
```

Compare the current configuration with the accepted baseline:

```text
sudo /usr/local/bin/config-audit.sh check
```

Explicitly accept an existing complete snapshot as the baseline:

```text
sudo /usr/local/bin/config-audit.sh accept SNAPSHOT-ID
```

List snapshots and the accepted baseline:

```text
sudo /usr/local/bin/config-audit.sh list
```

Inspect one snapshot, including the paths recorded with it and the top-level contents actually present in its tar archive:

```text
sudo /usr/local/bin/config-audit.sh list SNAPSHOT-ID
```

Display non-destructive uninstall information:

```text
sudo /usr/local/bin/config-audit.sh uninstall
```

Display the version:

```text
sudo /usr/local/bin/config-audit.sh version
```

## Snapshot contents

A successful snapshot normally creates:

- `SNAPSHOT-ID.tar.gz` — archived configuration data
- `SNAPSHOT-ID.tar.gz.sha256` — SHA-256 checksum
- `SNAPSHOT-ID.manifest` — path, type, mode, numeric ownership and file hash/link-target information
- `SNAPSHOT-ID.paths` — the path definition used for that snapshot

A snapshot is checked for configuration instability by comparing manifests generated immediately before and after archive creation. If configuration changes during the operation, the archive is retained as `.unstable`, an instability report is written, and the snapshot is not treated as a coherent checkpoint.

## Baselines and drift

Creating a snapshot does **not** make it trusted. `accept SNAPSHOT-ID` is a separate explicit administrative action.

`check` compares the live system against the manifest and path definition stored with the accepted baseline. It reports added, deleted and modified entries without displaying file contents.

## Backups

**Local configuration snapshots are not a substitute for an independent off-machine backup.**

`config-audit` protects against some forms of accidental change and provides useful local evidence, but a local archive can be lost or compromised with the host itself. Important systems should also have an appropriate independent backup strategy.

## Uninstall behaviour

The `uninstall` command is intentionally informational only. It displays the installed program path, configuration directory, documentation directory (including licence and disclaimer), and the **currently configured** archive directory, together with manual removal commands. It deletes nothing automatically.

This is deliberate: archived configuration snapshots, accepted baselines and audit reports may remain valuable after the utility itself is no longer required.

## Security notes

- The program must be run as root.
- `config.conf` and `paths.conf` are parsed as configuration data; they are not sourced as shell code.
- Control files must be regular root-owned files and must not be writable by group or others.
- The configuration directory must be an ordinary root-owned directory and must not be writable by group or others.
- The archive and reports directories must be ordinary root-owned directories with mode `0700` during normal operation.
- The utility refuses symbolic links in security-sensitive control-directory/file positions rather than silently following or altering them.
- The supplied parent of a custom archive location is never chmod'd or chown'd by the utility.

## Scope and limitations

`config-audit` is deliberately simple. Version 1.0.0 does not provide selective restore, automatic rollback, remote/off-machine backup, package management integration or automatic removal of stored evidence.

Review a snapshot and the live system before accepting a new baseline. Treat a snapshot as evidence and a recovery aid, not as proof that the captured configuration was correct or trustworthy.

## Licence

`config-audit` is licensed under **GPL-3.0-or-later**. See `LICENSE` for the standard, unmodified GNU General Public License version 3 text.

This program is distributed in the hope that it will be useful, but **WITHOUT ANY WARRANTY**; without even the implied warranty of **MERCHANTABILITY** or **FITNESS FOR A PARTICULAR PURPOSE**. See the GNU General Public License for details.


**YOU USE THIS SOFTWARE AT YOUR OWN RISK.**
