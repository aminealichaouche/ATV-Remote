# Recorded successful audit command; source revision:
# yuri-rod/smart-tv-remote-swift 0b78b61a59c153f6b8b7b9010b1a6fbc61cd6670
# Run from the inspected source clone. All 12 tests are pure offline unit tests.
# No dependency installation, discovery, wake, or TV connection is performed.
# This records the command already executed; it was not rerun when preserving it.

cd /private/tmp/tv-remote-audit-smartcast || exit 1
SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/tv-remote-smartcast-module-cache \
CLANG_MODULE_CACHE_PATH=/private/tmp/tv-remote-smartcast-module-cache \
swift test --disable-sandbox \
  --cache-path /private/tmp/tv-remote-smartcast-cache \
  --scratch-path /private/tmp/tv-remote-smartcast-build \
  --config-path /private/tmp/tv-remote-smartcast-config \
  --security-path /private/tmp/tv-remote-smartcast-security
