# config-audit

## How can I back up /etc and see what configuration files changed?

That is exactly what `config-audit` is designed to do.

`config-audit` backs up your Linux system configuration in a compressed, timestamped archive, including all of `/etc` by default and any additional files or directories you choose.

Run it again and `config-audit` compares your current configuration with an explicitly accepted baseline archive, clearly reporting every file that has been **added, deleted or modified**, whether you expected the change or not!

The archive is more than an audit record. If an important configuration file is deleted, damaged or incorrectly modified, you have a preserved copy from before the change that can be extracted and used to help put things right.

**Know your configuration. Know what changed. Keep the copy you may need to recover it.**

## Key features

* Backs up all of `/etc` by default.
* Add any other configuration files or directories you want to protect.
* Creates compressed, timestamped configuration archives.
* Uses SHA-256 integrity verification.
* Reports added, deleted and modified files against an accepted baseline.
* Keeps baseline acceptance as a separate, explicit administrative decision.
* Lets you inspect stored snapshots and their configured paths.
* Uses a configurable archive location.
* Does not automatically modify or restore your configuration.

## Requirements

`config-audit` is intended for GNU/Linux systems and requires Bash, GNU `tar`, standard GNU/Linux utilities and root privileges for normal operation.

## Installation

Download the prepared `config-audit-v1.0.0.tar.gz` release archive from the GitHub Releases page.

Extract it:

```text
tar -xzf config-audit-v1.0.0.tar.gz
cd config-audit-v1.0.0
```

Install it:

```text
sudo sh install.sh
```

The installed program is:

```text
/usr/local/bin/config-audit.sh
```

On first run, `config-audit` guides you through configuration and asks permission before creating its configuration and archive directories.

## Quick start

Create a configuration snapshot:

```text
sudo /usr/local/bin/config-audit.sh snapshot
```

List available snapshots:

```text
sudo /usr/local/bin/config-audit.sh list
```

Accept a snapshot as the baseline you want future checks compared against:

```text
sudo /usr/local/bin/config-audit.sh accept SNAPSHOT-ID
```

Check the current system against that accepted baseline:

```text
sudo /usr/local/bin/config-audit.sh check
```

A check reports configuration entries that have been:

**Added — Deleted — Modified**

without displaying the contents of changed files.

## Your archive can help you recover

`config-audit` does not automatically restore files.

However, each snapshot contains preserved copies of the configuration paths you selected. If a configuration file is later deleted, damaged or incorrectly modified, the archived copy can be extracted and used as a recovery aid.

This deliberate separation keeps restoration under the administrator's control.

## Full documentation

For detailed information about configuration, archive locations, permissions, snapshot contents, accepted baselines, security controls, uninstall behaviour and operational details, see:

**[Administrator's Guide](ADMIN-GUIDE.md)**

## Important backup note

**Local configuration snapshots are not a substitute for an independent off-machine backup.**

A local archive can be lost or compromised along with the host itself. Important systems should also have an appropriate independent backup strategy.

## Licence

`config-audit` is licensed under **GPL-3.0-or-later**.

See [LICENSE](LICENSE) for the standard, unmodified GNU General Public License version 3 text.

**YOU USE THIS SOFTWARE AT YOUR OWN RISK.**
