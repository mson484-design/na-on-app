import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:google_generative_ai/google_generative_ai.dart';

List<CameraDescription> cameras = [];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    cameras = await availableCameras();
  } catch (e) {
    debugPrint("카메라 초기화 에러: $e");
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: '나온 - 다정한 거울',
      theme: ThemeData(
        primarySwatch: Colors.pink,
      ),
      home: const MirrorScreen(),
    );
  }
}

class MirrorScreen extends StatefulWidget {
  const MirrorScreen({super.key});

  @override
  State<MirrorScreen> createState() => _MirrorScreenState();
}

class _MirrorScreenState extends State<MirrorScreen> {
  final TextEditingController _textController = TextEditingController();

  List<Map<String, String>> messages = [];

  bool isThinking = false;

  CameraController? _cameraController;

  final FlutterTts _flutterTts = FlutterTts();

  static const apiKey =
      String.fromEnvironment('GEMINI_API_KEY');

  late final GenerativeModel _aiModel;

  @override
  void initState() {
    super.initState();

    _aiModel = GenerativeModel(
      model: 'gemini-3.8-flash',
      apiKey: apiKey,
    );

    _initCamera();
    _initTts();
  }

  Future<void> _initTts() async {
    await _flutterTts.setLanguage("ko-KR");
    await _flutterTts.setSpeechRate(0.4);
    await _flutterTts.setPitch(1.0);
  }

  Future<void> _initCamera() async {
    if (cameras.isEmpty) return;

    int cameraIndex = cameras.length > 1 ? 1 : 0;

    _cameraController = CameraController(
      cameras[cameraIndex],
      ResolutionPreset.medium,
      enableAudio: false,
    );

    try {
      await _cameraController!.initialize();

      if (mounted) {
        setState(() {});
      }

      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) {
          _analyzeFaceAndGreet();
        }
      });
    } catch (e) {
      debugPrint("카메라 초기화 오류: $e");
    }
  }

  Future<void> _analyzeFaceAndGreet() async {
    if (_cameraController == null ||
        !_cameraController!.value.isInitialized) {
      return;
    }

    setState(() {
      isThinking = true;
    });

    try {
      final image = await _cameraController!.takePicture();

      final imageBytes = await image.readAsBytes();

      final prompt = TextPart(
        "당신은 다정한 and 우아한 뷰티/스타일 조언자 "
        "'나온'입니다. 첨부된 사진 속 인물의 스타일, 안색, "
        "분위기를 확인하고 첫인사를 다정하게 건네주세요.",
      );

      final imagePart = DataPart(
        'image/jpeg',
        imageBytes,
      );

      final response = await _aiModel.generateContent([
        Content.multi([
          prompt,
          imagePart,
        ])
      ]);

      if (response.text != null) {
        await _addAiMessage(response.text!);
      }
    } catch (e) {
      await _addAiMessage("에러 발생: $e");
    } finally {
      if (mounted) {
        setState(() {
          isThinking = false;
        });
      }
    }
  }

  Future<void> _addUserMessage(String text) async {
    if (text.trim().isEmpty) {
      return;
    }

    setState(() {
      messages.add({
        "sender": "user",
        "text": text,
      });

      isThinking = true;
    });

    _textController.clear();

    try {
      final prompt =
          "사용자가 '$text'라고 말했습니다. "
          "다정한 거울 '나온'의 입장에서 짧게 대답해주세요.";

      final response = await _aiModel.generateContent([
        Content.text(prompt),
      ]);

      if (response.text != null) {
        await _addAiMessage(response.text!);
      }
    } catch (e) {
      await _addAiMessage("에러 발생: $e");
    } finally {
      if (mounted) {
        setState(() {
          isThinking = false;
        });
      }
    }
  }

  Future<void> _addAiMessage(String text) async {
    if (!mounted) return;

    setState(() {
      messages.add({
        "sender": "ai",
        "text": text,
      });
    });

    await _flutterTts.speak(text);
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _textController.dispose();
    _flutterTts.stop();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '나온 - 다정한 거울',
        ),
        centerTitle: true,
      ),

      body: Column(
        children: [

          // ==========================================
          // 상단 80% : 카메라
          // ==========================================
          Expanded(
            flex: 8,
            child: Container(
              width: double.infinity,
              color: Colors.black,
              child: _cameraController == null ||
                      !_cameraController!.value.isInitialized
                  ? const Center(
                      child: CircularProgressIndicator(),
                    )
                  : CameraPreview(
                      _cameraController!,
                    ),
            ),
          ),

          // ==========================================
          // 하단 20% : 나온 AI 대화
          // ==========================================
          Expanded(
            flex: 2,
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border(
                  top: BorderSide(
                    color: Colors.pink.shade200,
                    width: 2,
                  ),
                ),
              ),
              child: Column(
                children: [

                  // AI 메시지 영역
                  Expanded(
                    child: messages.isEmpty
                        ? const Center(
                            child: Text(
                              '나온에게 말을 걸어보세요.',
                              style: TextStyle(
                                color: Colors.grey,
                                fontSize: 14,
                              ),
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            itemCount: messages.length,
                            itemBuilder: (context, index) {
                              final msg = messages[index];

                              final isUser =
                                  msg["sender"] == "user";

                              return Container(
                                alignment: isUser
                                    ? Alignment.centerRight
                                    : Alignment.centerLeft,
                                padding:
                                    const EdgeInsets.symmetric(
                                  horizontal: 4,
                                  vertical: 2,
                                ),
                                child: Container(
                                  constraints: BoxConstraints(
                                    maxWidth:
                                        MediaQuery.of(context)
                                                .size
                                                .width *
                                            0.85,
                                  ),
                                  padding:
                                      const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isUser
                                        ? Colors.pink[100]
                                        : Colors.grey[200],
                                    borderRadius:
                                        BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    msg["text"] ?? '',
                                    style: const TextStyle(
                                      fontSize: 13,
                                      color: Colors.black87,
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                  ),

                  // 생각 중 표시
                  if (isThinking)
                    const Padding(
                      padding: EdgeInsets.symmetric(
                        vertical: 2,
                      ),
                      child: Text(
                        "나온이가 생각 중이에요...",
                        style: TextStyle(
                          color: Colors.grey,
                          fontSize: 11,
                        ),
                      ),
                    ),

                  // 입력창
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      8,
                      3,
                      8,
                      6,
                    ),
                    child: Row(
                      children: [

                        Expanded(
                          child: SizedBox(
                            height: 42,
                            child: TextField(
                              controller: _textController,
                              decoration: InputDecoration(
                                hintText:
                                    '나온이에게 말을 걸어보세요...',
                                hintStyle: const TextStyle(
                                  fontSize: 12,
                                ),
                                contentPadding:
                                    const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius:
                                      BorderRadius.circular(20),
                                ),
                              ),
                              onSubmitted: (value) {
                                _addUserMessage(value);
                              },
                            ),
                          ),
                        ),

                        const SizedBox(width: 6),

                        IconButton(
                          icon: const Icon(
                            Icons.send,
                            color: Colors.pink,
                          ),
                          onPressed: () {
                            _addUserMessage(
                              _textController.text,
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
