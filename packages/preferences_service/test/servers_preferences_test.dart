import 'dart:convert';

import 'package:domain_models/domain_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:preferences_service/preferences_service.dart';

void main() {
  const web = ServerProfile(
    id: 'web',
    name: 'Web',
    protocol: ServerProtocol.sftp,
    host: 'web.example.com',
    user: 'deploy',
    auth: ServerAuth.agent,
  );
  const nas = ServerProfile(
    id: 'nas',
    protocol: ServerProtocol.davs,
    host: 'nas.lan',
    path: '/remote.php/dav/files/me',
  );

  test('saved servers go to the preferences and back, in their order', () {
    const prefs = Preferences(servers: [web, nas]);
    final text = jsonEncode(prefs.toJson());
    expect(text, isNot(contains('password')));
    final back = Preferences.fromJson(
      jsonDecode(text) as Map<String, Object?>,
    );
    expect(back.servers, [web, nas]);
    expect(back, prefs);
  });

  test('a broken entry is left out, an older file has none', () {
    final json = const Preferences(servers: [web]).toJson();
    json['servers'] = [
      {'id': 'x'},
      'nonsense',
      web.toJson(),
    ];
    expect(Preferences.fromJson(json).servers, [web]);
    json.remove('servers');
    expect(Preferences.fromJson(json).servers, isEmpty);
  });
}
