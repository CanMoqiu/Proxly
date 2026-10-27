# Home dashboard

[简体中文](dashboard.zh-CN.md) · **English** · [Documentation](README.en.md)

The default order is Status, Traffic, Overview, Current configuration, Operations, and Quick settings. Overview retains connection counts, cumulative download/upload, speed charts, and time markers.

Scroll to the bottom and select **Customize home** to edit the layout. Long-press a card and drag it to reorder; use its switch to show or hide it. Starting a drag provides haptic, scaling, elevation, and highlight feedback. Cards remain fully expanded while editing, with no height cap or internal scrolling. Only the dragged card shrinks and follows the finger. The page scrolls automatically only while the moving finger is within a narrow top or bottom edge area; a stationary long press does not start scrolling, and leaving the edge stops it. During dragging, a small gap and drop indicator replace a full-card placeholder. Releasing saves the destination order and smoothly expands the card and repositions its neighbors. Canceling leaves the order unchanged. Editing affects layout only; card contents cannot trigger business operations. The floating theme ball also provides haptic feedback for theme changes and long-press dragging.

Changes save locally. Select **Done** or navigate away to leave editing; **Restore defaults** resets order and visibility. The bottom button becomes **Done** while editing, and the page stays at the bottom. Instructions, restore, and done controls sit below the cards; restoring defaults also preserves the bottom position. Even when every card is hidden, the editing entry remains available.

Home action buttons and quick options use a minimum height of 48 and corner radius of 12. Action spacing is 8. Quick options share a continuous background, with a rounded theme-colored highlight around the selection. Narrow screens or large text can stack options vertically; text and button height adapt to their content.

Cards use padding and corner radii of 16, spacing of 12, and a common left title baseline. Current configuration places refresh separately from file information, leaving room for full paths to wrap. Overview retains its statistics, charts, and time markers. All six titles contain only the name, without subtitles; necessary state, path, and setting explanations remain in the content. Subscription names and traffic align by text baseline; state values and switches align right. Quick-setting groups share consistent text spacing. Editing instructions and the restore button use separate lines to avoid crowding on narrow screens with large text.

Fake-IP / Redir-Host options appear directly under Quick settings, without the former base-mode label. Switching preserves the current compatibility/enhanced, TUN, or mixed variant and uses UCI persistence, a coordinated OpenClash restart, health checks, and mode readback. Selection is disabled before loading, for unknown modes, after read failures, or while busy. A failed save does not start a restart; after a successful save but failed restart, the restart button can resume recovery.

## YAML configuration

- Current configuration shows the active OpenClash filename and path; subscriptions and states without a local file use the existing detection logic.
- Switch configuration opens a bottom sheet. Selecting a file still requires confirmation, then saves the active reference, restarts, and verifies activation.
- Edit configuration opens the editor directly. The filename at the top selects another YAML document for editing; it does not change the running configuration.
- The top-right file menu provides upload, rename, export, and delete. Uploading over an existing file requires confirmation. Export includes the current editing buffer and does not automatically write to the router.
- Delete requires confirmation and discards unsaved content. Failure keeps the buffer; success lets you select another YAML. The active file, including subscription-generated configuration, cannot be deleted until you switch away. Unknown active state also blocks deletion.
- Before switching away from unsaved text, save, discard, or cancel. Renaming preserves the buffer; subsequent saves use the new path.
- Rename checks remote canonical paths and does not confuse same-named files in different directories. Switch away before renaming an active subscription file. Unknown active state blocks renaming.
- On exit, the editor rereads the active configuration and offers an OpenClash restart only if a save or upload during this session overwrote that file. Editing or uploading another YAML does not prompt a restart.
- If the active configuration cannot be confirmed, the app suggests a manual restart if needed and still allows leaving the editor.

File operations retain SSH/SFTP, host-fingerprint confirmation, path and size restrictions, and rename rollback. YAML reads bound both the remote request length and actual accumulated bytes; growth during a read cannot bypass the 5 MiB limit.

File operations check the SFTP handshake. After failure, the current SSH connection checks OpenWrt component status. When the component is confirmed missing, the editor offers installation and recheck. Before installation, the router address and command are shown and explicit user confirmation is required. Automatic installation requires root, detects opkg or apk, refreshes its package index, and installs `openssh-sftp-server`.

SFTP is checked again after installation. A previously unread file is reloaded; unsaved text is retained so the user can save again. A timeout or disconnect leaves installation status uncertain: recheck before starting another install. If the component is present but the handshake fails, check the SSH SFTP configuration. Ordinary network or authentication errors are not treated as a missing component. Detection happens only during file operations and adds no background polling. A file that failed to load cannot be saved.

## Refresh and recovery

Home reuses the shared realtime source and restart coordinator. Runtime data refreshes every second; current configuration and quick settings refresh every five seconds. Hidden cards do not request their associated periodic reads. Home polling pauses when changing tabs, opening the editor, or backgrounding the app, then refreshes on return. In-flight reads are combined; results predating settings changes cannot replace current state.

A single top-right loading indicator combines initial reads and active operations. Cards retain status text and disabled buttons; Overview layout is unchanged. Periodic refreshes with existing data do not show the indicator.

On an offline cold start, automatic configuration and quick-setting failures stay within their cards instead of repeatedly showing error notices. Returning online immediately rereads YAML and quick settings. Old pre-disconnect results cannot overwrite recovered state or create duplicate reads.

Proxy, web Connections, and the standalone console distinguish unreachable networks, authentication failures, and panel initialization failures. Offline pages retain a message and retry button. Only the visible foreground offline page probes the controller every ten seconds and reloads on recovery; authentication and script failures do not automatically retry. iOS local-network permission is a troubleshooting suggestion, not an automatic diagnosis of every outage.

Home and web pages share connection observations from existing API and bridge requests, without additional permanent polling. During restarts they show a consistent restart message and ignore old results. After recovery, visible panels rebuild their services; hidden panels recover when shown. Concurrent recovery probes share a request. HTTP and WebSocket bridges both refuse upstream redirects.

After an SSH timeout or disconnect, quick settings attempt transaction recovery. If the remote operation is still running or recovery cannot be verified, the result remains unconfirmed; old values are not presented as current. The native connection list removes a connection only after the controller confirms closure; failure retains the record and offers retry.
