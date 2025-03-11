import 'package:dart_openai/dart_openai.dart';
import 'package:flutter/foundation.dart';
import 'package:liveprotector/bit_of_conversation.dart';
import 'package:collection/collection.dart';

class LLMProvider with ChangeNotifier {
  Exception? _error;
  Exception? get error => _error;

  late final OpenAIModelModel _model;
  OpenAIModelModel get model => _model;

  bool _warningTriggered = false;
  bool get warningTriggered => _warningTriggered;

  String? _warningMessage;
  String? get warningMessage => _warningMessage;

  late final OpenAIChatCompletionChoiceMessageModel _systemMessage;
  final PriorityQueue<BitOfConversation> _queue = PriorityQueue((p0, p1) => p0.on.compareTo(p1.on));

  LLMProvider({ required String baseUrl, required String systemMessage }) {
    OpenAI.baseUrl = baseUrl;

    try {
      fetchModel();

      // the system message that will be sent to the request.
      _systemMessage = OpenAIChatCompletionChoiceMessageModel(
        content: [
          OpenAIChatCompletionChoiceMessageContentItemModel.text(
            systemMessage,
          ),
        ],
        role: OpenAIChatMessageRole.assistant,
      );
    } on RequestFailedException catch(e) {
      _error = e;
      notifyListeners();
    }
  }

  Future<void> fetchModel() async {
    List<OpenAIModelModel> models = await OpenAI.instance.model.list();
    _model = models.first;
    notifyListeners();
  }

  void verifyNewChunkOfConversation(String newChunk) async {
    // the user message that will be sent to the request.
    final userMessage = OpenAIChatCompletionChoiceMessageModel(
      content: [
        OpenAIChatCompletionChoiceMessageContentItemModel.text(
          newChunk,
        ),
      ],
      role: OpenAIChatMessageRole.user,
    );

    _queue.add(BitOfConversation(chunk: newChunk));

    final requestMessages = [
      _systemMessage,
      userMessage
    ];

    // the actual request.
    OpenAIChatCompletionModel chatCompletion = await OpenAI.instance.chat.create(
      model: _model.id,
      responseFormat: {"type": "json_object"},
      messages: requestMessages,
      temperature: 0.2,
      maxTokens: 500,
    );

    
  }
}