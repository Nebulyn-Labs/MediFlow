import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../../services/firebase_service.dart';
import '../../models/audit_log.dart';
import 'package:med_supply_prototype/theme/medi_flow_theme.dart';

class AuditTrailPage extends ConsumerStatefulWidget {
  const AuditTrailPage({super.key});

  @override
  ConsumerState createState() => _AuditTrailPageState();
}

class _AuditTrailPageState extends ConsumerState<AuditTrailPage> {
  static const int _pageSize = 20;
  final ScrollController _scrollController = ScrollController();

  List<AuditLog> _logs = [];
  DocumentSnapshot? _lastDocument;
  bool _isLoading = false;
  bool _hasMore = true;
  String _selectedAction = 'All';
  String? _errorMessage;

  // Added state variable to track load more failures
  String? _loadMoreError;

  final List<String> _actionFilters = [
    'All',
    'delete_request',
    'delete_facility',
  ];

  @override
  void initState() {
    super.initState();
    _loadInitialData();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 200 &&
        !_isLoading &&
        _hasMore) {
      _loadMoreData();
    }
  }

  Future<void> _loadInitialData() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _logs = [];
      _lastDocument = null;
      _hasMore = true;
      _errorMessage = null;
      _loadMoreError = null;
    });

    final firebaseService = ref.read(firebaseServiceProvider);

    try {
      final result = await firebaseService.getPaginatedAuditLogs(
        pageSize: _pageSize,
        actionFilter: _selectedAction,
      );
      if (mounted) {
        setState(() {
          _logs = result.logs;
          _lastDocument = result.lastDocument;
          _hasMore = result.hasMore;
          _isLoading = false;
        });
      }
    } catch (e, st) {
      debugPrint('Failed to load audit logs: $e\n$st');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = e.toString();
        });
      }
    }
  }

  // Updated catch block to stop auto-retrying and store the error message
  Future<void> _loadMoreData() async {
    if (!mounted || _lastDocument == null || _isLoading) return;
    setState(() {
      _isLoading = true;
      _loadMoreError = null;
    });

    final firebaseService = ref.read(firebaseServiceProvider);

    try {
      final result = await firebaseService.getPaginatedAuditLogs(
        pageSize: _pageSize,
        startAfter: _lastDocument,
        actionFilter: _selectedAction,
      );
      if (mounted) {
        setState(() {
          _logs.addAll(result.logs);
          _lastDocument = result.lastDocument;
          _hasMore = result.hasMore;
          _isLoading = false;
          _loadMoreError = null;
        });
      }
    } catch (e) {
      debugPrint('Failed to load more audit logs: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasMore = false; // Stop auto-retrying on scroll
          _loadMoreError =
              'Failed to load more logs. Please check your connection and try again.';
        });
      }
    }
  }

  void _onFilterChanged(String filter) {
    if (_selectedAction == filter) return;
    setState(() {
      _selectedAction = filter;
    });
    _loadInitialData();
  }

  Widget _buildFilterChips(MediFlowTheme colors) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Row(
        children: _actionFilters.map((filter) {
          final isSelected = _selectedAction == filter;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              label: Text(
                filter == 'All'
                    ? 'All Actions'
                    : filter.replaceAll('_', ' ').toUpperCase(),
                style: TextStyle(
                  color: isSelected ? Colors.white : colors.textSecondary,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
              selected: isSelected,
              onSelected: (_) => _onFilterChanged(filter),
              backgroundColor: colors.surface,
              selectedColor: colors.primary,
              checkmarkColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(
                  color: isSelected ? colors.primary : colors.border,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.mediTheme;

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        title: Text(
          'Audit Trail',
          style: TextStyle(
            color: colors.textPrimary,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildFilterChips(colors),
          Expanded(
            child: _errorMessage != null
                // Replaced raw exception text with a friendly message and Retry button
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.error_outline,
                            color: colors.error,
                            size: 48,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Failed to load audit logs.\nPlease check your connection and try again.',
                            style: TextStyle(
                              color: colors.textSecondary,
                              fontSize: 16,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 24),
                          ElevatedButton.icon(
                            onPressed: _loadInitialData,
                            icon: const Icon(Icons.refresh),
                            label: const Text('Retry'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: colors.primary,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : _logs.isEmpty && !_isLoading
                    ? Center(
                        child: Text(
                          'No audit logs found.',
                          style: TextStyle(
                            color: colors.textSecondary,
                            fontSize: 16,
                          ),
                        ),
                      )
                    : ListView.separated(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(24),
                        itemCount: _logs.length +
                            (_hasMore || _loadMoreError != null ? 1 : 0),
                        separatorBuilder: (context, index) =>
                            const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          if (index == _logs.length) {
                            // Updated pagination footer to show inline error and Retry button instead of permanent spinner
                            if (_loadMoreError != null) {
                              return Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(16.0),
                                  child: Column(
                                    children: [
                                      Text(
                                        _loadMoreError!,
                                        style: TextStyle(
                                          color: colors.error,
                                          fontSize: 14,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                      const SizedBox(height: 12),
                                      ElevatedButton.icon(
                                        onPressed: () {
                                          setState(() {
                                            _loadMoreError = null;
                                            _hasMore = true; // Allow retry
                                          });
                                          _loadMoreData();
                                        },
                                        icon:
                                            const Icon(Icons.refresh, size: 18),
                                        label: const Text('Retry'),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: colors.primary,
                                          foregroundColor: Colors.white,
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 24,
                                            vertical: 12,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }
                            if (_isLoading) {
                              return Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(16.0),
                                  child: CircularProgressIndicator(
                                    color: colors.primary,
                                  ),
                                ),
                              );
                            }
                            return const SizedBox.shrink();
                          }
                          final log = _logs[index];
                          return _buildLogCard(log, colors);
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogCard(AuditLog log, MediFlowTheme colors) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  log.action.replaceAll('_', ' ').toUpperCase(),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: colors.primary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                DateFormat('MMM dd, yyyy - HH:mm').format(log.timestamp),
                style: TextStyle(
                  fontSize: 12,
                  color: colors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          RichText(
            text: TextSpan(
              style: TextStyle(
                fontSize: 14,
                color: colors.textPrimary,
              ),
              children: [
                const TextSpan(
                  text: 'Admin ID: ',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                TextSpan(text: '${log.adminId}\n'),
                const TextSpan(
                  text: 'Resource: ',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                TextSpan(text: '${log.resourceType} (${log.resourceId})\n'),
                const TextSpan(
                  text: 'Status: ',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                TextSpan(text: log.status),
              ],
            ),
          ),
          if (log.metadata != null && log.metadata!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Details:',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 14,
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: colors.surfaceLight,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                log.metadata.toString(),
                style: TextStyle(
                  fontSize: 12,
                  color: colors.textSecondary,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
