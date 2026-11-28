# User guide

[简体中文](dashboard.zh-CN.md) · **English** · [Documentation](README.en.md)

## Connection setup

On first launch, enter the controller address and secret. Use a LAN IP, `.local` or `.lan` domain, or LAN hostname. The default controller port is `9090`. A blank device name uses the controller address and port. Enter the same `secret` as on the controller. Select **Test connection** to check API access.

For OpenClash or Nikki configuration management, quick settings, and restart, also enter the SSH password. The account is `root`; the default port is `22` and can be changed. Verify the host fingerprint shown on the first SSH connection before accepting it.

Select **Continue** to detect the proxy software and core. You can choose **Proxy backend** manually in the connection form or save the device and connect later. When detection is inconclusive, the app keeps any confirmed backend. New devices can use Mihomo generic configuration.

A backend you select and save in Settings takes priority. Automatic detection resumes on cold launch or after at least five minutes in the background. Brief interruptions preserve the manual selection. A confirmation prompt appears only on Home when the controller is reachable.

### Managing multiple devices

Open **Settings → Controller settings → Switch** to see the device list. Select a device to switch immediately, or use **Add device** to save a separate address, credentials, and backend. To edit an existing device, switch to it first, then edit and save the controller card. Swipe left on an inactive device to delete it after confirmation. Wait for any active remote operation to finish before switching.

An orange outline marks an unsaved field. Leaving the Settings tab restores the saved form values.

## Home

The active device appears to the left of the Home title. The default card order is Runtime status, Traffic information, Overview, Current configuration, Runtime actions, and Quick settings.

Open **Customize dashboard** at the bottom. Touch and hold a card to reorder it, or tap the red minus in its upper-right corner to hide it. Hidden cards appear in their default order under **Available to add**. Tap the plus button on the left to put a card back on the dashboard. Changes save locally. **Reset layout** restores the default order and visibility.

Devices and proxy backends share the Home layout. Unsupported cards and options disappear from Home and Customize dashboard. Available cards return to their saved positions. Cards that have never been arranged follow the arranged cards. Manually hidden cards stay hidden.

## App updates

- In **Settings → About Proxly**, check for updates or turn off automatic update checks. Automatic checks run at startup at most once every 24 hours. **Skip this version** applies to both automatic and manual checks.
- On Android, the update dialog downloads the APK and opens the installer. On iOS, the update dialog downloads the IPA to Files. For its location and installation steps, see the [iOS installation guide](ios-selfsign.en.md#updates-and-renewal).

## Optional settings

Advanced options hides **Connections tab content** and **Show floating theme button** by default. Tap the app icon on About five times to show these options. Tap it five more times to hide them. Saved preferences remain active.

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
