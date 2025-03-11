import 'dart:core';

import 'package:cheetah_flutter/cheetah_error.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:liveprotector/cheetah_manager.dart';

class TranscriptionProvider with ChangeNotifier {
  late final CheetahManager _cheetahManager;

  final String _modelPath;

  Exception? _error;
  Exception? get error => _error;

  bool _isProcessing = false;
  bool get isProcessing => _isProcessing;
  String _transcriptText = "";
  String get transcriptText => _transcriptText;

  TranscriptionProvider({required String modelPath}) : _modelPath = modelPath {
    initCheetah();
  }

  Future<void> initCheetah() async {
    String apiKey = await rootBundle.loadString('assets/apikey.txt');

    try {
      _cheetahManager = await CheetahManager.create(
        apiKey,
        _modelPath,
        _transcriptCallback,
        _errorCallback,
      );
      notifyListeners();
    } on CheetahActivationException {
      _errorCallback(CheetahActivationException("AccessKey activation error."));
    } on CheetahActivationLimitException {
      _errorCallback(
        CheetahActivationLimitException("AccessKey reached its device limit."),
      );
    } on CheetahActivationRefusedException {
      _errorCallback(CheetahActivationRefusedException("AccessKey refused."));
    } on CheetahActivationThrottledException {
      _errorCallback(
        CheetahActivationThrottledException("AccessKey has been throttled."),
      );
    } on CheetahException catch (ex) {
      _errorCallback(ex);
    }
  }

  void _errorCallback(CheetahException error) {
    _error = error;
    notifyListeners();
  }

  void _transcriptCallback(String transcript) {
    _transcriptText = transcriptText + transcript;
    notifyListeners();
  }

  Future<void> startProcessing() async {
    if (isProcessing) {
      return;
    }

    try {
      await _cheetahManager.startProcess();
      _transcriptText = "";
      _isProcessing = true;
      notifyListeners();
    } on CheetahException catch (ex) {
      _errorCallback(ex);
    }
  }

  Future<void> stopProcessing() async {
    if (!isProcessing) {
      return;
    }

    try {
      await _cheetahManager.stopProcess();
      _isProcessing = false;
      notifyListeners();
    } on CheetahException catch (ex) {
      _errorCallback(ex);
    }
  }
}
