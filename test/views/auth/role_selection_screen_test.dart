import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:med_supply_prototype/views/auth/role_selection_screen.dart';

void main() {
  // The role selection screen is the landing page. Issue #326 makes its
  // two role cards real, accessible buttons: focusable, activatable by
  // Enter / Space, and announced as a button by screen readers.
  group('RoleSelectionScreen accessibility (#326)', () {
    late GoRouter router;

    setUp(() {
      router = GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(
            path: '/',
            builder: (_, __) => const RoleSelectionScreen(),
          ),
          GoRoute(
            path: '/login/facility',
            builder: (_, __) => const Scaffold(body: Text('FACILITY LOGIN')),
          ),
          GoRoute(
            path: '/login/admin',
            builder: (_, __) => const Scaffold(body: Text('ADMIN LOGIN')),
          ),
        ],
      );
    });

    Widget app() => ProviderScope(
          child: MaterialApp.router(routerConfig: router),
        );

    /// The page's two side-by-side panels overflow the default 800x600
    /// test viewport, so we run the tests on a wider surface.
    void useWideSurface(WidgetTester tester) {
      tester.view.physicalSize = const Size(2400, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
    }

    testWidgets('each role card is announced as a button with title + subtitle',
        (tester) async {
      useWideSurface(tester);
      await tester.pumpWidget(app());
      // The role screen has a forever-repeating pulse animation, so
      // pumpAndSettle would hang. One frame is enough to build the tree
      // and surface the Semantics nodes.
      await tester.pump();

      // Semantics should expose one button per card whose label combines
      // the title and subtitle so screen readers speak them as a single
      // affordance.
      final facilityLabel = find.bySemanticsLabel(
        RegExp(r'Facility Head\..*Manage inventory, daily logs & AI indents'),
      );
      final adminLabel = find.bySemanticsLabel(
        RegExp(r'CMS Admin\..*Global logistics & redistribution planning'),
      );

      expect(facilityLabel, findsOneWidget);
      expect(adminLabel, findsOneWidget);

      // Each card must be flagged as a button. We grab the Semantics
      // node for the labelled widget and check its flags.
      expect(
        tester
            .getSemantics(facilityLabel)
            .getSemanticsData()
            .flagsCollection
            .isButton,
        isTrue,
        reason: 'Facility card should be exposed as a button semantics.',
      );
      expect(
        tester
            .getSemantics(adminLabel)
            .getSemanticsData()
            .flagsCollection
            .isButton,
        isTrue,
        reason: 'Admin card should be exposed as a button semantics.',
      );
    });

    testWidgets('Tab moves focus through the role cards (#326)',
        (tester) async {
      useWideSurface(tester);
      await tester.pumpWidget(app());
      await tester.pump();

      // Walk the tab order and record which focusable nodes get focus.
      // The new FocusableActionDetector wrappers add one Focus node per
      // card, so there should be at least two focusables (plus the
      // brand-side focus nodes if any).
      final focusables = <FocusNode>[];

      for (final element in find.byType(Focus).evaluate()) {
        final w = element.widget as Focus;
        if (w.focusNode != null) focusables.add(w.focusNode!);
      }
      expect(focusables.length, greaterThanOrEqualTo(2),
          reason: 'Expected at least two focusable nodes (one per card).');

      // First Tab should advance focus to a different focusable than
      // the initial state. The role cards are the *first* focusable
      // stops on the page, so after one Tab the first focusable has
      // focus.
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(focusables.first.hasFocus, isTrue,
          reason: 'First Tab should focus the first role card.');

      // Second Tab → second focusable (CMS Admin).
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(focusables[1].hasFocus, isTrue,
          reason: 'Second Tab should focus the second role card.');
    });

    testWidgets('focusing a card toggles the visible focus ring',
        (tester) async {
      useWideSurface(tester);
      await tester.pumpWidget(app());
      await tester.pump();

      // Find the FocusableActionDetector wrapping the Facility Head card
      // by its enclosing Semantics label.
      final facilityDetector = find.descendant(
        of: find.bySemanticsLabel(RegExp(r'Facility Head\.')),
        matching: find.byType(FocusableActionDetector),
      );
      expect(facilityDetector, findsOneWidget);
      final detectorWidget =
          tester.widget<FocusableActionDetector>(facilityDetector);

      // The FocusableActionDetector owns a private FocusNode; we trigger
      // a focus change by calling its `onFocusChange` callback directly
      // with `true` to flip `_isFocusedFacility` in the screen state.
      detectorWidget.onFocusChange?.call(true);
      await tester.pump();

      // Re-read the AnimatedContainer's border colour.
      final afterDecoration = tester.widget<AnimatedContainer>(find
          .descendant(
            of: find.bySemanticsLabel(RegExp(r'Facility Head\.')),
            matching: find.byType(AnimatedContainer),
          )
          .first);
      final afterBorderSide =
          (afterDecoration.decoration as BoxDecoration).border!.top;
      const defaultBorderColor = Color(0xFF2A3550);

      // The focus ring reuses the gradient colour, not the default border.
      // Both being equal would mean the focus state did not propagate.
      expect(afterBorderSide.color, isNot(defaultBorderColor),
          reason: 'Focusing the card should swap the border for the gradient '
              'tint so keyboard users see a focus indicator.');
    });
  });
}
