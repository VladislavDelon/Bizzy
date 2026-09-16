import 'package:flutter/foundation.dart';

/// Валюта отображения цен. Хранится в SharedPreferences
/// ('bizzy_currency'), выбор — в «Настройках».
enum Currency {
  kzt('₸', 'Тенге (KZT)'),
  rub('₽', 'Рубли (RUB)'),
  usd(r'$', 'Доллары (USD)'),
  eur('€', 'Евро (EUR)');

  final String symbol;
  final String label;

  const Currency(this.symbol, this.label);

  static Currency fromString(String? value) {
    return Currency.values.firstWhere(
      (c) => c.name == value,
      orElse: () => Currency.kzt,
    );
  }
}

/// Текущая валюта приложения.
final ValueNotifier<Currency> appCurrency = ValueNotifier(Currency.kzt);

/// «2000 ₸» — сумма с текущим символом валюты.
String formatMoney(double amount) =>
    '${amount.toStringAsFixed(0)} ${appCurrency.value.symbol}';
