# Phone QR scanner

Admin/staff scanning now opens a full viewport camera screen on phones, including landscape. Desktop keeps a centered scanner. Browser chrome may remain visible when running in a browser; the installed app uses its available standalone viewport.

The scanner includes a QR positioning guide, close controls, conditional flashlight/camera switching, and the existing image-upload fallback. Camera permission failures offer a retry. Both accepted and denied results pause scanning until Scan Next Member is selected. Closing or backgrounding releases the camera; a permission request resolving after close also releases its stream. Returning from the background requires an explicit next scan.

The existing signed-pass redemption, subscription access checks, permissions, duplicate/expiry rules and financial behavior are unchanged. No SQL or backend deployment is required.

Validation: `node tests/browser/scanner-screen.cjs` runs the real scanner markup/methods, presentation module and subscription wrapper with local camera fixtures at 320×740, 390×844, 844×390 and 1280×850. It covers layout, access denial, flashlight/switching, accepted/denied pause, cleanup, late permission and permission retry. The normal unit suite covers existing signed-pass redemption. Real phone cameras and native torch support require a device check after deployment.

Device acceptance:

1. Open Scan as authorized admin/staff; confirm the camera fills the screen with reachable close controls in portrait and landscape.
2. Scan a valid live member QR; confirm one entry, a visible result and paused camera. Tap Scan Next Member.
3. Rescan the used QR and scan an invalid/expired QR; confirm denial without repeated attempts or extra attendance.
4. Close while the camera is active, or while permission is pending; confirm the camera indicator turns off. Background and return; explicitly resume.
5. Deny camera permission, then allow it and retry. Test flashlight and switching when offered.
6. Confirm desktop scanning, upload fallback and subscription restrictions still work.
