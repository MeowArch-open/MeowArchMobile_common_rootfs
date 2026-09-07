# MeowArch common rootfs

Arch Linux ARM (`aarch64`) rootfs profile for the Xiaomi `zorn` / SM8650
bring-up.

This repository owns the common Arch userspace and its package policy. It does
not contain the Linux kernel, UEFI, or the Display/Audio/Touch/Modem/Wi-Fi
source trees. Those are separate repositories and are consumed as build
inputs or runtime artifacts.

## Device snapshot

The package database was read from the current Arch partition on 2026-09-07
with Android's pacman, using `var/lib/pacman` directly:

```text
installed packages: 1290
explicit packages:    57
foreign packages:      6
orphan packages:       2
```

`profiles/zorn/packages.explicit` records the explicit package selection. The
dependencies are intentionally not duplicated there; pacman resolves them.
The two packages currently reported as orphans (`go` and `jq`) are retained in
`packages.tools` because they are useful for the build and bring-up workflow.

The device's pacman database contains `linux-aarch64 7.0.11-2`, but the
currently booted kernel is the separately built
`7.0.12-aloha-xingguangcuican`. The packaged kernel is therefore retained as a
protected compatibility package, not treated as the source of the running
kernel.

## Build contract

The intended build order is:

```text
1. bootstrap an Arch ARM rootfs
2. install the official package profile
3. install the pinned-kernel/firmware policy
4. build/install AUR packages from aur.lock (optional profile layer)
5. install runtime files and compiled artifacts from the subsystem repos
6. verify protected package versions
```

Use an Arch ARM build environment, or an equivalent aarch64 chroot. The AUR
recipes are architecture-aware, but `makepkg` must run as a non-root build
user. `-bin` packages still download the upstream aarch64 artifact; they are
not source builds merely because they are built by this repository.

```sh
# Build AUR packages as a normal user.
./scripts/build-aur.sh --out ./out/aur

# Assemble a rootfs as root, using the already-built AUR packages.
./scripts/build-rootfs.sh \
  --root /path/to/arch-root \
  --pacman-conf /etc/pacman.conf \
  --aur-dir ./out/aur \
  --components /path/to/MeowArch

# Verify that the kernel and firmware packages were not changed.
./scripts/check-protected.sh /path/to/arch-root
```

`build-rootfs.sh` does not silently fetch a different kernel or firmware
version. The versions in `profiles/zorn/packages.protected.tsv` are requested
explicitly; if the configured mirror no longer carries one, the build fails.
The target rootfs has a separate pacman database, so the assembly step first
synchronizes the configured repository databases into that target before
resolving the official package profile.

## pacman protection

`config/pacman/99-meowarch-protected.conf` is installed into the target
rootfs and included from `/etc/pacman.conf`. It uses `IgnorePkg` for the
kernel, kernel headers, all currently installed `linux-firmware-*` packages,
and the wireless regulatory database.

`config/pacman/90-meowarch-protected.hook` additionally rejects upgrade or
remove transactions targeting those packages. `scripts/check-protected.sh`
compares the installed versions with the locked versions. A user can always
deliberately delete the policy or invoke a separately configured pacman, so
the lock file and verification step remain part of the release check.

## AUR layer

`profiles/zorn/aur.lock.tsv` records the package version and the exact AUR git
commit observed on the device for the six installed foreign packages. It also
records `clash-geoip`, a runtime dependency required by the current `mihomo`
recipe even though it was not installed on the snapshot device:

```text
cc-switch-bin
hmcl-bin
mihomo
rustdesk-bin
visual-studio-code-bin
yay
clash-geoip
```

The build script checks out those commits before invoking `makepkg`. This
avoids building whatever happens to be at AUR `HEAD` while still keeping the
recipes outside this repository.

## MeowArch component interface

`profiles/zorn/components.lock.tsv` records the expected component repositories
and revisions. `scripts/install-meowarch.sh` consumes a checkout arranged as:

```text
components-root/
├── common/
├── display/
├── audio/
├── touch/
├── modem/
└── wifi/
```

It installs only runtime service/configuration/firmware material. Kernel
source and patches remain the responsibility of the kernel build stage; built
modules and userspace binaries may be supplied through `--artifacts`.

The `temp_work/` directory in the parent extraction tree is not an input to
this repository and must not be included in a release checkout.
