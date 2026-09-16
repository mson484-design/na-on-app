import 'dart:convert';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;

List<CameraDescription> cameras = [];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    cameras = await availableCameras();
  } catch (e) {
    debugPrint("카메라 초기화 오류: $e");
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
  final TextEditingController _textController =
      TextEditingController();

  final FlutterTts _flutterTts = FlutterTts();

  CameraController? _cameraController;

  List<Map<String, String>> messages = [];

  bool isThinking = false;

  static const apiKey =
      String.fromEnvironment('OPENAI_API_KEY');

  static const model = 'gpt-5.6-luna';

  @override
  void initState() {
    super.initState();

    _initCamera();
    _initTts();
  }

  Future<void> _initTts() async {
    await _flutterTts.setLanguage("ko-KR");
    await _flutterTts.setSpeechRate(0.4);
    await _flutterTts.setPitch(1.0);
  }

  Future<void> _initCamera() async {
    if (cameras.isEmpty) {
      _showError("카메라를 찾을 수 없습니다.");
      return;
    }

    CameraDescription selectedCamera = cameras.first;

    for (final camera in cameras) {
      if (camera.lensDirection == CameraLensDirection.front) {
        selectedCamera = camera;
        break;
      }
    }

    _cameraController = CameraController(
      selectedCamera,
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

      _showError("카메라 오류: $e");
    }
  }

  // ==========================================================
  // 사진 AI 분석
  // ==========================================================

  Future<void> _analyzeFaceAndGreet() async {
    if (_cameraController == null ||
        !_cameraController!.value.isInitialized) {
      return;
    }

    if (apiKey.trim().isEmpty) {
      _showError(
        "OpenAI API 키가 앱에 전달되지 않았습니다.\n"
        "GitHub Secret과 APK 빌드를 확인해주세요.",
      );
      return;
    }

    setState(() {
      isThinking = true;
    });

    try {
      final image = await _cameraController!.takePicture();

      final imageBytes = await image.readAsBytes();

      final base64Image = base64Encode(imageBytes);

      const prompt = '''
당신은 다정하고 우아한 뷰티·스타일 조언자 '나온'입니다.

사진 속 인물을 존중하는 방식으로 관찰하고,
보이는 범위에서 표정, 분위기, 스타일, 색감 등에 대해
가볍고 따뜻한 뷰티·스타일 조언을 해주세요.

의학적인 진단이나 나이 추정은 하지 마세요.

처음 만난 것처럼 자연스럽고 짧게 한국어로 인사해주세요.
''';

      final response = await http
          .post(
            Uri.parse(
              'https://api.openai.com/v1/responses',
            ),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $apiKey',
            },
            body: jsonEncode({
              'model': model,
              'input': [
                {
                  'role': 'user',
                  'content': [
                    {
                      'type': 'input_text',
                      'text': prompt,
                    },
                    {
                      'type': 'input_image',
                      'image_url':
                          'data:image/jpeg;base64,$base64Image',
                    },
                  ],
                }
              ],
            }),
          )
          .timeout(const Duration(seconds: 60));

      debugPrint(
        "OpenAI 상태코드: ${response.statusCode}",
      );

      debugPrint(
        "OpenAI 응답: ${response.body}",
      );

      if (response.statusCode >= 200 &&
          response.statusCode < 300) {
        final data = jsonDecode(response.body);

        final text = _extractOutputText(data);

        if (text.isNotEmpty) {
          await _addAiMessage(text);
        } else {
          await _addAiMessage(
            "사진은 확인했어요. 조금 더 가까이 바라볼게요.",
          );
        }
      } else {
        final errorMessage =
            _extractErrorMessage(response.body);

        _showError(
          "OpenAI 오류\n"
          "상태코드: ${response.statusCode}\n"
          "$errorMessage",
        );
      }
    } catch (e) {
      debugPrint("이미지 분석 오류: $e");

      _showError(
        "연결 오류\n$e",
      );
    } finally {
      if (mounted) {
        setState(() {
          isThinking = false;
        });
      }
    }
  }

  // ==========================================================
  // OpenAI 오류 내용 추출
  // ==========================================================

  String _extractErrorMessage(String body) {
    try {
      final data = jsonDecode(body);

      if (data is Map<String, dynamic>) {
        final error = data['error'];

        if (error is Map<String, dynamic>) {
          final message = error['message'];

          if (message != null) {
            return message.toString();
          }
        }
      }
    } catch (_) {}

    return body;
  }

  // ==========================================================
  // OpenAI 응답 텍스트 추출
  // ==========================================================

  String _extractOutputText(
      Map<String, dynamic> data) {
    try {
      if (data['output_text'] != null) {
        return data['output_text']
            .toString()
            .trim();
      }

      final output = data['output'];

      if (output is List) {
        for (final item in output) {
          if (item is Map<String, dynamic>) {
            final content = item['content'];

            if (content is List) {
              for (final part in content) {
                if (part is Map<String, dynamic>) {
                  if (part['type'] == 'output_text' &&
                      part['text'] != null) {
                    return part['text']
                        .toString()
                        .trim();
                  }
                }
              }
            }
          }
        }
      }
    } catch (e) {
      debugPrint("응답 분석 오류: $e");
    }

    return '';
  }

  // ==========================================================
  // 일반 대화
  // ==========================================================

  Future<void> _addUserMessage(String text) async {
    if (text.trim().isEmpty) {
      return;
    }

    if (apiKey.trim().isEmpty) {
      _showError(
        "OpenAI API 키가 앱에 없습니다.",
      );
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
      final response = await http
          .post(
            Uri.parse(
              'https://api.openai.com/v1/responses',
            ),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $apiKey',
            },
            body: jsonEncode({
              'model': model,
              'input':
                  "사용자가 '$text'라고 말했습니다. "
                  "다정한 거울 '나온'의 입장에서 "
                  "짧고 따뜻하게 한국어로 대답해주세요.",
            }),
          )
          .timeout(const Duration(seconds: 60));

      if (response.statusCode >= 200 &&
          response.statusCode < 300) {
        final data = jsonDecode(response.body);

        final answer =
            _extractOutputText(data);

        if (answer.isNotEmpty) {
          await _addAiMessage(answer);
        }
      } else {
        final errorMessage =
            _extractErrorMessage(response.body);

        _showError(
          "OpenAI 오류\n"
          "상태코드: ${response.statusCode}\n"
          "$errorMessage",
        );
      }
    } catch (e) {
      _showError(
        "대화 연결 오류\n$e",
      );
    } finally {
      if (mounted) {
        setState(() {
          isThinking = false;
        });
      }
    }
  }

  // ==========================================================
  // AI 메시지 + 음성
  // ==========================================================

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

  // ==========================================================
  // 오류 표시
  // ==========================================================

  void _showError(String text) {
    if (!mounted) return;

    setState(() {
      messages.add({
        "sender": "ai",
        "text": text,
      });
    });
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _textController.dispose();
    _flutterTts.stop();

    super.dispose();
  }

  // ==========================================================
  // 화면
  // ==========================================================

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

          Expanded(
            flex: 8,
            child: Container(
              width: double.infinity,
              color: Colors.black,
              child: _cameraController == null ||
                      !_cameraController!
                          .value
                          .isInitialized
                  ? const Center(
                      child:
                          CircularProgressIndicator(),
                    )
                  : CameraPreview(
                      _cameraController!,
                    ),
            ),
          ),

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
                            padding:
                                const EdgeInsets
                                    .symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            itemCount:
                                messages.length,
                            itemBuilder:
                                (context, index) {
                              final msg =
                                  messages[index];

                              final isUser =
                                  msg["sender"] ==
                                      "user";

                              return Container(
                                alignment: isUser
                                    ? Alignment
                                        .centerRight
                                    : Alignment
                                        .centerLeft,
                                padding:
                                    const EdgeInsets
                                        .symmetric(
                                  horizontal: 4,
                                  vertical: 2,
                                ),
                                child: Container(
                                  constraints:
                                      BoxConstraints(
                                    maxWidth:
                                        MediaQuery.of(
                                                  context,
                                                )
                                                .size
                                                .width *
                                            0.85,
                                  ),
                                  padding:
                                      const EdgeInsets
                                          .symmetric(
                                    horizontal: 10,
                                    vertical: 6,
                                  ),
                                  decoration:
                                      BoxDecoration(
                                    color: isUser
                                        ? Colors
                                            .pink[100]
                                        : Colors
                                            .grey[200],
                                    borderRadius:
                                        BorderRadius
                                            .circular(
                                      12,
                                    ),
                                  ),
                                  child: Text(
                                    msg["text"] ?? '',
                                    style:
                                        const TextStyle(
                                      fontSize: 13,
                                      color:
                                          Colors.black87,
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                  ),

                  if (isThinking)
                    const Padding(
                      padding:
                          EdgeInsets.symmetric(
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

                  Padding(
                    padding:
                        const EdgeInsets.fromLTRB(
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
                              controller:
                                  _textController,
                              decoration:
                                  InputDecoration(
                                hintText:
                                    '나온이에게 말을 걸어보세요...',
                                hintStyle:
                                    const TextStyle(
                                  fontSize: 12,
                                ),
                                contentPadding:
                                    const EdgeInsets
                                        .symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                border:
                                    OutlineInputBorder(
                                  borderRadius:
                                      BorderRadius
                                          .circular(
                                    20,
                                  ),
                                ),
                              ),
                              onSubmitted:
                                  (value) {
                                _addUserMessage(
                                  value,
                                );
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
