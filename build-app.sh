#!/bin/sh
set -eu
cd "$(dirname "$0")"
APP="Touchline Live.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/backend/src" native/.module-cache
rm -rf "$APP/Contents/Resources/backend/src/__pycache__"
sh build.sh
sh build-icon.sh
cp assets/TouchlineLive.icns "$APP/Contents/Resources/"
swiftc -swift-version 5 -O -module-cache-path native/.module-cache native/Model.swift native/Shortlist.swift native/ShortlistUI.swift native/Query.swift native/Projection.swift native/Personality.swift native/RoleFocus.swift native/RoleFocusControl.swift native/FacepackIndex.swift native/FacepackCache.swift native/PlayerFaces.swift native/Views.swift native/AdvancedFilters.swift native/SettingsWindowController.swift native/PythonRuntime.swift native/App.swift native/Tests.swift native/main.swift -o "$APP/Contents/MacOS/TouchlineLive" -framework AppKit -framework ImageIO
cp src/touchline_live.py src/live_player.py src/live_transfers.py src/live_date.py src/live_currency.py src/live_nationality.py "$APP/Contents/Resources/backend/src/"
cp touchline-probe "$APP/Contents/Resources/backend/"
python3 - <<'PY'
import pathlib,plistlib
info={'CFBundleExecutable':'TouchlineLive','CFBundleIconFile':'TouchlineLive.icns','CFBundleIdentifier':'local.touchline.live','CFBundleName':'Touchline Live','CFBundleDisplayName':'Touchline Live','CFBundlePackageType':'APPL','CFBundleShortVersionString':'0.4','CFBundleVersion':'4','LSMinimumSystemVersion':'13.0','NSHighResolutionCapable':True,'NSPrincipalClass':'NSApplication'}
pathlib.Path('Touchline Live.app/Contents/Info.plist').write_bytes(plistlib.dumps(info))
PY
printf '%s\n' "Built $PWD/$APP"
