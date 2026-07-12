import 'dart:convert';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:universal_io/io.dart';
import 'package:url_launcher/url_launcher.dart';

const teal = Color(0xFF00897B);
const coral = Color(0xFFFF6F5E);
const currencyOptions = <String, ({String symbol, int decimals})>{
  'PHP': (symbol: '₱', decimals: 2),
  'USD': (symbol: r'$', decimals: 2),
  'EUR': (symbol: '€', decimals: 2),
  'GBP': (symbol: '£', decimals: 2),
  'JPY': (symbol: '¥', decimals: 0),
  'AUD': (symbol: r'A$', decimals: 2),
  'CAD': (symbol: r'C$', decimals: 2),
  'SGD': (symbol: r'S$', decimals: 2),
};
String activeCurrencyCode = 'PHP';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = AppStore();
  await store.load();
  await NotificationService.instance.initialize();
  runApp(MoneyTracker(store: store));
}

class MoneyTracker extends StatelessWidget {
  const MoneyTracker({super.key, required this.store});
  final AppStore store;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (_, _) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'MoneyTrail',
        themeMode: store.themeMode,
        theme: appTheme(Brightness.light),
        darkTheme: appTheme(Brightness.dark),
        home: store.hasSeenWelcome
            ? HomePage(store: store)
            : WelcomePage(store: store),
      ),
    );
  }
}

ThemeData appTheme(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(
    seedColor: teal,
    brightness: brightness,
    surface: brightness == Brightness.light
        ? const Color(0xFFF6F6FA)
        : const Color(0xFF101816),
  ).copyWith(secondary: coral, tertiary: const Color(0xFF8B7CF6));
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    cardTheme: CardThemeData(
      elevation: brightness == Brightness.light ? 1 : 0,
      color: brightness == Brightness.light
          ? Colors.white
          : const Color(0xFF1B2724),
      shadowColor: const Color(0xFF6D67A8).withValues(alpha: .12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: brightness == Brightness.light
          ? Colors.white
          : const Color(0xFF202D2A),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: coral,
      foregroundColor: Colors.white,
    ),
    navigationBarTheme: NavigationBarThemeData(
      indicatorColor: brightness == Brightness.light
          ? coral.withValues(alpha: .18)
          : coral.withValues(alpha: .28),
    ),
  );
}

class Expense {
  Expense({
    required this.id,
    required this.title,
    required this.amount,
    required this.category,
    required this.date,
  });
  final int id;
  String title;
  double amount;
  String category;
  DateTime date;
  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'amount': amount,
    'category': category,
    'date': date.toIso8601String(),
  };
  factory Expense.fromJson(Map<String, dynamic> j) => Expense(
    id: j['id'],
    title: j['title'],
    amount: (j['amount'] as num).toDouble(),
    category: j['category'],
    date: DateTime.parse(j['date']),
  );
}

class Bill {
  Bill({
    required this.id,
    required this.title,
    required this.amount,
    required this.dueDay,
    this.paid = false,
    this.reminder = true,
    this.totalInstallments = 1,
    int? remainingInstallments,
    this.autoDeduct = true,
    this.type = 'fixed',
    DateTime? startMonth,
    List<String>? paidMonths,
  }) : remainingInstallments = remainingInstallments ?? totalInstallments,
       startMonth =
           startMonth ?? DateTime(DateTime.now().year, DateTime.now().month),
       paidMonths = paidMonths ?? [];
  final int id;
  String title;
  double amount;
  int dueDay;
  bool paid;
  bool reminder;
  int totalInstallments;
  int remainingInstallments;
  bool autoDeduct;
  String type;
  DateTime startMonth;
  List<String> paidMonths;
  double get amountLeft =>
      type == 'recurring' ? amount : amount * remainingInstallments;
  bool get isCompleted => type != 'recurring' && remainingInstallments <= 0;
  bool get isPaidThisMonth =>
      paidMonths.contains(DateFormat('yyyy-MM').format(DateTime.now()));
  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'amount': amount,
    'dueDay': dueDay,
    'paid': paid,
    'reminder': reminder,
    'totalInstallments': totalInstallments,
    'remainingInstallments': remainingInstallments,
    'autoDeduct': autoDeduct,
    'type': type,
    'startMonth': startMonth.toIso8601String(),
    'paidMonths': paidMonths,
  };
  factory Bill.fromJson(Map<String, dynamic> j) => Bill(
    id: j['id'],
    title: j['title'],
    amount: (j['amount'] as num).toDouble(),
    dueDay: j['dueDay'],
    paid: j['paid'] ?? false,
    reminder: j['reminder'] ?? true,
    totalInstallments: j['totalInstallments'] ?? 1,
    remainingInstallments:
        j['remainingInstallments'] ?? j['totalInstallments'] ?? 1,
    autoDeduct: j['autoDeduct'] ?? true,
    type: j['type'] ?? 'fixed',
    startMonth: j['startMonth'] == null
        ? null
        : DateTime.parse(j['startMonth']),
    paidMonths: (j['paidMonths'] as List?)?.cast<String>(),
  );
}

class SavingGoal {
  SavingGoal({
    required this.id,
    required this.title,
    required this.target,
    this.saved = 0,
  });
  final int id;
  String title;
  double target;
  double saved;
  double get remaining => (target - saved).clamp(0, double.infinity);
  double get progress => target <= 0 ? 0 : (saved / target).clamp(0, 1);
  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'target': target,
    'saved': saved,
  };
  factory SavingGoal.fromJson(Map<String, dynamic> j) => SavingGoal(
    id: j['id'],
    title: j['title'],
    target: (j['target'] as num).toDouble(),
    saved: (j['saved'] as num?)?.toDouble() ?? 0,
  );
}

class AppStore extends ChangeNotifier {
  final expenses = <Expense>[];
  final bills = <Bill>[];
  final savings = <SavingGoal>[];
  ThemeMode themeMode = ThemeMode.system;
  double monthlyBudget = 30000;
  String currencyCode = 'PHP';
  bool hasSeenWelcome = false;

  double get monthExpenses => expenses
      .where(
        (e) =>
            e.date.year == DateTime.now().year &&
            e.date.month == DateTime.now().month,
      )
      .fold(0, (a, e) => a + e.amount);
  double get billTotal => bills.fold(0, (a, b) => a + b.amount);
  double get unpaidBills => bills
      .where((b) => !b.isCompleted && !b.isPaidThisMonth)
      .fold(0, (a, b) => a + b.amount);
  double get billsLeftTotal => bills.fold(0, (a, b) => a + b.amountLeft);
  double get totalSavings => savings.fold(0, (a, s) => a + s.saved);
  double get savingsTarget => savings.fold(0, (a, s) => a + s.target);
  double get savingsRemaining =>
      savings.fold(0, (total, goal) => total + goal.remaining);
  double get remaining => monthlyBudget - monthExpenses - unpaidBills;

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    monthlyBudget = p.getDouble('budget') ?? 30000;
    currencyCode = p.getString('currencyCode') ?? 'PHP';
    if (!currencyOptions.containsKey(currencyCode)) currencyCode = 'PHP';
    activeCurrencyCode = currencyCode;
    hasSeenWelcome = p.getBool('hasSeenWelcome') ?? false;
    themeMode = ThemeMode.values[p.getInt('theme') ?? 0];
    final expenseData = p.getString('expenses');
    final billData = p.getString('bills');
    final savingsData = p.getString('savings');
    if (expenseData != null) {
      expenses.addAll(
        (jsonDecode(expenseData) as List).map((e) => Expense.fromJson(e)),
      );
    }
    if (billData != null) {
      bills.addAll((jsonDecode(billData) as List).map((e) => Bill.fromJson(e)));
    }
    if (savingsData != null) {
      savings.addAll(
        (jsonDecode(savingsData) as List).map((e) => SavingGoal.fromJson(e)),
      );
    }
  }

  Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    await p.setDouble('budget', monthlyBudget);
    await p.setString('currencyCode', currencyCode);
    await p.setBool('hasSeenWelcome', hasSeenWelcome);
    await p.setInt('theme', themeMode.index);
    await p.setString(
      'expenses',
      jsonEncode(expenses.map((e) => e.toJson()).toList()),
    );
    await p.setString(
      'bills',
      jsonEncode(bills.map((e) => e.toJson()).toList()),
    );
    await p.setString(
      'savings',
      jsonEncode(savings.map((e) => e.toJson()).toList()),
    );
  }

  Future<void> addExpense(Expense value) async {
    expenses.insert(0, value);
    notifyListeners();
    await save();
  }

  Future<void> removeExpense(Expense value) async {
    expenses.remove(value);
    notifyListeners();
    await save();
  }

  Future<void> updateExpense(Expense value) async {
    expenses.sort((a, b) => b.date.compareTo(a.date));
    notifyListeners();
    await save();
  }

  Future<void> addBill(Bill value) async {
    bills.add(value);
    notifyListeners();
    await save();
    await NotificationService.instance.schedule(value);
  }

  Future<void> removeBill(Bill value) async {
    bills.remove(value);
    notifyListeners();
    await save();
    await NotificationService.instance.cancel(value.id);
  }

  Future<void> reorderBills(int oldIndex, int newIndex) async {
    final bill = bills.removeAt(oldIndex);
    bills.insert(newIndex, bill);
    notifyListeners();
    await save();
  }

  Future<void> setBillOrder(List<int> orderedIds) async {
    final byId = {for (final bill in bills) bill.id: bill};
    bills
      ..clear()
      ..addAll(orderedIds.map((id) => byId[id]).whereType<Bill>());
    notifyListeners();
    await save();
  }

  Future<void> changeInstallments(Bill value, int delta) async {
    value.remainingInstallments = (value.remainingInstallments + delta).clamp(
      0,
      60,
    );
    if (value.remainingInstallments > value.totalInstallments) {
      value.totalInstallments = value.remainingInstallments;
    }
    notifyListeners();
    await save();
  }

  Future<void> recordBillPayment(Bill value) async {
    if (value.isCompleted) return;
    final month = DateFormat('yyyy-MM').format(DateTime.now());
    if (value.paidMonths.contains(month)) return;
    value.paidMonths.add(month);
    value.paid = true;
    if (value.type != 'recurring') value.remainingInstallments--;
    notifyListeners();
    await save();
  }

  Future<void> setBillMonthPaid(Bill value, DateTime month, bool isPaid) async {
    final key = DateFormat('yyyy-MM').format(month);
    if (isPaid && !value.paidMonths.contains(key)) {
      value.paidMonths.add(key);
    } else if (!isPaid) {
      value.paidMonths.remove(key);
    }
    value.paidMonths.sort();
    if (value.type != 'recurring') {
      final scheduledMonths = List.generate(
        value.totalInstallments,
        (index) => DateFormat('yyyy-MM').format(
          DateTime(value.startMonth.year, value.startMonth.month + index),
        ),
      );
      final paidScheduled = value.paidMonths
          .where(scheduledMonths.contains)
          .length;
      value.remainingInstallments = (value.totalInstallments - paidScheduled)
          .clamp(0, value.totalInstallments);
    }
    value.paid = value.isPaidThisMonth;
    notifyListeners();
    await save();
  }

  Future<void> undoBillPayment(Bill value) async {
    value.paid = false;
    if (value.paidMonths.isNotEmpty) value.paidMonths.removeLast();
    if (value.remainingInstallments < value.totalInstallments) {
      value.remainingInstallments++;
    }
    notifyListeners();
    await save();
  }

  Future<void> deductInstallment(Bill value) async {
    if (value.remainingInstallments > 0) value.remainingInstallments--;
    notifyListeners();
    await save();
  }

  Future<void> updateBill(Bill value) async {
    notifyListeners();
    await save();
    await NotificationService.instance.cancel(value.id);
    await NotificationService.instance.schedule(value);
  }

  Future<void> addSaving(SavingGoal value) async {
    savings.add(value);
    notifyListeners();
    await save();
  }

  Future<void> updateSaving(SavingGoal value) async {
    notifyListeners();
    await save();
  }

  Future<void> removeSaving(SavingGoal value) async {
    savings.remove(value);
    notifyListeners();
    await save();
  }

  Future<void> setTheme(ThemeMode value) async {
    themeMode = value;
    await save();
    notifyListeners();
  }

  Future<void> setBudget(double value) async {
    monthlyBudget = value;
    await save();
    notifyListeners();
  }

  Future<void> setCurrency(String value) async {
    if (!currencyOptions.containsKey(value)) return;
    currencyCode = value;
    activeCurrencyCode = value;
    notifyListeners();
    await save();
  }

  Future<void> completeWelcome() async {
    hasSeenWelcome = true;
    notifyListeners();
    await save();
  }
}

class NotificationService {
  NotificationService._();
  static final instance = NotificationService._();
  final plugin = FlutterLocalNotificationsPlugin();

  Future<void> initialize() async {
    tz.initializeTimeZones();
    try {
      final zone = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(zone.identifier));
    } catch (_) {}
    await plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(),
      ),
    );
  }

  Future<void> requestPermission() async {
    await plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestNotificationsPermission();
    await plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >()
        ?.requestPermissions(alert: true, badge: true, sound: true);
  }

  Future<void> schedule(Bill bill) async {
    if (!bill.reminder) return;
    await requestPermission();
    final now = tz.TZDateTime.now(tz.local);
    var when = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      bill.dueDay.clamp(1, 28),
      9,
    );
    if (when.isBefore(now)) {
      when = tz.TZDateTime(
        tz.local,
        now.year,
        now.month + 1,
        bill.dueDay.clamp(1, 28),
        9,
      );
    }
    await plugin.zonedSchedule(
      id: bill.id,
      title: '${bill.title} is due soon',
      body: '${money(bill.amount)} is due today.',
      scheduledDate: when,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'bill_reminders',
          'Bill reminders',
          channelDescription: 'Monthly bill due reminders',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.dayOfMonthAndTime,
    );
  }

  Future<void> cancel(int id) => plugin.cancel(id: id);
}

String money(double value) {
  final currency = currencyOptions[activeCurrencyCode]!;
  return NumberFormat.currency(
    symbol: currency.symbol,
    decimalDigits: currency.decimals,
  ).format(value);
}

class GitHubReleaseInfo {
  const GitHubReleaseInfo({
    required this.version,
    required this.buildNumber,
    required this.downloadUrl,
    required this.releaseUrl,
  });
  final String version;
  final int buildNumber;
  final String downloadUrl;
  final String releaseUrl;
}

class UpdateService {
  static const latestReleaseApi =
      'https://api.github.com/repos/vileanreal/MoneyTrail/releases/latest';

  static Future<({GitHubReleaseInfo release, bool hasUpdate, String current})>
  check() async {
    final response = await http
        .get(
          Uri.parse(latestReleaseApi),
          headers: const {
            'Accept': 'application/vnd.github+json',
            'User-Agent': 'MoneyTrail-App',
          },
        )
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      throw Exception('GitHub returned ${response.statusCode}.');
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final assets = (data['assets'] as List).cast<Map<String, dynamic>>();
    final apk = assets.cast<Map<String, dynamic>?>().firstWhere(
      (asset) => (asset?['name'] as String? ?? '').endsWith('.apk'),
      orElse: () => null,
    );
    if (apk == null) throw Exception('The latest release has no APK.');
    final body = data['body'] as String? ?? '';
    final buildMatch = RegExp(
      r'Build:\s*(\d+)',
      caseSensitive: false,
    ).firstMatch(body);
    final latestBuild = int.tryParse(buildMatch?.group(1) ?? '') ?? 1;
    final package = await PackageInfo.fromPlatform();
    final currentBuild = int.tryParse(package.buildNumber) ?? 1;
    final tag = (data['tag_name'] as String? ?? 'v1.0.0').replaceFirst('v', '');
    return (
      release: GitHubReleaseInfo(
        version: tag,
        buildNumber: latestBuild,
        downloadUrl: apk['browser_download_url'] as String,
        releaseUrl: data['html_url'] as String,
      ),
      hasUpdate: latestBuild > currentBuild,
      current: '${package.version}+${package.buildNumber}',
    );
  }

  static Future<void> downloadAndInstall(GitHubReleaseInfo release) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      await launchUrl(
        Uri.parse(release.downloadUrl),
        mode: LaunchMode.externalApplication,
      );
      return;
    }
    final response = await http
        .get(Uri.parse(release.downloadUrl))
        .timeout(const Duration(minutes: 3));
    if (response.statusCode != 200) {
      throw Exception('Download failed (${response.statusCode}).');
    }
    final directory = await getTemporaryDirectory();
    final file = File('${directory.path}/MoneyTrail-latest.apk');
    await file.writeAsBytes(response.bodyBytes, flush: true);
    final result = await OpenFilex.open(
      file.path,
      type: 'application/vnd.android.package-archive',
    );
    if (result.type != ResultType.done) throw Exception(result.message);
  }
}

Future<void> showUpdateChecker(BuildContext context) async {
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const AlertDialog(
      content: Row(
        children: [
          CircularProgressIndicator(),
          SizedBox(width: 18),
          Expanded(child: Text('Checking GitHub for updates…')),
        ],
      ),
    ),
  );
  try {
    final result = await UpdateService.check();
    if (!context.mounted) return;
    Navigator.pop(context);
    if (!result.hasUpdate) {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          icon: const Icon(Icons.verified_rounded, color: teal),
          title: const Text('MoneyTrail is up to date'),
          content: Text('Installed version: ${result.current}'),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Done'),
            ),
          ],
        ),
      );
      return;
    }
    final shouldInstall = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.system_update_rounded, color: coral),
        title: Text('MoneyTrail ${result.release.version} is available'),
        content: Text(
          'Build ${result.release.buildNumber} is newer than ${result.current}. Download and open the installer now?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Later'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.download_rounded),
            label: const Text('Download'),
          ),
        ],
      ),
    );
    if (shouldInstall != true || !context.mounted) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 18),
            Expanded(child: Text('Downloading the latest APK…')),
          ],
        ),
      ),
    );
    await UpdateService.downloadAndInstall(result.release);
    if (context.mounted) Navigator.pop(context);
  } catch (error) {
    if (!context.mounted) return;
    Navigator.of(
      context,
      rootNavigator: true,
    ).popUntil((route) => route.isFirst);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Could not check for updates: $error')),
    );
  }
}

Future<bool> confirmDelete(BuildContext context, String itemName) async {
  return await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          icon: const Icon(Icons.delete_outline),
          title: Text('Delete $itemName?'),
          content: const Text('This action cannot be undone.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(dialogContext).colorScheme.error,
                foregroundColor: Theme.of(dialogContext).colorScheme.onError,
              ),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Delete'),
            ),
          ],
        ),
      ) ??
      false;
}

Future<void> payCurrentBillMonth(
  BuildContext context,
  AppStore store,
  Bill bill,
) async {
  final label = DateFormat('MMMM yyyy').format(DateTime.now());
  if (bill.isPaidThisMonth) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${bill.title} is already paid for $label.')),
    );
    return;
  }
  if (bill.isCompleted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${bill.title} is already completed.')),
    );
    return;
  }
  await store.recordBillPayment(bill);
  if (!context.mounted) return;
  ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text('${bill.title} was paid for $label.')));
}

class WelcomePage extends StatelessWidget {
  const WelcomePage({super.key, required this.store});
  final AppStore store;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.white,
    body: SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Spacer(flex: 2),
            TweenAnimationBuilder<double>(
              tween: Tween(begin: .7, end: 1),
              duration: const Duration(milliseconds: 700),
              curve: Curves.easeOutBack,
              builder: (_, value, child) =>
                  Transform.scale(scale: value, child: child),
              child: Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  color: teal.withValues(alpha: .12),
                  shape: BoxShape.circle,
                  border: Border.all(color: teal.withValues(alpha: .2)),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: Image.asset(
                    'assets/branding/moneytrail-icon.png',
                    width: 82,
                    height: 82,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 34),
            const Text(
              'Welcome to',
              style: TextStyle(
                color: Color(0xFF172A38),
                fontSize: 32,
                height: 1.02,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 14),
            Semantics(
              label: 'MoneyTrail',
              image: true,
              child: Image.asset(
                'assets/branding/moneytrail-wordmark.png',
                width: 330,
                fit: BoxFit.contain,
              ),
            ),
            const SizedBox(height: 22),
            const Text(
              'Track savings, everyday spending, and every bill—privately on this device.',
              style: TextStyle(
                color: Color(0xFF647381),
                fontSize: 17,
                height: 1.5,
              ),
            ),
            const Spacer(),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: teal,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(58),
              ),
              onPressed: store.completeWelcome,
              icon: const Icon(Icons.arrow_forward_rounded),
              label: const Text('Start my trail'),
            ),
          ],
        ),
      ),
    ),
  );
}

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.store});
  final AppStore store;
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int index = 0;
  @override
  Widget build(BuildContext context) {
    final pages = [
      Dashboard(store: widget.store),
      ExpensesPage(store: widget.store),
      BillsPage(store: widget.store),
      SavingsPage(store: widget.store),
      SettingsPage(store: widget.store),
    ];
    return Scaffold(
      body: Stack(
        children: [
          Positioned(
            top: 80,
            right: -75,
            child: _BackgroundBubble(
              color: Theme.of(context).brightness == Brightness.light
                  ? const Color(0xFFFFCFC5)
                  : const Color(0xFF3A1715),
              size: 190,
            ),
          ),
          Positioned(
            bottom: 90,
            left: -95,
            child: _BackgroundBubble(
              color: Theme.of(context).brightness == Brightness.light
                  ? const Color(0xFFDCD7FF)
                  : const Color(0xFF1C183A),
              size: 220,
            ),
          ),
          SafeArea(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 320),
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween(
                    begin: const Offset(.03, 0),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                ),
              ),
              child: KeyedSubtree(key: ValueKey(index), child: pages[index]),
            ),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (v) => setState(() => index = v),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.grid_view_rounded),
            label: 'Overview',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            label: 'Expenses',
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined),
            label: 'Bills',
          ),
          NavigationDestination(
            icon: Icon(Icons.savings_outlined),
            label: 'Savings',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            label: 'More',
          ),
        ],
      ),
      floatingActionButton: index == 1 || index == 3
          ? FloatingActionButton.extended(
              onPressed: () => index == 1
                  ? showExpenseSheet(context, widget.store)
                  : showSavingSheet(context, widget.store),
              icon: const Icon(Icons.add),
              label: Text(index == 1 ? 'Expense' : 'Goal'),
            )
          : null,
    );
  }
}

class _BackgroundBubble extends StatelessWidget {
  const _BackgroundBubble({required this.color, required this.size});
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: .34),
        shape: BoxShape.circle,
      ),
    ),
  );
}

class PageHeader extends StatelessWidget {
  const PageHeader(
    this.title,
    this.subtitle, {
    super.key,
    this.showLogo = false,
  });
  final String title;
  final String subtitle;
  final bool showLogo;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
    child: Row(
      children: [
        if (showLogo) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Image.asset(
              'assets/branding/moneytrail-icon.png',
              width: 48,
              height: 48,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(width: 13),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontWeight: FontWeight.w900,
                ),
              ),
              if (subtitle.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    ),
  );
}

class Dashboard extends StatelessWidget {
  const Dashboard({super.key, required this.store});
  final AppStore store;
  @override
  Widget build(BuildContext context) {
    final progress = store.savingsTarget == 0
        ? 0.0
        : (store.totalSavings / store.savingsTarget).clamp(0.0, 1.0);
    final upcoming = [
      ...store.bills.where((b) => !b.isCompleted && !b.isPaidThisMonth),
    ]..sort((a, b) => a.dueDay.compareTo(b.dueDay));
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        PageHeader(
          'Good ${DateTime.now().hour < 12
              ? 'morning'
              : DateTime.now().hour < 18
              ? 'afternoon'
              : 'evening'}',
          DateFormat('EEEE, MMMM d, yyyy').format(DateTime.now()),
          showLogo: true,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: GlassPanel(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: Theme.of(context).brightness == Brightness.dark
                  ? const [Color(0xFF031B19), Color(0xFF0B3A35)]
                  : const [Color(0xFF176B67), Color(0xFF2A9D8F)],
            ),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Total savings',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: .82),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TweenAnimationBuilder<double>(
                    tween: Tween(end: store.totalSavings),
                    duration: const Duration(milliseconds: 650),
                    builder: (_, value, _) => Text(
                      money(value),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 34,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),
                  LinearProgressIndicator(
                    value: progress,
                    minHeight: 8,
                    borderRadius: BorderRadius.circular(20),
                    backgroundColor: Colors.white24,
                    color: const Color(0xFFA7F3D0),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    store.savingsTarget == 0
                        ? 'Create a goal to start your trail'
                        : '${money(store.totalSavings)} of ${money(store.savingsTarget)} saved',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: .82),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        StatsCarousel(
          items: [
            MetricData(
              icon: Icons.shopping_bag_outlined,
              label: 'Spent this month',
              value: money(store.monthExpenses),
              color: coral,
            ),
            MetricData(
              icon: Icons.account_balance_wallet_outlined,
              label: 'Allowance available',
              value: money(store.remaining),
              color: teal,
            ),
            MetricData(
              icon: Icons.event_note_outlined,
              label: 'Payments due',
              value: money(store.unpaidBills),
              color: const Color(0xFF8B7CF6),
            ),
            MetricData(
              icon: Icons.flag_outlined,
              label: 'Savings to go',
              value: money(store.savingsRemaining),
              color: const Color(0xFFFFA23A),
            ),
          ],
        ),
        MonthlyExpenseChart(expenses: store.expenses),
        SectionTitle(
          'Upcoming bills',
          upcoming.isEmpty ? '' : '${upcoming.length} remaining',
        ),
        if (upcoming.isEmpty)
          const EmptyCard(
            icon: Icons.check_circle_outline,
            text: 'You are all caught up',
          )
        else
          ...upcoming
              .take(3)
              .map(
                (b) => Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: BillTile(bill: b, store: store, showPayAction: true),
                ),
              ),
        const SectionTitle('Recent expenses', ''),
        if (store.expenses.isEmpty)
          const EmptyCard(
            icon: Icons.receipt_long_outlined,
            text: 'Your recent spending appears here',
          )
        else
          ...store.expenses
              .take(3)
              .map(
                (e) => Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: ExpenseTile(expense: e, store: store),
                ),
              ),
      ],
    );
  }
}

class MonthlyExpenseChart extends StatelessWidget {
  const MonthlyExpenseChart({super.key, required this.expenses});
  final List<Expense> expenses;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final days = DateTime(now.year, now.month + 1, 0).day;
    final values = List<double>.filled(days, 0);
    for (final expense in expenses) {
      if (expense.date.year == now.year && expense.date.month == now.month) {
        values[expense.date.day - 1] += expense.amount;
      }
    }
    final total = values.fold<double>(0, (sum, value) => sum + value);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(
                      color: coral.withValues(alpha: .14),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.show_chart_rounded, color: coral),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Expenses this month',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                        Text(
                          money(total),
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              SizedBox(
                height: 145,
                width: double.infinity,
                child: CustomPaint(
                  painter: _ExpenseLinePainter(
                    values: values,
                    gridColor: Theme.of(
                      context,
                    ).colorScheme.outlineVariant.withValues(alpha: .45),
                  ),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Day 1'),
                  Text('Day ${(days / 2).round()}'),
                  Text('Day $days'),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ExpenseLinePainter extends CustomPainter {
  const _ExpenseLinePainter({required this.values, required this.gridColor});
  final List<double> values;
  final Color gridColor;

  @override
  void paint(Canvas canvas, Size size) {
    final maxValue = values.fold<double>(
      0,
      (max, value) => value > max ? value : max,
    );
    final chartMax = maxValue <= 0 ? 1.0 : maxValue * 1.15;
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (var line = 0; line <= 3; line++) {
      final y = size.height * line / 3;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
    final path = Path();
    for (var index = 0; index < values.length; index++) {
      final x = size.width * index / (values.length - 1);
      final y = size.height - (values[index] / chartMax * size.height);
      if (index == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    final fill = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(fill, Paint()..color = coral.withValues(alpha: .10));
    canvas.drawPath(
      path,
      Paint()
        ..color = coral
        ..strokeWidth = 3
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _ExpenseLinePainter oldDelegate) =>
      oldDelegate.values != values || oldDelegate.gridColor != gridColor;
}

class GlassPanel extends StatelessWidget {
  const GlassPanel({super.key, required this.child, this.gradient});
  final Widget child;
  final Gradient? gradient;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(26),
    child: BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 350),
        decoration: BoxDecoration(
          gradient: gradient,
          color: gradient == null
              ? Theme.of(context).brightness == Brightness.light
                    ? Colors.white
                    : const Color(0xFF1B2724)
              : null,
          borderRadius: BorderRadius.circular(26),
          border: Border.all(
            color: Theme.of(context).brightness == Brightness.light
                ? teal.withValues(alpha: .08)
                : Colors.white.withValues(alpha: .12),
          ),
          boxShadow: [
            BoxShadow(
              color: teal.withValues(alpha: .16),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: child,
      ),
    ),
  );
}

class MetricData {
  const MetricData({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });
  final IconData icon;
  final String label;
  final String value;
  final Color color;
}

class StatsCarousel extends StatefulWidget {
  const StatsCarousel({super.key, required this.items});
  final List<MetricData> items;

  @override
  State<StatsCarousel> createState() => _StatsCarouselState();
}

class _StatsCarouselState extends State<StatsCarousel> {
  late final PageController controller;
  int page = 0;

  @override
  void initState() {
    super.initState();
    controller = PageController(viewportFraction: .47);
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      SizedBox(
        height: 148,
        child: PageView.builder(
          controller: controller,
          padEnds: false,
          itemCount: widget.items.length,
          onPageChanged: (value) => setState(() => page = value),
          itemBuilder: (_, index) {
            final item = widget.items[index];
            return Padding(
              padding: EdgeInsets.only(
                left: index == 0 ? 20 : 4,
                right: index == widget.items.length - 1 ? 20 : 8,
              ),
              child: MetricCard(
                icon: item.icon,
                label: item.label,
                value: item.value,
                color: item.color,
              ),
            );
          },
        ),
      ),
      const SizedBox(height: 6),
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(
          widget.items.length,
          (index) => AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            width: index == page ? 18 : 6,
            height: 6,
            margin: const EdgeInsets.symmetric(horizontal: 3),
            decoration: BoxDecoration(
              color: index == page
                  ? teal
                  : Theme.of(context).colorScheme.outlineVariant,
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
      ),
    ],
  );
}

class MetricCard extends StatelessWidget {
  const MetricCard({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.color = teal,
  });
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: .14),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(icon, color: color),
          ),
          const SizedBox(height: 10),
          Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 5),
          FittedBox(
            child: Text(
              value,
              style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    ),
  );
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, this.trailing, {super.key});
  final String title;
  final String trailing;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(22, 26, 22, 10),
    child: Row(
      children: [
        Container(
          width: 8,
          height: 22,
          decoration: BoxDecoration(
            color: title == 'Completed' ? const Color(0xFF8B7CF6) : teal,
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
        ),
        Text(
          trailing,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    ),
  );
}

class EmptyCard extends StatelessWidget {
  const EmptyCard({super.key, required this.icon, required this.text});
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 20),
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Row(
          children: [
            Icon(icon, color: teal),
            const SizedBox(width: 14),
            Expanded(child: Text(text)),
          ],
        ),
      ),
    ),
  );
}

class ExpensesPage extends StatefulWidget {
  const ExpensesPage({super.key, required this.store});
  final AppStore store;

  @override
  State<ExpensesPage> createState() => _ExpensesPageState();
}

class _ExpensesPageState extends State<ExpensesPage> {
  String sortBy = 'date';

  @override
  Widget build(BuildContext context) {
    final expenses = [...widget.store.expenses];
    if (sortBy == 'name') {
      expenses.sort(
        (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
      );
    } else {
      expenses.sort((a, b) => b.date.compareTo(a.date));
    }
    return Column(
      children: [
        const PageHeader('Expenses', 'Everything you spend, in one place'),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
          child: Row(
            children: [
              Text('Sort by', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(width: 10),
              Expanded(
                child: SegmentedButton<String>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(
                      value: 'date',
                      icon: Icon(Icons.calendar_today_outlined),
                      label: Text('Date'),
                    ),
                    ButtonSegment(
                      value: 'name',
                      icon: Icon(Icons.sort_by_alpha_rounded),
                      label: Text('Name'),
                    ),
                  ],
                  selected: {sortBy},
                  onSelectionChanged: (value) =>
                      setState(() => sortBy = value.first),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: expenses.isEmpty
              ? const Center(
                  child: EmptyState(
                    icon: Icons.receipt_long_outlined,
                    title: 'No expenses yet',
                    body: 'Tap “Expense” to record your first purchase.',
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 90),
                  itemCount: expenses.length,
                  itemBuilder: (_, i) =>
                      ExpenseTile(expense: expenses[i], store: widget.store),
                ),
        ),
      ],
    );
  }
}

class ExpenseTile extends StatelessWidget {
  const ExpenseTile({super.key, required this.expense, required this.store});
  final Expense expense;
  final AppStore store;
  @override
  Widget build(BuildContext context) => Dismissible(
    key: ValueKey(expense.id),
    direction: DismissDirection.endToStart,
    background: Container(
      margin: const EdgeInsets.symmetric(vertical: 5),
      padding: const EdgeInsets.only(right: 20),
      alignment: Alignment.centerRight,
      decoration: BoxDecoration(
        color: Colors.red.shade400,
        borderRadius: BorderRadius.circular(22),
      ),
      child: const Icon(Icons.delete_outline, color: Colors.white),
    ),
    confirmDismiss: (_) => confirmDelete(context, 'expense'),
    onDismissed: (_) => store.removeExpense(expense),
    child: Card(
      margin: const EdgeInsets.symmetric(horizontal: 0, vertical: 5),
      child: ListTile(
        onTap: () => showExpenseSheet(context, store, expense: expense),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: CircleAvatar(
          backgroundColor: teal.withValues(alpha: .12),
          child: Icon(categoryIcon(expense.category), color: teal),
        ),
        title: Text(
          expense.title,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          '${expense.category} · ${DateFormat('MMM d').format(expense.date)}',
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '-${money(expense.amount)}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            IconButton(
              tooltip: 'Edit expense',
              visualDensity: VisualDensity.compact,
              onPressed: () =>
                  showExpenseSheet(context, store, expense: expense),
              icon: const Icon(Icons.edit_outlined, size: 19),
            ),
          ],
        ),
      ),
    ),
  );
}

class BillsPage extends StatefulWidget {
  const BillsPage({super.key, required this.store});
  final AppStore store;

  @override
  State<BillsPage> createState() => _BillsPageState();
}

class _BillsPageState extends State<BillsPage> {
  int selectedTab = 0;

  @override
  Widget build(BuildContext context) {
    final recurring = widget.store.bills
        .where((bill) => bill.type == 'recurring')
        .toList();
    final installments = widget.store.bills
        .where((bill) => bill.type != 'recurring')
        .toList();
    return Stack(
      children: [
        Column(
          children: [
            PageHeader(
              'Payments',
              selectedTab == 0
                  ? '${recurring.length} recurring bill${recurring.length == 1 ? '' : 's'}'
                  : '${money(installments.fold<double>(0, (sum, bill) => sum + bill.amountLeft))} installment balance',
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Theme.of(context).brightness == Brightness.light
                      ? const Color(0xFFE9E7FF)
                      : const Color(0xFF171522),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: SegmentedButton<int>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(
                      value: 0,
                      icon: Icon(Icons.autorenew_rounded),
                      label: Text('Bills'),
                    ),
                    ButtonSegment(
                      value: 1,
                      icon: Icon(Icons.payments_outlined),
                      label: Text('Installments'),
                    ),
                  ],
                  selected: {selectedTab},
                  onSelectionChanged: (value) =>
                      setState(() => selectedTab = value.first),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: IndexedStack(
                index: selectedTab,
                children: [
                  _BillsTypeTab(
                    bills: recurring,
                    store: widget.store,
                    emptyTitle: 'No recurring bills',
                    emptyBody:
                        'Add electricity, rent, Spotify, or any monthly bill.',
                  ),
                  _BillsTypeTab(
                    bills: installments,
                    store: widget.store,
                    emptyTitle: 'No installment plans',
                    emptyBody:
                        'Add a phone, appliance, loan, or other finite plan.',
                  ),
                ],
              ),
            ),
          ],
        ),
        Positioned(
          right: 20,
          bottom: 18,
          child: FloatingActionButton.extended(
            heroTag: 'add-payment',
            onPressed: () => showBillSheet(
              context,
              widget.store,
              initialType: selectedTab == 0 ? 'recurring' : 'fixed',
            ),
            icon: const Icon(Icons.add),
            label: Text(selectedTab == 0 ? 'Add bill' : 'Add installment'),
          ),
        ),
      ],
    );
  }
}

class _BillsTypeTab extends StatelessWidget {
  const _BillsTypeTab({
    required this.bills,
    required this.store,
    required this.emptyTitle,
    required this.emptyBody,
  });
  final List<Bill> bills;
  final AppStore store;
  final String emptyTitle;
  final String emptyBody;

  void _reorder(List<Bill> group, int oldIndex, int newIndex) {
    final reordered = [...group];
    final moved = reordered.removeAt(oldIndex);
    reordered.insert(newIndex, moved);
    final idsInGroup = group.map((bill) => bill.id).toSet();
    var replacementIndex = 0;
    final orderedIds = store.bills.map((bill) {
      if (!idsInGroup.contains(bill.id)) return bill.id;
      return reordered[replacementIndex++].id;
    }).toList();
    store.setBillOrder(orderedIds);
  }

  @override
  Widget build(BuildContext context) {
    if (bills.isEmpty) {
      return Center(
        child: EmptyState(
          icon: Icons.calendar_month_outlined,
          title: emptyTitle,
          body: emptyBody,
        ),
      );
    }
    final ongoing = bills.where((bill) => !bill.isCompleted).toList();
    final completed = bills.where((bill) => bill.isCompleted).toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
      children: [
        if (ongoing.isNotEmpty) ...[
          Card(
            margin: const EdgeInsets.only(bottom: 14),
            child: ExpansionTile(
              initiallyExpanded: true,
              shape: const RoundedRectangleBorder(side: BorderSide.none),
              collapsedShape: const RoundedRectangleBorder(
                side: BorderSide.none,
              ),
              leading: const CircleAvatar(
                backgroundColor: teal,
                foregroundColor: Colors.white,
                child: Icon(Icons.play_arrow_rounded),
              ),
              title: const Text(
                'Ongoing',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: Text(
                '${ongoing.length} record${ongoing.length == 1 ? '' : 's'}',
              ),
              childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              children: [
                _BillGroup(
                  bills: ongoing,
                  store: store,
                  onReorder: (oldIndex, newIndex) =>
                      _reorder(ongoing, oldIndex, newIndex),
                ),
              ],
            ),
          ),
        ],
        if (completed.isNotEmpty) ...[
          Card(
            margin: const EdgeInsets.only(bottom: 14),
            child: ExpansionTile(
              initiallyExpanded: true,
              shape: const RoundedRectangleBorder(side: BorderSide.none),
              collapsedShape: const RoundedRectangleBorder(
                side: BorderSide.none,
              ),
              leading: const CircleAvatar(
                backgroundColor: Color(0xFF8B7CF6),
                foregroundColor: Colors.white,
                child: Icon(Icons.check_rounded),
              ),
              title: const Text(
                'Completed',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: Text(
                '${completed.length} record${completed.length == 1 ? '' : 's'}',
              ),
              childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              children: [
                _BillGroup(
                  bills: completed,
                  store: store,
                  onReorder: (oldIndex, newIndex) =>
                      _reorder(completed, oldIndex, newIndex),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _BillGroup extends StatelessWidget {
  const _BillGroup({
    required this.bills,
    required this.store,
    required this.onReorder,
  });
  final List<Bill> bills;
  final AppStore store;
  final ReorderCallback onReorder;

  @override
  Widget build(BuildContext context) => ReorderableListView.builder(
    shrinkWrap: true,
    physics: const NeverScrollableScrollPhysics(),
    buildDefaultDragHandles: false,
    itemCount: bills.length,
    onReorderItem: onReorder,
    itemBuilder: (_, index) => BillTile(
      key: ValueKey(bills[index].id),
      bill: bills[index],
      store: store,
      index: index,
      showEditAction: true,
    ),
  );
}

class BillTile extends StatelessWidget {
  const BillTile({
    super.key,
    required this.bill,
    required this.store,
    this.index,
    this.showPayAction = false,
    this.showEditAction = false,
  });
  final Bill bill;
  final AppStore store;
  final int? index;
  final bool showPayAction;
  final bool showEditAction;
  @override
  Widget build(BuildContext context) => Dismissible(
    key: ValueKey(bill.id),
    direction: DismissDirection.endToStart,
    background: Container(
      margin: const EdgeInsets.symmetric(vertical: 5),
      padding: const EdgeInsets.only(right: 20),
      alignment: Alignment.centerRight,
      decoration: BoxDecoration(
        color: Colors.red.shade400,
        borderRadius: BorderRadius.circular(22),
      ),
      child: const Icon(Icons.delete_outline, color: Colors.white),
    ),
    confirmDismiss: (_) => confirmDelete(context, 'bill'),
    onDismissed: (_) => store.removeBill(bill),
    child: Card(
      margin: const EdgeInsets.symmetric(horizontal: 0, vertical: 5),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => BillDetailsPage(store: store, bill: bill),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: bill.type == 'recurring'
                    ? teal.withValues(alpha: .14)
                    : const Color(0xFFFF8D7A).withValues(alpha: .18),
                child: Icon(
                  bill.type == 'recurring'
                      ? Icons.autorenew_rounded
                      : Icons.payments_outlined,
                  color: bill.type == 'recurring'
                      ? teal
                      : const Color(0xFFE85D4A),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      bill.title,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      bill.type == 'fixed'
                          ? '${bill.paidMonths.length} of ${bill.totalInstallments} payments completed · due day ${bill.dueDay}'
                          : 'Monthly bill · due day ${bill.dueDay}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    Text(
                      'Started ${DateFormat('MMM yyyy').format(bill.startMonth)} · ${bill.paidMonths.length} payment${bill.paidMonths.length == 1 ? '' : 's'} recorded',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (bill.type != 'recurring') const SizedBox(height: 7),
                    if (bill.type != 'recurring')
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: LinearProgressIndicator(
                          minHeight: 6,
                          value: bill.totalInstallments == 0
                              ? 1
                              : 1 -
                                    bill.remainingInstallments /
                                        bill.totalInstallments,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    money(bill.amount),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  Text(
                    bill.type == 'fixed' ? 'per installment' : 'every month',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if (bill.type != 'recurring') ...[
                    const SizedBox(height: 4),
                    Text(
                      '${money(bill.amountLeft)} left',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: teal,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                  if (showPayAction) ...[
                    const SizedBox(height: 6),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                      ),
                      onPressed: () =>
                          payCurrentBillMonth(context, store, bill),
                      icon: const Icon(Icons.check_rounded, size: 17),
                      label: Text(bill.isPaidThisMonth ? 'Paid' : 'Pay'),
                    ),
                  ],
                  if (showEditAction) ...[
                    const SizedBox(height: 6),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 9),
                      ),
                      onPressed: () =>
                          showBillSheet(context, store, bill: bill),
                      icon: const Icon(Icons.edit_outlined, size: 16),
                      label: const Text('Edit'),
                    ),
                  ],
                  if (index != null)
                    ReorderableDragStartListener(
                      index: index!,
                      child: const Padding(
                        padding: EdgeInsets.only(top: 6),
                        child: Icon(Icons.drag_handle_rounded, size: 22),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class BillDetailsPage extends StatelessWidget {
  const BillDetailsPage({super.key, required this.store, required this.bill});
  final AppStore store;
  final Bill bill;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) {
      final now = DateTime.now();
      final months = bill.type == 'recurring'
          ? [
              DateTime(now.year, now.month - 1),
              DateTime(now.year, now.month),
              DateTime(now.year, now.month + 1),
            ].where((month) => !month.isBefore(bill.startMonth)).toList()
          : List.generate(
              bill.totalInstallments,
              (index) =>
                  DateTime(bill.startMonth.year, bill.startMonth.month + index),
            );
      return Scaffold(
        appBar: AppBar(title: Text(bill.title)),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Theme.of(context).brightness == Brightness.light
                    ? const Color(0xFFE8F5F2)
                    : const Color(0xFF082A27),
                borderRadius: BorderRadius.circular(22),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 25,
                    backgroundColor: teal,
                    foregroundColor: Colors.white,
                    child: Icon(
                      bill.type == 'fixed'
                          ? Icons.payments_outlined
                          : Icons.autorenew_rounded,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          money(bill.amount),
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                        Text(
                          bill.type == 'recurring'
                              ? 'Renews monthly · due day ${bill.dueDay}'
                              : '${money(bill.amountLeft)} remaining balance',
                        ),
                      ],
                    ),
                  ),
                  Chip(
                    label: Text(
                      bill.type == 'recurring'
                          ? 'Recurring'
                          : bill.isCompleted
                          ? 'Completed'
                          : 'Ongoing',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Text(
              bill.type == 'recurring'
                  ? 'Previous, current & next month'
                  : 'Payment schedule',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            ...months.map((month) {
              final key = DateFormat('yyyy-MM').format(month);
              final isPaid = bill.paidMonths.contains(key);
              final dueDate = DateTime(month.year, month.month, bill.dueDay);
              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: CheckboxListTile(
                  value: isPaid,
                  onChanged: (value) =>
                      store.setBillMonthPaid(bill, month, value ?? false),
                  secondary: CircleAvatar(
                    backgroundColor: isPaid
                        ? teal.withValues(alpha: .16)
                        : Theme.of(context).colorScheme.surfaceContainerHighest,
                    child: Text(DateFormat('MMM').format(month)),
                  ),
                  title: Text(
                    DateFormat('MMMM yyyy').format(month),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(
                    isPaid
                        ? 'Paid'
                        : 'Due ${DateFormat('MMMM d, yyyy').format(dueDate)}',
                  ),
                ),
              );
            }),
          ],
        ),
      );
    },
  );
}

class SavingsPage extends StatelessWidget {
  const SavingsPage({super.key, required this.store});
  final AppStore store;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      PageHeader('Savings goals', '${money(store.totalSavings)} tucked away'),
      Expanded(
        child: store.savings.isEmpty
            ? const Center(
                child: EmptyState(
                  icon: Icons.savings_outlined,
                  title: 'Start a happy stash',
                  body: 'Create a goal and watch every contribution add up.',
                ),
              )
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 90),
                itemCount: store.savings.length,
                itemBuilder: (_, i) {
                  final goal = store.savings[i];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: GlassPanel(
                      child: InkWell(
                        onTap: () =>
                            showSavingSheet(context, store, goal: goal),
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const CircleAvatar(
                                    child: Icon(Icons.rocket_launch_outlined),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      goal.title,
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                  Text('${(goal.progress * 100).round()}%'),
                                  PopupMenuButton<String>(
                                    tooltip: 'Savings actions',
                                    onSelected: (action) async {
                                      if (action == 'edit') {
                                        showSavingSheet(
                                          context,
                                          store,
                                          goal: goal,
                                        );
                                      } else if (action == 'delete') {
                                        if (await confirmDelete(
                                          context,
                                          'savings goal',
                                        )) {
                                          store.removeSaving(goal);
                                        }
                                      }
                                    },
                                    itemBuilder: (_) => const [
                                      PopupMenuItem(
                                        value: 'edit',
                                        child: ListTile(
                                          contentPadding: EdgeInsets.zero,
                                          leading: Icon(Icons.edit_outlined),
                                          title: Text('Edit goal'),
                                        ),
                                      ),
                                      PopupMenuItem(
                                        value: 'delete',
                                        child: ListTile(
                                          contentPadding: EdgeInsets.zero,
                                          leading: Icon(Icons.delete_outline),
                                          title: Text('Delete goal'),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              const SizedBox(height: 18),
                              TweenAnimationBuilder<double>(
                                tween: Tween(end: goal.progress),
                                duration: const Duration(milliseconds: 600),
                                builder: (_, value, _) =>
                                    LinearProgressIndicator(
                                      value: value,
                                      minHeight: 10,
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                '${money(goal.saved)} saved · ${money(goal.remaining)} to go',
                              ),
                              const SizedBox(height: 14),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: FilledButton.icon(
                                  onPressed: () => showAddSavingsDialog(
                                    context,
                                    store,
                                    goal,
                                  ),
                                  icon: const Icon(Icons.add_rounded, size: 18),
                                  label: const Text('Add savings'),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
      ),
    ],
  );
}

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.store});
  final AppStore store;
  @override
  Widget build(BuildContext context) => ListView(
    children: [
      const PageHeader('More', ''),
      const SectionTitle('Money settings', ''),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Card(
          child: Column(
            children: [
              ListTile(
                contentPadding: const EdgeInsets.all(16),
                leading: const CircleAvatar(
                  child: Icon(Icons.account_balance_wallet_outlined),
                ),
                title: const Text('Monthly allowance'),
                subtitle: Text(money(store.monthlyBudget)),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => showBudgetDialog(context, store),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.all(16),
                child: DropdownButtonFormField<String>(
                  initialValue: store.currencyCode,
                  decoration: const InputDecoration(
                    labelText: 'Currency',
                    prefixIcon: Icon(Icons.currency_exchange_rounded),
                  ),
                  items: currencyOptions.entries
                      .map(
                        (entry) => DropdownMenuItem(
                          value: entry.key,
                          child: Text('${entry.key}  ${entry.value.symbol}'),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) store.setCurrency(value);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
      const SectionTitle('Appearance', ''),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Card(
          child: RadioGroup<ThemeMode>(
            groupValue: store.themeMode,
            onChanged: (v) => store.setTheme(v!),
            child: Column(
              children: ThemeMode.values
                  .map(
                    (mode) => RadioListTile<ThemeMode>(
                      value: mode,
                      title: Text(switch (mode) {
                        ThemeMode.system => 'Use device setting',
                        ThemeMode.light => 'Light',
                        ThemeMode.dark => 'Dark',
                      }),
                      secondary: Icon(switch (mode) {
                        ThemeMode.system => Icons.brightness_auto_outlined,
                        ThemeMode.light => Icons.light_mode_outlined,
                        ThemeMode.dark => Icons.dark_mode_outlined,
                      }),
                    ),
                  )
                  .toList(),
            ),
          ),
        ),
      ),
      const SectionTitle('App', ''),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Card(
          child: ListTile(
            contentPadding: const EdgeInsets.all(16),
            leading: const CircleAvatar(
              backgroundColor: coral,
              foregroundColor: Colors.white,
              child: Icon(Icons.system_update_rounded),
            ),
            title: const Text('Check for latest version'),
            subtitle: const Text(
              'Download and install the newest GitHub release.',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => showUpdateChecker(context),
          ),
        ),
      ),
      const SectionTitle('Privacy', ''),
      const Padding(
        padding: EdgeInsets.symmetric(horizontal: 20),
        child: Card(
          child: ListTile(
            contentPadding: EdgeInsets.all(16),
            leading: CircleAvatar(child: Icon(Icons.lock_outline)),
            title: Text('Offline only'),
            subtitle: Text('Your financial data never leaves this device.'),
          ),
        ),
      ),
      const SizedBox(height: 36),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
        child: Row(
          children: [
            Icon(
              Icons.route_rounded,
              size: 24,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 10),
            Text(
              'VLRDC',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    ],
  );
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
  });
  final IconData icon;
  final String title;
  final String body;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(40),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 60, color: teal),
        const SizedBox(height: 18),
        Text(
          title,
          style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Text(
          body,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    ),
  );
}

IconData categoryIcon(String category) => switch (category) {
  'Food' => Icons.restaurant_outlined,
  'Transport' => Icons.directions_car_outlined,
  'Shopping' => Icons.shopping_bag_outlined,
  'Health' => Icons.medical_services_outlined,
  _ => Icons.more_horiz,
};

Future<void> showExpenseSheet(
  BuildContext context,
  AppStore store, {
  Expense? expense,
}) async {
  final title = TextEditingController(text: expense?.title ?? '');
  final amount = TextEditingController(
    text: expense == null ? '' : expense.amount.toStringAsFixed(2),
  );
  String category = expense?.category ?? 'Food';
  DateTime date = expense?.date ?? DateTime.now();
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (context) => StatefulBuilder(
      builder: (context, setModalState) => Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          22,
          20,
          MediaQuery.viewInsetsOf(context).bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              expense == null ? 'Add expense' : 'Update expense',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: title,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'What did you buy?'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: amount,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Amount',
                prefixText: '₱ ',
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: category,
              decoration: const InputDecoration(labelText: 'Category'),
              items: [
                'Food',
                'Transport',
                'Shopping',
                'Health',
                'Other',
              ].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
              onChanged: (v) => setModalState(() => category = v!),
            ),
            const SizedBox(height: 12),
            InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () async {
                final selected = await showDatePicker(
                  context: context,
                  initialDate: date,
                  firstDate: DateTime(2000),
                  lastDate: DateTime.now(),
                );
                if (selected != null) setModalState(() => date = selected);
              },
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Date spent',
                  prefixIcon: Icon(Icons.calendar_today_outlined),
                ),
                child: Text(DateFormat('MMMM d, yyyy').format(date)),
              ),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () {
                final value = double.tryParse(amount.text);
                if (title.text.trim().isEmpty || value == null || value <= 0) {
                  return;
                }
                if (expense == null) {
                  store.addExpense(
                    Expense(
                      id: DateTime.now().millisecondsSinceEpoch,
                      title: title.text.trim(),
                      amount: value,
                      category: category,
                      date: date,
                    ),
                  );
                } else {
                  expense
                    ..title = title.text.trim()
                    ..amount = value
                    ..category = category
                    ..date = date;
                  store.updateExpense(expense);
                }
                Navigator.pop(context);
              },
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Text(
                  expense == null ? 'Save expense' : 'Update expense',
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

Future<void> showBillSheet(
  BuildContext context,
  AppStore store, {
  Bill? bill,
  String? initialType,
}) async {
  final title = TextEditingController(text: bill?.title ?? '');
  final amount = TextEditingController(
    text: bill == null ? '' : bill.amount.toStringAsFixed(2),
  );
  int day = bill?.dueDay ?? DateTime.now().day.clamp(1, 28);
  bool reminder = bill?.reminder ?? true;
  int installments = bill?.totalInstallments ?? 1;
  final installmentsInput = TextEditingController(text: '$installments');
  String billType = bill?.type ?? initialType ?? 'recurring';
  DateTime startMonth =
      bill?.startMonth ?? DateTime(DateTime.now().year, DateTime.now().month);
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (context) => StatefulBuilder(
      builder: (context, setModalState) => Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          22,
          20,
          MediaQuery.viewInsetsOf(context).bottom + 24,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                bill == null
                    ? billType == 'recurring'
                          ? 'Add recurring bill'
                          : 'Add installment plan'
                    : 'Update details',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: title,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Bill name'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: amount,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: billType == 'fixed'
                      ? 'Amount per installment'
                      : 'Monthly amount',
                  prefixText: '₱ ',
                ),
              ),
              const SizedBox(height: 12),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                    value: 'recurring',
                    icon: Icon(Icons.autorenew_rounded),
                    label: Text('Bill'),
                  ),
                  ButtonSegment(
                    value: 'fixed',
                    icon: Icon(Icons.payments_outlined),
                    label: Text('Installment'),
                  ),
                ],
                selected: {billType},
                onSelectionChanged: (value) => setModalState(() {
                  billType = value.first;
                  if (billType == 'recurring') {
                    installments = 1;
                    installmentsInput.text = '1';
                  }
                }),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                initialValue: day,
                decoration: const InputDecoration(
                  labelText: 'Due day each month',
                ),
                items: List.generate(
                  28,
                  (i) => DropdownMenuItem(
                    value: i + 1,
                    child: Text('Day ${i + 1}'),
                  ),
                ),
                onChanged: (v) => setModalState(() => day = v!),
              ),
              const SizedBox(height: 12),
              InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () async {
                  final selected = await showDatePicker(
                    context: context,
                    initialDate: startMonth,
                    firstDate: DateTime(2000),
                    lastDate: DateTime(2100),
                    helpText: 'Select starting month',
                  );
                  if (selected != null) {
                    setModalState(() {
                      startMonth = DateTime(selected.year, selected.month);
                    });
                  }
                },
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Starting month',
                    prefixIcon: Icon(Icons.calendar_month_outlined),
                  ),
                  child: Text(DateFormat('MMMM yyyy').format(startMonth)),
                ),
              ),
              const SizedBox(height: 12),
              if (billType == 'fixed')
                TextField(
                  controller: installmentsInput,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: 'Total installments',
                    helperText:
                        'Remaining payments are calculated from the schedule.',
                  ),
                  onChanged: (text) {
                    final value = int.tryParse(text);
                    if (value != null && value > 0) installments = value;
                  },
                ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Remind me on the due date'),
                value: reminder,
                onChanged: (v) => setModalState(() => reminder = v),
              ),
              const SizedBox(height: 10),
              FilledButton(
                onPressed: () {
                  final value = double.tryParse(amount.text);
                  if (billType == 'fixed') {
                    installments = int.tryParse(installmentsInput.text) ?? 0;
                  }
                  if (title.text.trim().isEmpty ||
                      value == null ||
                      value <= 0 ||
                      (billType == 'fixed' && installments < 1)) {
                    return;
                  }
                  final paidCount = bill?.paidMonths.length ?? 0;
                  final calculatedRemaining = billType == 'recurring'
                      ? 1
                      : (installments - paidCount).clamp(0, installments);
                  if (bill == null) {
                    store.addBill(
                      Bill(
                        id: DateTime.now().millisecondsSinceEpoch.remainder(
                          2147483647,
                        ),
                        title: title.text.trim(),
                        amount: value,
                        dueDay: day,
                        reminder: reminder,
                        totalInstallments: billType == 'recurring'
                            ? 1
                            : installments,
                        remainingInstallments: billType == 'recurring'
                            ? 1
                            : calculatedRemaining,
                        autoDeduct: true,
                        type: billType,
                        startMonth: startMonth,
                      ),
                    );
                  } else {
                    bill
                      ..title = title.text.trim()
                      ..amount = value
                      ..dueDay = day
                      ..reminder = reminder
                      ..totalInstallments = billType == 'recurring'
                          ? 1
                          : installments
                      ..remainingInstallments = billType == 'recurring'
                          ? 1
                          : calculatedRemaining
                      ..autoDeduct = true
                      ..type = billType
                      ..startMonth = startMonth;
                    store.updateBill(bill);
                  }
                  Navigator.pop(context);
                },
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Text(bill == null ? 'Save bill' : 'Update bill'),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

Future<void> showSavingSheet(
  BuildContext context,
  AppStore store, {
  SavingGoal? goal,
}) async {
  final title = TextEditingController(text: goal?.title ?? '');
  final target = TextEditingController(
    text: goal == null ? '' : goal.target.toStringAsFixed(2),
  );
  final saved = TextEditingController(
    text: goal == null ? '' : goal.saved.toStringAsFixed(2),
  );
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (context) => Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        22,
        20,
        MediaQuery.viewInsetsOf(context).bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            goal == null ? 'Create a savings goal' : 'Update savings',
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: title,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Goal name'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: target,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Target amount',
              prefixText: '₱ ',
            ),
          ),
          if (goal != null) ...[
            const SizedBox(height: 12),
            TextField(
              controller: saved,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Total saved',
                prefixText: '₱ ',
                helperText: 'Manually correct the accumulated total.',
              ),
            ),
          ],
          const SizedBox(height: 20),
          FilledButton(
            onPressed: () {
              final targetValue = double.tryParse(target.text);
              final savedValue = goal == null
                  ? 0.0
                  : double.tryParse(saved.text);
              if (title.text.trim().isEmpty ||
                  targetValue == null ||
                  targetValue <= 0 ||
                  savedValue == null ||
                  savedValue < 0) {
                return;
              }
              if (goal == null) {
                store.addSaving(
                  SavingGoal(
                    id: DateTime.now().millisecondsSinceEpoch,
                    title: title.text.trim(),
                    target: targetValue,
                    saved: 0,
                  ),
                );
              } else {
                goal
                  ..title = title.text.trim()
                  ..target = targetValue
                  ..saved = savedValue;
                store.updateSaving(goal);
              }
              Navigator.pop(context);
            },
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Text(goal == null ? 'Create goal' : 'Save changes'),
            ),
          ),
          if (goal != null)
            TextButton.icon(
              onPressed: () async {
                if (await confirmDelete(context, 'savings goal')) {
                  store.removeSaving(goal);
                  if (context.mounted) Navigator.pop(context);
                }
              },
              icon: const Icon(Icons.delete_outline),
              label: const Text('Delete goal'),
            ),
        ],
      ),
    ),
  );
}

Future<void> showAddSavingsDialog(
  BuildContext context,
  AppStore store,
  SavingGoal goal,
) async {
  final amount = TextEditingController();
  await showDialog(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text('Add to ${goal.title}'),
      content: TextField(
        controller: amount,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          labelText: 'Amount to add',
          prefixText: '₱ ',
          helperText: 'Currently saved: ${money(goal.saved)}',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final value = double.tryParse(amount.text);
            if (value == null || value <= 0) return;
            goal.saved += value;
            store.updateSaving(goal);
            Navigator.pop(dialogContext);
          },
          child: const Text('Add savings'),
        ),
      ],
    ),
  );
}

Future<void> showBudgetDialog(BuildContext context, AppStore store) async {
  final controller = TextEditingController(
    text: store.monthlyBudget.toStringAsFixed(0),
  );
  await showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Monthly budget'),
      content: TextField(
        controller: controller,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: const InputDecoration(prefixText: '₱ '),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final value = double.tryParse(controller.text);
            if (value != null && value > 0) store.setBudget(value);
            Navigator.pop(context);
          },
          child: const Text('Save'),
        ),
      ],
    ),
  );
}
