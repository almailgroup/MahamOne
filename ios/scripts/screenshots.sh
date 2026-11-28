#!/usr/bin/env bash
# Screenshots of the iPhone app, to review its screens without a device.
#
# Installs the app on a booted simulator and, for each case below, launches
# it in preview mode (App/Preview/PreviewMode.swift: a made-up owner and
# company, no account, no network) on a page and an overlay, light or dark,
# in English or Arabic; waits for it to settle; saves a screenshot; quits it.
#
# usage: screenshots.sh <MahamOne.app> [output folder]   (default: screenshots)
#        screenshots.sh --pick-device   the iPhone to use, as "<udid><tab><name, iOS x.y>":
#                                       the iPhone 17 Pro, else the newest iPhone on iOS 26+
#        screenshots.sh --list          the cases
#
# The app is a Debug build for the simulator (preview mode isn't in Release):
#   xcodebuild build -project MahamOne.xcodeproj -scheme MahamOne -configuration Debug \
#     -destination "id=$UDID" -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO
#   → DerivedData/Build/Products/Debug-iphonesimulator/MahamOne.app
#
# From the environment:
#   DEVICE   the simulator's UDID (default: the booted one)
#   SETTLE   seconds to wait after each launch (default 3)
#   ONLY     only the cases whose name matches this regular expression
#
# It starts the app afresh on that simulator: the app is reinstalled, the
# status bar set to 9:41, and the simulator's Keychain emptied before the
# sign-in case (which signs every app on it out). Use a simulator kept for this.
#
# The theme menu is opened with a tap on the drawer's "Theme" button, which
# needs AXe (brew install cameroncooke/axe/axe). Without it, that case shows
# the drawer and is marked "drawer only".
#
# Writes <case>.png for each case, and cases.tsv: case, result, what it shows.
# Exits 1 if a case failed.
set -uo pipefail

# name | label to tap after launching | what it shows | launch arguments
P="-MahamPreview 1"
CASES=(
  "home-light-en||Home, light, English|$P -MahamRoute / -MahamScheme light -MahamLanguage en"
  "home-dark-en||Home, dark, English|$P -MahamRoute / -MahamScheme dark -MahamLanguage en"
  "home-light-ar||Home, light, Arabic|$P -MahamRoute / -MahamScheme light -MahamLanguage ar"
  "home-dark-ar||Home, dark, Arabic|$P -MahamRoute / -MahamScheme dark -MahamLanguage ar"
  "drawer-light-en||The drawer|$P -MahamOverlay drawer -MahamScheme light -MahamLanguage en"
  "drawer-light-ar||The drawer, Arabic (right to left)|$P -MahamOverlay drawer -MahamScheme light -MahamLanguage ar"
  "create-light-en||The create menu, open from the +|$P -MahamOverlay create -MahamScheme light -MahamLanguage en"
  "switcher-light-en||The app switcher|$P -MahamOverlay switcher -MahamScheme light -MahamLanguage en"
  "search-light-en||Search|$P -MahamOverlay search -MahamScheme light -MahamLanguage en"
  "theme-light-en|Theme|The theme menu, from the drawer|$P -MahamOverlay theme -MahamScheme light -MahamLanguage en"
  "invoices-light-en||The invoices list|$P -MahamRoute /invoices -MahamScheme light -MahamLanguage en"
  "invoice-light-en||An invoice|$P -MahamRoute /invoices/p-inv-2 -MahamScheme light -MahamLanguage en"
  "bills-light-ar||The bills list, Arabic|$P -MahamRoute /bills -MahamScheme light -MahamLanguage ar"
  "products-light-en||Items|$P -MahamRoute /products -MahamScheme light -MahamLanguage en"
  "inventory-light-en||Inventory|$P -MahamRoute /inventory -MahamScheme light -MahamLanguage en"
  "clients-light-en||Clients|$P -MahamRoute /clients -MahamScheme light -MahamLanguage en"
  "client-light-en||A client|$P -MahamRoute /clients/p-cl-2 -MahamScheme light -MahamLanguage en"
  "payments-light-en||Payments received|$P -MahamRoute /payments -MahamScheme light -MahamLanguage en"
  "cheques-light-en||Cheques|$P -MahamRoute /cheques -MahamScheme light -MahamLanguage en"
  "expenses-light-en||Expenses|$P -MahamRoute /expenses -MahamScheme light -MahamLanguage en"
  "pipeline-light-en||CRM pipeline|$P -MahamRoute /crm -MahamScheme light -MahamLanguage en"
  "compliance-light-en||Compliance documents|$P -MahamRoute /compliance/documents -MahamScheme light -MahamLanguage en"
  "updates-light-en||Updates|$P -MahamRoute /notifications -MahamScheme light -MahamLanguage en"
  "settings-light-en||Settings|$P -MahamRoute /settings -MahamScheme light -MahamLanguage en"
  "books-light-en||Books dashboard|$P -MahamRoute /books -MahamScheme light -MahamLanguage en"
  "accounts-light-en||Chart of accounts|$P -MahamRoute /accounts -MahamScheme light -MahamLanguage en"
  "pnl-light-en||Profit and loss|$P -MahamRoute /reports/profit-and-loss -MahamScheme light -MahamLanguage en"
  "banking-light-en||Banking|$P -MahamRoute /banking -MahamScheme light -MahamLanguage en"
  "employees-light-en||Employees|$P -MahamRoute /employees -MahamScheme light -MahamLanguage en"
  "payroll-light-en||Payroll|$P -MahamRoute /payroll -MahamScheme light -MahamLanguage en"
  "people-light-ar||People overview, Arabic|$P -MahamRoute /people -MahamScheme light -MahamLanguage ar"
  "invoice-new-light-en||New invoice form|$P -MahamRoute /invoices/new -MahamScheme light -MahamLanguage en"
  "invoice-edit-light-ar||Editing an invoice, Arabic|$P -MahamRoute /invoices/p-inv-4/edit -MahamScheme light -MahamLanguage ar"
  "client-new-light-en||New client form|$P -MahamRoute /clients/new -MahamScheme light -MahamLanguage en"
  "item-new-light-en||New item form|$P -MahamRoute /products?new=1 -MahamScheme light -MahamLanguage en"
  "journal-new-light-en||New journal|$P -MahamRoute /journals/new -MahamScheme light -MahamLanguage en"
  "adjust-new-light-en||Stock adjustment form|$P -MahamRoute /inventory/adjustments/new -MahamScheme light -MahamLanguage en"
  "tasks-light-en||Maham Tasks|$P -MahamDepartment tasks -MahamScheme light -MahamLanguage en"
  "signin-light-en||Signing in (preview mode off)|-MahamScheme light -MahamLanguage en"
)

pick_device() {
  xcrun simctl list devices available -j | python3 -c '
import json, re, sys

best = None
for runtime, devices in json.load(sys.stdin)["devices"].items():
    match = re.search(r"\.iOS-(\d+)-(\d+)(?:-(\d+))?$", runtime)
    if not match:
        continue
    version = tuple(int(part or 0) for part in match.groups())
    if version[0] < 26:
        continue
    for device in devices:
        name = device.get("name", "")
        if not device.get("isAvailable", True) or not name.startswith("iPhone"):
            continue
        model = re.match(r"iPhone (\d+)\s*(.*)$", name)
        number = int(model.group(1)) if model else 0
        variant = {"Pro": 3, "Pro Max": 2, "": 1}.get(model.group(2) if model else name, 0)
        # The iPhone 17 Pro if there is one; else the newest iPhone, a Pro
        # first; on the newest iOS it has.
        key = (name == "iPhone 17 Pro", number, variant, version)
        if best is None or key > best[0]:
            best = (key, device["udid"], "%s, iOS %d.%d" % (name, version[0], version[1]))
if best is None:
    sys.exit("No iPhone simulator with iOS 26 or later (xcrun simctl list devices available).")
print("%s\t%s" % (best[1], best[2]))
'
}

case "${1:-}" in
  --pick-device)
    pick_device
    exit $?
    ;;
  --list)
    for entry in "${CASES[@]}"; do
      IFS='|' read -r name _ description _ <<< "$entry"
      printf '%-20s %s\n' "$name" "$description"
    done
    exit 0
    ;;
esac

APP=${1:-}
OUT=${2:-screenshots}
SETTLE=${SETTLE:-3}
ONLY=${ONLY:-}
if [ -z "$APP" ] || [ ! -d "$APP" ]; then
  echo "usage: $0 <MahamOne.app> [output folder]   (or --pick-device, --list)" >&2
  exit 2
fi

UDID=${DEVICE:-}
if [ -z "$UDID" ] || [ "$UDID" = booted ]; then
  UDID=$(xcrun simctl list devices booted -j | python3 -c '
import json, sys
booted = [d["udid"] for ds in json.load(sys.stdin)["devices"].values() for d in ds if d.get("state") == "Booted"]
print(booted[0] if booted else "")
')
fi
if [ -z "$UDID" ] || ! xcrun simctl getenv "$UDID" HOME > /dev/null 2>&1; then
  echo "No booted simulator. Boot one first: xcrun simctl boot \"\$($0 --pick-device | cut -f1)\"" >&2
  exit 2
fi

BUNDLE_ID=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Info.plist" 2> /dev/null)
BUNDLE_ID=${BUNDLE_ID:-com.almailgroup.mahamone}
AXE=$(command -v axe || true)

mkdir -p "$OUT"
SHEET="$OUT/cases.tsv"
printf 'case\tresult\tshows\n' > "$SHEET"
failed=0

echo "Simulator $UDID, app $BUNDLE_ID"
xcrun simctl status_bar "$UDID" override --time 9:41 --batteryLevel 100 --cellularBars 4 \
  || echo "::warning::The status bar couldn't be set."
xcrun simctl terminate "$UDID" "$BUNDLE_ID" > /dev/null 2>&1
xcrun simctl uninstall "$UDID" "$BUNDLE_ID" > /dev/null 2>&1
if ! xcrun simctl install "$UDID" "$APP"; then
  echo "::error::The app couldn't be installed on the simulator."
  exit 1
fi

# The first launch is slow (fonts, caches): once, unseen. The first case
# also waits longer: a launch just after the appearance changes can still be
# on the launch screen after $SETTLE seconds.
xcrun simctl ui "$UDID" appearance light > /dev/null 2>&1
xcrun simctl launch "$UDID" "$BUNDLE_ID" -MahamPreview 1 > /dev/null 2>&1 && sleep 6
xcrun simctl terminate "$UDID" "$BUNDLE_ID" > /dev/null 2>&1
first_settle=$((SETTLE + 4))

for entry in "${CASES[@]}"; do
  IFS='|' read -r name tap description args <<< "$entry"
  if [ -n "$ONLY" ] && ! [[ $name =~ $ONLY ]]; then continue; fi
  read -r -a argv <<< "$args"
  scheme=light
  [[ " $args " == *" -MahamScheme dark "* ]] && scheme=dark
  # Arabic for the system's own text too (Maham Tasks, alerts).
  [[ " $args " == *" -MahamLanguage ar "* ]] && argv+=(-AppleLanguages "(ar)")
  # Signing in starts signed out.
  [[ " $args " != *" -MahamPreview 1 "* ]] && xcrun simctl keychain "$UDID" reset > /dev/null 2>&1

  echo "• $name: $description"
  result=ok
  xcrun simctl ui "$UDID" appearance "$scheme" > /dev/null 2>&1
  xcrun simctl terminate "$UDID" "$BUNDLE_ID" > /dev/null 2>&1
  if ! xcrun simctl launch "$UDID" "$BUNDLE_ID" "${argv[@]}" > /dev/null; then
    result=failed
  else
    sleep "${first_settle:-$SETTLE}"
    first_settle=
    if [ -n "$tap" ]; then
      if [ -z "$AXE" ]; then
        result="drawer only"
        echo "  AXe isn't installed: no tap on \"$tap\"."
      elif "$AXE" tap --label "$tap" --wait-timeout 5 --udid "$UDID" > /dev/null; then
        sleep 1.5
      else
        result="drawer only"
        echo "  The tap on \"$tap\" failed."
      fi
    fi
    xcrun simctl io "$UDID" screenshot --type=png "$OUT/$name.png" > /dev/null 2>&1 || result=failed
  fi
  xcrun simctl terminate "$UDID" "$BUNDLE_ID" > /dev/null 2>&1
  if [ "$result" = failed ]; then
    failed=1
    echo "::error::Screenshot $name failed."
  fi
  printf '%s\t%s\t%s\n' "$name" "$result" "$description" >> "$SHEET"
done

xcrun simctl status_bar "$UDID" clear > /dev/null 2>&1
echo "Screenshots in $OUT"
exit $failed
