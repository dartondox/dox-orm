// The plural rules below are ported from Doctrine Inflector (MIT), the
// English rules that Laravel `Str::plural` uses, plus the uncountable
// words of Laravel `Pluralizer`.
//
// Copyright (c) 2006-2015 Doctrine Project
//
// Permission is hereby granted, free of charge, to any person obtaining a copy of
// this software and associated documentation files (the "Software"), to deal in
// the Software without restriction, including without limitation the rights to
// use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies
// of the Software, and to permit persons to whom the Software is furnished to do
// so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

/// words that do not change (Doctrine `Uninflected::getPlural` and
/// Laravel `Pluralizer::$uncountable`). Each is a pattern for the whole
/// word.
const List<String> _uninflectedWords = <String>[
  r'\w+media', 'advice', 'aircraft', 'amoyese', 'art', 'audio',
  'baggage', 'bison', 'borghese', 'bream', 'breeches', 'britches',
  'buffalo', 'butter', 'cantus', 'carp', 'cattle', 'chassis', 'clippers',
  'clothing', 'coal', 'cod', 'coitus', 'compensation', 'congoese',
  'contretemps', 'coreopsis', 'corps', 'cotton', 'data', 'debris', 'deer',
  'diabetes', 'djinn', 'education', 'eland', 'elk', 'emoji', 'equipment',
  'evidence', 'faroese', 'feedback', 'fish', 'flounder', 'flour',
  'foochowese', 'food', 'furniture', 'gallows', 'genevese', 'genoese',
  'gilbertese', 'gold', 'headquarters', 'herpes', 'hijinks', 'homework',
  'hottentotese', 'impatience', 'information', 'innings', 'jackanapes',
  'jeans', 'jedi', 'kin', 'kiplingese', 'knowledge', 'kongoese', 'leather',
  'love', 'lucchese', 'luggage', 'mackerel', 'maltese', 'management',
  'metadata', 'mews', 'money', 'moose', 'mumps', 'music', 'nankingese',
  'news', 'nexus', 'niasese', 'nutrition', 'offspring', 'oil', 'patience',
  'pekingese', 'piedmontese', 'pincers', 'pistoiese', 'plankton', 'pliers',
  'pokemon', 'police', 'polish', 'portuguese', 'proceedings', 'progress',
  'rabies', 'rain', 'research', 'rhinoceros', 'rice', 'salmon', 'sand',
  'sarawakese', 'scissors', 'sea[- ]bass', 'series', 'shavese', 'shears',
  'sheep', 'siemens', 'silk', 'sms', 'soap', 'social media', 'spam',
  'species', 'staff', 'sugar', 'swine', 'talent', 'toothpaste', 'traffic',
  'travel', 'trousers', 'trout', 'tuna', 'us', 'vermontese', 'vinegar',
  'weather', 'wenchowese', 'wheat', 'whiting', 'wildebeest', 'wood',
  'wool', 'yengeese',
  // plural only
  'people', 'trivia', r'\w+ware$', 'media',
  // Laravel
  'recommended', 'related',
];

final RegExp _uninflected = RegExp(
  '^(?:${_uninflectedWords.join('|')})\$',
  caseSensitive: false,
);

/// words with their own plural (Doctrine `Inflectible::getIrregular`)
const Map<String, String> _irregular = <String, String>{
  'atlas': 'atlases',
  'axe': 'axes',
  'beef': 'beefs',
  'blouse': 'blouses',
  'brother': 'brothers',
  'cafe': 'cafes',
  'chateau': 'chateaux',
  'niveau': 'niveaux',
  'child': 'children',
  'canvas': 'canvases',
  'cookie': 'cookies',
  'corpus': 'corpuses',
  'cow': 'cows',
  'criterion': 'criteria',
  'curriculum': 'curricula',
  'demo': 'demos',
  'domino': 'dominoes',
  'echo': 'echoes',
  'foot': 'feet',
  'fungus': 'fungi',
  'ganglion': 'ganglions',
  'gas': 'gases',
  'genie': 'genies',
  'genus': 'genera',
  'goose': 'geese',
  'graffito': 'graffiti',
  'hippopotamus': 'hippopotami',
  'hoof': 'hoofs',
  'human': 'humans',
  'iris': 'irises',
  'larva': 'larvae',
  'leaf': 'leaves',
  'lens': 'lenses',
  'loaf': 'loaves',
  'man': 'men',
  'medium': 'media',
  'memorandum': 'memoranda',
  'money': 'monies',
  'mongoose': 'mongooses',
  'motto': 'mottoes',
  'move': 'moves',
  'mythos': 'mythoi',
  'niche': 'niches',
  'nucleus': 'nuclei',
  'numen': 'numina',
  'occiput': 'occiputs',
  'octopus': 'octopuses',
  'opus': 'opuses',
  'ox': 'oxen',
  'passerby': 'passersby',
  'penis': 'penises',
  'person': 'people',
  'plateau': 'plateaux',
  'runner-up': 'runners-up',
  'safe': 'safes',
  'sex': 'sexes',
  'sieve': 'sieves',
  'soliloquy': 'soliloquies',
  'son-in-law': 'sons-in-law',
  'syllabus': 'syllabi',
  'testis': 'testes',
  'thief': 'thieves',
  'tooth': 'teeth',
  'tornado': 'tornadoes',
  'trilby': 'trilbys',
  'turf': 'turfs',
  'valve': 'valves',
  'volcano': 'volcanoes',
  'abuse': 'abuses',
  'avalanche': 'avalanches',
  'cache': 'caches',
  'curve': 'curves',
  'emphasis': 'emphases',
  'foe': 'foes',
  'grave': 'graves',
  'hoax': 'hoaxes',
  'neurosis': 'neuroses',
  'save': 'saves',
  'wave': 'waves',
  'oasis': 'oases',
  'zombie': 'zombies',
};

/// (pattern, replacement) in Doctrine order (`Inflectible::getPlural`),
/// the first match wins. `\1` is a group of the pattern, a group that
/// did not match is empty.
final List<(RegExp, String)> _rules = <(String, String)>[
  (r'(s)tatus$', r'\1\2tatuses'),
  (r'(quiz)$', r'\1zes'),
  (r'^(ox)$', r'\1\2en'),
  (r'([m|l])ouse$', r'\1ice'),
  (r'(matr|vert|ind)(ix|ex)$', r'\1ices'),
  (r'(x|ch|ss|sh)$', r'\1es'),
  (r'([^aeiouy]|qu)y$', r'\1ies'),
  (r'(hive|gulf)$', r'\1s'),
  (r'(?:([^f])fe|([lr])f)$', r'\1\2ves'),
  (r'sis$', 'ses'),
  (r'([ti])um$', r'\1a'),
  (r'(tax)on$', r'\1a'),
  (r'(c)riterion$', r'\1riteria'),
  (r'(p)erson$', r'\1eople'),
  (r'(m)an$', r'\1en'),
  (r'(c)hild$', r'\1hildren'),
  (r'(f)oot$', r'\1eet'),
  (r'(buffal|her|potat|tomat|volcan)o$', r'\1\2oes'),
  (
    r'(alumn|bacill|cact|foc|fung|nucle|radi|stimul|syllab|termin|vir)us$',
    r'\1i',
  ),
  (r'us$', 'uses'),
  (r'(alias)$', r'\1es'),
  (r'(analys|ax|cris|test|thes)is$', r'\1es'),
  (r's$', 's'),
  (r'$', 's'),
].map(_rule).toList();

(RegExp, String) _rule((String, String) rule) {
  return (RegExp(rule.$1, caseSensitive: false), rule.$2);
}

/// a `\1` in a replacement
final RegExp _group = RegExp(r'\\(\d)');

/// plurals already made, by snake name
final Map<String, String> _cache = <String, String>{};

/// the plural of a snake case name, like Laravel: only the last word
/// changes, so `blog_post` gives `blog_posts` and `category` gives
/// `categories`. `user_data` stays `user_data`.
String pluralName(String name) {
  String? known = _cache[name];
  if (known != null) return known;
  int cut = name.lastIndexOf('_') + 1;
  return _cache[name] =
      '${name.substring(0, cut)}${_plural(name.substring(cut))}';
}

String _plural(String word) {
  if (word.isEmpty || _uninflected.hasMatch(word)) return word;
  String? irregular = _irregular[word.toLowerCase()];
  if (irregular != null) return irregular;
  for (var (RegExp pattern, String replacement) in _rules) {
    RegExpMatch? match = pattern.firstMatch(word);
    if (match == null) continue;
    String text = replacement.replaceAllMapped(_group, (Match g) {
      int n = int.parse(g[1]!);
      return n <= match.groupCount ? match[n] ?? '' : '';
    });
    return word.replaceRange(match.start, match.end, text);
  }
  return word;
}
