import 'package:flutter_test/flutter_test.dart';

import 'package:labflow/features/laboratory/data/laboratory_service.dart';

void main() {
  group('laboratory code validation', () {
    test('accepts normalized standard code', () {
      expect(LaboratoryService.validateCode(' LAB-IOT-01 '), isNull);
    });

    for (final value in [
      'M',
      'LAB',
      'IOT-01',
      'LAB-IOT',
      'LAB-IOT-1',
      'LAB IOT 01',
      '',
    ]) {
      test('rejects $value', () {
        expect(LaboratoryService.validateCode(value), isNotNull);
      });
    }
  });

  group('laboratory name validation', () {
    test('accepts normal names', () {
      expect(LaboratoryService.validateName('Lab IoT'), isNull);
      expect(LaboratoryService.validateName('Laboratorium Komputer'), isNull);
    });

    for (final value in ['M', 'AB', '', '   ', '!!!']) {
      test('rejects $value', () {
        expect(LaboratoryService.validateName(value), isNotNull);
      });
    }
  });
}
