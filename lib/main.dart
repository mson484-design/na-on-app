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
      title: '나온 - 다정한 나온',
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

  String answerLength = '보통';

  final List<Map<String, String>> messages = [];

  @override
  void initState() {
    super.initState();
    _initializeCamera();
    _initSpeech();
    _initTts();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _addNaonMessage(
        '안녕하세요. 저는 나온이에요. '
        '지금 보이는 모습과 말씀을 바탕으로 편하게 도와드릴게요.',
        speak: false,
      );
    });
  }

  Future<void> _initializeCamera() async {
    if (cameras.isEmpty) {
      return;
    }

    CameraDescription selectedCamera = cameras.first;

    for (final camera in cameras) {
      if (camera.lensDirection == CameraLensDirection.front) {
        selectedCamera = camera;
        break;
      }
    }

    try {
      final controller = CameraController(
        selectedCamera,
        ResolutionPreset.medium,
        enableAudio: false,
      );

      await controller.initialize();

      if (!mounted) {
        await controller.dispose();
        return;
      }

      setState(() {
        _cameraController = controller;
        cameraReady = true;
      });
    } catch (e) {
      debugPrint('카메라 실행 오류: $e');
    }
  }

  Future<void> _initSpeech() async {
    try {
      speechReady = await _speech.initialize(
        onStatus: (status) {
          debugPrint('음성인식 상태: $status');

          if (status == 'notListening' && mounted) {
            setState(() {
              isListening = false;
            });
          }
        },
        onError: (error) {
          debugPrint('음성인식 오류: ${error.errorMsg}');

          if (mounted) {
            setState(() {
              isListening = false;
            });

            _showError('음성인식 오류\n${error.errorMsg}');
          }
        },
      );

      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      debugPrint('음성인식 초기화 오류: $e');

      if (mounted) {
        setState(() {
          speechReady = false;
        });
      }
    }
  }

  Future<void> _initTts() async {
    try {
      await _tts.setLanguage('ko-KR');
      await _tts.setSpeechRate(0.38);
      await _tts.setPitch(0.95);
      await _tts.setVolume(1.0);
    } catch (e) {
      debugPrint('TTS 초기화 오류: $e');
    }
  }

  Future<void> _toggleListening() async {
    if (!speechReady) {
      _showError('음성인식을 사용할 수 없습니다.\n휴대폰의 마이크 권한을 확인해주세요.');
      return;
    }

    if (isListening) {
      await _speech.stop();

      if (mounted) {
        setState(() {
          isListening = false;
        });
      }

      return;
    }

    try {
      await _tts.stop();

      if (mounted) {
        setState(() {
          isListening = true;
        });
      }

      await _speech.listen(
        localeId: 'ko-KR',
        partialResults: true,
        onResult: (result) {
          if (!mounted) {
            return;
          }

          setState(() {
            _textController.text = result.recognizedWords;
            _textController.selection = TextSelection.fromPosition(
              TextPosition(
                offset: _textController.text.length,
              ),
            );
          });

          if (result.finalResult) {
            final text = result.recognizedWords.trim();

            setState(() {
              isListening = false;
            });

            if (text.isNotEmpty) {
              _sendQuestion(text);
            }
          }
        },
      );
    } catch (e) {
      debugPrint('음성인식 실행 오류: $e');

      if (mounted) {
        setState(() {
          isListening = false;
        });

        _showError('음성인식을 시작하지 못했습니다.');
      }
    }
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
        'AI와 연결하는 중 문제가 생겼어요.\n'
        '잠시 후 다시 말씀해주세요.',
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
      final base64Image = base64Encode(bytes);
      imageData = base64Image;
    }

    String lengthInstruction;

    if (answerLength == '짧게') {
      lengthInstruction =
          '답변은 핵심만 1~2문장으로 아주 짧게 해주세요.';
    } else if (answerLength == '길게') {
      lengthInstruction =
          '답변은 충분히 자세하게 설명해주세요. '
          '실제로 도움이 되는 방법과 예시도 포함해주세요.';
    } else {
      lengthInstruction =
          '답변은 이해하기 편한 3~5문장 정도로 해주세요.';
    }

    final systemPrompt = '''
당신은 '나온 - 다정한 나온'이라는 개인 AI 도우미입니다.

사용자에게 친절하고 편안하게 말하세요.
아나운서처럼 또렷하고 자연스러운 말투를 사용하세요.

사용자가 질문하면 질문의 의도를 먼저 이해하고
실생활에서 도움이 되는 조언을 주세요.

사진이 제공되면 사진에서 실제로 관찰되는 모습만 활용하세요.
표정이나 분위기는 조심스럽게 표현하세요.
예:
"조금 편안해 보이네요."
"차분한 분위기가 느껴져요."

사진만으로 나이, 질병, 건강상태, 성격 등을 단정하지 마세요.
의학적 진단도 하지 마세요.

답변 길이:
$lengthInstruction

사용자가 편하게 다시 질문할 수 있도록 대화를 이어가세요.
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

    if (response.statusCode < 200 || response.statusCode >= 300) {
      debugPrint('OpenAI 오류: ${response.body}');
      throw Exception('OpenAI HTTP ${response.statusCode}');
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

      if (direct is String && direct.trim().isNotEmpty) {
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
      await _tts.speak(text);
    } catch (e) {
      debugPrint('음성 출력 오류: $e');
    }
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
        title: const Text('나온 - 다정한 나온'),
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
          left: 12,
          top: 12,
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 7,
            ),
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text(
              '나온',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
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
                  alignment:
                      isUser ? Alignment.centerRight : Alignment.centerLeft,
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
              padding: EdgeInsets.only(
                bottom: 4,
              ),
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
        backgroundColor:
            selected ? Colors.blue.shade100 : Colors.transparent,
      ),
      child: Text(
        value,
        style: TextStyle(
          fontSize: 12,
          fontWeight:
              selected ? FontWeight.bold : FontWeight.normal,
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
