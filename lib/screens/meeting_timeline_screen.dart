import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MeetingTimelineScreen extends StatefulWidget {
  final String meetingCode;
  final String meetingName;
  final String? meetingType;

  const MeetingTimelineScreen({
    super.key,
    required this.meetingCode,
    required this.meetingName,
    this.meetingType,
  });

  @override
  State<MeetingTimelineScreen> createState() => _MeetingTimelineScreenState();
}

class _MeetingTimelineScreenState extends State<MeetingTimelineScreen>
    with SingleTickerProviderStateMixin {
  final supabase = Supabase.instance.client;

  List<Map<String, dynamic>> _events = [];
  List<Map<String, dynamic>> _participants = [];
  int _totalMessages = 0;
  Map<String, dynamic>? _meeting;

  bool _isLoading = true;
  String? _errorMsg;

  late TabController _tabController;
  bool get _isClass => widget.meetingType == 'class';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _isClass ? 2 : 1, vsync: this);
    _loadAllData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadAllData() async {
    setState(() { _isLoading = true; _errorMsg = null; });
    try {
      final meeting = await supabase
          .from('meetings')
          .select()
          .eq('meeting_code', widget.meetingCode)
          .maybeSingle();
      _meeting = meeting;

      final events = await supabase
          .from('meeting_events')
          .select()
          .eq('meeting_code', widget.meetingCode)
          .order('created_at', ascending: true);
      _events = List<Map<String, dynamic>>.from(events);

      final participants = await supabase
          .from('meeting_participants')
          .select()
          .eq('meeting_code', widget.meetingCode)
          .order('joined_at', ascending: true);
      _participants = List<Map<String, dynamic>>.from(participants);

      // FIX: Message count — first try saved count, then live messages
      if (meeting != null) {
        // Try saved count first (set before messages are deleted)
        final savedCount = meeting['message_count'];
        if (savedCount != null && savedCount > 0) {
          _totalMessages = savedCount as int;
        } else {
          // Meeting still active — count live messages
          try {
            final msgs = await supabase
                .from('messages')
                .select('id')
                .eq('meeting_id', meeting['id'].toString());
            _totalMessages = (msgs as List).length;
          } catch (_) {
            _totalMessages = 0;
          }
        }
      }

      setState(() => _isLoading = false);
    } catch (e) {
      debugPrint('Load timeline error: $e');
      setState(() {
        _isLoading = false;
        _errorMsg = 'Unable to load meeting data. Please try again.';
      });
    }
  }

  // ─── Duration calculation ─────────────────────────────────────────────
  Duration? get _meetingDuration {
    // FIX: Try saved duration_minutes first
    final savedMins = _meeting?['duration_minutes'];
    if (savedMins != null && (savedMins as int) > 0) {
      return Duration(minutes: savedMins);
    }

    // Calculate from events
    final startEv = _events.firstWhere(
      (e) => e['event_type'] == 'started', orElse: () => {},
    );
    if (startEv.isEmpty) {
      // Fallback: use first user_joined event
      final firstJoin = _events.firstWhere(
        (e) => e['event_type'] == 'user_joined', orElse: () => {},
      );
      if (firstJoin.isEmpty) return null;
      final start = DateTime.tryParse(firstJoin['created_at']?.toString() ?? '');
      if (start == null) return null;
      final endEv = _events.lastWhere(
        (e) => e['event_type'] == 'ended', orElse: () => {},
      );
      final endStr = endEv.isNotEmpty ? endEv['created_at']?.toString() : null;
      final end = endStr != null ? DateTime.tryParse(endStr) : null;
      return end != null ? end.difference(start) : DateTime.now().difference(start);
    }

    final start = DateTime.tryParse(startEv['created_at']?.toString() ?? '');
    if (start == null) return null;

    final endEv = _events.lastWhere(
      (e) => e['event_type'] == 'ended', orElse: () => {},
    );
    final endStr = endEv.isNotEmpty ? endEv['created_at']?.toString() : null;
    final end = endStr != null ? DateTime.tryParse(endStr) : null;

    // FIX: Also check ended_at from meetings table
    final endedAt = _meeting?['ended_at'];
    if (end != null) return end.difference(start);
    if (endedAt != null) {
      final endedDt = DateTime.tryParse(endedAt.toString());
      if (endedDt != null) return endedDt.difference(start);
    }

    // Still ongoing
    return DateTime.now().difference(start);
  }

  bool get _meetingIsEnded {
    return _meeting?['is_active'] == false ||
        _events.any((e) => e['event_type'] == 'ended');
  }

  String _formatDuration(Duration? d) {
    if (d == null) return '--';
    if (d.inHours > 0) return '${d.inHours}h ${d.inMinutes % 60}m';
    if (d.inMinutes > 0) return '${d.inMinutes} min';
    return '${d.inSeconds} sec';
  }

  String _formatTime(dynamic dateStr) {
    if (dateStr == null) return '--:--';
    final dt = DateTime.tryParse(dateStr.toString())?.toLocal();
    if (dt == null) return '--:--';
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  String _participantDuration(Map<String, dynamic> p) {
    final joinStr = p['joined_at']?.toString();
    final leftStr = p['left_at']?.toString();
    if (joinStr == null) return '--';
    final join = DateTime.tryParse(joinStr);
    if (join == null) return '--';
    final left = leftStr != null ? DateTime.tryParse(leftStr) : null;
    if (left == null) return 'Still in meeting';
    final diff = left.difference(join);
    if (diff.inMinutes < 1) return '< 1 min';
    return '${diff.inMinutes} min';
  }

  bool _isLateJoin(Map<String, dynamic> p) {
    final joinStr = p['joined_at']?.toString();
    if (joinStr == null) return false;
    final join = DateTime.tryParse(joinStr);
    if (join == null) return false;

    // FIX: Use started event OR the earliest participant join time
    var startEv = _events.firstWhere(
      (e) => e['event_type'] == 'started', orElse: () => {},
    );

    DateTime? start;
    if (startEv.isNotEmpty) {
      start = DateTime.tryParse(startEv['created_at']?.toString() ?? '');
    } else if (_participants.isNotEmpty) {
      // Use earliest join time as start reference
      final sorted = List.from(_participants)
        ..sort((a, b) => (a['joined_at'] ?? '').compareTo(b['joined_at'] ?? ''));
      start = DateTime.tryParse(sorted.first['joined_at']?.toString() ?? '');
    }

    if (start == null) return false;
    return join.difference(start).inSeconds > 120;
  }

  Map<String, dynamic> _eventConfig(String type) {
    switch (type) {
      case 'started':
        return {'icon': Icons.play_circle_rounded, 'color': const Color(0xFF10B981), 'bg': const Color(0xFFECFDF5), 'label': 'Meeting started'};
      case 'user_joined':
        return {'icon': Icons.person_add_rounded, 'color': const Color(0xFF3B82F6), 'bg': const Color(0xFFEFF6FF), 'label': 'joined the meeting'};
      // FIX: user_left shows correctly now
      case 'user_left':
        return {'icon': Icons.person_remove_rounded, 'color': const Color(0xFF94A3B8), 'bg': const Color(0xFFF8FAFF), 'label': 'left the meeting'};
      case 'screen_share_started':
        return {'icon': Icons.screen_share_rounded, 'color': const Color(0xFF8B5CF6), 'bg': const Color(0xFFF5F3FF), 'label': 'started screen sharing'};
      case 'screen_share_stopped':
        return {'icon': Icons.stop_screen_share_rounded, 'color': const Color(0xFF94A3B8), 'bg': const Color(0xFFF8FAFF), 'label': 'stopped screen sharing'};
      case 'chat_message':
        return {'icon': Icons.chat_bubble_outline_rounded, 'color': const Color(0xFFF59E0B), 'bg': const Color(0xFFFFFBEB), 'label': 'sent a message'};
      case 'ended':
        return {'icon': Icons.stop_circle_rounded, 'color': const Color(0xFFEF4444), 'bg': const Color(0xFFFEF2F2), 'label': 'Meeting ended'};
      default:
        return {'icon': Icons.circle_outlined, 'color': const Color(0xFF94A3B8), 'bg': const Color(0xFFF1F5F9), 'label': type};
    }
  }

  // FIX: Event text — user_left shows name correctly
  String _eventText(Map<String, dynamic> ev) {
    final type = ev['event_type'] ?? '';
    final actor = ev['actor_name'] ?? '';
    final cfg = _eventConfig(type);
    final label = cfg['label'] as String;
    switch (type) {
      case 'started':
      case 'ended':
        return label;
      default:
        return '$actor $label';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFF),
      appBar: AppBar(
        backgroundColor: const Color(0xFF2563EB),
        foregroundColor: Colors.white,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Meeting Memory',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: Colors.white)),
            Text(widget.meetingName,
                style: const TextStyle(fontSize: 11, color: Colors.white70)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, size: 20),
            onPressed: _loadAllData,
            tooltip: 'Refresh',
          ),
        ],
        bottom: _isClass
            ? TabBar(
                controller: _tabController,
                indicatorColor: Colors.white,
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white60,
                tabs: const [
                  Tab(icon: Icon(Icons.timeline_rounded, size: 16), text: 'Timeline'),
                  Tab(icon: Icon(Icons.how_to_reg_rounded, size: 16), text: 'Attendance'),
                ],
              )
            : null,
      ),
      body: _isLoading
          ? const Center(child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(color: Color(0xFF2563EB)),
                SizedBox(height: 16),
                Text('Loading timeline...', style: TextStyle(color: Color(0xFF94A3B8))),
              ],
            ))
          : _errorMsg != null
              ? _buildError()
              : _isClass
                  ? TabBarView(
                      controller: _tabController,
                      children: [_buildTimelineTab(), _buildAttendanceTab()],
                    )
                  : _buildTimelineTab(),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline_rounded, size: 48, color: Colors.red),
            const SizedBox(height: 16),
            Text(_errorMsg ?? 'An error occurred.',
                style: const TextStyle(color: Color(0xFF64748B)), textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Try Again'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2563EB), foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: _loadAllData,
            ),
          ],
        ),
      ),
    );
  }

  // ─── TIMELINE TAB ─────────────────────────────────────────────────────
  Widget _buildTimelineTab() {
    return RefreshIndicator(
      onRefresh: _loadAllData,
      color: const Color(0xFF2563EB),
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: _buildSummaryCards()),
          if (_events.isEmpty)
            SliverFillRemaining(child: _buildEmptyState(
              icon: Icons.timeline_rounded,
              title: 'No timeline data yet',
              subtitle: 'Events are recorded during meetings.\nHost a meeting first.',
            ))
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (_, i) => _buildTimelineItem(i),
                  childCount: _events.length,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSummaryCards() {
    final dur = _meetingDuration;
    final participantCount = _participants.isNotEmpty
        ? _participants.length
        : _events.where((e) => e['event_type'] == 'user_joined').length;
    final hasScreenShare = _events.any((e) => e['event_type'] == 'screen_share_started');

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: _summaryCard(
                icon: Icons.timer_outlined,
                value: _meetingIsEnded ? _formatDuration(dur) : '${_formatDuration(dur)} ●',
                label: _meetingIsEnded ? 'Duration' : 'Ongoing',
                color: _meetingIsEnded ? const Color(0xFF2563EB) : const Color(0xFF10B981),
              )),
              const SizedBox(width: 10),
              Expanded(child: _summaryCard(
                icon: Icons.people_rounded,
                value: '$participantCount',
                label: 'Attended',
                color: const Color(0xFF10B981),
              )),
              const SizedBox(width: 10),
              Expanded(child: _summaryCard(
                icon: Icons.chat_bubble_outline_rounded,
                value: '$_totalMessages',
                label: 'Messages',
                color: const Color(0xFFF59E0B),
              )),
              const SizedBox(width: 10),
              Expanded(child: _summaryCard(
                icon: Icons.screen_share_rounded,
                value: hasScreenShare ? 'Yes' : 'No',
                label: 'Screen',
                color: const Color(0xFF8B5CF6),
              )),
            ],
          ),
          if (widget.meetingType != null) ...[
            const SizedBox(height: 12),
            _buildMeetingTypeCard(),
          ],
          const SizedBox(height: 8),
          if (_events.isNotEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 4, bottom: 4),
              child: Row(
                children: [
                  Icon(Icons.timeline_rounded, size: 14, color: Color(0xFF94A3B8)),
                  SizedBox(width: 6),
                  Text('Event Timeline',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF94A3B8))),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _summaryCard({required IconData icon, required String value, required String label, required Color color}) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 3))],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle),
            child: Icon(icon, color: color, size: 16),
          ),
          const SizedBox(height: 6),
          Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
          Text(label, style: const TextStyle(fontSize: 10, color: Color(0xFF94A3B8))),
        ],
      ),
    );
  }

  Widget _buildMeetingTypeCard() {
    final type = widget.meetingType ?? 'team';
    Color color;
    IconData icon;
    String label;
    List<String> features;

    switch (type) {
      case 'class':
        color = const Color(0xFF8B5CF6);
        icon = Icons.school_rounded;
        label = 'Class';
        features = ['Attendance tracked', 'Students join muted', 'Chat moderated'];
        break;
      case 'casual':
        color = const Color(0xFF10B981);
        icon = Icons.emoji_emotions_rounded;
        label = 'Casual Chat';
        features = ['All features open', 'Everyone can speak', 'Free chat'];
        break;
      default:
        color = const Color(0xFF2563EB);
        icon = Icons.work_rounded;
        label = 'Team Meeting';
        features = ['Screen share priority', 'Open chat', 'Collaboration mode'];
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(8)),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: color)),
                const SizedBox(height: 3),
                Text(features.join(' · '), style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8))),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimelineItem(int index) {
    final event = _events[index];
    final cfg = _eventConfig(event['event_type'] ?? '');
    final isLast = index == _events.length - 1;
    final time = _formatTime(event['created_at']);
    final text = _eventText(event);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 48,
            child: Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Text(time,
                  style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8), fontWeight: FontWeight.w500),
                  textAlign: TextAlign.right),
            ),
          ),
          const SizedBox(width: 12),
          Column(
            children: [
              Container(
                width: 30, height: 30,
                margin: const EdgeInsets.only(top: 8),
                decoration: BoxDecoration(
                  color: cfg['bg'] as Color,
                  shape: BoxShape.circle,
                  border: Border.all(color: (cfg['color'] as Color).withOpacity(0.35), width: 1.5),
                ),
                child: Icon(cfg['icon'] as IconData, color: cfg['color'] as Color, size: 15),
              ),
              if (!isLast)
                Expanded(child: Container(width: 1.5, color: const Color(0xFFE2E8F0))),
            ],
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(top: 8, bottom: isLast ? 0 : 14),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(color: const Color(0xFFF1F5F9)),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 4, offset: const Offset(0, 2))],
                ),
                child: Text(text,
                    style: const TextStyle(fontSize: 13, color: Color(0xFF0F172A), fontWeight: FontWeight.w500)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── ATTENDANCE TAB ───────────────────────────────────────────────────
  Widget _buildAttendanceTab() {
    final lateCount = _participants.where(_isLateJoin).length;
    final onTimeCount = _participants.length - lateCount;
    final total = _participants.length;

    return RefreshIndicator(
      onRefresh: _loadAllData,
      color: const Color(0xFF8B5CF6),
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 3))],
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _attSummaryItem(Icons.people_rounded, '$total', 'Total', const Color(0xFF2563EB)),
                            _attSummaryItem(Icons.check_circle_rounded, '$onTimeCount', 'On Time', const Color(0xFF10B981)),
                            _attSummaryItem(Icons.access_time_rounded, '$lateCount', 'Late', const Color(0xFFF59E0B)),
                            _attSummaryItem(Icons.timer_outlined, _formatDuration(_meetingDuration), 'Duration', const Color(0xFF8B5CF6)),
                          ],
                        ),
                        if (total > 0) ...[
                          const SizedBox(height: 14),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: total > 0 ? onTimeCount / total : 0,
                              backgroundColor: const Color(0xFFF59E0B).withOpacity(0.2),
                              valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF10B981)),
                              minHeight: 6,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('On time: ${total > 0 ? (onTimeCount / total * 100).round() : 0}%',
                                  style: const TextStyle(fontSize: 11, color: Color(0xFF10B981), fontWeight: FontWeight.w500)),
                              Text('Late: ${total > 0 ? (lateCount / total * 100).round() : 0}%',
                                  style: const TextStyle(fontSize: 11, color: Color(0xFFF59E0B), fontWeight: FontWeight.w500)),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Row(
                    children: [
                      Icon(Icons.people_outline_rounded, size: 14, color: Color(0xFF94A3B8)),
                      SizedBox(width: 6),
                      Text('Participant Details',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF94A3B8))),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
          if (_participants.isEmpty)
            SliverFillRemaining(child: _buildEmptyState(
              icon: Icons.people_outline_rounded,
              title: 'No attendance data',
              subtitle: 'Participants appear here when they join a class meeting.',
            ))
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (_, i) => _buildParticipantCard(_participants[i]),
                  childCount: _participants.length,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _attSummaryItem(IconData icon, String value, String label, Color color) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle),
          child: Icon(icon, color: color, size: 16),
        ),
        const SizedBox(height: 5),
        Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
        Text(label, style: const TextStyle(fontSize: 10, color: Color(0xFF94A3B8))),
      ],
    );
  }

  Widget _buildParticipantCard(Map<String, dynamic> p) {
    final isLate = _isLateJoin(p);
    final isHost = p['is_host'] == true;
    final stillIn = p['left_at'] == null;
    final name = p['display_name'] ?? 'Unknown';
    final joinTime = _formatTime(p['joined_at']);
    final leftTime = p['left_at'] != null ? _formatTime(p['left_at']) : null;
    final duration = _participantDuration(p);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isLate ? const Color(0xFFF59E0B).withOpacity(0.4)
              : isHost ? const Color(0xFF2563EB).withOpacity(0.3)
              : const Color(0xFFF1F5F9),
          width: (isLate || isHost) ? 1.5 : 1,
        ),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: isHost
                ? const Color(0xFF2563EB).withOpacity(0.15)
                : const Color(0xFF8B5CF6).withOpacity(0.15),
            backgroundImage: p['avatar_url'] != null ? NetworkImage(p['avatar_url']) : null,
            child: p['avatar_url'] == null
                ? Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
                    style: TextStyle(
                      color: isHost ? const Color(0xFF2563EB) : const Color(0xFF8B5CF6),
                      fontWeight: FontWeight.bold, fontSize: 15,
                    ))
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(name,
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF0F172A)),
                          overflow: TextOverflow.ellipsis),
                    ),
                    if (isHost) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: const Color(0xFF2563EB).withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
                        child: const Text('Host', style: TextStyle(color: Color(0xFF2563EB), fontSize: 9, fontWeight: FontWeight.bold)),
                      ),
                    ],
                    if (stillIn) ...[
                      const SizedBox(width: 6),
                      Container(width: 6, height: 6, decoration: const BoxDecoration(color: Color(0xFF10B981), shape: BoxShape.circle)),
                    ],
                  ],
                ),
                const SizedBox(height: 5),
                Row(
                  children: [
                    const Icon(Icons.login_rounded, size: 11, color: Color(0xFF10B981)),
                    const SizedBox(width: 3),
                    Text('In: $joinTime', style: const TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                    if (leftTime != null) ...[
                      const SizedBox(width: 10),
                      const Icon(Icons.logout_rounded, size: 11, color: Color(0xFF94A3B8)),
                      const SizedBox(width: 3),
                      Text('Out: $leftTime', style: const TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isLate ? const Color(0xFFF59E0B).withOpacity(0.12) : const Color(0xFF10B981).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  isLate ? '⏰ Late' : '✓ On Time',
                  style: TextStyle(
                    color: isLate ? const Color(0xFFF59E0B) : const Color(0xFF10B981),
                    fontSize: 10, fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                stillIn ? '🟢 In meeting' : duration,
                style: const TextStyle(fontSize: 10, color: Color(0xFF94A3B8)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState({required IconData icon, required String title, required String subtitle}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: const Color(0xFF2563EB).withOpacity(0.08), shape: BoxShape.circle),
              child: Icon(icon, size: 48, color: const Color(0xFF2563EB)),
            ),
            const SizedBox(height: 16),
            Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
            const SizedBox(height: 8),
            Text(subtitle, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}