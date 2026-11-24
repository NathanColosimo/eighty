#!/bin/sh
# Publishes the version in Sources/EightyKit/Version.swift:
#   1. tags it and pushes the tag, which makes the Release workflow build
#      Eighty-<version>.zip and attach it to a GitHub release;
#   2. points the Homebrew cask in NathanColosimo/homebrew-tap at that zip.
# Run from an up-to-date, clean main after the version bump has merged.
set -eu
cd "$(dirname "$0")/.."
. scripts/release.env
version=$(sed -n 's/.*eightyVersion = "\(.*\)"/\1/p' Sources/EightyKit/Version.swift)
tag="v$version"
repo=NathanColosimo/eighty
tap=NathanColosimo/homebrew-tap

[ -z "$(git status --porcelain)" ] || { echo "Working tree is not clean." >&2; exit 1; }
[ "$(git rev-parse --abbrev-ref HEAD)" = main ] || { echo "Release from main." >&2; exit 1; }

if ! git rev-parse "$tag" >/dev/null 2>&1; then
  git tag -a "$tag" -m "Eighty $version"
  git push origin "$tag"
fi

echo "Waiting for the Release workflow to publish $tag..."
until gh release view "$tag" --repo "$repo" --json assets --jq '.assets[].name' 2>/dev/null | grep -q "Eighty-$version.zip"; do
  sleep 15
done

work=$(mktemp -d)
gh release download "$tag" --repo "$repo" --pattern "Eighty-$version.zip" --dir "$work"
sha=$(shasum -a 256 "$work/Eighty-$version.zip" | cut -d' ' -f1)

gh repo clone "$tap" "$work/tap" -- --quiet
mkdir -p "$work/tap/Casks"
cat > "$work/tap/Casks/eighty.rb" <<CASK
cask "eighty" do
  version "$version"
  sha256 "$sha"

  url "https://github.com/$repo/releases/download/v#{version}/Eighty-#{version}.zip"
  name "Eighty"
  desc "Battery charge limit and heat protection for Apple silicon Macs"
  homepage "https://github.com/$repo"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on arch: :arm64
  depends_on macos: ">= :$MIN_MACOS_NAME"

  app "Eighty.app"
  binary "#{appdir}/Eighty.app/Contents/Helpers/eighty"

  # The app is ad-hoc signed, not notarized, so clear the download quarantine.
  postflight do
    system_command "/usr/bin/xattr", args: ["-dr", "com.apple.quarantine", "#{appdir}/Eighty.app"]
  end

  # Stops the background service and leaves macOS's plain charge limit in place.
  uninstall quit:   "dev.eighty.menubar",
            script: {
              executable: "#{appdir}/Eighty.app/Contents/Helpers/eighty",
              args:       ["uninstall"],
              sudo:       true,
            }

  caveats <<~EOS
    Open Eighty from Applications, then click its menu bar icon and choose
    "Install Background Service". Or, from a terminal: sudo eighty install
  EOS
end
CASK
git -C "$work/tap" add Casks/eighty.rb
if git -C "$work/tap" diff --cached --quiet; then
  echo "The tap already has $tag."
  exit 0
fi
git -C "$work/tap" commit --quiet -m "eighty $version"
git -C "$work/tap" push --quiet
echo "Released $tag; brew install --cask nathancolosimo/tap/eighty now installs it."
