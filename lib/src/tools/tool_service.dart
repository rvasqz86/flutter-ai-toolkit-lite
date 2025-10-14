

import 'package:rads_consult_llm/tools/tool.dart';

abstract class ToolService {
  Future<dynamic> executeTool(String toolName, Map<String, dynamic> args);

  Future<List<GenericTool>> getAvailableTools();

  Future<List<Map<String, dynamic>>> executeToolCalls(List<dynamic> toolCalls) async {
    final results = <Map<String, dynamic>>[];
    for (final toolCall in toolCalls) {
      try {
        final toolName = toolCall['name'] as String;
        final arguments = toolCall['arguments'] as Map<String, dynamic>;

        final result = await executeTool(toolName, arguments);
        results.add({'tool_name': toolName, 'success': true, 'result': result});
      } catch (e) {
        results.add({
          'tool_name': toolCall['name'],
          'success': false,
          'error': e.toString(),
        });
      }
    }
    return results;
  }
}
