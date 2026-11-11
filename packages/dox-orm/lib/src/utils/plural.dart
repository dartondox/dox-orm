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
  'axis': 'axes',
  'child': 'children',
  'criterion': 'criteria',
  'foot': 'feet',
  'goose': 'geese',
  'index': 'indices',
  'man': 'men',
  'matrix': 'matrices',
  'mouse': 'mice',
  'ox': 'oxen',
  'person': 'people',
  'quiz': 'quizzes',
  'tooth': 'teeth',
  'woman': 'women',
};

/// plurals of [_irregular], they stay as they are
final Set<String> _irregularPlurals = _irregular.values.toSet();

/// words that end in `o` and take `es`. Other `o` words take `s`
/// (`photo`, `piano`, `video`).
const Set<String> _oes = <String>{'echo', 'hero', 'potato', 'tomato', 'veto'};

/// words that end in `f` or `fe` and take `ves`
const Set<String> _ves = <String>{
  'calf',
  'half',
  'knife',
  'leaf',
  'life',
  'loaf',
  'shelf',
  'thief',
  'wife',
  'wolf',
};

/// a consonant then `y`: `category` gives `categories`
final RegExp _consonantY = RegExp(r'[^aeiou]y$');

/// endings that take `es`
final RegExp _esEnding = RegExp(r'(s|x|z|ch|sh)$');

/// a word that ends in `s` but is singular: `status`, `address`,
/// `analysis`, `alias`. Any other word that ends in `s` is plural
/// already (`users`, `goods`, `statuses`).
final RegExp _singularS = RegExp(r'(ss|us|is|as)$');

/// plurals already made, by snake name
final Map<String, String> _cache = <String, String>{};

/// the plural of a snake case name: only the last word changes, so
/// `blog_post` gives `blog_posts`, `category` gives `categories`. A
/// word that is plural already stays as it is (`users`, `people`).
///
/// ponytail: plain English rules and short lists of special words. A
/// model with another plural sets its table name with
/// `@DoxModel(table: ...)`.
String pluralName(String name) {
  String? known = _cache[name];
  if (known != null) return known;
  int cut = name.lastIndexOf('_') + 1;
  return _cache[name] =
      '${name.substring(0, cut)}${_plural(name.substring(cut))}';
}

String _plural(String word) {
  if (word.isEmpty || _same.contains(word)) return word;
  if (_irregularPlurals.contains(word)) return word;
  String? irregular = _irregular[word];
  if (irregular != null) return irregular;
  if (word.endsWith('s') && !_singularS.hasMatch(word)) return word;
  if (_oes.contains(word)) return '${word}es';
  if (_ves.contains(word)) {
    String stem = word.endsWith('fe')
        ? word.substring(0, word.length - 2)
        : word.substring(0, word.length - 1);
    return '${stem}ves';
  }
  if (_consonantY.hasMatch(word)) {
    return '${word.substring(0, word.length - 1)}ies';
  }
  if (_esEnding.hasMatch(word)) return '${word}es';
  return '${word}s';
}
