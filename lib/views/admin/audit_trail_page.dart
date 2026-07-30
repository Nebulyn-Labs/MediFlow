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
  ConsumerState<AuditTrailPage> createState() => _AuditTrailPageState();
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

  final List<String> _actionFilters = [
    'All',
    'delete_request',
    'delete_facility',
    // add more if needed
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

  Future<void> _loadMoreData() async {
    if (!mounted || _lastDocument == null) return;
    setState(() {
      _isLoading = true;
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
        });
      }
    } catch (e) {
      debugPrint('Failed to load more audit logs: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
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
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Text(
                        'Error loading logs:\n$_errorMessage',
                        style: const TextStyle(
                            color: MediColors.error, fontSize: 14),
                        textAlign: TextAlign.center,
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
                        separatorBuilder: (context, index) =>
                            const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          if (index == _logs.length) {
                            return const Center(
                              child: Padding(
                                padding: EdgeInsets.all(16.0),
                                child: CircularProgressIndicator(
                                    color: MediColors.primary),
                              ),
                            );
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
