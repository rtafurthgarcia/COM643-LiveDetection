import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:liveprotector/warning_message.dart';
import 'package:openai_dart/openai_dart.dart';

class ProtectionProvider with ChangeNotifier {
  Exception? _exception;
  Exception? get exception => _exception;

  final String model;
  final int wordThresholdBeforeProcessing;

  late OpenAIClient _client;

  bool _warningTriggered = false;
  bool get warningTriggered => _warningTriggered;

  String? _warningMessage;
  String? get warningMessage => _warningMessage;

  late final ChatCompletionMessage _systemMessage;

  int _wordCountSinceLastProcessing = 0;

  ProtectionProvider(
    { this.model = "gemma-2-2b-it",
    required String baseUrl, 
    required String systemMessage, 
    this.wordThresholdBeforeProcessing = 5 }
  ) {
    _client = OpenAIClient(
      apiKey: "xD",
      baseUrl: baseUrl
    );

    // the system message that will be sent to the request.
    _systemMessage = ChatCompletionMessage.system(
      content: systemMessage,
    );
  }

  void verifyTranscript(String conversation) async {
    // We don't want to overload the server so we only send requests every X amount of words
    final wordCount = conversation.split(' ').length;
    if ((wordCount - _wordCountSinceLastProcessing).abs() > wordThresholdBeforeProcessing) {
      if (wordCount == 0) {
        reset();
      }
      
      return;
    } else {
      _wordCountSinceLastProcessing = wordCount;
    }

    // the user message that will be sent to the request.
    final userMessage = ChatCompletionMessage.user(
      content: ChatCompletionUserMessageContent.string(conversation)
    );

    final requestMessages = [
      _systemMessage,
      userMessage
    ];

    // the actual request.
    final res = await _client.createChatCompletion(
      request: CreateChatCompletionRequest(
        model: ChatCompletionModel.modelId(model), 
        messages: requestMessages,
        temperature: 0.2,
        responseFormat: ResponseFormat.jsonSchema(
          jsonSchema: JsonSchemaObject(
            name: 'Generated warning',
            description: 'A warning, if necessary',
            strict: true,
            schema: {
              "description": "",
              "type": "object",
              "properties": {
                "warning": {
                  "type": "boolean"
                },
                "reason": {
                  "type": "string",
                  "minLength": 1
                }
              },
              "required": [
                "warning",
                "reason"
              ]
            }
          ),
        )
      )
    );

    var warningMessage = WarningMessage.fromJson(jsonDecode(res.choices.last.message.content ?? "") as Map<String, dynamic>);
    _warningMessage = warningMessage.reason;
    _warningTriggered = warningMessage.warning;
    notifyListeners();
  }

  void reset() {
    _exception = null;
    _warningMessage = "";
    _warningTriggered = false;
    _wordCountSinceLastProcessing = 0;
    notifyListeners();
  }
}