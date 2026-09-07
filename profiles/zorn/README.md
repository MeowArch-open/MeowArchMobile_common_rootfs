# zorn profile

This profile describes the Arch rootfs currently installed on the Redmi K80
(`zorn`, SM8650).

The package database was queried from the device's Arch partition on
2026-09-07 with Android pacman:

```text
pacman -Q   : 1290 packages
pacman -Qe  :   57 explicit packages
foreign     :    6 packages
orphans     :    2 packages (go, jq)
```

The explicit list is a seed list, not a frozen copy of all dependencies.
Official dependencies are resolved by pacman. AUR recipes are separately
locked in `aur.lock.tsv`, because they are not supplied by the Arch Linux ARM
repositories.

`packages.protected.tsv` is intentionally smaller than the full package set:
it marks the kernel, kernel ABI headers, firmware packages and regulatory data
that must stay at the versions validated with the current boot artifacts.
