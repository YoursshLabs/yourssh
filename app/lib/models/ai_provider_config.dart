enum AiProvider { anthropic, openai, gemini }

class AiProviderConfig {
  final String apiKey;
  final String model;

  const AiProviderConfig({required this.apiKey, required this.model});
}
