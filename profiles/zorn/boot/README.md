# zorn boot device trees

This directory holds the two device trees GRUB hands to the kernel — the trees
the boot menu actually selects, not subsystem/driver overlays:

- `zorn.dts` → `zorn.dtb`: the pure base tree. GRUB's **recovery** entry loads
  it with `modprobe.blacklist=msm`, giving a simplefb fallback that comes up
  even when the display/driver stack is wedged.
- `zorn-cam.dts` → `zorn-cam.dtb`: the full daily-driver tree GRUB's **normal**
  entry (the default) loads — real DPU + o11 panel, OV08D10 ultra-wide camera,
  iris HW video codec, and the i2c-master-hub sensor bus (`geniqup@9c0000` +
  `i2c@980000` enabled; the remaining hub sub-buses stay disabled). It was
  captured 1:1 from the running device ESP and recompiles identically.

The Builder compiles both during ESP assembly: `builder/scripts/build-esp.sh`
runs `dtc` on each and writes `dtb/zorn.dtb` and `dtb/zorn-cam.dtb` to the ESP.
The device's GRUB menu is exactly these two entries — recovery + normal, no
test entry — and `builder/config/zorn/grub.cfg.in` mirrors it (`default=1`, the
normal entry). The per-subsystem audio/tdm/display bring-up trees are
experiments and are deliberately **not** built into the shipping image.

Both sources live in the rootfs profile (rather than standalone repositories)
so the boot DTs travel with the profile that pins the rest of the zorn
userspace. They are deliberately kept separate from the per-subsystem DT
material tracked by the Display/Audio/Touch source repositories.

Regenerate/validate:

```sh
dtc -I dts -O dtb -o /tmp/zorn.dtb profiles/zorn/boot/zorn.dts
```

model string: `Qualcomm Technologies, Inc. Zorn based on SM8650`.
