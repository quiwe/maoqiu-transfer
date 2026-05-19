import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/transfer_task.dart';

class HistoryService {
  static const _historyKey = 'transfer_history';

  SharedPreferences? _prefs;
  final List<TransferHistoryRecord> _records = [];

  List<TransferHistoryRecord> get records => List.unmodifiable(_records);

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    final raw = _prefs?.getString(_historyKey);
    if (raw == null || raw.isEmpty) {
      return;
    }

    final decoded = jsonDecode(raw);
    if (decoded is! List) {
      return;
    }

    _records
      ..clear()
      ..addAll(
        decoded
            .whereType<Map>()
            .map((item) => TransferHistoryRecord.fromJson(Map<String, dynamic>.from(item))),
      );
  }

  Future<void> addRecords(Iterable<TransferHistoryRecord> records) async {
    _records.insertAll(0, records);
    if (_records.length > 200) {
      _records.removeRange(200, _records.length);
    }
    await _persist();
  }

  Future<void> clear() async {
    _records.clear();
    await _persist();
  }

  Future<void> _persist() async {
    final encoded = jsonEncode(_records.map((item) => item.toJson()).toList());
    await _prefs?.setString(_historyKey, encoded);
  }
}
