import 'package:flutter/material.dart';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:convert';
import 'meeting_timeline_screen.dart';
import 'meeting_theme.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class MeetingScreen extends StatefulWidget {
  final String channelId;
  final String userName;
  final int uid;
  final String meetingType;
  final bool isHost;

  const MeetingScreen({
    super.key,
    required this.channelId,
    required this.userName,
    required this.uid,
    this.meetingType = 'team',
    this.isHost = false,
  });

  @override
  State<MeetingScreen> createState() => _MeetingScreenState();
}

class _MeetingScreenState extends State<MeetingScreen> {
  final String appId = dotenv.env['AGORA_APP_ID'] ?? '';
final String tokenServerUrl = dotenv.env['TOKEN_SERVER_URL'] ?? '';
final supabase = Supabase.instance.client;

  late RtcEngine _engine;
  late MeetingTheme _theme;

  bool _localUserJoined = false;
  bool _isLoading = true;
  String? _errorMessage;

  bool isVideoOn = true;
  bool isScreenSharing = false;
  bool isFrontCamera = true;
  bool isChatOpen = false;
  bool _showTypeInfo = false;
  late bool isAudioOn;

  List<int> _remoteUids = [];
  bool _isLocalSpeaking = false;
  Map<int, bool> _remoteSpeaking = {};
  Map<int, bool> _remoteAudioMuted = {};
  Map<int, bool> _remoteVideoMuted = {};
  Map<int, String> _remoteNames = {};
  Map<int, String?> _remoteAvatars = {};

  Set<int> _chatDisabledUids = {};
  bool _localChatDisabled = false;

  int? _screenShareUid;
  bool _someoneIsSharing = false;

  int? _tappedUid;

  String _currentQuality = '480p';
  static const List<Map<String, dynamic>> _qualityPresets = [
    {'label': '360p', 'desc': 'Low bandwidth', 'icon': Icons.signal_cellular_alt_1_bar, 'w': 640, 'h': 360, 'fps': 15, 'bitrate': 400},
    {'label': '480p', 'desc': 'Balanced — recommended', 'icon': Icons.signal_cellular_alt_2_bar, 'w': 640, 'h': 480, 'fps': 15, 'bitrate': 600},
    {'label': '720p', 'desc': 'HD — good network required', 'icon': Icons.signal_cellular_alt, 'w': 1280, 'h': 720, 'fps': 24, 'bitrate': 1200},
    {'label': '1080p', 'desc': 'Full HD — Wi-Fi only', 'icon': Icons.signal_cellular_4_bar, 'w': 1920, 'h': 1080, 'fps': 30, 'bitrate': 2500},
  ];

  String? _localAvatarUrl;
  String? _localUserId;

  // ─── Waiting room ─────────────────────────────────────────────────────
  bool _isPrivateMeeting = false;
  List<Map<String, dynamic>> _waitingUsers = [];
  RealtimeChannel? _waitingChannel;

  final TextEditingController _chatController = TextEditingController();
  final ScrollController _chatScrollController = ScrollController();
  List<Map<String, dynamic>> _messages = [];
  RealtimeChannel? _chatChannel;
  RealtimeChannel? _participantsChannel;
  RealtimeChannel? _signalChannel;
  String? _meetingDbId;
  int _unreadCount = 0;

  final DateTime _joinTime = DateTime.now();

  @override
  void initState() {
    super.initState();
    _theme = MeetingTheme.fromType(widget.meetingType);
    isAudioOn = (widget.meetingType == 'class') ? widget.isHost : true;
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await _loadLocalProfile();
    await Future.wait([_initializeAgora(), _initChat()]);
    _subscribeToSignals();

    // Privacy setting load karo
    try {
      final meetingData = await supabase
          .from('meetings')
          .select('is_private')
          .eq('meeting_code', widget.channelId)
          .maybeSingle();
      if (mounted) setState(() => _isPrivateMeeting = meetingData?['is_private'] == true);
    } catch (_) {}

    // Agar host hai toh waiting room subscribe karo
    if (widget.isHost) _subscribeToWaitingRoom();
  }

  void _subscribeToWaitingRoom() {
    _waitingChannel = supabase
        .channel('waiting_${widget.channelId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'waiting_room',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'meeting_code',
            value: widget.channelId,
          ),
          callback: (payload) {
            if (mounted) {
              setState(() => _waitingUsers.add(payload.newRecord));
              _showWaitingUserAlert(payload.newRecord);
            }
          },
        )
        .subscribe();
  }

  void _showWaitingUserAlert(Map<String, dynamic> user) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      duration: const Duration(seconds: 25),
      backgroundColor: const Color(0xFF1E293B),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      content: Row(children: [
        CircleAvatar(
          radius: 18,
          backgroundColor: const Color(0xFF2563EB).withOpacity(0.3),
          backgroundImage: user['avatar_url'] != null ? NetworkImage(user['avatar_url']) : null,
          child: user['avatar_url'] == null
              ? Text((user['display_name'] ?? 'U')[0].toUpperCase(),
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))
              : null,
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(user['display_name'] ?? 'Someone',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
            const Text('wants to join the meeting',
                style: TextStyle(color: Colors.white60, fontSize: 11)),
          ],
        )),
        TextButton(
          onPressed: () { ScaffoldMessenger.of(context).hideCurrentSnackBar(); _rejectUser(user); },
          child: const Text('Deny', style: TextStyle(color: Colors.redAccent, fontSize: 12))),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF10B981), foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
          onPressed: () { ScaffoldMessenger.of(context).hideCurrentSnackBar(); _admitUser(user); },
          child: const Text('Admit')),
      ]),
    ));
  }

  Future<void> _admitUser(Map<String, dynamic> user) async {
    try {
      await supabase.from('waiting_room').update({'status': 'admitted'}).eq('id', user['id']);
      await supabase.from('meeting_signals').insert({
        'meeting_code': widget.channelId,
        'signal_type': 'admitted',
        'target_uid': user['agora_uid'],
        'sender_name': widget.userName,
        'created_at': DateTime.now().toIso8601String(),
      });
      setState(() => _waitingUsers.removeWhere((u) => u['id'] == user['id']));
      _showSnack('${user['display_name']} admitted.', const Color(0xFF10B981));
    } catch (e) { debugPrint('Admit error: $e'); }
  }

  Future<void> _rejectUser(Map<String, dynamic> user) async {
    try {
      await supabase.from('waiting_room').update({'status': 'rejected'}).eq('id', user['id']);
      await supabase.from('meeting_signals').insert({
        'meeting_code': widget.channelId,
        'signal_type': 'rejected',
        'target_uid': user['agora_uid'],
        'sender_name': widget.userName,
        'created_at': DateTime.now().toIso8601String(),
      });
      setState(() => _waitingUsers.removeWhere((u) => u['id'] == user['id']));
      _showSnack('${user['display_name']} was not admitted.', Colors.red);
    } catch (e) { debugPrint('Reject error: $e'); }
  }

  void _showWaitingRoomPanel() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: BoxDecoration(
          color: _theme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: Container(width: 40, height: 4,
                decoration: BoxDecoration(color: Colors.white12, borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 16),
            Row(children: [
              const Icon(Icons.hourglass_top_rounded, color: Colors.orange, size: 18),
              const SizedBox(width: 8),
              Text('Waiting Room (${_waitingUsers.length})',
                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            ]),
            const SizedBox(height: 16),
            if (_waitingUsers.isEmpty)
              const Center(child: Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Text('No one is waiting', style: TextStyle(color: Colors.white38)),
              ))
            else
              ..._waitingUsers.map((user) => Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white12),
                ),
                child: Row(children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: const Color(0xFF2563EB).withOpacity(0.2),
                    backgroundImage: user['avatar_url'] != null ? NetworkImage(user['avatar_url']) : null,
                    child: user['avatar_url'] == null
                        ? Text((user['display_name'] ?? 'U')[0].toUpperCase(),
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Text(user['display_name'] ?? 'User',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600))),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.redAccent, size: 20),
                    onPressed: () { Navigator.pop(context); _rejectUser(user); }),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF10B981), foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8)),
                    onPressed: () { Navigator.pop(context); _admitUser(user); },
                    child: const Text('Admit')),
                ]),
              )),
          ],
        ),
      ),
    );
  }

  Future<void> _loadLocalProfile() async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) return;
      _localUserId = user.id;
      final data = await supabase.from('profiles').select('avatar_url').eq('id', user.id).maybeSingle();
      if (mounted) setState(() => _localAvatarUrl = data?['avatar_url']);
    } catch (e) {
      debugPrint('Profile load error: $e');
    }
  }

  // ─── Participant registration ─────────────────────────────────────────
  Future<void> _registerParticipantAndLog() async {
    try {
      await supabase.from('meeting_participants').delete()
          .eq('meeting_code', widget.channelId).eq('agora_uid', widget.uid);
      await supabase.from('meeting_participants').insert({
        'meeting_code': widget.channelId,
        'agora_uid': widget.uid,
        'user_id': _localUserId,
        'display_name': widget.userName,
        'avatar_url': _localAvatarUrl,
        'joined_at': DateTime.now().toIso8601String(),
        'is_host': widget.isHost,
        'is_muted': !isAudioOn,
        'left_at': null,
      });
    } catch (e) { debugPrint('Register participant error: $e'); }

    try {
      await supabase.from('meeting_events').insert({
        'meeting_code': widget.channelId,
        'event_type': 'user_joined',
        'actor_name': widget.userName,
        'created_at': DateTime.now().toIso8601String(),
      });
    } catch (e) { debugPrint('Join event log error: $e'); }
  }

  Future<void> _fetchRemoteParticipantInfo(int remoteUid) async {
    try {
      await Future.delayed(const Duration(milliseconds: 800));
      final result = await supabase.from('meeting_participants').select()
          .eq('meeting_code', widget.channelId).eq('agora_uid', remoteUid).maybeSingle();
      if (result != null && mounted) {
        setState(() {
          _remoteNames[remoteUid] = result['display_name'] ?? 'User $remoteUid';
          _remoteAvatars[remoteUid] = result['avatar_url'];
        });
      }
    } catch (e) { debugPrint('Fetch remote info error: $e'); }
  }

  void _subscribeToParticipants() {
    _participantsChannel = supabase
        .channel('participants_${widget.channelId}_${widget.uid}')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'meeting_participants',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'meeting_code', value: widget.channelId),
          callback: (payload) {
            final record = payload.newRecord;
            final uid = record['agora_uid'];
            if (uid != null && uid != widget.uid && mounted) {
              setState(() {
                _remoteNames[uid] = record['display_name'] ?? 'User $uid';
                _remoteAvatars[uid] = record['avatar_url'];
              });
            }
          },
        ).subscribe();
  }

  // ─── Signals ─────────────────────────────────────────────────────────
  void _subscribeToSignals() {
    _signalChannel = supabase
        .channel('signals_${widget.channelId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'meeting_signals',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'meeting_code', value: widget.channelId),
          callback: (payload) async {
            if (!mounted) return;
            final signal = payload.newRecord;
            final signalType = signal['signal_type'] as String?;
            final targetUid = signal['target_uid'];
            final senderName = signal['sender_name'] ?? 'Host';

            // Guest: admitted/rejected signals
            if (signalType == 'admitted') {
              final rawUid = signal['target_uid'];
              final admittedUid = rawUid is int ? rawUid : int.tryParse(rawUid?.toString() ?? '');
              if (admittedUid == widget.uid && mounted) {
                _showSnack('You have been admitted to the meeting!', const Color(0xFF10B981));
              }
              return;
            }
            if (signalType == 'rejected') {
              final rawUid = signal['target_uid'];
              final rejectedUid = rawUid is int ? rawUid : int.tryParse(rawUid?.toString() ?? '');
              if (rejectedUid == widget.uid && mounted) {
                _showSnack('The host did not admit you.', Colors.red);
                await Future.delayed(const Duration(seconds: 2));
                if (mounted) Navigator.pop(context);
              }
              return;
            }

            if (signalType == 'screen_share_started') {
              final rawUid = signal['target_uid'];
              final sharerUid = rawUid is int ? rawUid : int.tryParse(rawUid?.toString() ?? '');
              if (sharerUid != null && sharerUid != widget.uid && mounted) {
                setState(() { _someoneIsSharing = true; _screenShareUid = sharerUid; });
              }
              return;
            }
            if (signalType == 'screen_share_stopped') {
              if (mounted) setState(() { _someoneIsSharing = false; _screenShareUid = null; });
              return;
            }

            final isForMe = targetUid == null || targetUid.toString() == widget.uid.toString();
            if (!isForMe) return;

            switch (signalType) {
              case 'unmute_request': _showUnmuteRequestDialog(senderName); break;
              case 'mute':
                await _forceMute();
                if (mounted) _showSnack('You were muted by $senderName.', _theme.primary);
                break;
              case 'mute_all':
                if (!widget.isHost) await _forceMute();
                break;
              case 'chat_disabled':
                if (mounted) setState(() => _localChatDisabled = true);
                _showSnack('$senderName disabled your chat.', Colors.red);
                break;
              case 'chat_enabled':
                if (mounted) setState(() => _localChatDisabled = false);
                _showSnack('$senderName enabled your chat.', const Color(0xFF10B981));
                break;
                case 'unmute_all':
                // FIX: Broadcast unmute request to everyone
                if (!widget.isHost) {
                  _showUnmuteRequestDialog(senderName);
                }
                break;
              case 'chat_enabled_all':
                // FIX: Enable chat for everyone
                if (!widget.isHost) {
                  if (mounted) setState(() => _localChatDisabled = false);
                  _showSnack('$senderName enabled chat for everyone.', const Color(0xFF3B82F6));
                }
                break;

            }
          },
        ).subscribe();
  }

  Future<void> _forceMute() async {
    await _engine.muteLocalAudioStream(true);
    if (mounted) setState(() { isAudioOn = false; _isLocalSpeaking = false; });
    try {
      await supabase.from('meeting_participants').update({'is_muted': true})
          .eq('meeting_code', widget.channelId).eq('agora_uid', widget.uid);
    } catch (_) {}
  }

  Future<void> _sendSignal(String signalType, int? targetUid) async {
    try {
      await supabase.from('meeting_signals').insert({
        'meeting_code': widget.channelId,
        'signal_type': signalType,
        'target_uid': targetUid,
        'sender_name': widget.userName,
        'created_at': DateTime.now().toIso8601String(),
      });
    } catch (e) { debugPrint('Send signal error: $e'); }
  }

  void _showSnack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: color, duration: const Duration(seconds: 2)),
    );
  }

  // void _showUnmuteRequestDialog(String senderName) {
  //   showDialog(
  //     context: context,
  //     builder: (_) => AlertDialog(
  //       shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
  //       title: const Text('Unmute Request', style: TextStyle(fontWeight: FontWeight.bold)),
  //       content: Text('$senderName is asking you to unmute your microphone.'),
  //       actions: [
  //         TextButton(onPressed: () => Navigator.pop(context), child: const Text('Stay Muted')),
  //         ElevatedButton(
  //           style: ElevatedButton.styleFrom(
  //             backgroundColor: const Color(0xFF10B981), foregroundColor: Colors.white,
  //             shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
  //           ),
  //           onPressed: () async {
  //             Navigator.pop(context);
  //             await _engine.enableAudio();
  //             await _engine.muteLocalAudioStream(false);
  //             if (mounted) setState(() => isAudioOn = true);
  //             try {
  //               await supabase.from('meeting_participants').update({'is_muted': false})
  //                   .eq('meeting_code', widget.channelId).eq('agora_uid', widget.uid);
  //             } catch (_) {}
  //           },
  //           child: const Text('Unmute'),
  //         ),
  //       ],
  //     ),
  //   );
  // }
  
 void _showUnmuteRequestDialog(String senderName) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Unmute Request', style: TextStyle(fontWeight: FontWeight.bold)),
        content: Text('$senderName is asking you to unmute your microphone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Stay Muted')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF10B981), foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () async {
              Navigator.pop(context);
              // FIX: Correct Agora unmute sequence
              await _engine.enableAudio();                    // 1. Enable audio engine
              await _engine.muteLocalAudioStream(false);      // 2. Stop muting stream
              await _engine.setClientRole(                    // 3. Ensure broadcaster role
                role: ClientRoleType.clientRoleBroadcaster,
              );
              if (mounted) setState(() => isAudioOn = true);
              try {
                await supabase.from('meeting_participants')
                    .update({'is_muted': false})
                    .eq('meeting_code', widget.channelId)
                    .eq('agora_uid', widget.uid);
              } catch (_) {}
            },
            child: const Text('Unmute'),
          ),
        ],
      ),
    );
  }
  // ─── Participant tap overlay ──────────────────────────────────────────
  void _handleTileTap(int uid, String name) {
    if (uid == widget.uid) return;
    setState(() => _tappedUid = _tappedUid == uid ? null : uid);
  }

  Widget _buildParticipantOverlay(int uid, String name) {
    final isMuted = _remoteAudioMuted[uid] ?? false;
    final isChatBlocked = _chatDisabledUids.contains(uid);
    final avatarUrl = _remoteAvatars[uid];
 
    return GestureDetector(
      onTap: () => setState(() => _tappedUid = null),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.82),
          borderRadius: BorderRadius.circular(15),
        ),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircleAvatar(
                  radius: 26,
                  backgroundColor: _theme.primary.withOpacity(0.4),
                  backgroundImage: avatarUrl != null ? NetworkImage(avatarUrl) : null,
                  child: avatarUrl == null
                      ? Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
                          style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold))
                      : null,
                ),
                const SizedBox(height: 8),
                Text(name, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
 
                const SizedBox(height: 12),
                const Divider(color: Colors.white12, height: 1),
                Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 2),
                  child: Text('This participant', style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 9)),
                ),
 
                if (widget.isHost) ...[
                  // Per-user controls
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _overlayBtn(
                          icon: isMuted ? Icons.mic_rounded : Icons.mic_off_rounded,
                          label: isMuted ? 'Req.\nUnmute' : 'Mute',
                          color: isMuted ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                          onTap: () async {
                            setState(() => _tappedUid = null);
                            if (isMuted) {
                              await _sendSignal('unmute_request', uid);
                              _showSnack('Unmute request sent.', const Color(0xFF10B981));
                            } else {
                              await _sendSignal('mute', uid);
                            }
                          },
                        ),
                        _overlayBtn(
                          icon: isChatBlocked ? Icons.chat_bubble_rounded : Icons.speaker_notes_off_rounded,
                          label: isChatBlocked ? 'Enable\nChat' : 'Disable\nChat',
                          color: isChatBlocked ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                          onTap: () async {
                            // FIX: Capture value before setState
                            final wasBlocked = isChatBlocked;
                            setState(() {
                              _tappedUid = null;
                              wasBlocked ? _chatDisabledUids.remove(uid) : _chatDisabledUids.add(uid);
                            });
                            await _sendSignal(wasBlocked ? 'chat_enabled' : 'chat_disabled', uid);
                          },
                        ),
                      ],
                    ),
                  ),
 
                  const SizedBox(height: 8),
                  const Divider(color: Colors.white12, height: 1),
                  Padding(
                    padding: const EdgeInsets.only(top: 4, bottom: 2),
                    child: Text('All participants', style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 9)),
                  ),
 
                  // Broadcast controls
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _overlayBtn(
                          icon: Icons.volume_off_rounded,
                          label: 'Mute\nAll',
                          color: Colors.redAccent,
                          onTap: () async {
                            setState(() => _tappedUid = null);
                            await _sendSignal('mute_all', null);
                          },
                        ),
                        // FIX: New — unmute all request
                        _overlayBtn(
                          icon: Icons.volume_up_rounded,
                          label: 'Unmute\nAll',
                          color: const Color(0xFF10B981),
                          onTap: () async {
                            setState(() => _tappedUid = null);
                            await _sendSignal('unmute_all', null);
                            _showSnack('Unmute request sent to everyone.', const Color(0xFF10B981));
                          },
                        ),
                        // FIX: New — enable chat for all
                        _overlayBtn(
                          icon: Icons.chat_rounded,
                          label: 'Chat\nOn All',
                          color: const Color(0xFF3B82F6),
                          onTap: () async {
                            setState(() {
                              _tappedUid = null;
                              _chatDisabledUids.clear(); // Clear all locally
                            });
                            await _sendSignal('chat_enabled_all', null);
                            _showSnack('Chat enabled for everyone.', const Color(0xFF3B82F6));
                          },
                        ),
                      ],
                    ),
                  ),
                ] else ...[
                  _overlayBtn(
                    icon: isChatOpen ? Icons.chat_bubble_rounded : Icons.chat_bubble_outline_rounded,
                    label: isChatOpen ? 'Close\nChat' : 'Open\nChat',
                    color: _theme.secondary,
                    onTap: () {
                      setState(() {
                        _tappedUid = null;
                        isChatOpen = !isChatOpen;
                        if (isChatOpen) { _unreadCount = 0; _showTypeInfo = false; }
                      });
                      if (isChatOpen) _scrollToBottom();
                    },
                  ),
                ],
 
                const SizedBox(height: 8),
                const Text('Tap anywhere to dismiss',
                    style: TextStyle(color: Colors.white38, fontSize: 9)),
              ],
            ),
          ),
        ),
      ),
    );
  }
  Widget _overlayBtn({required IconData icon, required String label, required Color color, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              color: color.withOpacity(0.18), shape: BoxShape.circle,
              border: Border.all(color: color.withOpacity(0.5)),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(height: 4),
          Text(label, style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.w600), textAlign: TextAlign.center),
        ],
      ),
    );
  }

  // ─── Quality picker ───────────────────────────────────────────────────
  Future<void> _applyQuality(Map<String, dynamic> preset) async {
    try {
      await _engine.setVideoEncoderConfiguration(VideoEncoderConfiguration(
        dimensions: VideoDimensions(width: preset['w'] as int, height: preset['h'] as int),
        frameRate: preset['fps'] as int,
        bitrate: preset['bitrate'] as int,
      ));
      if (mounted) setState(() => _currentQuality = preset['label'] as String);
      _showSnack('Video quality set to ${preset['label']}', const Color(0xFF10B981));
    } catch (e) { debugPrint('Quality change error: $e'); }
  }

  void _showQualityPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: BoxDecoration(
          color: _theme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white12, borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 16),
            Row(children: [
              const Icon(Icons.hd_rounded, color: Colors.white70, size: 18),
              const SizedBox(width: 8),
              const Text('Video Quality', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            ]),
            const SizedBox(height: 4),
            const Text('Lower quality uses less data and improves stability.', style: TextStyle(color: Colors.white38, fontSize: 12)),
            const SizedBox(height: 16),
            ..._qualityPresets.map((preset) {
              final isSelected = _currentQuality == preset['label'];
              return GestureDetector(
                onTap: () { Navigator.pop(context); _applyQuality(preset); },
                child: Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: isSelected ? _theme.primary.withOpacity(0.2) : Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: isSelected ? _theme.primary : Colors.white12, width: isSelected ? 1.5 : 1),
                  ),
                  child: Row(
                    children: [
                      Icon(preset['icon'] as IconData, color: isSelected ? _theme.secondary : Colors.white38, size: 20),
                      const SizedBox(width: 12),
                      Expanded(child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(preset['label'] as String, style: TextStyle(color: isSelected ? Colors.white : Colors.white70, fontSize: 14, fontWeight: FontWeight.w600)),
                          Text(preset['desc'] as String, style: const TextStyle(color: Colors.white38, fontSize: 11)),
                        ],
                      )),
                      if (isSelected)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(color: _theme.primary.withOpacity(0.3), borderRadius: BorderRadius.circular(8)),
                          child: Text('Active', style: TextStyle(color: _theme.secondary, fontSize: 10, fontWeight: FontWeight.bold)),
                        ),
                    ],
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  // ─── Agora ────────────────────────────────────────────────────────────
  Future<String?> _fetchToken(int uid) async {
    try {
      final url = "$tokenServerUrl/rtc/${widget.channelId}/$uid";
      final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) return jsonDecode(response.body)['token'];
    } catch (e) { debugPrint('Token fetch error: $e'); }
    return null;
  }

  Future<void> _initializeAgora() async {
    if (mounted) setState(() { _isLoading = true; _errorMessage = null; });

    final perms = await [Permission.microphone, Permission.camera].request();
    if (perms[Permission.microphone] != PermissionStatus.granted ||
        perms[Permission.camera] != PermissionStatus.granted) {
      if (mounted) setState(() { _errorMessage = 'Camera and microphone permissions are required.'; _isLoading = false; });
      return;
    }

    final token = await _fetchToken(widget.uid);
    if (token == null) {
      if (mounted) setState(() { _errorMessage = 'Unable to connect to the server. Please try again.'; _isLoading = false; });
      return;
    }

    _engine = createAgoraRtcEngine();
    await _engine.initialize(RtcEngineContext(appId: appId, channelProfile: ChannelProfileType.channelProfileCommunication));
    await _engine.enableVideo();
    await _engine.enableAudio();
    await _engine.startPreview();
    await _engine.setVideoEncoderConfiguration(
      const VideoEncoderConfiguration(dimensions: VideoDimensions(width: 640, height: 480), frameRate: 15, bitrate: 0),
    );
    await _engine.setAudioProfile(profile: AudioProfileType.audioProfileDefault, scenario: AudioScenarioType.audioScenarioChatroom);
    await _engine.enableAudioVolumeIndication(interval: 200, smooth: 3, reportVad: true);

    _engine.registerEventHandler(RtcEngineEventHandler(
      onJoinChannelSuccess: (connection, elapsed) async {
        if (mounted) setState(() { _localUserJoined = true; _isLoading = false; });
        await _registerParticipantAndLog();
        _subscribeToParticipants();
        if (widget.meetingType == 'class' && !widget.isHost) {
          await _engine.muteLocalAudioStream(true);
          if (mounted) setState(() => isAudioOn = false);
        }
      },
      onUserJoined: (connection, remoteUid, elapsed) {
        if (mounted) setState(() {
          if (!_remoteUids.contains(remoteUid)) {
            _remoteUids.add(remoteUid);
            _remoteSpeaking[remoteUid] = false;
            _remoteAudioMuted[remoteUid] = false;
            _remoteVideoMuted[remoteUid] = false;
            _remoteNames[remoteUid] = 'Joining...';
            _remoteAvatars[remoteUid] = null;
          }
        });
        _fetchRemoteParticipantInfo(remoteUid);
      },
      onUserOffline: (connection, remoteUid, reason) async {
        if (mounted && _screenShareUid == remoteUid) setState(() { _screenShareUid = null; _someoneIsSharing = false; });
        if (mounted && _tappedUid == remoteUid) setState(() => _tappedUid = null);
        try {
          await supabase.from('meeting_participants').update({'left_at': DateTime.now().toIso8601String()})
              .eq('meeting_code', widget.channelId).eq('agora_uid', remoteUid);
          await supabase.from('meeting_events').insert({
            'meeting_code': widget.channelId,
            'event_type': 'user_left',
            'actor_name': _remoteNames[remoteUid] ?? 'User $remoteUid',
            'created_at': DateTime.now().toIso8601String(),
          });
        } catch (e) { debugPrint('Leave tracking error: $e'); }
        if (mounted) setState(() {
          _remoteUids.remove(remoteUid);
          _remoteSpeaking.remove(remoteUid);
          _remoteAudioMuted.remove(remoteUid);
          _remoteVideoMuted.remove(remoteUid);
          _remoteNames.remove(remoteUid);
          _remoteAvatars.remove(remoteUid);
          _chatDisabledUids.remove(remoteUid);
        });
      },
      onUserMuteAudio: (connection, remoteUid, muted) {
        if (mounted) setState(() { _remoteAudioMuted[remoteUid] = muted; if (muted) _remoteSpeaking[remoteUid] = false; });
      },
      onUserMuteVideo: (connection, remoteUid, muted) {
        if (mounted) setState(() => _remoteVideoMuted[remoteUid] = muted);
      },
      onAudioVolumeIndication: (connection, speakers, speakerNumber, totalVolume) {
        bool localSpeaking = false;
        Map<int, bool> updated = {for (var uid in _remoteUids) uid: false};
        for (var s in speakers) {
          if (s.uid == 0 && (s.volume ?? 0) > 30 && isAudioOn) localSpeaking = true;
          if (_remoteUids.contains(s.uid) && (s.volume ?? 0) > 30 && !(_remoteAudioMuted[s.uid] ?? false)) updated[s.uid!] = true;
        }
        if (mounted) setState(() { _isLocalSpeaking = localSpeaking; _remoteSpeaking = updated; });
      },
      onTokenPrivilegeWillExpire: (connection, token) async {
        final newToken = await _fetchToken(widget.uid);
        if (newToken != null) await _engine.renewToken(newToken);
      },
      onError: (err, msg) => debugPrint('Agora error: $err - $msg'),
    ));

    await _engine.joinChannel(
      token: token,
      channelId: widget.channelId,
      uid: widget.uid,
      options: ChannelMediaOptions(
        clientRoleType: ClientRoleType.clientRoleBroadcaster,
        channelProfile: ChannelProfileType.channelProfileCommunication,
        publishCameraTrack: true,
        publishMicrophoneTrack: widget.meetingType == 'class' ? widget.isHost : true,
        autoSubscribeAudio: true,
        autoSubscribeVideo: true,
      ),
    );
  }

  // ─── Chat ─────────────────────────────────────────────────────────────
  Future<void> _initChat() async {
    try {
      final code = widget.channelId.toLowerCase().trim();
      var meeting = await supabase.from('meetings').select('id').eq('meeting_code', code).maybeSingle();
      if (meeting == null && _localUserId != null) {
        try {
          meeting = await supabase.from('meetings').insert({
            'meeting_code': code, 'meeting_name': 'Meeting $code',
            'host_id': _localUserId!, 'host_name': widget.userName,
            'is_active': true, 'meeting_type': widget.meetingType,
            'created_at': DateTime.now().toIso8601String(),
          }).select('id').single();
        } catch (_) {
          meeting = await supabase.from('meetings').select('id').eq('meeting_code', code).maybeSingle();
        }
      }
      if (meeting == null) return;
      _meetingDbId = meeting['id']?.toString();
      if (_meetingDbId != null) { await _loadMessages(); _subscribeToMessages(); }
    } catch (e) { debugPrint('Chat init error: $e'); }
  }

  Future<void> _loadMessages() async {
    if (_meetingDbId == null) return;
    try {
      final msgs = await supabase.from('messages').select().eq('meeting_id', _meetingDbId!).order('created_at', ascending: true);
      if (mounted) { setState(() => _messages = List<Map<String, dynamic>>.from(msgs)); _scrollToBottom(); }
    } catch (e) { debugPrint('Load messages error: $e'); }
  }

  void _subscribeToMessages() {
    if (_meetingDbId == null) return;
    _chatChannel?.unsubscribe();
    _chatChannel = supabase.channel('meeting_chat_${widget.channelId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          callback: (payload) {
            if (!mounted) return;
            final newMsg = payload.newRecord;
            if (newMsg['meeting_id']?.toString() != _meetingDbId) return;
            final optimisticIdx = _messages.indexWhere(
              (m) => m['_optimistic'] == true && m['text']?.toString() == newMsg['text']?.toString() && m['sender_name']?.toString() == newMsg['sender_name']?.toString(),
            );
            final exists = _messages.any((m) => m['_optimistic'] != true && m['id']?.toString() == newMsg['id']?.toString());
            if (exists) return;
            setState(() {
              if (optimisticIdx != -1) { _messages[optimisticIdx] = newMsg; }
              else {
                _messages.add(newMsg);
                if (!isChatOpen && newMsg['sender_name']?.toString() != widget.userName) _unreadCount++;
              }
            });
            _scrollToBottom();
          },
        ).subscribe();
  }

  Future<void> _sendMessage() async {
    if (widget.meetingType == 'class' && !widget.isHost) {
      _showSnack('Class mode: Only the host can send messages.', _theme.primary);
      return;
    }
    if (_localChatDisabled) {
      _showSnack('The host has disabled your chat.', Colors.red);
      return;
    }
    final text = _chatController.text.trim();
    if (text.isEmpty) return;
    if (_meetingDbId == null) { await _initChat(); if (_meetingDbId == null) return; }
    _chatController.clear();
    final tempId = 'temp_${DateTime.now().millisecondsSinceEpoch}';
    setState(() => _messages.add({
      'id': tempId, 'meeting_id': _meetingDbId, 'text': text,
      'user_id': _localUserId, 'sender_name': widget.userName,
      'sender_avatar': _localAvatarUrl, 'created_at': DateTime.now().toIso8601String(), '_optimistic': true,
    }));
    _scrollToBottom();
    try {
      await supabase.from('messages').insert({
        'meeting_id': _meetingDbId, 'text': text, 'user_id': _localUserId,
        'sender_name': widget.userName, 'sender_avatar': _localAvatarUrl,
        'created_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      debugPrint('Send message error: $e');
      if (mounted) {
        setState(() => _messages.removeWhere((m) => m['id'] == tempId));
        _showSnack('Failed to send message. Please try again.', Colors.red);
      }
    }
  }

  Future<void> _toggleCamera() async {
    final newState = !isVideoOn;
    setState(() => isVideoOn = newState);
    if (newState) { await _engine.enableLocalVideo(true); await _engine.startPreview(); await _engine.muteLocalVideoStream(false); }
    else { await _engine.muteLocalVideoStream(true); await _engine.enableLocalVideo(false); await _engine.stopPreview(); }
  }

  Future<void> _startScreenShare() async {
    try {
      await _engine.startScreenCapture(const ScreenCaptureParameters2(captureAudio: false, captureVideo: true));
      await _engine.updateChannelMediaOptions(const ChannelMediaOptions(
        publishScreenTrack: true, publishCameraTrack: false, publishMicrophoneTrack: true,
        clientRoleType: ClientRoleType.clientRoleBroadcaster,
        channelProfile: ChannelProfileType.channelProfileCommunication,
      ));
      try {
        await supabase.from('meeting_signals').insert({
          'meeting_code': widget.channelId, 'signal_type': 'screen_share_started',
          'target_uid': widget.uid, 'sender_name': widget.userName, 'created_at': DateTime.now().toIso8601String(),
        });
        await supabase.from('meetings').update({'is_screen_sharing': true, 'current_speaker': widget.userName}).eq('meeting_code', widget.channelId);
        await supabase.from('meeting_events').insert({'meeting_code': widget.channelId, 'event_type': 'screen_share_started', 'actor_name': widget.userName, 'created_at': DateTime.now().toIso8601String()});
      } catch (_) {}
      if (mounted) setState(() { isScreenSharing = true; _someoneIsSharing = true; _screenShareUid = widget.uid; });
    } catch (e) { _showSnack('Screen share failed: $e', Colors.red); }
  }

  Future<void> _stopScreenShare() async {
    try {
      await _engine.stopScreenCapture();
      await _engine.updateChannelMediaOptions(const ChannelMediaOptions(
        publishScreenTrack: false, publishCameraTrack: true, publishMicrophoneTrack: true,
        clientRoleType: ClientRoleType.clientRoleBroadcaster,
        channelProfile: ChannelProfileType.channelProfileCommunication,
      ));
      await _engine.enableLocalVideo(true);
      await _engine.startPreview();
      try {
        await supabase.from('meeting_signals').insert({'meeting_code': widget.channelId, 'signal_type': 'screen_share_stopped', 'target_uid': null, 'sender_name': widget.userName, 'created_at': DateTime.now().toIso8601String()});
        await supabase.from('meeting_events').insert({'meeting_code': widget.channelId, 'event_type': 'screen_share_stopped', 'actor_name': widget.userName, 'created_at': DateTime.now().toIso8601String()});
        await supabase.from('meetings').update({'is_screen_sharing': false}).eq('meeting_code', widget.channelId);
      } catch (_) {}
      if (mounted) setState(() { isScreenSharing = false; _someoneIsSharing = false; _screenShareUid = null; });
    } catch (e) { debugPrint('Stop screen share error: $e'); }
  }

  Future<void> _endCall() async {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Leave Meeting?', style: TextStyle(fontWeight: FontWeight.bold)),
        content: const Text('Chat messages will be deleted when you leave.', style: TextStyle(color: Colors.black54)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            onPressed: () async { Navigator.pop(context); await _cleanupAndLeave(); },
            child: const Text('Leave'),
          ),
        ],
      ),
    );
  }

Future<void> _cleanupAndLeave() async {
    try {
      if (isScreenSharing) await _stopScreenShare();
 
      await supabase.from('meeting_participants')
          .update({'left_at': DateTime.now().toIso8601String()})
          .eq('meeting_code', widget.channelId)
          .eq('agora_uid', widget.uid);
 
      // FIX: Save message count BEFORE deleting messages
      if (widget.isHost && _meetingDbId != null) {
        try {
          final msgs = await supabase.from('messages').select('id').eq('meeting_id', _meetingDbId!);
          final count = (msgs as List).length;
          await supabase.from('meetings')
              .update({'message_count': count})
              .eq('meeting_code', widget.channelId);
        } catch (_) {}
        await supabase.from('messages').delete().eq('meeting_id', _meetingDbId!);
      }
 
      final duration = DateTime.now().difference(_joinTime).inMinutes;
      await supabase.from('meetings').update({
        'is_active': false,
        'ended_at': DateTime.now().toIso8601String(),
        'duration_minutes': duration,
      }).eq('meeting_code', widget.channelId);
 
      await supabase.from('meeting_events').insert({
        'meeting_code': widget.channelId,
        'event_type': widget.isHost ? 'ended' : 'user_left',
        'actor_name': widget.userName,
        'created_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      debugPrint('Cleanup error: $e');
    }
 
    await _engine.leaveChannel();
    if (mounted) Navigator.pop(context);
  }
 

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 150), () {
      if (_chatScrollController.hasClients) {
        _chatScrollController.animateTo(_chatScrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      }
    });
  }

  @override
  void dispose() {
    _waitingChannel?.unsubscribe();
    _chatChannel?.unsubscribe();
    _participantsChannel?.unsubscribe();
    _signalChannel?.unsubscribe();
    _chatController.dispose();
    _chatScrollController.dispose();
    _engine.leaveChannel();
    _engine.release();
    super.dispose();
  }

  // ─── BUILD ────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async { _endCall(); return false; },
      child: Scaffold(
        backgroundColor: _theme.background,
        body: SafeArea(
          child: _isLoading
              ? _buildLoadingScreen()
              : _errorMessage != null
                  ? _buildErrorScreen()
                  : Stack(
                      children: [
                        Column(
                          children: [
                            _buildHeader(),
                            Expanded(child: _buildVideoGrid()),
                            _buildControls(),
                          ],
                        ),
                        AnimatedPositioned(
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeInOut,
                          right: isChatOpen ? 0 : -MediaQuery.of(context).size.width,
                          top: 0, bottom: 0,
                          width: MediaQuery.of(context).size.width * 0.85,
                          child: _buildChatPanel(),
                        ),
                        if (_showTypeInfo && !isChatOpen)
                          Positioned(top: 56, left: 12, right: 12, child: _buildTypeInfoPanel()),
                        if (widget.meetingType == 'class' && !widget.isHost && !isChatOpen && !_showTypeInfo)
                          Positioned(
                            top: 56, left: 0, right: 0,
                            child: Center(
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(color: _theme.primary.withOpacity(0.9), borderRadius: BorderRadius.circular(20)),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.school_rounded, color: Colors.white, size: 13),
                                    SizedBox(width: 6),
                                    Text('Class mode — Host controls the microphone',
                                        style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w500)),
                                  ],
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
        ),
      ),
    );
  }

  // ─── THEMED HEADER ────────────────────────────────────────────────────
  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [_theme.headerStart, _theme.headerEnd],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
      ),
      child: Row(
        children: [
          // Meeting ID pill
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(color: Colors.white.withOpacity(0.08), borderRadius: BorderRadius.circular(20)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.meeting_room_outlined, color: Colors.white54, size: 13),
                const SizedBox(width: 4),
                Text(widget.channelId, style: const TextStyle(color: Colors.white70, fontSize: 11, letterSpacing: 0.5)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Type badge — tappable
          GestureDetector(
            onTap: () => setState(() => _showTypeInfo = !_showTypeInfo),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                color: _theme.primary.withOpacity(0.25),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _theme.secondary.withOpacity(0.5)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_theme.emoji, style: const TextStyle(fontSize: 11)),
                  const SizedBox(width: 4),
                  Text(_theme.label, style: TextStyle(color: _theme.secondary, fontSize: 11, fontWeight: FontWeight.w600)),
                  const SizedBox(width: 3),
                  Icon(Icons.info_outline_rounded, color: _theme.secondary.withOpacity(0.7), size: 11),
                ],
              ),
            ),
          ),
          const Spacer(),
          if (_someoneIsSharing)
            Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.2), borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.orange.withOpacity(0.5)),
              ),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.screen_share_rounded, color: Colors.orange, size: 11),
                SizedBox(width: 4),
                Text('Presenting', style: TextStyle(color: Colors.orange, fontSize: 10, fontWeight: FontWeight.w600)),
              ]),
            ),
          // Participant count
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(color: Colors.white.withOpacity(0.08), borderRadius: BorderRadius.circular(20)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.people_outline, color: Colors.white70, size: 13),
                const SizedBox(width: 4),
                Text('${_remoteUids.length + 1}', style: const TextStyle(color: Colors.white70, fontSize: 11)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── TYPE INFO PANEL ──────────────────────────────────────────────────
  Widget _buildTypeInfoPanel() {
    final features = _getTypeFeatures();
    return Container(
      decoration: BoxDecoration(
        color: _theme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _theme.primary.withOpacity(0.4)),
        boxShadow: [BoxShadow(color: _theme.primary.withOpacity(0.2), blurRadius: 16, offset: const Offset(0, 4))],
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(color: _theme.primary.withOpacity(0.2), borderRadius: BorderRadius.circular(8)),
                child: Text(_theme.emoji, style: const TextStyle(fontSize: 16)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${_theme.label} Mode', style: TextStyle(color: _theme.secondary, fontSize: 13, fontWeight: FontWeight.bold)),
                    Text(_theme.tagline, style: const TextStyle(color: Colors.white38, fontSize: 10)),
                  ],
                ),
              ),
              GestureDetector(
                onTap: () => setState(() => _showTypeInfo = false),
                child: const Icon(Icons.close_rounded, color: Colors.white38, size: 18),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(color: Colors.white12, height: 1),
          const SizedBox(height: 10),
          ...features.map((f) => Padding(
            padding: const EdgeInsets.only(bottom: 7),
            child: Row(
              children: [
                Icon(f['icon'] as IconData, color: _theme.secondary, size: 14),
                const SizedBox(width: 8),
                Expanded(child: Text(f['label'] as String, style: const TextStyle(color: Colors.white70, fontSize: 12))),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: _theme.primary.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text('ON', style: TextStyle(color: _theme.secondary, fontSize: 9, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          )),
          if (widget.meetingType == 'class') ...[
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () {
                setState(() => _showTypeInfo = false);
                Navigator.push(context, MaterialPageRoute(
                  builder: (_) => MeetingTimelineScreen(meetingCode: widget.channelId, meetingName: '${widget.channelId} — Live', meetingType: widget.meetingType),
                ));
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 9),
                decoration: BoxDecoration(
                  color: _theme.primary.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _theme.primary.withOpacity(0.35)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.timeline_rounded, color: _theme.secondary, size: 14),
                    const SizedBox(width: 6),
                    Text('View Attendance & Timeline', style: TextStyle(color: _theme.secondary, fontSize: 12, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  List<Map<String, dynamic>> _getTypeFeatures() {
    switch (widget.meetingType) {
      case 'class':
        return [
          {'icon': Icons.record_voice_over_rounded, 'label': 'Attendance tracked'},
          {'icon': Icons.mic_off_rounded, 'label': 'Students join muted'},
          {'icon': Icons.chat_bubble_outline_rounded, 'label': 'Chat moderated by host'},
          {'icon': Icons.timeline_rounded, 'label': 'Join/leave timeline recorded'},
        ];
      case 'casual':
        return [
          {'icon': Icons.mic_rounded, 'label': 'Open mic for everyone'},
          {'icon': Icons.chat_rounded, 'label': 'Open chat for all'},
          {'icon': Icons.screen_share_rounded, 'label': 'Screen share enabled'},
          {'icon': Icons.video_call_rounded, 'label': 'No camera restrictions'},
        ];
      default:
        return [
          {'icon': Icons.screen_share_rounded, 'label': 'Screen share priority'},
          {'icon': Icons.chat_rounded, 'label': 'Team chat enabled'},
          {'icon': Icons.mic_rounded, 'label': 'Open mic for all'},
          {'icon': Icons.people_rounded, 'label': 'Collaboration mode'},
        ];
    }
  }

  Widget _buildLoadingScreen() {
    return Container(
      color: _theme.background,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: _theme.primary.withOpacity(0.15),
                shape: BoxShape.circle,
                border: Border.all(color: _theme.primary.withOpacity(0.3), width: 1.5),
              ),
              child: Text(_theme.emoji, style: const TextStyle(fontSize: 36)),
            ),
            const SizedBox(height: 20),
            CircularProgressIndicator(color: _theme.secondary, strokeWidth: 2.5),
            const SizedBox(height: 20),
            Text('Joining ${_theme.tagline}...', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Text(widget.channelId, style: const TextStyle(color: Colors.white38, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorScreen() {
    return Container(
      color: _theme.background,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(color: Colors.red.withOpacity(0.15), shape: BoxShape.circle),
                child: const Icon(Icons.wifi_off_rounded, color: Colors.redAccent, size: 48),
              ),
              const SizedBox(height: 20),
              const Text('Connection Failed', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(_errorMessage ?? 'An unexpected error occurred.', style: const TextStyle(color: Colors.white54, fontSize: 14), textAlign: TextAlign.center),
              const SizedBox(height: 32),
              ElevatedButton.icon(
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Try Again'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _theme.primary, foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: _initializeAgora,
              ),
              const SizedBox(height: 12),
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Go Back', style: TextStyle(color: Colors.white38))),
            ],
          ),
        ),
      ),
    );
  }

  // ─── VIDEO GRID ───────────────────────────────────────────────────────
Widget _buildVideoGrid() {
    if (isScreenSharing) return _buildScreenSharePresenterView();
    if (_someoneIsSharing && _screenShareUid != null && _screenShareUid != widget.uid) {
      return _buildScreenShareViewerView(_screenShareUid!);
    }
 
    final views = <Widget>[
      _videoTile(
        uid: widget.uid, label: widget.userName,
        speaking: _isLocalSpeaking && isAudioOn, isLocal: true,
        isVideoOn: isVideoOn, avatarUrl: _localAvatarUrl, isMuted: !isAudioOn,
        videoWidget: (_localUserJoined && isVideoOn)
            ? AgoraVideoView(controller: VideoViewController(rtcEngine: _engine, canvas: const VideoCanvas(uid: 0)))
            : null,
      ),
      ..._remoteUids.map((uid) => _videoTile(
        uid: uid, label: _remoteNames[uid] ?? 'Joining...',
        speaking: (_remoteSpeaking[uid] ?? false) && !(_remoteAudioMuted[uid] ?? false),
        isLocal: false, isVideoOn: !(_remoteVideoMuted[uid] ?? false),
        avatarUrl: _remoteAvatars[uid], isMuted: _remoteAudioMuted[uid] ?? false,
        videoWidget: (_remoteVideoMuted[uid] ?? false) ? null
            : AgoraVideoView(controller: VideoViewController.remote(
                rtcEngine: _engine, canvas: VideoCanvas(uid: uid),
                connection: RtcConnection(channelId: widget.channelId),
              )),
      )),
    ];
 
    final total = views.length;
 
    if (total == 1) {
      return Padding(padding: const EdgeInsets.all(8), child: views[0]);
    }
 
    if (total == 2) {
      return Column(
        children: views.map((v) => Expanded(
          child: Padding(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), child: v),
        )).toList(),
      );
    }
 
    // FIX: 3+ users — use LayoutBuilder to avoid overflow
    // 3 users: one full-width top + two bottom
    if (total == 3) {
      return Column(
        children: [
          Expanded(
            flex: 1,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
              child: views[0],
            ),
          ),
          Expanded(
            flex: 1,
            child: Row(
              children: [
                Expanded(child: Padding(padding: const EdgeInsets.fromLTRB(8, 4, 4, 8), child: views[1])),
                Expanded(child: Padding(padding: const EdgeInsets.fromLTRB(4, 4, 8, 8), child: views[2])),
              ],
            ),
          ),
        ],
      );
    }
 
    // 4+ users: 2-column scrollable grid
    // FIX: Use LayoutBuilder + GridView to avoid overflow
    return LayoutBuilder(
      builder: (context, constraints) {
        // Determine rows and item height
        final crossCount = 2;
        final itemHeight = constraints.maxHeight / ((total / crossCount).ceil());
        final clampedHeight = itemHeight.clamp(120.0, 280.0);
 
        return GridView.builder(
          physics: total <= 4
              ? const NeverScrollableScrollPhysics() // No scroll for 4 users
              : const ClampingScrollPhysics(),       // Scroll for 5+
          padding: const EdgeInsets.all(8),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossCount,
            childAspectRatio: constraints.maxWidth / 2 / clampedHeight,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
          ),
          itemCount: total,
          itemBuilder: (_, i) => views[i],
        );
      },
    );
  }
 
 
  Widget _buildScreenSharePresenterView() {
    return Column(
      children: [
        Expanded(
          flex: 3,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.orange.withOpacity(0.7), width: 2),
                boxShadow: [BoxShadow(color: Colors.orange.withOpacity(0.15), blurRadius: 16)],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    AgoraVideoView(controller: VideoViewController(
                      rtcEngine: _engine,
                      canvas: const VideoCanvas(uid: 0, sourceType: VideoSourceType.videoSourceScreen),
                    )),
                    Positioned(top: 10, left: 10, child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(color: Colors.orange, borderRadius: BorderRadius.circular(20)),
                      child: const Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.screen_share_rounded, color: Colors.white, size: 12),
                        SizedBox(width: 5),
                        Text('You are presenting', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
                      ]),
                    )),
                  ],
                ),
              ),
            ),
          ),
        ),
        _buildParticipantStrip(excludeUid: null, showLocalCamera: true),
      ],
    );
  }

  Widget _buildScreenShareViewerView(int sharerUid) {
    final sharerName = _remoteNames[sharerUid] ?? 'Participant';
    return Column(
      children: [
        Expanded(
          flex: 3,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _theme.secondary.withOpacity(0.6), width: 2),
                boxShadow: [BoxShadow(color: _theme.primary.withOpacity(0.2), blurRadius: 16)],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    AgoraVideoView(controller: VideoViewController.remote(
                      rtcEngine: _engine, canvas: VideoCanvas(uid: sharerUid),
                      connection: RtcConnection(channelId: widget.channelId),
                    )),
                    Positioned(top: 10, left: 10, child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: _theme.background.withOpacity(0.85),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white24),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.screen_share_rounded, color: _theme.secondary, size: 12),
                        const SizedBox(width: 5),
                        Text('$sharerName is presenting', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
                      ]),
                    )),
                  ],
                ),
              ),
            ),
          ),
        ),
        _buildParticipantStrip(excludeUid: sharerUid, showLocalCamera: true),
      ],
    );
  }

  Widget _buildParticipantStrip({int? excludeUid, required bool showLocalCamera}) {
    return SizedBox(
      height: 110,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
        children: [
          if (showLocalCamera)
            _smallTile(uid: widget.uid, label: 'You',
                videoWidget: isVideoOn ? AgoraVideoView(controller: VideoViewController(rtcEngine: _engine, canvas: const VideoCanvas(uid: 0))) : null),
          ..._remoteUids.where((uid) => uid != excludeUid).map((uid) => _smallTile(
            uid: uid, label: _remoteNames[uid] ?? 'User',
            videoWidget: (_remoteVideoMuted[uid] ?? false) ? null
                : AgoraVideoView(controller: VideoViewController.remote(
                    rtcEngine: _engine, canvas: VideoCanvas(uid: uid),
                    connection: RtcConnection(channelId: widget.channelId),
                  )),
          )),
        ],
      ),
    );
  }

  Widget _smallTile({required int uid, required String label, Widget? videoWidget}) {
    return Container(
      width: 80,
      margin: const EdgeInsets.only(right: 8),
      decoration: BoxDecoration(color: _theme.surface, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.white12)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(9),
        child: Stack(
          fit: StackFit.expand,
          children: [
            videoWidget != null ? videoWidget
                : Center(child: Text(label.isNotEmpty ? label[0].toUpperCase() : '?',
                    style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold))),
            Positioned(bottom: 0, left: 0, right: 0, child: Container(
              color: Colors.black54,
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w500), textAlign: TextAlign.center, overflow: TextOverflow.ellipsis),
            )),
          ],
        ),
      ),
    );
  }

  Widget _videoTile({
    required int uid, required String label, required bool speaking,
    required bool isLocal, required bool isVideoOn, required bool isMuted,
    String? avatarUrl, Widget? videoWidget,
  }) {
    final showOverlay = _tappedUid == uid && !isLocal;
    final speakingColor = widget.meetingType == 'casual' ? const Color(0xFF10B981) : _theme.secondary;

    return GestureDetector(
      onTap: !isLocal ? () => _handleTileTap(uid, label) : null,
      child: Container(
        decoration: BoxDecoration(
          color: _theme.surface,
          borderRadius: BorderRadius.circular(16),
          border: speaking
              ? Border.all(color: speakingColor, width: 2.5)
              : Border.all(color: Colors.white.withOpacity(0.06), width: 1),
          boxShadow: speaking ? [BoxShadow(color: speakingColor.withOpacity(0.3), blurRadius: 12)] : null,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(15),
          child: Stack(
            fit: StackFit.expand,
            children: [
              (isVideoOn && videoWidget != null) ? videoWidget : _buildAvatarPlaceholder(label, avatarUrl),
              Positioned(
                bottom: 0, left: 0, right: 0,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(10, 24, 10, 10),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter, end: Alignment.topCenter,
                      colors: [Colors.black87, Colors.transparent],
                    ),
                  ),
                  child: Row(
                    children: [
                      if (speaking)
                        Container(
                          margin: const EdgeInsets.only(right: 6), padding: const EdgeInsets.all(3),
                          decoration: BoxDecoration(color: speakingColor, shape: BoxShape.circle),
                          child: const Icon(Icons.mic, color: Colors.white, size: 10),
                        ),
                      Expanded(
                        child: Text(isLocal ? '${widget.userName} (You)' : label,
                            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500),
                            overflow: TextOverflow.ellipsis),
                      ),
                      if (isMuted)
                        Container(padding: const EdgeInsets.all(4), decoration: BoxDecoration(color: Colors.red.withOpacity(0.8), shape: BoxShape.circle), child: const Icon(Icons.mic_off, color: Colors.white, size: 11)),
                      if (!isVideoOn) ...[
                        const SizedBox(width: 4),
                        Container(padding: const EdgeInsets.all(4), decoration: BoxDecoration(color: Colors.red.withOpacity(0.7), shape: BoxShape.circle), child: const Icon(Icons.videocam_off, color: Colors.white, size: 11)),
                      ],
                      if (!isLocal) ...[
                        const SizedBox(width: 4),
                        const Icon(Icons.touch_app_rounded, color: Colors.white24, size: 11),
                      ],
                    ],
                  ),
                ),
              ),
              if (isLocal)
                Positioned(top: 8, right: 8, child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: _theme.primary.withOpacity(0.85), borderRadius: BorderRadius.circular(10)),
                  child: const Text('You', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                )),
              if (showOverlay)
                AnimatedOpacity(opacity: 1.0, duration: const Duration(milliseconds: 200), child: _buildParticipantOverlay(uid, label)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAvatarPlaceholder(String name, String? avatarUrl) {
    return Container(
      color: _theme.surface,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircleAvatar(
              radius: 40,
              backgroundColor: _theme.primary.withOpacity(0.3),
              backgroundImage: avatarUrl != null ? NetworkImage(avatarUrl) : null,
              child: avatarUrl == null
                  ? Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
                      style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white))
                  : null,
            ),
            const SizedBox(height: 8),
            Text(name, style: const TextStyle(color: Colors.white60, fontSize: 13)),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: Colors.white.withOpacity(0.08), borderRadius: BorderRadius.circular(20)),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.videocam_off, color: Colors.white38, size: 11),
                SizedBox(width: 4),
                Text('Camera off', style: TextStyle(color: Colors.white38, fontSize: 10)),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  // ─── THEMED CONTROLS ─────────────────────────────────────────────────
  Widget _buildControls() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [_theme.controlBar, _theme.surface],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(top: BorderSide(color: _theme.primary.withOpacity(0.2))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _controlBtn(
            icon: isAudioOn ? Icons.mic_rounded : Icons.mic_off_rounded,
            label: isAudioOn ? 'Mute' : 'Unmute',
            activeColor: Colors.white.withOpacity(0.1),
            inactiveColor: Colors.red.withOpacity(0.25),
            isActive: isAudioOn,
            iconColor: isAudioOn ? Colors.white : Colors.redAccent,
            onTap: () async {
              if (widget.meetingType == 'class' && !widget.isHost) {
                _showSnack('Class mode: The host controls your microphone.', _theme.primary);
                return;
              }
              final shouldMute = isAudioOn;
              setState(() { isAudioOn = !isAudioOn; if (!isAudioOn) _isLocalSpeaking = false; });
              await _engine.muteLocalAudioStream(shouldMute);
              try { await supabase.from('meeting_participants').update({'is_muted': !isAudioOn}).eq('meeting_code', widget.channelId).eq('agora_uid', widget.uid); } catch (_) {}
            },
          ),
          _controlBtn(
            icon: isVideoOn ? Icons.videocam_rounded : Icons.videocam_off_rounded,
            label: isVideoOn ? 'Cam Off' : 'Cam On',
            activeColor: Colors.white.withOpacity(0.1),
            inactiveColor: Colors.red.withOpacity(0.25),
            isActive: isVideoOn, iconColor: isVideoOn ? Colors.white : Colors.redAccent,
            onTap: _toggleCamera,
          ),
          _controlBtn(
            icon: Icons.flip_camera_ios_rounded, label: 'Flip',
            activeColor: Colors.white.withOpacity(0.1), inactiveColor: Colors.white.withOpacity(0.1),
            isActive: true, iconColor: Colors.white,
            onTap: () async { await _engine.switchCamera(); setState(() => isFrontCamera = !isFrontCamera); },
          ),
          _controlBtn(
            icon: Icons.hd_rounded, label: _currentQuality,
            activeColor: Colors.white.withOpacity(0.1), inactiveColor: Colors.white.withOpacity(0.1),
            isActive: true, iconColor: Colors.white70,
            onTap: _showQualityPicker,
          ),
          _controlBtn(
            icon: isScreenSharing ? Icons.stop_screen_share_rounded : Icons.screen_share_rounded,
            label: isScreenSharing ? 'Stop' : 'Present',
            activeColor: Colors.orange.withOpacity(0.25), inactiveColor: Colors.white.withOpacity(0.1),
            isActive: isScreenSharing, iconColor: isScreenSharing ? Colors.orange : Colors.white,
            onTap: isScreenSharing ? _stopScreenShare : _startScreenShare,
          ),
          Stack(
            clipBehavior: Clip.none,
            children: [
              _controlBtn(
                icon: Icons.chat_bubble_outline_rounded, label: 'Chat',
                activeColor: _theme.primary.withOpacity(0.35), inactiveColor: Colors.white.withOpacity(0.1),
                isActive: isChatOpen, iconColor: isChatOpen ? _theme.secondary : Colors.white,
                onTap: () {
                  setState(() {
                    isChatOpen = !isChatOpen;
                    if (isChatOpen) { _unreadCount = 0; _showTypeInfo = false; }
                  });
                  if (isChatOpen) _scrollToBottom();
                },
              ),
              if (_unreadCount > 0)
                Positioned(top: -4, right: -4, child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                  child: Text('$_unreadCount', style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                )),
            ],
          ),
          // Waiting room badge — host only
          if (widget.isHost && _waitingUsers.isNotEmpty)
            Stack(
              clipBehavior: Clip.none,
              children: [
                GestureDetector(
                  onTap: _showWaitingRoomPanel,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(11),
                        decoration: BoxDecoration(
                          color: Colors.orange.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(13),
                          border: Border.all(color: Colors.orange.withOpacity(0.5)),
                        ),
                        child: const Icon(Icons.people_outline_rounded, color: Colors.orange, size: 20),
                      ),
                      const SizedBox(height: 4),
                      const Text('Waiting', style: TextStyle(color: Colors.orange, fontSize: 10)),
                    ],
                  ),
                ),
                Positioned(
                  top: -4, right: -4,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                    child: Text('${_waitingUsers.length}',
                        style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          GestureDetector(
            onTap: _endCall,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
                  decoration: BoxDecoration(
                    color: Colors.red,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [BoxShadow(color: Colors.red.withOpacity(0.4), blurRadius: 8, offset: const Offset(0, 3))],
                  ),
                  child: const Icon(Icons.call_end_rounded, color: Colors.white, size: 22),
                ),
                const SizedBox(height: 4),
                const Text('End', style: TextStyle(color: Colors.white54, fontSize: 10)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _controlBtn({
    required IconData icon, required String label,
    required Color activeColor, required Color inactiveColor,
    required bool isActive, required Color iconColor, required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              color: isActive ? activeColor : inactiveColor,
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: Colors.white.withOpacity(0.06)),
            ),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(color: Colors.white54, fontSize: 10)),
        ],
      ),
    );
  }

  // ─── THEMED CHAT PANEL ────────────────────────────────────────────────
  Widget _buildChatPanel() {
    final chatInputDisabled = (widget.meetingType == 'class' && !widget.isHost) || _localChatDisabled;

    return Container(
      decoration: BoxDecoration(
        color: _theme.surface,
        borderRadius: const BorderRadius.only(topLeft: Radius.circular(20), bottomLeft: Radius.circular(20)),
        boxShadow: [BoxShadow(color: _theme.primary.withOpacity(0.2), blurRadius: 20, offset: const Offset(-4, 0))],
        border: Border(left: BorderSide(color: _theme.primary.withOpacity(0.2))),
      ),
      child: Column(
        children: [
          // Chat header
          Container(
            padding: const EdgeInsets.fromLTRB(16, 16, 8, 12),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [_theme.headerStart, _theme.headerEnd]),
              borderRadius: const BorderRadius.only(topLeft: Radius.circular(20)),
            ),
            child: Row(
              children: [
                Icon(Icons.chat_bubble_outline_rounded, color: _theme.secondary, size: 18),
                const SizedBox(width: 8),
                Text('Meeting Chat', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                if (widget.meetingType == 'class' || _localChatDisabled) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: _localChatDisabled ? Colors.red.withOpacity(0.2) : _theme.primary.withOpacity(0.25),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(_localChatDisabled ? 'Disabled' : 'Moderated',
                        style: TextStyle(color: _localChatDisabled ? Colors.redAccent : _theme.secondary, fontSize: 9)),
                  ),
                ],
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: Colors.white54, size: 20),
                  onPressed: () => setState(() => isChatOpen = false),
                ),
              ],
            ),
          ),
          Expanded(
            child: _messages.isEmpty
                ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(Icons.chat_bubble_outline, color: _theme.primary.withOpacity(0.2), size: 40),
                    const SizedBox(height: 10),
                    const Text('No messages yet.\nSay hello!', textAlign: TextAlign.center, style: TextStyle(color: Colors.white24, fontSize: 13)),
                  ]))
                : ListView.builder(
                    controller: _chatScrollController,
                    padding: const EdgeInsets.all(12),
                    itemCount: _messages.length,
                    itemBuilder: (_, i) {
                      final msg = _messages[i];
                      final isMe = msg['sender_name'] == widget.userName;
                      final showSenderInfo = i == 0 || _messages[i - 1]['sender_name'] != msg['sender_name'];
                      return _buildMessageBubble(msg, isMe, showSenderInfo);
                    },
                  ),
          ),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [_theme.headerEnd, _theme.surface]),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: _theme.primary.withOpacity(0.3),
                  backgroundImage: _localAvatarUrl != null ? NetworkImage(_localAvatarUrl!) : null,
                  child: _localAvatarUrl == null
                      ? Text(widget.userName.isNotEmpty ? widget.userName[0].toUpperCase() : '?',
                          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold))
                      : null,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _chatController,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    maxLines: null,
                    textInputAction: TextInputAction.send,
                    enabled: !chatInputDisabled,
                    onSubmitted: (_) => _sendMessage(),
                    decoration: InputDecoration(
                      hintText: _localChatDisabled ? 'Chat has been disabled by the host'
                          : (widget.meetingType == 'class' && !widget.isHost) ? 'Chat is moderated — host only'
                          : 'Type a message...',
                      hintStyle: const TextStyle(color: Colors.white24),
                      filled: true,
                      fillColor: chatInputDisabled ? Colors.white.withOpacity(0.03) : Colors.white.withOpacity(0.08),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: chatInputDisabled ? null : _sendMessage,
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: chatInputDisabled ? Colors.white12 : _theme.primary,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.send_rounded, color: chatInputDisabled ? Colors.white24 : Colors.white, size: 18),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(Map<String, dynamic> msg, bool isMe, bool showSenderInfo) {
    final senderName = msg['sender_name'] ?? 'User';
    final senderAvatar = msg['sender_avatar'] as String?;
    final isOptimistic = msg['_optimistic'] == true;
    final bubbleColor = isMe ? _theme.primary : _theme.surface.withOpacity(1.0);

    Widget avatarWidget = CircleAvatar(
      radius: 14,
      backgroundColor: _theme.primary.withOpacity(0.3),
      backgroundImage: senderAvatar != null ? NetworkImage(senderAvatar) : null,
      child: senderAvatar == null
          ? Text(senderName.isNotEmpty ? senderName[0].toUpperCase() : '?',
              style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold))
          : null,
    );

    return Padding(
      padding: EdgeInsets.only(bottom: 2, top: showSenderInfo ? 10 : 2),
      child: Row(
        mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMe) ...[showSenderInfo ? avatarWidget : const SizedBox(width: 28), const SizedBox(width: 6)],
          Column(
            crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              if (showSenderInfo && !isMe)
                Padding(
                  padding: const EdgeInsets.only(left: 4, bottom: 3),
                  child: Text(senderName, style: TextStyle(color: _theme.secondary, fontSize: 11, fontWeight: FontWeight.w600)),
                ),
              Container(
                constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.52),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: isMe ? bubbleColor.withOpacity(isOptimistic ? 0.6 : 1.0) : _theme.background,
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(14), topRight: const Radius.circular(14),
                    bottomLeft: Radius.circular(isMe ? 14 : 3), bottomRight: Radius.circular(isMe ? 3 : 14),
                  ),
                  border: isMe ? null : Border.all(color: _theme.primary.withOpacity(0.2)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(child: Text(msg['text'] ?? '', style: const TextStyle(color: Colors.white, fontSize: 13))),
                    if (isOptimistic) ...[
                      const SizedBox(width: 6),
                      const SizedBox(width: 10, height: 10, child: CircularProgressIndicator(color: Colors.white54, strokeWidth: 1.5)),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (isMe) ...[const SizedBox(width: 6), showSenderInfo ? avatarWidget : const SizedBox(width: 28)],
        ],
      ),
    );
  }
}