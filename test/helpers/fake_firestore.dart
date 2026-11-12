// ignore_for_file: subtype_of_sealed_class

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:mocktail/mocktail.dart';

class RecordedWriteOperation {
  const RecordedWriteOperation({
    required this.type,
    required this.collection,
    required this.docId,
    required this.payload,
  });

  final String type; // 'set' | 'update' | 'delete'
  final String collection;
  final String docId;
  final Map<String, Object?> payload;
}

/// In-memory fake implementation of [FirebaseFirestore] for verifying
/// exact write counts, payloads, timestamps, and transactions in unit tests.
class FakeMemoryFirestore extends Fake implements FirebaseFirestore {
  FakeMemoryFirestore({DateTime Function()? clock})
    : _clock = clock ?? (() => DateTime.now().toUtc());

  final DateTime Function() _clock;
  final Map<String, Map<String, Map<String, dynamic>>> _store =
      <String, Map<String, Map<String, dynamic>>>{};
  final List<RecordedWriteOperation> writes = <RecordedWriteOperation>[];
  int _autoIdCounter = 0;

  Object? failWritesWithError;
  void Function(int attempt)? onTransactionAttempt;
  Future<void> Function(String collection, String docId)? onBeforeDocGet;

  int get totalWriteCount => writes.length;

  int writeCountForCollection(String collection) =>
      writes.where((op) => op.collection == collection).length;

  List<RecordedWriteOperation> writesFor(String collection, [String? docId]) =>
      writes
          .where(
            (op) =>
                op.collection == collection &&
                (docId == null || op.docId == docId),
          )
          .toList();

  void seedDoc(String collection, String docId, Map<String, dynamic> data) {
    final col = _store.putIfAbsent(
      collection,
      () => <String, Map<String, dynamic>>{},
    );
    col[docId] = Map<String, dynamic>.from(data);
  }

  Map<String, dynamic>? peekDoc(String collection, String docId) {
    final doc = _store[collection]?[docId];
    return doc == null ? null : Map<String, dynamic>.from(doc);
  }

  Map<String, dynamic> _resolveValues(Map<String, Object?> input) {
    final resolved = <String, dynamic>{};
    for (final entry in input.entries) {
      final val = entry.value;
      if (val is FieldValue) {
        final str = val.toString();
        if (str.contains('delete')) {
          resolved[entry.key] = _DeletedFieldMarker.instance;
        } else {
          resolved[entry.key] = Timestamp.fromDate(_clock());
        }
      } else {
        resolved[entry.key] = val;
      }
    }
    return resolved;
  }

  void _applySet(
    String collection,
    String docId,
    Map<String, Object?> payload,
  ) {
    if (failWritesWithError != null) {
      throw failWritesWithError!;
    }
    writes.add(
      RecordedWriteOperation(
        type: 'set',
        collection: collection,
        docId: docId,
        payload: Map<String, Object?>.unmodifiable(payload),
      ),
    );
    final col = _store.putIfAbsent(
      collection,
      () => <String, Map<String, dynamic>>{},
    );
    final resolved = _resolveValues(payload);
    resolved.removeWhere((_, v) => v is _DeletedFieldMarker);
    col[docId] = resolved;
  }

  void _applyUpdate(
    String collection,
    String docId,
    Map<String, Object?> payload,
  ) {
    if (failWritesWithError != null) {
      throw failWritesWithError!;
    }
    final col = _store[collection];
    final existing = col?[docId];
    if (existing == null) {
      throw FirebaseException(
        plugin: 'cloud_firestore',
        code: 'not-found',
        message: 'Document $collection/$docId not found.',
      );
    }
    writes.add(
      RecordedWriteOperation(
        type: 'update',
        collection: collection,
        docId: docId,
        payload: Map<String, Object?>.unmodifiable(payload),
      ),
    );
    final resolved = _resolveValues(payload);
    for (final entry in resolved.entries) {
      if (entry.value is _DeletedFieldMarker) {
        existing.remove(entry.key);
      } else {
        existing[entry.key] = entry.value;
      }
    }
  }

  void _applyDelete(String collection, String docId) {
    if (failWritesWithError != null) {
      throw failWritesWithError!;
    }
    writes.add(
      RecordedWriteOperation(
        type: 'delete',
        collection: collection,
        docId: docId,
        payload: const <String, Object?>{},
      ),
    );
    _store[collection]?.remove(docId);
  }

  String _nextAutoId(String collection) {
    _autoIdCounter += 1;
    return 'auto_${collection}_$_autoIdCounter';
  }

  @override
  CollectionReference<Map<String, dynamic>> collection(String collectionPath) {
    return _FakeCollectionReference(this, collectionPath);
  }

  @override
  Future<T> runTransaction<T>(
    TransactionHandler<T> transactionHandler, {
    Duration timeout = const Duration(seconds: 30),
    int maxAttempts = 5,
  }) async {
    Object? lastError;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      onTransactionAttempt?.call(attempt);
      final tx = _FakeTransaction(this);
      try {
        final result = await transactionHandler(tx);
        tx.commit();
        return result;
      } on FirebaseException catch (e) {
        lastError = e;
        if (e.code == 'aborted' && attempt < maxAttempts) {
          continue;
        }
        rethrow;
      }
    }
    throw lastError!;
  }
}

class _DeletedFieldMarker {
  const _DeletedFieldMarker._();
  static const _DeletedFieldMarker instance = _DeletedFieldMarker._();
}

class _FakeCollectionReference extends Fake
    implements CollectionReference<Map<String, dynamic>> {
  _FakeCollectionReference(this._db, this._collectionPath);

  final FakeMemoryFirestore _db;
  final String _collectionPath;

  @override
  DocumentReference<Map<String, dynamic>> doc([String? path]) {
    final docId = (path == null || path.isEmpty)
        ? _db._nextAutoId(_collectionPath)
        : path;
    return _FakeDocumentReference(_db, _collectionPath, docId);
  }

  @override
  Future<DocumentReference<Map<String, dynamic>>> add(
    Map<String, dynamic> data,
  ) async {
    final ref = doc();
    await ref.set(data);
    return ref;
  }

  @override
  Query<Map<String, dynamic>> where(
    Object field, {
    Object? isEqualTo,
    Object? isNotEqualTo,
    Object? isLessThan,
    Object? isLessThanOrEqualTo,
    Object? isGreaterThan,
    Object? isGreaterThanOrEqualTo,
    Object? arrayContains,
    Iterable<Object?>? arrayContainsAny,
    Iterable<Object?>? whereIn,
    Iterable<Object?>? whereNotIn,
    bool? isNull,
  }) {
    return _FakeQuery(_db, _collectionPath, <(String, Object?)>[
      (field.toString(), isEqualTo),
    ]);
  }


  @override
  Query<Map<String, dynamic>> orderBy(Object field, {bool descending = false}) {
    return _FakeQuery(_db, _collectionPath, const []).orderBy(field, descending: descending);
  }

  @override
  Future<QuerySnapshot<Map<String, dynamic>>> get([GetOptions? options]) async {
    return _FakeQuery(_db, _collectionPath, const []).get(options);
  }
}

class _FakeQuery extends Fake implements Query<Map<String, dynamic>> {
  _FakeQuery(this._db, this._collectionPath, this._filters, [this._limitCount]);

  final FakeMemoryFirestore _db;
  final String _collectionPath;
  final List<(String, Object?)> _filters;
  final int? _limitCount;

  @override
  Query<Map<String, dynamic>> where(
    Object field, {
    Object? isEqualTo,
    Object? isNotEqualTo,
    Object? isLessThan,
    Object? isLessThanOrEqualTo,
    Object? isGreaterThan,
    Object? isGreaterThanOrEqualTo,
    Object? arrayContains,
    Iterable<Object?>? arrayContainsAny,
    Iterable<Object?>? whereIn,
    Iterable<Object?>? whereNotIn,
    bool? isNull,
  }) {
    return _FakeQuery(
      _db,
      _collectionPath,
      <(String, Object?)>[..._filters, (field.toString(), isEqualTo)],
      _limitCount,
    );
  }

  @override
  Query<Map<String, dynamic>> limit(int limit) {
    return _FakeQuery(_db, _collectionPath, _filters, limit);
  }

  @override
  Query<Map<String, dynamic>> orderBy(Object field, {bool descending = false}) {
    return this;
  }

  @override
  Stream<QuerySnapshot<Map<String, dynamic>>> snapshots({
    bool includeMetadataChanges = false,
    ListenSource source = ListenSource.defaultSource,
  }) {
    return Stream.fromFuture(get());
  }

  @override
  Future<QuerySnapshot<Map<String, dynamic>>> get([GetOptions? options]) async {
    final col = _db._store[_collectionPath] ?? const {};
    final matching = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    for (final entry in col.entries) {
      final data = entry.value;
      var ok = true;
      for (final (field, expected) in _filters) {
        if (data[field] != expected) {
          ok = false;
          break;
        }
      }
      if (ok) {
        matching.add(
          _FakeQueryDocumentSnapshot(
            entry.key,
            Map<String, dynamic>.from(data),
          ),
        );
        if (_limitCount != null && matching.length >= _limitCount) {
          break;
        }
      }
    }
    return _FakeQuerySnapshot(matching);
  }
}

class _FakeDocumentReference extends Fake
    implements DocumentReference<Map<String, dynamic>> {
  _FakeDocumentReference(this._db, this._collectionPath, this.id);

  final FakeMemoryFirestore _db;
  final String _collectionPath;

  @override
  final String id;

  @override
  CollectionReference<Map<String, dynamic>> collection(String collectionPath) {
    return _FakeCollectionReference(_db, '$_collectionPath/$id/$collectionPath');
  }

  @override
  Future<DocumentSnapshot<Map<String, dynamic>>> get([
    GetOptions? options,
  ]) async {
    await _db.onBeforeDocGet?.call(_collectionPath, id);
    final data = _db.peekDoc(_collectionPath, id);
    return _FakeDocumentSnapshot(id, data);
  }

  @override
  Future<void> set(Map<String, dynamic> data, [SetOptions? options]) async {
    _db._applySet(_collectionPath, id, Map<String, Object?>.from(data));
  }

  @override
  Future<void> update(Map<Object, Object?> data) async {
    final mapped = <String, Object?>{};
    for (final entry in data.entries) {
      mapped[entry.key.toString()] = entry.value;
    }
    _db._applyUpdate(_collectionPath, id, mapped);
  }

  @override
  Future<void> delete() async {
    _db._applyDelete(_collectionPath, id);
  }
}

class _FakeDocumentSnapshot extends Fake
    implements DocumentSnapshot<Map<String, dynamic>> {
  _FakeDocumentSnapshot(this.id, this._data);

  @override
  final String id;
  final Map<String, dynamic>? _data;

  @override
  bool get exists => _data != null;

  @override
  Map<String, dynamic>? data() =>
      _data == null ? null : Map<String, dynamic>.from(_data);
}

class _FakeQueryDocumentSnapshot extends _FakeDocumentSnapshot
    implements QueryDocumentSnapshot<Map<String, dynamic>> {
  _FakeQueryDocumentSnapshot(super.id, Map<String, dynamic> super.data);

  @override
  Map<String, dynamic> data() => Map<String, dynamic>.from(_data!);
}

class _FakeQuerySnapshot extends Fake
    implements QuerySnapshot<Map<String, dynamic>> {
  _FakeQuerySnapshot(this.docs);

  @override
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;
}

class _FakeTransaction extends Fake implements Transaction {
  _FakeTransaction(this._db);

  final FakeMemoryFirestore _db;
  final List<void Function()> _stagedOperations = <void Function()>[];

  @override
  Future<DocumentSnapshot<T>> get<T extends Object?>(
    DocumentReference<T> documentReference,
  ) async {
    final snap = await documentReference.get();
    return snap;
  }

  @override
  Transaction update(
    DocumentReference<Object?> documentReference,
    Map<Object, Object?> data,
  ) {
    final ref = documentReference as _FakeDocumentReference;
    final mapped = <String, Object?>{};
    for (final entry in data.entries) {
      mapped[entry.key.toString()] = entry.value;
    }
    _stagedOperations.add(() {
      _db._applyUpdate(ref._collectionPath, ref.id, mapped);
    });
    return this;
  }

  @override
  Transaction set<T>(
    DocumentReference<T> documentReference,
    T data, [
    SetOptions? options,
  ]) {
    final ref = documentReference as _FakeDocumentReference;
    _stagedOperations.add(() {
      _db._applySet(
        ref._collectionPath,
        ref.id,
        Map<String, Object?>.from(data as Map),
      );
    });
    return this;
  }

  void commit() {
    for (final op in _stagedOperations) {
      op();
    }
  }
}
