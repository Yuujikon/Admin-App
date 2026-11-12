import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('environment variables load and parse successfully', () {
    final envFile = File('assets/.env');
    expect(envFile.existsSync(), isTrue, reason: 'assets/.env file should exist');

    final content = envFile.readAsStringSync();
    dotenv.testLoad(fileInput: content);

    expect(dotenv.env['BREVO_API_KEY'], isNotNull);
    expect(dotenv.env['BREVO_API_KEY'], isNotEmpty);
    expect(dotenv.env['BREVO_SENDER_EMAIL'], equals('gdcstore.ph@gmail.com'));
    expect(dotenv.env['TRACCAR_GATEWAY_URL'], contains('ngrok'));
    expect(dotenv.env['TRACCAR_TOKEN'], isNotEmpty);
    expect(dotenv.env['STORE_GCASH_NUMBER'], equals('09558297358'));
  });
}
