# MoneyTrail Agent Context

## Product

MoneyTrail is a playful, offline-only personal finance tracker built with
Flutter. It supports Android, iOS, and web. The product tracks three areas:

- savings goals and contributions;
- dated, categorized expenses;
- recurring monthly bills and finite installment plans.

The app must remain offline-first. Do not add accounts, cloud synchronization,
analytics, advertising SDKs, or anything that uploads financial data. User
records are stored on-device with `shared_preferences`. The only network feature
is the user-triggered GitHub Release update checker.

## Brand and visual direction

- Product and package name: **MoneyTrail** / `money_trail`.
- Android application ID: `com.vlrdc.moneytrail`.
- Primary accent: teal (`#00897B`, with deeper `#176B67`); secondary accent is
  reddish coral (`#FF6F5E`) matching the logo.
- Light mode uses a clean off-white canvas and rounded white cards.
- Savings goal panels must be white in light mode; do not use a gray
  `surfaceContainerHighest` tint for these cards.
- Dark mode uses a lifted deep green-black background (`#101816`) and visibly
  lighter cards (`#1B2724`) so surfaces remain distinct.
- Keep layouts clean, eye-catching, generously spaced, and consistent.
- Soft coral/lavender background bubbles, colored section markers, and distinct
  teal/coral payment accents add personality without reducing readability.
- Avoid harsh multi-color gradients. The overview savings card uses a restrained
  teal gradient with a much darker variant in dark mode; headers intentionally
  have no colored background.
- Use 20–22 px horizontal gutters so cards and rows never touch screen edges.
- Reusable brand assets live in `assets/branding/`:
  - `moneytrail-icon.png`: trail-and-coin app icon and overview logo.
  - `moneytrail-wordmark.png`: transparent MoneyTrail wordmark for onboarding.
- The generated chroma-key source wordmark is intentionally ignored by Git.

## First-run and navigation behavior

- `WelcomePage` appears only on first launch. It uses a white background,
  the square logo, the MoneyTrail wordmark, a short privacy-focused subtitle,
  and a “Start my trail” action.
- `hasSeenWelcome` is persisted locally.
- Main navigation contains Overview, Expenses, Bills, Savings, and More.
- Page transitions use a short fade-and-slide animation.
- The overview header uses the logo beside the greeting and displays the full
  current date including weekday (`EEEE, MMMM d, yyyy`).

## Current feature behavior

### Overview

- The primary card shows total savings first.
- The total-savings card has a fixed teal background, so all of its text uses
  white rather than dynamic `onPrimary` colors in both themes.
- Savings progress compares saved value against total savings targets.
- Secondary metrics show current-month spending and available monthly budget.
- Upcoming bills and recent expenses use the same horizontal gutters as lists.
- Upcoming cards have the Pay action. Paying records the current month, updates
  an installment balance when relevant, and removes it from Upcoming.
- A custom line chart summarizes daily expenses in the current month.

### Expenses

- Expense fields: ID, title, amount, category, and user-selected date.
- Expenses are editable by tapping the row or its visible edit icon.
- Updating a date re-sorts expenses newest-first.
- The list can be sorted by newest date or name A–Z without mutating storage.
- Swipe from right to left to delete.
- Every destructive delete action requires confirmation before data is removed.

### Bills

- The Payments page has separate Bills and Installments tabs. Stored type
  `recurring` means an indefinite monthly bill; legacy `fixed` means a finite
  installment plan.
- Recurring bills have no total-month input and never complete. Their detail
  screen shows only previous/current/next month, so each new month becomes
  payable. Installments require only total installments; remaining payments are
  calculated from checked schedule entries and can move to Completed.
- Rows show amount/frequency, due day, start month, recorded payment count, and
  installment balance/progress where relevant. The row action is Edit, not Pay.
- Tapping either type opens a dedicated month/year schedule with paid
  checkboxes. There is no floating update action on this screen.
- Overview upcoming cards retain Pay. Paying records the current month and shows
  a clear success/already-paid message; recurring bills become payable again
  automatically when the calendar month changes.
- Ongoing and Completed groups are collapsible. Records can be reordered within
  their type/status group and order persists.
- Local due-date notifications are scheduled on supported mobile platforms.
  Browser background notifications are not guaranteed after the browser closes.

### Savings

- Savings goals have a title, target, accumulated saved amount, remaining
  amount, and animated progress. Each card has an Add Savings action for new
  contributions. Tapping a goal opens editing where the accumulated total can
  be corrected manually; the goal form has no add-amount field.
- Every goal has explicit edit and delete actions in its overflow menu; tapping
  the goal also opens editing.

### Settings

- Monthly allowance is editable.
- Currency is selectable (PHP, USD, EUR, GBP, JPY, AUD, CAD, SGD) and updates
  all displayed amounts.
- Theme choices are system, light, and dark.
- “Check for latest version” queries the public GitHub latest-release API. It
  compares the release body `Build: N` value with the installed build number,
  downloads the APK on Android, and opens the system package installer. Other
  platforms open the download externally. Never embed a GitHub token.
- The privacy card explains that data stays on the device.
- The bottom of the More tab left-aligns `Victor Leandro R. Dela Cruz` without
  a “Created by” label.

## Architecture

- Most implementation currently lives in `lib/main.dart`.
- `AppStore` is a `ChangeNotifier` and owns expenses, bills, savings, theme,
  budget, and first-run state.
- Mutations call `notifyListeners()` before slower persistence or notification
  operations so lists refresh immediately.
- Models serialize to JSON and are saved using `shared_preferences`.
- `NotificationService` uses `flutter_local_notifications`, `timezone`, and
  `flutter_timezone` for recurring local bill reminders.
- Currency display uses the persisted global currency code through `money()`.

## Platform notes

- Android, iOS, and web platform shells are generated.
- Android notification permissions and reboot receivers are configured.
- Android core-library desugaring is enabled for notification scheduling.
- iOS and Android display names are MoneyTrail.
- The default generated Flutter launch image was removed. Native launch
  backgrounds are teal in light mode and black in dark mode.
- Android declares internet and package-install permissions solely for the
  explicit update checker/install flow.
- App icons are generated with `flutter_launcher_icons` from the brand icon.

## Development and verification

```sh
flutter pub get
flutter analyze
flutter test
flutter run -d web-server
flutter build web
flutter build apk --release
```

Before handing off changes, run `dart format`, `flutter analyze`, and the tests.
For visual or interaction changes, also compile the web target. Android builds
require a configured Android SDK; iOS builds require full Xcode and CocoaPods.

## Repository and release context

- GitHub repository: `https://github.com/vileanreal/MoneyTrail`.
- Default branch: `main`.
- Keep generated build outputs out of Git. Attach release APKs to GitHub Releases
  rather than committing binaries to the repository.
- Do not commit secrets, signing keys, local financial data, `.dart_tool/`, or
  `build/` artifacts.
