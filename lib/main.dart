import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

List<CameraDescription> cameras = [];

const String naonBridgeUrl = 'https://shy-boat-f7da.mson9929.workers.dev';

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

class _NaonHomePageState extends State<NaonHomePage> with SingleTickerProviderStateMixin {
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

  final ImagePicker _imagePicker = ImagePicker();
  File? _styleSourceImage;
  Uint8List? _avatarIllustrationBytes;
  late final AnimationController _avatarGlowController;

  String answerLength = '보통';

  final List<Map<String, String>> messages = [];

  @override
  void initState() {
    super.initState();

    _avatarGlowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
      lowerBound: 0.0,
      upperBound: 1.0,
    );

    _initializeCamera();
    _initSpeech();
    _initTts();
    _loadSavedAvatarIllustration();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _addNaonMessage(
        '안녕하세요. 저는 나온 아바타예요. 지금 보이는 모습과 말씀을 바탕으로 편하게 도와드릴게요.',
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
  
  Future<void> _initSpeech({bool retry = true}) async {
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
          }
        },
      );

      if (mounted) {
        setState(() {});
      }

      if (!speechReady && retry) {
        await Future<void>.delayed(const Duration(milliseconds: 700));
        if (mounted) {
          await _initSpeech(retry: false);
        }
      }
    } catch (e) {
      debugPrint('음성인식 초기화 오류: $e');

      if (mounted) {
        setState(() {
          speechReady = false;
          isListening = false;
        });
      }

      if (retry) {
        await Future<void>.delayed(const Duration(milliseconds: 700));
        if (mounted) {
          await _initSpeech(retry: false);
        }
      }
    }
  }

  Future<void> _initTts() async {
      try {
        await _tts.setLanguage('ko-KR');
        await _tts.setSpeechRate(0.38);
        await _tts.setPitch(0.95);
        await _tts.setVolume(1.0);
        _tts.setCompletionHandler(() {
          if (mounted) {
            setState(() {
              _avatarSpeaking = false;
            });
            _avatarGlowController.stop();
            _avatarGlowController.value = 0.0;
          }
        });
      } catch (e) {
        debugPrint('TTS 초기화 오류: $e');
      }
    }

  Future<void> _toggleListening() async {
    if (!speechReady) {
      _showError(
        '음성인식을 사용할 수 없습니다.\n휴대폰의 마이크 권한을 확인해주세요.',
      );
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

  Future<void> _loadSavedAvatarIllustration() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString('naon_avatar_illustration_base64');
      if (saved == null || saved.isEmpty || !mounted) return;

      final bytes = base64Decode(saved);
      setState(() {
        _avatarIllustrationBytes = Uint8List.fromList(bytes);
      });
    } catch (e) {
      debugPrint('저장된 일러스트 불러오기 오류: $e');
    }
  }

  Future<void> _pickStyleSourceImage() async {
    try {
      final picked = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 90,
      );

      if (picked == null) return;

      if (!mounted) return;

      setState(() {
        _styleSourceImage = File(picked.path);
        _avatarIllustrationBytes = null;
      });

      _addNaonMessage(
        '사진을 등록했어요.',
        speak: true,
      );

      if (mounted) {
        setState(() {
          isThinking = true;
          messages.add({
            'type': 'naon',
            'text': '나만의 일러스트를 만들고 있어요… 잠시만 기다려 주세요.',
          });
        });
        _scrollToBottom();
      }

      await _generateAvatarIllustration();
    } catch (e) {
      debugPrint('스타일 사진 선택 오류: $e');
      _showError('사진을 불러오지 못했어요.');
    }
  }

  Future<void> _generateAvatarIllustration() async {
    final source = _styleSourceImage;
    if (source == null) return;

    if (mounted) {
      setState(() {
        isThinking = true;
      });
    }

    try {
      final sourceBytes = await source.readAsBytes();
      final imageBase64 = base64Encode(sourceBytes);

      final response = await http
          .post(
            Uri.parse('$naonBridgeUrl/avatar'),
            headers: {
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'imageBase64': imageBase64,
            }),
          )
          .timeout(const Duration(seconds: 180));

      debugPrint('나온 중간다리 이미지 상태코드: ${response.statusCode}');

      if (response.statusCode < 200 || response.statusCode >= 300) {
        debugPrint('나온 중간다리 이미지 오류: ${response.body}');
        throw Exception('중간다리 HTTP ${response.statusCode}');
      }

      final data = jsonDecode(response.body);
      final generatedBase64 = data['imageBase64'];

      if (generatedBase64 is! String || generatedBase64.isEmpty) {
        throw Exception('생성된 사용자 일러스트가 없습니다.');
      }

      final generatedBytes =
          Uint8List.fromList(base64Decode(generatedBase64));

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'naon_avatar_illustration_base64',
        generatedBase64,
      );

      final file = File(
        '${Directory.systemTemp.path}/naon_avatar_illustration_${DateTime.now().millisecondsSinceEpoch}.png',
      );
      await file.writeAsBytes(generatedBytes);

      if (!mounted) return;

      setState(() {
        _avatarIllustrationBytes = generatedBytes;
        isThinking = false;
        messages.add({
          'type': 'naon',
          'text': '나를 닮은 일러스트를 만들었어요. 이제 코디나 화장을 바꿔서 볼 수 있어요.',
          'imagePath': file.path,
        });
      });

      _scrollToBottom();
      await _speak(
        '나를 닮은 일러스트를 만들었어요. 이제 코디나 화장을 바꿔서 볼 수 있어요.',
      );
    } catch (e) {
      debugPrint('사용자 일러스트 생성 오류: $e');

      if (!mounted) return;

      setState(() {
        isThinking = false;
      });

      if (e is TimeoutException) {
        _showError(
          '일러스트를 만드는 데 시간이 오래 걸리고 있어요. 잠시 후 다시 시도해주세요.',
        );
      } else {
        _showError(
          '요청하신 이미지를 만드는 AI와 연결하는 데 문제가 생겼어요. 나중에 다시 시도해주세요.',
        );
      }
    }
  }

  bool _isStylePreviewRequest(String text) {
    final lower = text.toLowerCase();
    final show = lower.contains('보여줘') ||
        lower.contains('보여 줘') ||
        lower.contains('미리') ||
        lower.contains('예상') ||
        lower.contains('그려줘') ||
        lower.contains('그려 줘');

    final imageTopic = lower.contains('코디') ||
        lower.contains('화장') ||
        lower.contains('메이크업') ||
        lower.contains('립') ||
        lower.contains('옷') ||
        lower.contains('스타일') ||
        lower.contains('색') ||
        lower.contains('정장') ||
        lower.contains('캐주얼') ||
        lower.contains('일러스트') ||
        lower.contains('사진') ||
        lower.contains('모습') ||
        lower.contains('들판') ||
        lower.contains('바닷가') ||
        lower.contains('바다') ||
        lower.contains('배경') ||
        lower.contains('여행') ||
        lower.contains('장소');

    return show && imageTopic;
  }

  Future<void> _generateStylePreview(String request) async {
    if (_styleSourceImage == null && _avatarIllustrationBytes == null) {
      final message = '먼저 사진 버튼으로 사진을 등록해주세요.';
      if (mounted) {
        setState(() {
          messages.add({'type': 'naon', 'text': message});
        });
        _scrollToBottom();
      }
      await _speak(message);
      return;
    }

    const apiKey = String.fromEnvironment('OPENAI_API_KEY');
    if (apiKey.isEmpty) {
      final message = '사진 요청을 처리할 AI 연결에 문제가 있어요. 나중에 다시 시도해주세요.';
      if (mounted) {
        setState(() {
          messages.add({'type': 'naon', 'text': message});
          isThinking = false;
        });
      }
      await _speak(message);
      return;
    }

    try {
      final sourceBytes = _avatarIllustrationBytes ??
          await _styleSourceImage!.readAsBytes();
      final imageData = base64Encode(sourceBytes);

      final prompt = """
기준 이미지는 사용자의 정감 있는 개인 일러스트입니다.
이 일러스트 속 인물이 같은 사람으로 알아볼 수 있도록 특징과 일러스트 화풍을 유지하세요.
사용자의 요청을 반영해 옷, 화장, 색상 또는 배경을 자연스럽게 바꿔주세요.
사용자의 요청: $request
과도한 실사화나 완전히 다른 얼굴로의 변경은 피하세요.
한 사람만 나오게 하고, 불필요한 글자나 워터마크는 넣지 마세요.
""";

      final body = {
        'model': 'gpt-6-astra',
        'input': [
          {
            'role': 'user',
            'content': [
              {'type': 'input_text', 'text': prompt},
              {
                'type': 'input_image',
                'image_url': 'data:image/jpeg;base64,$imageData',
              },
            ],
          },
        ],
        'tools': [
          {
            'type': 'image_generation',
            'model': 'gpt-image-2.5-sunburst',
            'size': '512x512',
            'quality': 'low',
            'background': 'opaque',
            'action': 'edit',
          },
        ],
        'tool_choice': {'type': 'image_generation'},
      };

      final response = await http.post(
        Uri.parse('https://api.openai.com/v1/responses'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $apiKey',
        },
        body: jsonEncode(body),
      );

      if (response.statusCode < 200 || response.statusCode >= 300) {
        debugPrint('스타일 미리보기 HTTP ${response.statusCode}: ${response.body}');
        throw Exception('스타일 미리보기 HTTP ${response.statusCode}');
      }

      final data = jsonDecode(response.body);
      String? generatedBase64;
      final output = data['output'];

      if (output is List) {
        for (final item in output) {
          if (item is Map && item['type'] == 'image_generation_call') {
            final result = item['result'];
            if (result is String && result.isNotEmpty) {
              generatedBase64 = result;
              break;
            }
          }
        }
      }

      if (generatedBase64 == null || generatedBase64.isEmpty) {
        throw Exception('생성된 미리보기 이미지가 없습니다.');
      }

      final dir = Directory.systemTemp;
      final file = File(
        '${dir.path}/naon_style_preview_${DateTime.now().millisecondsSinceEpoch}.png',
      );
      await file.writeAsBytes(base64Decode(generatedBase64));

      if (!mounted) return;

      setState(() {
        messages.add({
          'type': 'naon',
          'text': '요청하신 스타일을 미리 보여드릴게요.',
          'imagePath': file.path,
        });
        isThinking = false;
      });
      _scrollToBottom();
      await _speak('요청하신 스타일을 미리 보여드릴게요.');
    } catch (e) {
      debugPrint('스타일 미리보기 오류: $e');

      if (!mounted) return;

      setState(() {
        isThinking = false;
      });

      final message = '사진 요청을 처리하는 AI와 연결하는 데 문제가 생겼어요. 나중에 다시 시도해주세요.';
      _showError(message);
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

    if (_isStylePreviewRequest(question)) {
      await _generateStylePreview(question);
      return;
    }

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
        if (!_avatarGlowController.isAnimating) {
          _avatarGlowController.repeat(reverse: true);
        }
      }

      await _tts.speak(text);
    } catch (e) {
      if (mounted) {
        setState(() {
          _avatarSpeaking = false;
        });
        _avatarGlowController.stop();
        _avatarGlowController.value = 0.0;
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
    _avatarGlowController.dispose();
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
        top: 10,
        right: 10,
        child: IgnorePointer(
          child: AnimatedBuilder(
            animation: _avatarGlowController,
            builder: (context, child) {
              final t = _avatarSpeaking
                  ? _avatarGlowController.value
                  : 0.0;

              final opacity = 0.04 + (0.10 * t);
              final blur = 18.0 + (18.0 * t);
              final size = 52.0 + (12.0 * t);

              return SizedBox(
                width: 72,
                height: 72,
                child: Center(
                  child: Container(
                    width: size,
                    height: size,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.pinkAccent.withOpacity(opacity),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.pinkAccent.withOpacity(opacity),
                          blurRadius: blur,
                          spreadRadius: 5.0 + (4.0 * t),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
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
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if ((message['text'] ?? '').isNotEmpty)
                          Text(
                            message['text'] ?? '',
                            style: const TextStyle(
                              fontSize: 14,
                              height: 1.35,
                            ),
                          ),
                        if ((message['imagePath'] ?? '').isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Image.file(
                                File(message['imagePath']!),
                                width: 260,
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                      ],
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
          const SizedBox(width: 2),
          IconButton(
            tooltip: '스타일 사진 등록',
            onPressed: _pickStyleSourceImage,
            icon: const Icon(
              Icons.photo_camera_back_outlined,
              size: 24,
            ),
          ),
          const SizedBox(width: 2),
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
