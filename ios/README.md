# Maham One for iPhone and iPad

The native app, in Swift and SwiftUI, for iOS 26 and later, with the Liquid
Glass design. One app, two departments, one account:

- **Maham One**: the company's overview (what's owed, what's late, invoiced
  by month), invoices, clients, people and expiring documents. The app only
  shows these for now. Changes are made on mahamone.com, and every screen has
  an "Open in Maham One" button.
- **Maham Tasks**: your work from tasks.mahamone.com. That covers Today,
  your tasks, project boards with drag and drop, task details with steps
  and comments, and making and changing tasks. Chat, messages, reports and
  the team pages stay on the website for now.

Both read and write the same database as the websites. Each request runs
as the signed-in person, so what someone sees is what the database lets them
see. Staff and viewers never see payroll or employee documents.

## What it uses from iOS

| | |
|---|---|
| Liquid Glass | Glass tab bar (it shrinks as you scroll), glass cards, buttons and toolbars; an iPad sidebar |
| Face ID / Touch ID | Locks the app when you come back after five minutes away |
| Widgets | Today (small, medium, large) with a tick to finish a task from the Home Screen; Lock Screen widgets |
| Controls | "New task" and "Today" in Control Center, on the Lock Screen or on the Action button |
| Siri and Shortcuts | "Add a task in Maham One", "What's due today in Maham One", "Complete a task", "Open today" |
| Live Activity | "Start focus" on a task puts a timer on the Lock Screen and in the Dynamic Island |
| Apple Intelligence | A summary of your day, written on the iPhone (nothing is sent anywhere) |
| Notifications | A reminder when a task is due, with Mark Done and Snooze on it |
| Spotlight | Your open tasks and the company's clients appear in the iPhone's search |
| Handoff | A task, invoice or client open on the iPhone opens on the Mac's web browser |
| Calendar and Contacts | Add a task to your calendar; save a client to your contacts |
| Phone, Messages, Mail, Maps | Call, text, email, FaceTime or find a client in one tap |
| Background refresh | Widgets and reminders keep up while the app is closed |
| Arabic | The whole app in English and Arabic, right to left |

## Folders

- `MahamKit/`: the app's core as a Swift package. It handles signing in
  (including the authenticator app's code), the database client and the
  data of both departments. It has tests (`swift test`) that run on Linux
  and on the Mac.
- `App/`: the app's screens and its connection to iOS.
- `Widgets/`: the widgets, the controls and the Live Activity.
- `Shared/`: the parts the app and its widgets both use: the session in the
  Keychain, the App Group cache, links and App Intents.
- `project.yml`: the Xcode project, made by [XcodeGen](https://github.com/yonaskolb/XcodeGen).
  The `.xcodeproj` is not kept in git.

## Running it on a Mac

You need a Mac with Xcode 26 or later.

```sh
brew install xcodegen
cd ios
cp Config/Local.xcconfig.example Config/Local.xcconfig   # then put your team id in it
xcodegen
open MahamOne.xcodeproj
```

Pick an iPhone simulator or your iPhone, then press Run. Sign in with your
Maham One email and password.

The database address and its publishable key are in
`Config/Shared.xcconfig`. The key is public by design, and it is the same
one the web app ships. The secret key is never used, and the app refuses
one if it is given by mistake.

Every push to `ios/` builds the app on GitHub's Macs (the "iOS" workflow).
That proves it compiles before anyone opens Xcode.

## Getting it to TestFlight

You need these once:

1. **An Apple Developer Program membership** for the company
   (developer.apple.com, 99 USD a year). Note the **Team ID** under
   Membership details and put it in `Config/Local.xcconfig`.
2. **The app's identifiers.** Xcode makes them the first time it signs the
   app, with "Automatically manage signing":
   - `com.almailgroup.mahamone` (the app)
   - `com.almailgroup.mahamone.widgets` (the widgets)
   - the App Group `group.com.almailgroup.mahamone`, which lets the widgets
     read what the app saved
3. **The app in App Store Connect** (appstoreconnect.apple.com → Apps → +
   → New App). Choose iOS, name it Maham One, language English, the bundle
   id `com.almailgroup.mahamone`, and any SKU (for example `mahamone-ios`).

Then for each build:

1. In Xcode choose **Any iOS Device (arm64)**, then **Product → Archive**.
2. In the Organizer: **Distribute App → App Store Connect → Upload**.
3. In App Store Connect → TestFlight, wait for the build to finish
   processing (about 10–30 minutes). Then add testers. Internal testers
   (people in your App Store Connect team) can install it straight away
   with the TestFlight app. External testers need Apple's quick beta review
   first.

Raise `CURRENT_PROJECT_VERSION` in `project.yml` for each new upload.
`MARKETING_VERSION` is the version people see.

Uploading from GitHub instead of a Mac is possible with an App Store
Connect API key stored as repository secrets. That can be added as its own
workflow when you want it.
