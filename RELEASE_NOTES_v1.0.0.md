# config-audit v1.0.0

`config-audit` is a conservative Linux configuration snapshot and drift-audit utility.

Version 1.0.0 provides timestamped configuration archives, manifests, SHA-256 verification, snapshot-stability checking, explicit baseline acceptance, drift reports, snapshot inspection, configurable archive storage, and a non-destructive uninstall-information command.

The release includes `install.sh`. The installer places the program at `/usr/local/bin/config-audit.sh` and installs the README, licence and disclaimer under `/usr/local/share/doc/config-audit/`. Configuration and archive locations are created/configured interactively on first run rather than by the installer.

The utility does not provide selective restore, automatic rollback or automatic deletion of stored evidence.

If the configured archive directory later disappears, the utility refuses to recreate it silently or write elsewhere. Missing paths in new snapshots stop snapshot creation; missing paths in an accepted baseline generate a warning while `check` continues so resulting drift can be reported.

Local configuration snapshots are not a substitute for an independent off-machine backup.

Licensed under GPL-3.0-or-later. The standard unmodified GPLv3 licence text is supplied in `LICENSE`.

**YOU USE THIS SOFTWARE AT YOUR OWN RISK.**
