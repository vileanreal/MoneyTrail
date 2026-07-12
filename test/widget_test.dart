import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_trail/main.dart';

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

  testWidgets('dashboard supports light and dark themes', (tester) async {
    final store = AppStore()
      ..themeMode = ThemeMode.dark
      ..hasSeenWelcome = true;
    await tester.pumpWidget(MoneyTracker(store: store));
    expect(find.text('Total savings'), findsOneWidget);
    expect(find.text('Overview'), findsOneWidget);
  });
}
