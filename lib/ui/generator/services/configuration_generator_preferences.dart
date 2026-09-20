import '../../../core/crypto/generator/models/generator_options.dart';
import '../../../core/settings/repositories/generator_preferences.dart';

class ConfigurationGeneratorPreferences extends GeneratorPreferences {
  final Future<dynamic> Function(String, dynamic) action;
  ConfigurationGeneratorPreferences(this.action);

  @override
  Future<GeneratorOptions> load() async => GeneratorOptions.fromJson(await action('generatorLoad', null));
  @override
  Future<void> save(GeneratorOptions options) async {
    await action('generatorSave', options.toJson());
  }
}
