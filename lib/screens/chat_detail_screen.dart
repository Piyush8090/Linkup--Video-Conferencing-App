import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ChatDetailScreen extends StatefulWidget {
  final String chatId;
  final String otherUserId;
  final String otherUserName;
  final String? otherUserAvatar;
  final String myId;
  final String myName;
  final String? myAvatar;

  const ChatDetailScreen({
    super.key,
    required this.chatId,
    required this.otherUserId,
    required this.otherUserName,
    this.otherUserAvatar,
    required this.myId,
    required this.myName,
    this.myAvatar,
  });

  @override
  State<ChatDetailScreen> createState() => _ChatDetailScreenState();
}

class _ChatDetailScreenState extends State<ChatDetailScreen> {
  final supabase = Supabase.instance.client;
  final TextEditingController _msgController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();

  List<Map<String, dynamic>> _messages = [];
  RealtimeChannel? _msgChannel;
  bool _isLoading = true;
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    _loadMessages();
    _subscribeToMessages();
  }

  Future<void> _loadMessages() async {
    try {
      final msgs = await supabase
          .from('chat_messages')
          .select()
          .eq('chat_id', widget.chatId)
          .order('created_at', ascending: true);
      setState(() {
        _messages = List<Map<String, dynamic>>.from(msgs);
        _isLoading = false;
      });
      _scrollToBottom();
    } catch (e) {
      debugPrint('Load messages error: $e');
      setState(() => _isLoading = false);
    }
  }

  void _subscribeToMessages() {
    _msgChannel = supabase
        .channel('chat_detail_${widget.chatId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'chat_messages',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'chat_id', value: widget.chatId),
          callback: (payload) {
            final newMsg = payload.newRecord;
            final isDuplicate = _messages.any((m) => m['id'] != null && m['id'] == newMsg['id']);
            if (!isDuplicate) {
              setState(() => _messages.add(newMsg));
              _scrollToBottom();
            } else {
              setState(() {
                final idx = _messages.indexWhere((m) => m['id'] == newMsg['id']);
                if (idx != -1) _messages[idx] = newMsg;
              });
            }
          },
        ).subscribe();
  }

  Future<void> _sendMessage() async {
    final text = _msgController.text.trim();
    if (text.isEmpty || _isSending) return;
    _msgController.clear();
    setState(() => _isSending = true);

    final optimistic = {
      'id': null, 'chat_id': widget.chatId, 'sender_id': widget.myId,
      'sender_name': widget.myName, 'sender_avatar': widget.myAvatar,
      'message': text, 'created_at': DateTime.now().toIso8601String(), '_optimistic': true,
    };
    setState(() => _messages.add(optimistic));
    _scrollToBottom();

    try {
      final saved = await supabase.from('chat_messages').insert({
        'chat_id': widget.chatId, 'sender_id': widget.myId,
        'sender_name': widget.myName, 'sender_avatar': widget.myAvatar,
        'message': text, 'created_at': DateTime.now().toIso8601String(),
      }).select().single();

      setState(() {
        final idx = _messages.indexWhere((m) => m['_optimistic'] == true && m['message'] == text);
        if (idx != -1) _messages[idx] = saved;
      });

      await supabase.from('chats').update({'last_message': text, 'last_message_at': DateTime.now().toIso8601String()}).eq('id', widget.chatId);
    } catch (e) {
      debugPrint('Send message error: $e');
      setState(() => _messages.removeWhere((m) => m['_optimistic'] == true && m['message'] == text));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to send message. Please try again.'), backgroundColor: Colors.red),
        );
      }
    }
    setState(() => _isSending = false);
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  String _formatTime(dynamic dateStr) {
    if (dateStr == null) return '';
    final dt = DateTime.tryParse(dateStr.toString())?.toLocal();
    if (dt == null) return '';
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  String _formatDateHeader(dynamic dateStr) {
    if (dateStr == null) return '';
    final dt = DateTime.tryParse(dateStr.toString())?.toLocal();
    if (dt == null) return '';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final msgDay = DateTime(dt.year, dt.month, dt.day);
    final diff = today.difference(msgDay).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    const months = ['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${dt.day} ${months[dt.month]}';
  }

  bool _shouldShowDateHeader(int index) {
    if (index == 0) return true;
    final curr = DateTime.tryParse(_messages[index]['created_at']?.toString() ?? '');
    final prev = DateTime.tryParse(_messages[index - 1]['created_at']?.toString() ?? '');
    if (curr == null || prev == null) return false;
    return curr.day != prev.day || curr.month != prev.month || curr.year != prev.year;
  }

  @override
  void dispose() {
    _msgChannel?.unsubscribe();
    _msgController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFF),
      appBar: _buildAppBar(),
      body: Column(
        children: [
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: Color(0xFF2563EB)))
                : _messages.isEmpty
                    ? _buildEmptyState()
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        itemCount: _messages.length,
                        itemBuilder: (_, i) {
                          final msg = _messages[i];
                          final isMe = msg['sender_id'] == widget.myId;
                          final showDate = _shouldShowDateHeader(i);
                          final showSenderInfo = i == 0 || _messages[i - 1]['sender_id'] != msg['sender_id'];
                          return Column(
                            children: [
                              if (showDate) _buildDateHeader(msg['created_at']),
                              _buildMessageBubble(msg, isMe, showSenderInfo),
                            ],
                          );
                        },
                      ),
          ),
          _buildInputBar(),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Color(0xFF0F172A), size: 20),
        onPressed: () => Navigator.pop(context),
      ),
      title: Row(
        children: [
          Hero(
            tag: 'avatar_${widget.otherUserId}',
            child: CircleAvatar(
              radius: 19,
              backgroundColor: const Color(0xFF2563EB).withOpacity(0.15),
              backgroundImage: widget.otherUserAvatar != null ? NetworkImage(widget.otherUserAvatar!) : null,
              child: widget.otherUserAvatar == null
                  ? Text(widget.otherUserName[0].toUpperCase(),
                      style: const TextStyle(color: Color(0xFF2563EB), fontWeight: FontWeight.bold, fontSize: 14))
                  : null,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(widget.otherUserName,
                style: const TextStyle(color: Color(0xFF0F172A), fontSize: 16, fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(height: 1, color: const Color(0xFFE2E8F0)),
      ),
    );
  }

  Widget _buildDateHeader(dynamic dateStr) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        children: [
          const Expanded(child: Divider(color: Color(0xFFE2E8F0))),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 12),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(20)),
            child: Text(_formatDateHeader(dateStr), style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11, fontWeight: FontWeight.w500)),
          ),
          const Expanded(child: Divider(color: Color(0xFFE2E8F0))),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(Map<String, dynamic> msg, bool isMe, bool showSenderInfo) {
    final isOptimistic = msg['_optimistic'] == true;
    final time = _formatTime(msg['created_at']);

    return Padding(
      padding: EdgeInsets.only(bottom: 2, top: showSenderInfo ? 8 : 2),
      child: Row(
        mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMe)
            SizedBox(
              width: 32,
              child: showSenderInfo
                  ? CircleAvatar(
                      radius: 14,
                      backgroundColor: const Color(0xFF2563EB).withOpacity(0.15),
                      backgroundImage: widget.otherUserAvatar != null ? NetworkImage(widget.otherUserAvatar!) : null,
                      child: widget.otherUserAvatar == null
                          ? Text(widget.otherUserName[0].toUpperCase(),
                              style: const TextStyle(color: Color(0xFF2563EB), fontSize: 11, fontWeight: FontWeight.bold))
                          : null,
                    )
                  : null,
            ),
          if (!isMe) const SizedBox(width: 6),
          Column(
            crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              Container(
                constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.65),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: isMe ? const Color(0xFF2563EB) : Colors.white,
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(18),
                    topRight: const Radius.circular(18),
                    bottomLeft: Radius.circular(isMe ? 18 : 4),
                    bottomRight: Radius.circular(isMe ? 4 : 18),
                  ),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 6, offset: const Offset(0, 2))],
                ),
                child: Text(
                  msg['message'] ?? '',
                  style: TextStyle(color: isMe ? Colors.white : const Color(0xFF0F172A), fontSize: 14, height: 1.4),
                ),
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(time, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 10)),
                  if (isMe) ...[
                    const SizedBox(width: 4),
                    isOptimistic
                        ? const SizedBox(width: 10, height: 10, child: CircularProgressIndicator(strokeWidth: 1.5, color: Color(0xFF94A3B8)))
                        : const Icon(Icons.done_all_rounded, size: 14, color: Color(0xFF2563EB)),
                  ],
                ],
              ),
            ],
          ),
          if (isMe) const SizedBox(width: 6),
        ],
      ),
    );
  }

  Widget _buildInputBar() {
    return Container(
      padding: EdgeInsets.fromLTRB(12, 10, 12, MediaQuery.of(context).padding.bottom + 10),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 10, offset: const Offset(0, -3))],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: TextField(
                controller: _msgController,
                focusNode: _focusNode,
                maxLines: 4,
                minLines: 1,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _sendMessage(),
                style: const TextStyle(color: Color(0xFF0F172A), fontSize: 14),
                decoration: const InputDecoration(
                  hintText: 'Message...',
                  hintStyle: TextStyle(color: Color(0xFF94A3B8), fontSize: 14),
                  contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  border: InputBorder.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            child: GestureDetector(
              onTap: _isSending ? null : _sendMessage,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _isSending ? const Color(0xFF2563EB).withOpacity(0.5) : const Color(0xFF2563EB),
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: const Color(0xFF2563EB).withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 3))],
                ),
                child: _isSending
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.send_rounded, color: Colors.white, size: 18),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircleAvatar(
            radius: 44,
            backgroundColor: const Color(0xFF2563EB).withOpacity(0.1),
            backgroundImage: widget.otherUserAvatar != null ? NetworkImage(widget.otherUserAvatar!) : null,
            child: widget.otherUserAvatar == null
                ? Text(widget.otherUserName[0].toUpperCase(),
                    style: const TextStyle(color: Color(0xFF2563EB), fontSize: 30, fontWeight: FontWeight.bold))
                : null,
          ),
          const SizedBox(height: 16),
          Text(widget.otherUserName,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
          const SizedBox(height: 8),
          const Text('No messages yet.\nSay hello! 👋',
              style: TextStyle(color: Color(0xFF94A3B8), fontSize: 14), textAlign: TextAlign.center),
        ],
      ),
    );
  }
}