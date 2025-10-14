import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter_ai_toolkit/flutter_ai_toolkit.dart';
import 'package:http/http.dart' as http;

import '../../tools/tool.dart';
import '../../tools/tool_service.dart';

/// Openrouter provider to be used with the standard api or Lite LLM
class OpenRouterProvider extends LlmProvider with ChangeNotifier {
  
  /// Base URL of API
  final String apiBaseUrl;
  
  /// Key
  final String apiKey;
  
  /// Model of choice  
  final String model;

  
  /// System prompt 
  final String systemPrompt;
  
  /// Tool Service provider
  final ToolService? toolService;

  final List<ChatMessage> _history = [];

  /// Constructor
  OpenRouterProvider(this.apiBaseUrl, this.apiKey, this.model, {
    required this.systemPrompt,
    this.toolService,
    Iterable<ChatMessage>? initialHistory,
  }) {
    if (initialHistory != null) {
      _history.addAll(initialHistory);
    }
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
  Stream<String> generateStream(
      String prompt, {
        Iterable<Attachment> attachments = const [],
      }) async* {
    // Generate without affecting history
    yield* _streamResponse(prompt, updateHistory: false);
  }

  @override
  Stream<String> sendMessageStream(
      String prompt, {
        Iterable<Attachment> attachments = const [],
      }) async* {
    // Add user message to history
    final userMessage = ChatMessage.user(prompt, attachments);
    _history.add(userMessage);
    notifyListeners();

    // Generate and collect response
    final responseBuffer = StringBuffer();

    await for (final chunk in _streamResponse(prompt, updateHistory: true)) {
      responseBuffer.write(chunk);
      yield chunk;
    }

    // Add assistant message to history
    final assistantMessage = ChatMessage.llm()..append(responseBuffer.toString());
    _history.add(assistantMessage);
    notifyListeners();
  }

  Stream<String> _streamResponse(String prompt, {required bool updateHistory}) async* {
    try {
      // Prepare messages for API
      final messages = buildMessages(systemPrompt, prompt, _history);

      // Prepare request payload
      final payload = {
        'model': model,
        'messages': messages,
        'stream': true,
        'temperature': 0.7,
        'max_tokens': 2048,
      };

      // Add tools if enabled
      if (toolService != null) {
        final tools = await toolService?.getAvailableTools()??[];
        if (tools.isNotEmpty) {
          payload['tools'] = tools.map((tool) => {
            'type': 'function',
            'function': tool,
          }).toList();
        }
      }

      // Make streaming request
      final request = http.Request('POST', Uri.parse('$apiBaseUrl/chat/completions'));
      request.headers.addAll({
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $apiKey',
        'HTTP-Referer': 'https://ascendjj.com',
        'X-Title': 'AscendJJ Admin',
      });
      request.body = jsonEncode(payload);

      final streamedResponse = await http.Client().send(request);

      if (streamedResponse.statusCode != 200) {
        final errorBody = await streamedResponse.stream.bytesToString();
        debugPrint('OpenRouter API error: ${streamedResponse.statusCode} - $errorBody');
        yield 'Error: Failed to get response from AI (${streamedResponse.statusCode})';
        return;
      }

      // Process streaming response
      final responseBuffer = StringBuffer();
      final toolCallsBuffer = <Map<String, dynamic>>[];

      await for (final chunk in streamedResponse.stream.transform(utf8.decoder).transform(const LineSplitter())) {
        if (chunk.isEmpty || !chunk.startsWith('data: ')) continue;

        final data = chunk.substring(6); // Remove 'data: ' prefix
        if (data == '[DONE]') break;

        try {
          final json = jsonDecode(data);
          final choices = json['choices'] as List?;
          if (choices == null || choices.isEmpty) continue;

          final delta = choices[0]['delta'];

          // Handle text content
          if (delta['content'] != null) {
            final content = delta['content'] as String;
            responseBuffer.write(content);
            yield content;
          }

          // Handle tool calls
          if (toolService != null && delta['tool_calls'] != null) {
            final toolCalls = delta['tool_calls'] as List;
            toolCallsBuffer.addAll(toolCalls.cast<Map<String, dynamic>>());
          }
        } catch (e) {
          debugPrint('Error parsing streaming chunk: $e');
          continue;
        }
      }

      // Execute tool calls if any
      if (toolCallsBuffer.isNotEmpty) {
        yield '\n\n---\n**Tool Execution Results:**\n';

        for (final toolCall in toolCallsBuffer) {
          try {
            // Safely extract function name and arguments
            final function = toolCall['function'];
            if (function == null) {
              debugPrint('Tool call missing function: $toolCall');
              continue;
            }

            final functionName = function['name'] as String?;
            final argumentsStr = function['arguments'] as String?;

            if (functionName == null || argumentsStr == null || argumentsStr.isEmpty) {
              debugPrint('Invalid tool call - name: $functionName, args: $argumentsStr');
              continue;
            }

            final arguments = jsonDecode(argumentsStr) as Map<String, dynamic>;

            yield '\n• Executing: $functionName...';

            final result = await toolService?.executeTool(functionName, arguments);
            yield ' ✓ Success';

            // Optionally add result details
            if (result is Map && result.toString().length > 100) {
              yield '\n  Result: ${result.toString().substring(0, 100)}...';
            } else if (result != null) {
              yield '\n  Result: ${result.toString()}';
            }
          } catch (e) {
            yield ' ✗ Failed: ${e.toString()}';
            debugPrint('Tool execution failed: $e');
          }
        }
      }

    } catch (e, st) {
      debugPrint('Error in OpenRouter streaming: $e');
      debugPrintStack(stackTrace: st);
      yield '\n\nError: ${e.toString()}';
    }
  }



  /// Clear conversation history
  void clearHistory() {
    _history.clear();
    notifyListeners();
  }
}