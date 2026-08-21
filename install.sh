#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
set -eu

PROGRAM_SRC="config-audit.sh"
README_SRC="README.md"
LICENSE_SRC="LICENSE"
BIN_DIR="/usr/local/bin"
PROGRAM_DST="${BIN_DIR}/config-audit.sh"
DOC_DIR="/usr/local/share/doc/config-audit"

if [ "$(id -u)" -ne 0 ]; then
    echo "[-] ERROR: install.sh must be run as root." >&2
    echo "    Run: sudo sh install.sh" >&2
    exit 2
fi

for f in "$PROGRAM_SRC" "$README_SRC" "$LICENSE_SRC"; do
    if [ ! -f "$f" ]; then
        echo "[-] ERROR: Required release file not found: $f" >&2
        echo "    Run the installer from the extracted config-audit release directory." >&2
        exit 2
    fi
done

echo "=============================================="
echo " CONFIG-AUDIT INSTALLER"
echo "=============================================="
echo
echo "This installer will install:"
echo
echo "  Program:"
echo "    $PROGRAM_DST"
echo
echo "  Documentation:"
echo "    $DOC_DIR/"
echo "    including the licence and disclaimer."
echo
echo "It will NOT create or alter:"
echo "  /etc/config-audit"
echo "or any configuration archive directory."
echo
echo "Those locations are configured interactively when"
echo "config-audit is run for the first time."
echo
if [ -e "$PROGRAM_DST" ] || [ -e "$DOC_DIR" ]; then
    echo "An existing config-audit installation or documentation was detected."
    echo "Existing files will be replaced only after your confirmation."
    echo
fi
printf "Proceed with installation? [y/N] "
IFS= read -r answer
case "$answer" in y|Y) ;; *) echo "Installation cancelled. No files have been installed."; exit 0;; esac

if [ -L "$BIN_DIR" ]; then
    echo "[-] ERROR: $BIN_DIR is a symbolic link." >&2
    echo "    Refusing to alter or install through it automatically." >&2
    exit 2
fi

if [ -e "$BIN_DIR" ] && [ ! -d "$BIN_DIR" ]; then
    echo "[-] ERROR: $BIN_DIR exists but is not a directory." >&2
    exit 2
fi

if [ ! -d "$BIN_DIR" ]; then
    install -d -o root -g root -m 0755 "$BIN_DIR"
fi

if [ -L "$DOC_DIR" ]; then
    echo "[-] ERROR: Documentation path is a symbolic link:" >&2
    echo "    $DOC_DIR" >&2
    echo "    Refusing to alter it automatically." >&2
    exit 2
fi

if [ -e "$DOC_DIR" ] && [ ! -d "$DOC_DIR" ]; then
    echo "[-] ERROR: Documentation path exists but is not a directory:" >&2
    echo "    $DOC_DIR" >&2
    exit 2
fi

install -d -o root -g root -m 0755 "$DOC_DIR"
install -o root -g root -m 0755 "$PROGRAM_SRC" "$PROGRAM_DST"
install -o root -g root -m 0644 "$README_SRC" "$LICENSE_SRC" "$DOC_DIR/"

echo
echo "Installation complete."
echo
echo "Program installed at:"
echo "  $PROGRAM_DST"
echo
echo "Documentation installed at:"
echo "  $DOC_DIR/"
echo "including the licence and disclaimer."
echo
echo "To start config-audit, run:"
echo "  sudo $PROGRAM_DST"
echo
echo "YOU USE THIS SOFTWARE AT YOUR OWN RISK."
