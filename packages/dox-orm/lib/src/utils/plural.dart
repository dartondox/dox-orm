/// words that have no plural form
const Set<String> _same = <String>{
  'audio',
  'data',
  'deer',
  'equipment',
  'feedback',
  'fish',
  'information',
  'media',
  'metadata',
  'money',
  'news',
  'rice',
  'series',
  'sheep',
  'species',
};

/// words with their own plural form
const Map<String, String> _irregular = <String, String>{
  'analysis': 'analyses',
  'child': 'children',
  'criterion': 'criteria',
  'foot': 'feet',
  'goose': 'geese',
  'half': 'halves',
  'knife': 'knives',
  'leaf': 'leaves',
  'life': 'lives',
  'man': 'men',
  'mouse': 'mice',
  'ox': 'oxen',
  'person': 'people',
  'tooth': 'teeth',
  'wife': 'wives',
  'woman': 'women',
};

/// the plural of a snake case name: only the last word changes, so
/// `blog_post` gives `blog_posts`, `category` gives `categories`.
///
/// ponytail: plain English rules and a short list of special words.
/// A model with another plural sets its table name with
/// `@DoxModel(table: ...)`.
String pluralName(String name) {
  int cut = name.lastIndexOf('_') + 1;
  String head = name.substring(0, cut);
  String word = name.substring(cut);
  return '$head${_plural(word)}';
}

String _plural(String word) {
  if (word.isEmpty || _same.contains(word)) return word;
  String? irregular = _irregular[word];
  if (irregular != null) return irregular;
  if (RegExp(r'[^aeiou]y$').hasMatch(word)) {
    return '${word.substring(0, word.length - 1)}ies';
  }
  if (RegExp(r'(s|x|z|ch|sh)$').hasMatch(word)) return '${word}es';
  return '${word}s';
}
