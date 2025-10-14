import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/core/message.dart';
import 'package:flutter_gemma/core/model_response.dart';
import 'package:flutter_gemma/flutter_gemma_interface.dart';
import '../../tools/tool_service.dart';
import '../interface/attachments.dart';
import '../interface/chat_message.dart';
import '../interface/llm_provider.dart';


/// Provider to use a local llm
class LocalGemmaProvider extends LlmProvider with ChangeNotifier {
  /// Inference model on device
  final InferenceModel inferenceModel;

  /// Toolservice for calling
  final ToolService? toolService;

  /// System prompt
  final String systemPrompt;

  final List<ChatMessage> _history = [];

  /// Constructor
  LocalGemmaProvider(this.inferenceModel, this.systemPrompt, this.toolService);

  @override
  Stream<String> generateStream(
      String prompt, {
        Iterable<Attachment> attachments = const [],
      }) async* {
    yield* _streamResponse(prompt, updateHistory: false);
  }

  @override
  Iterable<ChatMessage> get history => List.unmodifiable(_history);

  @override
  set history(Iterable<ChatMessage> history) {
    _history.clear();
    _history.addAll(history);
    notifyListeners();
  }

  @override
  Stream<String> sendMessageStream(
      String prompt, {
        Iterable<Attachment> attachments = const [],
      }) async* {
    final userMessage = ChatMessage.user(prompt, attachments);
    _history.add(userMessage);
    notifyListeners();

    // Generate and collect response
    final responseBuffer = StringBuffer();

    await for (final chunk in _streamResponse(prompt, updateHistory: true)) {
      responseBuffer.write(chunk);
      yield chunk;
    }
    final assistantMessage = ChatMessage.llm()..append(responseBuffer.toString());
    _history.add(assistantMessage);
    notifyListeners();
  }

  Stream<String> _streamResponse(String prompt, {required bool updateHistory}) async* {
    var chat = await inferenceModel.createChat();

    chat.addQueryChunk(Message(text: systemPrompt, isUser: false));
    chat.addQueryChunk(Message(text: prompt, isUser: true));

    StreamController<String> controller = StreamController();
    chat.generateChatResponseAsync().listen(
          (ModelResponse response) {
        if (response is TextResponse) {
          controller.add(response.token);
        } else if (response is FunctionCallResponse) {
          if (toolService == null) {
            debugPrint('LLM service is null');
          } else {
            debugPrint('Executing tool: ${response.name}');
            controller.add(
              toolService!.executeTool(response.name, response.args).toString(),
            );
          }
        } else if (response is ThinkingResponse) {
          controller.add('Thinking: ${response.content}');
        }
      },
      onDone: () {
        debugPrint('Chat stream closed');
      },
      onError: (error) {
        debugPrint('Chat error: $error');
      },
    );

    yield* controller.stream;
  }
}
