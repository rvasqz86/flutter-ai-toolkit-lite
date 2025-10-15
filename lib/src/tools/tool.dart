import '../../flutter_ai_toolkit.dart';

///Tool class
class GenericTool {
  ///Name of the tool
  final String name;
  ///Description of the tool
  final String description;
  ///Parameters of the tool
  final Parameters parameters;

  ///Constructor
  GenericTool({required this.name, required this.description, required this.parameters});

  ///Convert to JSON
  Map<String, Object> toJson(){
    return {
      'name': name,
      'description': description,
      'parameters': parameters.toJson(),
    };
  }
}

///Parameters class
class Parameters {
  final String type;
  final Map<String, dynamic> properties;

  ///Constructor
  Parameters({required this.type, required this.properties});

  ///Convert to JSON
  Map<String, Object> toJson() {
    return {
      'type': type,
      'properties': properties,
    };
  }
}



List<Map<String, dynamic>> buildMessages(String currentPrompt, String systemPrompt, List<ChatMessage> history) {
  final messages = <Map<String, dynamic>>[];

  // Add system prompt
  messages.add({
    'role': 'system',
    'content': systemPrompt,
  });

  // Add conversation history
  for (final message in history) {
    messages.add({
      'role': message.origin == MessageOrigin.user ? 'user' : 'assistant',
      'content': message.text,
    });
  }

  // Add current prompt if not already in history
  if (history.isEmpty || history.last.text != currentPrompt) {
    messages.add({
      'role': 'user',
      'content': currentPrompt,
    });
  }

  return messages;
}