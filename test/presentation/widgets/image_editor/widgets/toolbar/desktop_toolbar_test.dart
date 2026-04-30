import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/presentation/widgets/image_editor/core/editor_state.dart';
import 'package:nai_launcher/presentation/widgets/image_editor/widgets/toolbar/desktop_toolbar.dart';

void main() {
  testWidgets('fill action should update when mask availability changes', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final state = EditorState();
    var canFillMask = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 64,
            height: 900,
            child: DesktopToolbar(
              state: state,
              onFillMask: () {},
              canFillMask: () => canFillMask,
            ),
          ),
        ),
      ),
    );

    final fillInkWellFinder = find.ancestor(
      of: find.byIcon(Icons.format_color_fill),
      matching: find.byType(InkWell),
    );

    expect(tester.widget<InkWell>(fillInkWellFinder).onTap, isNull);

    canFillMask = true;
    state.layerManager.addLayer(name: '蒙版');
    await tester.pump();

    expect(tester.widget<InkWell>(fillInkWellFinder).onTap, isNotNull);

    state.dispose();
  });
}
