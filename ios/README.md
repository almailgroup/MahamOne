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
  Keychain, links and App Intents.
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

GitHub builds, signs and uploads the app for you: no Mac needed. You set
it up once; after that a new TestFlight build is one button.

### Once

1. **Apple Developer Program.** You need a membership for the company
   (developer.apple.com). Note the **Team ID** under Membership details.

2. **The app's bundle id.** Go to developer.apple.com → Certificates, IDs &
   Profiles → Identifiers → **+** → App IDs → App. Fill it in like this:
   - Description: `Maham One`
   - Bundle ID: Explicit, `com.almailgroup.mahamone`
   - Then Continue → Register.

   The widgets' id is made by the workflow itself.

3. **The app in App Store Connect.** Go to appstoreconnect.apple.com →
   Apps → **+** → New App, and fill it in like this:
   - Platform: iOS
   - Name: Maham One
   - Language: English
   - Bundle ID: the one from step 2
   - SKU: anything, for example `mahamone-ios`
   - User Access: Full Access

4. **An App Store Connect API key.** Go to App Store Connect → Users and
   Access → Integrations → App Store Connect API → Team Keys → **+**.
   - Name it `GitHub`.
   - Set Access to **Admin**. Xcode needs that to make the signing
     certificates.
   - Note the **Key ID** of the new key, and the **Issuer ID** shown above
     the list.
   - Download the key: a file named `AuthKey_XXXXXXXXXX.p8`. Apple lets you
     download it only once. Keep it safe, and never paste it into a chat or
     an email.

5. **Four secrets in GitHub.** Go to the repository → Settings → Secrets and
   variables → Actions → **New repository secret**, once for each of these:

   | Name | Value |
   |---|---|
   | `APPLE_TEAM_ID` | the Team ID from step 1 |
   | `APP_STORE_CONNECT_KEY_ID` | the Key ID from step 4 |
   | `APP_STORE_CONNECT_ISSUER_ID` | the Issuer ID from step 4 |
   | `APP_STORE_CONNECT_KEY` | the whole text of the `.p8` file. Open it in TextEdit or Notepad and copy everything, from `-----BEGIN PRIVATE KEY-----` to `-----END PRIVATE KEY-----` |

   GitHub keeps secrets encrypted. Nobody can read them back, not even in
   the workflow's logs.

6. **Testers.** In App Store Connect → Maham One → TestFlight → Internal
   Testing → **+**, make a group (for example "Team"). Add yourself and
   anyone in your App Store Connect team, and turn on automatic
   distribution. Each new build then reaches them by itself.

### Each new build

1. In the repository: Actions → **TestFlight** → **Run workflow** → Run.
2. Wait about 15 minutes for the run to turn green. Its summary says which
   build it uploaded, for example `1.0.0 (12.1)`.
3. Apple then processes the build. That usually takes 10–30 minutes, and
   Apple emails you when it's ready. Testers install it with the
   **TestFlight** app on their iPhone or iPad.

The first build asks one question in App Store Connect. Under TestFlight,
the build may show "Missing Compliance". The app only uses the iPhone's
standard encryption, and `ITSAppUsesNonExemptEncryption` already says so,
so it shouldn't ask. If it does, answer "None of the algorithms mentioned
above".

People outside your App Store Connect team are external testers. They need
Apple's beta review once per version (about a day): TestFlight → External
Testing → add a group, then add the build.

The version people see is `MARKETING_VERSION` in `project.yml`
(`1.0.0`). Raise it for a new release. Each run gets its own build number,
so no other edit is needed.

Running the workflow with **Upload** unticked only checks that the App
Store build compiles. It signs nothing and needs no secrets.

Uploading from a Mac instead still works. Put your Team ID in
`Config/Local.xcconfig`, open the project in Xcode, then Product → Archive
→ Distribute App → App Store Connect.
