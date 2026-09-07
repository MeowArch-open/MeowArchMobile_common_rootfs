#!/usr/bin/env bash
set -euo pipefail

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
root=${1:?usage: install-pacman-policy.sh ROOTFS}
root=${root%/}
[ -n "$root" ] || root=/

conf="$root/etc/pacman.conf"
dropin="$root/etc/pacman.conf.d/99-meowarch-protected.conf"
hookdir="$root/etc/pacman.d/hooks"
hook="$hookdir/90-meowarch-protected.hook"
blocker="$root/usr/local/libexec/meowarch/block-protected-transaction"

[ -f "$conf" ] || { echo "missing $conf" >&2; exit 1; }
install -d "$root/etc/pacman.conf.d" "$hookdir" "$(dirname -- "$blocker")"
install -m 0644 "$repo_dir/config/pacman/99-meowarch-protected.conf" "$dropin"
install -m 0644 "$repo_dir/config/pacman/90-meowarch-protected.hook" "$hook"
install -m 0755 "$repo_dir/scripts/block-protected-transaction" "$blocker"

if ! grep -Fq 'Include = /etc/pacman.conf.d/*.conf' "$conf"; then
	cat >>"$conf" <<'EOF'

# MeowArch release policy. Keep this include after the repository definitions.
Include = /etc/pacman.conf.d/*.conf
EOF
fi

echo "installed MeowArch pacman protection into $root"
