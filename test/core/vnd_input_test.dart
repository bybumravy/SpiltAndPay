import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:splitpay/core/money.dart';

void main() {
  final formatter = VndInputFormatter();
  test('formats and parses whole VND amounts', () {
    final value = formatter.formatEditUpdate(
      TextEditingValue.empty,
      const TextEditingValue(
        text: '1200000',
        selection: TextSelection.collapsed(offset: 7),
      ),
    );
    expect(value.text, '1.200.000');
    expect(parseVndInput(value.text), 1200000);
    expect(value.selection.baseOffset, 9);
  });
  test('keeps cursor position when inserting inside an amount', () {
    final value = formatter.formatEditUpdate(
      const TextEditingValue(text: '12.000'),
      const TextEditingValue(
        text: '123.000',
        selection: TextSelection.collapsed(offset: 3),
      ),
    );
    expect(value.text, '123.000');
    expect(value.selection.baseOffset, 4);
  });
  test('clearing an amount leaves an empty field', () {
    expect(
      formatter
          .formatEditUpdate(
            const TextEditingValue(text: '1.000'),
            TextEditingValue.empty,
          )
          .text,
      '',
    );
    expect(parseVndInput(''), isNull);
  });
}
