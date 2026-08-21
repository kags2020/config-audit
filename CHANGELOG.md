# Changelog

## 1.0.0

- Initial public release.
- Configuration snapshots with SHA-256 verification and stability checking.
- Explicit accepted-baseline workflow and drift reporting.
- First-run configuration with fixed `/etc/config-audit` control files and configurable private archive storage.
- Conservative handling of existing directories; user-supplied archive parents are never chmod'd or chown'd.
- `list SNAPSHOT-ID` inspection of stored audit paths and top-level archive contents.
- Defensive handling of missing archive directories and missing audit paths.
- Non-destructive uninstall information.
- `install.sh` for `/usr/local/bin` installation and permanent local documentation under `/usr/local/share/doc/config-audit/`.
- GPL-3.0-or-later licensing and visible at-your-own-risk notice on each invocation.
