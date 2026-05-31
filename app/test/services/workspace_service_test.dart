import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/providers/terminal_layout_provider.dart';
import 'package:yourssh/services/workspace_service.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('WorkspaceSnapshot.toJson / fromJson', () {
    test('round-trips all fields', () {
      const snap = WorkspaceSnapshot(
        hostIds: ['id-1', 'id-2'],
        activeHostId: 'id-1',
        layout: SplitLayout.horizontal,
        inputBarVisible: true,
      );
      final restored = WorkspaceSnapshot.fromJson(snap.toJson());
      expect(restored.hostIds, snap.hostIds);
      expect(restored.activeHostId, snap.activeHostId);
      expect(restored.layout, snap.layout);
      expect(restored.inputBarVisible, snap.inputBarVisible);
    });

    test('fromJson: missing activeHostId → null', () {
      final snap = WorkspaceSnapshot.fromJson({
        'hostIds': <String>[],
        'layout': 'single',
        'inputBarVisible': false,
      });
      expect(snap.activeHostId, isNull);
    });

    test('fromJson: unknown layout → SplitLayout.single', () {
      final snap = WorkspaceSnapshot.fromJson({
        'hostIds': <String>[],
        'activeHostId': null,
        'layout': 'unknown_value',
        'inputBarVisible': false,
      });
      expect(snap.layout, SplitLayout.single);
    });

    test('fromJson: missing inputBarVisible → false', () {
      final snap = WorkspaceSnapshot.fromJson({
        'hostIds': <String>[],
        'activeHostId': null,
        'layout': 'single',
      });
      expect(snap.inputBarVisible, isFalse);
    });
  });

  group('WorkspaceService', () {
    test('load returns null when key absent', () async {
      expect(await WorkspaceService().load(), isNull);
    });

    test('save then load round-trips snapshot', () async {
      const snap = WorkspaceSnapshot(
        hostIds: ['a', 'b'],
        activeHostId: 'a',
        layout: SplitLayout.vertical,
        inputBarVisible: false,
      );
      await WorkspaceService().save(snap);
      final loaded = await WorkspaceService().load();
      expect(loaded?.hostIds, ['a', 'b']);
      expect(loaded?.layout, SplitLayout.vertical);
      expect(loaded?.activeHostId, 'a');
    });

    test('clear makes load return null', () async {
      await WorkspaceService().save(const WorkspaceSnapshot(
        hostIds: ['x'],
        activeHostId: null,
        layout: SplitLayout.single,
        inputBarVisible: false,
      ));
      await WorkspaceService().clear();
      expect(await WorkspaceService().load(), isNull);
    });

    test('load returns null for malformed JSON', () async {
      SharedPreferences.setMockInitialValues(
          {'workspace_snapshot': 'not-valid-json{{'});
      expect(await WorkspaceService().load(), isNull);
    });
  });
}
