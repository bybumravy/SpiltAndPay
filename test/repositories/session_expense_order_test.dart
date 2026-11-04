import 'package:flutter_test/flutter_test.dart';
import 'package:splitpay/models/expense.dart';
import 'package:splitpay/repositories/session_repository.dart';

void main() {
  test('sortExpensesBySequence preserves editor item order', () {
    final sorted = SessionRepository.sortExpensesBySequence([
      const Expense(
        expenseId: 'expense-2',
        description: 'Second',
        amount: 2,
        payerId: 'a',
        participantIds: ['a'],
        shares: {'a': 2},
        sequence: 2,
      ),
      const Expense(
        expenseId: 'expense-1',
        description: 'First',
        amount: 1,
        payerId: 'a',
        participantIds: ['a'],
        shares: {'a': 1},
        sequence: 1,
      ),
    ]);

    expect(sorted.map((expense) => expense.description), ['First', 'Second']);
  });
}
