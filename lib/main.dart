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
    _cameraController = CameraController(cameras[cameraIndex], ResolutionPreset.medium);

    await _cameraController!.initialize();
    if (mounted) setState(() {});

    Future.delayed(const Duration(seconds: 2), () {
      _analyzeFaceAndGreet();
    });
  }

  Future<void> _analyzeFaceAndGreet() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) return;

    setState(() => isThinking = true);

    try {
      final image = await _cameraController!.takePicture();
      final imageBytes = await image.readAsBytes();

      final prompt = TextPart("당신은 다정한 and 우아한 뷰티/스타일 조언자 '나온'입니다. 첨부된 사진 속 인물의 스타일, 안색, 분위기를 확인하고 첫인사를 다정하게 건네주세요.");
      final imagePart = DataPart('image/jpeg', imageBytes);

      final response = await _aiModel.generateContent([
        Content.multi([prompt, imagePart])
      ]);

      if (response.text != null) {
        _addAiMessage(response.text!);
      }
    } catch (e) {
      _addAiMessage("에러 발생: $e");
    } finally {
      setState(() => isThinking = false);
    }
  }

  Future<void> _addUserMessage(String text) async {
    if (text.isEmpty) {
      return;
    }

    setState(() {
      messages.add({"sender": "user", "text": text});
      isThinking = true;
    });
    _textController.clear();

    try {
      final prompt = "사용자가 '$text'라고 말했습니다. 다정한 거울 '나온'의 입장에서 짧게 대답해주세요.";
      final response = await _aiModel.generateContent([Content.text(prompt)]);

      if (response.text != null) {
        _addAiMessage(response.text!);
      }
    } catch (e) {
      _addAiMessage("에러 발생: $e");
    } finally {
      setState(() => isThinking = false);
    }
  }

  Future<void> _addAiMessage(String text) async {
    setState(() {
      messages.add({"sender": "ai", "text": text});
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
        title: const Text('나온 - 다정한 거울'),
        centerTitle: true,
      ),
      body: Column(
        children: [
          Expanded(
            flex: 5,
            child: _cameraController == null || !_cameraController!.value.isInitialized
                ? const Center(child: CircularProgressIndicator())
                : CameraPreview(_cameraController!),
          ),
          Expanded(
            flex: 5,
            child: Column(
              children: [
                Expanded(
                  child: ListView.builder(
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      final msg = messages[index];
                      final isUser = msg["sender"] == "user";
                      return Container(
                        alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isUser ? Colors.pink[100] : Colors.grey[200],
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(msg["text"] ?? ''),
                        ),
                      );
                    },
                  ),
                ),
                if (isThinking)
                  const Padding(
                    padding: EdgeInsets.all(8.0),
                    child: Text("나온이가 생각 중이에요...", style: TextStyle(color: Colors.grey)),
                  ),
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _textController,
                          decoration: const InputDecoration(
                            hintText: '나온이에게 말을 걸어보세요...',
                            border: OutlineInputBorder(),
                          ),
                          onSubmitted: (value) => _addUserMessage(value),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.send, color: Colors.pink),
                        onPressed: () => _addUserMessage(_textController.text),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
