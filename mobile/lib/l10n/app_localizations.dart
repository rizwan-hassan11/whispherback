import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

/// App-wide localized strings for English, Urdu, Arabic, Dutch, and French.
class AppLocalizations {
  AppLocalizations(this.locale);

  final Locale locale;

  String get _lang => locale.languageCode;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static AppLocalizations ofOrThrow(BuildContext context) {
    final value = of(context);
    assert(value != null, 'AppLocalizations not found in context');
    return value!;
  }

  static const localizationsDelegates = <LocalizationsDelegate<dynamic>>[
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ];

  static const supportedLocales = <Locale>[
    Locale('en'),
    Locale('ur'),
    Locale('ar'),
    Locale('nl'),
    Locale('fr'),
  ];

  static const delegate = _AppLocalizationsDelegate();

  String _s(String en, String ur, String ar, String nl, String fr) {
    switch (_lang) {
      case 'ur':
        return ur;
      case 'ar':
        return ar;
      case 'nl':
        return nl;
      case 'fr':
        return fr;
      default:
        return en;
    }
  }

  // ── Language names ──────────────────────────────────────────────────────────
  String get languageEnglish => _s('English', 'English', 'English', 'English', 'English');
  String get languageUrdu => _s('Urdu', 'اردو', 'الأردية', 'Urdu', 'Ourdou');
  String get languageArabic => _s('Arabic', 'عربی', 'العربية', 'Arabisch', 'Arabe');
  String get languageDutch => _s('Dutch', 'ڈچ', 'الهولندية', 'Nederlands', 'Néerlandais');
  String get languageFrench => _s('French', 'فرانسیسی', 'الفرنسية', 'Frans', 'Français');

  String languageName(String code) => switch (code) {
        'ur' => languageUrdu,
        'ar' => languageArabic,
        'nl' => languageDutch,
        'fr' => languageFrench,
        _ => languageEnglish,
      };

  // ── Navigation ──────────────────────────────────────────────────────────────
  String get navHome => _s('Home', 'ہوم', 'الرئيسية', 'Home', 'Accueil');
  String get navLists => _s('Lists', 'لسٹیں', 'القوائم', 'Lijsten', 'Listes');
  String get navClips => _s('Clips', 'کلپس', 'المقاطع', 'Clips', 'Clips');
  String get navSchedule => _s('Schedule', 'شیڈول', 'الجدول', 'Schema', 'Planning');
  String get navSettings => _s('Settings', 'ترتیبات', 'الإعدادات', 'Instellingen', 'Paramètres');

  // ── Splash ──────────────────────────────────────────────────────────────────
  String get appTagline => _s(
        'Your Personalized Audio Whisperer',
        'آپ کا ذاتی آڈیو Whisperer',
        'مرافقك الصوتي الشخصي',
        'Jouw persoonlijke audio-whisperer',
        'Votre murmureur audio personnalisé',
      );

  // ── Common ──────────────────────────────────────────────────────────────────
  String get ok => _s('OK', 'ٹھیک', 'حسناً', 'OK', 'OK');
  String get save => _s('Save', 'محفوظ', 'حفظ', 'Opslaan', 'Enregistrer');
  String get cancel => _s('Cancel', 'منسوخ', 'إلغاء', 'Annuleren', 'Annuler');
  String get edit => _s('Edit', 'ترمیم', 'تعديل', 'Bewerken', 'Modifier');
  String get play => _s('Play', 'چلائیں', 'تشغيل', 'Afspelen', 'Lire');
  String get pause => _s('Pause', 'روکیں', 'إيقاف', 'Pauzeren', 'Pause');
  String get stop => _s('Stop', 'بند', 'إيقاف', 'Stoppen', 'Arrêter');
  String get create => _s('Create', 'بنائیں', 'إنشاء', 'Maken', 'Créer');
  String get browse => _s('Browse', 'براؤز', 'تصفح', 'Bladeren', 'Parcourir');
  String get remove => _s('Remove', 'ہٹائیں', 'إزالة', 'Verwijderen', 'Supprimer');
  String get live => _s('Live', 'لائیو', 'مباشر', 'Live', 'En direct');
  String get active => _s('Active', 'فعال', 'نشط', 'Actief', 'Actif');
  String get paused => _s('paused', 'روکا', 'متوقف', 'gepauzeerd', 'en pause');
  String get playlist => _s('Playlist', 'پلے لسٹ', 'قائمة تشغيل', 'Afspeellijst', 'Playlist');
  String get clipsUpper => _s('CLIPS', 'کلپس', 'المقاطع', 'CLIPS', 'CLIPS');
  String get yourClips => _s('YOUR CLIPS', 'آپ کی کلپس', 'مقاطعك', 'JOUW CLIPS', 'VOS CLIPS');
  String get yourSchedules => _s('YOUR SCHEDULES', 'آپ کے شیڈول', 'جداولك', 'JOUW SCHEMA\'S', 'VOS PLANNING');

  // ── Settings ────────────────────────────────────────────────────────────────
  String get settings => _s('Settings', 'ترتیبات', 'الإعدادات', 'Instellingen', 'Paramètres');
  String get settingsSubtitle =>
      _s('Preferences & defaults', 'ترجیحات اور ڈیفالٹ', 'التفضيلات والافتراضيات', 'Voorkeuren & standaard', 'Préférences et valeurs par défaut');
  String get groupDisplay => _s('Display', 'ڈسپلے', 'العرض', 'Weergave', 'Affichage');
  String get groupSchedulesAlarms =>
      _s('Schedules & alarms', 'شیڈول اور الارم', 'الجداول والتنبيهات', 'Schema\'s & alarmen', 'Plannings et alarmes');
  String get groupAccount => _s('Account', 'اکاؤنٹ', 'الحساب', 'Account', 'Compte');
  String get groupModes => _s('Modes', 'موڈز', 'الأوضاع', 'Modi', 'Modes');
  String get groupDevice => _s('Device', 'ڈیوائس', 'الجهاز', 'Apparaat', 'Appareil');
  String get theme => _s('Theme', 'تھیم', 'السمة', 'Thema', 'Thème');
  String get themeSubtitle =>
      _s('Light or dark appearance', 'روشن یا تاریک ظاہری شکل', 'المظهر الفاتح أو الداكن', 'Lichte of donkere weergave', 'Apparence claire ou sombre');
  String get light => _s('Light', 'روشن', 'فاتح', 'Licht', 'Clair');
  String get dark => _s('Dark', 'تاریک', 'داكن', 'Donker', 'Sombre');
  String get auto => _s('Auto', 'خودکار', 'تلقائي', 'Auto', 'Auto');
  String get showLabels => _s('Show labels', 'لیبل دکھائیں', 'إظهار التسميات', 'Labels tonen', 'Afficher les libellés');
  String get showLabelsSubtitle => _s(
        'Text under navigation icons',
        'نیویگیشن آئیکنز کے نیچے متن',
        'نص تحت أيقونات التنقل',
        'Tekst onder navigatiepictogrammen',
        'Texte sous les icônes de navigation',
      );
  String get language => _s('Language', 'زبان', 'اللغة', 'Taal', 'Langue');
  String get languageSubtitle => _s(
        'App display language',
        'ایپ کی زبان',
        'لغة عرض التطبيق',
        'Weergavetaal van de app',
        'Langue d\'affichage de l\'app',
      );
  String get chooseLanguage => _s('Choose language', 'زبان منتخب کریں', 'اختر اللغة', 'Kies taal', 'Choisir la langue');
  String get alarmsByDefault => _s('Alarms by default', 'ڈیفالٹ الارم', 'تنبيهات افتراضياً', 'Alarmen standaard', 'Alarmes par défaut');
  String get alarmsByDefaultSubtitle => _s(
        'New schedules notify when whispers are due',
        'نئے شیڈول whisper کی وقت پر اطلاع دیں',
        'تُبلغ الجداول الجديدة عند موعد الهمسات',
        'Nieuwe schema\'s melden wanneer whispers klaar zijn',
        'Les nouvelles plannings notifient quand les murmures sont dus',
      );
  String get defaultInterval => _s('Default interval', 'ڈیفالٹ وقفہ', 'الفاصل الافتراضي', 'Standaardinterval', 'Intervalle par défaut');
  String get signIn => _s('Sign in', 'سائن ان', 'تسجيل الدخول', 'Inloggen', 'Se connecter');
  String get signInSubtitle =>
      _s('Sync when cloud is enabled', 'کلاؤڈ فعال ہونے پر مطابقت', 'مزامنة عند تفعيل السحابة', 'Synchroniseren wanneer cloud aan staat', 'Synchroniser quand le cloud est activé');
  String get createAccount => _s('Create account', 'اکاؤنٹ بنائیں', 'إنشاء حساب', 'Account maken', 'Créer un compte');
  String get createAccountSettingsSubtitle =>
      _s('Backup clips and schedules', 'کلپس اور شیڈول بیک اپ', 'نسخ المقاطع والجداول احتياطياً', 'Clips en schema\'s back-uppen', 'Sauvegarder clips et plannings');
  String get sleepMode => _s('Sleep mode', 'نیند موڈ', 'وضع النوم', 'Slaapmodus', 'Mode veille');
  String get sleepModeSubtitle => _s('Silence windows', 'خاموشی کے اوقات', 'نوافذ الصمت', 'Stilteperiodes', 'Fenêtres de silence');
  String get prayerMode => _s('Prayer mode', 'نماز موڈ', 'وضع الصلاة', 'Gebedsmodus', 'Mode prière');
  String get prayerModeSubtitle =>
      _s('Karachi method · GPS', 'کراچی طریقہ · GPS', 'طريقة كراتشي · GPS', 'Karachi-methode · GPS', 'Méthode Karachi · GPS');
  String get batteryOptimization =>
      _s('Battery optimization', 'بیٹری آپٹیمائزیشن', 'تحسين البطارية', 'Batterijoptimalisatie', 'Optimisation batterie');
  String get batteryOptimizationSubtitle =>
      _s('Keep schedules reliable', 'شیڈول قابلِ اعتماد رکھیں', 'اجعل الجداول موثوقة', 'Schema\'s betrouwbaar houden', 'Garder les plannings fiables');
  String get versionFooter =>
      _s('WhisperBack v1.0.0 · Local MVP', 'WhisperBack v1.0.0 · Local MVP', 'WhisperBack v1.0.0 · Local MVP', 'WhisperBack v1.0.0 · Local MVP', 'WhisperBack v1.0.0 · Local MVP');

  String minutesBetweenWhispers(int minutes) => _s(
        '$minutes minutes between whispers',
        'whispers کے درمیان $minutes منٹ',
        '$minutes دقيقة بين الهمسات',
        '$minutes minuten tussen whispers',
        '$minutes minutes entre les murmures',
      );

  String minutesCount(int minutes) => _s('$minutes minutes', '$minutes منٹ', '$minutes دقيقة', '$minutes minuten', '$minutes minutes');

  // ── Home ────────────────────────────────────────────────────────────────────
  String get goodMorning => _s('Good morning', 'صبح بخیر', 'صباح الخير', 'Goedemorgen', 'Bonjour');
  String get goodAfternoon => _s('Good afternoon', 'دوپہر بخیر', 'مساء الخير', 'Goedemiddag', 'Bon après-midi');
  String get goodEvening => _s('Good evening', 'شام بخیر', 'مساء الخير', 'Goedenavond', 'Bonsoir');
  String get createPlaylistToStart => _s(
        'Create a playlist to get started',
        'شروع کرنے کے لیے پلے لسٹ بنائیں',
        'أنشئ قائمة تشغيل للبدء',
        'Maak een afspeellijst om te beginnen',
        'Créez une playlist pour commencer',
      );
  String get nextWhisper => _s('Next whisper', 'اگلی whisper', 'الهمسة التالية', 'Volgende whisper', 'Prochain murmure');
  String get nextWhisperSample => _s(
        'Morning Whispers · ~30 min',
        'Morning Whispers · ~30 منٹ',
        'Morning Whispers · ~30 د',
        'Morning Whispers · ~30 min',
        'Morning Whispers · ~30 min',
      );
  String get sleepModeActive => _s('Sleep mode active', 'نیند موڈ فعال', 'وضع النوم نشط', 'Slaapmodus actief', 'Mode veille actif');
  String get prayerPauseActive => _s('Prayer pause active', 'نماز وقفہ فعال', 'توقف الصلاة نشط', 'Gebedspauze actief', 'Pause prière active');
  String get activeWhispersPlaying =>
      _s('Active — whispers playing', 'فعال — whispers چل رہی ہیں', 'نشط — الهمسات تعمل', 'Actief — whispers spelen', 'Actif — murmures en cours');
  String get tapPowerToBegin =>
      _s('Tap power to begin', 'شروع کرنے کے لیے پاور دبائیں', 'اضغط للبدء', 'Tik op power om te beginnen', 'Appuyez sur power pour commencer');
  String get statPlaylists => _s('Playlists', 'پلے لسٹ', 'قوائم التشغيل', 'Afspeellijsten', 'Playlists');
  String get statScheduled => _s('Scheduled', 'شیڈول', 'مجدول', 'Gepland', 'Planifié');
  String get statClips => _s('Clips', 'کلپس', 'المقاطع', 'Clips', 'Clips');

  String playlistsReady(int count) {
    if (count == 1) {
      return _s('1 playlist ready to whisper', '1 پلے لسٹ whisper کے لیے تیار', 'قائمة واحدة جاهزة للهمس', '1 afspeellijst klaar om te whisperen', '1 playlist prête à murmurer');
    }
    return _s('$count playlists ready to whisper', '$count پلے لسٹ whispers کے لیے تیار', '$count قوائم جاهزة للهمس', '$count afspeellijsten klaar', '$count playlists prêtes à murmurer');
  }

  // ── Playlists ───────────────────────────────────────────────────────────────
  String get playlists => _s('Playlists', 'پلے لسٹ', 'قوائم التشغيل', 'Afspeellijsten', 'Playlists');
  String get scheduled => _s('Scheduled', 'شیڈول', 'مجدول', 'Gepland', 'Planifié');
  String get yourLibrary => _s('Your library', 'آپ کی لائبریری', 'مكتبتك', 'Jouw bibliotheek', 'Votre bibliothèque');
  String get addClips => _s('Add clips', 'کلپس شامل کریں', 'إضافة مقاطع', 'Clips toevoegen', 'Ajouter des clips');
  String get newPlaylist => _s('New playlist', 'نئی پلے لسٹ', 'قائمة جديدة', 'Nieuwe afspeellijst', 'Nouvelle playlist');
  String get noPlaylistsYet => _s('No playlists yet', 'ابھی کوئی پلے لسٹ نہیں', 'لا توجد قوائم بعد', 'Nog geen afspeellijsten', 'Aucune playlist');
  String get createPlaylist => _s('Create playlist', 'پلے لسٹ بنائیں', 'إنشاء قائمة', 'Afspeellijst maken', 'Créer une playlist');
  String get totalClips => _s('Total clips', 'کل کلپس', 'إجمالي المقاطع', 'Totaal clips', 'Total clips');
  String get shuffleOn => _s('Shuffle on', 'شفل آن', 'تشغيل عشوائي', 'Shuffle aan', 'Lecture aléatoire');
  String get shuffleOff => _s('Shuffle off', 'شفل آف', 'إيقاف العشوائي', 'Shuffle uit', 'Lecture aléatoire off');
  String get scheduledBadge => _s('Scheduled', 'شیڈول', 'مجدول', 'Gepland', 'Planifié');
  String get playAll => _s('Play all', 'سب چلائیں', 'تشغيل الكل', 'Alles afspelen', 'Tout lire');
  String get scheduledActiveNow => _s('Scheduled · Active now', 'شیڈول · ابھی فعال', 'مجدول · نشط الآن', 'Gepland · Nu actief', 'Planifié · Actif maintenant');
  String get scheduledPlayback => _s('Scheduled playback', 'شیڈول پلے بیک', 'تشغيل مجدول', 'Geplande weergave', 'Lecture planifiée');
  String get noClipsInPlaylist => _s('No clips in this playlist', 'اس پلے لسٹ میں کوئی کلپ نہیں', 'لا مقاطع في هذه القائمة', 'Geen clips in deze lijst', 'Aucun clip dans cette playlist');
  String get recordOrImportClips =>
      _s('Record or import clips, then add them here.', 'کلپ ریکارڈ یا درآمد کریں، پھر یہاں شامل کریں۔', 'سجّل أو استورد مقاطع ثم أضفها هنا.', 'Neem op of importeer clips en voeg ze hier toe.', 'Enregistrez ou importez des clips, puis ajoutez-les ici.');
  String get browseClips => _s('Browse clips', 'کلپس براؤز کریں', 'تصفح المقاطع', 'Clips bladeren', 'Parcourir les clips');

  String clipCountLabel(int count) => _s(
        '$count clip${count == 1 ? '' : 's'}',
        '$count کلپ',
        '$count مقط${count == 1 ? '' : 'ع'}',
        '$count clip${count == 1 ? '' : 's'}',
        '$count clip${count == 1 ? '' : 's'}',
      );

  String clipsInOrder(int count) => _s(
        '$count clip${count == 1 ? '' : 's'} in order',
        '$count کلپ ترتیب سے',
        '$count مقط${count == 1 ? '' : 'ع'} بالترتيب',
        '$count clip${count == 1 ? '' : 's'} op volgorde',
        '$count clip${count == 1 ? '' : 's'} dans l\'ordre',
      );

  String collectionsSummary(int collections, int clips) => _s(
        '$collections collections · $clips clips',
        '$collections مجموعے · $clips کلپس',
        '$collections مجموعات · $clips مقاطع',
        '$collections collecties · $clips clips',
        '$collections collections · $clips clips',
      );

  String scheduleStartsEvery(String time, String interval) => _s(
        'Starts $time · every $interval',
        '$time سے شروع · ہر $interval',
        'يبدأ $time · كل $interval',
        'Start $time · elke $interval',
        'Démarre $time · toutes les $interval',
      );

  // ── Clips ───────────────────────────────────────────────────────────────────
  String get clipLibrary => _s('Clip Library', 'کلپ لائبریری', 'مكتبة المقاطع', 'Clipbibliotheek', 'Bibliothèque de clips');
  String get record => _s('Record', 'ریکارڈ', 'تسجيل', 'Opnemen', 'Enregistrer');
  String get import => _s('Import', 'درآمد', 'استيراد', 'Importeren', 'Importer');
  String get all => _s('All', 'سب', 'الكل', 'Alles', 'Tout');
  String get recorded => _s('Recorded', 'ریکارڈ شدہ', 'مسجل', 'Opgenomen', 'Enregistré');
  String get imported => _s('Imported', 'درآمد شدہ', 'مستورد', 'Geïmporteerd', 'Importé');
  String get noClipsYet => _s('No clips yet', 'ابھی کوئی کلپ نہیں', 'لا مقاطع بعد', 'Nog geen clips', 'Aucun clip');
  String get noClipsEmptyHint => _s(
        'Record a whisper or import an audio file to get started.',
        'شروع کرنے کے لیے whisper ریکارڈ کریں یا آڈیو درآمد کریں۔',
        'سجّل همسة أو استورد ملفاً صوتياً للبدء.',
        'Neem een whisper op of importeer een audiobestand om te beginnen.',
        'Enregistrez un murmure ou importez un fichier audio pour commencer.',
      );
  String get noRecordedClips => _s('No recorded clips', 'کوئی ریکارڈ شدہ کلپ نہیں', 'لا مقاطع مسجلة', 'Geen opgenomen clips', 'Aucun clip enregistré');
  String get noImportedClips => _s('No imported clips', 'کوئی درآمد شدہ کلپ نہیں', 'لا مقاطع مستوردة', 'Geen geïmporteerde clips', 'Aucun clip importé');

  String clipsSummary(int count, String duration) => _s(
        '$count clip${count == 1 ? '' : 's'} · $duration total',
        '$count کلپ · $duration کل',
        '$count مقط${count == 1 ? '' : 'ع'} · $duration إجمالي',
        '$count clip${count == 1 ? '' : 's'} · $duration totaal',
        '$count clip${count == 1 ? '' : 's'} · $duration au total',
      );

  String filterLabel(String name, int count) => '$name · $count';

  String itemsCount(int count) => _s(
        '$count item${count == 1 ? '' : 's'}',
        '$count آئٹم',
        '$count عنصر',
        '$count item${count == 1 ? '' : 's'}',
        '$count élément${count == 1 ? '' : 's'}',
      );

  // ── Schedule overview ───────────────────────────────────────────────────────
  String get schedules => _s('Schedules', 'شیڈول', 'الجداول', 'Schema\'s', 'Plannings');
  String get noSchedulesYet => _s('No whispers scheduled yet', 'ابھی کوئی whisper شیڈول نہیں', 'لا همسات مجدولة بعد', 'Nog geen whispers gepland', 'Aucun murmure planifié');
  String get planYourWhispers => _s('Plan your whispers', 'اپنی whispers پلان کریں', 'خطط لهمساتك', 'Plan je whispers', 'Planifiez vos murmures');
  String get alarms => _s('Alarms', 'الارم', 'تنبيهات', 'Alarmen', 'Alarmes');
  String get next => _s('Next', 'اگلا', 'التالي', 'Volgende', 'Suivant');
  String get customizeSchedule => _s('Customize schedule', 'شیڈول حسبِ منشا', 'تخصيص الجدول', 'Schema aanpassen', 'Personnaliser la planning');
  String get customizeScheduleSubtitle =>
      _s('Times, intervals, days & alarms', 'اوقات، وقفے، دن اور الارم', 'الأوقات والفواصل والأيام والتنبيهات', 'Tijden, intervallen, dagen & alarmen', 'Horaires, intervalles, jours et alarmes');
  String get alarmOn => _s('Alarm on', 'الارم آن', 'تنبيه مفعّل', 'Alarm aan', 'Alarme activée');
  String get shuffle => _s('Shuffle', 'شفل', 'عشوائي', 'Shuffle', 'Aléatoire');
  String get nextWhisperIn => _s('Next whisper in ', 'اگلی whisper ', 'الهمسة التالية خلال ', 'Volgende whisper over ', 'Prochain murmure dans ');

  // ── Schedule builder ────────────────────────────────────────────────────────
  String get customize => _s('Customize', 'حسبِ منشا', 'تخصيص', 'Aanpassen', 'Personnaliser');
  String get setWhenWhispersPlay => _s(
        'Set when whispers play and how often',
        'طے کریں whispers کب اور کتنی بار چلیں',
        'حدد متى تعمل الهمسات ومدى تكرارها',
        'Stel in wanneer whispers spelen en hoe vaak',
        'Définissez quand et à quelle fréquence les murmures jouent',
      );
  String get timeWindow => _s('Time window', 'وقت کی مدت', 'نافذة الوقت', 'Tijdvenster', 'Fenêtre horaire');
  String get startTime => _s('Start time', 'شروع کا وقت', 'وقت البدء', 'Starttijd', 'Heure de début');
  String get endTime => _s('End time', 'اختتام کا وقت', 'وقت الانتهاء', 'Eindtijd', 'Heure de fin');
  String get noEnd => _s('No end', 'بغیر اختتام', 'بدون نهاية', 'Geen einde', 'Sans fin');
  String get repeatDays => _s('Repeat days', 'دہرانے کے دن', 'أيام التكرار', 'Herhalingsdagen', 'Jours de répétition');
  String get everyDay => _s('Every day', 'ہر روز', 'كل يوم', 'Elke dag', 'Chaque jour');
  String get weekdays => _s('Weekdays', 'ہفتے کے دن', 'أيام الأسبوع', 'Weekdagen', 'Jours ouvrables');
  String get weekends => _s('Weekends', 'ویک اینڈ', 'عطلة نهاية الأسبوع', 'Weekenden', 'Week-ends');
  String get intervalBetweenWhispers =>
      _s('Interval between whispers', 'whispers کے درمیان وقفہ', 'الفاصل بين الهمسات', 'Interval tussen whispers', 'Intervalle entre les murmures');
  String get playbackAndAlarms => _s('Playback & alarms', 'پلے بیک اور الارم', 'التشغيل والتنبيهات', 'Weergave & alarmen', 'Lecture et alarmes');
  String get shuffleClips => _s('Shuffle clips', 'کلپس شفل', 'تشغيل عشوائي للمقاطع', 'Clips shufflen', 'Lecture aléatoire des clips');
  String get shuffleClipsSubtitle =>
      _s('Random order within playlist', 'پلے لسٹ میں بے ترتیب', 'ترتيب عشوائي داخل القائمة', 'Willekeurige volgorde in lijst', 'Ordre aléatoire dans la playlist');
  String get alarmNotification => _s('Alarm notification', 'الارم اطلاع', 'إشعار التنبيه', 'Alarmmelding', 'Notification d\'alarme');
  String get alarmNotificationSubtitle =>
      _s('Notify when each whisper is due', 'ہر whisper کی وقت پر اطلاع', 'أبلغ عند موعد كل همسة', 'Melden wanneer elke whisper klaar is', 'Notifier quand chaque murmure est dû');
  String get saveSchedule => _s('Save Schedule', 'شیڈول محفوظ', 'حفظ الجدول', 'Schema opslaan', 'Enregistrer la planning');
  String get scheduleSaved => _s('Schedule saved', 'شیڈول محفوظ', 'تم حفظ الجدول', 'Schema opgeslagen', 'Planning enregistrée');
  String get scheduleSavedWithAlarm => _s('Schedule saved with alarm', 'الارم کے ساتھ شیڈول محفوظ', 'تم الحفظ مع التنبيه', 'Schema opgeslagen met alarm', 'Planning enregistrée avec alarme');
  String get scheduleConflict => _s('Schedule conflict', 'شیڈول تنازع', 'تعارض في الجدول', 'Schemaconflict', 'Conflit de planning');

  String scheduleConflictMessage(String name) => _s(
        'This overlaps with "$name". Adjust the start time or interval.',
        'یہ "$name" سے اوورلیپ ہے۔ شروع کا وقت یا وقفہ تبدیل کریں۔',
        'يتداخل مع "$name". عدّل وقت البدء أو الفاصل.',
        'Dit overlapt met "$name". Pas starttijd of interval aan.',
        'Chevauche "$name". Ajustez l\'heure de début ou l\'intervalle.',
      );

  // ── Playback ────────────────────────────────────────────────────────────────
  String get nowPlaying => _s('Now playing', 'اب چل رہا', 'يعمل الآن', 'Nu aan het spelen', 'En lecture');
  String get minimizePlayer => _s('Minimize player', 'پلیئر چھوٹا کریں', 'تصغير المشغّل', 'Speler minimaliseren', 'Réduire le lecteur');
  String get stopPlayback => _s('Stop playback', 'پلے بیک بند', 'إيقاف التشغيل', 'Weergave stoppen', 'Arrêter la lecture');
  String get toggleShuffle => _s('Toggle shuffle', 'شفل تبدیل', 'تبديل العشوائي', 'Shuffle wisselen', 'Basculer aléatoire');

  // ── Auth ────────────────────────────────────────────────────────────────────
  String get welcomeBack => _s('Welcome back', 'خوش آمدید', 'مرحباً بعودتك', 'Welkom terug', 'Bon retour');
  String get signInPageSubtitle => _s(
        'Sign in to sync your whispers across every device.',
        'ہر ڈیوائس پر whispers مطابقت کے لیے سائن ان کریں۔',
        'سجّل الدخول لمزامنة همساتك على كل جهاز.',
        'Log in om whispers op elk apparaat te synchroniseren.',
        'Connectez-vous pour synchroniser vos murmures sur tous les appareils.',
      );
  String get secure => _s('Secure', 'محفوظ', 'آمن', 'Veilig', 'Sécurisé');
  String get cloudSync => _s('Cloud sync', 'کلاؤڈ مطابقت', 'مزامنة سحابية', 'Cloudsync', 'Sync cloud');
  String get private => _s('Private', 'نجی', 'خاص', 'Privé', 'Privé');
  String get emailAddress => _s('Email address', 'ای میل', 'البريد الإلكتروني', 'E-mailadres', 'Adresse e-mail');
  String get emailHint => _s('you@example.com', 'you@example.com', 'you@example.com', 'you@example.com', 'you@example.com');
  String get password => _s('Password', 'پاس ورڈ', 'كلمة المرور', 'Wachtwoord', 'Mot de passe');
  String get passwordHint => _s('Your password', 'آپ کا پاس ورڈ', 'كلمة مرورك', 'Je wachtwoord', 'Votre mot de passe');
  String get forgotPassword => _s('Forgot password?', 'پاس ورڈ بھول گئے؟', 'نسيت كلمة المرور؟', 'Wachtwoord vergeten?', 'Mot de passe oublié ?');
  String get signInButton => _s('Sign In', 'سائن ان', 'تسجيل الدخول', 'Inloggen', 'Se connecter');
  String get dontHaveAccount => _s("Don't have an account? ", 'اکاؤنٹ نہیں؟ ', 'ليس لديك حساب؟ ', 'Geen account? ', 'Pas de compte ? ');
  String get signUpFree => _s('Sign up free', 'مفت سائن اپ', 'سجّل مجاناً', 'Gratis registreren', 'Inscrivez-vous gratuitement');
  String get createAccountTitle => _s('Create account', 'اکاؤنٹ بنائیں', 'إنشاء حساب', 'Account maken', 'Créer un compte');
  String get createAccountSubtitle => _s(
        'Record whispers, build playlists, and schedule playback.',
        'whispers ریکارڈ کریں، پلے لسٹ بنائیں، شیڈول کریں۔',
        'سجّل همسات، أنشئ قوائم، وجدول التشغيل.',
        'Neem whispers op, maak afspeellijsten en plan weergave.',
        'Enregistrez des murmures, créez des playlists et planifiez.',
      );
  String get syncClips => _s('Sync clips', 'کلپس مطابقت', 'مزامنة المقاطع', 'Clips synchroniseren', 'Synchroniser clips');
  String get schedulesLabel => _s('Schedules', 'شیڈول', 'الجداول', 'Schema\'s', 'Plannings');
  String get cloudBackup => _s('Cloud backup', 'کلاؤڈ بیک اپ', 'نسخ سحابي', 'Cloudback-up', 'Sauvegarde cloud');
  String get fullName => _s('Full name', 'پورا نام', 'الاسم الكامل', 'Volledige naam', 'Nom complet');
  String get fullNameHint => _s('Maria Khan', 'Maria Khan', 'Maria Khan', 'Maria Khan', 'Maria Khan');
  String get passwordHintSignup => _s('At least 8 characters', 'کم از کم 8 حروف', '8 أحرف على الأقل', 'Minimaal 8 tekens', 'Au moins 8 caractères');
  String get createAccountButton => _s('Create Account', 'اکاؤنٹ بنائیں', 'إنشاء حساب', 'Account maken', 'Créer un compte');
  String get acceptTermsError =>
      _s('Please accept the terms to continue', 'جاری رکھنے کے لیے شرائط قبول کریں', 'اقبل الشروط للمتابعة', 'Accepteer de voorwaarden om door te gaan', 'Acceptez les conditions pour continuer');
  String get alreadyHaveAccount => _s('Already have an account? ', 'پہلے سے اکاؤنٹ؟ ', 'لديك حساب؟ ', 'Al een account? ', 'Déjà un compte ? ');
  String get continueWithoutAccount => _s('Continue without account →', 'اکاؤنٹ کے بغیر جاری رکھیں →', 'المتابعة بدون حساب →', 'Doorgaan zonder account →', 'Continuer sans compte →');
  String get signUp => _s('Sign up', 'سائن اپ', 'التسجيل', 'Registreren', 'S\'inscrire');
  String get orContinueWith => _s('or continue with', 'یا جاری رکھیں', 'أو تابع مع', 'of ga verder met', 'ou continuer avec');
  String get google => _s('Google', 'Google', 'Google', 'Google', 'Google');
  String get apple => _s('Apple', 'Apple', 'Apple', 'Apple', 'Apple');
  String get termsPrefix => _s('I agree to the ', 'میں متفق ہوں ', 'أوافق على ', 'Ik ga akkoord met de ', 'J\'accepte les ');
  String get termsOfService => _s('Terms of Service', 'سروس کی شرائط', 'شروط الخدمة', 'Servicevoorwaarden', 'Conditions d\'utilisation');
  String get and => _s(' and ', ' اور ', ' و ', ' en ', ' et ');
  String get privacyPolicy => _s('Privacy Policy', 'رازداری کی پالیسی', 'سياسة الخصوصية', 'Privacybeleid', 'Politique de confidentialité');
  String get passwordHintEmpty =>
      _s('Use 8+ characters with letters and numbers.', '8+ حروف اور نمبر استعمال کریں۔', 'استخدم 8+ أحرف وأرقام.', 'Gebruik 8+ tekens met letters en cijfers.', 'Utilisez 8+ caractères avec lettres et chiffres.');
  String get passwordWeak => _s('Weak — add more characters.', 'کمزور — مزید حروف شامل کریں۔', 'ضعيف — أضف المزيد.', 'Zwak — voeg meer tekens toe.', 'Faible — ajoutez des caractères.');
  String get passwordFair => _s('Fair — add numbers or symbols.', 'ٹھیک — نمبر یا علامات شامل کریں۔', 'مقبول — أضف أرقاماً أو رموزاً.', 'Redelijk — voeg cijfers of symbolen toe.', 'Correct — ajoutez chiffres ou symboles.');
  String get passwordGood => _s('Good password.', 'اچھا پاس ورڈ۔', 'كلمة مرور جيدة.', 'Goed wachtwoord.', 'Bon mot de passe.');
  String get passwordStrong => _s('Strong password.', 'مضبوط پاس ورڈ۔', 'كلمة مرور قوية.', 'Sterk wachtwoord.', 'Mot de passe fort.');

  // ── Sleep ───────────────────────────────────────────────────────────────────
  String get sleepModeTitle => _s('Sleep Mode', 'نیند موڈ', 'وضع النوم', 'Slaapmodus', 'Mode veille');
  String get nightRoutine => _s('NIGHT ROUTINE', 'رات کا معمول', 'روتين الليل', 'NACHTROUTINE', 'ROUTINE NOCTURNE');
  String get restPeacefully => _s('Rest peacefully', 'پرامن آرام', 'ارتح peacefully', 'Rust vredig', 'Reposez-vous paisiblement');
  String get sleepHeroBody => _s(
        'All whispers pause during sleep. Your schedules resume automatically when sleep ends.',
        'نیند کے دوران تمام whispers رک جاتی ہیں۔ نیند ختم ہونے پر شیڈول خود بحال ہو جاتے ہیں۔',
        'تتوقف جميع الهمسات أثناء النوم. تستأنف الجداول تلقائياً عند الانتهاء.',
        'Alle whispers pauzeren tijdens slaap. Schema\'s hervatten automatisch.',
        'Tous les murmures s\'arrêtent pendant le sommeil. Les plannings reprennent automatiquement.',
      );
  String get duration => _s('DURATION', 'مدت', 'المدة', 'DUUR', 'DURÉE');
  String get startSleepMode => _s('Start Sleep Mode', 'نیند موڈ شروع', 'بدء وضع النوم', 'Slaapmodus starten', 'Démarrer mode veille');
  String get sleepTapHint =>
      _s('Tap to pause all whispers until you wake', 'جاگنے تک whispers روکنے کے لیے دبائیں', 'اضغط لإيقاف الهمسات حتى الاستيقاظ', 'Tik om whispers te pauzeren tot je wakker wordt', 'Appuyez pour pauser les murmures jusqu\'au réveil');
  String get sleepActive => _s('Sleep active', 'نیند فعال', 'النوم نشط', 'Slaap actief', 'Sommeil actif');
  String get endNow => _s('End now', 'اب ختم', 'إنهاء الآن', 'Nu beëindigen', 'Terminer maintenant');
  String get instantPause => _s('Instant pause', 'فوری وقفہ', 'إيقاف فوري', 'Direct pauzeren', 'Pause instantanée');
  String get instantPauseDesc =>
      _s('Whispers stop the moment sleep begins', 'نیند شروع ہوتے ہی whispers رک جati ہیں', 'تتوقف الهمسات عند بدء النوم', 'Whispers stoppen zodra slaap begint', 'Les murmures s\'arrêtent dès le début du sommeil');
  String get schedulesWait => _s('Schedules wait', 'شیڈول انتظار', 'الجداول تنتظر', 'Schema\'s wachten', 'Plannings en attente');
  String get schedulesWaitDesc =>
      _s('Everything resumes when you wake', 'جاگنے پر سب بحال', 'يستأنف كل شيء عند الاستيقاظ', 'Alles hervat bij wakker worden', 'Tout reprend au réveil');
  String get quietAlarms => _s('Quiet alarms', 'خاموش الارم', 'تنبيهات هادئة', 'Stille alarmen', 'Alarmes silencieuses');
  String get quietAlarmsDesc =>
      _s('No interruptions while you rest', 'آرام کے دوران کوئی رکاوٹ نہیں', 'لا مقاطعات أثناء الراحة', 'Geen onderbrekingen tijdens rust', 'Aucune interruption pendant le repos');

  String sleepModeUntil(String time) => _s('Sleep mode until $time', 'نیند موڈ $time تک', 'وضع النوم حتى $time', 'Slaapmodus tot $time', 'Mode veille jusqu\'à $time');
  String untilTime(String time) => _s('Until $time', '$time تک', 'حتى $time', 'Tot $time', 'Jusqu\'à $time');

  // ── Prayer ──────────────────────────────────────────────────────────────────
  String get prayerModeTitle => _s('Prayer Mode', 'نماز موڈ', 'وضع الصلاة', 'Gebedsmodus', 'Mode prière');
  String get faithAndFocus => _s('FAITH & FOCUS', 'ایمان اور توجہ', 'الإيمان والتركيز', 'GELOOF & FOCUS', 'FOI ET CONCENTRATION');
  String get pauseDuringPrayer => _s('Pause during prayer', 'نماز کے دوران وقفہ', 'إيقاف أثناء الصلاة', 'Pauzeren tijdens gebed', 'Pause pendant la prière');
  String get prayerHeroBody => _s(
        'Prayer times are calculated on your device using GPS. Coordinates never leave your phone.',
        'نماز کے اوقات GPS سے آپ کے فون پر حساب ہوتے ہیں۔ کوآرڈینیٹس فون سے باہر نہیں جاتے۔',
        'تُحسب أوقات الصلاة على جهازك بـ GPS. الإحداثيات لا تغادر هاتفك.',
        'Gebedstijden worden op je apparaat berekend met GPS. Coördinaten verlaten je telefoon nooit.',
        'Les heures de prière sont calculées sur votre appareil via GPS. Les coordonnées ne quittent jamais votre téléphone.',
      );
  String get onDevice => _s('On-device', 'ڈیوائس پر', 'على الجهاز', 'Op apparaat', 'Sur l\'appareil');
  String get onDeviceDesc => _s('All calculations stay on-device', 'تمام حساب ڈیوائس پر', 'جميع الحسابات على الجهاز', 'Alle berekeningen op apparaat', 'Tous les calculs sur l\'appareil');
  String get autoPause => _s('Auto pause', 'خودکار وقفہ', 'إيقاف تلقائي', 'Automatisch pauzeren', 'Pause automatique');
  String get autoPauseDesc =>
      _s('Whispers pause during each prayer', 'ہر نماز کے دوران whispers رکتی ہیں', 'تتوقف الهمسات أثناء كل صلاة', 'Whispers pauzeren tijdens elk gebed', 'Les murmures s\'arrêtent pendant chaque prière');
  String get calculationMethod => _s('Calculation method', 'حساب کا طریقہ', 'طريقة الحساب', 'Berekeningsmethode', 'Méthode de calcul');
  String get madhab => _s('Madhab', 'مذہب', 'المذهب', 'Madhab', 'Madhab');
  String get enablePrayerMode => _s('Enable prayer mode', 'نماز موڈ فعال', 'تفعيل وضع الصلاة', 'Gebedsmodus inschakelen', 'Activer mode prière');
  String get accurateTimes => _s('Accurate times', 'درست اوقات', 'أوقات دقيقة', 'Nauwkeurige tijden', 'Horaires précis');
  String get accurateTimesDesc =>
      _s('Based on your location', 'آپ کے مقام پر مبنی', 'بناءً على موقعك', 'Gebaseerd op je locatie', 'Basé sur votre position');
  String get autoPausePrayerDesc =>
      _s('Whispers resume after prayer', 'نماز کے بعد whispers بحال', 'تستأنف الهمسات بعد الصلاة', 'Whispers hervatten na gebed', 'Les murmures reprennent après la prière');
  String get asrMadhab => _s('Asr madhab', 'عصر مذہب', 'مذهب العصر', 'Asr-madhab', 'Madhab Asr');
  String get useGpsLocation => _s('Use GPS location', 'GPS مقام استعمال', 'استخدام موقع GPS', 'GPS-locatie gebruiken', 'Utiliser la position GPS');
  String get useGpsLocationDesc => _s(
        'Recommended for accurate prayer times',
        'درست نماز کے اوقات کے لیے تجویز',
        'موصى به لأوقات صلاة دقيقة',
        'Aanbevolen voor nauwkeurige gebedstijden',
        'Recommandé pour des heures de prière précises',
      );

  // ── Battery ─────────────────────────────────────────────────────────────────
  String get batteryTitle => _s('Battery', 'بیٹری', 'البطارية', 'Batterij', 'Batterie');
  String get batteryHeroTitle => _s('Keep WhisperBack running', 'WhisperBack چلتا رکھیں', 'أبق WhisperBack يعمل', 'Houd WhisperBack actief', 'Gardez WhisperBack actif');
  String get batteryHeroBody => _s(
        'Battery savers can delay whispers and miss schedules. Disable optimization for reliable playback.',
        'بیٹری سیور whispers اور شیڈول میں تاخیر کر سکتے ہیں۔ قابلِ اعتماد پلے بیک کے لیے optimization بند کریں۔',
        'قد تؤخر موفرات البطارية الهمسات والجداول. عطّل التحسين لتشغيل موثوق.',
        'Batterijspaarders kunnen whispers vertragen. Schakel optimalisatie uit voor betrouwbare weergave.',
        'Les économiseurs de batterie peuvent retarder les murmures. Désactivez l\'optimisation pour une lecture fiable.',
      );
  String get whyItMatters => _s('WHY IT MATTERS', 'کیوں اہم', 'لماذا يهم', 'WAAROM HET UITMAAKT', 'POURQUOI C\'EST IMPORTANT');
  String get oemGuides => _s('OEM guides', 'OEM گائیڈ', 'أدلة OEM', 'OEM-gidsen', 'Guides OEM');
  String get samsungGuide => _s('Samsung / One UI', 'Samsung / One UI', 'Samsung / One UI', 'Samsung / One UI', 'Samsung / One UI');
  String get xiaomiGuide => _s('Xiaomi / MIUI', 'Xiaomi / MIUI', 'Xiaomi / MIUI', 'Xiaomi / MIUI', 'Xiaomi / MIUI');
  String get huaweiGuide => _s('Huawei / EMUI', 'Huawei / EMUI', 'Huawei / EMUI', 'Huawei / EMUI', 'Huawei / EMUI');
  String get stockAndroidGuide => _s('Stock Android', 'Stock Android', 'Stock Android', 'Stock Android', 'Stock Android');
  String get reliableSchedules => _s('RELIABLE SCHEDULES', 'قابلِ اعتماد شیڈول', 'جداول موثوقة', 'BETROUWBARE SCHEMA\'S', 'PLANNINGS FIABLES');
  String get batteryWhitelistBody => _s(
        'Some phones limit background apps to save battery. Whitelisting WhisperBack helps scheduled whispers play on time.',
        'کچھ فونز بیٹری بچانے کے لیے پس منظر ایپس محدود کرتے ہیں۔ WhisperBack کو whitelist کرنے سے شیڈول whispers وقت پر چلتی ہیں۔',
        'بعض الهواتف تحد التطبيقات في الخلفية. إضافة WhisperBack للقائمة البيضاء يساعد الهمسات المجدولة.',
        'Sommige telefoons beperken achtergrondapps. WhisperBack whitelisten helpt geplande whispers op tijd.',
        'Certains téléphones limitent les apps en arrière-plan. Autoriser WhisperBack aide les murmures planifiés.',
      );
  String get onTimePlayback => _s('On-time playback', 'وقت پر پلے بیک', 'تشغيل في الوقت', 'Weergave op tijd', 'Lecture à l\'heure');
  String get onTimePlaybackDesc =>
      _s('Schedules fire when they should', 'شیڈول وقت پر چلتے ہیں', 'تعمل الجداول في وقتها', 'Schema\'s starten wanneer nodig', 'Les plannings se déclenchent à l\'heure');
  String get reliableAlarms => _s('Reliable alarms', 'قابلِ اعتماد الارم', 'تنبيهات موثوقة', 'Betrouwbare alarmen', 'Alarmes fiables');
  String get reliableAlarmsDesc =>
      _s('Notifications are not delayed', 'اطلاعات میں تاخیر نہیں', 'الإشعارات لا تتأخر', 'Meldingen worden niet vertraagd', 'Les notifications ne sont pas retardées');
  String get noDataCollection => _s('No data collection', 'ڈیٹا جمع نہیں', 'لا جمع للبيانات', 'Geen gegevensverzameling', 'Pas de collecte de données');
  String get noDataCollectionDesc => _s(
        'Only system battery settings change',
        'صرف سسٹم بیٹری ترتیبات بدلتی ہیں',
        'يتغير فقط إعدادات بطارية النظام',
        'Alleen systeem-batterijinstellingen wijzigen',
        'Seuls les paramètres batterie système changent',
      );
  String get byPhoneBrand => _s('BY PHONE BRAND', 'فون برانڈ کے لحاظ', 'حسب العلامة', 'PER MERK', 'PAR MARQUE');
  String get openSystemSettings =>
      _s('Open system settings', 'سسٹم ترتیبات کھولیں', 'فتح إعدادات النظام', 'Systeeminstellingen openen', 'Ouvrir les réglages système');
  String get openSystemSettingsSnack => _s(
        'Open system Settings → Apps → WhisperBack → Battery',
        'Settings → Apps → WhisperBack → Battery کھولیں',
        'افتح الإعدادات → التطبيقات → WhisperBack → البطارية',
        'Open Instellingen → Apps → WhisperBack → Batterij',
        'Ouvrez Réglages → Apps → WhisperBack → Batterie',
      );

  // ── Record / Import / New playlist ──────────────────────────────────────────
  String get recordTitle => _s('Record', 'ریکارڈ', 'تسجيل', 'Opnemen', 'Enregistrer');
  String get captureAWhisper => _s('CAPTURE A WHISPER', 'WHISPER ریکارڈ', 'التقاط همسة', 'WHISPER OPnemen', 'CAPTURER UN MURMURE');
  String get recordNewClip => _s('Record a new clip', 'نئی کلپ ریکارڈ', 'تسجيل مقطع جديد', 'Nieuwe clip opnemen', 'Enregistrer un nouveau clip');
  String get newRecording => _s('New recording', 'نئی ریکارڈنگ', 'تسجيل جديد', 'Nieuwe opname', 'Nouvel enregistrement');
  String get startRecording => _s('Start Recording', 'ریکارڈنگ شروع', 'بدء التسجيل', 'Opname starten', 'Commencer l\'enregistrement');
  String get stopAndSave => _s('Stop & Save', 'روکیں اور محفوظ', 'إيقاف وحفظ', 'Stoppen & opslaan', 'Arrêter et enregistrer');
  String get micPermissionRequired =>
      _s('Microphone permission required', 'مائیک کی اجازت درکار', 'إذن الميكروفون مطلوب', 'Microfoontoestemming vereist', 'Autorisation micro requise');
  String get micPermissionSnack =>
      _s('Microphone permission is required to record', 'ریکارڈ کے لیے مائیک کی اجازت ضروری', 'إذن الميكروفون مطلوب للتسجيل', 'Microfoontoestemming is vereist om op te nemen', 'L\'autorisation micro est requise pour enregistrer');
  String get recording => _s('Recording…', 'ریکارڈنگ…', 'جاري التسجيل…', 'Opnemen…', 'Enregistrement…');
  String get clipTitle => _s('Clip title', 'کلپ کا عنوان', 'عنوان المقطع', 'Cliptitel', 'Titre du clip');
  String get recordingCancelled => _s('Recording cancelled', 'ریکارڈنگ منسوخ', 'تم إلغاء التسجيل', 'Opname geannuleerd', 'Enregistrement annulé');
  String savedClip(String title) => _s('Saved $title', '$title محفوظ', 'تم حفظ $title', '$title opgeslagen', '$title enregistré');

  String get importTitle => _s('Import', 'درآمد', 'استيراد', 'Importeren', 'Importer');
  String get addAudio => _s('ADD AUDIO', 'آڈیو شامل', 'إضافة صوت', 'AUDIO TOEVOEGEN', 'AJOUTER AUDIO');
  String get importFromDevice => _s('Import from device', 'ڈیوائس سے درآمد', 'استيراد من الجهاز', 'Importeren van apparaat', 'Importer depuis l\'appareil');
  String get chooseAudioFile => _s('Choose audio file', 'آڈیو فائل منتخب', 'اختر ملفاً صوتياً', 'Kies audiobestand', 'Choisir un fichier audio');
  String get tapToBrowseAudio =>
      _s('Tap to browse MP3 or M4A on your device', 'MP3 یا M4A براؤز کرنے کے لیے دبائیں', 'اضغط لتصفح MP3 أو M4A', 'Tik om MP3 of M4A te bladeren', 'Appuyez pour parcourir MP3 ou M4A');
  String get audioFile => _s('Audio file', 'آڈیو فائل', 'ملف صوتي', 'Audiobestand', 'Fichier audio');
  String get importing => _s('Importing…', 'درآمد…', 'جاري الاستيراد…', 'Importeren…', 'Importation…');
  String get copyingFile => _s('Copying file into WhisperBack…', 'WhisperBack میں فائل کاپی…', 'نسخ الملف إلى WhisperBack…', 'Bestand kopiëren naar WhisperBack…', 'Copie du fichier dans WhisperBack…');
  String importedClip(String title) => _s('Imported $title', '$title درآمد', 'تم استيراد $title', '$title geïmporteerd', '$title importé');

  String get buildCollection => _s('BUILD A COLLECTION', 'مجموعہ بنائیں', 'بناء مجموعة', 'COLLECTIE BOUWEN', 'CRÉER UNE COLLECTION');
  String get createAPlaylist => _s('Create a playlist', 'پلے لسٹ بنائیں', 'إنشاء قائمة تشغيل', 'Afspeellijst maken', 'Créer une playlist');
  String get quickIdeas => _s('QUICK IDEAS', 'فوری آئیڈیاز', 'أفكار سريعة', 'SNELLE IDEEËN', 'IDÉES RAPIDES');
  String get creating => _s('Creating…', 'بن رہا…', 'جاري الإنشاء…', 'Maken…', 'Création…');
  String get playlistName => _s('Playlist name', 'پلے لسٹ کا نام', 'اسم القائمة', 'Naam afspeellijst', 'Nom de la playlist');
  String get playlistNameHint => _s('e.g. Morning Whispers', 'مثلاً Morning Whispers', 'مثلاً Morning Whispers', 'bijv. Morning Whispers', 'ex. Morning Whispers');
  String get afterCreatingHint => _s(
        'After creating, add clips from your library and set a schedule when you\'re ready.',
        'بنانے کے بعد لائبریری سے کلپس شامل کریں اور شیڈول سیٹ کریں۔',
        'بعد الإنشاء، أضف مقاطع من مكتبتك وحدد جدولاً.',
        'Voeg daarna clips toe uit je bibliotheek en stel een schema in.',
        'Ensuite, ajoutez des clips et définissez une planning.',
      );
  String get enterPlaylistName => _s('Enter a playlist name', 'پلے لسٹ کا نام درج کریں', 'أدخل اسم القائمة', 'Voer een naam in', 'Entrez un nom de playlist');
  String createdPlaylist(String name) => _s('Created $name', '$name بنائی', 'تم إنشاء $name', '$name gemaakt', '$name créée');
  String get ideaMorningWhispers => _s('Morning Whispers', 'Morning Whispers', 'Morning Whispers', 'Morning Whispers', 'Morning Whispers');
  String get ideaWorkFocus => _s('Work Focus', 'Work Focus', 'Work Focus', 'Work Focus', 'Work Focus');
  String get ideaEveningCalm => _s('Evening Calm', 'Evening Calm', 'Evening Calm', 'Evening Calm', 'Evening Calm');
  String get createPlaylistDescription => _s(
        'Group your whispers into a collection. Add clips and schedules after you create it.',
        'اپنی whispers مجموعے میں شامل کریں۔ بنانے کے بعد کلپس اور شیڈول شامل کریں۔',
        'اجمع همساتك في مجموعة. أضف المقاطع والجداول بعد الإنشاء.',
        'Groepeer whispers in een collectie. Voeg clips en schema\'s toe na het maken.',
        'Regroupez vos murmures. Ajoutez clips et plannings après la création.',
      );
  String get recordSpeakClearlyHint => _s(
        'Speak clearly into your microphone. Clips are saved locally on your device.',
        'مائیک میں واضح بولیں۔ کلپس آپ کے ڈیوائس پر محفوظ ہوتی ہیں۔',
        'تحدث بوضوح في الميكروفون. تُحفظ المقاطع محلياً على جهازك.',
        'Spreek duidelijk in je microfoon. Clips worden lokaal opgeslagen.',
        'Parlez clairement dans le micro. Les clips sont enregistrés localement.',
      );
  String get importBody => _s(
        'Import MP3 or M4A files from your device. Files are copied into the app for safe offline playback.',
        'MP3 یا M4A فائلیں درآمد کریں۔ فائلیں آف لائن پلے بیک کے لیے ایپ میں کاپی ہوتی ہیں۔',
        'استورد ملفات MP3 أو M4A. تُنسخ الملفات إلى التطبيق للتشغيل دون اتصال.',
        'Importeer MP3- of M4A-bestanden. Bestanden worden gekopieerd voor offline weergave.',
        'Importez des fichiers MP3 ou M4A. Les fichiers sont copiés pour une lecture hors ligne.',
      );
  String get importedClipsStayOnDevice => _s(
        'Imported clips stay on your device. Original files are not modified.',
        'درآمد شدہ کلپس آپ کے ڈیوائس پر رہتی ہیں۔ اصل فائلیں تبدیل نہیں ہوتیں۔',
        'تبقى المقاطع المستوردة على جهازك. الملفات الأصلية لا تُعدّل.',
        'Geïmporteerde clips blijven op je apparaat. Originele bestanden worden niet gewijzigd.',
        'Les clips importés restent sur votre appareil. Les fichiers originaux ne sont pas modifiés.',
      );

  // ── Duration / schedule helpers ─────────────────────────────────────────────
  String get zeroSec => _s('0 sec', '0 سیکنڈ', '0 ث', '0 sec', '0 s');
  String durationSec(int sec) => _s('$sec sec', '$sec سیکنڈ', '$sec ث', '$sec sec', '$sec s');
  String durationMin(int min) => _s('$min min', '$min منٹ', '$min د', '$min min', '$min min');
  String durationMinSec(int min, int sec) => _s('$min min $sec sec', '$min منٹ $sec سیکنڈ', '$min د $sec ث', '$min min $sec sec', '$min min $sec s');

  String intervalLabel(int minutes) {
    if (minutes >= 60 && minutes % 60 == 0) {
      final h = minutes ~/ 60;
      return h == 1 ? oneHour : hoursCount(h);
    }
    return durationMin(minutes);
  }

  String get oneHour => _s('1 hour', '1 گھنٹہ', 'ساعة واحدة', '1 uur', '1 heure');
  String hoursCount(int hours) => _s('$hours hours', '$hours گھنٹے', '$hours ساعات', '$hours uur', '$hours heures');

  List<String> get weekdayShortLabels => _lang == 'ar'
      ? const ['ن', 'ث', 'ر', 'خ', 'ج', 'س', 'ح']
      : _lang == 'ur'
          ? const ['پ', 'م', 'ب', 'ج', 'ج', 'ہ', 'ات']
          : _lang == 'nl'
              ? const ['M', 'D', 'W', 'D', 'V', 'Z', 'Z']
              : _lang == 'fr'
                  ? const ['L', 'M', 'M', 'J', 'V', 'S', 'D']
                  : const ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  String daysLabelFromMask(int daysMask) {
    if (daysMask == 127) return everyDay;
    if (daysMask == 31) return weekdays;
    if (daysMask == 96) return weekends;
    final parts = <String>[];
    final labels = weekdayShortLabels;
    for (var i = 0; i < 7; i++) {
      if ((daysMask & (1 << i)) != 0) parts.add(labels[i]);
    }
    return parts.join(_s(' · ', ' · ', ' · ', ' · ', ' · '));
  }
}

class _AppLocalizationsDelegate extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) =>
      AppLocalizations.supportedLocales.any((l) => l.languageCode == locale.languageCode);

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture(AppLocalizations(locale));
  }

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

extension AppLocalizationsContext on BuildContext {
  AppLocalizations get l10n => AppLocalizations.ofOrThrow(this);
}
