# MoneyTrail

MoneyTrail is a playful, offline-only Flutter tracker for savings, expenses, and
installment bills on Android, iOS, and the web. Financial records stay on the device. No account,
backend, analytics service, or internet connection is required.

## Features

- Monthly dashboard with budget, spending, unpaid bills, and remaining balance
- Expense recording with categories and swipe-to-delete
- Editable recurring bills with automatic or manual installment deductions
- Savings goals with contributions, targets, and animated progress
- Total remaining installment balance across all bills
- Monthly local notifications for bill due dates
- Teal Material 3 design with glass effects, motion, and light/dark modes
- Local persistence using `shared_preferences`

## Run

```sh
flutter pub get
flutter run
```

To test in a browser without Chrome installed:

```sh
flutter run -d web-server
```

Open the local URL printed by Flutter in Safari or another browser. Browser data
is stored locally. Scheduled background notifications remain a mobile-focused
feature and may not run after the browser is closed.

Android development requires Android Studio and an Android SDK. iOS development
requires a full Xcode installation and CocoaPods. Run `flutter doctor -v` to
check the local toolchain.

## Verify

```sh
flutter analyze
flutter test
```

The default currency is Philippine peso (₱). Change the `money` formatter in
`lib/main.dart` if another currency is needed.
