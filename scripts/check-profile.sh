#!/usr/bin/env bash
set -euo pipefail

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
profile="$repo_dir/profiles/zorn"
explicit="$profile/packages.explicit"
aur="$profile/aur.lock.tsv"
protected="$profile/packages.protected.tsv"
policy="$repo_dir/config/pacman/99-meowarch-protected.conf"
hook="$repo_dir/config/pacman/90-meowarch-protected.hook"
fail=0

count=$(awk 'NF && $1 !~ /^#/ {print $1}' "$explicit" | sort -u | wc -l)
if [ "$count" -ne 57 ]; then
	echo "explicit package count: expected 57, got $count" >&2
	fail=1
else
	echo "OK explicit package count: $count"
fi

aur_count=$(awk 'NF && $1 !~ /^#/ {print $1}' "$aur" | sort -u | wc -l)
if [ "$aur_count" -ne 7 ]; then
	echo "AUR lock count: expected 7, got $aur_count" >&2
	fail=1
else
	echo "OK AUR lock count: $aur_count"
fi

while IFS=$'\t' read -r package expected commit arch kind; do
	case "$package" in
		''|\#*) continue ;;
	esac
	if [ "$kind" = binary ] && [[ "$arch" != aarch64 && "$arch" != any ]]; then
		echo "unexpected binary architecture: $package $arch" >&2
		fail=1
	fi
done <"$aur"

while IFS=$'\t' read -r package expected reason; do
	case "$package" in
		''|\#*) continue ;;
	esac
	if [[ "$package" == linux-firmware-* ]]; then
		policy_ok=$(grep -F 'linux-firmware-*' "$policy" || true)
		hook_ok=$(grep -F 'Target = linux-firmware-*' "$hook" || true)
	else
		policy_ok=$(grep -F "$package" "$policy" || true)
		hook_ok=$(grep -F "Target = $package" "$hook" || true)
	fi
	if [ -z "$policy_ok" ] || [ -z "$hook_ok" ]; then
		echo "protected package is not covered by policy: $package" >&2
		fail=1
	fi
done <"$protected"

if [ "$fail" -eq 0 ]; then
	echo "profile checks passed"
fi
exit "$fail"
