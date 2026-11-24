# Releasing

1. Bump `eightyVersion` in `Sources/EightyKit/Version.swift` in a pull request and merge it.
2. If the release needs a newer macOS, raise `MIN_MACOS` and `MIN_MACOS_NAME` in
   `scripts/release.env` in the same pull request. Older releases keep their own
   requirement in the cask history and on their GitHub release page.
3. On an up-to-date `main`, run `scripts/release.sh`. It:
   - tags `v<version>` and pushes the tag;
   - waits for the Release workflow, which tests, builds, signs with the Developer ID
     certificate, notarizes and staples `Eighty.app`, zips it as
     `Eighty-<version>.zip`, attests its build provenance, and publishes a GitHub
     release;
   - updates `Casks/eighty.rb` in
     [NathanColosimo/homebrew-tap](https://github.com/NathanColosimo/homebrew-tap)
     with the new version, checksum, and minimum macOS.

Users then get it with `brew upgrade --cask eighty`. Within a minute the running
background service sees the newer app, checks its `eighty` is signed by the same
Developer ID team and newer, and swaps itself for it (`Sources/eighty/SelfUpdate.swift`).
If that can't happen (an unsigned build, or a service older than 0.1.4), the app
shows "Update Background Service" after three minutes.

Check a downloaded zip came from this repo's workflow:
`gh attestation verify Eighty-<version>.zip --repo NathanColosimo/eighty`

## Signing secrets

The Release workflow reads these from the `release` environment, which only `v*`
tags can deploy to:

| Secret | What |
|---|---|
| `MACOS_CERT_P12` | Base64 of a `.p12` holding the "Developer ID Application" certificate and its private key |
| `MACOS_CERT_PASSWORD` | That `.p12`'s password |
| `NOTARY_KEY_P8` | The App Store Connect API key file (`AuthKey_<id>.p8`) |
| `NOTARY_KEY_ID` | That key's ID |
| `NOTARY_ISSUER` | The issuer ID above the keys in App Store Connect → Users and Access → Integrations |

The Developer ID certificate expires on 2027-02-01. Before then, create a new one
(Xcode → Settings → Accounts → Manage Certificates → + → Developer ID Application),
export it as a `.p12`, and replace the first two secrets:

```sh
base64 -i developer-id.p12 | gh secret set MACOS_CERT_P12 --env release
gh secret set MACOS_CERT_PASSWORD --env release
```

To sign and notarize on a Mac instead: `EIGHTY_SIGN_IDENTITY="$DEVELOPER_ID"
scripts/build-app.sh`, then `scripts/notarize.sh` with `NOTARY_KEY`,
`NOTARY_KEY_ID`, and `NOTARY_ISSUER` set.
