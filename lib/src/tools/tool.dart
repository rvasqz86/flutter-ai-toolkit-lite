class GenericTool {
  final String name;
  final String description;
  final Parameters parameters;

  GenericTool({required this.name, required this.description, required this.parameters});

}

class Parameters {
  final String type;
  final Map<String, dynamic> properties;

  Parameters({required this.type, required this.properties});
}
