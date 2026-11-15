import 'dart:ui' as ui;

/// A language people can choose on the home page.
/// Keep the codes in sync with `LANGS` in server/index.js.
class Lang {
  const Lang(this.code, this.name, this.native);
  final String code; // ISO 639-1, or 'any'
  final String name; // English name
  final String native; // name written in the language itself
  String get badge => code == 'any' ? 'ALL' : code.toUpperCase();
}

const String kAnyLang = 'any';

const List<Lang> kLanguages = [
  Lang('any', 'Any language', 'Anyone'),
  Lang('en', 'English', 'English'),
  Lang('fr', 'French', 'Français'),
  Lang('ar', 'Arabic', 'العربية'),
  Lang('es', 'Spanish', 'Español'),
  Lang('pt', 'Portuguese', 'Português'),
  Lang('de', 'German', 'Deutsch'),
  Lang('it', 'Italian', 'Italiano'),
  Lang('tr', 'Turkish', 'Türkçe'),
  Lang('ru', 'Russian', 'Русский'),
  Lang('uk', 'Ukrainian', 'Українська'),
  Lang('pl', 'Polish', 'Polski'),
  Lang('nl', 'Dutch', 'Nederlands'),
  Lang('ro', 'Romanian', 'Română'),
  Lang('el', 'Greek', 'Ελληνικά'),
  Lang('sv', 'Swedish', 'Svenska'),
  Lang('he', 'Hebrew', 'עברית'),
  Lang('fa', 'Persian', 'فارسی'),
  Lang('ur', 'Urdu', 'اردو'),
  Lang('hi', 'Hindi', 'हिन्दी'),
  Lang('bn', 'Bengali', 'বাংলা'),
  Lang('id', 'Indonesian', 'Bahasa Indonesia'),
  Lang('vi', 'Vietnamese', 'Tiếng Việt'),
  Lang('th', 'Thai', 'ไทย'),
  Lang('zh', 'Chinese', '中文'),
  Lang('ja', 'Japanese', '日本語'),
  Lang('ko', 'Korean', '한국어'),
];

Lang langByCode(String? code) => kLanguages.firstWhere(
  (l) => l.code == code,
  orElse: () => kLanguages.first,
);

/// The language of the visitor's browser / phone, if we offer it; otherwise 'any'.
String deviceLanguageCode() {
  try {
    final code = ui.PlatformDispatcher.instance.locale.languageCode
        .toLowerCase();
    return kLanguages.any((l) => l.code == code) ? code : kAnyLang;
  } catch (_) {
    return kAnyLang;
  }
}
