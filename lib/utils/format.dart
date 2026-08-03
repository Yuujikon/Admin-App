import 'package:intl/intl.dart';

final _peso = NumberFormat.currency(locale: 'fil_PH', symbol: '₱');
String formatPeso(double amount) => _peso.format(amount);

String formatDate(DateTime dt) => DateFormat('MMM d, y hh:mm a').format(dt);