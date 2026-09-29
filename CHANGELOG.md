# Changelog

## 1.0.0 (2026-09-30)

- GTK 4 and libadwaita front end: status, install, update, reinstall, launch, uninstall, live log
- pkexec helper with a fixed allowlist of actions and flags
- Install script: SHA256 verification against the repository index, alien conversion without Debian maintainer scripts, launcher repair, sandbox permissions, SELinux relabel, ownership marker
- Uninstall script: refuses to remove a non-alien package, never deletes paths owned by any installed rpm, optional user data purge
- Tested on Fedora 44 (GNOME, Wayland, x86_64) with Claude Desktop 1.24012.0
