# Proxly 26.6 pre-release security review

[简体中文](beta-security-review-26.6.md) · **English** · [Documentation](README.en.md)

> Historical record: the plans, version references, and validation scope below describe the review on 2026-10-02. They do not describe the current release process. The final 26.6 publication included Android and iOS packages; see the [release notes](releases/26.6.0.en.md).

Review date: 2026-10-02. Baseline: `beta@25d0744`, compared with `72286c3` (26.5). The review focused on SSH/UCI/YAML operations, controller authentication, WebView import bridging, resource updates, and sensitive-data handling in three beta commits. It does not represent a full penetration test of router firmware or third-party dependencies.

## Findings and fixes

### P1: Deserializing arbitrary Ruby objects as root

The former `openclash_quick_settings_service.dart:1182–1187,1343–1348` used `unsafe_load_file` to read runtime YAML. The fallback OpenClash `YAML.rb` also aliased `load` to `unsafe_load`. If an attacker could place Ruby type tags in the local YAML being read, opening quick settings or changing sniffing/DNS settings could construct objects. Impact depended on available Ruby classes and callbacks on the router. Checking for a top-level Hash after deserialization could not stop nested object construction. This does not establish that any arbitrary remote user could attack the device.

Fix: override the deserialization entry after loading the OpenClash compatibility module and use `safe_load`. Allow only the additional Date/Time values without execution callbacks and retain YAML aliases; arbitrary Ruby objects and Symbol remain disallowed. Preserve the compatibility module's text correction, decryption, and writing behavior. Regression tests use a class that only raises a marker exception to verify its object callback does not execute and that both system and compatibility loading paths retain aliases.

References: [Ruby Psych safe loading](https://ruby-doc.org/stdlib-3.1.1/libdoc/psych/rdoc/Psych.html), [OpenClash YAML compatibility module](https://github.com/vernesong/OpenClash/blob/master/luci-app-openclash/root/usr/share/openclash/YAML.rb).

### P2: Unrestricted permissions on temporary configuration backups

The former `openclash_quick_settings_service.dart:922,1438–1447` wrote UCI and runtime configuration to `/tmp/proxly_<timestamp>.*` without setting a umask or creating a private directory. With a typical umask of 022, other local users could read backups containing controller secrets and subscription data; interrupted connections could leave backups behind. Timestamp names also failed to exclude precreated files or symbolic links. This already affected the 26.5 transaction path, which the beta's new run-mode persistence path reused.

Fix: random transaction directories, atomic `mkdir`, directory mode 0700, and umask 077. Reject existing directories instead of following precreated symlinks. Recovery and cleanup use the same directory. Ruby temporary writes use exclusive creation with initial mode 0600 and only clean up temporary files successfully created by that operation. Linux regressions verify directory/file permissions and symlink rejection.

### P2: Diagnostic redaction missed JSON and credentials containing spaces

The former regex at `openclash_quick_settings_service.dart:1048–1061` did not match `{"password":"..."}` and replaced only the first segment of `secret: "value with spaces"`. Remaining values could enter error details and Debug logs. The issue was reproduced locally using synthetic credentials, without reading actual device data.

Fix: centralized filtering for quoted fields, complete values containing spaces, and compound names such as `dashboard_password`, with JSON/YAML/UCI and escaped-quote tests. Diagnostics still limit length and filter URLs, Bearer values, and addresses. This does not guarantee recognition of every secret in arbitrary text.

## Other checks

- Beta quick settings used the app's configured controller address and Token; run-mode changes used coordinated restarts, and enum mappings constrained writes.
- Initial and changed SSH host fingerprints still required confirmation; passwords were not inserted into remote shell commands.
- File path restrictions, panel ZIP size/path/symlink/digest checks, and imported-setting sensitive-field filtering remained present.
- Official Zashboard v3.25.0 `dist.zip` SHA-256: `98bb75a3df37a9ece122ec43d65515ccad93254e020eaf2b3ae2a3859bcf4d42`. Comparing 321 bundled files found only Git line-ending differences and no extra or missing files. This established matching provenance, not the absence of vulnerabilities throughout the third-party panel.
- The plan at the time was to release only 26.6 source and documentation, without APK uploads, and retain only build-validation logs.

## Validation scope

Local static analysis and Flutter regressions used Flutter 3.47.5. Ruby behavior and POSIX permission tests ran in Linux CI and were explicitly skipped on Windows. An Android Debug build checked shared code and dependencies. Router-specific differences and iOS Web/SSH issues still required later device validation; this Android source review did not claim to resolve iOS failures.
