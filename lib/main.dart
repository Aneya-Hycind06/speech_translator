import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:http/http.dart' as http;
import 'package:speech_to_text/speech_to_text.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Speech Translator',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        // Seeded from the app accent so menus, ripples and snack bars match
        // the palette instead of falling back to Material blue.
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFE0715A)),
        useMaterial3: true,
        textTheme: GoogleFonts.puritanTextTheme(),
      ),
      home: const SpeechScreen(),
    );
  }
}

/// One entry in the conversation. Only the translated text is stored/shown.
class ChatMessage {
  final String text;
  final String language;
  // Left bubbles carry the top language. Flipped when the two languages are
  // swapped so a bubble always stays on the side of the language it is in.
  bool isLeft;
  final DateTime time;
  bool isPinned;
  bool isFavourite;

  ChatMessage({
    required this.text,
    required this.language,
    required this.isLeft,
    required this.time,
    this.isPinned = false,
    this.isFavourite = false,
  });
}

/// Colour tokens for one theme.
///
/// Accent use is deliberate: [accent] fills only the two primary controls (the
/// mic and the swap button); everything else that needs to look "active" uses
/// the tinted [accentSurface] with [accentText] on top, which keeps the orange
/// from taking over the screen and keeps small text readable in both themes.
class _Palette {
  const _Palette({
    required this.bg,
    required this.surface,
    required this.surfaceMuted,
    required this.border,
    required this.textPrimary,
    required this.textSecondary,
    required this.textFaint,
    required this.accent,
    required this.accentText,
    required this.accentSurface,
    required this.heroGradient,
    required this.shadowOpacity,
  });

  final Color bg;
  final Color surface; // cards, sheets, round header buttons
  final Color surfaceMuted; // incoming bubbles, icon chips
  final Color border;
  final Color textPrimary;
  final Color textSecondary;
  final Color textFaint; // timestamps and other 10px meta text
  final Color accent; // fills and graphics — never small text
  final Color accentText; // accent-coloured text and icons
  final Color accentSurface; // tinted background for "active" surfaces
  final List<Color> heroGradient; // mic + swap button
  final double shadowOpacity;

  static const dark = _Palette(
    bg: Color(0xFF101219),
    surface: Color(0xFF191B24),
    surfaceMuted: Color(0xFF232634),
    border: Color(0xFF2E3140),
    textPrimary: Color(0xFFEDEFF5),
    textSecondary: Color(0xFFA3A6B5),
    textFaint: Color(0xFF7B7E8D),
    accent: Color(0xFFE8836B),
    accentText: Color(0xFFF3A48F),
    accentSurface: Color(0xFF2C2028),
    heroGradient: [Color(0xFFF0916F), Color(0xFFE06A5E)],
    shadowOpacity: 0.28,
  );

  static const light = _Palette(
    bg: Color(0xFFF5F6FA),
    surface: Colors.white,
    surfaceMuted: Color(0xFFE7EAF2),
    border: Color(0xFFE1E4EE),
    textPrimary: Color(0xFF16181F),
    textSecondary: Color(0xFF5C5F6E),
    textFaint: Color(0xFF696C7A),
    accent: Color(0xFFE0715A),
    accentText: Color(0xFFB34328),
    accentSurface: Color(0xFFFDEAE4),
    heroGradient: [Color(0xFFEE8A6C), Color(0xFFDE6A57)],
    shadowOpacity: 0.07,
  );
}

class SpeechScreen extends StatefulWidget {
  const SpeechScreen({super.key});

  @override
  State<SpeechScreen> createState() => _SpeechScreenState();
}

class _SpeechScreenState extends State<SpeechScreen>
    with TickerProviderStateMixin {
  // One icon scale for the whole app. Every icon is from the "rounded"
  // Material family and uses one of these three sizes (the mic and swap
  // buttons are the deliberate exceptions — they are the primary controls).
  // How long the undoable "New chat started" bar stays up. Kept well under
  // 6 seconds so it never lingers over the conversation.
  static const Duration _undoSnackDuration = Duration(seconds: 4);

  static const double _iconMeta = 12; // inline with small uppercase labels
  static const double _iconAction = 18; // tappable icons inside cards/bubbles
  static const double _iconNav = 20; // header buttons and list rows

  /// Colours for the theme currently in use.
  _Palette get _c => _isDarkMode ? _Palette.dark : _Palette.light;

  final SpeechToText _speech = SpeechToText();
  final FlutterTts _tts = FlutterTts();
  final AudioPlayer _audioPlayer = AudioPlayer();
  final ScrollController _chatScroll = ScrollController();

  bool _isInitialized = false;
  bool _isDarkMode = true;

  // true = conversation (chat) mode, false = quick translate mode.
  bool _conversationMode = true;

  // Which side is currently speaking. true = Language A (left dropdown).
  bool _activeIsTop = true;
  bool _isListening = false;
  bool _isRestartingListening = false;
  bool _isTranslating = false;
  String _currentSpoken = '';
  String _accumulatedSpoken = '';
  String _lastPartial = '';

  final List<ChatMessage> _messages = [];

  // Pinned/favourited messages that are no longer part of the live chat —
  // either quick translate results or leftovers from a previous conversation.
  final List<ChatMessage> _saved = [];

  // Quick translate mode state (single source + single translation).
  String _quickSource = '';
  ChatMessage? _quickResult;

  static const String _apiKey = 'YOUR_API_KEY_HERE';

  final Map<String, String> _translateCodes = {
    'English': 'en',
    'Hindi': 'hi',
    'Tamil': 'ta',
    'Telugu': 'te',
    'Kannada': 'kn',
    'Malayalam': 'ml',
    'Bengali': 'bn',
    'Marathi': 'mr',
    'Gujarati': 'gu',
    'Punjabi': 'pa',
    'Urdu': 'ur',
    'Spanish': 'es',
    'French': 'fr',
    'German': 'de',
    'Japanese': 'ja',
    'Chinese': 'zh',
    'Arabic': 'ar',
  };

  final Map<String, String> _speechLocales = {
    'English': 'en-US',
    'Hindi': 'hi-IN',
    'Tamil': 'ta-IN',
    'Telugu': 'te-IN',
    'Kannada': 'kn-IN',
    'Malayalam': 'ml-IN',
    'Bengali': 'bn-IN',
    'Marathi': 'mr-IN',
    'Gujarati': 'gu-IN',
    'Punjabi': 'pa-IN',
    'Urdu': 'ur-PK',
    'Spanish': 'es-ES',
    'French': 'fr-FR',
    'German': 'de-DE',
    'Japanese': 'ja-JP',
    'Chinese': 'zh-CN',
    'Arabic': 'ar-SA',
  };

  String _selectedLanguageTop = 'Hindi';
  String _selectedLanguageBottom = 'English';

  // Drives the swap animation: the two cards slide toward each other, fade
  // through the midpoint (where the values actually change) and settle back.
  late final AnimationController _swapCtrl;
  bool _pendingSwapApply = false;

  // Short pop played on the card whose language was just picked.
  late final AnimationController _pickCtrl;
  bool? _pickedIsTop;

  // Recording visuals: expanding rings behind the mic and the moving bars.
  late final AnimationController _rippleCtrl;
  late final AnimationController _waveCtrl;
  final Stopwatch _recordWatch = Stopwatch();
  // Smoothed 0..1 microphone level, drives the height of the waveform bars.
  double _soundLevel = 0;

  @override
  void initState() {
    super.initState();
    _rippleCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );
    _waveCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _swapCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    )..addListener(() {
        if (_pendingSwapApply && _swapCtrl.value >= 0.5) {
          _pendingSwapApply = false;
          setState(_applySwap);
        }
      });
    _pickCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );
    _initSpeech();
  }

  @override
  void dispose() {
    _rippleCtrl.dispose();
    _waveCtrl.dispose();
    _swapCtrl.dispose();
    _pickCtrl.dispose();
    _chatScroll.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  void _swapLanguages() {
    if (_swapCtrl.isAnimating) return;
    HapticFeedback.mediumImpact();
    _pendingSwapApply = true;
    _swapCtrl.forward(from: 0);
  }

  // Reverses the translation direction. Existing bubbles flip sides so that
  // "left bubble = top language" still holds after the swap.
  void _applySwap() {
    final previousTop = _selectedLanguageTop;
    _selectedLanguageTop = _selectedLanguageBottom;
    _selectedLanguageBottom = previousTop;
    for (final m in _messages) {
      m.isLeft = !m.isLeft;
    }
  }

  void _pickLanguage(bool isTop, String lang) {
    HapticFeedback.selectionClick();
    setState(() {
      _activeIsTop = isTop;
      if (isTop) {
        // Never let both sides hold the same language — push the old one over.
        if (lang == _selectedLanguageBottom) {
          _selectedLanguageBottom = _selectedLanguageTop;
        }
        _selectedLanguageTop = lang;
      } else {
        if (lang == _selectedLanguageTop) {
          _selectedLanguageTop = _selectedLanguageBottom;
        }
        _selectedLanguageBottom = lang;
      }
      _pickedIsTop = isTop;
    });
    _pickCtrl.forward(from: 0);
  }

  Future<void> _initSpeech() async {
    bool available = await _speech.initialize(
      onError: (error) async {
        print('[STT-DEBUG] onError: ${error.errorMsg} | isListening: $_isListening');
        if (_isListening && !_isRestartingListening) {
          _isRestartingListening = true;
          if (_currentSpoken.trim().isNotEmpty) {
            _accumulatedSpoken = _currentSpoken.trim();
          }
          await Future.delayed(const Duration(milliseconds: 250));
          if (_isListening) {
            await _startListening(keepAccumulated: true);
          }
          _isRestartingListening = false;
        } else if (!_isListening) {
          _endRecordingUi();
        }
      },
      onStatus: (status) async {
        print('[STT-DEBUG] onStatus: $status | isListening: $_isListening');
        if (status == 'done' || status == 'notListening') {
          if (_isListening && !_isRestartingListening) {
            _isRestartingListening = true;
            if (_currentSpoken.trim().isNotEmpty) {
              _accumulatedSpoken = _currentSpoken.trim();
            }
            await Future.delayed(const Duration(milliseconds: 250));
            if (_isListening) {
              await _startListening(keepAccumulated: true);
            }
            _isRestartingListening = false;
          } else if (!_isListening) {
            _endRecordingUi();
          }
        }
      },
    );
    if (available) {
      try {
        final locales = await _speech.locales();
        for (final entry in _translateCodes.entries) {
          final langName = entry.key;
          final code = entry.value;
          for (final l in locales) {
            final locId = l.localeId;
            if (locId.toLowerCase().startsWith(code.toLowerCase()) ||
                locId.toLowerCase().startsWith('${code}_'.toLowerCase()) ||
                locId.toLowerCase().startsWith('$code-'.toLowerCase())) {
              _speechLocales[langName] = locId;
              break;
            }
          }
        }
        print('[STT-DEBUG] Resolved speech locales: $_speechLocales');
      } catch (e) {
        print('[STT-DEBUG] Locales resolution error: $e');
      }
    }

    if (!mounted) return;
    setState(() => _isInitialized = available);
  }

  // Stops the recording timer and the ripple/waveform loops. Safe to call
  // more than once — the plugin fires both onStatus and our own stop.
  void _endRecordingUi() {
    print('[STT-DEBUG] _endRecordingUi called');
    _recordWatch.stop();
    _rippleCtrl.stop();
    _waveCtrl.stop();
    _soundLevel = 0;
    if (!mounted) return;
    setState(() => _isListening = false);
  }

  String _getChirpVoice(String locale) {
    final Map<String, String> voices = {
      'en-US': 'en-US-Chirp3-HD-Aoede',
      'hi-IN': 'hi-IN-Chirp3-HD-Aoede',
      'ta-IN': 'ta-IN-Chirp3-HD-Aoede',
      'te-IN': 'te-IN-Chirp3-HD-Aoede',
      'kn-IN': 'kn-IN-Chirp3-HD-Aoede',
      'ml-IN': 'ml-IN-Chirp3-HD-Aoede',
      'bn-IN': 'bn-IN-Chirp3-HD-Aoede',
      'mr-IN': 'mr-IN-Chirp3-HD-Aoede',
      'gu-IN': 'gu-IN-Chirp3-HD-Aoede',
      'pa-IN': 'pa-IN-Chirp3-HD-Aoede',
      'ur-PK': 'ur-PK-Wavenet-A',
      'es-ES': 'es-ES-Chirp3-HD-Aoede',
      'fr-FR': 'fr-FR-Chirp3-HD-Aoede',
      'de-DE': 'de-DE-Chirp3-HD-Aoede',
      'ja-JP': 'ja-JP-Chirp3-HD-Aoede',
      'zh-CN': 'cmn-CN-Chirp3-HD-Aoede',
      'ar-SA': 'ar-XA-Chirp3-HD-Aoede',
    };
    return voices[locale] ?? 'en-US-Chirp3-HD-Aoede';
  }

  Future<void> _speak(String text, String language, {double rate = 1.0}) async {
    final Map<String, String> ttsLocales = {
      'English': 'en-US',
      'Hindi': 'hi-IN',
      'Tamil': 'ta-IN',
      'Telugu': 'te-IN',
      'Kannada': 'kn-IN',
      'Malayalam': 'ml-IN',
      'Bengali': 'bn-IN',
      'Marathi': 'mr-IN',
      'Gujarati': 'gu-IN',
      'Punjabi': 'pa-IN',
      'Urdu': 'ur-PK',
      'Spanish': 'es-ES',
      'French': 'fr-FR',
      'German': 'de-DE',
      'Japanese': 'ja-JP',
      'Chinese': 'zh-CN',
      'Arabic': 'ar-SA',
    };

    final locale = ttsLocales[language] ?? 'en-US';

    final url = Uri.parse(
      'https://texttospeech.googleapis.com/v1/text:synthesize?key=$_apiKey',
    );

    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'input': {'text': text},
          'voice': {
            'languageCode': locale,
            'name': _getChirpVoice(locale),
          },
          'audioConfig': {
            'audioEncoding': 'MP3',
            'speakingRate': rate,
          },
        }),
      );

      print('TTS status code: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final audioContent = data['audioContent'];
        final bytes = base64Decode(audioContent);
        final dir = await getTemporaryDirectory();
        final file = File('${dir.path}/tts.mp3');
        await file.writeAsBytes(bytes);
        await _audioPlayer.stop();
        await _audioPlayer.play(DeviceFileSource(file.path));
      } else {
        print('TTS API error: ${response.body}');
        await _tts.setLanguage(locale);
        await _tts.setSpeechRate(rate < 1.0 ? 0.3 : 0.5);
        await _tts.speak(text);
      }
    } catch (e) {
      print('TTS error: $e');
      await _tts.setLanguage(locale);
      await _tts.setSpeechRate(rate < 1.0 ? 0.3 : 0.5);
      await _tts.speak(text);
    }
  }

  Future<void> _startListening({bool keepAccumulated = false}) async {
    if (!_isInitialized) await _initSpeech();

    final activeLang =
        _activeIsTop ? _selectedLanguageTop : _selectedLanguageBottom;
    final localeId = _speechLocales[activeLang]!;

    print('[STT-DEBUG] _startListening | keepAccumulated: $keepAccumulated | beforeAccumulated: "$_accumulatedSpoken" | beforeCurrent: "$_currentSpoken"');

    // Save existing spoken text into _accumulatedSpoken so pauses never erase previous words
    if (_currentSpoken.trim().isNotEmpty) {
      _accumulatedSpoken = _currentSpoken.trim();
    }

    setState(() {
      _isListening = true;
    });

    if (!keepAccumulated) {
      _accumulatedSpoken = '';
      _currentSpoken = '';
      _lastPartial = '';
    }

    if (!keepAccumulated) {
      _soundLevel = 0;
      _recordWatch
        ..reset()
        ..start();
      _rippleCtrl.repeat();
      _waveCtrl.repeat();
    }

    try {
      await _speech.stop();
    } catch (_) {}

    try {
      await _speech.listen(
        onResult: (SpeechRecognitionResult result) {
          final newWords = result.recognizedWords.trim();
          if (newWords.isEmpty) return;

          // Detect if native STT started a new phrase batch after a silence pause
          if (_lastPartial.isNotEmpty &&
              !newWords.toLowerCase().startsWith(_lastPartial.toLowerCase())) {
            if (_currentSpoken.trim().isNotEmpty) {
              _accumulatedSpoken = _currentSpoken.trim();
            }
          }

          _lastPartial = newWords;

          final activeLang =
              _activeIsTop ? _selectedLanguageTop : _selectedLanguageBottom;
          final code = _translateCodes[activeLang] ?? 'en';
          final needsSpace = (code != 'zh' && code != 'ja');

          final combined = _accumulatedSpoken.isEmpty
              ? newWords
              : (needsSpace
                      ? '$_accumulatedSpoken $newWords'
                      : '$_accumulatedSpoken$newWords')
                  .trim();

          print('[STT-DEBUG] onResult | lang: $activeLang ($code) | newWords: "$newWords" | finalResult: ${result.finalResult} | combined: "$combined"');

          if (mounted) {
            setState(() {
              _currentSpoken = combined;
            });
          }

          if (result.finalResult && newWords.isNotEmpty) {
            _accumulatedSpoken = combined;
            _lastPartial = '';
          }
        },
        // Feeds the waveform. No setState — the wave controller already
        // repaints every frame while listening.
        onSoundLevelChange: (level) {
          final normalised = ((level + 2) / 12).clamp(0.0, 1.0);
          _soundLevel = _soundLevel * 0.7 + normalised * 0.3;
        },
        localeId: localeId,
        listenFor: const Duration(seconds: 60),
        pauseFor: const Duration(seconds: 60),
        partialResults: true,
        listenMode: ListenMode.dictation,
      );
    } catch (e) {
      print('[STT-DEBUG] Listen attempt error: $e');
    }
  }

  Future<void> _stopListening() async {
    print('[STT-DEBUG] _stopListening called | currentSpoken: "$_currentSpoken" | accumulatedSpoken: "$_accumulatedSpoken"');
    setState(() => _isListening = false);
    await _speech.stop();
    await Future.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;
    _endRecordingUi();

    final text = _currentSpoken.trim();

    // Clear accumulated and current spoken string when the mic is let go
    _accumulatedSpoken = '';
    _currentSpoken = '';
    _lastPartial = '';

    if (text.isNotEmpty) {
      if (_conversationMode) {
        await _translateAndAdd(text);
      } else {
        await _translateQuick(text);
      }
    }
  }

  Future<void> _translateAndAdd(String text) async {
    final sourceLang =
        _activeIsTop ? _selectedLanguageTop : _selectedLanguageBottom;
    final targetLang =
        _activeIsTop ? _selectedLanguageBottom : _selectedLanguageTop;
    // Left/grey bubbles carry Language A (top); right/orange carry Language B.
    final isLeft = targetLang == _selectedLanguageTop;

    setState(() => _isTranslating = true);
    _scrollToBottom();

    final url = Uri.parse(
      'https://translation.googleapis.com/language/translate/v2?key=$_apiKey',
    );

    String? translated;
    var ok = false;
    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'q': text,
          'source': _translateCodes[sourceLang]!,
          'target': _translateCodes[targetLang]!,
          'format': 'text',
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        translated = data['data']['translations'][0]['translatedText'];
        ok = true;
      } else {
        translated = 'Translation failed. Try again.';
      }
    } catch (e) {
      translated = 'Error: Check internet connection.';
    }

    setState(() {
      _isTranslating = false;
      _messages.add(ChatMessage(
        text: translated!,
        language: targetLang,
        isLeft: isLeft,
        time: DateTime.now(),
      ));
      // Back-and-forth: on a successful translation, automatically hand the
      // mic to the other language so the reply is ready. A failed attempt
      // keeps the same side active so it can be retried.
      if (ok) _activeIsTop = !_activeIsTop;
    });
    _scrollToBottom();
  }

  // Quick translate: one source -> one translation, no conversation history
  // and no automatic side switching.
  Future<void> _translateQuick(String text) async {
    final sourceLang =
        _activeIsTop ? _selectedLanguageTop : _selectedLanguageBottom;
    final targetLang =
        _activeIsTop ? _selectedLanguageBottom : _selectedLanguageTop;
    final isLeft = targetLang == _selectedLanguageTop;

    setState(() {
      _quickSource = text;
      _quickResult = null;
      _isTranslating = true;
    });

    final url = Uri.parse(
      'https://translation.googleapis.com/language/translate/v2?key=$_apiKey',
    );

    String? translated;
    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'q': text,
          'source': _translateCodes[sourceLang]!,
          'target': _translateCodes[targetLang]!,
          'format': 'text',
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        translated = data['data']['translations'][0]['translatedText'];
      } else {
        translated = 'Translation failed. Try again.';
      }
    } catch (e) {
      translated = 'Error: Check internet connection.';
    }

    setState(() {
      _isTranslating = false;
      _quickResult = ChatMessage(
        text: translated!,
        language: targetLang,
        isLeft: isLeft,
        time: DateTime.now(),
      );
    });
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_chatScroll.hasClients) {
        _chatScroll.animateTo(
          _chatScroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  String _formatTime(DateTime t) {
    final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final m = t.minute.toString().padLeft(2, '0');
    final ampm = t.hour < 12 ? 'AM' : 'PM';
    return '$h:$m $ampm';
  }

  // ---------------------------------------------------------------- UI

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _c.bg,
      body: SafeArea(
        child:
            _conversationMode ? _buildConversation() : _buildQuickTranslate(),
      ),
    );
  }

  Widget _buildConversation() {
    return Column(
      children: [
        _buildHeader(),
        Expanded(child: _buildChatList()),
        if (_isListening) _buildLiveTranscript(),
        _buildMicBar(),
      ],
    );
  }

  Widget _buildQuickTranslate() {
    return Column(
      children: [
        _buildHeader(),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
            child: Column(
              children: [
                _buildSourceBox(),
                const SizedBox(height: 10),
                Icon(Icons.keyboard_double_arrow_down_rounded,
                    size: _iconAction, color: _c.accentText),
                const SizedBox(height: 10),
                _buildTranslationBox(),
              ],
            ),
          ),
        ),
        _buildMicBar(),
      ],
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        children: [
          Row(
            children: [
              Text(
                'Speech Translator',
                style: TextStyle(
                  color: _c.textPrimary,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              _buildNewChatButton(),
              const SizedBox(width: 8),
              _buildSettingsButton(),
              const SizedBox(width: 8),
              _buildThemeToggle(),
            ],
          ),
          const SizedBox(height: 14),
          _buildLanguageBar(),
        ],
      ),
    );
  }

  // Two language dropdown boxes with a large swap button between them.
  Widget _buildLanguageBar() {
    return AnimatedBuilder(
      animation: Listenable.merge([_swapCtrl, _pickCtrl]),
      builder: (context, _) {
        // 0 → 1 → 0 across the swap, so the cards travel out and come back.
        final travel =
            Curves.easeInOut.transform(1 - (2 * _swapCtrl.value - 1).abs());
        final dx = travel * 20;
        final fade = 1 - travel * 0.7;

        Widget slide(bool isTop) {
          return Expanded(
            child: Transform.translate(
              offset: Offset(isTop ? dx : -dx, 0),
              child: Opacity(opacity: fade, child: _langCard(isTop: isTop)),
            ),
          );
        }

        return Row(
          children: [
            slide(true),
            const SizedBox(width: 10),
            _buildSwapButton(),
            const SizedBox(width: 10),
            slide(false),
          ],
        );
      },
    );
  }

  Widget _langCard({required bool isTop}) {
    final active = isTop == _activeIsTop;
    final value = isTop ? _selectedLanguageTop : _selectedLanguageBottom;

    // The active side is a tinted card rather than a saturated fill: it still
    // reads as selected, but keeps the text at full contrast.
    final labelColor = active ? _c.accentText : _c.textSecondary;
    final valueColor = active ? _c.accentText : _c.textPrimary;

    // A short pop on the card that was just changed.
    final pulse = _pickedIsTop == isTop
        ? 1 + 0.06 * math.sin(math.pi * _pickCtrl.value)
        : 1.0;

    return Transform.scale(
      scale: pulse,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
        decoration: BoxDecoration(
          color: active ? _c.accentSurface : _c.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: active ? _c.accent.withOpacity(0.55) : _c.border,
            width: 1.5,
          ),
          boxShadow: active
              ? [
                  BoxShadow(
                    color: _c.accent.withOpacity(0.14),
                    blurRadius: 12,
                    offset: const Offset(0, 3),
                  ),
                ]
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(
                  active ? Icons.mic_rounded : Icons.south_east_rounded,
                  size: _iconMeta,
                  color: labelColor,
                ),
                const SizedBox(width: 4),
                Text(
                  active ? 'SPEAKING' : 'TRANSLATE TO',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.9,
                    color: labelColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: value,
                isExpanded: true,
                isDense: true,
                menuMaxHeight: 340,
                dropdownColor: _c.surface,
                borderRadius: BorderRadius.circular(16),
                icon: Icon(Icons.expand_more_rounded,
                    size: _iconNav, color: valueColor),
                // Tapping a box makes that side the active (speaking) one,
                // overriding the automatic back-and-forth alternation.
                onTap: () => setState(() => _activeIsTop = isTop),
                onChanged: (v) {
                  if (v != null) _pickLanguage(isTop, v);
                },
                // Closed state: plain name, no tick mark.
                selectedItemBuilder: (_) => _translateCodes.keys
                    .map((lang) => Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            lang,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: valueColor,
                            ),
                          ),
                        ))
                    .toList(),
                items: _translateCodes.keys.map((lang) {
                  final selected = lang == value;
                  return DropdownMenuItem(
                    value: lang,
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            lang,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight:
                                  selected ? FontWeight.w700 : FontWeight.w500,
                              color: selected ? _c.accentText : _c.textPrimary,
                            ),
                          ),
                        ),
                        if (selected)
                          Icon(Icons.check_rounded,
                              size: _iconAction, color: _c.accentText),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSwapButton() {
    return GestureDetector(
      onTap: _swapLanguages,
      child: Transform.rotate(
        angle: Curves.easeInOutCubic.transform(_swapCtrl.value) * math.pi,
        child: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: _c.heroGradient,
            ),
            boxShadow: [
              BoxShadow(
                color: _c.accent.withOpacity(0.22),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: const Icon(Icons.swap_horiz_rounded,
              color: Colors.white, size: 30),
        ),
      ),
    );
  }

  Widget _buildChatList() {
    if (_messages.isEmpty && !_isTranslating) {
      return _buildEmptyState();
    }

    return ListView.builder(
      controller: _chatScroll,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      itemCount: _messages.length + (_isTranslating ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == _messages.length) {
          return _buildTypingIndicator();
        }
        return _buildBubble(_messages[index]);
      },
    );
  }

  // Shown before the first translation, in place of the chat list.
  Widget _buildEmptyState() {
    final dark = _isDarkMode;

    // Scrolls instead of overflowing on short screens (small phones in
    // landscape, or with a large system font scale).
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: math.max(0, constraints.maxHeight - 40),
          ),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        _c.accent.withOpacity(dark ? 0.20 : 0.14),
                        _c.accent.withOpacity(dark ? 0.06 : 0.05),
                      ],
                    ),
                  ),
                  child: Icon(Icons.mic_none_rounded,
                      size: 42, color: _c.accentText),
                ),
                const SizedBox(height: 18),
                Text(
                  'Hold the microphone',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _c.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'to start translating',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _c.textSecondary,
                    fontSize: 15,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  '$_selectedLanguageTop  ⇄  $_selectedLanguageBottom',
                  style: TextStyle(
                    color: _c.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBubble(ChatMessage msg) {
    final isLeft = msg.isLeft;

    final bubble = Container(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.72,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        // Side B is accent-tinted rather than accent-filled, so the message
        // text keeps full contrast in both themes.
        color: isLeft ? _c.surfaceMuted : _c.accentSurface,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(20),
          topRight: const Radius.circular(20),
          bottomLeft: Radius.circular(isLeft ? 6 : 20),
          bottomRight: Radius.circular(isLeft ? 20 : 6),
        ),
        border: isLeft ? null : Border.all(color: _c.accent.withOpacity(0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            msg.text,
            style: TextStyle(
              fontSize: 15,
              height: 1.4,
              fontWeight: FontWeight.w500,
              color: _c.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _bubbleIconButton(
                icon: Icons.volume_up_rounded,
                isLeft: isLeft,
                onTap: () => _speak(msg.text, msg.language),
              ),
              const SizedBox(width: 6),
              _bubbleIconButton(
                icon: Icons.slow_motion_video_rounded,
                isLeft: isLeft,
                onTap: () => _speak(msg.text, msg.language, rate: 0.5),
              ),
              const SizedBox(width: 6),
              _bubbleIconButton(
                icon: Icons.more_horiz_rounded,
                isLeft: isLeft,
                onTap: () => _showMessageActions(msg),
              ),
            ],
          ),
        ],
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment:
            isLeft ? CrossAxisAlignment.start : CrossAxisAlignment.end,
        children: [
          bubble,
          Padding(
            padding: EdgeInsets.only(
              top: 4,
              left: isLeft ? 8 : 0,
              right: isLeft ? 0 : 8,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _formatTime(msg.time),
                  style: TextStyle(fontSize: 10, color: _c.textFaint),
                ),
                if (msg.isPinned) ...[
                  const SizedBox(width: 6),
                  Icon(Icons.push_pin_rounded,
                      size: _iconMeta, color: _c.textFaint),
                ],
                if (msg.isFavourite) ...[
                  const SizedBox(width: 6),
                  Icon(Icons.favorite_rounded,
                      size: _iconMeta, color: _c.accentText),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _bubbleIconButton({
    required IconData icon,
    required bool isLeft,
    required VoidCallback onTap,
  }) {
    final bg = isLeft ? _c.border : _c.accent.withOpacity(0.16);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(shape: BoxShape.circle, color: bg),
        child: Icon(icon, size: _iconAction, color: _c.accentText),
      ),
    );
  }

  Widget _buildTypingIndicator() {
    final isLeft = !_activeIsTop;

    return Align(
      alignment: isLeft ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: BoxDecoration(
          color: _c.surfaceMuted,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _dot(_c.textSecondary),
            const SizedBox(width: 5),
            _dot(_c.textSecondary),
            const SizedBox(width: 5),
            _dot(_c.textSecondary),
          ],
        ),
      ),
    );
  }

  Widget _dot(Color c) => Container(
        width: 6,
        height: 6,
        decoration: BoxDecoration(shape: BoxShape.circle, color: c),
      );

  String _formatElapsed(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Widget _buildMicBar() {
    final activeLang =
        _activeIsTop ? _selectedLanguageTop : _selectedLanguageBottom;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            child: _isListening
                ? _buildRecordingStrip()
                : const SizedBox(width: double.infinity),
          ),
          _buildMicButton(),
          const SizedBox(height: 8),
          Text(
            (_isListening
                    ? 'Release to translate'
                    : 'Hold to speak · $activeLang')
                .toUpperCase(),
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.2,
              color: _c.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  // "● LISTENING 00:08  ~~~~~~" strip shown above the mic while recording.
  Widget _buildRecordingStrip() {
    final dark = _isDarkMode;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AnimatedBuilder(
        animation: Listenable.merge([_rippleCtrl, _waveCtrl]),
        builder: (context, _) {
          final blink = 0.45 + 0.55 * (1 - (2 * _rippleCtrl.value - 1).abs());
          return Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: _c.accent.withOpacity(dark ? 0.16 : 0.10),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Opacity(
                      opacity: blink,
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _c.accentText,
                        ),
                      ),
                    ),
                    const SizedBox(width: 7),
                    Text(
                      'LISTENING',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.9,
                        color: _c.accentText,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _formatElapsed(_recordWatch.elapsed),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        fontFeatures: const [FontFeature.tabularFigures()],
                        color: _c.accentText,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SizedBox(
                  height: 34,
                  child: CustomPaint(
                    painter: _WaveformPainter(
                      phase: _waveCtrl.value,
                      level: _soundLevel,
                      color: _c.accent,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildMicButton() {
    final size = _isListening ? 88.0 : 76.0;

    return SizedBox(
      width: 132,
      height: 132,
      child: AnimatedBuilder(
        animation: _rippleCtrl,
        builder: (context, child) {
          // Two rings a half-cycle apart, expanding out of the button.
          final rings = _isListening
              ? [0.0, 0.5].map((offset) {
                  final t = (_rippleCtrl.value + offset) % 1.0;
                  return Container(
                    width: size * (1 + 0.5 * t),
                    height: size * (1 + 0.5 * t),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _c.accent.withOpacity(0.18 * (1 - t)),
                    ),
                  );
                }).toList()
              : const <Widget>[];

          return Stack(
            alignment: Alignment.center,
            children: [...rings, child!],
          );
        },
        child: GestureDetector(
          onLongPressStart: (_) => _startListening(),
          onLongPressEnd: (_) => _stopListening(),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutBack,
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: _c.heroGradient,
              ),
              boxShadow: [
                BoxShadow(
                  color: _c.accent.withOpacity(_isListening ? 0.32 : 0.22),
                  blurRadius: _isListening ? 20 : 14,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Icon(
              _isListening ? Icons.mic_rounded : Icons.mic_none_rounded,
              color: Colors.white,
              size: 38,
            ),
          ),
        ),
      ),
    );
  }

  // The round buttons in the top-right corner.
  Widget _headerButton({
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: _c.surface,
          border: Border.all(color: _c.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(_c.shadowOpacity),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Icon(icon, color: color, size: _iconNav),
      ),
    );
  }

  Widget _buildThemeToggle() {
    return _headerButton(
      icon: _isDarkMode ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
      color: _c.accentText,
      onTap: () => setState(() => _isDarkMode = !_isDarkMode),
    );
  }

  Widget _buildSettingsButton() {
    return _headerButton(
      icon: Icons.settings_rounded,
      color: _c.textSecondary,
      onTap: _openSaved,
    );
  }

  Widget _buildNewChatButton() {
    return _headerButton(
      icon: Icons.refresh_rounded,
      color: _c.textSecondary,
      onTap: _startNewChat,
    );
  }

  // Live speech-to-text preview shown above the mic while listening.
  Widget _buildLiveTranscript() {
    final activeLang =
        _activeIsTop ? _selectedLanguageTop : _selectedLanguageBottom;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _c.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _c.accent.withOpacity(0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.graphic_eq_rounded,
              color: _c.accentText, size: _iconAction),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _currentSpoken.isEmpty
                  ? 'Listening ($activeLang)…'
                  : _currentSpoken,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                height: 1.3,
                color:
                    _currentSpoken.isEmpty ? _c.textSecondary : _c.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---- Quick translate boxes ----

  // Shared shell for the two quick-translate cards: tight padding, rounded
  // corners and a light shadow. The translated card is tinted with the accent
  // so the two are never confused for each other.
  BoxDecoration _quickCardDecoration({required bool isTranslation}) {
    return BoxDecoration(
      color: isTranslation ? _c.accentSurface : _c.surface,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(
        color: isTranslation ? _c.accent.withOpacity(0.35) : _c.border,
      ),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(_c.shadowOpacity),
          blurRadius: 14,
          offset: const Offset(0, 4),
        ),
      ],
    );
  }

  Widget _cardLabel(String text, Color color, IconData icon) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: _iconMeta, color: color),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.9,
              color: color,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSourceBox() {
    final sourceLang =
        _activeIsTop ? _selectedLanguageTop : _selectedLanguageBottom;

    final showLive = _isListening;
    final content = showLive
        ? (_currentSpoken.isEmpty ? 'Listening…' : _currentSpoken)
        : (_quickSource.isEmpty ? 'Hold the mic to speak…' : _quickSource);
    final isPlaceholder =
        showLive ? _currentSpoken.isEmpty : _quickSource.isEmpty;

    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 88),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      decoration: _quickCardDecoration(isTranslation: false),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _cardLabel(
                'SOURCE · ${sourceLang.toUpperCase()}',
                _c.textSecondary,
                showLive ? Icons.graphic_eq_rounded : Icons.mic_none_rounded,
              ),
              const Spacer(),
              if (_quickSource.isNotEmpty && !_isListening)
                GestureDetector(
                  onTap: () => _speak(_quickSource, sourceLang),
                  child: Icon(Icons.volume_up_rounded,
                      color: _c.accentText, size: _iconAction),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            content,
            style: TextStyle(
              fontSize: 17,
              height: 1.35,
              fontWeight: FontWeight.w500,
              color: isPlaceholder ? _c.textSecondary : _c.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTranslationBox() {
    final result = _quickResult;
    final targetLang =
        _activeIsTop ? _selectedLanguageBottom : _selectedLanguageTop;

    final content = _isTranslating
        ? 'Translating…'
        : (result == null ? 'The translation will appear here…' : result.text);
    final isPlaceholder = result == null;

    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 88),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      decoration: _quickCardDecoration(isTranslation: true),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _cardLabel(
                'TRANSLATION · ${(result?.language ?? targetLang).toUpperCase()}',
                _c.accentText,
                Icons.translate_rounded,
              ),
              const Spacer(),
              if (result != null) ...[
                GestureDetector(
                  onTap: () => _speak(result.text, result.language),
                  child: Icon(Icons.volume_up_rounded,
                      color: _c.accentText, size: _iconAction),
                ),
                const SizedBox(width: 12),
                GestureDetector(
                  onTap: () => _speak(result.text, result.language, rate: 0.5),
                  child: Icon(Icons.slow_motion_video_rounded,
                      color: _c.accentText, size: _iconAction),
                ),
                const SizedBox(width: 12),
                GestureDetector(
                  onTap: () => _showMessageActions(result),
                  child: Icon(Icons.more_horiz_rounded,
                      color: _c.accentText, size: _iconAction),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Text(
            content,
            style: TextStyle(
              fontSize: 20,
              height: 1.35,
              fontWeight: FontWeight.w600,
              color: isPlaceholder ? _c.textSecondary : _c.accentText,
            ),
          ),
        ],
      ),
    );
  }

  // Copy / Share / Pin / Favourite for a single message.
  void _showMessageActions(ChatMessage msg) {
    showModalBottomSheet(
      context: context,
      backgroundColor: _c.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 10),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: _c.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    msg.text,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: _c.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
              _actionTile(Icons.replay_rounded, 'Redo translation', () {
                Navigator.pop(ctx);
                _redoMessage(msg);
              }),
              _actionTile(Icons.copy_rounded, 'Copy', () {
                Navigator.pop(ctx);
                _copyMessage(msg);
              }),
              _actionTile(Icons.share_rounded, 'Share', () {
                Navigator.pop(ctx);
                _snack('Share coming soon');
              }),
              _actionTile(
                msg.isPinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
                msg.isPinned ? 'Unpin' : 'Pin',
                () {
                  Navigator.pop(ctx);
                  setState(() {
                    msg.isPinned = !msg.isPinned;
                    _trackIfSaved(msg);
                  });
                  _snack(msg.isPinned ? 'Pinned' : 'Unpinned');
                },
              ),
              _actionTile(
                msg.isFavourite
                    ? Icons.favorite_rounded
                    : Icons.favorite_border_rounded,
                msg.isFavourite ? 'Remove favourite' : 'Favourite',
                () {
                  Navigator.pop(ctx);
                  setState(() {
                    msg.isFavourite = !msg.isFavourite;
                    _trackIfSaved(msg);
                  });
                },
              ),
              const SizedBox(height: 10),
            ],
          ),
        );
      },
    );
  }

  Widget _actionTile(IconData icon, String label, VoidCallback onTap) {
    return ListTile(
      leading: Icon(icon, size: _iconNav, color: _c.accentText),
      title: Text(
        label,
        style: TextStyle(
            color: _c.textPrimary, fontSize: 15, fontWeight: FontWeight.w500),
      ),
      onTap: onTap,
    );
  }

  void _copyMessage(ChatMessage msg) {
    Clipboard.setData(ClipboardData(text: msg.text));
    _snack('Copied to clipboard');
  }

  // Keeps [_saved] in step with a message's pin/favourite flags, so quick
  // translate results and messages from earlier chats stay in the saved list.
  void _trackIfSaved(ChatMessage msg) {
    if (msg.isPinned || msg.isFavourite) {
      if (!_messages.contains(msg) && !_saved.contains(msg)) _saved.add(msg);
    } else {
      _saved.remove(msg);
    }
  }

  // Clears the conversation and starts over. Pinned and favourited messages
  // move to [_saved] rather than being destroyed, and the whole thing is
  // undoable for as long as the snack bar is up.
  void _startNewChat() {
    if (_messages.isEmpty && _quickResult == null && _quickSource.isEmpty) {
      _snack('Already a new chat');
      return;
    }

    final previousMessages = List<ChatMessage>.from(_messages);
    final previousSource = _quickSource;
    final previousResult = _quickResult;
    final moved = _messages
        .where((m) => (m.isPinned || m.isFavourite) && !_saved.contains(m))
        .toList();

    HapticFeedback.mediumImpact();
    setState(() {
      _saved.addAll(moved);
      _messages.clear();
      _quickSource = '';
      _quickResult = null;
      _currentSpoken = '';
    });

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: const Text('New chat started'),
          duration: _undoSnackDuration,
          action: SnackBarAction(
            label: 'UNDO',
            onPressed: () => setState(() {
              _messages
                ..clear()
                ..addAll(previousMessages);
              _quickSource = previousSource;
              _quickResult = previousResult;
              _saved.removeWhere(moved.contains);
            }),
          ),
        ),
      );
  }

  // Delete the message and re-arm the mic for whoever originally spoke it,
  // so the translation can be done again.
  void _redoMessage(ChatMessage msg) {
    setState(() {
      if (identical(msg, _quickResult)) {
        // Quick translate: just clear the boxes, keep the same source side.
        _quickResult = null;
        _quickSource = '';
      } else {
        _messages.remove(msg);
        // The original speaker was the side opposite the bubble's language.
        _activeIsTop = !msg.isLeft;
      }
    });
    final lang = _activeIsTop ? _selectedLanguageTop : _selectedLanguageBottom;
    _snack('Removed — hold the mic to redo ($lang)');
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 1)),
    );
  }

  // Settings sheet: shows pinned messages and favourites.
  void _openSaved() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: _c.bg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheet) {
            final all = [..._messages, ..._saved];
            final pinned = all.where((m) => m.isPinned).toList();
            final favs = all.where((m) => m.isFavourite).toList();
            return SizedBox(
              height: MediaQuery.of(context).size.height * 0.7,
              child: Column(
                children: [
                  const SizedBox(height: 10),
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: _c.border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Settings',
                        style: TextStyle(
                          color: _c.textPrimary,
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                      children: [
                        _settingsSectionHeader('MODE'),
                        _modeTile(
                          'Conversation mode',
                          Icons.chat_bubble_outline_rounded,
                          _conversationMode,
                          () {
                            setState(() => _conversationMode = true);
                            Navigator.pop(ctx);
                          },
                        ),
                        _modeTile(
                          'Quick translate',
                          Icons.bolt_rounded,
                          !_conversationMode,
                          () {
                            setState(() => _conversationMode = false);
                            Navigator.pop(ctx);
                          },
                        ),
                        const SizedBox(height: 20),
                        _savedSectionHeader(
                            'PINNED', Icons.push_pin_rounded, pinned.length),
                        if (pinned.isEmpty)
                          _savedEmpty('No pinned messages')
                        else
                          ...pinned.map((m) => _savedTile(
                                m,
                                isPinnedSection: true,
                                setSheet: setSheet,
                              )),
                        const SizedBox(height: 20),
                        _savedSectionHeader(
                            'FAVOURITES', Icons.favorite_rounded, favs.length),
                        if (favs.isEmpty)
                          _savedEmpty('No favourites yet')
                        else
                          ...favs.map((m) => _savedTile(
                                m,
                                isPinnedSection: false,
                                setSheet: setSheet,
                              )),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _settingsSectionHeader(String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, left: 4),
      child: Text(
        label,
        style: TextStyle(
          color: _c.accentText,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.0,
        ),
      ),
    );
  }

  Widget _modeTile(
    String label,
    IconData icon,
    bool selected,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected ? _c.accentSurface : _c.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? _c.accent.withOpacity(0.55) : _c.border,
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            Icon(icon,
                color: selected ? _c.accentText : _c.textSecondary,
                size: _iconNav),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: _c.textPrimary,
                  fontSize: 15,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
            if (selected)
              Icon(Icons.check_circle_rounded,
                  color: _c.accentText, size: _iconNav),
          ],
        ),
      ),
    );
  }

  Widget _savedSectionHeader(String label, IconData icon, int count) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, left: 4),
      child: Row(
        children: [
          Icon(icon, size: _iconMeta, color: _c.accentText),
          const SizedBox(width: 8),
          Text(
            '$label ($count)',
            style: TextStyle(
              color: _c.accentText,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.0,
            ),
          ),
        ],
      ),
    );
  }

  Widget _savedEmpty(String message) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 4),
      child: Text(message,
          style: TextStyle(color: _c.textSecondary, fontSize: 13)),
    );
  }

  Widget _savedTile(
    ChatMessage m, {
    required bool isPinnedSection,
    required StateSetter setSheet,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _c.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _c.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  m.text,
                  style: TextStyle(
                      color: _c.textPrimary, fontSize: 14, height: 1.3),
                ),
                const SizedBox(height: 4),
                Text(
                  '${m.language} · ${_formatTime(m.time)}',
                  style: TextStyle(color: _c.textFaint, fontSize: 10),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => _speak(m.text, m.language),
            child: Icon(Icons.volume_up_rounded,
                color: _c.accentText, size: _iconAction),
          ),
          const SizedBox(width: 14),
          GestureDetector(
            onTap: () {
              setState(() {
                if (isPinnedSection) {
                  m.isPinned = false;
                } else {
                  m.isFavourite = false;
                }
                _trackIfSaved(m);
              });
              setSheet(() {});
            },
            child: Icon(
              isPinnedSection ? Icons.push_pin_rounded : Icons.favorite_rounded,
              color: isPinnedSection ? _c.textSecondary : _c.accentText,
              size: _iconAction,
            ),
          ),
        ],
      ),
    );
  }
}

/// Scrolling bar waveform drawn while the mic is listening. [phase] is the
/// 0..1 animation position and [level] the smoothed microphone loudness, so
/// the bars keep moving on silence but jump when the user actually speaks.
class _WaveformPainter extends CustomPainter {
  const _WaveformPainter({
    required this.phase,
    required this.level,
    required this.color,
  });

  final double phase;
  final double level;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const barWidth = 3.0;
    const gap = 4.0;
    final count = (size.width / (barWidth + gap)).floor();
    if (count <= 0) return;

    final mid = size.height / 2;
    final travel = phase * 2 * math.pi;
    // Quiet input still ripples gently; loud input uses the full height.
    final envelope = 0.3 + 0.7 * level;

    for (var i = 0; i < count; i++) {
      final wave = 0.5 + 0.5 * math.sin(travel * 2 + i * 0.55);
      // Taper the ends so the waveform fades out instead of cutting off.
      final edge = math.sin(math.pi * (i + 0.5) / count);
      final height = (size.height * (0.12 + 0.88 * wave * envelope) * edge)
          .clamp(3.0, size.height);
      final x = i * (barWidth + gap);

      final paint = Paint()
        ..color = color.withOpacity(0.35 + 0.65 * wave)
        ..style = PaintingStyle.fill;

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, mid - height / 2, barWidth, height),
          const Radius.circular(2),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_WaveformPainter old) =>
      old.phase != phase || old.level != level || old.color != color;
}
