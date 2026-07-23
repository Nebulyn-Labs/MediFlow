import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:med_supply_prototype/constants/colors.dart';
import 'services/firebase_setup.dart';
import 'services/theme_provider.dart';import 'views/auth/role_selection_screen.dart';
import 'views/auth/login_screen.dart';
import 'views/shared/sidebar_layout.dart';
import 'views/shared/help_page.dart';

// Facility Pages
import 'views/facility/facility_overview.dart';
import 'views/facility/ai_forecast_page.dart';
import 'views/facility/active_indents_page.dart';
import 'views/facility/daily_logging_page.dart';
import 'views/facility/alerts_page.dart';

// Admin Pages
import 'views/admin/admin_overview.dart';
import 'views/admin/admin_indent_approval_page.dart';
import 'views/admin/admin_indent_status_page.dart';
import 'views/admin/route_optimization_map.dart';
import 'views/shared/ai_chat_page.dart';

final GlobalKey<NavigatorState> _rootNavigatorKey = GlobalKey<NavigatorState>();
final GlobalKey<NavigatorState> _facilityShellNavigatorKey =
    GlobalKey<NavigatorState>();
final GlobalKey<NavigatorState> _adminShellNavigatorKey =
    GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase and App Check securely
  await initializeFirebaseServices();

  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: true,
    cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
  );

  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    debugPrint('FlutterError: ${details.exceptionAsString()}');
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('PlatformDispatcher error: $error\n$stack');
    return true;
  };

  runApp(const ProviderScope(child: MediFlowApp()));
}

final _router = GoRouter(
  navigatorKey: _rootNavigatorKey,
  initialLocation: '/',
  redirect: (context, state) {
    final isLoggedIn = FirebaseAuth.instance.currentUser != null;
    final isAuthRoute = state.uri.toString() == '/' ||
        state.uri.toString().startsWith('/login');
    if (!isLoggedIn && !isAuthRoute) return '/';
    return null;
  },
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const RoleSelectionScreen(),
    ),
    GoRoute(
      path: '/login/:role',
      builder: (context, state) {
        final role = state.pathParameters['role']!;
        return LoginScreen(role: role);
      },
    ),
    ShellRoute(
      navigatorKey: _facilityShellNavigatorKey,
      builder: (context, state, child) {
        final pathParams = state.pathParameters;
        return SidebarLayout(
            role: 'facility', facilityId: pathParams['id'], child: child);
      },
      routes: [
        GoRoute(
            path: '/facility/:id/overview',
            builder: (context, state) =>
                FacilityOverview(facilityId: state.pathParameters['id']!)),
        GoRoute(
            path: '/facility/:id/forecast',
            builder: (context, state) =>
                AIForecastPage(facilityId: state.pathParameters['id']!)),
        GoRoute(
            path: '/facility/:id/indent',
            builder: (context, state) =>
                ActiveIndentsPage(facilityId: state.pathParameters['id']!)),
        GoRoute(
            path: '/facility/:id/active-indents',
            builder: (context, state) =>
                ActiveIndentsPage(facilityId: state.pathParameters['id']!)),
        GoRoute(
            path: '/facility/:id/logging',
            builder: (context, state) =>
                DailyLoggingPage(facilityId: state.pathParameters['id']!)),
        GoRoute(
            path: '/facility/:id/alerts',
            builder: (context, state) =>
                AlertsPage(facilityId: state.pathParameters['id']!)),
        GoRoute(
            path: '/facility/:id/chat',
            builder: (context, state) => AIChatPage(
                facilityId: state.pathParameters['id']!, role: 'facility')),
        GoRoute(
            path: '/facility/:id/help',
            builder: (context, state) => HelpPage(role: 'facility')),
      ],
    ),
    ShellRoute(
      navigatorKey: _adminShellNavigatorKey,
      builder: (context, state, child) {
        return SidebarLayout(role: 'admin', child: child);
      },
      routes: [
        GoRoute(
            path: '/admin/overview',
            builder: (context, state) => const AdminOverview()),
        GoRoute(
            path: '/admin/approvals',
            builder: (context, state) => const AdminIndentApprovalPage()),
        GoRoute(
            path: '/admin/supply-status',
            builder: (context, state) => const AdminIndentStatusPage()),
        GoRoute(
            path: '/admin/routing',
            builder: (context, state) => const RouteOptimizationMap()),
        GoRoute(
            path: '/admin/chat',
            builder: (context, state) => const AIChatPage(role: 'admin')),
        GoRoute(
            path: '/admin/help',
            builder: (context, state) => const HelpPage(role: 'admin')),
      ],
    ),
  ],
);

class AppScrollBehavior extends MaterialScrollBehavior {
  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.stylus,
        PointerDeviceKind.trackpad,
      };
}

class MediFlowApp extends ConsumerWidget {
  const MediFlowApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeProvider);
    return MaterialApp.router(
      title: 'MediFlow',
      debugShowCheckedModeBanner: false,
      scrollBehavior: AppScrollBehavior(),
      themeMode: themeMode,
      theme: _buildTheme(Brightness.light),
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,        scaffoldBackgroundColor: MediColors.bg,
        colorScheme: ColorScheme.dark(
          surface: MediColors.surface,
          primary: MediColors.primary,
          secondary: MediColors.cyan,
          error: MediColors.error,
          onSurface: MediColors.textPrimary,
          onPrimary: Colors.white,
          outline: MediColors.border,
        ),
        textTheme: GoogleFonts.interTextTheme(
          ThemeData.dark().textTheme,
        ),
        cardTheme: CardThemeData(
          color: MediColors.surface,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: MediColors.border),
          ),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          centerTitle: false,
          titleTextStyle: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: MediColors.textPrimary,
          ),
          iconTheme: IconThemeData(color: MediColors.textSecondary),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: MediColors.surfaceLight,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: MediColors.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: MediColors.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: MediColors.primary, width: 2),
          ),
          labelStyle: const TextStyle(color: MediColors.textSecondary),
          hintStyle: const TextStyle(color: MediColors.textMuted),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: MediColors.primary,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            textStyle:
                const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: MediColors.primary,
            side: const BorderSide(color: MediColors.border),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        dividerTheme:
            const DividerThemeData(color: MediColors.border, thickness: 1),
        snackBarTheme: SnackBarThemeData(
          backgroundColor: MediColors.surfaceLight,
          contentTextStyle: const TextStyle(color: MediColors.textPrimary),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          behavior: SnackBarBehavior.floating,
        ),
        popupMenuTheme: PopupMenuThemeData(
          color: MediColors.surfaceLight,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: MediColors.border),
          ),
        ),
        dialogTheme: DialogThemeData(
          backgroundColor: MediColors.surface,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          titleTextStyle: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: MediColors.textPrimary),
        ),
        tabBarTheme: TabBarThemeData(
          labelColor: MediColors.primary,
          unselectedLabelColor: MediColors.textMuted,
          indicatorColor: MediColors.primary,
          dividerColor: MediColors.border,
        ),
        dataTableTheme: DataTableThemeData(
          headingTextStyle: const TextStyle(
              fontWeight: FontWeight.w600,
              color: MediColors.textSecondary,
              fontSize: 13),
          dataTextStyle:
              const TextStyle(color: MediColors.textPrimary, fontSize: 13),
          headingRowColor: WidgetStateProperty.all(MediColors.surfaceLight),
          dataRowColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.hovered)) {
              return MediColors.surfaceHover;
            }
            return Colors.transparent;
          }),
          dividerThickness: 1,
          decoration: const BoxDecoration(
border: Border(
                  bottom: BorderSide(color: MediColors.border, width: 0.5))),
        ),
      ),
      routerConfig: _router,
    );
  }

  ThemeData _buildTheme(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final bg = isDark ? MediColors.bg : MediColorsLight.bg;
    final surface = isDark ? MediColors.surface : MediColorsLight.surface;
    final surfaceLight =
        isDark ? MediColors.surfaceLight : MediColorsLight.surfaceLight;
    final surfaceHover =
        isDark ? MediColors.surfaceHover : MediColorsLight.surfaceHover;
    final border = isDark ? MediColors.border : MediColorsLight.border;
    final textPrimary =
        isDark ? MediColors.textPrimary : MediColorsLight.textPrimary;
    final textSecondary =
        isDark ? MediColors.textSecondary : MediColorsLight.textSecondary;
    final textMuted = isDark ? MediColors.textMuted : MediColorsLight.textMuted;
    final primary = isDark ? MediColors.primary : MediColorsLight.primary;
    final error = isDark ? MediColors.error : MediColorsLight.error;

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: bg,
      colorScheme: isDark
          ? ColorScheme.dark(
              surface: surface,
              primary: primary,
              secondary: MediColors.cyan,
              error: error,
              onSurface: textPrimary,
              onPrimary: Colors.white,
              outline: border,
            )
          : ColorScheme.light(
              surface: surface,
              primary: primary,
              secondary: MediColorsLight.cyan,
              error: error,
              onSurface: textPrimary,
              onPrimary: Colors.white,
              outline: border,
            ),
      textTheme: isDark
          ? GoogleFonts.interTextTheme(ThemeData.dark().textTheme)
          : GoogleFonts.interTextTheme(ThemeData.light().textTheme),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: border),
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: textPrimary,
        ),
        iconTheme: IconThemeData(color: textSecondary),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceLight,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: primary, width: 2),
        ),
        labelStyle: TextStyle(color: textSecondary),
        hintStyle: TextStyle(color: textMuted),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primary,
          side: BorderSide(color: border),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      dividerTheme: DividerThemeData(color: border, thickness: 1),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: surfaceLight,
        contentTextStyle: TextStyle(color: textPrimary),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        behavior: SnackBarBehavior.floating,
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: surfaceLight,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: border),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        titleTextStyle: TextStyle(
            fontSize: 18, fontWeight: FontWeight.w700, color: textPrimary),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: primary,
        unselectedLabelColor: textMuted,
        indicatorColor: primary,
        dividerColor: border,
      ),
      dataTableTheme: DataTableThemeData(
        headingTextStyle: TextStyle(
            fontWeight: FontWeight.w600, color: textSecondary, fontSize: 13),
        dataTextStyle: TextStyle(color: textPrimary, fontSize: 13),
        headingRowColor: WidgetStateProperty.all(surfaceLight),
        dataRowColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.hovered)) {
            return surfaceHover;
          }
          return Colors.transparent;
        }),
        dividerThickness: 1,
        decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: border, width: 0.5))),
      ),
    );
  }
}