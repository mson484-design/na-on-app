import 'dart:convert';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
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

  final ImagePicker _imagePicker = ImagePicker();
  File? _avatarImage;
  String _avatarMood = '자연스럽게';
  String _avatarStyle = '편안한 일상복';
  String _avatarExpression = '편안한 표정';
  int _avatarSetupStep = 0;
  bool _avatarSetupMode = false;

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

  Future<void> _loadSavedAvatar() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final path = prefs.getString('naon_avatar_path');
      final mood = prefs.getString('naon_avatar_mood');
      final style = prefs.getString('naon_avatar_style');
      final expression = prefs.getString('naon_avatar_expression');

      if (!mounted) return;

      setState(() {
        if (path != null && File(path).existsSync()) {
          _avatarImage = File(path);
        }
        if (mood != null && mood.isNotEmpty) _avatarMood = mood;
        if (style != null && style.isNotEmpty) _avatarStyle = style;
        if (expression != null && expression.isNotEmpty) {
          _avatarExpression = expression;
        }
      });
    } catch (e) {
      debugPrint('아바타 불러오기 오류: $e');
    }
  }

  Future<void> _pickAvatarPhoto() async {
  try {
    // 1. 기존 아바타 정보 삭제
    final prefs = await SharedPreferences.getInstance();

    await prefs.remove('naon_avatar_path');
    await prefs.remove('naon_avatar_mood');
    await prefs.remove('naon_avatar_style');
    await prefs.remove('naon_avatar_expression');

    if (!mounted) return;

    setState(() {
      _avatarImage = null;
      _avatarMood = '자연스럽게';
      _avatarStyle = '편안한 일상복';
      _avatarExpression = '편안한 표정';
      _avatarSetupStep = 0;
    });

    // 2. 새 사진 선택
    final picked = await _imagePicker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 88,
      maxWidth: 1200,
    );

    if (picked == null) return;

    // 3. 새 사진 등록
    final file = File(picked.path);

    await prefs.setString(
      'naon_avatar_path',
      file.path,
    );

    if (!mounted) return;

    setState(() {
      _avatarImage = file;
    });

    _addNaonMessage(
      '기존 아바타를 삭제하고 새 사진으로 등록했어요.',
    );
  } catch (e) {
    debugPrint('아바타 사진 교체 오류: $e');
    _showError('아바타 사진을 교체하지 못했습니다.');
  }
}

  bool _isAvatarCommand(String text) {
    final t = text.replaceAll(' ', '');
    return t.contains('아바타') &&
        (t.contains('만들') ||
            t.contains('생성') ||
            t.contains('바꿔') ||
            t.contains('교체') ||
            t.contains('설정'));
  }

  Future<void> _startAvatarSetup() async {
    _avatarSetupMode = true;
    _avatarSetupStep = 0;

    if (_avatarImage == null) {
      _addNaonMessage(
        '먼저 아바타로 사용할 사진을 올려주세요. 아래 📷 버튼을 누르면 휴대폰 사진에서 선택할 수 있어요.',
      );
      return;
    }

    _askNextAvatarQuestion();
  }

  void _askNextAvatarQuestion() {
    if (!_avatarSetupMode) return;

    if (_avatarSetupStep == 0) {
      _addNaonMessage(
        '첫 번째 질문이에요. 어떤 분위기의 아바타를 원하세요?\n① 밝고 귀엽게\n② 차분하고 세련되게\n③ 자연스럽게',
      );
    } else if (_avatarSetupStep == 1) {
      _addNaonMessage(
        '두 번째 질문이에요. 어떤 스타일로 보여드릴까요?\n① 편안한 일상복\n② 깔끔한 정장\n③ 원하는 스타일을 직접 말하기',
      );
    } else if (_avatarSetupStep == 2) {
      _addNaonMessage(
        '세 번째 질문이에요. 어떤 표정이 좋으세요?\n① 밝게 웃는 표정\n② 편안한 표정\n③ 진지하고 또렷한 표정',
      );
    }
  }

  Future<bool> _handleAvatarSetupAnswer(String answer) async {
    if (!_avatarSetupMode) return false;

    final t = answer.replaceAll(' ', '');

    if (_avatarSetupStep == 0) {
      if (t.contains('밝') || t.contains('귀엽') || t.contains('1')) {
        _avatarMood = '밝고 귀엽게';
      } else if (t.contains('차분') || t.contains('세련') || t.contains('2')) {
        _avatarMood = '차분하고 세련되게';
      } else {
        _avatarMood = '자연스럽게';
      }
      _avatarSetupStep = 1;
      _askNextAvatarQuestion();
      return true;
    }

    if (_avatarSetupStep == 1) {
      if (t.contains('정장') || t.contains('2')) {
        _avatarStyle = '깔끔한 정장';
      } else if (t.contains('직접') || t.contains('3')) {
        _avatarStyle = answer.trim();
      } else {
        _avatarStyle = '편안한 일상복';
      }
      _avatarSetupStep = 2;
      _askNextAvatarQuestion();
      return true;
    }

    if (_avatarSetupStep == 2) {
      if (t.contains('웃') || t.contains('밝') || t.contains('1')) {
        _avatarExpression = '밝게 웃는 표정';
      } else if (t.contains('진지') || t.contains('또렷') || t.contains('3')) {
        _avatarExpression = '진지하고 또렷한 표정';
      } else {
        _avatarExpression = '편안한 표정';
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('naon_avatar_mood', _avatarMood);
      await prefs.setString('naon_avatar_style', _avatarStyle);
      await prefs.setString('naon_avatar_expression', _avatarExpression);

      _avatarSetupMode = false;
      _avatarSetupStep = 0;

      if (mounted) setState(() {});

      _addNaonMessage(
        '3가지 설정이 끝났어요. 이제 등록한 사진을 바탕으로 나온 캐릭터를 만들게요.',
        speak: false,
      );

      await _generateAvatarCharacter();
      return true;
    }

    return false;
  }

  Future<void> _generateAvatarCharacter() async {
    if (_avatarImage == null) {
      _showError('먼저 아바타 사진을 등록해주세요.');
      return;
    }

    const apiKey = String.fromEnvironment('OPENAI_API_KEY');
    if (apiKey.isEmpty) {
      _showError('OPENAI_API_KEY가 없습니다.');
      return;
    }

    try {
      final sourceFile = _avatarImage!;
      final bytes = await sourceFile.readAsBytes();
      final imageData = base64Encode(bytes);

      final prompt = """
등록한 사진 속 사람을 참고해서 '나온'이라는 개인 AI 아바타 캐릭터를 만들어주세요.
사진 속 인물의 얼굴 특징과 전체적인 인상을 최대한 자연스럽게 유지하되,
실사 사진 그대로가 아니라 친근하고 깔끔한 캐릭터형 아바타로 변환해주세요.
상반신 중심의 정면 또는 약간의 3/4 방향, 얼굴이 잘 보이게 만들어주세요.
작은 화면의 원형 아바타에서 잘 보이도록 단순하고 선명하게 표현해주세요.
분위기: $_avatarMood
스타일: $_avatarStyle
표정: $_avatarExpression
배경은 투명하게 만들고 캐릭터만 나오게 해주세요.
텍스트나 글자는 넣지 마세요.
""";

      final body = {
        'model': 'gpt-5.6-luna',
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
            'model': 'gpt-image-2',
            'size': '1024x1024',
            'quality': 'low',
            'background': 'transparent',
          },
        ],
        'tool_choice': 'required',
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
        debugPrint('아바타 생성 오류: ${response.body}');
        throw Exception('이미지 생성 HTTP ${response.statusCode}');
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
        throw Exception('생성된 아바타 이미지가 없습니다.');
      }

      final generatedFile = File(
        '${sourceFile.parent.path}/naon_avatar_generated.png',
      );
      await generatedFile.writeAsBytes(base64Decode(generatedBase64));

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('naon_avatar_path', generatedFile.path);

      if (!mounted) return;

      setState(() {
        _avatarImage = generatedFile;
      });

      _addNaonMessage(
        '나온 캐릭터 아바타가 완성됐어요. 이제 오른쪽 위에서 나온이 함께할게요.',
      );
    } catch (e) {
      debugPrint('나온 캐릭터 생성 오류: $e');
      _showError('캐릭터 생성에 실패했습니다. 사진과 인터넷 연결을 확인해주세요.');
    }
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

    if (_avatarSetupMode) {
      setState(() {
        messages.add({
          'type': 'user',
          'text': question,
        });
        _textController.clear();
      });
      _scrollToBottom();
      await _handleAvatarSetupAnswer(question);
      return;
    }

    if (_isAvatarCommand(question)) {
      setState(() {
        messages.add({
          'type': 'user',
          'text': question,
        });
        _textController.clear();
      });
      _scrollToBottom();
      await _startAvatarSetup();
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

      if (_avatarMood == '밝고 귀엽게') {
        rate = 0.45;
        pitch = 1.08;
      } else if (_avatarMood == '차분하고 세련되게') {
        rate = 0.32;
        pitch = 0.90;
      } else if (_isCheerful(text, lower)) {
        rate = 0.45;
        pitch = 1.08;
      } else if (_isCalm(text, lower)) {
        rate = 0.32;
        pitch = 0.90;
      } else {
        rate = 0.38;
        pitch = 0.97;
      }

      await _tts.setSpeechRate(rate);
      await _tts.setPitch(pitch);
      await _tts.setVolume(1.0);

      await _tts.speak(text);
    } catch (e) {
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
        child: Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withOpacity(0.95),
            border: Border.all(
              color: Colors.pinkAccent,
              width: 2,
            ),
          ),
          child: ClipOval(
            child: _avatarImage != null
                ? Image.file(
                    _avatarImage!,
                    width: 64,
                    height: 64,
                    fit: BoxFit.cover,
                  )
                : const Center(
                    child: Text(
                      '나온',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.pink,
                      ),
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
