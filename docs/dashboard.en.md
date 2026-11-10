# User guide

[简体中文](dashboard.zh-CN.md) · **English** · [Documentation](README.en.md)

## Connection setup

On first launch, enter the controller address and secret. Use a LAN IP, `.local` / `.lan` domain, or LAN hostname, such as `192.168.1.1:9090`. The secret must match the controller's `secret`. Check connection tests API access.

For OpenClash or Nikki configuration management, quick settings, and restart, also enter the SSH password. The account is `root`; the default port is `22` and can be changed. Verify the host fingerprint shown on the first SSH connection before accepting it.

Continue detects proxy software and core and preselects the software in Preferences. Unidentified software uses Mihomo generic configuration. You can change the choice manually or save setup and connect later. Proxy software in Advanced options can be changed at any time, including while offline.

Detection runs on cold launch, return from the background, and after saving connection settings. An uncertain result retains a confirmed choice. When manual confirmation is needed, the selection sheet appears only on Home with a connected controller; connection failure does not open it.

## Home

The default order is Status, Traffic, Overview, Current configuration, Operations, and Quick settings. Status shows software, core version, and connection state. Traffic and Overview show usage, speeds, and connection counts.

Open Customize home at the bottom, long-press and drag to reorder, and use switches to show or hide cards. Changes save locally. Restore defaults resets order and visibility. Customize home remains available even when every card is hidden.

Layout preferences are shared across proxy software. Unsupported cards and options are hidden from Home and Customize home. Cards return to their saved positions when available again; cards never arranged before follow the arranged cards. Switching software does not reveal manually hidden cards.

## Adapter support

| Feature | OpenClash | Nikki | Mihomo generic configuration |
| --- | --- | --- | --- |
| Status, traffic, proxies, rules, connection operations | Supported | Supported | Subject to controller API support |
| Proxy mode | Supported | Supported | Supported |
| DNS mode, traffic handling, bypass, sniffing, DNS respect-rules | Supported | Supported with the limits below | No dedicated settings |
| Streaming auto-selection | When supported by the device | Unsupported | Unsupported |
| YAML management and service restart | Supported | Supported; subscription caches are read-only | Unsupported |

Software without a dedicated adapter uses Mihomo generic configuration. Software and core are displayed separately; a Mihomo core does not imply OpenClash management.

### Nikki

- TCP/UDP handling uses combinations of Redirect, TPROXY, and TUN as presets.
- Mainland bypass enables mainland IPv4 and IPv6 bypass together; Off disables both. If their current values differ, either choice sets them to the same value.
- Core-only mode hides quick settings. With mixin-file overrides, only area bypass remains available.
- Local profiles use `/etc/nikki/profiles`. Subscription caches under `/etc/nikki/subscriptions` are read-only; upload and activate a local profile to modify the content. The generated `/etc/nikki/run/config.yaml` is not an editing target.

The adapter does not cover every Nikki LuCI option. Available quick settings depend on the device's current configuration.

## YAML management

Current configuration shows the active configuration. Switching requires selecting a file and confirming; the app saves the reference, restarts the proxy service, and verifies the result. A restart may interrupt existing connections.

Edit configuration opens the editor. The filename at the top selects a document to edit without activating it. The top-right file menu provides upload, rename, export, and delete.

| Operation | Notes |
| --- | --- |
| Save | Writes the current file; on exit, changes to the active configuration can be followed by a service restart |
| Upload | Overwriting requires confirmation; uploading another file does not activate it |
| Export | Includes unsaved edits without writing to the router |
| Rename | Preserves edits; switch away before renaming an active subscription file |
| Delete | Requires confirmation; the active configuration cannot be deleted, and an unknown active state blocks deletion and renaming |
| Switch editing file | Save, discard, or cancel when there are unsaved edits |

Only `.yaml` / `.yml` files in supported directories are handled, up to `5 MiB` each. OpenClash supports `/etc/openclash/config`, `/openclash/config`, `/etc/clash/config`, and `/root/.config/clash/config`; uploads go to `/etc/openclash/config`. Files that failed to load cannot be saved.

### SFTP unavailable

Listing files uses SSH; reading and writing use SFTP. If files appear but cannot be opened, use the editor's SFTP diagnosis. When an OpenWrt component is confirmed missing, review and confirm the command to install `openssh-sftp-server` through `opkg` or `apk`. Root access is required.

After an installation timeout or disconnect, recheck before retrying. If the component is present but the handshake fails, check SSH's SFTP configuration. Network and authentication failures do not imply a missing component.

## Refresh and troubleshooting

Home refreshes while visible in the foreground. Runtime data updates about every second, subscriptions every 30 seconds, and configuration and quick settings every 15 seconds after successful reads. Manual refresh and reconnection trigger an immediate read. Changing tabs or backgrounding pauses the relevant polling.

| Symptom | Action |
| --- | --- |
| Cannot connect | Check the network, controller address, port, and `external-controller`; on iOS, also check Local Network permission |
| Authentication failed | Check the controller secret; for SSH, separately verify password, port, and host fingerprint |
| Web panel failed to load | Retry; a visible foreground offline page checks for recovery automatically, while authentication errors require corrected settings |
| Settings saved but restart failed | Retry through the restart control; confirmed saves do not need another write |
| Operation result unconfirmed | Check the router's actual state and refresh before retrying to avoid duplicate operations |

See the [Zashboard guide](bundled-zashboard.en.md) for layout, imports, and updates.
