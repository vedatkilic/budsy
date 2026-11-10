# Homebrew Cask for Budsy (previously "Galaxy Buds for Mac").
#
# Setup (one time):
#   1. Create a public repo named "homebrew-tap" on your GitHub account.
#   2. Put this file at "Casks/budsy.rb" in that repo.
#   3. Copy "tap_migrations.json" (next to this file) to the tap repo root so
#      users of the old "galaxy-buds" cask are redirected to "budsy".
#   4. Copy this file into that repo whenever it changes.
#
# On every release: bump `version` and paste the new `sha256` (package.sh
# prints it after building the .dmg), then commit to the tap repo.
#
# Users then install with:
#   brew install --cask vedatkilic/tap/budsy

cask "budsy" do
  version "1.6.0"
  sha256 "9d9532a8993495fb66ea90afbe9602fdb908b0b0d0052a1239441bc894bf22a0"

  url "https://github.com/vedatkilic/budsy/releases/download/v#{version}/Budsy-#{version}.dmg"
  name "Budsy"
  desc "Menu-bar controller for Samsung Galaxy Buds"
  homepage "https://github.com/vedatkilic/budsy"

  app "Budsy.app"

  zap trash: [
    "~/Library/Preferences/com.nivorbit.budsy.plist",
    "~/Library/Preferences/com.nivorbit.galaxybuds.plist",
    "~/Library/Preferences/com.nivorbit.budsapp.plist",
  ]
end
