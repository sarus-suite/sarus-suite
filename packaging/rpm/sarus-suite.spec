Name:           sarus-suite
Version:        %{sarus_suite_version}
Release:        %{sarus_suite_release}%{?dist}
Summary:        Self-contained Sarus Suite container runtime
License:        BSD-3-Clause AND LicenseRef-Sarus-Suite-Bundled-Components
URL:            https://github.com/sarus-suite/sarus-suite
Source0:        sarus-suite-system-payload.tar.gz

%description
Sarus Suite packages static container runtime, image management, filesystem,
and OCI hook components for a system-wide installation. Per-user runtime and
image-store state is created on demand and is not owned by this package.

%prep

%build

%install
install -d %{buildroot}
tar -xzf %{SOURCE0} -C %{buildroot}

# Keep administrator-editable system configuration across upgrades. Generate
# this list from the payload so optional CDI and registries.d files stay KISS.
find %{buildroot}/etc -depth -type d -printf '%%%%dir %%p\n' \
  | sed 's|%{buildroot}||' > %{_builddir}/sarus-suite-etc.files
find %{buildroot}/etc -type f -printf '%%%%config(noreplace) %%p\n' \
  | sed 's|%{buildroot}||' >> %{_builddir}/sarus-suite-etc.files

%files -f %{_builddir}/sarus-suite-etc.files
%defattr(-,root,root,-)
/opt/sarus-suite

%changelog
* Wed Aug 19 2026 Sarus Suite maintainers <sarus-suite@cscs.ch> - %{version}-%{release}
- Add a scriptlet-free system package
