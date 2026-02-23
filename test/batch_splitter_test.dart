import 'package:flutter_test/flutter_test.dart';
import 'package:photomailer/core/batch_splitter_preview.dart';

void main() {
  test('creates one group when total size fits limit', () {
    final groups = splitSizesByLimit(<int>[5, 7, 8], 20);
    expect(groups.length, 1);
  });

  test('creates separate group for oversized file', () {
    final groups = splitSizesByLimit(<int>[5, 30, 4], 20);
    expect(groups.length, 3);
    expect(groups[1], <int>[30]);
  });

  test('throws when limit is invalid', () {
    expect(
      () => splitSizesByLimit(<int>[1, 2, 3], 0),
      throwsArgumentError,
    );
  });
}

