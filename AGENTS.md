# MoneyTrail Agent Context

## Product

MoneyTrail is a playful, offline-only personal finance tracker built with
Flutter. It supports Android, iOS, and web. The product tracks three areas:

- savings goals and contributions;
- dated, categorized expenses;
- fixed and recurring bills, including remaining-month balances.

The app must remain offline-first. Do not add accounts, cloud synchronization,
analytics, remote APIs, advertising SDKs, or any feature that uploads financial
data. User records are stored on the device with `shared_preferences`.

## Brand and visual direction

- Product and package name: **MoneyTrail** / `money_trail`.
- Android application ID: `com.vlrdc.moneytrail`.
- Primary accent: teal (`#00897B`, with deeper `#176B67`).
- Light mode uses a clean off-white canvas and rounded white cards.
- Dark mode uses a true black background and near-black cards.
- Keep layouts clean, eye-catching, generously spaced, and consistent.
- Avoid harsh multi-color gradients. The overview savings card uses a restrained
  teal gradient; headers intentionally have no colored background.
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
- Savings progress compares saved value against total savings targets.
- Secondary metrics show current-month spending and available monthly budget.
- Upcoming bills and recent expenses use the same horizontal gutters as lists.

### Expenses

- Expense fields: ID, title, amount, category, and user-selected date.
- Expenses are editable by tapping the row or its visible edit icon.
- Updating a date re-sorts expenses newest-first.
- Swipe from right to left to delete.

### Bills

- Bill types are `fixed` and `recurring`.
- Fixed bills do not ask for or display installment/month details.
- Recurring bills store total installments/months and months remaining.
- Each recurring bill row shows amount per installment, total amount left,
  months remaining, due day, and progress.
- Bills can be reordered manually with the drag handle; order persists locally.
- Tapping a bill opens editing. Recurring months left use explicit minus and
  plus controls. There is intentionally no Pay button or checkbox.
- Local due-date notifications are scheduled on supported mobile platforms.
  Browser background notifications are not guaranteed after the browser closes.

### Savings

- Savings goals have a title, target, saved amount, remaining amount, and
  animated progress.
- Goals can be created, edited, and deleted.

### Settings

- Monthly budget is editable.
- Theme choices are system, light, and dark.
- The privacy card explains that data stays on the device.

## Architecture

- Most implementation currently lives in `lib/main.dart`.
- `AppStore` is a `ChangeNotifier` and owns expenses, bills, savings, theme,
  budget, and first-run state.
- Mutations call `notifyListeners()` before slower persistence or notification
  operations so lists refresh immediately.
- Models serialize to JSON and are saved using `shared_preferences`.
- `NotificationService` uses `flutter_local_notifications`, `timezone`, and
  `flutter_timezone` for recurring local bill reminders.
- Currency is currently Philippine peso (`₱`) through the `money()` formatter.

## Platform notes

- Android, iOS, and web platform shells are generated.
- Android notification permissions and reboot receivers are configured.
- Android core-library desugaring is enabled for notification scheduling.
- iOS and Android display names are MoneyTrail.
- The default generated Flutter launch image was removed. Native launch
  backgrounds are teal in light mode and black in dark mode.
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
