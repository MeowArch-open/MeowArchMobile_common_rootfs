#!/usr/bin/env bash
set -euo pipefail

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
root=${1:-/}
root=${root%/}
[ -n "$root" ] || root=/
pacman_bin=${PACMAN:-pacman}
dbpath="$root/var/lib/pacman"
lock="$repo_dir/profiles/zorn/packages.protected.tsv"

[ -d "$dbpath/local" ] || { echo "missing pacman database: $dbpath/local" >&2; exit 1; }

fail=0
while IFS=$'\t' read -r package expected reason; do
	case "$package" in
		''|\#*) continue ;;
	esac
	line=$($pacman_bin --config /dev/null --root "$root" --dbpath "$dbpath" -Q "$package" 2>/dev/null || true)
	read -r got_package got_version _ <<<"$line"
	if [ "$got_package" != "$package" ] || [ "$got_version" != "$expected" ]; then
		echo "MISMATCH $package: expected $expected, got ${got_version:-not-installed} ($reason)" >&2
		fail=1
	else
		echo "OK        $package $got_version"
	fi
done <"$lock"

exit "$fail"
