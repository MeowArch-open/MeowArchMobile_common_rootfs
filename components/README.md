# Component input contract

This directory is intentionally empty in the repository. The build scripts
consume sibling checkouts supplied with `--components`.

Expected layout:

```text
components-root/common
components-root/display
components-root/audio
components-root/touch
components-root/modem
components-root/wifi
```

The component repositories own their source, patches, DTS, services and
firmware. `common_rootfs` only installs runtime files and accepts compiled
outputs through a rootfs-shaped `--artifacts` directory.
