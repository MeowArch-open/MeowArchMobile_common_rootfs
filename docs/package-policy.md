# Package policy

## Three package classes

1. `packages.explicit`: the 57 explicitly installed packages observed on the
   device. Dependencies are resolved by pacman.
2. `packages.tools`: `go` and `jq`, which were present but currently orphaned.
3. `aur.lock.tsv`: six foreign packages observed on the device, plus
   `clash-geoip`, which is a transitive runtime dependency of the current
   `mihomo` AUR recipe.

The package database contained 1290 packages in total. The complete dependency
closure is deliberately not handwritten here: doing so would make the profile
fragile and would duplicate pacman's dependency solver. A release build can
capture a full `pacman -Q` snapshot separately for audit purposes.

## Protected packages

`packages.protected.tsv` is the release ABI boundary for the current boot
artifacts. It pins:

- the packaged Arch ARM kernel and kernel API headers;
- every `linux-firmware*` package installed in the snapshot;
- `wireless-regdb`, which affects the validated Wi-Fi behavior.

The exact version is passed to the initial installation transaction. The
pacman drop-in and pre-transaction hook are installed only after the initial
transaction so that a fresh rootfs can acquire the pinned packages. Every
subsequent build ends with `check-protected.sh`.

The running custom Image is not represented by `linux-aarch64 7.0.11-2` in the
package database. It is a separate build artifact and must be supplied by the
kernel/boot pipeline.

## Deliberate configuration conflict resolution

The Display and Modem component repositories both contain `zorn-msm.conf`.
The Display copy is the current policy: it provides the Display module softdep
and does not blacklist `msm`. The older Modem copy blacklists `msm`, so the
rootfs installer deliberately skips the Modem copy. This avoids a silent
last-writer-wins result during assembly.
