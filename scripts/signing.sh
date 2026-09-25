# Sourced by the build scripts. Decides how xcodebuild signs:
#  - a team from $DEVELOPMENT_TEAM or Config/Signing.xcconfig → automatic signing with the iCloud entitlements
#    (THUBAN_SIGNED=YES) and -allowProvisioningUpdates (Xcode creates / updates the App IDs, the iCloud container
#    and the profiles with the Apple ID added in Xcode ▸ Settings ▸ Accounts);
#  - no team → exactly the old builds (ad-hoc Mac, unsigned simulator) without the iCloud entitlements.
# Sets TEAM (may be empty) and SIGN_ARGS (an array for xcodebuild).
TEAM="${DEVELOPMENT_TEAM:-}"
if [[ -z "$TEAM" && -f Config/Signing.xcconfig ]]; then
  TEAM="$(sed -nE 's/^[[:space:]]*DEVELOPMENT_TEAM[[:space:]]*=[[:space:]]*([A-Za-z0-9]+).*/\1/p' Config/Signing.xcconfig | tail -1)"
fi
if [[ -n "$TEAM" ]]; then
  SIGN_ARGS=(DEVELOPMENT_TEAM="$TEAM" THUBAN_SIGNED=YES -allowProvisioningUpdates -allowProvisioningDeviceRegistration)
else
  SIGN_ARGS=(DEVELOPMENT_TEAM= THUBAN_SIGNED=NO)
fi
