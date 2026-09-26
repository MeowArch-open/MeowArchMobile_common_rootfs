# zorn boot device tree

`zorn.dts` here is the base device tree source for the Xiaomi `zorn` / SM8650
target. It is the tree GRUB loads at boot (as `zorn.dtb`), not a
subsystem/driver overlay.

The Builder compiles it during ESP assembly:
`builder/scripts/build-esp.sh` runs `dtc` on
`common_rootfs/profiles/zorn/boot/zorn.dts` to produce `dtb/zorn.dtb` on the
ESP, alongside the display/audio variants that are compiled from the Audio
repo's `dts/` snapshots. GRUB's `grub.cfg` `devicetree` line selects which
`.dtb` a given menu entry hands to the kernel.

This source lives in the rootfs profile (rather than a standalone repository)
so the base boot DT travels with the profile that pins the rest of the zorn
userspace. It is deliberately kept separate from the per-subsystem DT material
tracked by the Display/Audio/Touch source repositories.

Regenerate/validate:

```sh
dtc -I dts -O dtb -o /tmp/zorn.dtb profiles/zorn/boot/zorn.dts
```

model string: `Qualcomm Technologies, Inc. Zorn based on SM8650`.
