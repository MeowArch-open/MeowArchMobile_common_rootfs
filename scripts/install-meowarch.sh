#!/usr/bin/env bash
set -euo pipefail

root=${1:?usage: install-meowarch.sh ROOTFS COMPONENTS [ARTIFACTS]}
components=${2:?usage: install-meowarch.sh ROOTFS COMPONENTS [ARTIFACTS]}
artifacts=${3:-}
root=${root%/}
[ -n "$root" ] || root=/

install_dir() {
	local src=$1 dst=$2 mode=${3:-0644}
	[ -d "$src" ] || return 0
	while IFS= read -r -d '' file; do
		local rel=${file#"$src/"}
		install -D -m "$mode" "$file" "$root/$dst/$rel"
	done < <(find "$src" -type f -print0)
}

install_network_dir() {
	local src=$1
	[ -d "$src" ] || return 0
	while IFS= read -r -d '' file; do
		local rel=${file#"$src/"}
		install -D -m 0644 "$file" "$root/etc/systemd/network/$rel"
	done < <(find "$src" -type f -name '*.network' -print0)
}

install_modem_modprobe() {
	local src="$components/modem/services/zorn/modprobe"
	[ -d "$src" ] || return 0
	while IFS= read -r -d '' file; do
		local rel=${file#"$src/"}
		# This historical Modem copy blacklists msm. The Display repository's
		# zorn-msm.conf is the current canonical policy and is installed above.
		if [ "$rel" = zorn-msm.conf ]; then
			echo "skip stale modem zorn-msm.conf; display policy is canonical"
			continue
		fi
		install -D -m 0644 "$file" "$root/etc/modprobe.d/$rel"
	done < <(find "$src" -type f -print0)
}

install_units_and_scripts() {
	local unit_src=$1 script_src=$2
	[ -d "$unit_src" ] || return 0
	install_dir "$unit_src" etc/systemd/system 0644
	[ -d "$script_src" ] || return 0
	while IFS= read -r -d '' unit; do
		while IFS= read -r command; do
			command=${command#*=}
			command=${command#-}
			command=${command%% *}
			case "$command" in
				/usr/local/bin/*|/usr/local/sbin/*)
					name=${command##*/}
					candidate=$(find "$script_src" -type f -name "$name" -print -quit)
					[ -n "$candidate" ] || continue
					install -D -m 0755 "$candidate" "$root$command"
					;;
			esac
		done < <(grep -E '^(ExecStart|ExecStartPre|ExecStartPost|ExecStop|ExecStopPost)=' "$unit" || true)
	done < <(find "$unit_src" -type f -name '*.service' -print0)
}

enable_multi_user_units() {
	local list="$components/modem/services/zorn/enabled-multi-user.txt"
	[ -f "$list" ] || return 0
	install -d "$root/etc/systemd/system/multi-user.target.wants"
	while IFS= read -r unit; do
		case "$unit" in
			''|\#*) continue ;;
		esac
		if [ ! -f "$root/etc/systemd/system/$unit" ]; then
			echo "warning: enabled unit is not installed: $unit" >&2
			continue
		fi
		ln -sfn "../$unit" "$root/etc/systemd/system/multi-user.target.wants/$unit"
	done <"$list"
}

[ -d "$components" ] || { echo "missing components root: $components" >&2; exit 1; }

# Shared files.
install_units_and_scripts "$components/common/services/systemd" "$components/common/services/scripts"
install_network_dir "$components/common/services/network"
install_dir "$components/common/services/ssh" etc/ssh/sshd_config.d 0644

# Display runtime files.
install_units_and_scripts "$components/display/services/systemd" "$components/display/services/scripts"
install_dir "$components/display/services/modprobe" etc/modprobe.d 0644
install_dir "$components/display/services/sddm" etc/sddm.conf.d 0644
install_dir "$components/display/services/sddm-theme" usr/share/sddm/themes/zorn 0644

# Audio runtime files. Bring-up experiments are deliberately not installed by
# default; they remain available in the source repository for development.
install_units_and_scripts "$components/audio/services/systemd" "$components/audio/services/scripts"
if [ -f "$components/audio/services/ucm/XiaoMi-K80-zorn-zorn.conf" ]; then
	install -D -m 0644 "$components/audio/services/ucm/XiaoMi-K80-zorn-zorn.conf" \
		"$root/usr/share/alsa/ucm2/conf.d/sm8650/XiaoMi-K80-zorn-zorn.conf"
fi
if [ -f "$components/audio/services/ucm/HiFi.conf" ]; then
	install -D -m 0644 "$components/audio/services/ucm/HiFi.conf" \
		"$root/usr/share/alsa/ucm2/Qualcomm/sm8650/zorn/HiFi.conf"
fi

# Touch runtime files. The keychord unit is a user unit, not a system unit.
if [ -f "$components/touch/services/systemd/zorn-keychord.service" ]; then
	install -D -m 0644 "$components/touch/services/systemd/zorn-keychord.service" \
		"$root/etc/systemd/user/zorn-keychord.service"
fi
install_dir "$components/touch/services/modprobe" etc/modprobe.d 0644
if [ -f "$components/touch/services/scripts/zorn-keychord.py" ]; then
	install -D -m 0755 "$components/touch/services/scripts/zorn-keychord.py" \
		"$root/usr/local/bin/zorn-keychord.py"
fi

# Modem runtime files. Build-only source trees, Android references and staged
# test scripts are intentionally not copied into the target rootfs.
install_units_and_scripts "$components/modem/services/zorn/systemd" "$components/modem/services/zorn/scripts"
install_modem_modprobe
install_network_dir "$components/modem/services/zorn/network"

# Wi-Fi runtime files. Hostapd/libnl source is built separately; only the
# target configuration and service enter the rootfs here.
install_units_and_scripts "$components/wifi/services/systemd" "$components/wifi/services/scripts"
install_network_dir "$components/wifi/services/network"
install_dir "$components/wifi/services/network/hostapd" etc/hostapd 0644

enable_multi_user_units

# Component firmware is a direct runtime dependency. Fail on differing
# collisions rather than silently choosing whichever subsystem was visited
# last.
for component in display audio modem; do
	src="$components/$component/firmware/qcom"
	[ -d "$src" ] || continue
	while IFS= read -r -d '' file; do
		rel=${file#"$src/"}
		dest="$root/usr/lib/firmware/qcom/$rel"
		if [ -e "$dest" ] && ! cmp -s "$file" "$dest"; then
			echo "firmware collision: $dest" >&2
			exit 1
		fi
		install -D -m 0644 "$file" "$dest"
	done < <(find "$src" -type f -print0)
done

# Optional output from the kernel/userspace component build stages. It must be
# a rootfs-shaped tree (usr/lib/modules, usr/local/sbin, ...).
if [ -n "$artifacts" ]; then
	[ -d "$artifacts" ] || { echo "missing artifacts root: $artifacts" >&2; exit 1; }
	if [ -d "$artifacts/usr/local" ]; then
		while IFS= read -r -d '' file; do
			rel=${file#"$artifacts/"}
			install -D -m 0755 "$file" "$root/$rel"
		done < <(find "$artifacts/usr/local" -type f -print0)
	fi
	if [ -d "$artifacts/usr/lib" ]; then
		while IFS= read -r -d '' file; do
			rel=${file#"$artifacts/"}
			install -D -m 0644 "$file" "$root/$rel"
		done < <(find "$artifacts/usr/lib" -type f -print0)
	fi
fi

echo "installed MeowArch runtime files into $root"
