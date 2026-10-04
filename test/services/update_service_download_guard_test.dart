import 'package:flutter_test/flutter_test.dart';
import 'package:proxly/services/update_service.dart';

void main() {
  test('APK size guard rejects an oversized Content-Length', () {
    final guard = ApkDownloadSizeGuard(maxBytes: 10);

    expect(() => guard.validateContentLength(11), throwsException);
    expect(guard.receivedBytes, 0);
  });

  test('APK size guard rejects chunked responses after the cumulative limit',
      () {
    final guard = ApkDownloadSizeGuard(maxBytes: 10);

    guard.validateContentLength(null);
    guard.addChunk(6);
    expect(guard.receivedBytes, 6);
    expect(() => guard.addChunk(5), throwsException);
    expect(guard.receivedBytes, 11);
  });

  test('APK size guard accepts a response exactly at the limit', () {
    final guard = ApkDownloadSizeGuard(maxBytes: 10);

    guard.validateContentLength(10);
    guard.addChunk(4);
    guard.addChunk(6);
    expect(guard.receivedBytes, 10);
  });
}
