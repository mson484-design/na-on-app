import 'dart:convert';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;
import 'package:speech_to_text/speech_to_text.dart' as stt;

List<CameraDescription> cameras = [];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    cameras = await availableCameras();
  } catch (e) {
    debugPrint('카메라 초기화 오류: $e');
  }

  runApp(const NaonApp());
}

class NaonApp extends StatelessWidget {
  const NaonApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: '나온 아바타',
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
      ),
      home: const NaonHomePage(),
    );
  }
}

class NaonHomePage extends StatefulWidget {
  const NaonHomePage({super.key});

  @override
  State<NaonHomePage> createState() => _NaonHomePageState();
}

class _NaonHomePageState extends State<NaonHomePage> {
  CameraController? _cameraController;

  final FlutterTts _tts = FlutterTts();
  final stt.SpeechToText _speech = stt.SpeechToText();

  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  bool cameraReady = false;
  bool speechReady = false;
  bool isListening = false;
  bool isThinking = false;

  bool _avatarSpeaking = false;

  String answerLength = '보통';

  final List<Map<String, String>> messages = [];

  @override
  void initState() {
    super.initState();

    _initializeCamera();
    _initSpeech();
    _initTts();
    _loadSavedAvatar();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _addNaonMessage(
        '안녕하세요. 저는 나온 아바타예요. 지금 보이는 모습과 말씀을 바탕으로 편하게 도와드릴게요.',
        speak: false,
      );
    });
  }

  Future<void> _sendTextQuestion() async {
    final text = _textController.text.trim();

    if (text.isEmpty) {
      return;
    }

    FocusScope.of(context).unfocus();
    await _sendQuestion(text);
  }

  Future<void> _sendQuestion(String question) async {
    if (isThinking) {
      return;
    }

    setState(() {
      messages.add({
        'type': 'user',
        'text': question,
      });

      _textController.clear();
      isThinking = true;
    });

    _scrollToBottom();

    XFile? image;

    try {
      if (_cameraController != null &&
          _cameraController!.value.isInitialized) {
        image = await _cameraController!.takePicture();
      }

      final answer = await _askOpenAI(
        question,
        image,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        messages.add({
          'type': 'naon',
          'text': answer,
        });

        isThinking = false;
      });

      _scrollToBottom();

      await _speak(answer);
    } catch (e) {
      debugPrint('AI 요청 오류: $e');

      if (!mounted) {
        return;
      }

      setState(() {
        isThinking = false;
      });

      _showError(
        'AI와 연결하는 중 문제가 생겼어요.\n잠시 후 다시 말씀해주세요.',
      );
    }
  }

  Future<String> _askOpenAI(
    String question,
    XFile? image,
  ) async {
    const apiKey = String.fromEnvironment('OPENAI_API_KEY');

    if (apiKey.isEmpty) {
      throw Exception('OPENAI_API_KEY가 없습니다.');
    }

    String imageData = '';

    if (image != null) {
      final bytes = await image.readAsBytes();
      imageData = base64Encode(bytes);
    }

    String lengthInstruction;

    if (answerLength == '짧게') {
      lengthInstruction =
          '답변은 핵심만 1~2문장으로 아주 짧게 해주세요.';
    } else if (answerLength == '길게') {
      lengthInstruction =
          '답변은 충분히 자세하게 설명해주세요. 실제로 도움이 되는 방법과 예시도 포함해주세요.';
    } else {
      lengthInstruction =
          '답변은 이해하기 편한 3~5문장 정도로 해주세요.';
    }

    final systemPrompt = '''
당신은 '나온 - 다정한 나온'이라는 개인 AI 도우미입니다.

사용자에게 친절하고 자연스럽게 말하세요.

상황에 따라 말투의 분위기를 조절하세요.

기분이 좋거나 재미있는 상황:
밝고 활기찬 음악 DJ처럼 표현하세요.
짧고 생동감 있는 문장을 사용하세요.

중요한 정보를 전달하는 상황:
방송 아나운서처럼 또렷하고 안정적으로 설명하세요.

걱정하거나 고민하는 상황:
속도를 서두르지 않는 차분하고 편안한 분위기로 말하세요.

단, 과장된 감정 표현은 피하고 자연스럽게 대화하세요.

사진이 제공되면 사진에서 실제로 관찰되는 모습만 활용하세요.

표정이나 분위기는 조심스럽게 표현하세요.
예:
"조금 편안해 보이네요."
"차분한 분위기가 느껴져요."
"오늘은 밝은 느낌이 조금 더 느껴져요."

사진만으로 나이, 질병, 건강상태, 성격 등을 단정하지 마세요.
의학적 진단도 하지 마세요.

답변 길이:
$lengthInstruction

사용자가 다시 질문하기 쉽도록 대화를 자연스럽게 이어가세요.
''';

    final List<Map<String, dynamic>> content = [
      {
        'type': 'input_text',
        'text': '$systemPrompt\n\n사용자의 질문:\n$question',
      },
    ];

    if (imageData.isNotEmpty) {
      content.add({
        'type': 'input_image',
        'image_url': 'data:image/jpeg;base64,$imageData',
      });
    }

    final body = {
      'model': 'gpt-5.6-luna',
      'input': [
        {
          'role': 'user',
          'content': content,
        }
      ],
      'max_output_tokens': 700,
    };

    final response = await http.post(
      Uri.parse('https://api.openai.com/v1/responses'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $apiKey',
      },
      body: jsonEncode(body),
    );

    debugPrint('OpenAI 상태코드: ${response.statusCode}');

    if (response.statusCode < 200 ||
        response.statusCode >= 300) {
      debugPrint('OpenAI 오류: ${response.body}');
      throw Exception(
        'OpenAI HTTP ${response.statusCode}',
      );
    }

    final data = jsonDecode(response.body);

    final outputText = _extractOutputText(data);

    if (outputText.trim().isEmpty) {
      throw Exception('AI 응답이 비어 있습니다.');
    }

    return outputText.trim();
  }

  String _extractOutputText(dynamic data) {
    if (data is Map<String, dynamic>) {
      final direct = data['output_text'];

      if (direct is String &&
          direct.trim().isNotEmpty) {
        return direct;
      }

      final output = data['output'];

      if (output is List) {
        final buffer = StringBuffer();

        for (final item in output) {
          if (item is! Map) {
            continue;
          }

          final content = item['content'];

          if (content is! List) {
            continue;
          }

          for (final part in content) {
            if (part is Map) {
              final text = part['text'];

              if (text is String) {
                buffer.write(text);
              }
            }
          }
        }

        return buffer.toString();
      }
    }

    return '';
  }

  Future<void> _speak(String text) async {
    try {
      await _tts.stop();

      final lower = text.toLowerCase();

      double rate = 0.38;
      double pitch = 0.95;

      if (_isCheerful(text, lower)) {
        rate = 0.45;
        pitch = 1.08;
      } else if (_isCalm(text, lower)) {
        rate = 0.32;
        pitch = 0.90;
      }

      await _tts.setSpeechRate(rate);
      await _tts.setPitch(pitch);
      await _tts.setVolume(1.0);

      if (mounted) {
        setState(() {
          _avatarSpeaking = true;
        });
      }

      await _tts.speak(text);
    } catch (e) {
      if (mounted) {
        setState(() {
          _avatarSpeaking = false;
        });
      }
      debugPrint('음성 출력 오류: $e');
    }
  }

  bool _isCheerful(String text, String lower) {
    const cheerfulWords = [
      '축하',
      '좋아요',
      '멋져요',
      '잘했어요',
      '신나요',
      '즐거',
      '재미',
      '반가워',
      '최고',
      '응원',
      '기분',
      '웃',
      '행복',
      '환영',
    ];

    for (final word in cheerfulWords) {
      if (text.contains(word) || lower.contains(word)) {
        return true;
      }
    }

    return text.contains('!');
  }

  bool _isCalm(String text, String lower) {
    const calmWords = [
      '걱정',
      '고민',
      '힘들',
      '속상',
      '불안',
      '천천히',
      '괜찮',
      '편안',
      '주의',
      '조심',
      '안전',
    ];

    for (final word in calmWords) {
      if (text.contains(word) || lower.contains(word)) {
        return true;
      }
    }

    return false;
  }

  void _addNaonMessage(
    String text, {
    bool speak = true,
  }) {
    if (!mounted) {
      return;
    }

    setState(() {
      messages.add({
        'type': 'naon',
        'text': text,
      });
    });

    _scrollToBottom();

    if (speak) {
      _speak(text);
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) {
        return;
      }

      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  void _showError(String message) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _tts.stop();
    _speech.stop();
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('나온 아바타'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              flex: 8,
              child: _buildCameraArea(),
            ),
            Expanded(
              flex: 2,
              child: _buildChatArea(),
            ),
          ],
        ),
      ),
    );
  }

 Widget _buildCameraArea() {
  if (!cameraReady ||
      _cameraController == null ||
      !_cameraController!.value.isInitialized) {
    return Container(
      width: double.infinity,
      color: Colors.black,
      child: const Center(
        child: CircularProgressIndicator(),
      ),
    );
  }

  return Stack(
    fit: StackFit.expand,
    children: [
      CameraPreview(_cameraController!),

      Positioned(
        top: 12,
        right: 12,
        child: AnimatedScale(
          scale: _avatarSpeaking ? 1.08 : 1.0,
          duration: const Duration(milliseconds: 220),
          child: AnimatedRotation(
            turns: _avatarSpeaking ? 0.015 : 0.0,
            duration: const Duration(milliseconds: 220),
            child: Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.95),
                border: Border.all(
                  color: _avatarSpeaking
                      ? Colors.pinkAccent
                      : Colors.pink.shade200,
                  width: _avatarSpeaking ? 3 : 2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.12),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Icon(
                _avatarSpeaking
                    ? Icons.record_voice_over_rounded
                    : Icons.face_rounded,
                size: 34,
                color: Colors.pinkAccent,
              ),
            ),
          ),
        ),
      ),

    ],
  );
}

  Widget _buildChatArea() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        border: Border(
          top: BorderSide(
            color: Colors.grey.shade300,
          ),
        ),
      ),
      child: Column(
        children: [
          _buildLengthButtons(),
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 4,
              ),
              itemCount: messages.length,
              itemBuilder: (context, index) {
                final message = messages[index];
                final isUser = message['type'] == 'user';

                return Align(
                  alignment: isUser
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: Container(
                    constraints: const BoxConstraints(
                      maxWidth: 330,
                    ),
                    margin: const EdgeInsets.only(
                      bottom: 6,
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: isUser
                          ? Colors.blue.shade100
                          : Colors.white,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      message['text'] ?? '',
                      style: const TextStyle(
                        fontSize: 14,
                        height: 1.35,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          if (isThinking)
            const Padding(
              padding: EdgeInsets.only(bottom: 4),
              child: Text(
                '나온이 생각하고 있어요...',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey,
                ),
              ),
            ),
          _buildInputArea(),
        ],
      ),
    );
  }

  Widget _buildLengthButtons() {
    return SizedBox(
      height: 34,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _lengthButton('짧게'),
          const SizedBox(width: 6),
          _lengthButton('보통'),
          const SizedBox(width: 6),
          _lengthButton('길게'),
        ],
      ),
    );
  }

  Widget _lengthButton(String value) {
    final selected = answerLength == value;

    return TextButton(
      onPressed: () {
        setState(() {
          answerLength = value;
        });
      },
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(
          horizontal: 10,
          vertical: 2,
        ),
        backgroundColor: selected
            ? Colors.blue.shade100
            : Colors.transparent,
      ),
      child: Text(
        value,
        style: TextStyle(
          fontSize: 12,
          fontWeight: selected
              ? FontWeight.bold
              : FontWeight.normal,
        ),
      ),
    );
  }

  Widget _buildInputArea() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        8,
        2,
        8,
        6,
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _textController,
              minLines: 1,
              maxLines: 2,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) {
                _sendTextQuestion();
              },
              decoration: InputDecoration(
                hintText: isListening
                    ? '말씀해주세요...'
                    : '나온에게 물어보세요',
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 9,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            tooltip: '아바타 사진',
            onPressed: _pickAvatarPhoto,
            icon: const Icon(Icons.photo_library_outlined),
          ),
          IconButton(
            tooltip: '음성인식',
            onPressed: _toggleListening,
            icon: Icon(
              isListening ? Icons.mic : Icons.mic_none,
              color: isListening ? Colors.red : null,
            ),
          ),
          IconButton(
            tooltip: '보내기',
            onPressed: _sendTextQuestion,
            icon: const Icon(Icons.send),
          ),
        ],
      ),
    );
  }
}
