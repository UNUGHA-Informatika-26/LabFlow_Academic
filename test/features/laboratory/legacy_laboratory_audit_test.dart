import 'package:flutter_test/flutter_test.dart';
import 'package:labflow/features/laboratory/data/laboratory_service.dart';

import '../../helpers/fake_firestore.dart';

void main() {
  late FakeMemoryFirestore firestore;
  late LaboratoryService labService;

  setUp(() {
    firestore = FakeMemoryFirestore();
    labService = LaboratoryService(firestore: firestore);
  });

  group('Task D — Legacy Laboratory Data Compatibility Audit', () {
    test('Reads legacy laboratory documents with missing timestamps, legacy code, short name, and extra fields without crashing', () async {
      firestore.seedDoc('laboratories', 'legacy-lab-1', {
        'name': 'M', // short legacy name (< 3 chars)
        'code': 'IOT', // legacy code not matching ^LAB-[A-Z0-9]+-[0-9]{2}$
        'description': 'Lab lama dari versi 1',
        'location': '', // empty legacy location
        'status': 'active',
        'legacyCapacity': 40, // extra field not in current model
        'headOfLab': 'Dr. Budi', // extra field
        // createdAt and updatedAt missing
      });

      final lab = await labService.getLaboratory('legacy-lab-1');
      expect(lab.id, 'legacy-lab-1');
      expect(lab.name, 'M');
      expect(lab.code, 'IOT');
      expect(lab.location, '');
      expect(lab.status, 'active');
      expect(lab.updatedAt, isNull);
    });

    test('Allows updating unrelated fields (e.g. status or location) on a legacy document while preserving unchanged legacy code/name', () async {
      firestore.seedDoc('laboratories', 'legacy-lab-1', {
        'name': 'M',
        'code': 'LAB-01', // legacy code format
        'description': 'Deskripsi lama',
        'location': 'Gedung Lama',
        'status': 'active',
        'extraLegacyField': 'tetap-aman',
      });

      final update = await labService.updateLaboratory(
        laboratoryId: 'legacy-lab-1',
        name: 'M', // unchanged legacy name
        code: 'LAB-01', // unchanged legacy code
        description: 'Deskripsi diperbarui',
        location: 'Gedung FMIKOM Lantai 2',
        status: 'inactive',
      );

      expect(
        update.keys.toSet(),
        {'description', 'location', 'status', 'updatedAt'},
      );
      final stored = firestore.peekDoc('laboratories', 'legacy-lab-1')!;
      expect(stored['code'], 'LAB-01');
      expect(stored['status'], 'inactive');
      expect(stored['location'], 'Gedung FMIKOM Lantai 2');
      expect(stored['extraLegacyField'], 'tetap-aman');
    });

    test('Rejects modifying a legacy field to a new invalid value', () async {
      firestore.seedDoc('laboratories', 'legacy-lab-1', {
        'name': 'Laboratorium Lama',
        'code': 'IOT-LAMA',
        'description': 'Deskripsi',
        'location': 'Gedung A',
        'status': 'active',
      });

      // Changing legacy code 'IOT-LAMA' to another invalid code 'INVALID-999' must be rejected:
      await expectLater(
        () => labService.updateLaboratory(
          laboratoryId: 'legacy-lab-1',
          name: 'Laboratorium Lama',
          code: 'INVALID-999',
          description: 'Deskripsi',
          location: 'Gedung A',
          status: 'active',
        ),
        throwsA(isA<LaboratoryException>()),
      );

      // Changing legacy code 'IOT-LAMA' to a valid standard code 'LAB-IOT-01' succeeds:
      await labService.updateLaboratory(
        laboratoryId: 'legacy-lab-1',
        name: 'Laboratorium Lama',
        code: 'LAB-IOT-01',
        description: 'Deskripsi',
        location: 'Gedung A',
        status: 'active',
      );
      expect(
        firestore.peekDoc('laboratories', 'legacy-lab-1')!['code'],
        'LAB-IOT-01',
      );
    });

    test('New laboratory creation strictly enforces all current validation rules', () async {
      await expectLater(
        () => labService.createLaboratory(
          name: 'AB',
          code: 'LAB-IOT-01',
          description: '',
          location: 'Gedung A',
          status: 'active',
        ),
        throwsA(isA<LaboratoryException>()),
      );

      await expectLater(
        () => labService.createLaboratory(
          name: 'Laboratorium IoT',
          code: 'IOT-01',
          description: '',
          location: 'Gedung A',
          status: 'active',
        ),
        throwsA(isA<LaboratoryException>()),
      );

      await expectLater(
        () => labService.createLaboratory(
          name: 'Laboratorium IoT',
          code: 'LAB-IOT-01',
          description: '',
          location: '   ',
          status: 'active',
        ),
        throwsA(isA<LaboratoryException>()),
      );
    });
  });
}
