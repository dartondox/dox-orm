import 'dart:convert';
import 'dart:io';

import 'package:dox_orm/dox_orm.dart';

// coverage:ignore-file
/// writes each query as one json line to [file].
///
/// the lines are kept in memory and written to the file in the background,
/// in order, so a query does not wait for the disk. call [flush] to wait
/// until every line is in the file, eg. before `exit()`.
class FileQueryPrinter implements QueryPrinter {
  Function(String)? filter;
  final File file;

  FileQueryPrinter({required this.file, this.filter});

  /// lines not written yet
  final StringBuffer _pending = StringBuffer();

  /// the last write. each write starts after the one before it.
  Future<void> _writing = Future<void>.value();

  bool _scheduled = false;
  bool _dirReady = false;

  @override
  void log(String query, List<String> params) {
    Map<String, dynamic> payload = <String, dynamic>{
      'timestamp': DateTime.now().toIso8601String(),
      'level': 'INFO',
      'message': query,
      'payload': <String, dynamic>{'query': query, 'params': params},
    };

    String stringToPrint = jsonEncode(payload);
    if (filter != null) {
      stringToPrint = filter!(stringToPrint);
    }

    _pending.writeln(stringToPrint);
    if (!_scheduled) {
      _scheduled = true;
      _writing = _writing.then(_write);
    }
  }

  /// wait until every logged line is in the file
  Future<void> flush() => _writing;

  /// write all pending lines in one append
  Future<void> _write(void _) async {
    _scheduled = false;
    String text = _pending.toString();
    _pending.clear();
    try {
      if (!_dirReady) {
        await file.parent.create(recursive: true);
        _dirReady = true;
      }
      await file.writeAsString(text, mode: FileMode.append, flush: true);
    } catch (e) {
      // ponytail: a log write must not crash the app, so print the error
      stderr.writeln('FileQueryPrinter: can not write ${file.path}: $e');
    }
  }
}
