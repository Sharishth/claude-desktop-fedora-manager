# Contributing

Bug reports and pull requests are welcome, especially test reports from Fedora versions, desktops and architectures not yet listed in the README.

## Before opening a pull request

- Run `shellcheck scripts/*.sh src/helper build.sh` and `python3 -m pyflakes src/claude-deb2rpm-manager`.
- Test on a real Fedora install: install, update, reinstall, uninstall, and uninstall with data removal.
- Keep the helper allowlist strict. Any new privileged action needs a matching entry in `src/helper` and a reason in the pull request.

## Ground rules

- Never commit or attach Claude Desktop binaries, `.deb` files or converted rpms. Claude Desktop is proprietary; this project only automates downloading it from Anthropic.
- Keep the project clearly unofficial in names, text and artwork. Do not use Anthropic logos.
