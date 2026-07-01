import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum GemmaStatus { idle, pickingFile, installing, ready, error }

class GemmaService extends ChangeNotifier {
  static const _prefsKey = 'gemma_model_path';

  GemmaStatus status = GemmaStatus.idle;
  String? modelPath;
  String? errorMessage;
  int installProgress = 0;

  InferenceModel? _model;
  InferenceChat? _chat;

  Future<void> tryAutoLoad() async {
    final prefs = await SharedPreferences.getInstance();
    final savedPath = prefs.getString(_prefsKey);
    if (savedPath == null) return;
    if (!File(savedPath).existsSync()) {
      await prefs.remove(_prefsKey);
      return;
    }
    await _installFromPath(savedPath);
  }

  /// Kullanıcıya dosya seçici açar, seçilen .bin dosyasını yükler.
  Future<void> pickAndInstall() async {
    status = GemmaStatus.pickingFile;
    notifyListeners();

    final result = await FilePicker.platform.pickFiles(type: FileType.any, withData: false);

    if (result == null || result.files.single.path == null) {
      status = GemmaStatus.idle;
      notifyListeners();
      return;
    }

    final path = result.files.single.path!;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, path);

    await _installFromPath(path);
  }

  Future<void> _installFromPath(String path) async {
    status = GemmaStatus.installing;
    errorMessage = null;
    installProgress = 0;
    notifyListeners();

    try {
      await FlutterGemma.installModel(
        modelType: ModelType.gemmaIt,
        fileType: ModelFileType.task,
      ).fromFile(path).withProgress((int progress) {
        installProgress = progress;
        notifyListeners();
      }).install();

      _model = await FlutterGemma.getActiveModel(
        maxTokens: 1024,
        preferredBackend: PreferredBackend.cpu,
      );

      _chat = await _model!.createChat();

      modelPath = path;
      status = GemmaStatus.ready;
      notifyListeners();
    } catch (e) {
      errorMessage = e.toString();
      status = GemmaStatus.error;
      notifyListeners();
    }
  }

  Future<void> resetChat() async {
    if (_model == null) return;
    await _chat?.stopGeneration();
    _chat = await _model!.createChat();
    notifyListeners();
  }

  Stream<String> askStream(String userMessage) async* {
    if (_chat == null) {
      throw StateError('Model henüz hazır değil.');
    }

    await _chat!.addQueryChunk(Message.text(text: userMessage, isUser: true));

    await for (final chunk in _chat!.generateChatResponseAsync()) {
      if (chunk is TextResponse) {
        if (chunk.token.isNotEmpty) {
          yield chunk.token;
        }
      }
    }
  }

  @override
  Future<void> dispose() async {
    await _model?.close();
    super.dispose();
  }
}
