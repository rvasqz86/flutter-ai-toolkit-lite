import 'dart:async';
import 'dart:math';

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

  /// Temperature for response generation (0.0 to 1.0)
  final double temperature;

  /// Top-K sampling parameter
  final int topK;

  /// Token buffer for context management
  final int tokenBuffer;

  final List<ChatMessage> _history = [];

  /// Persistent chat session
  InferenceChat? _chat;

  /// Random number generator for seed variation
  static final _random = Random();

  /// Constructor
  LocalGemmaProvider(
    this.inferenceModel,
    this.systemPrompt,
    this.toolService, {
    this.temperature = 0.8,
    this.topK = 40,
    this.tokenBuffer = 256,
  })  : assert(temperature >= 0.0 && temperature <= 1.0,
            'temperature must be between 0.0 and 1.0'),
        assert(topK > 0, 'topK must be greater than 0'),
        assert(tokenBuffer > 0, 'tokenBuffer must be greater than 0');

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
  Future<void> clearHistory() async {
    _history.clear();
    // Properly dispose the chat session before nulling
    if (_chat != null) {
      try {
        await _chat!.stopGeneration();
      } catch (e) {
        debugPrint('Error stopping generation during clearHistory: $e');
      }
    }
    _chat = null;
    notifyListeners();
  }

  /// Dispose the provider and clean up resources
  ///
  /// Note: dispose() must be synchronous per ChangeNotifier contract, but stopGeneration()
  /// is async. We use fire-and-forget here - the async cleanup will complete eventually,
  /// but may not be immediate. This is acceptable as the native resources will eventually
  /// be cleaned up by the async operation, even after the Dart object is disposed.
  @override
  void dispose() {
    if (_chat != null) {
      // Fire-and-forget: stopGeneration is async but dispose must be sync.
      // Resources may remain temporarily active but will clean up eventually.
      unawaited(_chat!.stopGeneration().catchError((e) {
        debugPrint('Error stopping generation during dispose: $e');
        return Future.value();
      }));
      _chat = null;
    }
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
        temperature: temperature,
        randomSeed: _random.nextInt(100000),  // Use Random for better entropy
        topK: topK,
        tokenBuffer: tokenBuffer,
    );

    // Calculate how many messages to replay (exclude current user message if already in history)
    // The current user message was added to _history in sendMessageStream before calling this method
    final messagesToReplay = updateHistory ? _history.length - 1 : _history.length;
    debugPrint('LocalGemmaProvider: Replaying $messagesToReplay messages from history');

    // Add system prompt first
    await _chat!.addQueryChunk(Message(text: systemPrompt, isUser: false));

    // Replay previous messages (both user and assistant), but exclude the current user message
    // that was just added to _history in sendMessageStream to avoid duplication
    for (var i = 0; i < messagesToReplay; i++) {
      final msg = _history[i];
      if (msg.origin == MessageOrigin.user) {
        await _chat!.addQueryChunk(Message(text: msg.text, isUser: true));
      } else if (msg.origin == MessageOrigin.llm) {
        await _chat!.addQueryChunk(Message(text: msg.text, isUser: false));
      }
    }

    // Add the current user message (prompt parameter)
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
