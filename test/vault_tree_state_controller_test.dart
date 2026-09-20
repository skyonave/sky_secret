import 'package:flutter_test/flutter_test.dart';
import 'package:skysecret/core/settings/repositories/vault_tree_preferences.dart';
import 'package:skysecret/ui/vault/controllers/vault_tree_state_controller.dart';

void main() {
  test('general folders survive visiting the project list repeatedly', () {
    final state = VaultTreeStateController();
    state.restore('general', {'section'});
    state.collapsed.addAll({'folder', '@favorites'});
    state.clear();
    expect(state.collapsed, isEmpty);
    state.restore('general', {});
    expect(state.collapsed, {'section', 'folder', '@favorites'});
    state.clear();
    state.restore('general', {});
    expect(state.collapsed, {'section', 'folder', '@favorites'});
  });

  test('general and project folders remain independent including shared virtual sections', () {
    final state = VaultTreeStateController();
    state.restore('general', {'general-folder', '@favorites'});
    state.restore('project-a', {'project-folder'});
    state.collapsed.add('@trash');
    state.restore('project-b', {});
    state.collapsed.add('@favorites');
    state.restore('general', {});
    expect(state.collapsed, {'general-folder', '@favorites'});
    state.restore('project-a', {});
    expect(state.collapsed, {'project-folder', '@trash'});
    state.restore('project-b', {});
    expect(state.collapsed, {'@favorites'});
  });

  test('expanding every folder survives locking and repeated clearing', () {
    final state = VaultTreeStateController();
    state.restore('general', {'folder'});
    state.collapsed.clear();
    state.clear();
    state.clear();
    state.restore('general', {'folder'});
    expect(state.collapsed, isEmpty);
  });

  test('switching before a preference write finishes keeps the latest folder state', () async {
    final preferences = VaultTreePreferences();
    await preferences.save('general', {'older'});
    final state = VaultTreeStateController();
    state.restore('general', preferences.collapsed('general'));
    state.collapsed
      ..clear()
      ..add('latest');
    final saving = preferences.save('general', state.collapsed);
    state.clear();
    state.restore('general', preferences.collapsed('general'));
    expect(state.collapsed, {'latest'});
    await saving;
    expect(preferences.collapsed('general'), {'latest'});
  });
}
