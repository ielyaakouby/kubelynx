#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

# shellcheck source=installer/lib.sh
source installer/lib.sh

fake_home="$(mktemp -d "${TMPDIR:-/tmp}/kubelynx-install-test.XXXXXX")"
trap 'rm -rf "$fake_home"' EXIT

export HOME="$fake_home"
unset XDG_DATA_HOME
unset KUBELYNX_INSTALL_DIR
unset KUBELYNX_BIN_DIR

install_dir="$(kubelynx::install_dir)"
bin_dir="$(kubelynx::bin_dir)"
link="$(kubelynx::bin_link)"

[[ "$install_dir" == "${fake_home}/.local/share/kubelynx" ]] || fail "install dir: $install_dir"
[[ "$bin_dir" == "${fake_home}/.local/bin" ]] || fail "bin dir: $bin_dir"
[[ "$link" == "${fake_home}/.local/bin/kubelynx" ]] || fail "bin link: $link"

kubelynx::is_safe_install_dir "$install_dir" || fail "expected install dir to be safe"
kubelynx::is_safe_install_dir "/" && fail "refused / should be unsafe"
kubelynx::is_safe_install_dir "$HOME" && fail "HOME should be unsafe"
kubelynx::is_safe_install_dir "${HOME}/not-kubelynx" && fail "non-kubelynx basename should be unsafe"

export KUBELYNX_INSTALL_DIR="${fake_home}/custom-prefix/kubelynx"
[[ "$(kubelynx::install_dir)" == "${fake_home}/custom-prefix/kubelynx" ]] || fail "KUBELYNX_INSTALL_DIR ignored"

# End-to-end user-space install / uninstall against a fake HOME.
unset KUBELYNX_INSTALL_DIR
mkdir -p "$bin_dir"
bash "${ROOT}/installer/install.sh"

[[ -L "$link" ]] || fail "expected symlink $link"
[[ -d "$(kubelynx::install_dir)" ]] || fail "expected install directory"
[[ -f "$(kubelynx::install_dir)/VERSION" ]] || fail "installed tree missing VERSION"
"$link" --version | grep -q '^KubeLynx v' || fail "installed binary --version failed"

bash "${ROOT}/installer/uninstall.sh"
[[ -L "$link" ]] && fail "symlink still present after uninstall"
[[ -d "$(kubelynx::install_dir)" ]] && fail "install dir still present after uninstall"

# Uninstall is idempotent.
bash "${ROOT}/installer/uninstall.sh"

# Pre-rename Kubediag layout: migrate the data dir and drop the old CLI symlink.
# The "kubediag" names below are intentional legacy paths.
legacy_dir="${fake_home}/.local/share/kubediag"
legacy_link="${fake_home}/.local/bin/kubediag"
mkdir -p "$legacy_dir/bin" "$legacy_dir/src/k8s" "$bin_dir"
printf '3.0.0\n' >"$legacy_dir/VERSION"
printf '#!/bin/sh\necho legacy\n' >"$legacy_dir/bin/kubediag.sh"
chmod +x "$legacy_dir/bin/kubediag.sh"
ln -sfn "$legacy_dir/bin/kubediag.sh" "$legacy_link"

bash "${ROOT}/installer/install.sh"
[[ ! -e "$legacy_dir" ]] || fail "legacy Kubediag directory should have been migrated"
[[ ! -L "$legacy_link" ]] || fail "legacy kubediag symlink should have been removed"
[[ -d "$(kubelynx::install_dir)" ]] || fail "expected migrated/installed KubeLynx directory"
[[ -L "$link" ]] || fail "expected kubelynx symlink after migration"
"$link" --version | grep -q '^KubeLynx v' || fail "migrated install --version failed"

bash "${ROOT}/installer/uninstall.sh"
