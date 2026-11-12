import 'package:dox_orm/dox_orm.dart';
import 'package:test/test.dart';

import 'models/blog/blog.model.dart';

/// a blog that keeps only a few fields in toJson()
class ShortBlog extends Blog {
  @override
  List<String> get visibleFields => const <String>['uid', 'title', 'status'];
}

Blog _blog(Blog b) => b
  ..uid = 1
  ..title = 't'
  ..status = 's'
  ..description = 'd';

void main() {
  group('Visibility |', () {
    test('toJson with none used keeps hidden as before', () {
      Map<String, dynamic> json = _blog(Blog()).toJson();
      expect(json.containsKey('status'), false);
      expect(json.containsKey('secret_note'), false);
      expect(json['body'], 'd');
    });

    test('makeHidden and makeVisible on one model', () {
      Blog blog = _blog(Blog());
      expect(blog.makeHidden(<String>['body']), blog);
      blog.makeVisible(<String>['status']);
      Map<String, dynamic> json = blog.toJson();
      expect(json.containsKey('body'), false);
      expect(json['status'], 's');
      expect(json.containsKey('secret_note'), false);
      expect(blog.toMap(removeHiddenField: true)['status'], 's');

      /// the last call wins
      blog.makeHidden(<String>['status']).makeVisible(<String>['body']);
      json = blog.toJson();
      expect(json.containsKey('status'), false);
      expect(json['body'], 'd');

      /// another model of the class does not change
      expect(_blog(Blog()).toJson().containsKey('status'), false);
    });

    test('visibleFields keeps only its fields, hidden still wins', () {
      ShortBlog blog = _blog(ShortBlog()) as ShortBlog;
      expect(blog.toJson(), <String, dynamic>{'uid': 1, 'title': 't'});

      blog.makeVisible(<String>['status', 'body']);
      expect(blog.toJson(), <String, dynamic>{
        'uid': 1,
        'title': 't',
        'status': 's',
        'body': 'd',
      });
    });

    test('on a list of models', () {
      List<Blog> blogs = <Blog>[_blog(Blog()), _blog(Blog())];
      expect(blogs.makeVisible(<String>['status']), blogs);
      expect(toMap(blogs)[1]['status'], 's');
      blogs.makeHidden(<String>['title']);
      expect(toMap(blogs)[0].containsKey('title'), false);
    });
  });
}
