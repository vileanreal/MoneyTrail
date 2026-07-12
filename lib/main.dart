import 'dart:convert';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

const teal = Color(0xFF00897B);

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
        : Colors.black,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    cardTheme: CardThemeData(
      elevation: brightness == Brightness.light ? 1 : 0,
      color: brightness == Brightness.light
          ? Colors.white
          : const Color(0xFF0B0B0B),
      shadowColor: const Color(0xFF6D67A8).withValues(alpha: .12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
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
  double get remaining => monthlyBudget - monthExpenses - unpaidBills;

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    monthlyBudget = p.getDouble('budget') ?? 30000;
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

String money(double value) =>
    NumberFormat.currency(symbol: '₱', decimalDigits: 2).format(value);

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
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
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
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              Expanded(
                child: MetricCard(
                  icon: Icons.shopping_bag_outlined,
                  label: 'Spent',
                  value: money(store.monthExpenses),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: MetricCard(
                  icon: Icons.account_balance_wallet_outlined,
                  label: 'Available',
                  value: money(store.remaining),
                ),
              ),
            ],
          ),
        ),
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
                    : const Color(0xFF0B0B0B)
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

class MetricCard extends StatelessWidget {
  const MetricCard({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
  });
  final IconData icon;
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: teal),
          const SizedBox(height: 18),
          Text(
            label,
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

class ExpensesPage extends StatelessWidget {
  const ExpensesPage({super.key, required this.store});
  final AppStore store;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      const PageHeader('Expenses', 'Everything you spend, in one place'),
      Expanded(
        child: store.expenses.isEmpty
            ? const Center(
                child: EmptyState(
                  icon: Icons.receipt_long_outlined,
                  title: 'No expenses yet',
                  body: 'Tap “Expense” to record your first purchase.',
                ),
              )
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 90),
                itemCount: store.expenses.length,
                itemBuilder: (_, i) =>
                    ExpenseTile(expense: store.expenses[i], store: store),
              ),
      ),
    ],
  );
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
          const SectionTitle('Ongoing', ''),
          _BillGroup(
            bills: ongoing,
            store: store,
            onReorder: (oldIndex, newIndex) =>
                _reorder(ongoing, oldIndex, newIndex),
          ),
        ],
        if (completed.isNotEmpty) ...[
          const SectionTitle('Completed', ''),
          _BillGroup(
            bills: completed,
            store: store,
            onReorder: (oldIndex, newIndex) =>
                _reorder(completed, oldIndex, newIndex),
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
                          ? '${bill.remainingInstallments} of ${bill.totalInstallments} installments left · due day ${bill.dueDay}'
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
      final monthsSinceStart =
          (now.year - bill.startMonth.year) * 12 +
          now.month -
          bill.startMonth.month;
      final scheduleLength = bill.type == 'recurring'
          ? (monthsSinceStart + 13 > 12 ? monthsSinceStart + 13 : 12)
          : bill.totalInstallments;
      final months = List.generate(
        scheduleLength,
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
                              ? '${bill.paidMonths.length} months paid · renews monthly'
                              : '${bill.paidMonths.length} paid · ${bill.remainingInstallments} remaining',
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
              'Payment schedule',
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
      const PageHeader('More', 'Make MoneyTrail feel like yours'),
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
              'Victor Leandro R. Dela Cruz',
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
  int remaining = bill?.remainingInstallments ?? 1;
  final installmentsInput = TextEditingController(text: '$installments');
  final remainingInput = TextEditingController(text: '$remaining');
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
                    remaining = 1;
                    installmentsInput.text = '1';
                    remainingInput.text = '1';
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
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: installmentsInput,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        decoration: const InputDecoration(
                          labelText: 'Total installments',
                        ),
                        onChanged: (text) {
                          final value = int.tryParse(text);
                          if (value == null || value < 1) return;
                          installments = value;
                          if (remaining > installments) {
                            remaining = installments;
                            remainingInput.text = '$remaining';
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: remainingInput,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        decoration: const InputDecoration(
                          labelText: 'Months left',
                        ),
                        onChanged: (text) {
                          final value = int.tryParse(text);
                          if (value == null || value < 0) return;
                          remaining = value;
                        },
                      ),
                    ),
                  ],
                ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Remind me on the due date'),
                value: reminder,
                onChanged: (v) => setModalState(() => reminder = v),
              ),
              if (bill != null && bill.paidMonths.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  'Paid months',
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: bill.paidMonths.map((month) {
                    final date = DateTime.parse('$month-01');
                    return Chip(
                      label: Text(DateFormat('MMM yyyy').format(date)),
                    );
                  }).toList(),
                ),
              ],
              const SizedBox(height: 10),
              FilledButton(
                onPressed: () {
                  final value = double.tryParse(amount.text);
                  if (billType == 'fixed') {
                    installments = int.tryParse(installmentsInput.text) ?? 0;
                    remaining = int.tryParse(remainingInput.text) ?? -1;
                  }
                  if (title.text.trim().isEmpty ||
                      value == null ||
                      value <= 0 ||
                      (billType == 'fixed' &&
                          (installments < 1 ||
                              remaining < 0 ||
                              remaining > installments))) {
                    return;
                  }
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
                            : remaining,
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
                          : remaining
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
