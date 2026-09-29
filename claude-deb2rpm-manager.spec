%global app_id    local.ClaudeDeb2Rpm.Manager
%global helperdir /usr/libexec/%{name}

Name:           claude-deb2rpm-manager
Version:        1.0.0
Release:        1%{?dist}
Summary:        Unofficial GUI to install and update Claude Desktop on Fedora

License:        MIT
URL:            https://github.com/YOUR_GITHUB_USERNAME/claude-desktop-fedora-manager
Source0:        %{name}-%{version}.tar.gz
BuildArch:      noarch

BuildRequires:  desktop-file-utils

Requires:       python3
Requires:       python3-gobject
Requires:       gtk4
Requires:       libadwaita >= 1.5
Requires:       polkit
Requires:       alien
Requires:       curl
Requires:       rpm
Requires:       coreutils
Requires:       gawk
Requires:       sed
Requires:       grep
Requires:       findutils
Requires:       hicolor-icon-theme

%description
Unofficial GTK front end that installs, updates and removes Claude Desktop on
Fedora by downloading Anthropic's official Debian package, verifying its
checksum, converting it with alien and installing the result. Privileged steps
run through pkexec. Not affiliated with or endorsed by Anthropic. Claude
Desktop itself is not included; it is downloaded from Anthropic at install time.

Removing this package does not remove Claude Desktop. Uninstall Claude Desktop
from the tool first when switching to an official Fedora package.

%prep
%setup -q

%build
# Nothing to build.

%install
install -Dm0755 src/claude-deb2rpm-manager %{buildroot}%{_bindir}/claude-deb2rpm-manager
install -Dm0755 src/helper %{buildroot}%{helperdir}/helper
install -Dm0755 scripts/install-claude-deb-to-rpm.sh   %{buildroot}%{helperdir}/install.sh
install -Dm0755 scripts/uninstall-claude-deb-to-rpm.sh %{buildroot}%{helperdir}/uninstall.sh
install -Dm0644 data/%{app_id}.desktop %{buildroot}%{_datadir}/applications/%{app_id}.desktop
install -Dm0644 data/%{app_id}.policy  %{buildroot}%{_datadir}/polkit-1/actions/%{app_id}.policy
install -Dm0644 data/%{app_id}.svg     %{buildroot}%{_datadir}/icons/hicolor/scalable/apps/%{app_id}.svg

%check
desktop-file-validate %{buildroot}%{_datadir}/applications/%{app_id}.desktop

%files
%license LICENSE
%doc README.md
%{_bindir}/claude-deb2rpm-manager
%dir %{helperdir}
%{helperdir}/helper
%{helperdir}/install.sh
%{helperdir}/uninstall.sh
%{_datadir}/applications/%{app_id}.desktop
%{_datadir}/polkit-1/actions/%{app_id}.policy
%{_datadir}/icons/hicolor/scalable/apps/%{app_id}.svg

%changelog
* Wed Sep 30 2026 Sharishth <sharishth@users.noreply.github.com> - 1.0.0-1
- Initial release: GTK front end, pkexec helper, install and uninstall pipeline
