import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:io';
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
  colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF4285F4)),
  useMaterial3: true,
  textTheme: GoogleFonts.puritanTextTheme(),
),
      home: const SpeechScreen(),
    );
  }
}

class SpeechScreen extends StatefulWidget {
  const SpeechScreen({super.key});

  @override
  State<SpeechScreen> createState() => _SpeechScreenState();
}

class _SpeechScreenState extends State<SpeechScreen> {
  final SpeechToText _speech = SpeechToText();
  final FlutterTts _tts = FlutterTts();
  final AudioPlayer _audioPlayer = AudioPlayer();
  final ScrollController _scrollTop = ScrollController();
  final ScrollController _scrollBottom = ScrollController();
  bool _isInitialized = false;
  bool _isDarkMode = true;

  String _spokenTextTop = '';
  String _translatedTextTop = '';
  String _spokenTextBottom = '';
  String _translatedTextBottom = '';

  bool _isListeningTop = false;
  bool _isListeningBottom = false;
  bool _isTranslatingTop = false;
  bool _isTranslatingBottom = false;

  static const String _apiKey = 'AIzaSyCuHDGdtncRsr7e7nF1yRIqDkRYzFYh6Yo';

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
    'English': 'en_US',
    'Hindi': 'hi_IN',
    'Tamil': 'ta_IN',
    'Telugu': 'te_IN',
    'Kannada': 'kn_IN',
    'Malayalam': 'ml_IN',
    'Bengali': 'bn_IN',
    'Marathi': 'mr_IN',
    'Gujarati': 'gu_IN',
    'Punjabi': 'pa_IN',
    'Urdu': 'ur_PK',
    'Spanish': 'es_ES',
    'French': 'fr_FR',
    'German': 'de_DE',
    'Japanese': 'ja_JP',
    'Chinese': 'zh_CN',
    'Arabic': 'ar_SA',
  };

  final Map<String, String> _ttsLocales = {
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

  @override
  void initState() {
    super.initState();
    _initSpeech();
  }

  @override
  void dispose() {
    _scrollTop.dispose();
    _scrollBottom.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  Future<void> _initSpeech() async {
    bool available = await _speech.initialize(
      onError: (error) {
        setState(() {
          _isListeningTop = false;
          _isListeningBottom = false;
        });
      },
      onStatus: (status) {
        if (status == 'done' || status == 'notListening') {
          setState(() {
            _isListeningTop = false;
            _isListeningBottom = false;
          });
        }
      },
    );
    setState(() => _isInitialized = available);
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

  Future<void> _translate(String text, bool isTop) async {
    if (text.isEmpty) return;

    if (isTop) {
      setState(() => _isTranslatingTop = true);
    } else {
      setState(() => _isTranslatingBottom = true);
    }

    final sourceLangCode = isTop
        ? _translateCodes[_selectedLanguageTop]!
        : _translateCodes[_selectedLanguageBottom]!;

    final targetLangCode = isTop
        ? _translateCodes[_selectedLanguageBottom]!
        : _translateCodes[_selectedLanguageTop]!;

    final url = Uri.parse(
      'https://translation.googleapis.com/language/translate/v2?key=$_apiKey',
    );

    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'q': text,
          'source': sourceLangCode,
          'target': targetLangCode,
          'format': 'text',
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final translated =
            data['data']['translations'][0]['translatedText'];
        setState(() {
          if (isTop) {
            _translatedTextBottom = translated;
          } else {
            _translatedTextTop = translated;
          }
        });
      } else {
        setState(() {
          if (isTop) {
            _translatedTextBottom = 'Translation failed. Try again.';
          } else {
            _translatedTextTop = 'Translation failed. Try again.';
          }
        });
      }
    } catch (e) {
      setState(() {
        if (isTop) {
          _translatedTextBottom = 'Error: Check internet connection.';
        } else {
          _translatedTextTop = 'Error: Check internet connection.';
        }
      });
    }

    if (isTop) {
      setState(() => _isTranslatingTop = false);
    } else {
      setState(() => _isTranslatingBottom = false);
    }
  }

  Future<void> _startListening(bool isTop) async {
    if (!_isInitialized) await _initSpeech();

    final localeId = isTop
        ? _speechLocales[_selectedLanguageTop]!
        : _speechLocales[_selectedLanguageBottom]!;

    setState(() {
      if (isTop) {
        _isListeningTop = true;
        _spokenTextTop = 'Listening...';
        _translatedTextTop = '';
        _translatedTextBottom = '';
      } else {
        _isListeningBottom = true;
        _spokenTextBottom = 'Listening...';
        _translatedTextBottom = '';
        _translatedTextTop = '';
      }
    });

    await _speech.listen(
      onResult: (SpeechRecognitionResult result) {
        setState(() {
          if (isTop) {
            _spokenTextTop = result.recognizedWords;
          } else {
            _spokenTextBottom = result.recognizedWords;
          }
        });
      },
      localeId: localeId,
      listenFor: const Duration(seconds: 60),
      pauseFor: const Duration(seconds: 60),
      partialResults: true,
    );
  }

  Future<void> _stopListening(bool isTop) async {
    await _speech.stop();
    await Future.delayed(const Duration(milliseconds: 500));
    setState(() {
      if (isTop) {
        _isListeningTop = false;
      } else {
        _isListeningBottom = false;
      }
    });

    final spokenText = isTop ? _spokenTextTop : _spokenTextBottom;
    if (spokenText.isNotEmpty && spokenText != 'Listening...') {
      _translate(spokenText, isTop);
    }
  }

@override
Widget build(BuildContext context) {
  final panelBg =
      _isDarkMode ? const Color(0xFF0D0E15) : const Color(0xFFF4F5FA);
  return Scaffold(
    backgroundColor: panelBg,
    body: SafeArea(
      child: Stack(
        alignment: Alignment.center,
        children: [
          Column(
            children: [
              Expanded(
                child: RotatedBox(
                  quarterTurns: 2,
                  child: _buildPanel(
                    isTop: true,
                    spokenText: _spokenTextTop,
                    translatedText: _translatedTextTop,
                    isListening: _isListeningTop,
                    isTranslating: _isTranslatingTop,
                    selectedLanguage: _selectedLanguageTop,
                  ),
                ),
              ),
              Expanded(
                child: _buildPanel(
                  isTop: false,
                  spokenText: _spokenTextBottom,
                  translatedText: _translatedTextBottom,
                  isListening: _isListeningBottom,
                  isTranslating: _isTranslatingBottom,
                  selectedLanguage: _selectedLanguageBottom,
                ),
              ),
            ],
          ),
          // theme toggle — centered on the seam, neutral for both users
          _buildThemeToggle(),
        ],
      ),
    ),
  );
}

  Widget _buildPanel({
  required bool isTop,
  required String spokenText,
  required String translatedText,
  required bool isListening,
  required bool isTranslating,
  required String selectedLanguage,
}) {
  final dark = _isDarkMode;
  final panelBg = dark ? const Color(0xFF0D0E15) : const Color(0xFFF4F5FA);
  final cardBg = dark ? const Color(0xFF1B1C27) : Colors.white;
  final primaryTxt = dark ? const Color(0xFFF2F3F7) : const Color(0xFF15161E);
  final secondaryTxt = dark ? const Color(0xFF8A8C9B) : const Color(0xFF6B6D7C);
  final pillBg = dark ? const Color(0xFF262733) : const Color(0xFFE9EBF2);
  final pillTxt = dark ? const Color(0xFFD4D6E2) : const Color(0xFF3A3B47);
  final iconBtnBg = dark ? const Color(0xFF23242F) : const Color(0xFFEDEFF5);
  const accent = Color(0xFFFF6B57);
  final scrollController = isTop ? _scrollTop : _scrollBottom;

  return Container(
  width: double.infinity,
  color: panelBg,
  padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
  child: Column(
    children: [
      // language selector pill
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        decoration: BoxDecoration(
          color: pillBg,
          borderRadius: BorderRadius.circular(30),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: selectedLanguage,
            isDense: true,
            dropdownColor: cardBg,
            borderRadius: BorderRadius.circular(16),
            icon: Icon(
              Icons.keyboard_arrow_down,
              color: pillTxt,
              size: 18,
            ),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: pillTxt,
              letterSpacing: 1.0,
            ),
            items: _translateCodes.keys.map((lang) {
              return DropdownMenuItem(
                  value: lang,
                  child: Text(lang.toUpperCase()));
            }).toList(),
            onChanged: (value) {
              setState(() {
                if (isTop) {
                  _selectedLanguageTop = value!;
                } else {
                  _selectedLanguageBottom = value!;
                }
              });
            },
          ),
        ),
      ),

      const SizedBox(height: 12),

      Expanded(
        child: Scrollbar(
          controller: scrollController,
          thumbVisibility: true,
          child: SingleChildScrollView(
            controller: scrollController,
            child: Column(
              children: [
      // spoken text card
Container(
  width: double.infinity,
  padding: const EdgeInsets.all(18),
  decoration: BoxDecoration(
    color: cardBg,
    borderRadius: BorderRadius.circular(22),
  ),
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        spokenText.isEmpty
            ? 'Hold mic and speak...'
            : spokenText,
        style: TextStyle(
          fontSize: 15,
          height: 1.5,
          fontWeight: FontWeight.w500,
          color: spokenText.isEmpty ? secondaryTxt : primaryTxt,
        ),
      ),
      if (spokenText.isNotEmpty &&
          spokenText != 'Listening...') ...[
        const SizedBox(height: 12),
        Row(
          children: [
            _iconButton(
              icon: Icons.volume_up_rounded,
              bg: iconBtnBg,
              color: accent,
              onTap: () => _speak(spokenText, selectedLanguage),
            ),
            const SizedBox(width: 10),
            _iconButton(
              icon: Icons.slow_motion_video_rounded,
              bg: iconBtnBg,
              color: accent,
              onTap: () => _speak(spokenText, selectedLanguage, rate: 0.5),
            ),
          ],
        ),
      ],
    ],
  ),
),

      const SizedBox(height: 10),

      // translated text card
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(22),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${isTop ? _selectedLanguageBottom : _selectedLanguageTop} RESPONSE'
                  .toUpperCase(),
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
                color: accent,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              isTranslating
                  ? 'Translating...'
                  : translatedText.isEmpty
                      ? 'Translation appears here...'
                      : translatedText,
              style: TextStyle(
                fontSize: 20,
                height: 1.4,
                fontWeight: FontWeight.w700,
                color: translatedText.isEmpty ? secondaryTxt : primaryTxt,
              ),
            ),
            const SizedBox(height: 8),
            if (translatedText.isNotEmpty)
              Row(
                children: [
                  _iconButton(
                    icon: Icons.volume_up_rounded,
                    bg: iconBtnBg,
                    color: accent,
                    onTap: () => _speak(
                      translatedText,
                      isTop
                          ? _selectedLanguageBottom
                          : _selectedLanguageTop,
                    ),
                  ),
                  const SizedBox(width: 10),
                  _iconButton(
                    icon: Icons.slow_motion_video_rounded,
                    bg: iconBtnBg,
                    color: accent,
                    onTap: () => _speak(
                      translatedText,
                      isTop
                          ? _selectedLanguageBottom
                          : _selectedLanguageTop,
                      rate: 0.5,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),

              ],
            ),
          ),
        ),
      ),

      const SizedBox(height: 10),

      // mic button — now at BOTTOM
      GestureDetector(
        onLongPressStart: (_) => _startListening(isTop),
        onLongPressEnd: (_) => _stopListening(isTop),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: isListening ? 74 : 62,
          height: isListening ? 74 : 62,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFFFF9A4D), Color(0xFFFF4D6D)],
            ),
            boxShadow: [
              BoxShadow(
                color: accent.withOpacity(isListening ? 0.65 : 0.45),
                blurRadius: isListening ? 30 : 20,
                spreadRadius: isListening ? 6 : 2,
              ),
            ],
          ),
          child: Icon(
            isListening ? Icons.mic : Icons.mic_none_rounded,
            color: Colors.white,
            size: 30,
          ),
        ),
      ),

      const SizedBox(height: 10),

      Text(
        (isListening ? 'Release to translate' : 'Hold to speak')
            .toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.5,
          color: secondaryTxt,
        ),
      ),
    ],
  ),
);
}

Widget _iconButton({
  required IconData icon,
  required Color bg,
  required Color color,
  required VoidCallback onTap,
}) {
  return GestureDetector(
    onTap: onTap,
    child: Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(shape: BoxShape.circle, color: bg),
      child: Icon(icon, color: color, size: 20),
    ),
  );
}

Widget _buildThemeToggle() {
  final btnBg = _isDarkMode ? const Color(0xFF20212D) : Colors.white;
  final iconColor =
      _isDarkMode ? const Color(0xFFFFB27A) : const Color(0xFFFF6B57);
  return Align(
    alignment: Alignment.centerRight,
    child: Padding(
      padding: const EdgeInsets.only(right: 6),
      child: GestureDetector(
        onTap: () => setState(() => _isDarkMode = !_isDarkMode),
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: btnBg,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(_isDarkMode ? 0.4 : 0.12),
                blurRadius: 8,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Icon(
            _isDarkMode ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
            color: iconColor,
            size: 20,
          ),
        ),
      ),
    ),
  );
}
}