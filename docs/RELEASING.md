# Releasing

1. Bump `eightyVersion` in `Sources/EightyKit/Version.swift` in a pull request and merge it.
2. If the release needs a newer macOS, raise `MIN_MACOS` and `MIN_MACOS_NAME` in
   `scripts/release.env` in the same pull request. Older releases keep their own
   requirement in the cask history and on their GitHub release page.
3. On an up-to-date `main`, run `scripts/release.sh`. It:
   - tags `v<version>` and pushes the tag;
   - waits for the Release workflow, which tests, builds `Eighty-<version>.zip`,
     attests its build provenance, and publishes a GitHub release;
   - updates `Casks/eighty.rb` in
     [NathanColosimo/homebrew-tap](https://github.com/NathanColosimo/homebrew-tap)
     with the new version, checksum, and minimum macOS.

Users then get it with `brew upgrade --cask eighty`. Upgrades leave the running
background service alone, and the menu bar app offers to update it.

Check a downloaded zip came from this repo's workflow:
`gh attestation verify Eighty-<version>.zip --repo NathanColosimo/eighty`
