import 'package:dox_orm/dox_orm.dart';

import 'shared_mixin.dart';

mixin Limit<T> implements SharedMixin<T> {
  int? _limit;
  int? _offset;

  /// the row lock of a select, see lockForUpdate() and sharedLock()
  _Lock? _lock;

  /// true when lockForUpdate() or sharedLock() was called
  bool get hasLock => _lock != null;

  /// the lock part that goes at the very end of a select, after LIMIT
  /// and OFFSET. it is empty on sqlite, which has no row locks.
  String getLockQuery() {
    _Lock? lock = _lock;
    if (lock == null) return '';
    switch (dbDriver.getName()) {
      case Driver.postgres:
        return lock == _Lock.update ? ' FOR UPDATE' : ' FOR SHARE';

      /// `LOCK IN SHARE MODE` works on mariadb and on mysql 8.4.
      /// mariadb does not know `FOR SHARE`.
      case Driver.mysql:
        return lock == _Lock.update ? ' FOR UPDATE' : ' LOCK IN SHARE MODE';

      /// sqlite has no row locks. our sqlite transactions start with
      /// `BEGIN IMMEDIATE`, which takes the write lock of the whole
      /// database, so other transactions wait anyway.
      case Driver.sqlite:
        return '';
    }
  }

  /// param names of the LIMIT and OFFSET values. they are params, so
  /// every page gives the same sql and the drivers reuse one statement.
  static const String limitKey = 'dox_limit';
  static const String offsetKey = 'dox_offset';

  /// only the parts that were set. `OFFSET 0` is left out.
  String getLimitQuery() {
    int? offset = _offset == 0 ? null : _offset;
    if (_limit == null && _offset == null) return "";
    Map<String, dynamic> values = substitutionValues;
    if (_limit != null) {
      values[limitKey] = _limit;
    } else {
      values.remove(limitKey);
    }
    if (offset != null) {
      values[offsetKey] = offset;
    } else {
      values.remove(offsetKey);
    }
    if (_limit != null) {
      return offset == null
          ? " LIMIT @$limitKey"
          : " LIMIT @$limitKey OFFSET @$offsetKey";
    }
    if (offset == null) {
      return "";
    }

    /// OFFSET without LIMIT: mysql and sqlite need a LIMIT
    switch (dbDriver.getName()) {
      case Driver.mysql:
        return " LIMIT 18446744073709551615 OFFSET @$offsetKey";
      case Driver.sqlite:
        return " LIMIT -1 OFFSET @$offsetKey";
      case Driver.postgres:
        return " OFFSET @$offsetKey";
    }
  }

  /// limit query
  ///
  /// ```
  /// List blogs = await Blog().take(10).get()
  /// ```
  QueryBuilder<T> take(int value) {
    _limit = value;
    return queryBuilder;
  }

  /// limit query
  ///
  /// ```
  /// List blogs = await Blog().limit(10).get()
  /// ```
  QueryBuilder<T> limit(int value) {
    _limit = value;
    return queryBuilder;
  }

  /// lock the selected rows for update (`FOR UPDATE`). other
  /// transactions that lock or change these rows wait until this
  /// transaction ends. use it with find(), get(), getFirst(),
  /// firstOrFail() and findOrFail().
  ///
  /// the lock only lasts inside QueryBuilder.transaction(). outside a
  /// transaction the query commits right away, so the lock ends at once.
  /// sqlite has no row locks: it is a no-op there, but our sqlite
  /// transactions use `BEGIN IMMEDIATE`, which locks the whole database
  /// for writes, so the same code is still safe.
  /// count() and the other aggregates do not lock.
  ///
  /// ```
  /// await QueryBuilder.transaction(() async {
  ///   Account? account = await Account().lockForUpdate().find(1);
  ///   account!.balance = account.balance! - 10;
  ///   await account.save();
  /// });
  /// ```
  /// ponytail: postgres does not allow a lock with groupBy(), distinct()
  /// or on the nullable side of a left join. the database throws then.
  QueryBuilder<T> lockForUpdate() {
    _lock = _Lock.update;
    return queryBuilder;
  }

  /// lock the selected rows with a shared lock: other transactions can
  /// read them, but they wait to change them until this transaction ends.
  /// it is `FOR SHARE` on postgres and `LOCK IN SHARE MODE` on mysql and
  /// mariadb. like lockForUpdate(), it only lasts inside
  /// QueryBuilder.transaction(), and it is a no-op on sqlite.
  ///
  /// ```
  /// await QueryBuilder.transaction(() async {
  ///   User? user = await User().sharedLock().find(1);
  ///   await Order().create(<String, dynamic>{'user_id': user!.id});
  /// });
  /// ```
  QueryBuilder<T> sharedLock() {
    _lock = _Lock.share;
    return queryBuilder;
  }

  /// offset limit
  ///
  /// ```
  /// List blogs = await Blog().limit(10).offset(10).get()
  /// ```
  QueryBuilder<T> offset(int value) {
    _offset = value;
    return queryBuilder;
  }
}

/// the kinds of row lock
enum _Lock { update, share }
