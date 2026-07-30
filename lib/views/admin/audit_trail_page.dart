import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../../services/firebase_service.dart';
import '../../models/audit_log.dart';
import 'package:med_supply_prototype/constants/colors.dart';

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
          _loadMoreError = 'Failed to load more logs. Please check your connection and try again.';
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

  Widget _buildFilterChips() {
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
                  color: isSelected ? Colors.white : MediColors.textSecondary,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
              selected: isSelected,
              onSelected: (_) => _onFilterChanged(filter),
              backgroundColor: MediColors.surface,
              selectedColor: MediColors.primary,
              checkmarkColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(
                  color: isSelected ? MediColors.primary : MediColors.border,
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
    return Scaffold(
      backgroundColor: MediColors.bg,
      appBar: AppBar(
        backgroundColor: MediColors.surface,
        title: const Text(
          'Audit Trail',
          style: TextStyle(
              color: MediColors.textPrimary, fontWeight: FontWeight.bold),
        ),
        elevation: 1,
        shadowColor: Colors.black12,
        iconTheme: const IconThemeData(color: MediColors.textPrimary),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildFilterChips(),
          Expanded(
            child: _errorMessage != null
                // Replaced raw exception text with a friendly message and Retry button
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
<<<<<<< HEAD
                      child: Text(
                        'Error loading logs:\n$_errorMessage',
                        style: const TextStyle(
                            color: MediColors.error, fontSize: 14),
                        textAlign: TextAlign.center,
=======
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.error_outline, color: MediColors.error, size: 48),
                          const SizedBox(height: 16),
                          const Text(
                            'Failed to load audit logs.\nPlease check your connection and try again.',
                            style: TextStyle(color: MediColors.textSecondary, fontSize: 16),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 24),
                          ElevatedButton.icon(
                            onPressed: _loadInitialData,
                            icon: const Icon(Icons.refresh),
                            label: const Text('Retry'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: MediColors.primary,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ],
>>>>>>> 967456f (fix(audit): show inline error and retry button for load more failures instead of silent infinite spinner)
                      ),
                    ),
                  )
                : _logs.isEmpty && !_isLoading
                    ? const Center(
                        child: Text(
                          'No audit logs found.',
                          style: TextStyle(
                              color: MediColors.textSecondary, fontSize: 16),
                        ),
                      )
                    : ListView.separated(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(24),
                        itemCount: _logs.length + (_hasMore ? 1 : 0),
                        separatorBuilder: (context, index) => const SizedBox(height: 12),
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
                                        style: const TextStyle(color: MediColors.error, fontSize: 14),
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
                                        icon: const Icon(Icons.refresh, size: 18),
                                        label: const Text('Retry'),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: MediColors.primary,
                                          foregroundColor: Colors.white,
                                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }
                            if (_isLoading) {
                              return const Center(
                                child: Padding(
                                  padding: EdgeInsets.all(16.0),
                                  child: CircularProgressIndicator(color: MediColors.primary),
                                ),
                              );
                            }
                            return const SizedBox.shrink();
                          }
                          final log = _logs[index];
                          return _buildLogCard(log);
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogCard(AuditLog log) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: MediColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MediColors.border),
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
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: MediColors.primary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                DateFormat('MMM dd, yyyy - HH:mm').format(log.timestamp),
                style: const TextStyle(
                  fontSize: 12,
                  color: MediColors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          RichText(
            text: TextSpan(
              style:
                  const TextStyle(fontSize: 14, color: MediColors.textPrimary),
              children: [
                const TextSpan(
                    text: 'Admin ID: ',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                TextSpan(text: '${log.adminId}\n'),
                const TextSpan(
                    text: 'Resource: ',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                TextSpan(text: '${log.resourceType} (${log.resourceId})\n'),
                const TextSpan(
                    text: 'Status: ',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                TextSpan(text: log.status),
              ],
            ),
          ),
          if (log.metadata != null && log.metadata!.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Text(
              'Details:',
              style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  color: MediColors.textPrimary),
            ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: MediColors.bg,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                log.metadata.toString(),
                style: const TextStyle(
                    fontSize: 12,
                    color: MediColors.textSecondary,
                    fontFamily: 'monospace'),
              ),
            ),
          ]
        ],
      ),
    );
  }
}
