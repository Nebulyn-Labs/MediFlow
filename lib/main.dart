import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:med_supply_prototype/theme/medi_flow_theme.dart';
import 'package:med_supply_prototype/views/shared/not_found_page.dart';

import 'services/firebase_setup.dart';
import 'services/user_profile_cache.dart';
import 'views/admin/admin_indent_approval_page.dart';
import 'views/admin/admin_indent_status_page.dart';
// Admin Pages
import 'views/admin/admin_overview.dart';
import 'views/admin/audit_trail_page.dart';
import 'views/admin/route_optimization_map.dart';
import 'views/auth/forgot_password_page.dart';
import 'views/auth/login_screen.dart';
import 'views/auth/role_selection_screen.dart';
import 'views/facility/active_indents_page.dart';
import 'views/facility/ai_forecast_page.dart';
import 'views/facility/daily_logging_page.dart';
import 'views/facility/facility_overview.dart';
import 'views/facility/wastage_report_page.dart';
import 'views/facility/facility_profile_page.dart';
import 'views/facility/alerts_hub_page.dart';
import 'views/shared/ai_chat_page.dart';
import 'views/shared/help_page.dart';
import 'views/shared/sidebar_layout.dart';

final GlobalKey<NavigatorState> _rootNavigatorKey = GlobalKey<NavigatorState>();
final GlobalKey<NavigatorState> _facilityShellNavigatorKey =
    GlobalKey<NavigatorState>();
final GlobalKey<NavigatorState> _adminShellNavigatorKey =
    GlobalKey<NavigatorState>();

void _handleGlobalError(Object error, StackTrace? stack) {
  debugPrint('Global Error Caught: $error');
  if (stack != null) debugPrint(stack.toString());
}

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
    _handleGlobalError(details.exception, details.stack);
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    _handleGlobalError(error, stack);
    return true;
  };
  ErrorWidget.builder = (FlutterErrorDetails details) {
    const mediTheme = MediFlowTheme.dark;

    return Material(
      child: Scaffold(
        backgroundColor: mediTheme.background,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline, size: 64, color: mediTheme.error),
                const SizedBox(height: 16),
                Text(
                  'Something went wrong',
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: mediTheme.textPrimary),
                ),
                const SizedBox(height: 8),
                Text(
                  kDebugMode
                      ? details.exceptionAsString()
                      : 'An unexpected error occurred. Our team has been notified.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: mediTheme.textMuted, fontSize: 13),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () {
                    _router.go('/');
                  },
                  child: const Text('Go Home'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  };
  runApp(const ProviderScope(child: MediFlowApp()));
}

/// Returns `'/'` when an unauthenticated user tries to reach a protected route,
/// redirects based on role/facility for authenticated users, or `null` to allow
/// navigation. Extracted so tests can reuse it without duplicating it.
///
/// For authenticated users, enforces role-based access:
/// - Facility users cannot access `/admin/*` routes
/// - Facility users cannot access `/facility/<other-id>/*` routes
/// - Users with no resolvable role are bounced to `/`
///
/// Role and facility lookups are cached in [profileCache] so Firestore is not
/// queried on every navigation.
final profileCache = UserProfileCache();

Future<String?> authRedirect(BuildContext context, GoRouterState state) async {
  final user = FirebaseAuth.instance.currentUser;
  final uri = state.uri.toString();
  final isAuthRoute = uri == '/' ||
      uri.startsWith('/login') ||
      uri.startsWith('/forgot-password');

  if (user == null) {
    return isAuthRoute ? null : '/';
  }

  if (isAuthRoute) return null;

  final profile = await profileCache.getUserProfile(user.uid);

  if (profile == null) return '/';

  final isAdminRoute = uri.startsWith('/admin');
  final isFacilityRoute = uri.startsWith('/facility/');

  if (isAdminRoute && !profile.isAdmin) {
    if (profile.isFacilityHead && profile.facilityId != null) {
      return '/facility/${profile.facilityId}/overview';
    }
    return '/';
  }

  if (isFacilityRoute && !profile.isFacilityHead) {
    return profile.isAdmin ? '/admin/overview' : '/';
  }

  if (isFacilityRoute && profile.isFacilityHead) {
    final facilityId = state.pathParameters['id'];
    if (facilityId != null && facilityId != profile.facilityId) {
      return '/facility/${profile.facilityId}/overview';
    }
  }

  return null;
}

final _router = GoRouter(
  navigatorKey: _rootNavigatorKey,
  initialLocation: '/',
  errorBuilder: (context, state) => const NotFoundPage(),
  redirect: authRedirect,
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const RoleSelectionScreen(),
    ),
    GoRoute(
      path: '/login/:role',
      builder: (context, state) {
        final role = state.pathParameters['role']!;
        if (!['facility', 'admin'].contains(role)) {
          return const NotFoundPage();
        }
        return LoginScreen(role: role);
      },
    ),
    GoRoute(
      path: '/forgot-password',
      builder: (context, state) => const ForgotPasswordPage(),
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
                AlertsHubPage(facilityId: state.pathParameters['id']!)),
        GoRoute(
            path: '/facility/:id/wastage',
            builder: (context, state) =>
                WastageReportPage(facilityId: state.pathParameters['id']!)),
        GoRoute(
            path: '/facility/:id/chat',
            builder: (context, state) => AIChatPage(
                facilityId: state.pathParameters['id']!, role: 'facility')),
        GoRoute(
            path: '/facility/:id/profile',
            builder: (context, state) =>
                FacilityProfilePage(facilityId: state.pathParameters['id']!)),
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
            path: '/admin/audit',
            builder: (context, state) => const AuditTrailPage()),
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

class MediFlowApp extends StatelessWidget {
  const MediFlowApp({super.key});

  @override
  Widget build(BuildContext context) {
    const mediTheme = MediFlowTheme.dark;

    return MaterialApp.router(
      title: 'MediFlow',
      debugShowCheckedModeBanner: false,
      scrollBehavior: AppScrollBehavior(),
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        extensions: [mediTheme],
        scaffoldBackgroundColor: mediTheme.background,
        colorScheme: ColorScheme.dark(
          surface: mediTheme.surface,
          surfaceContainerHighest: mediTheme.surfaceLight,
          primary: mediTheme.primary,
          secondary: mediTheme.cyan,
          error: mediTheme.error,
          onSurface: mediTheme.textPrimary,
          onSurfaceVariant: mediTheme.textSecondary,
          onPrimary: mediTheme.onAccent,
          outline: mediTheme.border,
          outlineVariant: mediTheme.borderLight,
        ),
        textTheme: GoogleFonts.interTextTheme(
          ThemeData.dark().textTheme,
        ),
        cardTheme: CardThemeData(
          color: mediTheme.surface,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: mediTheme.border),
          ),
        ),
        appBarTheme: AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          centerTitle: false,
          titleTextStyle: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: mediTheme.textPrimary,
          ),
          iconTheme: IconThemeData(color: mediTheme.textSecondary),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: mediTheme.surfaceLight,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: mediTheme.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: mediTheme.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: mediTheme.primary, width: 2),
          ),
          labelStyle: TextStyle(color: mediTheme.textSecondary),
          hintStyle: TextStyle(color: mediTheme.textMuted),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: mediTheme.primary,
            foregroundColor: mediTheme.onAccent,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            textStyle:
                const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: mediTheme.primary,
            side: BorderSide(color: mediTheme.border),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        dividerTheme: DividerThemeData(color: mediTheme.border, thickness: 1),
        snackBarTheme: SnackBarThemeData(
          backgroundColor: mediTheme.surfaceLight,
          contentTextStyle: TextStyle(color: mediTheme.textPrimary),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          behavior: SnackBarBehavior.floating,
        ),
        popupMenuTheme: PopupMenuThemeData(
          color: mediTheme.surfaceLight,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: mediTheme.border),
          ),
        ),
        dialogTheme: DialogThemeData(
          backgroundColor: mediTheme.surface,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          titleTextStyle: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: mediTheme.textPrimary),
        ),
        tabBarTheme: TabBarThemeData(
          labelColor: mediTheme.primary,
          unselectedLabelColor: mediTheme.textMuted,
          indicatorColor: mediTheme.primary,
          dividerColor: mediTheme.border,
        ),
        dataTableTheme: DataTableThemeData(
          headingTextStyle: TextStyle(
              fontWeight: FontWeight.w600,
              color: mediTheme.textSecondary,
              fontSize: 13),
          dataTextStyle: TextStyle(color: mediTheme.textPrimary, fontSize: 13),
          headingRowColor: WidgetStateProperty.all(mediTheme.surfaceLight),
          dataRowColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.hovered)) {
              return mediTheme.surfaceHover;
            }
            return Colors.transparent;
          }),
          dividerThickness: 1,
          decoration: BoxDecoration(
              border: Border(
                  bottom: BorderSide(color: mediTheme.border, width: 0.5))),
        ),
      ),
      routerConfig: _router,
    );
  }
}
