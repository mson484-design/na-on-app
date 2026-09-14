import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:google_generative_ai/google_generative_ai.dart';

List<CameraDescription> cameras = [];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  cameras = await availableCameras();
  runApp(const MagicMirrorApp());
}

class MagicMirrorApp extends StatelessWidget {
  const MagicMirrorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primaryColor: Colors.pinkAccent,
        visualDensity: VisualDensity.adaptivePlatformDensity,
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
  
  // 🔥 기사님의 구글 AI API KEY가 안전하게 입력되어 있습니다 🔥
  static const apiKey = 'AQ.Ab8RN6KxepidiZrGquuKq3Kh4U3Clo3hl32ad4rWAk0w1kzTzw';
  late final GenerativeModel _aiModel;

  @override
  void initState() {
    super.initState();
    _aiModel = GenerativeModel(model: 'gemini-1.5-flash', apiKey: apiKey);
    _initCamera();
    _initTts();
  }

  Future<void> _initCamera() async {
    if (cameras.isEmpty) return;
    int cameraIndex = cameras.length > 1 ? 1 : 0;
    _cameraController = CameraController(cameras[cameraIndex], ResolutionPreset.medium);
    
    await _cameraController!.initialize();
    if (mounted) setState(() {});
    
    // 앱 시작 2초 후 얼굴 분석 시작
    Future.delayed(const Duration(seconds: 2), () {
      _analyzeFaceAndGreet();
    });
  }

  Future<void> _initTts() async {
    await _flutterTts.setLanguage("ko-KR");
    await _flutterTts.setSpeechRate(0.4);
    await _flutterTts.setPitch(1.0);
  }

  Future<void> _analyzeFaceAndGreet() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) return;
    
    setState(() => isThinking = true);
    
    try {
      final image = await _cameraController!.takePicture();
      final imageBytes = await image.readAsBytes();
      
      final prompt = TextPart("당신은 다정하고 우아한 뷰티/스타일 조언자 '나온'입니다. 첨부된 사진 속 인물의 스타일, 안색, 분위기를 확인하고 다정한 칭찬과 함께 가벼운 뷰티 또는 코디 제안을 2~3문장으로 자연스럽게 건네주세요.");
      final imagePart = DataPart('image/jpeg', imageBytes);
      
      final response = await _aiModel.generateContent([
        Content.multi([prompt, imagePart])
      ]);
      
      if (response.text != null) {
        _addAiMessage(response.text!);
      }
    } catch (e) {
      _addAiMessage("연결 상태가 좋지 않네요. API 키를 확인해 주세요!");
    } finally {
      setState(() => isThinking = false);
    }
  }

  Future<void> _addUserMessage(String text) async {
    if (text.isEmpty) return;
    
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
      _addAiMessage("제가 지금은 답을 드리기 어려워요.");
    } finally {
      setState(() => isThinking = false);
    }
  }

  void _addAiMessage(String text) {
    setState(() {
      messages.add({"sender": "ai", "text": text});
    });
    _flutterTts.speak(text);
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _flutterTts.stop();
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          SizedBox(
            width: double.infinity,
            height: double.infinity,
            child: _cameraController != null && _cameraController!.value.isInitialized
                ? CameraPreview(_cameraController!)
                : const Center(child: CircularProgressIndicator()),
          ),
          SafeArea(
            child: Column(
              children: [
                if (isThinking)
                  Container(
                    padding: const EdgeInsets.all(8.0),
                    color: Colors.black45,
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.pinkAccent, strokeWidth: 2)),
                        SizedBox(width: 8),
                        Text("나온이 거울 속 모습을 살피고 있어요...", style: TextStyle(color: Colors.white, fontSize: 12)),
                      ],
                    ),
                  ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16.0),
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      final msg = messages[index];
                      final isUser = msg["sender"] == "user";
                      return Align(
                        alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 8.0),
                          padding: const EdgeInsets.all(14.0),
                          decoration: BoxDecoration(
                            color: isUser ? Colors.pinkAccent.withOpacity(0.8) : Colors.white.withOpacity(0.85),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            msg["text"]!,
                            style: TextStyle(fontSize: 16, color: isUser ? Colors.white : Colors.black87, height: 1.4),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 12.0),
                  color: Colors.black54,
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _textController,
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            hintText: "거울에게 말해보세요...",
                            hintStyle: const TextStyle(color: Colors.white54),
                            filled: true,
                            fillColor: Colors.white24,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: BorderSide.none),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                          ),
                          onSubmitted: _addUserMessage,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.send, color: Colors.pinkAccent),
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
