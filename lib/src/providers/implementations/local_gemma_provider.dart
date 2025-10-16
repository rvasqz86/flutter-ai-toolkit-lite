import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/core/chat.dart';
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

  /// Persistent chat session
  InferenceChat? _chat;

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

  /// Clears the chat history and resets the chat session
  void clearHistory() {
    _history.clear();
    _chat = null; // Reset the chat session
    notifyListeners();
  }

  /// Dispose the provider and clean up resources
  @override
  void dispose() {
    _chat = null;
    super.dispose();
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
    // ALWAYS recreate chat session to ensure full history context
    // This is necessary because the native session doesn't retain state after getResponseAsync()
    debugPrint('LocalGemmaProvider: Creating fresh chat session with full history replay');
    _chat = await inferenceModel.createChat(
        temperature: 0.8,
        randomSeed: DateTime.now().millisecondsSinceEpoch % 100000,  // Use varying seed
        topK: 40,
        tokenBuffer: 256,
    );

    // Replay full conversation history from _history
    debugPrint('LocalGemmaProvider: Replaying ${_history.length} messages from history');

    // Add system prompt first
    await _chat!.addQueryChunk(Message(text: systemPrompt, isUser: false));

    // Replay all previous messages (both user and assistant)
    for (final msg in _history) {
      if (msg.origin == MessageOrigin.user) {
        await _chat!.addQueryChunk(Message(text: msg.text, isUser: true));
      } else if (msg.origin == MessageOrigin.llm) {
        await _chat!.addQueryChunk(Message(text: msg.text, isUser: false));
      }
    }

    // Add the current user message
    debugPrint('LocalGemmaProvider: Adding current user message: $prompt');
    await _chat!.addQueryChunk(Message(text: prompt, isUser: true));

    StreamController<String> controller = StreamController();
    _chat!.generateChatResponseAsync().listen(
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
        controller.close();
      },
      onError: (error) {
        debugPrint('Chat error: $error');
        controller.close();
      },
    );

    yield* controller.stream;
  }
}
