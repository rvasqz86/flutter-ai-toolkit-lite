
import 'package:flutter_ai_toolkit/src/tools/tool.dart';
/// ToolService interface
abstract class ToolService {

  /// Executes a tool with the given name and arguments.
  Future<dynamic> executeTool(String toolName, Map<String, dynamic> args);

  /// Retrieves a list of available tools.
  Future<List<GenericTool>> getAvailableTools();

  /// Executes a list of tool calls.
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
