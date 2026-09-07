#!/usr/bin/env bash
set -euo pipefail

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
profile="$repo_dir/profiles/zorn"
root=
pacman_conf=/etc/pacman.conf
aur_dir=
components=
artifacts=
protected_package_dir=
compat_package_dir=
skip_official=0
skip_aur=0

usage() {
	cat <<'EOF'
usage: build-rootfs.sh --root ROOTFS [options]

Options:
  --root DIR             target Arch rootfs (required)
  --pacman-conf FILE     pacman config used for official packages
  --aur-dir DIR          install packages built by build-aur.sh
  --components DIR       sibling MeowArch component checkouts
  --artifacts DIR        rootfs-shaped compiled component artifacts
  --protected-package-dir DIR
                         exact kernel/firmware packages captured from device
  --compat-package-dir DIR
                         temporary ABI-coherence seed packages; not protected
  --skip-official        do not run the official package transaction
  --skip-aur             allow a base-only rootfs without the AUR layer
EOF
}

while [ "$#" -gt 0 ]; do
	case "$1" in
		--root) root=$2; shift 2 ;;
		--pacman-conf) pacman_conf=$2; shift 2 ;;
		--aur-dir) aur_dir=$2; shift 2 ;;
		--components) components=$2; shift 2 ;;
		--artifacts) artifacts=$2; shift 2 ;;
		--protected-package-dir) protected_package_dir=$2; shift 2 ;;
		--compat-package-dir) compat_package_dir=$2; shift 2 ;;
		--skip-official) skip_official=1; shift ;;
		--skip-aur) skip_aur=1; shift ;;
		-h|--help) usage; exit 0 ;;
		*) echo "unknown option: $1" >&2; usage >&2; exit 2 ;;
	esac
done

[ -n "$root" ] || { usage >&2; exit 2; }
root=${root%/}
[ -n "$root" ] || root=/
[ -f "$pacman_conf" ] || { echo "missing pacman config: $pacman_conf" >&2; exit 1; }
command -v pacman >/dev/null || { echo "pacman is required" >&2; exit 1; }

# The ARM64 builder commonly runs through qemu-user on an x86 host.  Such a
# container inherits a host kernel without Landlock, while pacman 7 enables
# its downloader sandbox by default.  Keep the build usable there; callers
# with a working Landlock implementation can set this to 0.
pacman_sandbox_args=()
if [ "${MEOWARCH_DISABLE_PACMAN_SANDBOX:-1}" = 1 ]; then
	pacman_sandbox_args+=(--disable-sandbox)
fi

mapfile -t packages < <(awk 'NF && $1 !~ /^#/ {print $1}' "$profile/packages.explicit")
mapfile -t tools < <(awk 'NF && $1 !~ /^#/ {print $1}' "$profile/packages.tools")

declare -A aur_names=()
while IFS=$'\t' read -r package expected commit arch kind; do
	case "$package" in
		''|\#*) continue ;;
	esac
	aur_names["$package"]=1
done <"$profile/aur.lock.tsv"

declare -A protected_names=()
while IFS=$'\t' read -r package version reason; do
	case "$package" in
		''|\#*) continue ;;
	esac
	protected_names["$package"]="$version"
done <"$profile/packages.protected.tsv"

protected_version() {
	awk -F '\t' -v name="$1" '$1 == name {print $2; exit}' "$profile/packages.protected.tsv"
}

declare -A seen=()
official_args=()
protected_files=()
compat_files=()

if [ -n "$protected_package_dir" ]; then
	[ -d "$protected_package_dir" ] || {
		echo "missing protected package directory: $protected_package_dir" >&2
		exit 1
	}
	declare -A protected_file_by_name=()
	shopt -s nullglob
	candidates=("$protected_package_dir"/*.pkg.tar.*)
	shopt -u nullglob
	for candidate in "${candidates[@]}"; do
		info=$(pacman --config /dev/null -Qp -i "$candidate")
		got_package=$(sed -n 's/^Name[[:space:]]*: //p' <<<"$info")
		got_version=$(sed -n 's/^Version[[:space:]]*: //p' <<<"$info")
		[ -n "$got_package" ] || continue
		[ -n "${protected_names[$got_package]+yes}" ] || continue
		[ "$got_version" = "${protected_names[$got_package]}" ] || continue
		protected_file_by_name["$got_package"]=$candidate
	done
	for package in "${!protected_names[@]}"; do
		version=${protected_names[$package]}
		match=${protected_file_by_name[$package]-}
		[ -n "$match" ] || {
			echo "missing exact protected package: $package=$version in $protected_package_dir" >&2
			exit 1
		}
		protected_files+=("$match")
	done
fi

if [ -n "$compat_package_dir" ]; then
	[ -d "$compat_package_dir" ] || {
		echo "missing compatibility package directory: $compat_package_dir" >&2
		exit 1
	}
	shopt -s nullglob
	compat_files=("$compat_package_dir"/*.pkg.tar.*)
	shopt -u nullglob
fi

for package in "${packages[@]}" "${tools[@]}"; do
	if [ -n "${aur_names[$package]+yes}" ]; then
		continue
	fi
	if [ -n "${seen[$package]+yes}" ]; then
		continue
	fi
	seen["$package"]=1
	if [ -n "$protected_package_dir" ] && [ -n "${protected_names[$package]+yes}" ]; then
		continue
	fi
	version=$(protected_version "$package")
	if [ -n "$version" ]; then
		official_args+=("$package=$version")
	else
		official_args+=("$package")
	fi
done

# Include protected packages that were split out of an explicit package.
while IFS=$'\t' read -r package version reason; do
	case "$package" in
		''|\#*) continue ;;
	esac
	if [ -z "${seen[$package]+yes}" ]; then
		seen["$package"]=1
		if [ -z "$protected_package_dir" ]; then
			official_args+=("$package=$version")
		fi
	fi
done <"$profile/packages.protected.tsv"

if [ "$skip_official" -eq 0 ]; then
	install -d "$root" "$root/var/lib/pacman" "$root/var/cache/pacman/pkg"
	# Run this in an Arch ARM environment (or an equivalent aarch64 chroot).
	# The protected versions are part of the transaction, so an unavailable
	# historical package causes a hard failure instead of a silent upgrade.
	# The target root has its own empty dbpath; sync its repository databases
	# before resolving the official package set.
	pacman --config "$pacman_conf" --root "$root" \
		--dbpath "$root/var/lib/pacman" --cachedir "$root/var/cache/pacman/pkg" \
		"${pacman_sandbox_args[@]}" -Sy --noconfirm
	if [ "${#protected_files[@]}" -gt 0 ]; then
		# These packages were reconstructed or captured from the device and are
		# intentionally installed before resolving ordinary dependencies.  The
		# normal transaction below then sees the exact protected versions as
		# already installed instead of selecting a newer repository version.
		pacman --config "$pacman_conf" --root "$root" \
			--dbpath "$root/var/lib/pacman" --cachedir "$root/var/cache/pacman/pkg" \
			"${pacman_sandbox_args[@]}" -U --needed --nodeps --noconfirm "${protected_files[@]}"
	fi
	if [ "${#compat_files[@]}" -gt 0 ]; then
		# Compatibility seeds solve transient rolling-repository ABI gaps. They
		# are not added to the protected-package policy and remain upgradeable.
		pacman --config "$pacman_conf" --root "$root" \
			--dbpath "$root/var/lib/pacman" --cachedir "$root/var/cache/pacman/pkg" \
			"${pacman_sandbox_args[@]}" -U --needed --nodeps --noconfirm "${compat_files[@]}"
	fi
	pacman --config "$pacman_conf" --root "$root" \
		--dbpath "$root/var/lib/pacman" --cachedir "$root/var/cache/pacman/pkg" \
		"${pacman_sandbox_args[@]}" -S --needed --noconfirm "${official_args[@]}"
fi

"$repo_dir/scripts/install-pacman-policy.sh" "$root"

if [ "$skip_aur" -eq 0 ]; then
	[ -n "$aur_dir" ] || { echo "AUR packages are required; pass --aur-dir or use --skip-aur" >&2; exit 1; }
	[ -d "$aur_dir" ] || { echo "missing AUR directory: $aur_dir" >&2; exit 1; }
	shopt -s nullglob
	aur_packages=("$aur_dir"/*.pkg.tar.*)
	shopt -u nullglob
	[ "${#aur_packages[@]}" -gt 0 ] || { echo "no AUR packages in $aur_dir" >&2; exit 1; }
	pacman --config "$pacman_conf" --root "$root" \
		--dbpath "$root/var/lib/pacman" --cachedir "$root/var/cache/pacman/pkg" \
		"${pacman_sandbox_args[@]}" -U --needed --noconfirm "${aur_packages[@]}"
else
	echo "AUR layer skipped"
fi

if [ -n "$components" ]; then
	args=("$root" "$components")
	[ -n "$artifacts" ] && args+=("$artifacts")
	"$repo_dir/scripts/install-meowarch.sh" "${args[@]}"
else
	echo "MeowArch runtime layer skipped; pass --components if required"
fi

"$repo_dir/scripts/check-protected.sh" "$root"
echo "rootfs assembly complete: $root"
