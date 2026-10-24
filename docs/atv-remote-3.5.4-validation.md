# ATV Remote 3.5.4 (50) validation

**Transfer setup toolbar.** Share and import no longer need a scroll to the bottom. The top-right button is a blue **Share** or **Import** that runs the next step: Share creates the transfer and then opens the share sheet; Import chooses a file, unlocks a protected file with its phrase, then imports the reviewed selection. It is disabled while the bottom button would be, and hidden after a successful import. **Exit** at the top left replaces Done and the back button and closes Transfer setup. The buttons at the bottom of the form are unchanged.

## Verification

UI tests create a transfer and import a reviewed selection through the top-right button, and check that Transfer setup shows Exit in place of a back button. The sharing and import UI flows pass with Exit.
