import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'chat_detail_screen.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => ChatScreenState();
}

class ChatScreenState extends State<ChatScreen> {
  final supabase = Supabase.instance.client;

  List<Map<String, dynamic>> _allChats = [];
  List<Map<String, dynamic>> _filteredChats = [];
  List<Map<String, dynamic>> _allUsers = [];

  String _searchText = '';
  String? _myId;
  String? _myName;
  String? _myAvatar;
  bool _isLoading = true;

  final TextEditingController _searchController = TextEditingController();
  RealtimeChannel? _chatsChannel;

  @override
  void initState() {
    super.initState();
    _loadCurrentUser();
  }

  Future<void> _loadCurrentUser() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    _myId = user.id;

    final profile = await supabase
        .from('profiles')
        .select()
        .eq('id', user.id)
        .maybeSingle();

    _myName = profile?['username'] ?? 'Me';
    _myAvatar = profile?['avatar_url'];

    await _loadChats();
    _subscribeToChats();
  }

  Future<void> _loadChats() async {
    if (_myId == null) return;
    setState(() => _isLoading = true);

    try {
      final chats = await supabase
          .from('chats')
          .select()
          .contains('members', [_myId!])
          .order('last_message_at', ascending: false, nullsFirst: false);

      final enriched = <Map<String, dynamic>>[];
      for (final chat in chats) {
        final members = List<String>.from(chat['members'] ?? []);
        final otherId = members.firstWhere(
          (id) => id != _myId,
          orElse: () => '',
        );

        Map<String, dynamic>? otherProfile;
        if (otherId.isNotEmpty) {
          otherProfile = await supabase
              .from('profiles')
              .select()
              .eq('id', otherId)
              .maybeSingle();
        }

        enriched.add({
          ...chat,
          'other_user_id': otherId,
          'other_user_name': otherProfile?['username'] ?? 'User',
          'other_user_avatar': otherProfile?['avatar_url'],
        });
      }

      setState(() {
        _allChats = enriched;
        _filteredChats = enriched;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Load chats error: $e');
      setState(() => _isLoading = false);
    }
  }

  void _subscribeToChats() {
    if (_myId == null) return;
    _chatsChannel = supabase
        .channel('chats_realtime_$_myId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'chats',
          callback: (_) => _loadChats(),
        )
        .subscribe();
  }

  void _onSearchChanged(String value) {
    setState(() {
      _searchText = value.toLowerCase();
      _filteredChats = _allChats.where((chat) {
        final name = (chat['other_user_name'] ?? '').toString().toLowerCase();
        final lastMsg = (chat['last_message'] ?? '').toString().toLowerCase();
        return name.contains(_searchText) || lastMsg.contains(_searchText);
      }).toList();
    });
  }

  Future<void> _openUserSearch() async {
    try {
      final users = await supabase
          .from('profiles')
          .select()
          .neq('id', _myId!);
      setState(() => _allUsers = List<Map<String, dynamic>>.from(users));
    } catch (e) {
      debugPrint('User search error: $e');
    }

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _buildUserSearchSheet(),
    );
  }

  Widget _buildUserSearchSheet() {
    final searchCtrl = TextEditingController();
    List<Map<String, dynamic>> filtered = List.from(_allUsers);

    return StatefulBuilder(
      builder: (ctx, setSheetState) => Container(
        height: MediaQuery.of(context).size.height * 0.75,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.black12,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'New Message',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: searchCtrl,
                autofocus: true,
                onChanged: (v) {
                  setSheetState(() {
                    filtered = _allUsers
                        .where((u) => (u['username'] ?? '')
                            .toString()
                            .toLowerCase()
                            .contains(v.toLowerCase()))
                        .toList();
                  });
                },
                decoration: InputDecoration(
                  hintText: 'Search people...',
                  prefixIcon: const Icon(Icons.search, color: Color(0xFF94A3B8)),
                  filled: true,
                  fillColor: const Color(0xFFF1F5F9),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                ),
              ),
            ),
            const SizedBox(height: 8),
            const Divider(height: 1),
            Expanded(
              child: filtered.isEmpty
                  ? const Center(
                      child: Text('No users found',
                          style: TextStyle(color: Colors.black38)))
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: filtered.length,
                      itemBuilder: (_, i) {
                        final user = filtered[i];
                        return ListTile(
                          leading: CircleAvatar(
                            radius: 22,
                            backgroundColor:
                                const Color(0xFF2563EB).withOpacity(0.15),
                            backgroundImage: user['avatar_url'] != null
                                ? NetworkImage(user['avatar_url'])
                                : null,
                            child: user['avatar_url'] == null
                                ? Text(
                                    (user['username'] ?? 'U')[0].toUpperCase(),
                                    style: const TextStyle(
                                      color: Color(0xFF2563EB),
                                      fontWeight: FontWeight.bold,
                                    ),
                                  )
                                : null,
                          ),
                          title: Text(
                            user['username'] ?? 'User',
                            style: const TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 15),
                          ),
                          subtitle: Text(
                            user['email'] ?? '',
                            style: const TextStyle(
                                color: Colors.black45, fontSize: 12),
                          ),
                          onTap: () async {
                            Navigator.pop(ctx);
                            await _startOrOpenChat(user);
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _startOrOpenChat(Map<String, dynamic> otherUser) async {
    final otherId = otherUser['id'] as String;

    final existing = _allChats.firstWhere(
      (c) => c['other_user_id'] == otherId,
      orElse: () => {},
    );

    if (existing.isNotEmpty) {
      _openChat(existing);
      return;
    }

    try {
      final newChat = await supabase.from('chats').insert({
        'members': [_myId, otherId],
        'title': otherUser['username'],
        'created_at': DateTime.now().toIso8601String(),
      }).select().single();

      final enriched = {
        ...newChat,
        'other_user_id': otherId,
        'other_user_name': otherUser['username'] ?? 'User',
        'other_user_avatar': otherUser['avatar_url'],
      };

      _openChat(enriched);
      await _loadChats();
    } catch (e) {
      debugPrint('Create chat error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Failed to start chat. Please try again.')),
        );
      }
    }
  }

  void _openChat(Map<String, dynamic> chat) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatDetailScreen(
          chatId: chat['id'],
          otherUserId: chat['other_user_id'] ?? '',
          otherUserName: chat['other_user_name'] ?? 'User',
          otherUserAvatar: chat['other_user_avatar'],
          myId: _myId!,
          myName: _myName ?? 'Me',
          myAvatar: _myAvatar,
        ),
      ),
    ).then((_) => _loadChats());
  }

  String _formatTime(dynamic dateStr) {
    if (dateStr == null) return '';
    final dt = DateTime.tryParse(dateStr.toString())?.toLocal();
    if (dt == null) return '';

    final now = DateTime.now();
    final diff = now.difference(dt);

    if (diff.inDays == 0) {
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } else if (diff.inDays == 1) {
      return 'Yesterday';
    } else if (diff.inDays < 7) {
      const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      return days[dt.weekday - 1];
    } else {
      return '${dt.day}/${dt.month}';
    }
  }

  @override
  void dispose() {
    _chatsChannel?.unsubscribe();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFF),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Messages',
          style: TextStyle(
            color: Color(0xFF0F172A),
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          IconButton(
            icon: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: const Color(0xFF2563EB).withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.edit_outlined,
                  color: Color(0xFF2563EB), size: 18),
            ),
            onPressed: _openUserSearch,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          // Search bar
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              decoration: InputDecoration(
                hintText: 'Search messages...',
                hintStyle:
                    const TextStyle(color: Color(0xFF94A3B8), fontSize: 14),
                prefixIcon: const Icon(Icons.search,
                    color: Color(0xFF94A3B8), size: 20),
                suffixIcon: _searchText.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close,
                            color: Color(0xFF94A3B8), size: 18),
                        onPressed: () {
                          _searchController.clear();
                          _onSearchChanged('');
                        },
                      )
                    : null,
                filled: true,
                fillColor: const Color(0xFFF1F5F9),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 11),
              ),
            ),
          ),

          // Chat list
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(
                        color: Color(0xFF2563EB)))
                : _filteredChats.isEmpty
                    ? _buildEmptyState()
                    : RefreshIndicator(
                        onRefresh: _loadChats,
                        color: const Color(0xFF2563EB),
                        child: ListView.separated(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          itemCount: _filteredChats.length,
                          separatorBuilder: (_, __) => const Divider(
                            height: 1,
                            indent: 76,
                            endIndent: 16,
                            color: Color(0xFFF1F5F9),
                          ),
                          itemBuilder: (_, i) =>
                              _buildChatTile(_filteredChats[i]),
                        ),
                      ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _openUserSearch,
        backgroundColor: const Color(0xFF2563EB),
        child: const Icon(Icons.chat_outlined, color: Colors.white),
      ),
    );
  }

  Widget _buildChatTile(Map<String, dynamic> chat) {
    final name = chat['other_user_name'] ?? 'User';
    final avatar = chat['other_user_avatar'] as String?;
    final lastMsg = chat['last_message'] as String?;
    final time = _formatTime(chat['last_message_at'] ?? chat['created_at']);

    return InkWell(
      onTap: () => _openChat(chat),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            // ✅ Simple avatar — no online dot
            CircleAvatar(
              radius: 26,
              backgroundColor: const Color(0xFF2563EB).withOpacity(0.15),
              backgroundImage: avatar != null ? NetworkImage(avatar) : null,
              child: avatar == null
                  ? Text(
                      name[0].toUpperCase(),
                      style: const TextStyle(
                        color: Color(0xFF2563EB),
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 12),

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      Text(
                        time,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF94A3B8),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    lastMsg ?? 'Start a conversation',
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF94A3B8),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFF2563EB).withOpacity(0.08),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.forum_outlined,
                size: 52, color: Color(0xFF2563EB)),
          ),
          const SizedBox(height: 20),
          const Text(
            'No conversations yet',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Start a new chat by tapping the\nedit icon or the button below',
            style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 28),
          ElevatedButton.icon(
            onPressed: _openUserSearch,
            icon: const Icon(Icons.add_comment_outlined),
            label: const Text('New Message'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2563EB),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(
                  horizontal: 28, vertical: 13),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
              textStyle: const TextStyle(
                  fontWeight: FontWeight.w600, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }
}