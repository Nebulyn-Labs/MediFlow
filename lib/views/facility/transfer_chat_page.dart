import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/firebase_service.dart';
import '../../models/transfer_thread.dart';
import '../../models/transfer_message.dart';
import '../../models/facility.dart';
import 'package:med_supply_prototype/constants/colors.dart';
import '../../utils/date_formatter.dart';

class TransferChatPage extends ConsumerStatefulWidget {
  final String threadId;
  final String facilityId;

  const TransferChatPage({
    super.key,
    required this.threadId,
    required this.facilityId,
  });

  @override
  ConsumerState<TransferChatPage> createState() => _TransferChatPageState();
}

class _TransferChatPageState extends ConsumerState<TransferChatPage> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  Facility? _otherFacility;

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    _messageController.clear();

    try {
      await ref
          .read(firebaseServiceProvider)
          .sendTransferMessage(widget.threadId, text, widget.facilityId);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to send message: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: StreamBuilder<TransferThread?>(
          stream: ref
              .read(firebaseServiceProvider)
              .streamTransferThread(widget.threadId),
          builder: (context, snapshot) {
            if (!snapshot.hasData || snapshot.data == null) {
              return const Text('Transfer Chat');
            }
            final thread = snapshot.data!;

            // Try fetching the other facility's name if we haven't already
            if (_otherFacility == null) {
              final otherId = thread.donorFacilityId == widget.facilityId
                  ? thread.recipientFacilityId
                  : thread.donorFacilityId;

              ref
                  .read(firebaseServiceProvider)
                  .getFacility(otherId)
                  .then((fac) {
                if (mounted && fac != null) {
                  setState(() => _otherFacility = fac);
                }
              });
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_otherFacility?.name ?? 'Loading facility...',
                    style: const TextStyle(fontSize: 16)),
                Text('${thread.quantity}x ${thread.medicineName}',
                    style:
                        const TextStyle(fontSize: 12, color: Colors.white70)),
              ],
            );
          },
        ),
        backgroundColor: MediColors.primary,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<List<TransferMessage>>(
              stream: ref
                  .read(firebaseServiceProvider)
                  .streamTransferMessages(widget.threadId),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                }

                final messages = snapshot.data ?? [];

                if (messages.isEmpty) {
                  return const Center(
                      child: Text(
                          'No messages yet. Send a message to start coordinating.',
                          style: TextStyle(color: MediColors.textMuted)));
                }

                // Auto-scroll to bottom on new messages
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (_scrollController.hasClients) {
                    _scrollController.animateTo(
                      _scrollController.position.maxScrollExtent,
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOut,
                    );
                  }
                });

                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(16),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final message = messages[index];
                    final isMe = message.senderId == widget.facilityId;

                    return Align(
                      alignment:
                          isMe ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                          color: isMe
                              ? MediColors.primary
                              : MediColors.surfaceLight,
                          borderRadius: BorderRadius.circular(16).copyWith(
                            bottomRight: isMe
                                ? const Radius.circular(0)
                                : const Radius.circular(16),
                            bottomLeft: !isMe
                                ? const Radius.circular(0)
                                : const Radius.circular(16),
                          ),
                          border: isMe
                              ? null
                              : Border.all(color: MediColors.border),
                        ),
                        constraints: BoxConstraints(
                            maxWidth: MediaQuery.of(context).size.width * 0.75),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              message.text,
                              style: TextStyle(
                                color: isMe
                                    ? Colors.white
                                    : MediColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              DateFormatter.formatTime(message.sentAt),
                              style: TextStyle(
                                fontSize: 10,
                                color: isMe
                                    ? Colors.white70
                                    : MediColors.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              color: MediColors.surface,
              border: Border(top: BorderSide(color: MediColors.border)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    decoration: InputDecoration(
                      hintText: 'Type a message...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: MediColors.surfaceLight,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 10),
                    ),
                    maxLines: null,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                const SizedBox(width: 8),
                CircleAvatar(
                  backgroundColor: MediColors.primary,
                  child: IconButton(
                    icon: const Icon(Icons.send, color: Colors.white, size: 20),
                    onPressed: _sendMessage,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
