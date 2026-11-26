# Feed QA snapshots

These files are immutable upstream inputs, not replacement implementations.

- `homeproxy.Makefile`: https://raw.githubusercontent.com/immortalwrt/homeproxy/master/Makefile; Git blob `14166586bbd4346ef3d2b24688f42a2594e0ae47`.
- `adguardhome.Makefile`: https://raw.githubusercontent.com/ZqinKing/luci-app-adguardhome/master/Makefile; Git blob `62b2c5ad74716d795df4cecf620201e99bcce62f`.
- `tcping.Makefile`: https://api.github.com/repos/Openwrt-Passwall/openwrt-passwall-packages/contents/tcping/Makefile?ref=main; Git blob `e4b867596b027a57a4ad492fcebe8daad0c85e9b`.
- `cups.Makefile`: https://api.github.com/repos/kenzok8/small-package/contents/cups/Makefile; Git blob `24df4ae4f89a97fe4666d385b6eca3de223c80dd`.
- `luci.mk`: immortalwrt/luci, Git blob `e95d73e38de1494017ed233cbf2b6ab18e211003`.

Captured on 2026-11-26. Upstream license and copyright headers are retained.
The CUPS fixture removes only the two spaces on blank line 110 to satisfy the repository whitespace check; all semantic lines are unchanged.

Run `bash tests/feed_sync.sh` for the offline root/sparse synchronization cases.
Run `bash tests/feed_index.sh /path/to/immortalwrt` with an upstream tree containing include, scripts, config, target, package, tools, toolchain and the root Makefiles. This runs real feed scanning and installation without compiling firmware.
The HomeProxy, AdGuardHome, TCPing and CUPS Makefiles and LuCI rules are real inputs. Unchanged external catalogs use dependency doubles; their package implementations are outside this test.
`UPDATE_SCRIPT`, `CUSTOM_FEED_MODULE` and `FEED_SYNC_MODULE` support mutated copies without editing production files. `EVIDENCE_DIR` retains the generated index.
