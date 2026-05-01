import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'meeting_screen.dart';
import 'schedule_screen.dart';
import 'meeting_timeline_screen.dart';
import '../widgets/meeting_card.dart';
import 'waiting_room_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen> {
  final supabase = Supabase.instance.client;

  String username = 'User';
  String? avatarUrl;
  String? userId;
  bool isLoading = true;

  List<Map<String, dynamic>> scheduledMeetings = [];
  List<Map<String, dynamic>> meetingHistory = [];

  List<Map<String, dynamic>> _notifications = [];
  int _unreadCount = 0;
  int _totalMeetingCount = 0;
  RealtimeChannel? _notifChannel;

  final TextEditingController _meetingIdController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();

  String _selectedMeetingType = 'team';

  // Recent meetings — show 5, expandable
  bool _showAllHistory = false;
  static const int _historyPreviewCount = 5;

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  Future<void> _loadUser() async {
    final user = supabase.auth.currentUser;
    if (user != null) {
      final data = await supabase
          .from('profiles')
          .select()
          .eq('id', user.id)
          .maybeSingle();

      setState(() {
        username = data?['username'] ?? 'User';
        avatarUrl = data?['avatar_url'];
        userId = user.id;
        isLoading = false;
      });

      await _loadMeetings();
      _loadNotifications();
      _subscribeToNotifications();
    } else {
      setState(() => isLoading = false);
    }
  }

Future<void> _loadMeetings() async {
  if (userId == null) return;
  try {
    final scheduled = await supabase
        .from('meetings')
        .select()
        .eq('host_id', userId!)
        .eq('is_active', true)
        .not('scheduled_at', 'is', null)
        .gte('scheduled_at',
            DateTime.now().subtract(const Duration(minutes: 15)).toIso8601String())
        .order('scheduled_at', ascending: true);

    final history = await supabase
        .from('meetings')
        .select()
        .eq('host_id', userId!)
        .eq('is_active', false)
        .filter('scheduled_at', 'is', null)
        .order('created_at', ascending: false)
        .limit(5);

    // Total count for stats pill
    final totalCount = await supabase
        .from('meetings')
        .select('id')
        .eq('host_id', userId!)
        .eq('is_active', false)
        .filter('scheduled_at', 'is', null);

    setState(() {
      scheduledMeetings = List<Map<String, dynamic>>.from(scheduled);
      meetingHistory = List<Map<String, dynamic>>.from(history);
      _totalMeetingCount = (totalCount as List).length;
    });
  } catch (e) {
    debugPrint('Load meetings error: $e');
  }
}
  Future<void> _loadNotifications() async {
    if (userId == null) return;
    try {
      final notifs = await supabase
          .from('notifications')
          .select()
          .eq('user_id', userId!)
          .order('created_at', ascending: false)
          .limit(20);

      final list = List<Map<String, dynamic>>.from(notifs);
      if (mounted) {
        setState(() {
          _notifications = list;
          _unreadCount = list.where((n) => n['is_read'] == false).length;
        });
      }
    } catch (e) {
      debugPrint('Load notifications error: $e');
    }
  }

  void _subscribeToNotifications() {
    if (userId == null) return;
    _notifChannel = supabase
        .channel('notifs_$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'notifications',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: userId!,
          ),
          callback: (payload) {
            if (mounted) {
              setState(() {
                _notifications.insert(0, payload.newRecord);
                _unreadCount++;
              });
            }
          },
        )
        .subscribe();
  }

  Future<void> _markAllAsRead() async {
    if (userId == null) return;
    try {
      await supabase
          .from('notifications')
          .update({'is_read': true})
          .eq('user_id', userId!)
          .eq('is_read', false);
      setState(() {
        _notifications = _notifications
            .map((n) => {...n, 'is_read': true})
            .toList();
        _unreadCount = 0;
      });
    } catch (e) {
      debugPrint('Mark read error: $e');
    }
  }

  Future<void> _deleteNotification(String id) async {
    try {
      await supabase.from('notifications').delete().eq('id', id);
      setState(() {
        _notifications.removeWhere((n) => n['id'] == id);
        _unreadCount = _notifications
            .where((n) => n['is_read'] == false)
            .length;
      });
    } catch (e) {
      debugPrint('Delete notif error: $e');
    }
  }

  Future<void> _sendNotification({
    required String toUserId,
    required String title,
    required String body,
    required String type,
  }) async {
    try {
      await supabase.from('notifications').insert({
        'user_id': toUserId,
        'title': title,
        'body': body,
        'type': type,
        'is_read': false,
        'created_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      debugPrint('Notification send failed: $e');
    }
  }

  int _generateUid() => Random().nextInt(900000) + 100000;

  String _generateMeetingCode() {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final rand = Random();
    String p1 = List.generate(
      3,
      (_) => chars[rand.nextInt(chars.length)],
    ).join();
    String p2 = List.generate(
      4,
      (_) => chars[rand.nextInt(chars.length)],
    ).join();
    String p3 = List.generate(
      3,
      (_) => chars[rand.nextInt(chars.length)],
    ).join();
    return '$p1-$p2-$p3';
  }

  bool _isMeetingPrivate = false;

  // ── Clear meeting history ─────────────────────────────────────────────
  Future<void> _clearMeetingHistory() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Clear Meeting History',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: const Text(
          'This will remove all meetings from your history list. Active meetings will not be affected.',
          style: TextStyle(color: Colors.black54),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear All'),
          ),
        ],
      ),
    );

    if (confirm == true && userId != null) {
  try {
    // Sirf recent list se hide karo — DB record intact, history sheet safe
    await supabase
        .from('meetings')
        .update({'show_in_recent': false})
        .eq('host_id', userId!)
        .eq('is_active', false)
        .filter('scheduled_at', 'is', null);
  } catch (e) {
    debugPrint('Clear recent error: $e');
  }
  setState(() => meetingHistory = []);
  if (mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Meeting history cleared.'),
        backgroundColor: Color(0xFF10B981),
        duration: Duration(seconds: 2),
      ),
    );
  }
}
  }

  void _showMeetingTypeSelector() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSheet) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.black12,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'What kind of meeting?',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Features will auto-configure based on your choice.',
                style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
              ),
              const SizedBox(height: 20),
              _meetingTypeCard(
                type: 'class',
                icon: Icons.school_rounded,
                title: 'Class',
                desc:
                    'Attendance ON · Chat moderated · Participants join muted',
                color: const Color(0xFF8B5CF6),
                selected: _selectedMeetingType == 'class',
                onTap: () {
                  setState(() => _selectedMeetingType = 'class');
                  setSheet(() {});
                },
              ),
              const SizedBox(height: 10),
              _meetingTypeCard(
                type: 'team',
                icon: Icons.work_rounded,
                title: 'Team Meeting',
                desc: 'Screen share priority · Open mic · Collaboration mode',
                color: const Color(0xFF2563EB),
                selected: _selectedMeetingType == 'team',
                onTap: () {
                  setState(() => _selectedMeetingType = 'team');
                  setSheet(() {});
                },
              ),
              const SizedBox(height: 10),
              _meetingTypeCard(
                type: 'casual',
                icon: Icons.emoji_emotions_rounded,
                title: 'Casual Chat',
                desc: 'All features unlocked · No restrictions',
                color: const Color(0xFF10B981),
                selected: _selectedMeetingType == 'casual',
                onTap: () {
                  setState(() => _selectedMeetingType = 'casual');
                  setSheet(() {});
                },
              ),
              const SizedBox(height: 24),
              // ─── Privacy toggle ──────────────────────────────────────
              GestureDetector(
                onTap: () {
                  setState(() => _isMeetingPrivate = !_isMeetingPrivate);
                  setSheet(() {});
                },
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _isMeetingPrivate
                          ? const Color(0xFF2563EB).withOpacity(0.4)
                          : const Color(0xFFE2E8F0),
                    ),
                    color: _isMeetingPrivate
                        ? const Color(0xFF2563EB).withOpacity(0.05)
                        : Colors.white,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _isMeetingPrivate
                            ? Icons.lock_rounded
                            : Icons.lock_open_rounded,
                        color: _isMeetingPrivate
                            ? const Color(0xFF2563EB)
                            : const Color(0xFF64748B),
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _isMeetingPrivate
                                  ? 'Private Meeting'
                                  : 'Public Meeting',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                                color: _isMeetingPrivate
                                    ? const Color(0xFF2563EB)
                                    : const Color(0xFF0F172A),
                              ),
                            ),
                            Text(
                              _isMeetingPrivate
                                  ? 'Participants need your approval to join'
                                  : 'Anyone with the ID can join directly',
                              style: const TextStyle(
                                  color: Color(0xFF94A3B8), fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: _isMeetingPrivate,
                        onChanged: (v) {
                          setState(() => _isMeetingPrivate = v);
                          setSheet(() {});
                        },
                        activeColor: const Color(0xFF2563EB),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        _getMeetingTypeConfig(_selectedMeetingType)['color']
                            as Color,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  onPressed: () {
                    Navigator.pop(ctx);
                    _createAndJoinMeeting();
                  },
                  child: const Text('Create Meeting'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _meetingTypeCard({
    required String type,
    required IconData icon,
    required String title,
    required String desc,
    required Color color,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected ? color.withOpacity(0.07) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? color : const Color(0xFFE2E8F0),
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: selected ? color : const Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    desc,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF94A3B8),
                    ),
                  ),
                ],
              ),
            ),
            if (selected)
              Icon(Icons.check_circle_rounded, color: color, size: 20),
          ],
        ),
      ),
    );
  }

  Future<void> _createAndJoinMeeting() async {
    if (userId == null) return;
    final meetingCode = _generateMeetingCode();
    final uid = _generateUid();

    try {
      await supabase.from('meetings').insert({
        'meeting_code': meetingCode,
        'meeting_name': "$username's Meeting",
        'host_id': userId,
        'host_name': username,
        'is_active': true,
        'is_private': _isMeetingPrivate,
        'meeting_type': _selectedMeetingType,
        'created_at': DateTime.now().toIso8601String(),
      });

      await supabase.from('meeting_events').insert({
        'meeting_code': meetingCode,
        'event_type': 'started',
        'actor_name': username,
        'created_at': DateTime.now().toIso8601String(),
      });

      _sendNotification(
        toUserId: userId!,
        title: 'Meeting Started',
        body: 'You started: $meetingCode',
        type: 'meeting',
      );
      if (mounted) _showMeetingCreatedDialog(meetingCode, uid);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to create meeting: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showMeetingCreatedDialog(String meetingCode, int uid) {
    final typeConfig = _getMeetingTypeConfig(_selectedMeetingType);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: (typeConfig['color'] as Color).withOpacity(
                    0.1,
                  ),
                  child: Icon(
                    typeConfig['icon'] as IconData,
                    color: typeConfig['color'] as Color,
                  ),
                ),
                const SizedBox(width: 12),
                const Text(
                  'Meeting Ready!',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: (typeConfig['color'] as Color).withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    typeConfig['icon'] as IconData,
                    size: 13,
                    color: typeConfig['color'] as Color,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    typeConfig['label'] as String,
                    style: TextStyle(
                      color: typeConfig['color'] as Color,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Share this ID with participants to join.',
              style: TextStyle(color: Colors.black54, fontSize: 13),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFF),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: typeConfig['color'] as Color,
                  width: 1.5,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: Text(
                      meetingCode,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2,
                        color: typeConfig['color'] as Color,
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: meetingCode));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Row(
                            children: [
                              Icon(
                                Icons.check_circle,
                                color: Colors.white,
                                size: 16,
                              ),
                              SizedBox(width: 8),
                              Text('Meeting ID copied!'),
                            ],
                          ),
                          backgroundColor: Color(0xFF10B981),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: (typeConfig['color'] as Color).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        Icons.copy,
                        color: typeConfig['color'] as Color,
                        size: 18,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (_selectedMeetingType == 'class') ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF8B5CF6).withOpacity(0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: const Color(0xFF8B5CF6).withOpacity(0.2),
                  ),
                ),
                child: const Row(
                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      size: 14,
                      color: Color(0xFF8B5CF6),
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Class mode: Participants will join muted.',
                        style: TextStyle(
                          fontSize: 11,
                          color: Color(0xFF8B5CF6),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.black45),
            ),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.videocam, size: 18),
            label: const Text('Start Meeting'),
            style: ElevatedButton.styleFrom(
              backgroundColor: typeConfig['color'] as Color,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => MeetingScreen(
                    channelId: meetingCode,
                    userName: username,
                    uid: uid,
                    meetingType: _selectedMeetingType,
                    isHost: true,
                  ),
                ),
              ).then((_) => _loadMeetings());
            },
          ),
        ],
      ),
    );
  }

  Map<String, dynamic> _getMeetingTypeConfig(String type) {
    switch (type) {
      case 'class':
        return {
          'icon': Icons.school_rounded,
          'label': 'Class',
          'color': const Color(0xFF8B5CF6),
        };
      case 'casual':
        return {
          'icon': Icons.emoji_emotions_rounded,
          'label': 'Casual Chat',
          'color': const Color(0xFF10B981),
        };
      default:
        return {
          'icon': Icons.work_rounded,
          'label': 'Team Meeting',
          'color': const Color(0xFF2563EB),
        };
    }
  }

  Future<void> _joinMeeting(String meetingCode, String name) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(color: Color(0xFF2563EB)),
                SizedBox(height: 16),
                Text('Joining meeting...'),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      final meeting = await supabase
          .from('meetings')
          .select()
          .eq('meeting_code', meetingCode.toLowerCase().trim())
          .maybeSingle();

      if (meeting == null) {
        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Row(
                children: [
                  Icon(Icons.error_outline, color: Colors.white, size: 16),
                  SizedBox(width: 8),
                  Text('Meeting not found. Please check the ID.'),
                ],
              ),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      final uid = _generateUid();
      final meetingType = meeting['meeting_type'] ?? 'team';
      final code = meetingCode.toLowerCase().trim();

      // Check karo private hai ya nahi
      final isPrivate = meeting['is_private'] == true;

      if (isPrivate && meeting['host_id'] != userId) {
        if (mounted) Navigator.pop(context); // loading dialog band karo
        await _enterWaitingRoom(
          meetingCode: code,
          name: name,
          uid: uid,
          meetingType: meetingType,
          hostId: meeting['host_id'],
        );
        return;
      }

      final events = await supabase
          .from('meeting_events')
          .select()
          .eq('meeting_code', code)
          .order('created_at', ascending: true);

      final eventList = List<Map<String, dynamic>>.from(events);
      final startedEvent = eventList.firstWhere(
        (e) => e['event_type'] == 'started',
        orElse: () => <String, dynamic>{},
      );

      Duration? meetingDuration;
      if (startedEvent.isNotEmpty) {
        final startTime = DateTime.tryParse(
          startedEvent['created_at']?.toString() ?? '',
        );
        if (startTime != null)
          meetingDuration = DateTime.now().difference(startTime);
      }

      String? meetingDbId = meeting['id']?.toString();
      List<Map<String, dynamic>> recentMessages = [];
      if (meetingDbId != null) {
        try {
          final msgs = await supabase
              .from('messages')
              .select()
              .eq('meeting_id', meetingDbId)
              .order('created_at', ascending: false)
              .limit(3);
          recentMessages = List<Map<String, dynamic>>.from(
            msgs,
          ).reversed.toList();
        } catch (_) {}
      }

      final isScreenSharing = meeting['is_screen_sharing'] == true;
      final currentSpeaker = meeting['current_speaker'] as String?;

      int participantCount = 0;
      try {
        final participants = await supabase
            .from('meeting_participants')
            .select('id')
            .eq('meeting_code', code)
            .filter('left_at', 'is', null);
        participantCount = (participants as List).length;
      } catch (_) {
        participantCount = eventList
            .where((e) => e['event_type'] == 'user_joined')
            .length;
      }

      _sendNotification(
        toUserId: meeting['host_id'],
        title: '$name joined your meeting',
        body: 'Meeting: $meetingCode',
        type: 'meeting',
      );

      if (mounted) {
        Navigator.pop(context);
        if (meetingDuration != null && meetingDuration.inSeconds > 30) {
          _showLateJoinOverlay(
            meetingCode: code,
            name: name,
            uid: uid,
            meetingType: meetingType,
            duration: meetingDuration,
            currentSpeaker: currentSpeaker,
            isScreenSharing: isScreenSharing,
            participantCount: participantCount,
            recentMessages: recentMessages,
          );
        } else {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => MeetingScreen(
                channelId: code,
                userName: name,
                uid: uid,
                meetingType: meetingType,
                isHost: false,
              ),
            ),
          ).then((_) => _loadMeetings());
        }
      }
    } catch (e) {
      debugPrint('Join meeting error: $e');
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Unable to join meeting: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

Future<void> _enterWaitingRoom({
  required String meetingCode,
  required String name,
  required int uid,
  required String meetingType,
  required String hostId,
}) async {
  // Waiting room me insert karo
  try {
    final profile = await supabase
        .from('profiles')
        .select('avatar_url')
        .eq('id', userId!)
        .maybeSingle();

    await supabase.from('waiting_room').insert({
      'meeting_code': meetingCode,
      'user_id': userId,
      'display_name': name,
      'avatar_url': profile?['avatar_url'],
      'agora_uid': uid,
      'status': 'waiting',
      'requested_at': DateTime.now().toIso8601String(),
    });
  } catch (e) {
    debugPrint('Waiting room insert error: $e');
  }

  if (!mounted) return;

  // Waiting room screen pe navigate karo
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => WaitingRoomScreen(
        meetingCode: meetingCode,
        userName: name,
        uid: uid,
        meetingType: meetingType,
        userId: userId!,
      ),
    ),
  ).then((_) => _loadMeetings());
}

  void _showLateJoinOverlay({
    required String meetingCode,
    required String name,
    required int uid,
    required String meetingType,
    required Duration duration,
    String? currentSpeaker,
    required bool isScreenSharing,
    required int participantCount,
    required List<Map<String, dynamic>> recentMessages,
  }) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isDismissible: false,
      isScrollControlled: true,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFF1A1A2E),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: EdgeInsets.fromLTRB(
          24,
          20,
          24,
          MediaQuery.of(ctx).viewInsets.bottom + 32,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF59E0B).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.access_time_rounded,
                    color: Color(0xFFF59E0B),
                    size: 18,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    "You're joining late — here's what happened",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            _lateJoinRow(
              icon: Icons.timer_outlined,
              color: const Color(0xFFA78BFA),
              label: 'Meeting has been running for',
              value: minutes > 0 ? '${minutes}m ${seconds}s' : '${seconds}s',
            ),
            const SizedBox(height: 10),
            _lateJoinRow(
              icon: Icons.mic_rounded,
              color: const Color(0xFF60A5FA),
              label: 'Currently speaking',
              value: currentSpeaker ?? 'No one',
            ),
            const SizedBox(height: 10),
            _lateJoinRow(
              icon: Icons.screen_share_rounded,
              color: const Color(0xFF34D399),
              label: 'Screen sharing',
              value: isScreenSharing ? 'Active' : 'Not active',
              valueColor: isScreenSharing
                  ? const Color(0xFF34D399)
                  : Colors.white60,
            ),
            const SizedBox(height: 10),
            _lateJoinRow(
              icon: Icons.people_rounded,
              color: const Color(0xFFFBBF24),
              label: 'Participants in meeting',
              value: '$participantCount people',
            ),

            if (recentMessages.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Text(
                'Recent messages',
                style: TextStyle(
                  color: Colors.white60,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white12),
                ),
                child: Column(
                  children: recentMessages
                      .map(
                        (msg) => Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${msg['sender_name'] ?? 'User'}: ',
                                style: const TextStyle(
                                  color: Color(0xFF93C5FD),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  msg['text'] ?? '',
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 12,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
            ],

            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white60,
                      side: const BorderSide(color: Colors.white24),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2563EB),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () {
                      Navigator.pop(ctx);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => MeetingScreen(
                            channelId: meetingCode,
                            userName: name,
                            uid: uid,
                            meetingType: meetingType,
                            isHost: false,
                          ),
                        ),
                      ).then((_) => _loadMeetings());
                    },
                    child: const Text('Join Now'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _lateJoinRow({
    required IconData icon,
    required Color color,
    required String label,
    required String value,
    Color? valueColor,
  }) {
    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color, size: 16),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(color: Colors.white60, fontSize: 13),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            color: valueColor ?? Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _notifChannel?.unsubscribe();
    _meetingIdController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadMeetings,
          color: const Color(0xFF2563EB),
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(),
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildQuickActions(),
                      const SizedBox(height: 28),
                      if (scheduledMeetings.isNotEmpty) ...[
                        _buildSectionHeader(
                          icon: Icons.calendar_today,
                          title: 'Upcoming Meetings',
                          color: const Color(0xFFF59E0B),
                        ),
                        const SizedBox(height: 12),
                        ...scheduledMeetings.map(
                          (m) => MeetingCard(
                            title: m['meeting_name'] ?? 'Meeting',
                            time: _formatTime(m['scheduled_at']),
                            date: _formatDate(m['scheduled_at']),
                            host: m['host_name'] ?? username,
                            channelId: m['meeting_code'] ?? '',
                            isScheduled: true,
                            currentUsername: username,
                          ),
                        ),
                        const SizedBox(height: 24),
                      ],
                      _buildRecentMeetingsSection(),
                      const SizedBox(height: 32),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRecentMeetingsSection() {
    final displayList = _showAllHistory
        ? meetingHistory
        : meetingHistory.take(_historyPreviewCount).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _buildSectionHeader(
              icon: Icons.history,
              title: 'Recent Meetings',
              color: const Color(0xFF8B5CF6),
            ),
            const Spacer(),
            if (meetingHistory.isNotEmpty)
              GestureDetector(
                onTap: _clearMeetingHistory,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.red.withOpacity(0.2)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.delete_outline_rounded,
                        color: Colors.red,
                        size: 13,
                      ),
                      SizedBox(width: 4),
                      Text(
                        'Clear',
                        style: TextStyle(
                          color: Colors.red,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (meetingHistory.isEmpty)
          _buildEmptyState()
        else ...[
          // Meeting count badge
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF8B5CF6).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${meetingHistory.length} meeting${meetingHistory.length == 1 ? '' : 's'} total',
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF8B5CF6),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          ...displayList.map((m) => _buildHistoryTile(m)),
          // Show more / Show less
          if (meetingHistory.length > _historyPreviewCount)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: GestureDetector(
                onTap: () => setState(() => _showAllHistory = !_showAllHistory),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: const Color(0xFF8B5CF6).withOpacity(0.3),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        _showAllHistory
                            ? Icons.expand_less_rounded
                            : Icons.expand_more_rounded,
                        color: const Color(0xFF8B5CF6),
                        size: 18,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _showAllHistory
                            ? 'Show less'
                            : 'Show ${meetingHistory.length - _historyPreviewCount} more',
                        style: const TextStyle(
                          color: Color(0xFF8B5CF6),
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ],
    );
  }

  Widget _buildHistoryTile(Map<String, dynamic> m) {
    final typeConfig = _getMeetingTypeConfig(m['meeting_type'] ?? 'team');
    final typeColor = typeConfig['color'] as Color;
    final typeIcon = typeConfig['icon'] as IconData;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => MeetingScreen(
              channelId: m['meeting_code'],
              userName: username,
              uid: _generateUid(),
              meetingType: m['meeting_type'] ?? 'team',
              isHost: m['host_id'] == userId,
            ),
          ),
        ),
        onLongPress: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => MeetingTimelineScreen(
              meetingCode: m['meeting_code'] ?? '',
              meetingName: m['meeting_name'] ?? 'Meeting',
              meetingType: m['meeting_type'],
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              // Type icon
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: typeColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(typeIcon, color: typeColor, size: 20),
              ),
              const SizedBox(width: 12),
              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      m['meeting_name'] ?? 'Meeting',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        const Icon(
                          Icons.access_time_rounded,
                          size: 11,
                          color: Color(0xFF94A3B8),
                        ),
                        const SizedBox(width: 3),
                        Text(
                          _formatDate(m['created_at']),
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF94A3B8),
                          ),
                        ),
                        if (m['duration_minutes'] != null &&
                            m['duration_minutes'] > 0) ...[
                          const Text(
                            ' · ',
                            style: TextStyle(color: Color(0xFF94A3B8)),
                          ),
                          Text(
                            '${m['duration_minutes']} min',
                            style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFF94A3B8),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              // Meeting code pill
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFF),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Text(
                  m['meeting_code'] ?? '',
                  style: const TextStyle(
                    color: Color(0xFF2563EB),
                    fontWeight: FontWeight.w600,
                    fontSize: 10,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              const Icon(
                Icons.chevron_right_rounded,
                size: 16,
                color: Color(0xFFCBD5E1),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final hour = DateTime.now().hour;
    String greeting;
    IconData greetIcon;
    if (hour < 12) {
      greeting = 'Good Morning';
      greetIcon = Icons.wb_sunny_outlined;
    } else if (hour < 17) {
      greeting = 'Good Afternoon';
      greetIcon = Icons.wb_cloudy_outlined;
    } else {
      greeting = 'Good Evening';
      greetIcon = Icons.nights_stay_outlined;
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 28),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF1D4ED8), Color(0xFF3B82F6)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(28),
          bottomRight: Radius.circular(28),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: Colors.white24,
                backgroundImage: avatarUrl != null
                    ? NetworkImage(avatarUrl!)
                    : null,
                child: avatarUrl == null
                    ? Text(
                        username.isNotEmpty ? username[0].toUpperCase() : 'U',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(greetIcon, color: Colors.white70, size: 13),
                        const SizedBox(width: 4),
                        Text(
                          greeting,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isLoading ? '...' : username,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              GestureDetector(
                onTap: _showNotificationsPanel,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white12,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.notifications_outlined,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                    if (_unreadCount > 0)
                      Positioned(
                        top: -4,
                        right: -4,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                          ),
                          constraints: const BoxConstraints(
                            minWidth: 18,
                            minHeight: 18,
                          ),
                          child: Text(
                            _unreadCount > 9 ? '9+' : '$_unreadCount',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          // Live stats bar
          const SizedBox(height: 20),
          Row(
            children: [
              _statPill(
                Icons.videocam_rounded,
                '$_totalMeetingCount',
                'Meetings',
              ),
              const SizedBox(width: 10),
              _statPill(
                Icons.calendar_today_rounded,
                '${scheduledMeetings.length}',
                'Upcoming',
              ),
              const SizedBox(width: 10),
              _statPill(
                Icons.notifications_outlined,
                '${_notifications.where((n) => n['is_read'] == false).length}',
                'Alerts',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statPill(IconData icon, String value, String label) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withOpacity(0.15)),
        ),
        child: Row(
          children: [
            Icon(icon, color: Colors.white70, size: 14),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    label,
                    style: const TextStyle(color: Colors.white60, fontSize: 9),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickActions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Quick Actions',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.bold,
            color: Color(0xFF0F172A),
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: _actionButton(
                icon: Icons.videocam_rounded,
                label: 'New\nMeeting',
                color: const Color(0xFF2563EB),
                onTap: _showMeetingTypeSelector,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _actionButton(
                icon: Icons.login_rounded,
                label: 'Join\nMeeting',
                color: const Color(0xFF10B981),
                onTap: _showJoinMeetingDialog,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _actionButton(
                icon: Icons.calendar_month_rounded,
                label: 'Schedule',
                color: const Color(0xFFF59E0B),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ScheduleScreen()),
                ).then((_) => _loadMeetings()),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _actionButton(
                icon: Icons.history_rounded,
                label: 'History',
                color: const Color(0xFF8B5CF6),
                onTap: _showHistoryBottomSheet,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _actionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.12),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1E293B),
                height: 1.3,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader({
    required IconData icon,
    required String title,
    required Color color,
  }) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color, size: 16),
        ),
        const SizedBox(width: 10),
        Text(
          title,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.bold,
            color: Color(0xFF0F172A),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 36),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Center(
        child: Column(
          children: [
            Icon(Icons.video_call_outlined, size: 36, color: Colors.black38),
            SizedBox(height: 14),
            Text(
              'No meetings yet',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Colors.black54,
              ),
            ),
            SizedBox(height: 4),
            Text(
              'Start a new meeting to get going!',
              style: TextStyle(color: Colors.black38, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  void _showNotificationsPanel() async {
    if (_unreadCount > 0) await _markAllAsRead();
    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSheetState) => Container(
          height: MediaQuery.of(context).size.height * 0.72,
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
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2563EB).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.notifications_outlined,
                        color: Color(0xFF2563EB),
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      'Notifications',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    if (_notifications.isNotEmpty)
                      TextButton(
                        onPressed: () async {
                          await supabase
                              .from('notifications')
                              .delete()
                              .eq('user_id', userId!);
                          setState(() {
                            _notifications = [];
                            _unreadCount = 0;
                          });
                          setSheetState(() {});
                          Navigator.pop(ctx);
                        },
                        child: const Text(
                          'Clear All',
                          style: TextStyle(color: Colors.red, fontSize: 13),
                        ),
                      ),
                  ],
                ),
              ),
              const Divider(height: 20),
              Expanded(
                child: _notifications.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                color: const Color(
                                  0xFF2563EB,
                                ).withOpacity(0.06),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.notifications_none_rounded,
                                size: 40,
                                color: Color(0xFF2563EB),
                              ),
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'No notifications yet',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              "You're all caught up!",
                              style: TextStyle(color: Color(0xFF94A3B8)),
                            ),
                          ],
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 4,
                        ),
                        itemCount: _notifications.length,
                        separatorBuilder: (_, __) =>
                            const Divider(height: 1, color: Color(0xFFF1F5F9)),
                        itemBuilder: (_, i) {
                          final notif = _notifications[i];
                          final isUnread = notif['is_read'] == false;
                          final type = notif['type'] ?? 'general';
                          return Dismissible(
                            key: Key(notif['id'].toString()),
                            direction: DismissDirection.endToStart,
                            background: Container(
                              alignment: Alignment.centerRight,
                              padding: const EdgeInsets.only(right: 16),
                              color: Colors.red.withOpacity(0.1),
                              child: const Icon(
                                Icons.delete_outline_rounded,
                                color: Colors.red,
                              ),
                            ),
                            onDismissed: (_) {
                              _deleteNotification(notif['id'].toString());
                              setSheetState(() => _notifications.removeAt(i));
                            },
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              leading: Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: _notifColor(type).withOpacity(0.1),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  _notifIcon(type),
                                  color: _notifColor(type),
                                  size: 18,
                                ),
                              ),
                              title: Text(
                                notif['title'] ?? '',
                                style: TextStyle(
                                  fontWeight: isUnread
                                      ? FontWeight.bold
                                      : FontWeight.w500,
                                  fontSize: 14,
                                ),
                              ),
                              subtitle: notif['body'] != null
                                  ? Text(
                                      notif['body'],
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Color(0xFF94A3B8),
                                      ),
                                    )
                                  : null,
                              trailing: isUnread
                                  ? Container(
                                      width: 8,
                                      height: 8,
                                      decoration: const BoxDecoration(
                                        color: Color(0xFF2563EB),
                                        shape: BoxShape.circle,
                                      ),
                                    )
                                  : null,
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

void _showHistoryBottomSheet() {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => FutureBuilder<List<Map<String, dynamic>>>(
      future: supabase
          .from('meetings')
          .select()
          .eq('host_id', userId!)
          .order('created_at', ascending: false)
          .limit(50)
          .then((data) => List<Map<String, dynamic>>.from(data)),
      builder: (ctx, snapshot) {
        final allHistory = snapshot.data ?? [];

        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: DraggableScrollableSheet(
            initialChildSize: 0.6,
            maxChildSize: 0.9,
            minChildSize: 0.4,
            expand: false,
            builder: (_, controller) => Column(
              children: [
                const SizedBox(height: 12),
                Container(width: 40, height: 4,
                    decoration: BoxDecoration(color: Colors.black12, borderRadius: BorderRadius.circular(2))),
                const SizedBox(height: 20),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      const Icon(Icons.history, color: Color(0xFF8B5CF6)),
                      const SizedBox(width: 10),
                      const Text('Meeting History',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      const Spacer(),
                      if (allHistory.isNotEmpty)
                        Text('${allHistory.length} total',
                            style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13)),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                const Divider(),
                Expanded(
                  child: !snapshot.hasData
                      ? const Center(child: CircularProgressIndicator(color: Color(0xFF8B5CF6)))
                      : allHistory.isEmpty
                          ? const Center(child: Text('No history yet',
                              style: TextStyle(color: Colors.black38)))
                          : ListView.builder(
                              controller: controller,
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              itemCount: allHistory.length,
                              itemBuilder: (_, i) {
                                final m = allHistory[i];
                                final isScheduled = m['scheduled_at'] != null;
                                final isActive = m['is_active'] == true;
                                return ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: const Color(0xFF2563EB).withOpacity(0.1),
                                    child: Icon(
                                      isScheduled ? Icons.calendar_today_rounded : Icons.videocam,
                                      color: const Color(0xFF2563EB), size: 18,
                                    ),
                                  ),
                                  title: Text(m['meeting_name'] ?? 'Meeting',
                                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                                  subtitle: Row(
                                    children: [
                                      Text(_formatDate(m['created_at']),
                                          style: const TextStyle(fontSize: 12, color: Colors.black45)),
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: isActive
                                              ? const Color(0xFF10B981).withOpacity(0.1)
                                              : Colors.grey.withOpacity(0.1),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(isActive ? 'Active' : 'Ended',
                                            style: TextStyle(
                                                fontSize: 10,
                                                color: isActive ? const Color(0xFF10B981) : Colors.grey)),
                                      ),
                                      if (m['meeting_type'] != null) ...[
                                        const SizedBox(width: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF2563EB).withOpacity(0.08),
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: Text(m['meeting_type'],
                                              style: const TextStyle(fontSize: 10, color: Color(0xFF2563EB))),
                                        ),
                                      ],
                                    ],
                                  ),
                                  trailing: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                        color: const Color(0xFFEFF6FF), borderRadius: BorderRadius.circular(8)),
                                    child: Text(m['meeting_code'] ?? '',
                                        style: const TextStyle(
                                            color: Color(0xFF2563EB), fontWeight: FontWeight.w600, fontSize: 11)),
                                  ),
                                  onLongPress: () {
                                    Navigator.pop(context);
                                    Navigator.push(context, MaterialPageRoute(
                                      builder: (_) => MeetingTimelineScreen(
                                          meetingCode: m['meeting_code'] ?? '',
                                          meetingName: m['meeting_name'] ?? 'Meeting'),
                                    ));
                                  },
                                  onTap: () {
                                    Navigator.pop(context);
                                    Navigator.push(context, MaterialPageRoute(
                                      builder: (_) => MeetingScreen(
                                        channelId: m['meeting_code'],
                                        userName: username,
                                        uid: _generateUid(),
                                        meetingType: m['meeting_type'] ?? 'team',
                                        isHost: m['host_id'] == userId,
                                      ),
                                    ));
                                  },
                                );
                              },
                            ),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}
  void _showJoinMeetingDialog() {
    _meetingIdController.clear();
    _nameController.text = username;

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            CircleAvatar(
              backgroundColor: Color(0xFFECFDF5),
              child: Icon(Icons.login_rounded, color: Color(0xFF10B981)),
            ),
            SizedBox(width: 12),
            Text(
              'Join Meeting',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _meetingIdController,
              decoration: InputDecoration(
                labelText: 'Meeting ID',
                hintText: 'abc-1234-xyz',
                prefixIcon: const Icon(Icons.meeting_room_outlined),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(
                    color: Color(0xFF10B981),
                    width: 2,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _nameController,
              decoration: InputDecoration(
                labelText: 'Display Name',
                prefixIcon: const Icon(Icons.person_outline),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(
                    color: Color(0xFF10B981),
                    width: 2,
                  ),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.black45),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF10B981),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () async {
              final meetingId = _meetingIdController.text.trim();
              final name = _nameController.text.trim().isEmpty
                  ? 'Guest'
                  : _nameController.text.trim();
              if (meetingId.isEmpty) return;
              Navigator.pop(context);
              await _joinMeeting(meetingId, name);
            },
            child: const Text('Join Now'),
          ),
        ],
      ),
    );
  }

  IconData _notifIcon(String type) {
    switch (type) {
      case 'meeting':
        return Icons.videocam_rounded;
      case 'chat':
        return Icons.chat_bubble_outline_rounded;
      case 'schedule':
        return Icons.calendar_today_rounded;
      default:
        return Icons.notifications_outlined;
    }
  }

  Color _notifColor(String type) {
    switch (type) {
      case 'meeting':
        return const Color(0xFF2563EB);
      case 'chat':
        return const Color(0xFF10B981);
      case 'schedule':
        return const Color(0xFFF59E0B);
      default:
        return const Color(0xFF8B5CF6);
    }
  }

  String _formatTime(dynamic dateStr) {
    if (dateStr == null) return '';
    final dt = DateTime.tryParse(dateStr.toString())?.toLocal();
    if (dt == null) return '';
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  String _formatDate(dynamic dateStr) {
    if (dateStr == null) return '';
    final dt = DateTime.tryParse(dateStr.toString())?.toLocal();
    if (dt == null) return '';
    const months = [
      '',
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${dt.day} ${months[dt.month]} ${dt.year}';
  }
}