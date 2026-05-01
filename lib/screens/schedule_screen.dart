import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'meeting_screen.dart';

class ScheduleScreen extends StatefulWidget {
  const ScheduleScreen({super.key});

  @override
  State<ScheduleScreen> createState() => ScheduleScreenState();
}

class ScheduleScreenState extends State<ScheduleScreen> {
  final supabase = Supabase.instance.client;
  final _titleController = TextEditingController();

  String _username = 'User';
  String? _userId;
  bool _isLoadingUser = true;
  bool _isLoadingMeetings = false;
  bool _isScheduling = false;
  bool _showPast = false;

  List<Map<String, dynamic>> _allMeetings = [];
  List<Map<String, dynamic>> _upcomingMeetings = [];
  List<Map<String, dynamic>> _pastMeetings = [];

  DateTime? _selectedDate;
  TimeOfDay? _selectedTime;
  String _selectedType = 'team';

  @override
  void initState() {
    super.initState();
    _loadUserAndMeetings();
  }

  Future<void> _loadUserAndMeetings() async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      setState(() => _isLoadingUser = false);
      return;
    }

    try {
      final data = await supabase
          .from('profiles')
          .select()
          .eq('id', user.id)
          .maybeSingle();
      setState(() {
        _userId = user.id;
        _username = data?['username'] ?? 'User';
        _isLoadingUser = false;
      });
      await _loadScheduledMeetings();
    } catch (e) {
      debugPrint('Load user error: $e');
      setState(() => _isLoadingUser = false);
    }
  }

  Future<void> _loadScheduledMeetings() async {
    if (_userId == null) return;
    setState(() => _isLoadingMeetings = true);

    try {
      // FIX: Added .eq('is_active', true) so soft-deleted meetings don't reappear
      final meetings = await supabase
          .from('meetings')
          .select()
          .eq('host_id', _userId!)
          .eq('is_active', true) // ← BUG FIX: was missing, deleted items kept showing
          .not('scheduled_at', 'is', null)
          .order('scheduled_at', ascending: true);

      final all = List<Map<String, dynamic>>.from(meetings);
      final now = DateTime.now();

      // Grace period: treat as upcoming until 1 hour after scheduled time
      final upcoming = all.where((m) {
        final dt =
            DateTime.tryParse(m['scheduled_at'].toString())?.toLocal();
        if (dt == null) return false;
        return dt.isAfter(now.subtract(const Duration(hours: 1)));
      }).toList();

      final past = all.where((m) {
        final dt =
            DateTime.tryParse(m['scheduled_at'].toString())?.toLocal();
        if (dt == null) return true;
        return dt.isBefore(now.subtract(const Duration(hours: 1)));
      }).toList();

      setState(() {
        _allMeetings = all;
        _upcomingMeetings = upcoming;
        _pastMeetings = past;
        _isLoadingMeetings = false;
      });
    } catch (e) {
      debugPrint('Load meetings error: $e');
      setState(() => _isLoadingMeetings = false);
    }
  }

  String _generateMeetingCode() {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final rand = Random();
    final p1 =
        List.generate(3, (_) => chars[rand.nextInt(chars.length)]).join();
    final p2 =
        List.generate(4, (_) => chars[rand.nextInt(chars.length)]).join();
    final p3 =
        List.generate(3, (_) => chars[rand.nextInt(chars.length)]).join();
    return '$p1-$p2-$p3';
  }

  int _generateUid() => Random().nextInt(900000) + 100000;

  void _showScheduleDialog() {
    _titleController.clear();
    _selectedType = 'team';
    setState(() {
      _selectedDate = null;
      _selectedTime = null;
    });

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius:
                  BorderRadius.vertical(top: Radius.circular(24)),
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
                        borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                const SizedBox(height: 20),
                const Text('Schedule a Meeting',
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF0F172A))),
                const SizedBox(height: 4),
                const Text('Set up your meeting in advance',
                    style: TextStyle(
                        color: Color(0xFF94A3B8), fontSize: 13)),
                const SizedBox(height: 20),

                // Title
                TextField(
                  controller: _titleController,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    labelText: 'Meeting Title',
                    hintText: 'e.g. Team Standup',
                    prefixIcon: const Icon(Icons.title_rounded,
                        color: Color(0xFF2563EB)),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                          color: Color(0xFF2563EB), width: 2),
                    ),
                  ),
                ),
                const SizedBox(height: 14),

                // Meeting type chips
                Row(
                  children: [
                    _typeChip('team', Icons.work_rounded, 'Team',
                        const Color(0xFF2563EB), setSheet),
                    const SizedBox(width: 8),
                    _typeChip('class', Icons.school_rounded, 'Class',
                        const Color(0xFF8B5CF6), setSheet),
                    const SizedBox(width: 8),
                    _typeChip(
                        'casual',
                        Icons.emoji_emotions_rounded,
                        'Casual',
                        const Color(0xFF10B981),
                        setSheet),
                  ],
                ),
                const SizedBox(height: 14),

                // Date + Time pickers
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: ctx,
                            initialDate: DateTime.now()
                                .add(const Duration(days: 1)),
                            firstDate: DateTime.now(),
                            lastDate: DateTime.now()
                                .add(const Duration(days: 365)),
                          );
                          if (picked != null) {
                            setState(() => _selectedDate = picked);
                            setSheet(() {});
                          }
                        },
                        child: _pickerTile(
                          icon: Icons.calendar_today_rounded,
                          text: _selectedDate == null
                              ? 'Select Date'
                              : '${_selectedDate!.day}/${_selectedDate!.month}/${_selectedDate!.year}',
                          selected: _selectedDate != null,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: GestureDetector(
                        onTap: () async {
                          final picked = await showTimePicker(
                              context: ctx,
                              initialTime: TimeOfDay.now());
                          if (picked != null) {
                            setState(() => _selectedTime = picked);
                            setSheet(() {});
                          }
                        },
                        child: _pickerTile(
                          icon: Icons.access_time_rounded,
                          text: _selectedTime == null
                              ? 'Select Time'
                              : _selectedTime!.format(ctx),
                          selected: _selectedTime != null,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2563EB),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                      textStyle: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600),
                    ),
                    onPressed: _isScheduling
                        ? null
                        : () async {
                            Navigator.pop(ctx);
                            await _scheduleMeeting();
                          },
                    child: _isScheduling
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2))
                        : const Text('Schedule Meeting'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _typeChip(String type, IconData icon, String label,
      Color color, StateSetter setSheet) {
    final selected = _selectedType == type;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() => _selectedType = type);
          setSheet(() {});
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? color.withOpacity(0.1) : Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: selected ? color : const Color(0xFFE2E8F0),
                width: selected ? 2 : 1),
          ),
          child: Column(
            children: [
              Icon(icon,
                  color: selected ? color : const Color(0xFF94A3B8),
                  size: 18),
              const SizedBox(height: 4),
              Text(label,
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: selected
                          ? color
                          : const Color(0xFF94A3B8))),
            ],
          ),
        ),
      ),
    );
  }

  Widget _pickerTile(
      {required IconData icon,
      required String text,
      required bool selected}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        border: Border.all(
            color: selected
                ? const Color(0xFF2563EB)
                : const Color(0xFFE2E8F0),
            width: selected ? 2 : 1),
        borderRadius: BorderRadius.circular(12),
        color: selected ? const Color(0xFFEFF6FF) : Colors.white,
      ),
      child: Row(
        children: [
          Icon(icon,
              size: 16,
              color: selected
                  ? const Color(0xFF2563EB)
                  : const Color(0xFF94A3B8)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                  color: selected
                      ? const Color(0xFF0F172A)
                      : const Color(0xFF94A3B8),
                  fontSize: 13,
                  fontWeight: selected
                      ? FontWeight.w600
                      : FontWeight.normal),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _scheduleMeeting() async {
    if (_titleController.text.trim().isEmpty) {
      _snack('Please enter a meeting title.', Colors.orange);
      return;
    }
    if (_selectedDate == null || _selectedTime == null) {
      _snack('Please select a date and time.', Colors.orange);
      return;
    }

    setState(() => _isScheduling = true);

    final scheduledAt = DateTime(
      _selectedDate!.year,
      _selectedDate!.month,
      _selectedDate!.day,
      _selectedTime!.hour,
      _selectedTime!.minute,
    );
    final meetingCode = _generateMeetingCode();

    try {
      await supabase.from('meetings').insert({
        'meeting_code': meetingCode,
        'meeting_name': _titleController.text.trim(),
        'host_id': _userId,
        'host_name': _username,
        'scheduled_at': scheduledAt.toIso8601String(),
        'meeting_type': _selectedType,
        'is_active': true,
        'created_at': DateTime.now().toIso8601String(),
      });

      setState(() => _isScheduling = false);
      if (mounted) {
        await _loadScheduledMeetings();
        _showSuccessDialog(meetingCode, scheduledAt);
      }
    } catch (e) {
      setState(() => _isScheduling = false);
      if (mounted) {
        _snack('Failed to schedule meeting. Please try again.',
            Colors.red);
      }
    }
  }

  void _snack(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(msg),
        backgroundColor: color,
        duration: const Duration(seconds: 2)));
  }

  void _showSuccessDialog(String code, DateTime scheduledAt) {
    final typeConfig = _getTypeConfig(_selectedType);
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const CircleAvatar(
              backgroundColor: Color(0xFFECFDF5),
              child:
                  Icon(Icons.check_rounded, color: Color(0xFF10B981)),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text('Meeting Scheduled!',
                  style: TextStyle(
                      fontSize: 17, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                  color: (typeConfig['color'] as Color).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(typeConfig['icon'] as IconData,
                    size: 13,
                    color: typeConfig['color'] as Color),
                const SizedBox(width: 5),
                Text(typeConfig['label'] as String,
                    style: TextStyle(
                        color: typeConfig['color'] as Color,
                        fontSize: 11,
                        fontWeight: FontWeight.w600)),
              ]),
            ),
            const SizedBox(height: 12),
            Row(children: [
              const Icon(Icons.calendar_today_rounded,
                  size: 13, color: Color(0xFF64748B)),
              const SizedBox(width: 6),
              Text(_formatDateTime(scheduledAt),
                  style: const TextStyle(
                      color: Color(0xFF64748B), fontSize: 13)),
            ]),
            const SizedBox(height: 16),
            const Text('Meeting ID',
                style: TextStyle(
                    color: Color(0xFF94A3B8),
                    fontSize: 12,
                    fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            _meetingIdBox(code),
          ],
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2563EB),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.pop(context),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  Widget _meetingIdBox(String code) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFF),
        borderRadius: BorderRadius.circular(12),
        border:
            Border.all(color: const Color(0xFF2563EB), width: 1.5),
      ),
      child: Row(
        children: [
          Expanded(
              child: Text(code,
                  style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2,
                      color: Color(0xFF2563EB)))),
          GestureDetector(
            onTap: () {
              Clipboard.setData(ClipboardData(text: code));
              _snack(
                  'Meeting ID copied!', const Color(0xFF10B981));
            },
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.copy_rounded,
                  color: Color(0xFF2563EB), size: 16),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(Map<String, dynamic> meeting) async {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        title: const Text('Cancel Meeting?',
            style: TextStyle(fontWeight: FontWeight.bold)),
        content: Text(
            'Cancel "${meeting['meeting_name']}"? This cannot be undone.',
            style: const TextStyle(color: Color(0xFF64748B))),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Keep It'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () async {
              Navigator.pop(context);
              // FIX: .toString() added — Supabase returns dynamic ID,
              // passing it directly caused a silent type mismatch
              await _deleteMeeting(meeting['id'].toString());
            },
            child: const Text('Cancel Meeting'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteMeeting(String id) async {
    try {
      // Soft delete — sets is_active: false so meeting_events/participants
      // data is preserved in the database
      await supabase
          .from('meetings')
          .update({'is_active': false})
          .eq('id', id);

      // Reload — now filtered by is_active: true so it won't reappear
      await _loadScheduledMeetings();

      if (mounted) {
        _snack('Meeting cancelled successfully.', const Color(0xFF10B981));
      }
    } catch (e) {
      debugPrint('Delete meeting error: $e');
      if (mounted) {
        _snack('Failed to cancel meeting. Please try again.', Colors.red);
      }
    }
  }

  Map<String, dynamic> _getTypeConfig(String? type) {
    switch (type) {
      case 'class':
        return {
          'icon': Icons.school_rounded,
          'label': 'Class',
          'color': const Color(0xFF8B5CF6)
        };
      case 'casual':
        return {
          'icon': Icons.emoji_emotions_rounded,
          'label': 'Casual',
          'color': const Color(0xFF10B981)
        };
      default:
        return {
          'icon': Icons.work_rounded,
          'label': 'Team',
          'color': const Color(0xFF2563EB)
        };
    }
  }

  String _formatDateTime(DateTime dt) {
    const months = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '${dt.day} ${months[dt.month]} ${dt.year} at $h:$m';
  }

  String _formatDate(dynamic raw) {
    if (raw == null) return '';
    final dt = DateTime.tryParse(raw.toString())?.toLocal();
    if (dt == null) return '';
    const months = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${dt.day} ${months[dt.month]} ${dt.year}';
  }

  String _formatTime(dynamic raw) {
    if (raw == null) return '';
    final dt = DateTime.tryParse(raw.toString())?.toLocal();
    if (dt == null) return '';
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  String _timeUntil(dynamic raw) {
    if (raw == null) return '';
    final dt = DateTime.tryParse(raw.toString())?.toLocal();
    if (dt == null) return '';
    final now = DateTime.now();
    final diff = dt.difference(now);

    if (diff.isNegative) {
      final ago = now.difference(dt);
      if (ago.inMinutes < 60) return '${ago.inMinutes}m ago';
      if (ago.inHours < 24) return '${ago.inHours}h ago';
      return _formatDate(raw);
    }

    if (diff.inMinutes < 60) return 'In ${diff.inMinutes} min';
    if (diff.inHours < 24) {
      return 'In ${diff.inHours}h ${diff.inMinutes % 60}m';
    }
    if (diff.inDays == 1) return 'Tomorrow';
    if (diff.inDays < 7) return 'In ${diff.inDays} days';
    return _formatDate(raw);
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        title: const Text('Schedule',
            style:
                TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
        backgroundColor: const Color(0xFF2563EB),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          if (_pastMeetings.isNotEmpty)
            TextButton(
              onPressed: () =>
                  setState(() => _showPast = !_showPast),
              child: Text(
                  _showPast
                      ? 'Hide Past'
                      : 'Past (${_pastMeetings.length})',
                  style: const TextStyle(
                      color: Colors.white70, fontSize: 13)),
            ),
          IconButton(
            icon: const Icon(Icons.add_rounded),
            onPressed:
                _isLoadingUser ? null : _showScheduleDialog,
          ),
        ],
      ),
      body: _isLoadingUser
          ? const Center(
              child: CircularProgressIndicator(
                  color: Color(0xFF2563EB)))
          : RefreshIndicator(
              onRefresh: _loadScheduledMeetings,
              color: const Color(0xFF2563EB),
              child: _isLoadingMeetings
                  ? const Center(
                      child: CircularProgressIndicator(
                          color: Color(0xFF2563EB)))
                  : _buildBody(),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed:
            _isLoadingUser ? null : _showScheduleDialog,
        backgroundColor: const Color(0xFF2563EB),
        icon: const Icon(Icons.add_rounded, color: Colors.white),
        label: const Text('New Meeting',
            style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600)),
      ),
    );
  }

  Widget _buildBody() {
    final displayList = _showPast
        ? [..._upcomingMeetings, ..._pastMeetings]
        : _upcomingMeetings;

    if (_upcomingMeetings.isEmpty && _pastMeetings.isEmpty) {
      return _buildEmptyState();
    }

    if (_upcomingMeetings.isEmpty && !_showPast) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                    color:
                        const Color(0xFF10B981).withOpacity(0.1),
                    shape: BoxShape.circle),
                child: const Icon(Icons.event_available_rounded,
                    size: 48, color: Color(0xFF10B981)),
              ),
              const SizedBox(height: 20),
              const Text('No Upcoming Meetings',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF0F172A))),
              const SizedBox(height: 8),
              Text(
                _pastMeetings.isNotEmpty
                    ? 'You have ${_pastMeetings.length} past meeting${_pastMeetings.length == 1 ? '' : 's'}.'
                    : 'Schedule a new meeting to get started.',
                style: const TextStyle(
                    color: Color(0xFF94A3B8), fontSize: 13),
                textAlign: TextAlign.center,
              ),
              if (_pastMeetings.isNotEmpty) ...[
                const SizedBox(height: 16),
                OutlinedButton(
                  onPressed: () =>
                      setState(() => _showPast = true),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF2563EB),
                    side: const BorderSide(
                        color: Color(0xFF2563EB)),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  child: Text(
                      'View ${_pastMeetings.length} Past Meeting${_pastMeetings.length == 1 ? '' : 's'}'),
                ),
              ],
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      itemCount: displayList.length +
          (_showPast && _pastMeetings.isNotEmpty ? 1 : 0),
      itemBuilder: (_, i) {
        // Section header between upcoming and past
        if (_showPast &&
            i == _upcomingMeetings.length &&
            _pastMeetings.isNotEmpty) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(0, 8, 0, 12),
            child: Row(
              children: [
                const Icon(Icons.history_rounded,
                    size: 14, color: Color(0xFF94A3B8)),
                const SizedBox(width: 6),
                Text(
                    'Past Meetings (${_pastMeetings.length})',
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF94A3B8))),
              ],
            ),
          );
        }
        final idx =
            (_showPast && i > _upcomingMeetings.length)
                ? i - 1
                : i;
        return _buildCard(displayList[idx]);
      },
    );
  }

  Widget _buildCard(Map<String, dynamic> meeting) {
    final dt = DateTime.tryParse(
            meeting['scheduled_at']?.toString() ?? '')
        ?.toLocal();
    final isUpcoming = dt != null &&
        dt.isAfter(
            DateTime.now().subtract(const Duration(hours: 1)));
    final isSoon = dt != null &&
        dt.isAfter(DateTime.now()) &&
        dt.isBefore(
            DateTime.now().add(const Duration(hours: 2)));
    final code = meeting['meeting_code'] ?? '';
    final typeConfig = _getTypeConfig(meeting['meeting_type']);
    final typeColor = typeConfig['color'] as Color;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 12,
              offset: const Offset(0, 4)),
          if (isSoon)
            BoxShadow(
                color: const Color(0xFF10B981).withOpacity(0.15),
                blurRadius: 20),
        ],
        border: isSoon
            ? Border.all(
                color:
                    const Color(0xFF10B981).withOpacity(0.4),
                width: 1.5)
            : null,
      ),
      child: Column(
        children: [
          // Color accent bar
          Container(
            height: 4,
            decoration: BoxDecoration(
              color: isUpcoming
                  ? typeColor
                  : const Color(0xFFCBD5E1),
              borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(18)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Title row
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                          color: typeColor.withOpacity(0.1),
                          borderRadius:
                              BorderRadius.circular(10)),
                      child: Icon(
                          typeConfig['icon'] as IconData,
                          color: typeColor,
                          size: 18),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                          Text(
                              meeting['meeting_name'] ??
                                  'Meeting',
                              style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF0F172A))),
                          const SizedBox(height: 2),
                          Text(typeConfig['label'] as String,
                              style: TextStyle(
                                  fontSize: 11,
                                  color: typeColor,
                                  fontWeight:
                                      FontWeight.w500)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Status badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: isSoon
                            ? const Color(0xFF10B981)
                                .withOpacity(0.1)
                            : isUpcoming
                                ? const Color(0xFFEFF6FF)
                                : const Color(0xFFF1F5F9),
                        borderRadius:
                            BorderRadius.circular(20),
                      ),
                      child: Text(
                        isSoon
                            ? '🔴 Starting Soon'
                            : isUpcoming
                                ? 'Upcoming'
                                : 'Past',
                        style: TextStyle(
                          color: isSoon
                              ? const Color(0xFF10B981)
                              : isUpcoming
                                  ? const Color(0xFF2563EB)
                                  : const Color(0xFF94A3B8),
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 14),

                // Date + time + countdown
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFF),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: const Color(0xFFE2E8F0)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.calendar_today_rounded,
                          size: 13, color: typeColor),
                      const SizedBox(width: 6),
                      Text(
                          _formatDate(meeting['scheduled_at']),
                          style: const TextStyle(
                              fontSize: 13,
                              color: Color(0xFF0F172A),
                              fontWeight: FontWeight.w500)),
                      const SizedBox(width: 12),
                      Icon(Icons.access_time_rounded,
                          size: 13, color: typeColor),
                      const SizedBox(width: 4),
                      Text(
                          _formatTime(meeting['scheduled_at']),
                          style: const TextStyle(
                              fontSize: 13,
                              color: Color(0xFF0F172A),
                              fontWeight: FontWeight.w500)),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: typeColor.withOpacity(0.08),
                          borderRadius:
                              BorderRadius.circular(8),
                        ),
                        child: Text(
                            _timeUntil(meeting['scheduled_at']),
                            style: TextStyle(
                                fontSize: 11,
                                color: typeColor,
                                fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 10),

                // Meeting ID row
                GestureDetector(
                  onTap: () {
                    Clipboard.setData(
                        ClipboardData(text: code));
                    _snack('Meeting ID copied!',
                        const Color(0xFF10B981));
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: const Color(0xFFE2E8F0)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.tag_rounded,
                            size: 13,
                            color: Color(0xFF64748B)),
                        const SizedBox(width: 6),
                        Text(code,
                            style: const TextStyle(
                                fontSize: 13,
                                color: Color(0xFF2563EB),
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1)),
                        const Spacer(),
                        const Icon(Icons.copy_rounded,
                            size: 14,
                            color: Color(0xFF94A3B8)),
                        const SizedBox(width: 4),
                        const Text('Copy',
                            style: TextStyle(
                                fontSize: 11,
                                color: Color(0xFF94A3B8))),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                // Action buttons
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.copy_rounded,
                            size: 14),
                        label: const Text('Copy ID'),
                        onPressed: () {
                          Clipboard.setData(
                              ClipboardData(text: code));
                          _snack('Meeting ID copied!',
                              const Color(0xFF10B981));
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor:
                              const Color(0xFF2563EB),
                          side: const BorderSide(
                              color: Color(0xFF2563EB)),
                          shape: RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius.circular(10)),
                          padding: const EdgeInsets.symmetric(
                              vertical: 10),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton.icon(
                        icon: const Icon(
                            Icons.videocam_rounded,
                            size: 15),
                        label: const Text('Join Now'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: typeColor,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius.circular(10)),
                          padding: const EdgeInsets.symmetric(
                              vertical: 10),
                        ),
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => MeetingScreen(
                                channelId: code,
                                userName: _username,
                                uid: _generateUid(),
                                meetingType:
                                    meeting['meeting_type'] ??
                                        'team',
                                isHost: true,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      icon: const Icon(
                          Icons.delete_outline_rounded,
                          color: Colors.red,
                          size: 20),
                      onPressed: () =>
                          _confirmDelete(meeting),
                      tooltip: 'Cancel Meeting',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return ListView(
      children: [
        SizedBox(
            height: MediaQuery.of(context).size.height * 0.18),
        Column(
          children: [
            Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                  color:
                      const Color(0xFF2563EB).withOpacity(0.08),
                  shape: BoxShape.circle),
              child: const Icon(Icons.calendar_month_rounded,
                  size: 56, color: Color(0xFF2563EB)),
            ),
            const SizedBox(height: 24),
            const Text('No Scheduled Meetings',
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0F172A))),
            const SizedBox(height: 8),
            const Text(
                'Plan meetings in advance and share\nthe ID with your participants.',
                style: TextStyle(
                    color: Color(0xFF94A3B8), fontSize: 14),
                textAlign: TextAlign.center),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: _showScheduleDialog,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Schedule a Meeting'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2563EB),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                    horizontal: 32, vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                textStyle: const TextStyle(
                    fontWeight: FontWeight.w600, fontSize: 15),
              ),
            ),
          ],
        ),
      ],
    );
  }
}