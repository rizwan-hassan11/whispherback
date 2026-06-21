import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

/// App-wide localized strings for English, Urdu, Arabic, Dutch, French, and
/// Vietnamese.
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
    Locale('vi'),
  ];

  static const delegate = _AppLocalizationsDelegate();

  String _s(String en, String ur, String ar, String nl, String fr, String vi) {
    switch (_lang) {
      case 'ur':
        return ur;
      case 'ar':
        return ar;
      case 'nl':
        return nl;
      case 'fr':
        return fr;
      case 'vi':
        return vi;
      default:
        return en;
    }
  }

  // ── Language names ──────────────────────────────────────────────────────────
  String get languageEnglish =>
      _s('English', 'انگریزی', 'الإنجليزية', 'Engels', 'Anglais', 'Tiếng Anh');
  String get languageUrdu =>
      _s('Urdu', 'اردو', 'الأردية', 'Urdu', 'Ourdou', 'Tiếng Urdu');
  String get languageArabic =>
      _s('Arabic', 'عربی', 'العربية', 'Arabisch', 'Arabe', 'Tiếng Ả Rập');
  String get languageDutch => _s('Dutch', 'ولندیزی', 'الهولندية', 'Nederlands',
      'Néerlandais', 'Tiếng Hà Lan');
  String get languageFrench =>
      _s('French', 'فرانسیسی', 'الفرنسية', 'Frans', 'Français', 'Tiếng Pháp');
  String get languageVietnamese => _s('Vietnamese', 'ویتنامی', 'الفيتنامية',
      'Vietnamees', 'Vietnamien', 'Tiếng Việt');

  String languageName(String code) => switch (code) {
        'ur' => languageUrdu,
        'ar' => languageArabic,
        'nl' => languageDutch,
        'fr' => languageFrench,
        'vi' => languageVietnamese,
        _ => languageEnglish,
      };

  // ── Navigation ──────────────────────────────────────────────────────────────
  String get navHome =>
      _s('Home', 'ہوم', 'الرئيسية', 'Home', 'Accueil', 'Trang chủ');
  String get navLists =>
      _s('Lists', 'لسٹیں', 'القوائم', 'Lijsten', 'Listes', 'Danh sách');
  String get navClips =>
      _s('Clips', 'کلپس', 'المقاطع', 'Clips', 'Clips', 'Đoạn ghi');
  String get navSchedule =>
      _s('Schedule', 'شیڈول', 'الجدول', 'Schema', 'Planning', 'Lịch');
  String get navSettings => _s('Settings', 'ترتیبات', 'الإعدادات',
      'Instellingen', 'Paramètres', 'Cài đặt');

  // ── Splash ──────────────────────────────────────────────────────────────────
  String get appTagline => _s(
        'Your Personalized Audio Whisperer',
        'آپ کا ذاتی آڈیو ساتھی',
        'مرافقك الصوتي الشخصي',
        'Jouw persoonlijke audio-whisperer',
        'Votre murmureur audio personnalisé',
        'Trợ lý âm thanh cá nhân của bạn',
      );

  // ── Common ──────────────────────────────────────────────────────────────────
  String get ok => _s('OK', 'ٹھیک', 'حسناً', 'OK', 'OK', 'OK');
  String get save =>
      _s('Save', 'محفوظ کریں', 'حفظ', 'Opslaan', 'Enregistrer', 'Lưu');
  String get cancel =>
      _s('Cancel', 'منسوخ کریں', 'إلغاء', 'Annuleren', 'Annuler', 'Hủy');
  String get edit =>
      _s('Edit', 'ترمیم', 'تعديل', 'Bewerken', 'Modifier', 'Sửa');
  String get play => _s('Play', 'چلائیں', 'تشغيل', 'Afspelen', 'Lire', 'Phát');
  String get pause =>
      _s('Pause', 'روکیں', 'إيقاف مؤقت', 'Pauzeren', 'Pause', 'Tạm dừng');
  String get stop =>
      _s('Stop', 'بند کریں', 'إيقاف', 'Stoppen', 'Arrêter', 'Dừng');
  String get create => _s('Create', 'بنائیں', 'إنشاء', 'Maken', 'Créer', 'Tạo');
  String get browse =>
      _s('Browse', 'براؤز کریں', 'تصفح', 'Bladeren', 'Parcourir', 'Duyệt');
  String get remove =>
      _s('Remove', 'ہٹائیں', 'إزالة', 'Verwijderen', 'Supprimer', 'Xóa');
  String get live =>
      _s('Live', 'لائیو', 'مباشر', 'Live', 'En direct', 'Trực tiếp');
  String get active =>
      _s('Active', 'فعال', 'نشط', 'Actief', 'Actif', 'Đang bật');
  String get paused =>
      _s('paused', 'رکا ہوا', 'متوقف', 'gepauzeerd', 'en pause', 'đã tạm dừng');
  String get playlist => _s('Playlist', 'پلے لسٹ', 'قائمة تشغيل',
      'Afspeellijst', 'Playlist', 'Danh sách phát');
  String get clipsUpper =>
      _s('CLIPS', 'کلپس', 'المقاطع', 'CLIPS', 'CLIPS', 'ĐOẠN GHI');
  String get yourClips => _s('YOUR CLIPS', 'آپ کی کلپس', 'مقاطعك', 'JOUW CLIPS',
      'VOS CLIPS', 'ĐOẠN GHI CỦA BẠN');
  String get yourSchedules => _s('YOUR SCHEDULES', 'آپ کے شیڈول', 'جداولك',
      'JOUW SCHEMA\'S', 'VOS PLANNINGS', 'LỊCH CỦA BẠN');

  // ── Settings ────────────────────────────────────────────────────────────────
  String get settings => _s('Settings', 'ترتیبات', 'الإعدادات', 'Instellingen',
      'Paramètres', 'Cài đặt');
  String get settingsSubtitle => _s(
      'Preferences & defaults',
      'ترجیحات اور ڈیفالٹ',
      'التفضيلات والافتراضيات',
      'Voorkeuren & standaard',
      'Préférences et valeurs par défaut',
      'Tùy chọn & mặc định');
  String get groupDisplay =>
      _s('Display', 'ڈسپلے', 'العرض', 'Weergave', 'Affichage', 'Hiển thị');
  String get groupSchedulesAlarms => _s(
      'Schedules & alarms',
      'شیڈول اور الارم',
      'الجداول والتنبيهات',
      'Schema\'s & alarmen',
      'Plannings et alarmes',
      'Lịch & báo thức');
  String get groupAccount =>
      _s('Account', 'اکاؤنٹ', 'الحساب', 'Account', 'Compte', 'Tài khoản');
  String get groupModes =>
      _s('Modes', 'موڈز', 'الأوضاع', 'Modi', 'Modes', 'Chế độ');
  String get groupDevice =>
      _s('Device', 'ڈیوائس', 'الجهاز', 'Apparaat', 'Appareil', 'Thiết bị');
  String get theme =>
      _s('Theme', 'تھیم', 'السمة', 'Thema', 'Thème', 'Giao diện');
  String get themeSubtitle => _s(
      'Light or dark appearance',
      'روشن یا تاریک ظاہری شکل',
      'المظهر الفاتح أو الداكن',
      'Lichte of donkere weergave',
      'Apparence claire ou sombre',
      'Giao diện sáng hoặc tối');
  String get light => _s('Light', 'روشن', 'فاتح', 'Licht', 'Clair', 'Sáng');
  String get dark => _s('Dark', 'تاریک', 'داكن', 'Donker', 'Sombre', 'Tối');
  String get auto => _s('Auto', 'خودکار', 'تلقائي', 'Auto', 'Auto', 'Tự động');
  String get showLabels => _s('Show labels', 'لیبل دکھائیں', 'إظهار التسميات',
      'Labels tonen', 'Afficher les libellés', 'Hiện nhãn');
  String get showLabelsSubtitle => _s(
        'Text under navigation icons',
        'نیویگیشن آئیکنز کے نیچے متن',
        'نص تحت أيقونات التنقل',
        'Tekst onder navigatiepictogrammen',
        'Texte sous les icônes de navigation',
        'Chữ dưới biểu tượng điều hướng',
      );
  String get language =>
      _s('Language', 'زبان', 'اللغة', 'Taal', 'Langue', 'Ngôn ngữ');
  String get languageSubtitle => _s(
        'App display language',
        'ایپ کی زبان',
        'لغة عرض التطبيق',
        'Weergavetaal van de app',
        'Langue d\'affichage de l\'app',
        'Ngôn ngữ hiển thị của ứng dụng',
      );
  String get chooseLanguage => _s('Choose language', 'زبان منتخب کریں',
      'اختر اللغة', 'Kies taal', 'Choisir la langue', 'Chọn ngôn ngữ');
  String get alarmsByDefault => _s(
      'Alarms by default',
      'ڈیفالٹ الارم',
      'تنبيهات افتراضياً',
      'Alarmen standaard',
      'Alarmes par défaut',
      'Báo thức mặc định');
  String get alarmsByDefaultSubtitle => _s(
        'New schedules notify when whispers are due',
        'نئے شیڈول سرگوشی کے وقت پر اطلاع دیں',
        'تُبلغ الجداول الجديدة عند موعد الهمسات',
        'Nieuwe schema\'s melden wanneer whispers klaar zijn',
        'Les nouveaux plannings notifient quand les murmures sont dus',
        'Lịch mới sẽ báo khi đến giờ phát lời thì thầm',
      );
  String get defaultInterval => _s(
      'Default interval',
      'ڈیفالٹ وقفہ',
      'الفاصل الافتراضي',
      'Standaardinterval',
      'Intervalle par défaut',
      'Khoảng cách mặc định');
  String get signIn => _s('Sign in', 'سائن ان', 'تسجيل الدخول', 'Inloggen',
      'Se connecter', 'Đăng nhập');
  String get signInSubtitle => _s(
      'Sync when cloud is enabled',
      'کلاؤڈ فعال ہونے پر مطابقت',
      'مزامنة عند تفعيل السحابة',
      'Synchroniseren wanneer cloud aan staat',
      'Synchroniser quand le cloud est activé',
      'Đồng bộ khi bật đám mây');
  String get createAccount => _s('Create account', 'اکاؤنٹ بنائیں',
      'إنشاء حساب', 'Account maken', 'Créer un compte', 'Tạo tài khoản');
  String get createAccountSettingsSubtitle => _s(
      'Backup clips and schedules',
      'کلپس اور شیڈول بیک اپ',
      'نسخ المقاطع والجداول احتياطياً',
      'Clips en schema\'s back-uppen',
      'Sauvegarder clips et plannings',
      'Sao lưu đoạn ghi và lịch');
  String get sleepMode => _s('Sleep mode', 'نیند موڈ', 'وضع النوم',
      'Slaapmodus', 'Mode veille', 'Chế độ ngủ');
  String get sleepModeSubtitle => _s(
      'Silence windows',
      'خاموشی کے اوقات',
      'نوافذ الصمت',
      'Stilteperiodes',
      'Fenêtres de silence',
      'Khung giờ im lặng');
  String get prayerMode => _s('Prayer mode', 'نماز موڈ', 'وضع الصلاة',
      'Gebedsmodus', 'Mode prière', 'Chế độ cầu nguyện');
  String get prayerModeSubtitle => _s(
      'Karachi method · GPS',
      'کراچی طریقہ · GPS',
      'طريقة كراتشي · GPS',
      'Karachi-methode · GPS',
      'Méthode Karachi · GPS',
      'Phương pháp Karachi · GPS');
  String get batteryOptimization => _s(
      'Battery optimization',
      'بیٹری آپٹیمائزیشن',
      'تحسين البطارية',
      'Batterijoptimalisatie',
      'Optimisation batterie',
      'Tối ưu hóa pin');
  String get batteryOptimizationSubtitle => _s(
      'Usually fixed with one Allow tap when you turn Active ON',
      'عام طور پر Active آن کرتے وقت ایک Allow سے ٹھیک ہو جاتا ہے',
      'يُصلح عادةً بضغطة سماح واحدة عند تفعيل الوضع النشط',
      'Meestal opgelost met één Toestaan bij Active AAN',
      'Se règle en général avec un Autoriser quand Actif est ON',
      'Thường chỉ cần một lần Cho phép khi bật Active');
  String get versionFooter => _s(
      'WhisperBack v1.0.0 · Local MVP',
      'WhisperBack v1.0.0 · Local MVP',
      'WhisperBack v1.0.0 · Local MVP',
      'WhisperBack v1.0.0 · Local MVP',
      'WhisperBack v1.0.0 · Local MVP',
      'WhisperBack v1.0.0 · Local MVP');

  String minutesBetweenWhispers(int minutes) => _s(
        '$minutes minutes between whispers',
        'سرگوشیوں کے درمیان $minutes منٹ',
        '$minutes دقيقة بين الهمسات',
        '$minutes minuten tussen whispers',
        '$minutes minutes entre les murmures',
        '$minutes phút giữa các lời thì thầm',
      );

  String minutesCount(int minutes) => _s(
      '$minutes minutes',
      '$minutes منٹ',
      '$minutes دقيقة',
      '$minutes minuten',
      '$minutes minutes',
      '$minutes phút');

  // ── Home ────────────────────────────────────────────────────────────────────
  String get goodMorning => _s('Good morning', 'صبح بخیر', 'صباح الخير',
      'Goedemorgen', 'Bonjour', 'Chào buổi sáng');
  String get goodAfternoon => _s('Good afternoon', 'دوپہر بخیر', 'مساء الخير',
      'Goedemiddag', 'Bon après-midi', 'Chào buổi chiều');
  String get goodEvening => _s('Good evening', 'شام بخیر', 'مساء الخير',
      'Goedenavond', 'Bonsoir', 'Chào buổi tối');
  String get createPlaylistToStart => _s(
        'Create a playlist to get started',
        'شروع کرنے کے لیے پلے لسٹ بنائیں',
        'أنشئ قائمة تشغيل للبدء',
        'Maak een afspeellijst om te beginnen',
        'Créez une playlist pour commencer',
        'Tạo danh sách phát để bắt đầu',
      );
  String get nextWhisper => _s('Next whisper', 'اگلی سرگوشی', 'الهمسة التالية',
      'Volgende whisper', 'Prochain murmure', 'Lời thì thầm tiếp theo');
  String get nextWhisperSample => _s(
        'Morning Whispers · ~30 min',
        'Morning Whispers · ~30 منٹ',
        'Morning Whispers · ~30 دقيقة',
        'Morning Whispers · ~30 min',
        'Morning Whispers · ~30 min',
        'Morning Whispers · ~30 phút',
      );
  String get sleepModeActive => _s(
      'Sleep mode active',
      'نیند موڈ فعال',
      'وضع النوم نشط',
      'Slaapmodus actief',
      'Mode veille actif',
      'Chế độ ngủ đang bật');
  String get prayerPauseActive => _s(
      'Prayer pause active',
      'نماز وقفہ فعال',
      'توقف الصلاة نشط',
      'Gebedspauze actief',
      'Pause prière active',
      'Tạm dừng cầu nguyện đang bật');
  String get activeWhispersPlaying => _s(
      'Active — whispers playing',
      'فعال — سرگوشیاں چل رہی ہیں',
      'نشط — الهمسات تعمل',
      'Actief — whispers spelen',
      'Actif — murmures en cours',
      'Đang bật — đang phát lời thì thầm');
  String get tapPowerToBegin => _s(
      'Tap power to begin',
      'شروع کرنے کے لیے پاور دبائیں',
      'اضغط على الزر للبدء',
      'Tik op power om te beginnen',
      'Appuyez sur power pour commencer',
      'Nhấn nút nguồn để bắt đầu');
  String get statPlaylists => _s('Playlists', 'پلے لسٹ', 'قوائم التشغيل',
      'Afspeellijsten', 'Playlists', 'Danh sách phát');
  String get statScheduled => _s(
      'Scheduled', 'شیڈول شدہ', 'مجدول', 'Gepland', 'Planifié', 'Đã lên lịch');
  String get statClips =>
      _s('Clips', 'کلپس', 'المقاطع', 'Clips', 'Clips', 'Đoạn ghi');

  String playlistsReady(int count) {
    if (count == 1) {
      return _s(
          '1 playlist ready to whisper',
          '1 پلے لسٹ سرگوشی کے لیے تیار',
          'قائمة واحدة جاهزة للهمس',
          '1 afspeellijst klaar om te whisperen',
          '1 playlist prête à murmurer',
          '1 danh sách phát sẵn sàng thì thầm');
    }
    return _s(
        '$count playlists ready to whisper',
        '$count پلے لسٹ سرگوشی کے لیے تیار',
        '$count قوائم جاهزة للهمس',
        '$count afspeellijsten klaar',
        '$count playlists prêtes à murmurer',
        '$count danh sách phát sẵn sàng thì thầm');
  }

  // ── Playlists ───────────────────────────────────────────────────────────────
  String get playlists => _s('Playlists', 'پلے لسٹ', 'قوائم التشغيل',
      'Afspeellijsten', 'Playlists', 'Danh sách phát');
  String get scheduled => _s(
      'Scheduled', 'شیڈول شدہ', 'مجدول', 'Gepland', 'Planifié', 'Đã lên lịch');
  String get yourLibrary => _s('Your library', 'آپ کی لائبریری', 'مكتبتك',
      'Jouw bibliotheek', 'Votre bibliothèque', 'Thư viện của bạn');
  String get addClips => _s('Add clips', 'کلپس شامل کریں', 'إضافة مقاطع',
      'Clips toevoegen', 'Ajouter des clips', 'Thêm đoạn ghi');
  String get newPlaylist => _s('New playlist', 'نئی پلے لسٹ', 'قائمة جديدة',
      'Nieuwe afspeellijst', 'Nouvelle playlist', 'Danh sách phát mới');
  String get noPlaylistsYet => _s(
      'No playlists yet',
      'ابھی کوئی پلے لسٹ نہیں',
      'لا توجد قوائم بعد',
      'Nog geen afspeellijsten',
      'Aucune playlist',
      'Chưa có danh sách phát');
  String get createPlaylist => _s(
      'Create playlist',
      'پلے لسٹ بنائیں',
      'إنشاء قائمة',
      'Afspeellijst maken',
      'Créer une playlist',
      'Tạo danh sách phát');
  String get renamePlaylist => _s(
      'Rename playlist',
      'پلے لسٹ کا نام بدلیں',
      'إعادة تسمية القائمة',
      'Afspeellijst hernoemen',
      'Renommer la playlist',
      'Đổi tên danh sách phát');
  String get deletePlaylist => _s(
      'Delete playlist',
      'پلے لسٹ حذف کریں',
      'حذف القائمة',
      'Afspeellijst verwijderen',
      'Supprimer la playlist',
      'Xóa danh sách phát');
  String get deletePlaylistConfirm => _s(
      'Delete this playlist? This cannot be undone.',
      'یہ پلے لسٹ حذف کریں؟ یہ واپس نہیں ہو سکتی۔',
      'حذف هذه القائمة؟ لا يمكن التراجع.',
      'Deze afspeellijst verwijderen? Dit kan niet ongedaan worden.',
      'Supprimer cette playlist ? Action irréversible.',
      'Xóa danh sách phát này? Không thể hoàn tác.');
  String get deletePlaylistBlocked => _s(
      'Disable the active schedule before deleting this playlist.',
      'حذف سے پہلے فعال شیڈول بند کریں۔',
      'عطّل الجدول النشط قبل الحذف.',
      'Schakel het actieve schema uit voordat je verwijdert.',
      'Désactivez la planification active avant de supprimer.',
      'Tắt lịch đang chạy trước khi xóa.');
  String get playlistDeleted => _s(
      'Playlist deleted',
      'پلے لسٹ حذف ہو گئی',
      'تم حذف القائمة',
      'Afspeellijst verwijderd',
      'Playlist supprimée',
      'Đã xóa danh sách phát');
  String get playlistRenamed => _s(
      'Playlist renamed',
      'نام تبدیل ہو گیا',
      'تمت إعادة التسمية',
      'Naam gewijzigd',
      'Playlist renommée',
      'Đã đổi tên');
  String get removeFromPlaylist => _s(
      'Remove from playlist',
      'پلے لسٹ سے ہٹائیں',
      'إزالة من القائمة',
      'Verwijderen uit afspeellijst',
      'Retirer de la playlist',
      'Xóa khỏi danh sách phát');
  String get selectClipsHint => _s(
      'Select clips to add',
      'شامل کرنے کے لیے کلپس منتخب کریں',
      'اختر المقاطع للإضافة',
      'Selecteer clips om toe te voegen',
      'Sélectionnez des clips à ajouter',
      'Chọn đoạn ghi để thêm');
  String get delete => _s(
      'Delete', 'حذف', 'حذف', 'Verwijderen', 'Supprimer', 'Xóa');
  String get deleteClip => _s(
      'Delete clip',
      'کلپ حذف کریں',
      'حذف المقطع',
      'Clip verwijderen',
      'Supprimer le clip',
      'Xóa đoạn ghi');
  String get deleteClipConfirm => _s(
      'Delete this clip permanently? It will be removed from all playlists.',
      'یہ کلپ مستقل حذف ہو گی؟ تمام پلے لسٹس سے ہٹ جائے گی۔',
      'حذف هذا المقطع نهائياً؟ سيُزال من جميع القوائم.',
      'Deze clip permanent verwijderen? Verwijderd uit alle afspeellijsten.',
      'Supprimer ce clip définitivement ? Retiré de toutes les playlists.',
      'Xóa vĩnh viễn đoạn ghi này? Sẽ bị gỡ khỏi mọi danh sách phát.');
  String get clipDeleted => _s(
      'Clip deleted',
      'کلپ حذف ہو گئی',
      'تم حذف المقطع',
      'Clip verwijderd',
      'Clip supprimé',
      'Đã xóa đoạn ghi');
  String get removeFromPlaylistConfirm => _s(
      'Remove from this playlist? The clip stays in your library.',
      'اس پلے لسٹ سے ہٹائیں؟ کلپ آپ کی لائبریری میں رہے گی۔',
      'إزالة من هذه القائمة؟ يبقى المقطع في مكتبتك.',
      'Uit deze afspeellijst verwijderen? De clip blijft in je bibliotheek.',
      'Retirer de cette playlist ? Le clip reste dans votre bibliothèque.',
      'Gỡ khỏi danh sách phát này? Đoạn ghi vẫn còn trong thư viện.');
  String get clipRemovedFromPlaylist => _s(
      'Clip removed from playlist',
      'کلپ پلے لسٹ سے ہٹا دی گئی',
      'تمت إزالة المقطع من القائمة',
      'Clip uit afspeellijst verwijderd',
      'Clip retiré de la playlist',
      'Đã gỡ đoạn ghi khỏi danh sách phát');
  String get dragToReorder => _s(
      'Hold and drag to reorder',
      'ترتیب بدلنے کے لیے دبائیں اور گھسیٹیں',
      'اضغط واسحب لإعادة الترتيب',
      'Houd ingedrukt en sleep om te sorteren',
      'Maintenez et glissez pour réorganiser',
      'Giữ và kéo để sắp xếp lại');
  String get rename => _s(
      'Rename', 'نام بدلیں', 'إعادة تسمية', 'Hernoemen', 'Renommer', 'Đổi tên');
  String get totalClips => _s('Total clips', 'کل کلپس', 'إجمالي المقاطع',
      'Totaal clips', 'Total clips', 'Tổng số đoạn ghi');
  String get shuffleOn => _s('Shuffle on', 'شفل آن', 'تشغيل عشوائي',
      'Shuffle aan', 'Lecture aléatoire activée', 'Bật phát ngẫu nhiên');
  String get shuffleOff => _s('Shuffle off', 'شفل آف', 'إيقاف العشوائي',
      'Shuffle uit', 'Lecture aléatoire désactivée', 'Tắt phát ngẫu nhiên');
  String get scheduledBadge => _s(
      'Scheduled', 'شیڈول شدہ', 'مجدول', 'Gepland', 'Planifié', 'Đã lên lịch');
  String get playAll => _s('Play all', 'سب چلائیں', 'تشغيل الكل',
      'Alles afspelen', 'Tout lire', 'Phát tất cả');
  String get scheduledActiveNow => _s(
      'Scheduled · Active now',
      'شیڈول · ابھی فعال',
      'مجدول · نشط الآن',
      'Gepland · Nu actief',
      'Planifié · Actif maintenant',
      'Đã lên lịch · Đang chạy');
  String get scheduledPlayback => _s(
      'Scheduled playback',
      'شیڈول پلے بیک',
      'تشغيل مجدول',
      'Geplande weergave',
      'Lecture planifiée',
      'Phát theo lịch');
  String get noClipsInPlaylist => _s(
      'No clips in this playlist',
      'اس پلے لسٹ میں کوئی کلپ نہیں',
      'لا مقاطع في هذه القائمة',
      'Geen clips in deze lijst',
      'Aucun clip dans cette playlist',
      'Không có đoạn ghi trong danh sách này');
  String get recordOrImportClips => _s(
      'Record or import clips, then add them here.',
      'کلپ ریکارڈ یا درآمد کریں، پھر یہاں شامل کریں۔',
      'سجّل أو استورد مقاطع ثم أضفها هنا.',
      'Neem op of importeer clips en voeg ze hier toe.',
      'Enregistrez ou importez des clips, puis ajoutez-les ici.',
      'Ghi âm hoặc nhập đoạn ghi, rồi thêm vào đây.');
  String get browseClips => _s(
      'Browse clips',
      'کلپس براؤز کریں',
      'تصفح المقاطع',
      'Clips bladeren',
      'Parcourir les clips',
      'Duyệt đoạn ghi');
  String get selectClipsForPlaylist => _s(
        'Select clips to add to this playlist',
        'اس پلے لسٹ میں شامل کرنے کے لیے کلپس منتخب کریں',
        'اختر المقاطع لإضافتها إلى هذه القائمة',
        'Selecteer clips voor deze afspeellijst',
        'Sélectionnez les clips à ajouter à cette playlist',
        'Chọn đoạn ghi để thêm vào danh sách phát này',
      );
  String get added =>
      _s('Added', 'شامل', 'مضاف', 'Toegevoegd', 'Ajouté', 'Đã thêm');
  String get done => _s('Done', 'مکمل', 'تم', 'Klaar', 'Terminé', 'Xong');
  String get recordOrImportFirst => _s(
        'Record or import a clip first, then add it to your playlist.',
        'پہلے کلپ ریکارڈ یا درآمد کریں، پھر پلے لسٹ میں شامل کریں۔',
        'سجّل أو استورد مقطعاً أولاً، ثم أضفه إلى قائمتك.',
        'Neem eerst een clip op of importeer er een.',
        'Enregistrez ou importez un clip, puis ajoutez-le à votre playlist.',
        'Hãy ghi âm hoặc nhập một đoạn ghi trước, rồi thêm vào danh sách phát.',
      );
  String clipsAddedToPlaylist(int count, String playlist) => _s(
        '$count clip${count == 1 ? '' : 's'} added to $playlist',
        '$count کلپ $playlist میں شامل',
        'تمت إضافة $count مقطع إلى $playlist',
        '$count clip${count == 1 ? '' : 's'} toegevoegd aan $playlist',
        '$count clip${count == 1 ? '' : 's'} ajouté${count == 1 ? '' : 's'} à $playlist',
        'Đã thêm $count đoạn ghi vào $playlist',
      );
  String addClipsCount(int count) => _s(
        'Add $count clip${count == 1 ? '' : 's'}',
        '$count کلپ شامل کریں',
        'إضافة $count مقطع',
        '$count clip${count == 1 ? '' : 's'} toevoegen',
        'Ajouter $count clip${count == 1 ? '' : 's'}',
        'Thêm $count đoạn ghi',
      );
  String get scheduleSavedTurnActive => _s(
        'Schedule saved. Turn the app Active on Home to start whispers.',
        'شیڈول محفوظ۔ سرگوشیاں شروع کرنے کے لیے ہوم پر ایپ فعال کریں۔',
        'تم حفظ الجدول. فعّل التطبيق من الرئيسية لبدء الهمس.',
        'Schema opgeslagen. Zet de app op Actief op Home.',
        'Planning enregistrée. Activez l\'app sur l\'accueil pour démarrer.',
        'Đã lưu lịch. Bật ứng dụng ở Trang chủ để bắt đầu phát.',
      );
  String get scheduleRemoved => _s(
        'Schedule removed.',
        'شیڈول ہٹا دیا گیا۔',
        'تمت إزالة الجدول.',
        'Schema verwijderd.',
        'Planification supprimée.',
        'Đã xoá lịch.',
      );

  String clipCountLabel(int count) => _s(
        '$count clip${count == 1 ? '' : 's'}',
        '$count کلپ',
        '$count مقطع',
        '$count clip${count == 1 ? '' : 's'}',
        '$count clip${count == 1 ? '' : 's'}',
        '$count đoạn ghi',
      );

  String clipsInOrder(int count) => _s(
        '$count clip${count == 1 ? '' : 's'} in order',
        '$count کلپ ترتیب سے',
        '$count مقطع بالترتيب',
        '$count clip${count == 1 ? '' : 's'} op volgorde',
        '$count clip${count == 1 ? '' : 's'} dans l\'ordre',
        '$count đoạn ghi theo thứ tự',
      );

  String collectionsSummary(int collections, int clips) => _s(
        '$collections collections · $clips clips',
        '$collections مجموعے · $clips کلپس',
        '$collections مجموعات · $clips مقاطع',
        '$collections collecties · $clips clips',
        '$collections collections · $clips clips',
        '$collections bộ sưu tập · $clips đoạn ghi',
      );

  String scheduleStartsEvery(String time, String interval) => _s(
        'Starts $time · every $interval',
        '$time سے شروع · ہر $interval',
        'يبدأ $time · كل $interval',
        'Start $time · elke $interval',
        'Démarre $time · toutes les $interval',
        'Bắt đầu $time · mỗi $interval',
      );

  // ── Clips ───────────────────────────────────────────────────────────────────
  String get clipLibrary => _s('Clip Library', 'کلپ لائبریری', 'مكتبة المقاطع',
      'Clipbibliotheek', 'Bibliothèque de clips', 'Thư viện đoạn ghi');
  String get record =>
      _s('Record', 'ریکارڈ', 'تسجيل', 'Opnemen', 'Enregistrer', 'Ghi âm');
  String get import =>
      _s('Import', 'درآمد', 'استيراد', 'Importeren', 'Importer', 'Nhập');
  String get all => _s('All', 'سب', 'الكل', 'Alles', 'Tout', 'Tất cả');
  String get recorded =>
      _s('Recorded', 'ریکارڈ شدہ', 'مسجل', 'Opgenomen', 'Enregistré', 'Đã ghi');
  String get imported => _s(
      'Imported', 'درآمد شدہ', 'مستورد', 'Geïmporteerd', 'Importé', 'Đã nhập');
  String get noClipsYet => _s('No clips yet', 'ابھی کوئی کلپ نہیں',
      'لا مقاطع بعد', 'Nog geen clips', 'Aucun clip', 'Chưa có đoạn ghi');
  String get noClipsEmptyHint => _s(
        'Record a whisper or import an audio file to get started.',
        'شروع کرنے کے لیے سرگوشی ریکارڈ کریں یا آڈیو درآمد کریں۔',
        'سجّل همسة أو استورد ملفاً صوتياً للبدء.',
        'Neem een whisper op of importeer een audiobestand om te beginnen.',
        'Enregistrez un murmure ou importez un fichier audio pour commencer.',
        'Ghi một lời thì thầm hoặc nhập tệp âm thanh để bắt đầu.',
      );
  String get noRecordedClips => _s(
      'No recorded clips',
      'کوئی ریکارڈ شدہ کلپ نہیں',
      'لا مقاطع مسجلة',
      'Geen opgenomen clips',
      'Aucun clip enregistré',
      'Không có đoạn ghi nào');
  String get noImportedClips => _s(
      'No imported clips',
      'کوئی درآمد شدہ کلپ نہیں',
      'لا مقاطع مستوردة',
      'Geen geïmporteerde clips',
      'Aucun clip importé',
      'Không có đoạn ghi đã nhập');

  String clipsSummary(int count, String duration) => _s(
        '$count clip${count == 1 ? '' : 's'} · $duration total',
        '$count کلپ · کل $duration',
        '$count مقطع · $duration إجمالي',
        '$count clip${count == 1 ? '' : 's'} · $duration totaal',
        '$count clip${count == 1 ? '' : 's'} · $duration au total',
        '$count đoạn ghi · tổng $duration',
      );

  String filterLabel(String name, int count) => '$name · $count';

  String itemsCount(int count) => _s(
        '$count item${count == 1 ? '' : 's'}',
        '$count آئٹم',
        '$count عنصر',
        '$count item${count == 1 ? '' : 's'}',
        '$count élément${count == 1 ? '' : 's'}',
        '$count mục',
      );

  // ── Schedule overview ───────────────────────────────────────────────────────
  String get schedules =>
      _s('Schedules', 'شیڈول', 'الجداول', 'Schema\'s', 'Plannings', 'Lịch');
  String get noSchedulesYet => _s(
      'No whispers scheduled yet',
      'ابھی کوئی سرگوشی شیڈول نہیں',
      'لا همسات مجدولة بعد',
      'Nog geen whispers gepland',
      'Aucun murmure planifié',
      'Chưa có lời thì thầm nào được lên lịch');
  String get planYourWhispers => _s(
      'Plan your whispers',
      'اپنی سرگوشیاں پلان کریں',
      'خطط لهمساتك',
      'Plan je whispers',
      'Planifiez vos murmures',
      'Lên kế hoạch cho lời thì thầm');
  String get alarms =>
      _s('Alarms', 'الارم', 'تنبيهات', 'Alarmen', 'Alarmes', 'Báo thức');
  String get next =>
      _s('Next', 'اگلا', 'التالي', 'Volgende', 'Suivant', 'Tiếp theo');
  String get previousTrack => _s(
      'Previous track',
      'پچھلا ٹریک',
      'المسار السابق',
      'Vorige track',
      'Piste précédente',
      'Bài trước');
  String get nextTrack => _s(
      'Next track',
      'اگلا ٹریک',
      'المسار التالي',
      'Volgende track',
      'Piste suivante',
      'Bài tiếp');
  String get playAdhanTitle => _s(
      'Play adhan voice',
      'اذان کی آواز چلائیں',
      'تشغيل صوت الأذان',
      'Adhan-stem afspelen',
      "Jouer l'adhan",
      'Phát giọng adhan');
  String get playAdhanSubtitle => _s(
      'Plays the call to prayer at each prayer time',
      'ہر نماز کے وقت پر اذان چلتی ہے',
      'يشغّل الأذان عند كل وقت صلاة',
      'Speelt de oproep tot gebed bij elke gebedstijd',
      "Joue l'appel à la prière à chaque heure",
      'Phát lời gọi cầu nguyện vào mỗi giờ cầu nguyện');
  String prayerNotificationBody(String prayer) => _s(
      'It is time for $prayer',
      '$prayer کا وقت ہو گیا ہے',
      'حان وقت صلاة $prayer',
      'Het is tijd voor $prayer',
      "C'est l'heure de $prayer",
      'Đã đến giờ $prayer');
  String get customizeSchedule => _s(
      'Customize schedule',
      'شیڈول حسبِ منشا',
      'تخصيص الجدول',
      'Schema aanpassen',
      'Personnaliser le planning',
      'Tùy chỉnh lịch');
  String get customizeScheduleSubtitle => _s(
      'Times, intervals, days & alarms',
      'اوقات، وقفے، دن اور الارم',
      'الأوقات والفواصل والأيام والتنبيهات',
      'Tijden, intervallen, dagen & alarmen',
      'Horaires, intervalles, jours et alarmes',
      'Giờ, khoảng cách, ngày & báo thức');
  String get alarmOn => _s('Alarm on', 'الارم آن', 'تنبيه مفعّل', 'Alarm aan',
      'Alarme activée', 'Bật báo thức');
  String get shuffle =>
      _s('Shuffle', 'شفل', 'عشوائي', 'Shuffle', 'Aléatoire', 'Ngẫu nhiên');
  String get nextWhisperIn => _s(
      'Next whisper in ',
      'اگلی سرگوشی ',
      'الهمسة التالية خلال ',
      'Volgende whisper over ',
      'Prochain murmure dans ',
      'Lời thì thầm tiếp theo sau ');

  // ── Schedule builder ────────────────────────────────────────────────────────
  String get customize => _s('Customize', 'حسبِ منشا', 'تخصيص', 'Aanpassen',
      'Personnaliser', 'Tùy chỉnh');
  String get setWhenWhispersPlay => _s(
        'Set when whispers play and how often',
        'طے کریں سرگوشیاں کب اور کتنی بار چلیں',
        'حدد متى تعمل الهمسات ومدى تكرارها',
        'Stel in wanneer whispers spelen en hoe vaak',
        'Définissez quand et à quelle fréquence les murmures jouent',
        'Đặt thời điểm và tần suất phát lời thì thầm',
      );
  String get timeWindow => _s('Time window', 'وقت کی مدت', 'نافذة الوقت',
      'Tijdvenster', 'Fenêtre horaire', 'Khung giờ');
  String get startTime => _s('Start time', 'شروع کا وقت', 'وقت البدء',
      'Starttijd', 'Heure de début', 'Giờ bắt đầu');
  String get endTime => _s('End time', 'اختتام کا وقت', 'وقت الانتهاء',
      'Eindtijd', 'Heure de fin', 'Giờ kết thúc');
  String get noEnd => _s('No end', 'بغیر اختتام', 'بدون نهاية', 'Geen einde',
      'Sans fin', 'Không kết thúc');
  String get repeatDays => _s('Repeat days', 'دہرانے کے دن', 'أيام التكرار',
      'Herhalingsdagen', 'Jours de répétition', 'Ngày lặp lại');
  String get everyDay => _s(
      'Every day', 'ہر روز', 'كل يوم', 'Elke dag', 'Chaque jour', 'Mỗi ngày');
  String get weekdays => _s('Weekdays', 'ہفتے کے دن', 'أيام الأسبوع',
      'Weekdagen', 'Jours ouvrables', 'Ngày trong tuần');
  String get weekends => _s('Weekends', 'ویک اینڈ', 'عطلة نهاية الأسبوع',
      'Weekenden', 'Week-ends', 'Cuối tuần');
  String get intervalBetweenWhispers => _s(
      'Interval between whispers',
      'سرگوشیوں کے درمیان وقفہ',
      'الفاصل بين الهمسات',
      'Interval tussen whispers',
      'Intervalle entre les murmures',
      'Khoảng cách giữa các lời thì thầm');
  String get playbackAndAlarms => _s(
      'Playback & alarms',
      'پلے بیک اور الارم',
      'التشغيل والتنبيهات',
      'Weergave & alarmen',
      'Lecture et alarmes',
      'Phát & báo thức');
  String get shuffleClips => _s(
      'Shuffle clips',
      'کلپس شفل',
      'تشغيل عشوائي للمقاطع',
      'Clips shufflen',
      'Lecture aléatoire des clips',
      'Phát ngẫu nhiên đoạn ghi');
  String get shuffleClipsSubtitle => _s(
      'Random order within playlist',
      'پلے لسٹ میں بے ترتیب',
      'ترتيب عشوائي داخل القائمة',
      'Willekeurige volgorde in lijst',
      'Ordre aléatoire dans la playlist',
      'Thứ tự ngẫu nhiên trong danh sách');
  String get alarmNotification => _s(
      'Alarm notification',
      'الارم اطلاع',
      'إشعار التنبيه',
      'Alarmmelding',
      'Notification d\'alarme',
      'Thông báo báo thức');
  String get alarmNotificationSubtitle => _s(
      'Notify when each whisper is due',
      'ہر سرگوشی کے وقت پر اطلاع',
      'أبلغ عند موعد كل همسة',
      'Melden wanneer elke whisper klaar is',
      'Notifier quand chaque murmure est dû',
      'Báo khi đến giờ mỗi lời thì thầm');
  String get saveSchedule => _s('Save Schedule', 'شیڈول محفوظ کریں',
      'حفظ الجدول', 'Schema opslaan', 'Enregistrer le planning', 'Lưu lịch');
  String get scheduleSaved => _s(
      'Schedule saved',
      'شیڈول محفوظ',
      'تم حفظ الجدول',
      'Schema opgeslagen',
      'Planning enregistrée',
      'Đã lưu lịch');
  String get scheduleSavedWithAlarm => _s(
      'Schedule saved with alarm',
      'الارم کے ساتھ شیڈول محفوظ',
      'تم الحفظ مع التنبيه',
      'Schema opgeslagen met alarm',
      'Planning enregistrée avec alarme',
      'Đã lưu lịch kèm báo thức');
  String get scheduleConflict => _s(
      'Schedule conflict',
      'شیڈول تنازع',
      'تعارض في الجدول',
      'Schemaconflict',
      'Conflit de planning',
      'Lịch bị trùng');

  String scheduleConflictMessage(String name) => _s(
        'This overlaps with "$name". Adjust the start time or interval.',
        'یہ "$name" سے اوورلیپ ہے۔ شروع کا وقت یا وقفہ تبدیل کریں۔',
        'يتداخل مع "$name". عدّل وقت البدء أو الفاصل.',
        'Dit overlapt met "$name". Pas starttijd of interval aan.',
        'Chevauche "$name". Ajustez l\'heure de début ou l\'intervalle.',
        'Trùng với "$name". Hãy chỉnh giờ bắt đầu hoặc khoảng cách.',
      );

  // ── Playback ────────────────────────────────────────────────────────────────
  String get nowPlaying => _s('Now playing', 'اب چل رہا', 'يعمل الآن',
      'Nu aan het spelen', 'En lecture', 'Đang phát');
  String get scheduledWhisper => _s(
      'Scheduled whisper',
      'شیڈول سرگوشی',
      'همسة مجدولة',
      'Geplande whisper',
      'Murmure planifié',
      'Lời thì thầm theo lịch');
  String get libraryPreview => _s(
      'Library preview',
      'لائبریری پیش نظارہ',
      'معاينة المكتبة',
      'Bibliotheekvoorbeeld',
      'Aperçu bibliothèque',
      'Xem thử thư viện');
  String get tapToOpenApp => _s(
      'Tap to open WhisperBack',
      'WhisperBack کھولنے کے لیے ٹیپ کریں',
      'اضغط لفتح WhisperBack',
      'Tik om WhisperBack te openen',
      'Appuyez pour ouvrir WhisperBack',
      'Chạm để mở WhisperBack');
  String get genericErrorTryAgain => _s(
      'Something went wrong. Please try again.',
      'کچھ غلط ہوا۔ دوبارہ کوشش کریں۔',
      'حدث خطأ. يرجى المحاولة مرة أخرى.',
      'Er ging iets mis. Probeer opnieuw.',
      'Une erreur est survenue. Réessayez.',
      'Đã xảy ra lỗi. Vui lòng thử lại.');
  String get loadContentFailed => _s(
      'Couldn\'t load content',
      'مواد لوڈ نہیں ہو سکا',
      'تعذّر تحميل المحتوى',
      'Inhoud laden mislukt',
      'Impossible de charger le contenu',
      'Không tải được nội dung');
  String get importFailed => _s(
      'Import failed',
      'درآمد ناکام',
      'فشل الاستيراد',
      'Importeren mislukt',
      'Échec de l\'importation',
      'Nhập thất bại');
  String get importInvalidFormat => _s(
      'Only MP3 and M4A audio files are supported.',
      'صرف MP3 اور M4A فائلیں سپورٹ ہیں۔',
      'يُدعم MP3 و M4A فقط.',
      'Alleen MP3- en M4A-bestanden worden ondersteund.',
      'Seuls les fichiers MP3 et M4A sont pris en charge.',
      'Chỉ hỗ trợ tệp MP3 và M4A.');
  String get recordingFailed => _s(
      'Recording failed. Check storage space and try again.',
      'ریکارڈنگ ناکام۔ اسٹوریج چیک کریں اور دوبارہ کوشش کریں۔',
      'فشل التسجيل. تحقق من المساحة وحاول مرة أخرى.',
      'Opnemen mislukt. Controleer opslag en probeer opnieuw.',
      'Échec de l\'enregistrement. Vérifiez l\'espace et réessayez.',
      'Ghi âm thất bại. Kiểm tra bộ nhớ và thử lại.');
  String get retry =>
      _s('Try again', 'دوبارہ کوشش', 'حاول مجدداً', 'Opnieuw', 'Réessayer', 'Thử lại');
  String get today =>
      _s('Today', 'آج', 'اليوم', 'Vandaag', 'Aujourd\'hui', 'Hôm nay');
  String get yesterday =>
      _s('Yesterday', 'کل', 'أمس', 'Gisteren', 'Hier', 'Hôm qua');
  String daysAgo(int days) => _s(
      '${days}d ago',
      '$days دن پہلے',
      'منذ $days ي',
      '$days d geleden',
      'Il y a $days j',
      '$days ngày trước');
  String get audioServiceUnavailableTitle => _s(
      'Background audio unavailable',
      'پس منظر آڈیو دستیاب نہیں',
      'الصوت في الخلفية غير متاح',
      'Achtergrondaudio niet beschikbaar',
      'Audio arrière-plan indisponible',
      'Không có audio nền');
  String get audioServiceUnavailableBanner => _s(
      'Restart the app for reliable schedules and lock-screen controls.',
      'قابل اعتماد شیڈول کے لیے ایپ دوبارہ شروع کریں۔',
      'أعد تشغيل التطبيق للجدولة الموثوقة.',
      'Herstart de app voor betrouwbare planning.',
      'Redémarrez l\'app pour une planification fiable.',
      'Khởi động lại app để lên lịch ổn định.');
  String get audioServiceUnavailableBody => _s(
      'WhisperBack could not start its audio service. Close the app completely and open it again. Scheduled whispers need this to play reliably in the background.',
      'WhisperBack آڈیو سروس شروع نہیں ہو سکی۔ ایپ بند کر کے دوبارہ کھولیں۔',
      'تعذّر بدء خدمة الصوت. أغلق التطبيق تماماً وأعد فتحه.',
      'Audioservice startte niet. Sluit de app volledig en open opnieuw.',
      'Le service audio n\'a pas démarré. Fermez complètement l\'app et rouvrez.',
      'Không khởi động được dịch vụ audio. Đóng hẳn app rồi mở lại.');
  String get activeRequiresAudioService => _s(
      'Turning Active on requires background audio. Restart the app and try again.',
      'فعال کرنے کے لیے پس منظر آڈیو چاہیے۔ ایپ دوبارہ شروع کریں۔',
      'تفعيل الوضع النشط يتطلب الصوت في الخلفية. أعد تشغيل التطبيق.',
      'Actief vereist achtergrondaudio. Herstart de app.',
      'Actif nécessite l\'audio arrière-plan. Redémarrez l\'app.',
      'Bật Active cần audio nền. Khởi động lại app.');
  String get notificationActiveTitle => _s(
      'WhisperBack is active',
      'WhisperBack فعال ہے',
      'WhisperBack نشط',
      'WhisperBack is actief',
      'WhisperBack est actif',
      'WhisperBack đang bật');
  String notificationSchedulesArmed(int count) => _s(
      '$count schedule(s) armed · whispers will play automatically',
      '$count شیڈول تیار · سرگوشیاں خود چلیں گی',
      '$count جدول(ات) جاهزة · ستُشغّل الهمسات تلقائياً',
      '$count planning(en) actief · whispers spelen automatisch',
      '$count planning(s) armée(s) · lecture automatique',
      '$count lịch sẵn sàng · tự động phát');
  String get notificationActiveBodyIdle => _s(
      'Listening for your scheduled whispers',
      'آپ کی شیڈول سرگوشیاں سن رہا ہے',
      'بانتظار همساتك المجدولة',
      'Luistert naar geplande whispers',
      'En attente de vos murmures planifiés',
      'Đang chờ lời thì thầm theo lịch');
  String notificationScheduledReady(String name) => _s(
      '"$name" is ready to play',
      '"$name" چلنے کے لیے تیار',
      '"$name" جاهز للتشغيل',
      '"$name" is klaar om te spelen',
      '"$name" est prêt à jouer',
      '"$name" sẵn sàng phát');
  String notificationNextUpcoming(String name, String time) => _s(
      'Next: "$name" at $time',
      'اگلا: "$name" $time پر',
      'التالي: "$name" الساعة $time',
      'Volgende: "$name" om $time',
      'Suivant : "$name" à $time',
      'Tiếp theo: "$name" lúc $time');
  String get authComingSoon => _s(
      'Cloud sign-in coming in a future update. The app works fully offline today.',
      'کلاؤڈ سائن ان مستقبل میں۔ ایپ آج مکمل آف لائن کام کرتی ہے۔',
      'تسجيل الدخول السحابي قادم لاحقاً. التطبيق يعمل دون اتصال اليوم.',
      'Cloud-inloggen komt later. De app werkt nu volledig offline.',
      'Connexion cloud bientôt. L\'app fonctionne hors ligne aujourd\'hui.',
      'Đăng nhập đám mây sẽ có sau. App hoạt động offline đầy đủ.');
  String get minimizePlayer => _s(
      'Minimize player',
      'پلیئر چھوٹا کریں',
      'تصغير المشغّل',
      'Speler minimaliseren',
      'Réduire le lecteur',
      'Thu nhỏ trình phát');
  String get stopPlayback => _s('Stop playback', 'پلے بیک بند کریں',
      'إيقاف التشغيل', 'Weergave stoppen', 'Arrêter la lecture', 'Dừng phát');
  String get toggleShuffle => _s(
      'Toggle shuffle',
      'شفل تبدیل کریں',
      'تبديل العشوائي',
      'Shuffle wisselen',
      'Basculer aléatoire',
      'Bật/tắt phát ngẫu nhiên');

  // ── Auth ────────────────────────────────────────────────────────────────────
  String get welcomeBack => _s('Welcome back', 'خوش آمدید', 'مرحباً بعودتك',
      'Welkom terug', 'Bon retour', 'Chào mừng trở lại');
  String get signInPageSubtitle => _s(
        'Sign in to sync your whispers across every device.',
        'ہر ڈیوائس پر سرگوشیاں مطابقت کے لیے سائن ان کریں۔',
        'سجّل الدخول لمزامنة همساتك على كل جهاز.',
        'Log in om whispers op elk apparaat te synchroniseren.',
        'Connectez-vous pour synchroniser vos murmures sur tous les appareils.',
        'Đăng nhập để đồng bộ lời thì thầm trên mọi thiết bị.',
      );
  String get secure =>
      _s('Secure', 'محفوظ', 'آمن', 'Veilig', 'Sécurisé', 'An toàn');
  String get cloudSync => _s('Cloud sync', 'کلاؤڈ مطابقت', 'مزامنة سحابية',
      'Cloudsync', 'Sync cloud', 'Đồng bộ đám mây');
  String get private =>
      _s('Private', 'نجی', 'خاص', 'Privé', 'Privé', 'Riêng tư');
  String get emailAddress => _s('Email address', 'ای میل', 'البريد الإلكتروني',
      'E-mailadres', 'Adresse e-mail', 'Địa chỉ email');
  String get emailHint => _s(
      'you@example.com',
      'you@example.com',
      'you@example.com',
      'you@example.com',
      'you@example.com',
      'you@example.com');
  String get password => _s('Password', 'پاس ورڈ', 'كلمة المرور', 'Wachtwoord',
      'Mot de passe', 'Mật khẩu');
  String get passwordHint => _s('Your password', 'آپ کا پاس ورڈ', 'كلمة مرورك',
      'Je wachtwoord', 'Votre mot de passe', 'Mật khẩu của bạn');
  String get forgotPassword => _s(
      'Forgot password?',
      'پاس ورڈ بھول گئے؟',
      'نسيت كلمة المرور؟',
      'Wachtwoord vergeten?',
      'Mot de passe oublié ?',
      'Quên mật khẩu?');
  String get signInButton => _s('Sign In', 'سائن ان', 'تسجيل الدخول',
      'Inloggen', 'Se connecter', 'Đăng nhập');
  String get dontHaveAccount => _s(
      "Don't have an account? ",
      'اکاؤنٹ نہیں؟ ',
      'ليس لديك حساب؟ ',
      'Geen account? ',
      'Pas de compte ? ',
      'Chưa có tài khoản? ');
  String get signUpFree => _s('Sign up free', 'مفت سائن اپ', 'سجّل مجاناً',
      'Gratis registreren', 'Inscrivez-vous gratuitement', 'Đăng ký miễn phí');
  String get createAccountTitle => _s('Create account', 'اکاؤنٹ بنائیں',
      'إنشاء حساب', 'Account maken', 'Créer un compte', 'Tạo tài khoản');
  String get createAccountSubtitle => _s(
        'Record whispers, build playlists, and schedule playback.',
        'سرگوشیاں ریکارڈ کریں، پلے لسٹ بنائیں، شیڈول کریں۔',
        'سجّل همسات، أنشئ قوائم، وجدول التشغيل.',
        'Neem whispers op, maak afspeellijsten en plan weergave.',
        'Enregistrez des murmures, créez des playlists et planifiez.',
        'Ghi lời thì thầm, tạo danh sách phát và lên lịch.',
      );
  String get syncClips => _s('Sync clips', 'کلپس مطابقت', 'مزامنة المقاطع',
      'Clips synchroniseren', 'Synchroniser clips', 'Đồng bộ đoạn ghi');
  String get schedulesLabel =>
      _s('Schedules', 'شیڈول', 'الجداول', 'Schema\'s', 'Plannings', 'Lịch');
  String get cloudBackup => _s('Cloud backup', 'کلاؤڈ بیک اپ', 'نسخ سحابي',
      'Cloudback-up', 'Sauvegarde cloud', 'Sao lưu đám mây');
  String get fullName => _s('Full name', 'پورا نام', 'الاسم الكامل',
      'Volledige naam', 'Nom complet', 'Họ và tên');
  String get fullNameHint => _s('Maria Khan', 'Maria Khan', 'Maria Khan',
      'Maria Khan', 'Maria Khan', 'Maria Khan');
  String get passwordHintSignup => _s(
      'At least 8 characters',
      'کم از کم 8 حروف',
      '8 أحرف على الأقل',
      'Minimaal 8 tekens',
      'Au moins 8 caractères',
      'Ít nhất 8 ký tự');
  String get createAccountButton => _s('Create Account', 'اکاؤنٹ بنائیں',
      'إنشاء حساب', 'Account maken', 'Créer un compte', 'Tạo tài khoản');
  String get acceptTermsError => _s(
      'Please accept the terms to continue',
      'جاری رکھنے کے لیے شرائط قبول کریں',
      'اقبل الشروط للمتابعة',
      'Accepteer de voorwaarden om door te gaan',
      'Acceptez les conditions pour continuer',
      'Vui lòng chấp nhận điều khoản để tiếp tục');
  String get alreadyHaveAccount => _s(
      'Already have an account? ',
      'پہلے سے اکاؤنٹ؟ ',
      'لديك حساب؟ ',
      'Al een account? ',
      'Déjà un compte ? ',
      'Đã có tài khoản? ');
  String get continueWithoutAccount => _s(
      'Continue without account →',
      'اکاؤنٹ کے بغیر جاری رکھیں →',
      'المتابعة بدون حساب →',
      'Doorgaan zonder account →',
      'Continuer sans compte →',
      'Tiếp tục không cần tài khoản →');
  String get signUp => _s(
      'Sign up', 'سائن اپ', 'التسجيل', 'Registreren', 'S\'inscrire', 'Đăng ký');
  String get orContinueWith => _s(
      'or continue with',
      'یا جاری رکھیں',
      'أو تابع مع',
      'of ga verder met',
      'ou continuer avec',
      'hoặc tiếp tục với');
  String get google =>
      _s('Google', 'Google', 'Google', 'Google', 'Google', 'Google');
  String get apple => _s('Apple', 'Apple', 'Apple', 'Apple', 'Apple', 'Apple');
  String get termsPrefix => _s('I agree to the ', 'میں متفق ہوں ', 'أوافق على ',
      'Ik ga akkoord met de ', 'J\'accepte les ', 'Tôi đồng ý với ');
  String get termsOfService => _s(
      'Terms of Service',
      'سروس کی شرائط',
      'شروط الخدمة',
      'Servicevoorwaarden',
      'Conditions d\'utilisation',
      'Điều khoản dịch vụ');
  String get and => _s(' and ', ' اور ', ' و ', ' en ', ' et ', ' và ');
  String get privacyPolicy => _s(
      'Privacy Policy',
      'رازداری کی پالیسی',
      'سياسة الخصوصية',
      'Privacybeleid',
      'Politique de confidentialité',
      'Chính sách bảo mật');
  String get passwordHintEmpty => _s(
      'Use 8+ characters with letters and numbers.',
      '8+ حروف اور نمبر استعمال کریں۔',
      'استخدم 8+ أحرف وأرقام.',
      'Gebruik 8+ tekens met letters en cijfers.',
      'Utilisez 8+ caractères avec lettres et chiffres.',
      'Dùng từ 8 ký tự trở lên gồm chữ và số.');
  String get passwordWeak => _s(
      'Weak — add more characters.',
      'کمزور — مزید حروف شامل کریں۔',
      'ضعيف — أضف المزيد.',
      'Zwak — voeg meer tekens toe.',
      'Faible — ajoutez des caractères.',
      'Yếu — thêm ký tự.');
  String get passwordFair => _s(
      'Fair — add numbers or symbols.',
      'ٹھیک — نمبر یا علامات شامل کریں۔',
      'مقبول — أضف أرقاماً أو رموزاً.',
      'Redelijk — voeg cijfers of symbolen toe.',
      'Correct — ajoutez chiffres ou symboles.',
      'Khá — thêm số hoặc ký hiệu.');
  String get passwordGood => _s(
      'Good password.',
      'اچھا پاس ورڈ۔',
      'كلمة مرور جيدة.',
      'Goed wachtwoord.',
      'Bon mot de passe.',
      'Mật khẩu tốt.');
  String get passwordStrong => _s(
      'Strong password.',
      'مضبوط پاس ورڈ۔',
      'كلمة مرور قوية.',
      'Sterk wachtwoord.',
      'Mot de passe fort.',
      'Mật khẩu mạnh.');

  // ── Sleep ───────────────────────────────────────────────────────────────────
  String get sleepModeTitle => _s('Sleep Mode', 'نیند موڈ', 'وضع النوم',
      'Slaapmodus', 'Mode veille', 'Chế độ ngủ');
  String get nightRoutine => _s('NIGHT ROUTINE', 'رات کا معمول', 'روتين الليل',
      'NACHTROUTINE', 'ROUTINE NOCTURNE', 'THÓI QUEN BAN ĐÊM');
  String get restPeacefully => _s(
      'Rest peacefully',
      'پرامن آرام کریں',
      'استرح بسلام',
      'Rust vredig',
      'Reposez-vous paisiblement',
      'Nghỉ ngơi yên bình');
  String get sleepHeroBody => _s(
        'All whispers pause during sleep. Your schedules resume automatically when sleep ends.',
        'نیند کے دوران تمام سرگوشیاں رک جاتی ہیں۔ نیند ختم ہونے پر شیڈول خود بحال ہو جاتے ہیں۔',
        'تتوقف جميع الهمسات أثناء النوم. تستأنف الجداول تلقائياً عند الانتهاء.',
        'Alle whispers pauzeren tijdens slaap. Schema\'s hervatten automatisch.',
        'Tous les murmures s\'arrêtent pendant le sommeil. Les plannings reprennent automatiquement.',
        'Mọi lời thì thầm tạm dừng khi ngủ. Lịch tự động tiếp tục khi kết thúc giấc ngủ.',
      );
  String get duration =>
      _s('DURATION', 'مدت', 'المدة', 'DUUR', 'DURÉE', 'THỜI LƯỢNG');
  String get startSleepMode => _s(
      'Start Sleep Mode',
      'نیند موڈ شروع کریں',
      'بدء وضع النوم',
      'Slaapmodus starten',
      'Démarrer mode veille',
      'Bắt đầu chế độ ngủ');
  String get sleepTapHint => _s(
      'Tap to pause all whispers until you wake',
      'جاگنے تک سرگوشیاں روکنے کے لیے دبائیں',
      'اضغط لإيقاف الهمسات حتى الاستيقاظ',
      'Tik om whispers te pauzeren tot je wakker wordt',
      'Appuyez pour pauser les murmures jusqu\'au réveil',
      'Nhấn để tạm dừng mọi lời thì thầm cho đến khi thức dậy');
  String get sleepActive => _s('Sleep active', 'نیند فعال', 'النوم نشط',
      'Slaap actief', 'Sommeil actif', 'Chế độ ngủ đang bật');
  String get endNow => _s('End now', 'ابھی ختم کریں', 'إنهاء الآن',
      'Nu beëindigen', 'Terminer maintenant', 'Kết thúc ngay');
  String get instantPause => _s('Instant pause', 'فوری وقفہ', 'إيقاف فوري',
      'Direct pauzeren', 'Pause instantanée', 'Tạm dừng tức thì');
  String get instantPauseDesc => _s(
      'Whispers stop the moment sleep begins',
      'نیند شروع ہوتے ہی سرگوشیاں رک جاتی ہیں',
      'تتوقف الهمسات عند بدء النوم',
      'Whispers stoppen zodra slaap begint',
      'Les murmures s\'arrêtent dès le début du sommeil',
      'Lời thì thầm dừng ngay khi bắt đầu ngủ');
  String get schedulesWait => _s('Schedules wait', 'شیڈول انتظار',
      'الجداول تنتظر', 'Schema\'s wachten', 'Plannings en attente', 'Lịch chờ');
  String get schedulesWaitDesc => _s(
      'Everything resumes when you wake',
      'جاگنے پر سب بحال',
      'يستأنف كل شيء عند الاستيقاظ',
      'Alles hervat bij wakker worden',
      'Tout reprend au réveil',
      'Mọi thứ tiếp tục khi bạn thức dậy');
  String get quietAlarms => _s('Quiet alarms', 'خاموش الارم', 'تنبيهات هادئة',
      'Stille alarmen', 'Alarmes silencieuses', 'Báo thức im lặng');
  String get quietAlarmsDesc => _s(
      'No interruptions while you rest',
      'آرام کے دوران کوئی رکاوٹ نہیں',
      'لا مقاطعات أثناء الراحة',
      'Geen onderbrekingen tijdens rust',
      'Aucune interruption pendant le repos',
      'Không bị gián đoạn khi nghỉ ngơi');

  String sleepModeUntil(String time) => _s(
      'Sleep mode until $time',
      'نیند موڈ $time تک',
      'وضع النوم حتى $time',
      'Slaapmodus tot $time',
      'Mode veille jusqu\'à $time',
      'Chế độ ngủ đến $time');
  String untilTime(String time) => _s('Until $time', '$time تک', 'حتى $time',
      'Tot $time', 'Jusqu\'à $time', 'Đến $time');

  // ── Prayer ──────────────────────────────────────────────────────────────────
  String get prayerModeTitle => _s('Prayer Mode', 'نماز موڈ', 'وضع الصلاة',
      'Gebedsmodus', 'Mode prière', 'Chế độ cầu nguyện');
  String get faithAndFocus => _s(
      'FAITH & FOCUS',
      'ایمان اور توجہ',
      'الإيمان والتركيز',
      'GELOOF & FOCUS',
      'FOI ET CONCENTRATION',
      'ĐỨC TIN & TẬP TRUNG');
  String get pauseDuringPrayer => _s(
      'Pause during prayer',
      'نماز کے دوران وقفہ',
      'إيقاف أثناء الصلاة',
      'Pauzeren tijdens gebed',
      'Pause pendant la prière',
      'Tạm dừng khi cầu nguyện');
  String get prayerHeroBody => _s(
        'Prayer times are calculated on your device using GPS. Coordinates never leave your phone.',
        'نماز کے اوقات GPS سے آپ کے فون پر حساب ہوتے ہیں۔ کوآرڈینیٹس فون سے باہر نہیں جاتے۔',
        'تُحسب أوقات الصلاة على جهازك بـ GPS. الإحداثيات لا تغادر هاتفك.',
        'Gebedstijden worden op je apparaat berekend met GPS. Coördinaten verlaten je telefoon nooit.',
        'Les heures de prière sont calculées sur votre appareil via GPS. Les coordonnées ne quittent jamais votre téléphone.',
        'Giờ cầu nguyện được tính trên thiết bị bằng GPS. Tọa độ không bao giờ rời khỏi điện thoại.',
      );
  String get onDevice => _s('On-device', 'ڈیوائس پر', 'على الجهاز',
      'Op apparaat', 'Sur l\'appareil', 'Trên thiết bị');
  String get onDeviceDesc => _s(
      'All calculations stay on-device',
      'تمام حساب ڈیوائس پر',
      'جميع الحسابات على الجهاز',
      'Alle berekeningen op apparaat',
      'Tous les calculs sur l\'appareil',
      'Mọi tính toán đều ở trên thiết bị');
  String get autoPause => _s('Auto pause', 'خودکار وقفہ', 'إيقاف تلقائي',
      'Automatisch pauzeren', 'Pause automatique', 'Tự động tạm dừng');
  String get autoPauseDesc => _s(
      'Whispers pause during each prayer',
      'ہر نماز کے دوران سرگوشیاں رکتی ہیں',
      'تتوقف الهمسات أثناء كل صلاة',
      'Whispers pauzeren tijdens elk gebed',
      'Les murmures s\'arrêtent pendant chaque prière',
      'Lời thì thầm tạm dừng trong mỗi buổi cầu nguyện');
  String get calculationMethod => _s(
      'Calculation method',
      'حساب کا طریقہ',
      'طريقة الحساب',
      'Berekeningsmethode',
      'Méthode de calcul',
      'Phương pháp tính');
  String get madhab =>
      _s('Madhab', 'مذہب', 'المذهب', 'Madhab', 'Madhab', 'Madhab');
  String get enablePrayerMode => _s(
      'Enable prayer mode',
      'نماز موڈ فعال کریں',
      'تفعيل وضع الصلاة',
      'Gebedsmodus inschakelen',
      'Activer mode prière',
      'Bật chế độ cầu nguyện');
  String get accurateTimes => _s('Accurate times', 'درست اوقات', 'أوقات دقيقة',
      'Nauwkeurige tijden', 'Horaires précis', 'Giờ chính xác');
  String get accurateTimesDesc => _s(
      'Based on your location',
      'آپ کے مقام پر مبنی',
      'بناءً على موقعك',
      'Gebaseerd op je locatie',
      'Basé sur votre position',
      'Dựa trên vị trí của bạn');
  String get autoPausePrayerDesc => _s(
      'Whispers resume after prayer',
      'نماز کے بعد سرگوشیاں بحال',
      'تستأنف الهمسات بعد الصلاة',
      'Whispers hervatten na gebed',
      'Les murmures reprennent après la prière',
      'Lời thì thầm tiếp tục sau khi cầu nguyện');
  String get asrMadhab => _s('Asr madhab', 'عصر مذہب', 'مذهب العصر',
      'Asr-madhab', 'Madhab Asr', 'Madhab Asr');
  String get useGpsLocation => _s(
      'Use GPS location',
      'GPS مقام استعمال کریں',
      'استخدام موقع GPS',
      'GPS-locatie gebruiken',
      'Utiliser la position GPS',
      'Dùng vị trí GPS');
  String get useGpsLocationDesc => _s(
        'Recommended for accurate prayer times',
        'درست نماز کے اوقات کے لیے تجویز',
        'موصى به لأوقات صلاة دقيقة',
        'Aanbevolen voor nauwkeurige gebedstijden',
        'Recommandé pour des heures de prière précises',
        'Khuyến nghị để có giờ cầu nguyện chính xác',
      );

  // ── Battery ─────────────────────────────────────────────────────────────────
  String get batteryTitle =>
      _s('Battery', 'بیٹری', 'البطارية', 'Batterij', 'Batterie', 'Pin');
  String get batteryHeroTitle => _s(
      'Keep WhisperBack running',
      'WhisperBack چلتا رکھیں',
      'أبق WhisperBack يعمل',
      'Houd WhisperBack actief',
      'Gardez WhisperBack actif',
      'Giữ WhisperBack luôn chạy');
  String get batteryHeroBody => _s(
        'Battery savers can delay whispers and miss schedules. Disable optimization for reliable playback.',
        'بیٹری سیور سرگوشیوں اور شیڈول میں تاخیر کر سکتے ہیں۔ قابلِ اعتماد پلے بیک کے لیے آپٹیمائزیشن بند کریں۔',
        'قد تؤخر موفرات البطارية الهمسات والجداول. عطّل التحسين لتشغيل موثوق.',
        'Batterijspaarders kunnen whispers vertragen. Schakel optimalisatie uit voor betrouwbare weergave.',
        'Les économiseurs de batterie peuvent retarder les murmures. Désactivez l\'optimisation pour une lecture fiable.',
        'Trình tiết kiệm pin có thể làm trễ lời thì thầm. Tắt tối ưu hóa để phát ổn định.',
      );
  String get whyItMatters => _s('WHY IT MATTERS', 'کیوں اہم ہے', 'لماذا يهم',
      'WAAROM HET UITMAAKT', 'POURQUOI C\'EST IMPORTANT', 'TẠI SAO QUAN TRỌNG');
  String get oemGuides => _s('OEM guides', 'OEM گائیڈ', 'أدلة OEM',
      'OEM-gidsen', 'Guides OEM', 'Hướng dẫn OEM');
  String get samsungGuide => _s(
      'Samsung / One UI',
      'Samsung / One UI',
      'Samsung / One UI',
      'Samsung / One UI',
      'Samsung / One UI',
      'Samsung / One UI');
  String get xiaomiGuide => _s('Xiaomi / MIUI', 'Xiaomi / MIUI',
      'Xiaomi / MIUI', 'Xiaomi / MIUI', 'Xiaomi / MIUI', 'Xiaomi / MIUI');
  String get huaweiGuide => _s('Huawei / EMUI', 'Huawei / EMUI',
      'Huawei / EMUI', 'Huawei / EMUI', 'Huawei / EMUI', 'Huawei / EMUI');
  String get stockAndroidGuide => _s('Stock Android', 'Stock Android',
      'Stock Android', 'Stock Android', 'Stock Android', 'Stock Android');
  String get reliableSchedules => _s(
      'RELIABLE SCHEDULES',
      'قابلِ اعتماد شیڈول',
      'جداول موثوقة',
      'BETROUWBARE SCHEMA\'S',
      'PLANNINGS FIABLES',
      'LỊCH ĐÁNG TIN CẬY');
  String get batteryWhitelistBody => _s(
        'Some phones limit background apps to save battery. Whitelisting WhisperBack helps scheduled whispers play on time.',
        'کچھ فونز بیٹری بچانے کے لیے پس منظر ایپس محدود کرتے ہیں۔ WhisperBack کو whitelist کرنے سے شیڈول سرگوشیاں وقت پر چلتی ہیں۔',
        'بعض الهواتف تحد التطبيقات في الخلفية. إضافة WhisperBack للقائمة البيضاء يساعد الهمسات المجدولة.',
        'Sommige telefoons beperken achtergrondapps. WhisperBack whitelisten helpt geplande whispers op tijd.',
        'Certains téléphones limitent les apps en arrière-plan. Autoriser WhisperBack aide les murmures planifiés.',
        'Một số điện thoại hạn chế ứng dụng nền để tiết kiệm pin. Đưa WhisperBack vào danh sách trắng giúp phát đúng giờ.',
      );
  String get onTimePlayback => _s(
      'On-time playback',
      'وقت پر پلے بیک',
      'تشغيل في الوقت',
      'Weergave op tijd',
      'Lecture à l\'heure',
      'Phát đúng giờ');
  String get onTimePlaybackDesc => _s(
      'Schedules fire when they should',
      'شیڈول وقت پر چلتے ہیں',
      'تعمل الجداول في وقتها',
      'Schema\'s starten wanneer nodig',
      'Les plannings se déclenchent à l\'heure',
      'Lịch chạy đúng thời điểm');
  String get reliableAlarms => _s(
      'Reliable alarms',
      'قابلِ اعتماد الارم',
      'تنبيهات موثوقة',
      'Betrouwbare alarmen',
      'Alarmes fiables',
      'Báo thức đáng tin cậy');
  String get reliableAlarmsDesc => _s(
      'Notifications are not delayed',
      'اطلاعات میں تاخیر نہیں',
      'الإشعارات لا تتأخر',
      'Meldingen worden niet vertraagd',
      'Les notifications ne sont pas retardées',
      'Thông báo không bị trễ');
  String get noDataCollection => _s(
      'No data collection',
      'ڈیٹا جمع نہیں',
      'لا جمع للبيانات',
      'Geen gegevensverzameling',
      'Pas de collecte de données',
      'Không thu thập dữ liệu');
  String get noDataCollectionDesc => _s(
        'Only system battery settings change',
        'صرف سسٹم بیٹری ترتیبات بدلتی ہیں',
        'تتغير فقط إعدادات بطارية النظام',
        'Alleen systeem-batterijinstellingen wijzigen',
        'Seuls les paramètres batterie système changent',
        'Chỉ thay đổi cài đặt pin của hệ thống',
      );
  String get byPhoneBrand => _s('BY PHONE BRAND', 'فون برانڈ کے لحاظ',
      'حسب العلامة', 'PER MERK', 'PAR MARQUE', 'THEO HÃNG ĐIỆN THOẠI');
  String get openSystemSettings => _s(
      'Open system settings',
      'سسٹم ترتیبات کھولیں',
      'فتح إعدادات النظام',
      'Systeeminstellingen openen',
      'Ouvrir les réglages système',
      'Mở cài đặt hệ thống');
  String get openSystemSettingsSnack => _s(
        'Open system Settings → Apps → WhisperBack → Battery',
        'Settings → Apps → WhisperBack → Battery کھولیں',
        'افتح الإعدادات → التطبيقات → WhisperBack → البطارية',
        'Open Instellingen → Apps → WhisperBack → Batterij',
        'Ouvrez Réglages → Apps → WhisperBack → Batterie',
        'Mở Cài đặt → Ứng dụng → WhisperBack → Pin',
      );

  // ── Permission prompts ──────────────────────────────────────────────────────
  String get permissionNotNow =>
      _s('Not now', 'ابھی نہیں', 'ليس الآن', 'Niet nu', 'Pas maintenant', 'Để sau');
  String get permissionOpenSettings => _s(
      'Open Settings',
      'ترتیبات کھولیں',
      'فتح الإعدادات',
      'Instellingen openen',
      'Ouvrir les réglages',
      'Mở cài đặt');
  String get permissionDeniedSnack => _s(
      'Permission needed. Try again or open Settings to enable it.',
      'اجازت درکار ہے۔ دوبارہ کوشش کریں یا ترتیبات سے فعال کریں۔',
      'الإذن مطلوب. حاول مرة أخرى أو فعّله من الإعدادات.',
      'Toestemming vereist. Probeer opnieuw of schakel het in via Instellingen.',
      'Autorisation requise. Réessayez ou activez-la dans Réglages.',
      'Cần quyền. Thử lại hoặc bật trong Cài đặt.');
  String get permissionMicrophoneTitle => micPermissionRequired;
  String get permissionMicrophoneBody => _s(
      'WhisperBack needs microphone access to record whispers. Without it, recording cannot start.',
      'سرگوشیاں ریکارڈ کرنے کے لیے WhisperBack کو مائیک کی اجازت چاہیے۔',
      'WhisperBack يحتاج الميكروفون لتسجيل الهمسات.',
      'WhisperBack heeft microfoontoegang nodig om whispers op te nemen.',
      'WhisperBack a besoin du micro pour enregistrer des murmures.',
      'WhisperBack cần micrô để ghi lời thì thầm.');
  String get permissionMicrophoneSettingsPath => _s(
      'Settings → Apps → WhisperBack → Permissions → Microphone → Allow',
      'Settings → Apps → WhisperBack → Permissions → Microphone → Allow',
      'الإعدادات → التطبيقات → WhisperBack → الأذونات → الميكروفون → السماح',
      'Instellingen → Apps → WhisperBack → Machtigingen → Microfoon → Toestaan',
      'Réglages → Apps → WhisperBack → Autorisations → Micro → Autoriser',
      'Cài đặt → Ứng dụng → WhisperBack → Quyền → Micrô → Cho phép');
  String get permissionLocationTitle => _s(
      'Location permission required',
      'مقام کی اجازت درکار',
      'إذن الموقع مطلوب',
      'Locatietoestemming vereist',
      'Autorisation de localisation requise',
      'Cần quyền vị trí');
  String get permissionLocationBody => _s(
      'GPS helps calculate accurate prayer times for your area. You can keep prayer mode off or disable GPS anytime.',
      'GPS آپ کے علاقے کے درست نماز کے اوقات کے لیے مدد کرتا ہے۔',
      'GPS يساعد في حساب أوقات الصلاة بدقة لمنطقتك.',
      'GPS helpt nauwkeurige gebedstijden voor jouw regio te berekenen.',
      'Le GPS aide à calculer les heures de prière pour votre zone.',
      'GPS giúp tính giờ cầu nguyện chính xác cho khu vực của bạn.');
  String get permissionLocationSettingsPath => _s(
      'Settings → Apps → WhisperBack → Permissions → Location → Allow',
      'Settings → Apps → WhisperBack → Permissions → Location → Allow',
      'الإعدادات → التطبيقات → WhisperBack → الأذونات → الموقع → السماح',
      'Instellingen → Apps → WhisperBack → Machtigingen → Locatie → Toestaan',
      'Réglages → Apps → WhisperBack → Autorisations → Localisation → Autoriser',
      'Cài đặt → Ứng dụng → WhisperBack → Quyền → Vị trí → Cho phép');
  String get permissionLocationDeniedSnack => _s(
      'Location access is needed for GPS prayer times.',
      'GPS نماز کے اوقات کے لیے مقام کی اجازت ضروری ہے۔',
      'الوصول إلى الموقع مطلوب لأوقات الصلاة عبر GPS.',
      'Locatietoegang is nodig voor GPS-gebedstijden.',
      'L\'accès à la localisation est requis pour les heures GPS.',
      'Cần quyền vị trí cho giờ cầu nguyện GPS.');
  String get permissionNotificationsTitle => _s(
      'Notifications required',
      'اطلاعات درکار',
      'الإشعارات مطلوبة',
      'Meldingen vereist',
      'Notifications requises',
      'Cần thông báo');
  String get permissionNotificationsBody => _s(
      'Scheduled whispers use notifications to play on time, even when the app is closed.',
      'شیڈول سرگوشیاں وقت پر چلانے کے لیے اطلاعات استعمال کرتی ہیں۔',
      'الهمسات المجدولة تستخدم الإشعارات للتشغيل في الوقت المحدد.',
      'Geplande whispers gebruiken meldingen om op tijd af te spelen.',
      'Les murmures planifiés utilisent les notifications pour jouer à l\'heure.',
      'Lời thì thầm theo lịch dùng thông báo để phát đúng giờ.');
  String get permissionNotificationsSettingsPath => _s(
      'Settings → Apps → WhisperBack → Permissions → Notifications → Allow',
      'Settings → Apps → WhisperBack → Permissions → Notifications → Allow',
      'الإعدادات → التطبيقات → WhisperBack → الأذونات → الإشعارات → السماح',
      'Instellingen → Apps → WhisperBack → Machtigingen → Meldingen → Toestaan',
      'Réglages → Apps → WhisperBack → Autorisations → Notifications → Autoriser',
      'Cài đặt → Ứng dụng → WhisperBack → Quyền → Thông báo → Cho phép');
  String get permissionNotificationsDeniedSnack => _s(
      'Allow notifications so scheduled whispers can play on time.',
      'شیڈول سرگوشیاں چلانے کے لیے اطلاعات کی اجازت دیں۔',
      'اسمح بالإشعارات لتشغيل الهمسات المجدولة في الوقت.',
      'Sta meldingen toe zodat geplande whispers op tijd spelen.',
      'Autorisez les notifications pour les murmures planifiés.',
      'Cho phép thông báo để phát lời thì thầm đúng giờ.');
  String get permissionNotificationsShort =>
      _s('Notifications', 'اطلاعات', 'الإشعارات', 'Meldingen', 'Notifications', 'Thông báo');
  String get permissionExactAlarmsTitle => _s(
      'Alarms & reminders required',
      'الارم اور یاددہانی درکار',
      'المنبهات والتذكيرات مطلوبة',
      'Alarmen vereist',
      'Alarmes requises',
      'Cần báo thức & nhắc nhở');
  String get permissionExactAlarmsBody => _s(
      'Android needs permission to schedule exact alarms so whispers fire at the right minute.',
      'Android کو درست وقت پر سرگوشیاں چلانے کے لیے exact alarm کی اجازت چاہیے۔',
      'Android يحتاج إذن المنبهات الدقيقة لتشغيل الهمسات في الوقت الصحيح.',
      'Android heeft exacte alarmen nodig om whispers op het juiste moment te starten.',
      'Android a besoin d\'alarmes exactes pour lancer les murmures à la bonne minute.',
      'Android cần báo thức chính xác để phát đúng phút.');
  String get permissionExactAlarmsSettingsPath => _s(
      'Settings → Apps → WhisperBack → Alarms & reminders → Allow',
      'Settings → Apps → WhisperBack → Alarms & reminders → Allow',
      'الإعدادات → التطبيقات → WhisperBack → المنبهات والتذكيرات → السماح',
      'Instellingen → Apps → WhisperBack → Alarmen & herinneringen → Toestaan',
      'Réglages → Apps → WhisperBack → Alarmes et rappels → Autoriser',
      'Cài đặt → Ứng dụng → WhisperBack → Báo thức & nhắc nhở → Cho phép');
  String get permissionExactAlarmsDeniedSnack => _s(
      'Allow alarms & reminders for reliable schedules.',
      'قابل اعتماد شیڈول کے لیے alarms & reminders کی اجازت دیں۔',
      'اسمح بالمنبهات والتذكيرات للجدولة الموثوقة.',
      'Sta alarmen & herinneringen toe voor betrouwbare planning.',
      'Autorisez alarmes et rappels pour une planification fiable.',
      'Cho phép báo thức & nhắc nhở để lên lịch ổn định.');
  String get permissionExactAlarmsShort => _s(
      'Alarms & reminders',
      'Alarms & reminders',
      'المنبهات والتذكيرات',
      'Alarmen & herinneringen',
      'Alarmes et rappels',
      'Báo thức & nhắc nhở');
  String get permissionBatteryTitle => batteryOptimization;
  String get permissionBatteryBody => batteryWhitelistBody;
  String get permissionBatterySettingsPath => openSystemSettingsSnack;
  String get permissionBatteryDeniedSnack => _s(
      'Unrestricted battery helps whispers play when the phone is idle.',
      'غیر محدود بیٹری فون بیکار ہونے پر بھی سرگوشیاں چلانے میں مدد کرتی ہے۔',
      'البطارية غير المقيدة تساعد على تشغيل الهمسات عند خمول الهاتف.',
      'Onbeperkte batterij helpt whispers af te spelen als de telefoon idle is.',
      'Batterie non restreinte pour jouer les murmures quand le téléphone est inactif.',
      'Pin không hạn chế giúp phát khi điện thoại nghỉ.');
  String get permissionBatteryShort =>
      _s('Battery (Unrestricted)', 'بیٹری (غیر محدود)', 'البطارية (غير مقيدة)', 'Batterij (onbeperkt)', 'Batterie (non restreinte)', 'Pin (không hạn chế)');
  String get permissionAudioTitle => _s(
      'Audio access required',
      'آڈیو رسائی درکار',
      'الوصول إلى الصوت مطلوب',
      'Audiotoegang vereist',
      'Accès audio requis',
      'Cần quyền truy cập âm thanh');
  String get permissionAudioBody => _s(
      'WhisperBack needs permission to read audio files you choose from your device.',
      'آپ کے فون سے آڈیو فائلیں درآمد کرنے کے لیے رسائی درکار ہے۔',
      'WhisperBack يحتاج إذناً لقراءة ملفات الصوت التي تختارها.',
      'WhisperBack heeft toegang nodig om gekozen audiobestanden te lezen.',
      'WhisperBack a besoin d\'accéder aux fichiers audio choisis.',
      'WhisperBack cần quyền đọc tệp âm thanh bạn chọn.');
  String get permissionAudioSettingsPath => _s(
      'Settings → Apps → WhisperBack → Permissions → Music and audio → Allow',
      'Settings → Apps → WhisperBack → Permissions → Music and audio → Allow',
      'الإعدادات → التطبيقات → WhisperBack → الأذونات → الموسيقى والصوت → السماح',
      'Instellingen → Apps → WhisperBack → Machtigingen → Muziek en audio → Toestaan',
      'Réglages → Apps → WhisperBack → Autorisations → Musique et audio → Autoriser',
      'Cài đặt → Ứng dụng → WhisperBack → Quyền → Nhạc và âm thanh → Cho phép');
  String get permissionAudioDeniedSnack => _s(
      'Allow audio access to import MP3 or M4A files.',
      'MP3 یا M4A درآمد کرنے کے لیے آڈیو رسائی دیں۔',
      'اسمح بالوصول إلى الصوت لاستيراد MP3 أو M4A.',
      'Sta audiotoegang toe om MP3- of M4A-bestanden te importeren.',
      'Autorisez l\'accès audio pour importer des MP3 ou M4A.',
      'Cho phép truy cập âm thanh để nhập MP3 hoặc M4A.');
  String get schedulingPermissionsTitle => _s(
      'Finish setup for scheduled whispers',
      'شیڈول سرگوشیاں کے لیے سیٹ اپ مکمل کریں',
      'أكمل الإعداد للهمسات المجدولة',
      'Setup voltooien voor geplande whispers',
      'Terminer la configuration des murmures planifiés',
      'Hoàn tất thiết lập lời thì thầm theo lịch');
  String schedulingPermissionsBody(String missingList) => _s(
      'WhisperBack still needs:\n• $missingList\n\nEnable these in Settings so schedules work reliably.',
      'WhisperBack کو ابھی درکار:\n• $missingList\n\nترتیبات میں فعال کریں تاکہ شیڈول درست کام کریں۔',
      'WhisperBack ما زال يحتاج:\n• $missingList\n\nفعّلها من الإعدادات لتعمل الجداول بموثوقية.',
      'WhisperBack heeft nog nodig:\n• $missingList\n\nSchakel dit in via Instellingen.',
      'WhisperBack a encore besoin de:\n• $missingList\n\nActivez-les dans Réglages.',
      'WhisperBack vẫn cần:\n• $missingList\n\nBật trong Cài đặt để lịch hoạt động ổn định.');
  String get schedulingPermissionsSettingsPath => _s(
      'Settings → Apps → WhisperBack → Permissions (and Battery → Unrestricted)',
      'Settings → Apps → WhisperBack → Permissions (اور Battery → Unrestricted)',
      'الإعدادات → التطبيقات → WhisperBack → الأذونات (والبطارية → غير مقيدة)',
      'Instellingen → Apps → WhisperBack → Machtigingen (en Batterij → Onbeperkt)',
      'Réglages → Apps → WhisperBack → Autorisations (et Batterie → Non restreinte)',
      'Cài đặt → Ứng dụng → WhisperBack → Quyền (và Pin → Không hạn chế)');
  String get schedulingSetupIntro => _s(
      'Tap Allow on the next prompts so whispers run automatically in the background.',
      'اگلے پرامپٹس پر Allow دبائیں تاکہ سرگوشیاں پس منظر میں خود چلیں۔',
      'اضغط السماح في النوافذ التالية لتشغيل الهمسات تلقائياً.',
      'Tik op Toestaan bij de volgende prompts voor automatische whispers.',
      'Appuyez sur Autoriser aux prochaines invites pour une lecture auto.',
      'Chạm Cho phép ở các hộp tiếp theo để phát tự động.');
  String get schedulingSetupComplete => _s(
      'Background setup complete — scheduled whispers are ready.',
      'پس منظر سیٹ اپ مکمل — شیڈول سرگوشیاں تیار ہیں۔',
      'اكتمل إعداد الخلفية — الهمسات المجدولة جاهزة.',
      'Achtergrondsetup voltooid — geplande whispers zijn klaar.',
      'Configuration arrière-plan terminée — murmures planifiés prêts.',
      'Thiết lập nền xong — lời thì thầm theo lịch đã sẵn sàng.');
  String get schedulingFinishSetupAction => _s(
      'Finish setup',
      'سیٹ اپ مکمل کریں',
      'أكمل الإعداد',
      'Setup voltooien',
      'Terminer la configuration',
      'Hoàn tất thiết lập');

  // ── Record / Import / New playlist ──────────────────────────────────────────
  String get recordTitle =>
      _s('Record', 'ریکارڈ', 'تسجيل', 'Opnemen', 'Enregistrer', 'Ghi âm');
  String get captureAWhisper => _s(
      'CAPTURE A WHISPER',
      'سرگوشی ریکارڈ کریں',
      'التقاط همسة',
      'WHISPER OPNEMEN',
      'CAPTURER UN MURMURE',
      'GHI MỘT LỜI THÌ THẦM');
  String get recordNewClip => _s(
      'Record a new clip',
      'نئی کلپ ریکارڈ کریں',
      'تسجيل مقطع جديد',
      'Nieuwe clip opnemen',
      'Enregistrer un nouveau clip',
      'Ghi đoạn ghi mới');
  String get newRecording => _s('New recording', 'نئی ریکارڈنگ', 'تسجيل جديد',
      'Nieuwe opname', 'Nouvel enregistrement', 'Bản ghi mới');
  String get startRecording => _s(
      'Start Recording',
      'ریکارڈنگ شروع کریں',
      'بدء التسجيل',
      'Opname starten',
      'Commencer l\'enregistrement',
      'Bắt đầu ghi âm');
  String get stopAndSave => _s(
      'Stop & Save',
      'روکیں اور محفوظ کریں',
      'إيقاف وحفظ',
      'Stoppen & opslaan',
      'Arrêter et enregistrer',
      'Dừng & lưu');
  String get micPermissionRequired => _s(
      'Microphone permission required',
      'مائیک کی اجازت درکار',
      'إذن الميكروفون مطلوب',
      'Microfoontoestemming vereist',
      'Autorisation micro requise',
      'Cần quyền micrô');
  String get micPermissionSnack => _s(
      'Microphone permission is required to record',
      'ریکارڈ کے لیے مائیک کی اجازت ضروری',
      'إذن الميكروفون مطلوب للتسجيل',
      'Microfoontoestemming is vereist om op te nemen',
      'L\'autorisation micro est requise pour enregistrer',
      'Cần quyền micrô để ghi âm');
  String get recording => _s('Recording…', 'ریکارڈنگ…', 'جاري التسجيل…',
      'Opnemen…', 'Enregistrement…', 'Đang ghi âm…');
  String get clipTitle => _s('Clip title', 'کلپ کا عنوان', 'عنوان المقطع',
      'Cliptitel', 'Titre du clip', 'Tiêu đề đoạn ghi');
  String get recordingCancelled => _s(
      'Recording cancelled',
      'ریکارڈنگ منسوخ',
      'تم إلغاء التسجيل',
      'Opname geannuleerd',
      'Enregistrement annulé',
      'Đã hủy ghi âm');
  String savedClip(String title) => _s(
      'Saved $title',
      '$title محفوظ',
      'تم حفظ $title',
      '$title opgeslagen',
      '$title enregistré',
      'Đã lưu $title');

  String get importTitle =>
      _s('Import', 'درآمد', 'استيراد', 'Importeren', 'Importer', 'Nhập');
  String get addAudio => _s('ADD AUDIO', 'آڈیو شامل کریں', 'إضافة صوت',
      'AUDIO TOEVOEGEN', 'AJOUTER AUDIO', 'THÊM ÂM THANH');
  String get importFromDevice => _s(
      'Import from device',
      'ڈیوائس سے درآمد',
      'استيراد من الجهاز',
      'Importeren van apparaat',
      'Importer depuis l\'appareil',
      'Nhập từ thiết bị');
  String get chooseAudioFile => _s(
      'Choose audio file',
      'آڈیو فائل منتخب کریں',
      'اختر ملفاً صوتياً',
      'Kies audiobestand',
      'Choisir un fichier audio',
      'Chọn tệp âm thanh');
  String get tapToBrowseAudio => _s(
      'Tap to browse MP3 or M4A on your device',
      'اپنے ڈیوائس پر MP3 یا M4A براؤز کرنے کے لیے دبائیں',
      'اضغط لتصفح MP3 أو M4A',
      'Tik om MP3 of M4A te bladeren',
      'Appuyez pour parcourir MP3 ou M4A',
      'Nhấn để duyệt MP3 hoặc M4A trên thiết bị');
  String get audioFile => _s('Audio file', 'آڈیو فائل', 'ملف صوتي',
      'Audiobestand', 'Fichier audio', 'Tệp âm thanh');
  String get importing => _s('Importing…', 'درآمد ہو رہی ہے…',
      'جاري الاستيراد…', 'Importeren…', 'Importation…', 'Đang nhập…');
  String get copyingFile => _s(
      'Copying file into WhisperBack…',
      'WhisperBack میں فائل کاپی ہو رہی ہے…',
      'نسخ الملف إلى WhisperBack…',
      'Bestand kopiëren naar WhisperBack…',
      'Copie du fichier dans WhisperBack…',
      'Đang sao chép tệp vào WhisperBack…');
  String importedClip(String title) => _s(
      'Imported $title',
      '$title درآمد',
      'تم استيراد $title',
      '$title geïmporteerd',
      '$title importé',
      'Đã nhập $title');

  String get buildCollection => _s(
      'BUILD A COLLECTION',
      'مجموعہ بنائیں',
      'بناء مجموعة',
      'COLLECTIE BOUWEN',
      'CRÉER UNE COLLECTION',
      'TẠO BỘ SƯU TẬP');
  String get createAPlaylist => _s(
      'Create a playlist',
      'پلے لسٹ بنائیں',
      'إنشاء قائمة تشغيل',
      'Afspeellijst maken',
      'Créer une playlist',
      'Tạo danh sách phát');
  String get quickIdeas => _s('QUICK IDEAS', 'فوری آئیڈیاز', 'أفكار سريعة',
      'SNELLE IDEEËN', 'IDÉES RAPIDES', 'Ý TƯỞNG NHANH');
  String get creating => _s('Creating…', 'بن رہا ہے…', 'جاري الإنشاء…',
      'Maken…', 'Création…', 'Đang tạo…');
  String get playlistName => _s(
      'Playlist name',
      'پلے لسٹ کا نام',
      'اسم القائمة',
      'Naam afspeellijst',
      'Nom de la playlist',
      'Tên danh sách phát');
  String get playlistNameHint => _s(
      'e.g. Morning Whispers',
      'مثلاً Morning Whispers',
      'مثلاً Morning Whispers',
      'bijv. Morning Whispers',
      'ex. Morning Whispers',
      'ví dụ: Morning Whispers');
  String get afterCreatingHint => _s(
        'After creating, add clips from your library and set a schedule when you\'re ready.',
        'بنانے کے بعد لائبریری سے کلپس شامل کریں اور تیار ہونے پر شیڈول سیٹ کریں۔',
        'بعد الإنشاء، أضف مقاطع من مكتبتك وحدد جدولاً.',
        'Voeg daarna clips toe uit je bibliotheek en stel een schema in.',
        'Ensuite, ajoutez des clips et définissez un planning.',
        'Sau khi tạo, thêm đoạn ghi từ thư viện và lên lịch khi bạn sẵn sàng.',
      );
  String get enterPlaylistName => _s(
      'Enter a playlist name',
      'پلے لسٹ کا نام درج کریں',
      'أدخل اسم القائمة',
      'Voer een naam in',
      'Entrez un nom de playlist',
      'Nhập tên danh sách phát');
  String createdPlaylist(String name) => _s('Created $name', '$name بنائی',
      'تم إنشاء $name', '$name gemaakt', '$name créée', 'Đã tạo $name');
  String playlistLimitReached(int limit) => _s(
        'Playlist limit reached ($limit). Upgrade to Premium for more.',
        'پلے لسٹ کی حد ($limit) پوری ہو گئی۔ مزید کے لیے پریمیم حاصل کریں۔',
        'تم بلوغ حد القوائم ($limit). الترقية إلى بريميوم للمزيد.',
        'Limiet bereikt ($limit). Upgrade naar Premium voor meer.',
        'Limite atteinte ($limit). Passez à Premium pour plus.',
        'Đã đạt giới hạn ($limit). Nâng cấp Premium để thêm.',
      );
  String get ideaMorningWhispers => _s(
      'Morning Whispers',
      'Morning Whispers',
      'Morning Whispers',
      'Morning Whispers',
      'Morning Whispers',
      'Morning Whispers');
  String get ideaWorkFocus => _s('Work Focus', 'Work Focus', 'Work Focus',
      'Work Focus', 'Work Focus', 'Work Focus');
  String get ideaEveningCalm => _s('Evening Calm', 'Evening Calm',
      'Evening Calm', 'Evening Calm', 'Evening Calm', 'Evening Calm');
  String get createPlaylistDescription => _s(
        'Group your whispers into a collection. Add clips and schedules after you create it.',
        'اپنی سرگوشیاں مجموعے میں شامل کریں۔ بنانے کے بعد کلپس اور شیڈول شامل کریں۔',
        'اجمع همساتك في مجموعة. أضف المقاطع والجداول بعد الإنشاء.',
        'Groepeer whispers in een collectie. Voeg clips en schema\'s toe na het maken.',
        'Regroupez vos murmures. Ajoutez clips et plannings après la création.',
        'Nhóm các lời thì thầm vào một bộ sưu tập. Thêm đoạn ghi và lịch sau khi tạo.',
      );
  String get recordSpeakClearlyHint => _s(
        'Speak clearly into your microphone. Clips are saved locally on your device.',
        'مائیک میں واضح بولیں۔ کلپس آپ کے ڈیوائس پر محفوظ ہوتی ہیں۔',
        'تحدث بوضوح في الميكروفون. تُحفظ المقاطع محلياً على جهازك.',
        'Spreek duidelijk in je microfoon. Clips worden lokaal opgeslagen.',
        'Parlez clairement dans le micro. Les clips sont enregistrés localement.',
        'Hãy nói rõ vào micrô. Đoạn ghi được lưu cục bộ trên thiết bị của bạn.',
      );
  String get importBody => _s(
        'Import MP3 or M4A files from your device. Files are copied into the app for safe offline playback.',
        'اپنے ڈیوائس سے MP3 یا M4A فائلیں درآمد کریں۔ فائلیں آف لائن پلے بیک کے لیے ایپ میں کاپی ہوتی ہیں۔',
        'استورد ملفات MP3 أو M4A. تُنسخ الملفات إلى التطبيق للتشغيل دون اتصال.',
        'Importeer MP3- of M4A-bestanden. Bestanden worden gekopieerd voor offline weergave.',
        'Importez des fichiers MP3 ou M4A. Les fichiers sont copiés pour une lecture hors ligne.',
        'Nhập tệp MP3 hoặc M4A từ thiết bị. Tệp được sao chép vào ứng dụng để phát ngoại tuyến an toàn.',
      );
  String get importedClipsStayOnDevice => _s(
        'Imported clips stay on your device. Original files are not modified.',
        'درآمد شدہ کلپس آپ کے ڈیوائس پر رہتی ہیں۔ اصل فائلیں تبدیل نہیں ہوتیں۔',
        'تبقى المقاطع المستوردة على جهازك. الملفات الأصلية لا تُعدّل.',
        'Geïmporteerde clips blijven op je apparaat. Originele bestanden worden niet gewijzigd.',
        'Les clips importés restent sur votre appareil. Les fichiers originaux ne sont pas modifiés.',
        'Đoạn ghi đã nhập vẫn ở trên thiết bị. Tệp gốc không bị thay đổi.',
      );

  // ── Duration / schedule helpers ─────────────────────────────────────────────
  String get zeroSec =>
      _s('0 sec', '0 سیکنڈ', '0 ثانية', '0 sec', '0 s', '0 giây');
  String durationSec(int sec) => _s('$sec sec', '$sec سیکنڈ', '$sec ثانية',
      '$sec sec', '$sec s', '$sec giây');
  String durationMin(int min) => _s('$min min', '$min منٹ', '$min دقيقة',
      '$min min', '$min min', '$min phút');
  String durationMinSec(int min, int sec) => _s(
      '$min min $sec sec',
      '$min منٹ $sec سیکنڈ',
      '$min دقيقة $sec ثانية',
      '$min min $sec sec',
      '$min min $sec s',
      '$min phút $sec giây');

  String intervalLabel(int minutes) {
    if (minutes >= 60 && minutes % 60 == 0) {
      final h = minutes ~/ 60;
      return h == 1 ? oneHour : hoursCount(h);
    }
    return durationMin(minutes);
  }

  String get oneHour =>
      _s('1 hour', '1 گھنٹہ', 'ساعة واحدة', '1 uur', '1 heure', '1 giờ');
  String hoursCount(int hours) => _s('$hours hours', '$hours گھنٹے',
      '$hours ساعات', '$hours uur', '$hours heures', '$hours giờ');

  List<String> get weekdayShortLabels => _lang == 'ar'
      ? const ['ن', 'ث', 'ر', 'خ', 'ج', 'س', 'ح']
      : _lang == 'ur'
          ? const ['پ', 'م', 'ب', 'ج', 'ج', 'ہ', 'ا']
          : _lang == 'nl'
              ? const ['M', 'D', 'W', 'D', 'V', 'Z', 'Z']
              : _lang == 'fr'
                  ? const ['L', 'M', 'M', 'J', 'V', 'S', 'D']
                  : _lang == 'vi'
                      ? const ['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN']
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
    return parts.join(' · ');
  }
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => AppLocalizations.supportedLocales
      .any((l) => l.languageCode == locale.languageCode);

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
