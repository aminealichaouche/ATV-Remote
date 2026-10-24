# ATV Remote 3.5.5 (51) validation

**Transfer setup Back.** The top-left button of Transfer setup is now **Back** instead of Exit. It returns to the screen that opened it (Settings or Your TVs) instead of closing Settings; when Transfer setup is shown on its own, as for an incoming file, Back closes it. The blue top-right **Share**/**Import** button from 3.5.4 is unchanged.

## Verification

The Settings navigation UI test checks that Back from Transfer setup returns to Your TVs and to Settings. Sharing and import UI flows go Back to Settings, then close it.
