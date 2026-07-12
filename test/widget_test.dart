import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_trail/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('expense and bill totals are calculated', () {
    final store = AppStore()..monthlyBudget = 10000;
    store.expenses.add(
      Expense(
        id: 1,
        title: 'Lunch',
        amount: 250,
        category: 'Food',
        date: DateTime.now(),
      ),
    );
    store.bills.add(
      Bill(
        id: 2,
        title: 'Laptop',
        amount: 4000,
        dueDay: 1,
        totalInstallments: 3,
      ),
    );
    store.savings.add(
      SavingGoal(id: 3, title: 'Holiday', target: 10000, saved: 2500),
    );
    expect(store.monthExpenses, 250);
    expect(store.unpaidBills, 4000);
    expect(store.billsLeftTotal, 12000);
    expect(store.totalSavings, 2500);
    expect(store.remaining, 5750);
  });

  test('monthly payments combine active bills and installments', () {
    final now = DateTime.now();
    final store = AppStore();
    store.bills.addAll([
      Bill(
        id: 10,
        title: 'Internet',
        amount: 1500,
        dueDay: 10,
        type: 'recurring',
        startMonth: DateTime(now.year, now.month),
      ),
      Bill(
        id: 11,
        title: 'Phone',
        amount: 2000,
        dueDay: 15,
        totalInstallments: 6,
        startMonth: DateTime(now.year, now.month),
      ),
      Bill(
        id: 12,
        title: 'Future plan',
        amount: 3000,
        dueDay: 20,
        startMonth: DateTime(now.year, now.month + 1),
      ),
      Bill(
        id: 13,
        title: 'Completed plan',
        amount: 1000,
        dueDay: 5,
        totalInstallments: 1,
        remainingInstallments: 0,
        startMonth: DateTime(now.year, now.month - 1),
      ),
    ]);

    expect(store.monthlyPaymentTotal, 3500);
  });

  test('bill payments track months and cannot duplicate a month', () async {
    SharedPreferences.setMockInitialValues({});
    final store = AppStore();
    final bill = Bill(
      id: 4,
      title: 'Phone',
      amount: 1000,
      dueDay: 15,
      totalInstallments: 3,
      startMonth: DateTime(DateTime.now().year, DateTime.now().month),
    );
    store.bills.add(bill);

    await store.recordBillPayment(bill);
    await store.recordBillPayment(bill);

    expect(bill.paidMonths, hasLength(1));
    expect(bill.remainingInstallments, 2);
    expect(bill.isPaidThisMonth, isTrue);
  });

  test(
    'recurring bills accept payments across months without completing',
    () async {
      SharedPreferences.setMockInitialValues({});
      final store = AppStore();
      final now = DateTime.now();
      final bill = Bill(
        id: 5,
        title: 'Electricity',
        amount: 1800,
        dueDay: 20,
        type: 'recurring',
        startMonth: DateTime(now.year, now.month),
      );
      store.bills.add(bill);

      await store.setBillMonthPaid(bill, now, true);
      await store.setBillMonthPaid(
        bill,
        DateTime(now.year, now.month + 1),
        true,
      );

      expect(bill.paidMonths, hasLength(2));
      expect(bill.isCompleted, isFalse);
      expect(bill.remainingInstallments, 1);
    },
  );

  testWidgets('dashboard supports light and dark themes', (tester) async {
    final store = AppStore()
      ..themeMode = ThemeMode.dark
      ..hasSeenWelcome = true;
    await tester.pumpWidget(MoneyTracker(store: store));
    expect(find.text('Total savings'), findsOneWidget);
    expect(find.text('Overview'), findsOneWidget);
  });
}
