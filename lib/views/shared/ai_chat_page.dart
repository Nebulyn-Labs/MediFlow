import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/ai_service.dart';
import '../../services/firebase_service.dart';
import 'package:med_supply_prototype/constants/colors.dart';

class AIChatPage extends ConsumerStatefulWidget {
  final String? facilityId;
  final String role;
  const AIChatPage({super.key, this.facilityId, required this.role});

  @override
  ConsumerState<AIChatPage> createState() => _AIChatPageState();
}

class _AIChatPageState extends ConsumerState<AIChatPage> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<Map<String, String>> _messages = [];
  bool _isTyping = false;
  Map<String, dynamic> _activeContext = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadContext());
  }

  Future<void> _loadContext() async {
    if (widget.facilityId != null) {
      final firebase = ref.read(firebaseServiceProvider);
      try {
        final inventory = await firebase.getInventoryOnce(widget.facilityId!);
        final logs = await firebase.getRecentLogs(widget.facilityId!, days: 60);
        if (mounted) {
          setState(() {
            _activeContext = {
              "system_state": "LIVE",
              "data_sources": ["Firestore", "Local Logs"],
              "current_inventory": inventory.map((i) => i.toMap()).toList(),
              "historical_data": logs.map((l) => l.toMap()).toList(),
            };
          });
        }
      } catch (e) {
        debugPrint('Error loading context: $e');
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    _controller.clear();

    setState(() {
      _messages.add({'role': 'user', 'content': text});
      _isTyping = true;
    });
    _scrollToBottom();

    try {
      final response = await ref.read(aiServiceProvider).getChatResponse(
            query: text,
            context: _activeContext,
            role: widget.role,
            history: _messages.length > 10
                ? _messages.sublist(_messages.length - 10)
                : _messages,
          );
      if (mounted) {
        setState(() {
          _messages.add({'role': 'ai', 'content': response});
          _isTyping = false;
        });
        _scrollToBottom();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _messages.add({
            'role': 'ai',
            'content': 'I encountered an error accessing the system: $e'
          });
          _isTyping = false;
        });
        _scrollToBottom();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MediColors.bg,
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                  gradient: MediColors.primaryGradient,
                  borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.smart_toy_rounded,
                  color: Colors.white, size: 18),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('MediFlow AI',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: MediColors.textPrimary)),
                const Text(
                  'gemini-flash-lite-latest',
                  style: TextStyle(fontSize: 11, color: MediColors.textMuted),
                ),
              ],
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: _messages.isEmpty
                ? _buildEmptyState()
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(24),
                    itemCount: _messages.length + (_isTyping ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index == _messages.length && _isTyping) {
                        return _buildTypingIndicator();
                      }
                      final msg = _messages[index];
                      return _buildBubble(msg['role']!, msg['content']!);
                    },
                  ),
          ),

          // Input bar
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: MediColors.surface,
              border: Border(top: BorderSide(color: MediColors.border)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    style: const TextStyle(color: MediColors.textPrimary),
                    decoration: InputDecoration(
                      hintText: 'Ask about inventory, forecasts, alerts...',
                      filled: true,
                      fillColor: MediColors.surfaceLight,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 14),
                    ),
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  decoration: BoxDecoration(
                      gradient: MediColors.primaryGradient,
                      borderRadius: BorderRadius.circular(14)),
                  child: IconButton(
                    onPressed: _isTyping ? null : _sendMessage,
                    icon: const Icon(Icons.send_rounded,
                        color: Colors.white, size: 20),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.0, end: 1.0),
          duration: const Duration(milliseconds: 450),
          curve: Curves.easeOut,
          builder: (context, value, child) {
            return Opacity(
              opacity: value,
              child: Transform.translate(
                offset: Offset(0, (1 - value) * 16),
                child: child,
              ),
            );
          },
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: MediColors.primarySubtle,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Icon(Icons.smart_toy_rounded,
                    size: 52, color: MediColors.primary),
              ),
              const SizedBox(height: 24),
              Text('MediFlow AI Assistant',
                  style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: MediColors.textPrimary)),
              const SizedBox(height: 8),
              Text(
                'Ask MediFlow AI about inventory, medicine availability, '
                'stock insights, expiry risks, or healthcare logistics.',
                textAlign: TextAlign.center,
                style: TextStyle(color: MediColors.textSecondary),
              ),
              const SizedBox(height: 32),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                alignment: WrapAlignment.center,
                children: [
                  _buildSuggestion('Which medicines are expiring soon?'),
                  _buildSuggestion('Show low stock medicines.'),
                  _buildSuggestion('Explain inventory trends.'),
                  _buildSuggestion('How can I improve stock distribution?'),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSuggestion(String text) {
    return OutlinedButton(
      onPressed: () {
        _controller.text = text;
        _sendMessage();
      },
      style: OutlinedButton.styleFrom(
        foregroundColor: MediColors.primary,
        side: BorderSide(color: MediColors.border),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: Text(text, style: const TextStyle(fontSize: 13)),
    );
  }

  Widget _buildBubble(String role, String text) {
    final isUser = role == 'user';
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        constraints:
            BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.6),
        decoration: BoxDecoration(
          gradient: isUser ? MediColors.primaryGradient : null,
          color: isUser ? null : MediColors.surface,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft:
                isUser ? const Radius.circular(18) : const Radius.circular(4),
            bottomRight:
                isUser ? const Radius.circular(4) : const Radius.circular(18),
          ),
          border: isUser ? null : Border.all(color: MediColors.border),
        ),
        child: SelectableText(
          text,
          style: TextStyle(
            color: isUser ? Colors.white : MediColors.textPrimary,
            fontSize: 14,
            height: 1.5,
          ),
        ),
      ),
    );
  }

  Widget _buildTypingIndicator() {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: BoxDecoration(
          color: MediColors.surface,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(18),
            topRight: Radius.circular(18),
            bottomRight: Radius.circular(18),
            bottomLeft: Radius.circular(4),
          ),
          border: Border.all(color: MediColors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(
              3,
              (i) => Padding(
                    padding: EdgeInsets.only(right: i < 2 ? 6 : 0),
                    child: _BouncingDot(delay: i * 150),
                  )),
        ),
      ),
    );
  }
}

class _BouncingDot extends StatefulWidget {
  final int delay;
  const _BouncingDot({this.delay = 0});

  @override
  State<_BouncingDot> createState() => _BouncingDotState();
}

class _BouncingDotState extends State<_BouncingDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
        duration: const Duration(milliseconds: 600), vsync: this);
    _animation = Tween(begin: 0.0, end: -6.0)
        .animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
    Future.delayed(Duration(milliseconds: widget.delay), () {
      if (mounted) _controller.repeat(reverse: true);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) => Transform.translate(
        offset: Offset(0, _animation.value),
        child: Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
                color: MediColors.primary, shape: BoxShape.circle)),
      ),
    );
  }
}
