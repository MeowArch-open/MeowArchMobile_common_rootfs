#!/usr/bin/env bash
set -euo pipefail

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
aur_lock="$repo_dir/profiles/zorn/aur.lock.tsv"
compat_lock="$repo_dir/profiles/zorn/compat.lock.tsv"
work=${AUR_WORKDIR:-$repo_dir/.work/aur}
out=${AUR_OUT:-$repo_dir/out/aur}

usage() {
	cat <<'EOF'
usage: build-aur.sh [--out DIR] [--work DIR]

Build the pinned AUR recipes for the zorn profile. Run as a normal Arch build
user, not as root; install the resulting packages with build-rootfs.sh.
EOF
}

while [ "$#" -gt 0 ]; do
	case "$1" in
		--out) out=$2; shift 2 ;;
		--work) work=$2; shift 2 ;;
		-h|--help) usage; exit 0 ;;
		*) echo "unknown option: $1" >&2; usage >&2; exit 2 ;;
	esac
done

[ "$(id -u)" -ne 0 ] || { echo "build-aur.sh must run as a non-root user" >&2; exit 1; }
command -v git >/dev/null || { echo "git is required" >&2; exit 1; }
command -v makepkg >/dev/null || { echo "makepkg is required" >&2; exit 1; }
command -v pacman >/dev/null || { echo "pacman is required" >&2; exit 1; }

mkdir -p "$work" "$out"

build_locked_package() {
	local package=$1 expected=$2 commit=$3 arch=$4 kind=$5 remote=$6
	local dir="$work/$package"
	if [ ! -d "$dir/.git" ]; then
		git clone "$remote" "$dir"
	fi
	git -C "$dir" fetch --quiet origin "$commit"
	git -C "$dir" checkout --quiet --detach "$commit"

	local pkgver pkgrel actual
	pkgver=$(sed -n -E 's/^pkgver=([^#]+).*/\1/p' "$dir/PKGBUILD" | head -n 1)
	pkgrel=$(sed -n -E 's/^pkgrel=([^#]+).*/\1/p' "$dir/PKGBUILD" | head -n 1)
	actual="$pkgver-$pkgrel"
	[ "$actual" = "$expected" ] || {
		echo "$package: PKGBUILD is $actual, lock requires $expected" >&2
		exit 1
	}

	if [ "$kind" = compat ]; then
		local srcinfo build_deps
		srcinfo=$(makepkg --dir "$dir" --printsrcinfo)
		mapfile -t build_deps < <(
			awk -v target="$package" -v arch="$arch" '
				function emit(value) {
					sub(/[<>=].*$/, "", value)
					if (value != "") print value
				}
				$1 == "pkgname" { current = $3; next }
				$1 == "depends" || $1 == "depends_" arch {
					if (current == "" || current == target) emit($3)
					next
				}
				$1 == "makedepends" || $1 == "makedepends_" arch ||
				$1 == "checkdepends" || $1 == "checkdepends_" arch {
					if (current == "") emit($3)
				}
			' <<<"$srcinfo" | sort -u
		)
		[ "${#build_deps[@]}" -gt 0 ] || {
			echo "$package: locked PKGBUILD declares no build dependencies" >&2
			exit 1
		}
		sudo pacman --disable-sandbox -S --needed --noconfirm "${build_deps[@]}"
	fi

	local artifacts artifact info got_package got_version got_arch found=0
	mapfile -t artifacts < <(makepkg --dir "$dir" --packagelist)
	[ "${#artifacts[@]}" -gt 0 ] || { echo "$package: PKGBUILD declares no packages" >&2; exit 1; }

	# Dependencies are installed into the target rootfs as one transaction.
	# --nodeps also permits AUR-to-AUR dependencies such as mihomo ->
	# clash-geoip without modifying the build host's package database.
	makepkg --dir "$dir" --nodeps --noconfirm --cleanbuild --clean --force
	for artifact in "${artifacts[@]}"; do
		[ -f "$artifact" ] || { echo "$package: missing declared artifact: $artifact" >&2; exit 1; }
		info=$(LC_ALL=C pacman --config /dev/null -Qp -i "$artifact")
		got_package=$(sed -n 's/^Name[[:space:]]*: //p' <<<"$info")
		if [ "$got_package" != "$package" ]; then
			echo "$package: leaving split package out of profile: $got_package"
			continue
		fi
		got_version=$(sed -n 's/^Version[[:space:]]*: //p' <<<"$info")
		got_arch=$(sed -n 's/^Architecture[[:space:]]*: //p' <<<"$info")
		[ "$got_version" = "$expected" ] || { echo "$package: artifact is $got_version" >&2; exit 1; }
		[ "$got_arch" = "$arch" ] || { echo "$package: artifact arch is $got_arch, lock requires $arch" >&2; exit 1; }
		cp -f "$artifact" "$out/"
		found=1
		echo "$got_package $got_version ($got_arch, $kind)"
	done
	[ "$found" -eq 1 ] || { echo "$package: makepkg did not produce the locked package" >&2; exit 1; }
}

while IFS=$'\t' read -r package expected commit arch kind; do
	case "$package" in
		''|\#*) continue ;;
	esac
	build_locked_package "$package" "$expected" "$commit" "$arch" "$kind" \
		"https://aur.archlinux.org/$package.git"
done <"$aur_lock"

if [ -f "$compat_lock" ]; then
	while IFS=$'\t' read -r package expected commit arch kind remote; do
		case "$package" in
			''|\#*) continue ;;
		esac
		build_locked_package "$package" "$expected" "$commit" "$arch" "$kind" "$remote"
	done <"$compat_lock"
fi

echo "AUR packages are in $out"
