import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/core/storage/local_storage_service.dart';
import 'package:nai_launcher/presentation/providers/layout_state_provider.dart';

void main() {
  group('LayoutState fixed tags sidebar fields', () {
    test('defaults to collapsed list mode with safe dimensions', () {
      const state = LayoutState();

      expect(state.fixedTagsSidebarExpanded, isFalse);
      expect(state.fixedTagsSidebarWidth, 280.0);
      expect(state.fixedTagsSidebarViewMode, 'list');
      expect(state.fixedTagsNegativeHeight, 180.0);
    });

    test('copyWith updates sidebar fields without resetting existing fields',
        () {
      final state = const LayoutState().copyWith(leftPanelWidth: 400.0);
      final updated = state.copyWith(
        fixedTagsSidebarExpanded: true,
        fixedTagsSidebarWidth: 320.0,
        fixedTagsSidebarViewMode: 'grid',
        fixedTagsNegativeHeight: 240.0,
      );

      expect(updated.leftPanelWidth, 400.0);
      expect(updated.fixedTagsSidebarExpanded, isTrue);
      expect(updated.fixedTagsSidebarWidth, 320.0);
      expect(updated.fixedTagsSidebarViewMode, 'grid');
      expect(updated.fixedTagsNegativeHeight, 240.0);
    });
  });

  group('LayoutStateNotifier fixed tags sidebar persistence', () {
    test('build reads sidebar state from storage', () {
      final storage = _FakeLayoutStorage()
        ..expanded = true
        ..width = 340.0
        ..viewMode = 'grid'
        ..negativeHeight = 260.0;
      final container = ProviderContainer(
        overrides: [
          localStorageServiceProvider.overrideWith((ref) => storage),
        ],
      );
      addTearDown(container.dispose);

      final state = container.read(layoutStateNotifierProvider);

      expect(state.fixedTagsSidebarExpanded, isTrue);
      expect(state.fixedTagsSidebarWidth, 340.0);
      expect(state.fixedTagsSidebarViewMode, 'grid');
      expect(state.fixedTagsNegativeHeight, 260.0);
    });

    test('setters write sidebar state back to storage', () async {
      final storage = _FakeLayoutStorage();
      final container = ProviderContainer(
        overrides: [
          localStorageServiceProvider.overrideWith((ref) => storage),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(layoutStateNotifierProvider.notifier);
      await notifier.setFixedTagsSidebarExpanded(true);
      await notifier.setFixedTagsSidebarWidth(360.0);
      await notifier.setFixedTagsSidebarViewMode('grid');
      await notifier.setFixedTagsNegativeHeight(300.0);

      expect(storage.expanded, isTrue);
      expect(storage.width, 360.0);
      expect(storage.viewMode, 'grid');
      expect(storage.negativeHeight, 300.0);
    });
  });
}

class _FakeLayoutStorage extends LocalStorageService {
  bool leftExpanded = true;
  bool rightExpanded = true;
  double leftWidth = 300.0;
  double rightWidth = 280.0;
  double promptHeight = 200.0;
  bool promptMaximized = false;
  bool expanded = false;
  double width = 280.0;
  String viewMode = 'list';
  double negativeHeight = 180.0;

  @override
  bool getLeftPanelExpanded() => leftExpanded;

  @override
  bool getRightPanelExpanded() => rightExpanded;

  @override
  double getLeftPanelWidth() => leftWidth;

  @override
  double getRightPanelWidth() => rightWidth;

  @override
  double getPromptAreaHeight() => promptHeight;

  @override
  bool getPromptMaximized() => promptMaximized;

  @override
  bool getFixedTagsSidebarExpanded() => expanded;

  @override
  Future<void> setFixedTagsSidebarExpanded(bool value) async {
    expanded = value;
  }

  @override
  double getFixedTagsSidebarWidth() => width;

  @override
  Future<void> setFixedTagsSidebarWidth(double value) async {
    width = value;
  }

  @override
  String getFixedTagsSidebarViewMode() => viewMode;

  @override
  Future<void> setFixedTagsSidebarViewMode(String value) async {
    viewMode = value;
  }

  @override
  double getFixedTagsNegativeHeight() => negativeHeight;

  @override
  Future<void> setFixedTagsNegativeHeight(double value) async {
    negativeHeight = value;
  }
}
