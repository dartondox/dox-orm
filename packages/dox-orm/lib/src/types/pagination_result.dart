/// pagination result
class Pagination<T> {
  /// total records
  final int total;

  /// record per page
  final int perPage;

  /// last page of the pagination
  final int lastPage;

  /// current page of pagination
  final int currentPage;

  List<T> data;

  /// constructor
  Pagination({
    required this.total,
    required this.perPage,
    required this.lastPage,
    required this.currentPage,
    required this.data,
  });

  /// get list of data
  List<R> getData<R>() {
    return data as List<R>;
  }

  /// support json encode
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'total': total,
      'per_page': perPage,
      'last_page': lastPage,
      'current_page': currentPage,
      'data': data,
    };
  }
}

/// result of simplePaginate(): a page without the total count
class SimplePagination<T> {
  /// record per page
  final int perPage;

  /// current page of pagination
  final int currentPage;

  /// true when there is a next page
  final bool hasMorePages;

  List<T> data;

  /// constructor
  SimplePagination({
    required this.perPage,
    required this.currentPage,
    required this.hasMorePages,
    required this.data,
  });

  /// the number of the first row of this page, null when it is empty
  int? get from => data.isEmpty ? null : (currentPage - 1) * perPage + 1;

  /// the number of the last row of this page, null when it is empty
  int? get to =>
      data.isEmpty ? null : (currentPage - 1) * perPage + data.length;

  /// support json encode
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'per_page': perPage,
      'current_page': currentPage,
      'from': from,
      'to': to,
      'has_more_pages': hasMorePages,
      'data': data,
    };
  }
}

/// result of cursorPaginate()
class CursorPagination<T> {
  /// record per page
  final int perPage;

  /// the cursor of the next page, null on the last page
  final String? nextCursor;

  /// the cursor of the page before, null on the first page
  final String? prevCursor;

  List<T> data;

  /// constructor
  CursorPagination({
    required this.perPage,
    required this.nextCursor,
    required this.prevCursor,
    required this.data,
  });

  /// support json encode
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'per_page': perPage,
      'next_cursor': nextCursor,
      'prev_cursor': prevCursor,
      'data': data,
    };
  }
}
