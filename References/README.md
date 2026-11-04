# Reference source

This directory contains the upstream MacFanPro source archive used while adapting a temperature-based fan curve for Stats.

- Upstream: https://github.com/macfanpro/macfanpro
- Archive: https://codeload.github.com/macfanpro/macfanpro/zip/refs/heads/main
- License: see `MacFanPro/LICENSE` (MIT)

The current integration invokes the bundled MacFanPro CLI from Modules/Sensors/macFanProBridge.swift. Its installed MacFanPro background service performs fan writes. Stats temporarily invokes the embedded installer for one-time authorization, then removes the temporary setup copy. Users normally open Stats only.

This supersedes the earlier local description that all writes used the original Stats SMC helper. Existing Stats SMC sources remain in the base application; the custom curve writes through the MacFanPro bridge.

The upstream archive is retained for attribution and comparison. Do not edit it as part of the Stats integration.
