import 'package:flutter/material.dart';

const appName = 'ASplayer';
const appVersion = '0.1.0';
const developerName = 'Amirsina Poormehr';
const developerSite = 'https://aspoormehr.ir';

enum Lang {
  en('English'),
  fa('فارسی');

  const Lang(this.displayName);

  final String displayName;

  TextDirection get direction => this == Lang.fa ? TextDirection.rtl : TextDirection.ltr;
}

/// Hand-rolled instead of ARB files, because the language has to change inside
/// the app without relaunching it.
class Strings {
  const Strings({
    required this.start,
    required this.onboardLine1,
    required this.onboardLine2,
    required this.onboardBody,
    required this.hello,
    required this.searchSong,
    required this.categories,
    required this.yourSongs,
    required this.recentlyPlayed,
    required this.noSongFound,
    required this.all,
    required this.favorites,
    required this.mostPlayed,
    required this.recentlyAdded,
    required this.nothingHere,
    required this.noFavoritesYet,
    required this.nothingPlayedYet,
    required this.emptyTitle,
    required this.emptyBody,
    required this.importFromFiles,
    required this.favEmptyBody,
    required this.library,
    required this.songs,
    required this.artists,
    required this.albums,
    required this.playlists,
    required this.playAll,
    required this.sortBy,
    required this.sortNewest,
    required this.sortTitle,
    required this.sortArtist,
    required this.sortDuration,
    required this.newPlaylist,
    required this.playlistNamePlaceholder,
    required this.create,
    required this.cancel,
    required this.close,
    required this.noPlaylistsYet,
    required this.playlistEmpty,
    required this.addToPlaylist,
    required this.playNext,
    required this.addToQueue,
    required this.markFavorite,
    required this.unmarkFavorite,
    required this.removeFromPlaylist,
    required this.deleteFromLibrary,
    required this.deletePlaylist,
    required this.queue,
    required this.nowPlaying,
    required this.upNext,
    required this.queueEmpty,
    required this.sleepTimer,
    required this.cancelTimer,
    required this.playbackSpeed,
    required this.normalSpeed,
    required this.settings,
    required this.trackCount,
    required this.storageUsed,
    required this.howToAdd,
    required this.howToAddBody,
    required this.backgroundPlay,
    required this.backgroundPlayBody,
    required this.language,
    required this.appearance,
    required this.appearanceSystem,
    required this.appearanceLight,
    required this.appearanceDark,
    required this.pressBackAgain,
    required this.selectAll,
    required this.deselectAll,
    required this.nSelected,
    required this.delete,
    required this.deleteQuestion,
    required this.groupActions,
    required this.importFromPhone,
    required this.importFromPhoneBody,
    required this.scanningPhone,
    required this.noSongsOnPhone,
    required this.permissionNeeded,
    required this.importing,
    required this.imported,
    required this.about,
    required this.aboutTagline,
    required this.developedBy,
    required this.visitWebsite,
    required this.versionLabel,
    required this.unknownArtist,
    required this.noAlbum,
    required this.songsCount,
    required this.songsInLibrary,
    required this.minutesLabel,
    required this.sleepsIn,
    required this.totalDuration,
  });

  final String start, onboardLine1, onboardLine2, onboardBody;
  final String hello, searchSong, categories, yourSongs, recentlyPlayed, noSongFound;
  final String all, favorites, mostPlayed, recentlyAdded;
  final String nothingHere, noFavoritesYet, nothingPlayedYet;
  final String emptyTitle, emptyBody, importFromFiles, favEmptyBody;
  final String library, songs, artists, albums, playlists, playAll;
  final String sortBy, sortNewest, sortTitle, sortArtist, sortDuration;
  final String newPlaylist, playlistNamePlaceholder, create, cancel, close;
  final String noPlaylistsYet, playlistEmpty, addToPlaylist;
  final String playNext, addToQueue, markFavorite, unmarkFavorite;
  final String removeFromPlaylist, deleteFromLibrary, deletePlaylist;
  final String queue, nowPlaying, upNext, queueEmpty;
  final String sleepTimer, cancelTimer, playbackSpeed, normalSpeed;
  final String settings, trackCount, storageUsed;
  final String howToAdd, howToAddBody, backgroundPlay, backgroundPlayBody;
  final String language, appearance, appearanceSystem, appearanceLight, appearanceDark;
  final String pressBackAgain;
  final String selectAll, deselectAll, delete, deleteQuestion, groupActions;
  final String Function(int) nSelected;
  final String importFromPhone, importFromPhoneBody, scanningPhone;
  final String noSongsOnPhone, permissionNeeded, importing;
  final String Function(int) imported;
  final String about, aboutTagline, developedBy, visitWebsite, versionLabel;
  final String unknownArtist, noAlbum;

  final String Function(int) songsCount;
  final String Function(int) songsInLibrary;
  final String Function(int) minutesLabel;
  final String Function(String) sleepsIn;
  final String Function(int) totalDuration;

  static const en = Strings(
    start: "Let's start",
    onboardLine1: 'Dive into',
    onboardLine2: 'your own library.',
    onboardBody:
        'Keep your songs in one place and listen whenever you want — no internet, no subscription.',
    hello: 'Hello!',
    searchSong: 'Search for a song',
    categories: 'Categories',
    yourSongs: 'Your songs',
    recentlyPlayed: 'Recently played',
    noSongFound: 'No song matches that name',
    all: 'All',
    favorites: 'Favorites',
    mostPlayed: 'Most played',
    recentlyAdded: 'Recently added',
    nothingHere: 'Nothing here yet',
    noFavoritesYet: "You haven't marked anything yet",
    nothingPlayedYet: 'Nothing has been played yet',
    emptyTitle: 'No songs yet',
    emptyBody: 'In Telegram, tap an audio file, choose Share, and pick ASplayer.',
    importFromFiles: 'Import from Files',
    favEmptyBody: 'Tap the heart next to any song in your library.',
    library: 'Library',
    songs: 'Songs',
    artists: 'Artists',
    albums: 'Albums',
    playlists: 'Playlists',
    playAll: 'Play all',
    sortBy: 'Sort by',
    sortNewest: 'Newest',
    sortTitle: 'Title',
    sortArtist: 'Artist',
    sortDuration: 'Duration',
    newPlaylist: 'New playlist',
    playlistNamePlaceholder: 'Name',
    create: 'Create',
    cancel: 'Cancel',
    close: 'Close',
    noPlaylistsYet: "You haven't made a playlist yet",
    playlistEmpty: 'This playlist is empty.\nHold a song in your library and choose Add to playlist.',
    addToPlaylist: 'Add to playlist',
    playNext: 'Play next',
    addToQueue: 'Add to queue',
    markFavorite: 'Mark as favorite',
    unmarkFavorite: 'Remove from favorites',
    removeFromPlaylist: 'Remove from playlist',
    deleteFromLibrary: 'Delete from library',
    deletePlaylist: 'Delete playlist',
    queue: 'Queue',
    nowPlaying: 'Now playing',
    upNext: 'Up next',
    queueEmpty: 'Nothing in the queue',
    sleepTimer: 'Sleep timer',
    cancelTimer: 'Cancel timer',
    playbackSpeed: 'Playback speed',
    normalSpeed: 'Normal',
    settings: 'Settings',
    trackCount: 'Songs',
    storageUsed: 'Storage used',
    howToAdd: 'How do I add songs?',
    howToAddBody:
        'In Telegram, tap an audio file, choose Share, and pick ASplayer from the list. The song is copied into the app and Telegram is no longer needed.',
    backgroundPlay: 'Background playback',
    backgroundPlayBody:
        'Audio keeps going when the screen locks. Controls work from the notification shade, headphones, and in the car.',
    language: 'Language',
    appearance: 'Appearance',
    appearanceSystem: 'System',
    appearanceLight: 'Light',
    appearanceDark: 'Dark',
    pressBackAgain: 'Press back again to exit',
    selectAll: 'Select all',
    deselectAll: 'Deselect all',
    nSelected: _enSelected,
    delete: 'Delete',
    deleteQuestion: 'Delete the selected songs from your library?',
    groupActions: 'Actions',
    importFromPhone: 'Import songs from this phone',
    importFromPhoneBody:
        'Adds every song already on your phone. Files are not copied — they stay where they are, and removing a song here never deletes it.',
    scanningPhone: 'Looking for songs…',
    noSongsOnPhone: 'No songs found on this phone',
    permissionNeeded: 'ASplayer needs permission to read your music',
    importing: 'Adding songs…',
    imported: _enImported,
    about: 'About',
    aboutTagline: 'Your own music, on your own phone. No account, no ads, no internet.',
    developedBy: 'Built by',
    visitWebsite: 'Visit website',
    versionLabel: 'Version',
    unknownArtist: 'Unknown artist',
    noAlbum: 'No album',
    songsCount: _enSongs,
    songsInLibrary: _enSongsInLibrary,
    minutesLabel: _enMinutes,
    sleepsIn: _enSleepsIn,
    totalDuration: _enTotal,
  );

  static const fa = Strings(
    start: 'شروع کنیم',
    onboardLine1: 'غرق شو در',
    onboardLine2: 'کتابخانه‌ی خودت.',
    onboardBody:
        'آهنگ‌هایت را یک‌جا نگه دار و هر وقت خواستی گوش بده — بدون اینترنت، بدون اشتراک.',
    hello: 'سلام!',
    searchSong: 'جست‌وجوی آهنگ',
    categories: 'دسته‌بندی',
    yourSongs: 'آهنگ‌های تو',
    recentlyPlayed: 'اخیراً گوش داده‌شده',
    noSongFound: 'آهنگی با این نام پیدا نشد',
    all: 'همه',
    favorites: 'مورد علاقه',
    mostPlayed: 'بیشترین پخش',
    recentlyAdded: 'اخیراً اضافه‌شده',
    nothingHere: 'چیزی اینجا نیست',
    noFavoritesYet: 'هنوز آهنگی را نشان نکرده‌ای',
    nothingPlayedYet: 'هنوز آهنگی پخش نشده',
    emptyTitle: 'هنوز آهنگی اضافه نکردی',
    emptyBody: 'در تلگرام روی فایل صوتی بزن، دکمه‌ی اشتراک‌گذاری را انتخاب کن و ASplayer را بزن.',
    importFromFiles: 'وارد کردن از فایل‌ها',
    favEmptyBody: 'کنار هر آهنگ در کتابخانه، دکمه‌ی قلب را بزن.',
    library: 'کتابخانه',
    songs: 'آهنگ‌ها',
    artists: 'خواننده‌ها',
    albums: 'آلبوم‌ها',
    playlists: 'لیست‌های پخش',
    playAll: 'پخش همه',
    sortBy: 'مرتب‌سازی',
    sortNewest: 'تازه‌ترین',
    sortTitle: 'نام آهنگ',
    sortArtist: 'خواننده',
    sortDuration: 'مدت',
    newPlaylist: 'لیست پخش تازه',
    playlistNamePlaceholder: 'نام',
    create: 'بساز',
    cancel: 'بی‌خیال',
    close: 'بستن',
    noPlaylistsYet: 'هنوز لیست پخشی نساخته‌ای',
    playlistEmpty: 'این لیست پخش خالی است.\nاز کتابخانه، آهنگ را نگه دار و «افزودن به لیست پخش» را بزن.',
    addToPlaylist: 'افزودن به لیست پخش',
    playNext: 'پخش بعدی',
    addToQueue: 'افزودن به صف',
    markFavorite: 'نشان کردن',
    unmarkFavorite: 'برداشتن نشان',
    removeFromPlaylist: 'برداشتن از لیست پخش',
    deleteFromLibrary: 'حذف از کتابخانه',
    deletePlaylist: 'حذف لیست پخش',
    queue: 'صف پخش',
    nowPlaying: 'در حال پخش',
    upNext: 'بعدی',
    queueEmpty: 'چیزی در صف نیست',
    sleepTimer: 'تایمر خواب',
    cancelTimer: 'لغو تایمر',
    playbackSpeed: 'سرعت پخش',
    normalSpeed: 'عادی',
    settings: 'تنظیمات',
    trackCount: 'تعداد آهنگ‌ها',
    storageUsed: 'فضای اشغال‌شده',
    howToAdd: 'چطور آهنگ اضافه کنم؟',
    howToAddBody:
        'در تلگرام روی فایل صوتی بزن، دکمه‌ی اشتراک‌گذاری را انتخاب کن و از فهرست، ASplayer را بزن. آهنگ داخل حافظه‌ی اپ کپی می‌شود و دیگر به تلگرام نیازی نیست.',
    backgroundPlay: 'پخش در پس‌زمینه',
    backgroundPlayBody:
        'با قفل شدن گوشی صدا قطع نمی‌شود. کنترل‌ها از نوار اعلان، هدفون و نمایشگر ماشین کار می‌کنند.',
    language: 'زبان',
    appearance: 'ظاهر',
    appearanceSystem: 'سیستم',
    appearanceLight: 'روشن',
    appearanceDark: 'تیره',
    pressBackAgain: 'برای خروج دوباره بازگشت را بزن',
    selectAll: 'انتخاب همه',
    deselectAll: 'برداشتن انتخاب',
    nSelected: _faSelected,
    delete: 'حذف',
    deleteQuestion: 'آهنگ‌های انتخاب‌شده از کتابخانه حذف شوند؟',
    groupActions: 'کارها',
    importFromPhone: 'وارد کردن آهنگ‌های گوشی',
    importFromPhoneBody:
        'همه‌ی آهنگ‌هایی که روی گوشی داری اضافه می‌شوند. فایل‌ها کپی نمی‌شوند — سر جایشان می‌مانند، و حذف آهنگ از اینجا هرگز فایل اصلی را پاک نمی‌کند.',
    scanningPhone: 'در حال جست‌وجوی آهنگ‌ها…',
    noSongsOnPhone: 'آهنگی روی این گوشی پیدا نشد',
    permissionNeeded: 'ASplayer برای خواندن موزیک‌هایت به اجازه نیاز دارد',
    importing: 'در حال افزودن آهنگ‌ها…',
    imported: _faImported,
    about: 'درباره',
    aboutTagline: 'موزیک خودت، روی گوشی خودت. بدون حساب کاربری، بدون تبلیغات، بدون اینترنت.',
    developedBy: 'ساخته‌ی',
    visitWebsite: 'رفتن به سایت',
    versionLabel: 'نسخه',
    unknownArtist: 'خواننده‌ی ناشناس',
    noAlbum: 'بدون آلبوم',
    songsCount: _faSongs,
    songsInLibrary: _faSongsInLibrary,
    minutesLabel: _faMinutes,
    sleepsIn: _faSleepsIn,
    totalDuration: _faTotal,
  );
}

String _enSelected(int n) => '$n selected';
String _enImported(int n) => '$n songs added';
String _enSongs(int n) => '$n songs';
String _enSongsInLibrary(int n) => '$n songs in your library';
String _enMinutes(int n) => '$n minutes';
String _enSleepsIn(String t) => 'Stops in $t';
String _enTotal(int m) => m < 60 ? '$m min' : '${m ~/ 60} h ${m % 60} min';

String _faSelected(int n) => '$n انتخاب شد';
String _faImported(int n) => '$n آهنگ اضافه شد';
String _faSongs(int n) => '$n آهنگ';
String _faSongsInLibrary(int n) => '$n آهنگ در کتابخانه‌ات';
String _faMinutes(int n) => '$n دقیقه';
String _faSleepsIn(String t) => 'خاموش می‌شود تا $t';
String _faTotal(int m) => m < 60 ? '$m دقیقه' : '${m ~/ 60} ساعت و ${m % 60} دقیقه';
