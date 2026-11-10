# Dialog interaction rules

[简体中文](popup-interactions.zh-CN.md) · **English** · [Documentation](README.en.md)

Applies to native pages and native web-page toolbars. Zashboard's internal menus remain upstream-managed.

## Choosing components

| Purpose | Component | Behavior |
| --- | --- | --- |
| Single selection, file actions, import source | `AppOptionsSheet` | Mark the current item; selection returns a value, while backdrop, swipe down, or back cancels |
| Action or security confirmation | `AppDialog` | Name the action on the primary button; execute only after explicit confirmation |
| Filename or SSH password | Form within `AppDialog` | Show errors inline and retain input on failure |
| Connection details | `AppPopup.sheet` | Shared safe areas, padding, and drag indicator |
| Brief feedback | `AppFeedback` | Shared duration and placement |
| Persistent failure or restart | Page state and recovery controls | Dismissal does not undo a remote operation |

## Results and asynchronous operations

Open through `AppPopup.dialog` / `AppPopup.sheet` and return results through `AppPopup.close`. Duplicate opens from the same source return null; SSH security confirmation from a different source can still appear.

Return results only after the exit animation and backdrop have finished, before opening the next confirmation or system picker. Repeated taps during exit must not close the underlying page. Callers own request exclusion, endpoint checks, timeouts, and retries; presentation components do not request router operations.

Place deletion last and use the danger color. Require confirmation for deletion, overwrite, installation, and SSH trust. Unsaved edits offer Keep editing, Discard, and Save and continue; failed saves stay on the current file.

Disable buttons and back navigation as required during submission to prevent duplicate requests. SSH password saves disable submit, cancel, and system back; dismissing a download cancels it. After asynchronous completion, check that the page is still valid before navigation.

## Layout and checks

Bottom sheets share titles, spacing, and safe areas; long content scrolls. Centered dialogs separate content from actions, stack three buttons, and wrap two when width is insufficient. Forms retain keyboard avoidance and inline validation.

Check both languages, large text, short screens, light/dark themes, and back navigation on both platforms. Cover repeated submissions, sequential confirmations, cancellation, retained input on failure, and asynchronous callbacks after dismissal.
