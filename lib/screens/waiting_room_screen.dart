import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'meeting_screen.dart';

class WaitingRoomScreen extends StatefulWidget {
  final String meetingCode;
  final String userName;
  final int uid;
  final String meetingType;
  final String userId;

  const WaitingRoomScreen({
    super.key,
    required this.meetingCode,
    required this.userName,
    required this.uid,
    required this.meetingType,
    required this.userId,
  });

  @override
  State<WaitingRoomScreen> createState() => _WaitingRoomScreenState();
}

class _WaitingRoomScreenState extends State<WaitingRoomScreen> {
  final supabase = Supabase.instance.client;
  RealtimeChannel? _signalChannel;
  bool _isRejected = false;
  int _waitingSeconds = 0;
  Timer? _timer;
  static const int _maxWaitSeconds = 120; // 2 minute max wait

  @override
  void initState() {
    super.initState();
    _subscribeToSignals();
    _startTimer();
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() => _waitingSeconds++);

      // 2 minute ke baad auto reject
      if (_waitingSeconds >= _maxWaitSeconds) {
        t.cancel();
        _handleTimeout();
      }
    });
  }

  void _handleTimeout() {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Request Timed Out'),
        content: const Text('Host did not respond. Please try again later.'),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2563EB),
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(context);
            },
            child: const Text('Go Back'),
          ),
        ],
      ),
    );
  }

  void _subscribeToSignals() {
    _signalChannel = supabase
        .channel('wait_signal_${widget.meetingCode}_${widget.uid}')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'meeting_signals',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'meeting_code',
            value: widget.meetingCode,
          ),
          callback: (payload) {
            final signal = payload.newRecord;
            final targetUid = signal['target_uid'];
            final signalType = signal['signal_type'];

            // Sirf apna signal check karo
            if (targetUid != widget.uid) return;

            if (signalType == 'admitted') {
              _timer?.cancel();
              _joinMeeting();
            } else if (signalType == 'rejected') {
              _timer?.cancel();
              setState(() => _isRejected = true);
            }
          },
        )
        .subscribe();
  }

  void _joinMeeting() {
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => MeetingScreen(
          channelId: widget.meetingCode,
          userName: widget.userName,
          uid: widget.uid,
          meetingType: widget.meetingType,
          isHost: false,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _signalChannel?.unsubscribe();
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final remaining = _maxWaitSeconds - _waitingSeconds;
    final progress = _waitingSeconds / _maxWaitSeconds;

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: _isRejected ? _buildRejectedView() : _buildWaitingView(remaining, progress),
          ),
        ),
      ),
    );
  }

  Widget _buildWaitingView(int remaining, double progress) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Pulse animation circle
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.95, end: 1.05),
          duration: const Duration(milliseconds: 900),
          builder: (_, scale, child) => Transform.scale(scale: scale, child: child),
          child: Container(
            width: 110,
            height: 110,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF2563EB).withOpacity(0.15),
              border: Border.all(color: const Color(0xFF2563EB).withOpacity(0.4), width: 2),
            ),
            child: const Icon(Icons.hourglass_empty_rounded, color: Color(0xFF60A5FA), size: 48),
          ),
        ),
        const SizedBox(height: 32),
        const Text('Waiting for host to admit you',
            style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center),
        const SizedBox(height: 12),
        Text(widget.meetingCode,
            style: const TextStyle(color: Color(0xFF60A5FA), fontSize: 14, letterSpacing: 2, fontWeight: FontWeight.w600)),
        const SizedBox(height: 32),

        // Progress bar
        Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Time remaining', style: TextStyle(color: Colors.white38, fontSize: 12)),
                Text('${remaining}s', style: const TextStyle(color: Colors.white60, fontSize: 12, fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: 1 - progress,
                backgroundColor: Colors.white12,
                valueColor: AlwaysStoppedAnimation<Color>(
                  remaining > 60 ? const Color(0xFF10B981) : remaining > 30 ? const Color(0xFFF59E0B) : Colors.red,
                ),
                minHeight: 6,
              ),
            ),
          ],
        ),
        const SizedBox(height: 40),
        OutlinedButton(
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white60,
            side: const BorderSide(color: Colors.white24),
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 13),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ],
    );
  }

  Widget _buildRejectedView() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.red.withOpacity(0.1),
          ),
          child: const Icon(Icons.cancel_rounded, color: Colors.red, size: 56),
        ),
        const SizedBox(height: 24),
        const Text('Entry Denied', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        const Text('The host did not admit you to this meeting.',
            style: TextStyle(color: Colors.white54, fontSize: 14), textAlign: TextAlign.center),
        const SizedBox(height: 40),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF2563EB),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 13),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          onPressed: () => Navigator.pop(context),
          child: const Text('Go Back'),
        ),
      ],
    );
  }
}