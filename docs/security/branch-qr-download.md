# Branch QR preview and download

Both Super Admin entry pages (`index.html` and `gym/index.html`) use the same local branch QR generator. The existing QR action opens a preview and a Download high-resolution PNG button. The filename includes the gym name. The QR continues to encode the same branch portal URL.

The locally bundled, MIT-licensed QRCode.js 1.0.0 supplies the module matrix. A canvas renders whole square pixels, high error correction and a four-module white quiet zone. The PNG is at least 2048 × 2048 pixels; its exact dimensions vary with QR density to keep module edges sharp. The preview displays the same PNG at a smaller size. No external QR service receives the portal URL, and downloads need no extra network request. Failed generation disables download and shows a retry message.

Related admin header changes match Announcements to the other control heights. On phones the controls use icons and stay at the top right, with accessible labels retained.

No database, SQL, Edge Function, branch URL, role or permission changes. This is part of the existing UI follow-up review branch. All 239 local tests passed. Mocked Chromium verified control sizing and phone placement at 320, 375 and 1280 pixels. Both master entry pages generated and downloaded a 2074 × 2074 PNG for the test URL; an independent jsQR decoder verified the exact URL. No live tenant records were changed and no production deployment or merge was performed by the agent.
