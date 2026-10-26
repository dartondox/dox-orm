import 'drivers/db_driver.dart';
import 'query_builder.dart';
import 'shared_mixin.dart';

mixin OrderBy<T> implements SharedMixin<T> {
  /// made on the first orderBy(), most rows never need it
  List<String>? _orderBy;

  String getOrderByQuery() {
    List<String>? orderBy = _orderBy;
    if (orderBy != null) {
      return " ORDER BY ${orderBy.join(',')}";
    }
    return "";
  }

  /// order by query
  ///
  /// ```
  /// List blogs = await Blog().orderBy('id').get()
  /// List blogs = await Blog().orderBy('id', 'desc').get()
  /// ```
  QueryBuilder<T> orderBy(dynamic column, [dynamic type]) {
    /// only allow asc or desc, to block sql injection from user input
    if (type != null &&
        !<String>['asc', 'desc'].contains(type.toString().toLowerCase())) {
      throw ArgumentError.value(type, 'type', 'must be asc or desc');
    }
    String name = helper.wrap(column.toString());
    (_orderBy ??= <String>[]).add(type == null ? name : '$name $type');
    return queryBuilder;
  }

  /// order by raw query, nothing is quoted. never put user input in it.
  ///
  /// ```
  /// List blogs = await Blog().orderByRaw('count(*) desc').get()
  /// ```
  QueryBuilder<T> orderByRaw(String query) {
    (_orderBy ??= <String>[]).add(query);
    return queryBuilder;
  }

  /// newest first: order by [column] desc, `created_at` by default
  ///
  /// ```
  /// Blog? blog = await Blog().latest().getFirst();
  /// List<Blog> blogs = await Blog().latest('updated_at').get();
  /// ```
  QueryBuilder<T> latest([String column = 'created_at']) {
    return orderBy(column, 'desc');
  }

  /// oldest first: order by [column] asc, `created_at` by default
  ///
  /// ```
  /// Blog? blog = await Blog().oldest().getFirst();
  /// ```
  QueryBuilder<T> oldest([String column = 'created_at']) {
    return orderBy(column, 'asc');
  }

  /// random order, `RANDOM()` on postgres and sqlite, `RAND()` on mysql
  ///
  /// ```
  /// Blog? blog = await Blog().inRandomOrder().getFirst();
  /// ```
  /// ponytail: it sorts the whole table, slow on big tables
  QueryBuilder<T> inRandomOrder() {
    return orderByRaw(
      dbDriver.getName() == Driver.mysql ? 'RAND()' : 'RANDOM()',
    );
  }
}
