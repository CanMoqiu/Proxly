# Dialog and button interaction rules

[简体中文](popup-interactions.zh-CN.md) · **English** · [Documentation](README.en.md)

Proxly's native interface and native web-page toolbars share these rules. Menus inside Zashboard remain upstream-managed.

| Purpose | Component | Dismissal and result |
| --- | --- | --- |
| Single selection, file management, import source | `AppOptionsSheet` | Selection returns a value; backdrop, swipe down, or back returns null |
| Action and security confirmation | `AppDialog` | Name the action on the primary button; execute only after explicit consent |
| Filename or SSH password input | Dedicated form in `AppDialog` | Show field errors inline and retain input on failure |
| Connection details | Dedicated content with `AppPopup.sheet` | Shared padding, safe area, drag indicator, and dismissal behavior |
| Brief result feedback | `AppFeedback` | Retain success and error lifetimes |
| Persistent failure, installation, restart | Owning page state and recovery controls | Dismissing the interface does not cancel a remote operation |

## Display and execution

- Open through `AppPopup.dialog` or `AppPopup.sheet`; buttons return results with `AppPopup.close`.
- Duplicate opens from the same source context return null, without sharing a successful result that could execute twice. SSH trust confirmation from a different source can still appear.
- Wait for the exit animation and backdrop removal before returning the result and opening another confirmation or a system picker.
- Another tap during exit must not close the underlying page.
- Lists mark the current selection; business callers do not reapply the same configuration or language.
- Put delete last in the action list and use the danger color. Preserve existing confirmations and validation for deletion, overwrite, installation, and SSH trust.
- Unsaved edits offer Keep editing, Discard changes, and Save and continue. A failed save stays on the current file.
- Presentation components do not access the router or add polling. Existing business state handles mutual exclusion, endpoint checks, timeouts, rollback, and retry.

## Layout and asynchronous operations

- Bottom sheets share titles, option spacing, rounded corners, and safe areas; long lists scroll.
- Centered dialog titles and content can scroll while actions remain separate. Three buttons stack vertically; two wrap when space is insufficient.
- Forms retain keyboard avoidance and validation. While saving an SSH password, disable submit and cancel and intercept system back.
- Disable update buttons during processing. Keep permission prompts and errors inside the update dialog; closing a download dialog sets the cancellation flag.
- Apply these rules in Chinese and English, with large text, short screens, light/dark themes, and Android/iOS.

## Regression focus

Check duplicate opens and submissions, sequential confirmations after selection, backdrop/gesture/system-back cancellation, SSH security confirmation, retained edits after save failure, and closing a dialog before asynchronous completion. For updates, also check browser-launch retry and scrolling long release notes.
