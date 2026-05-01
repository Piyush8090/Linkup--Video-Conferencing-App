import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import '../screens/meeting_screen.dart';
class MeetingCard extends StatelessWidget {
  final String title;
  final String time;
  final String date;
  final String host;
  final String channelId;
  final bool isScheduled;
  final String currentUsername;
  const MeetingCard({
    super.key,
    required this.title,
    required this.time,
    required this.date,
    required this.host,
    required this.channelId,
    required this.isScheduled,
    required this.currentUsername,
  });
  int _generateUid() => Random().nextInt(900000) + 100000;
  void _shareMeeting(BuildContext context) async {
    final shareText = '''
🎥 *$title*

$host has invited you to a meeting!

📋 *Meeting ID:* $channelId
${isScheduled ? '⏰ *Time:* $time • $date' : ''}

To join the meeting:
1. Open the LinkUp app
2. Tap "Join Meeting"
3. Enter this ID: *$channelId*

---
Sent from LinkUp
    '''.trim();
    Share.share(
      shareText,
      subject: 'LinkUp Meeting Invitation - $title',
    );
    try {
    print('🔵 Share triggered');
    final result = await Share.share(
      'Test share from LinkUp\nMeeting ID: $channelId',
      subject: 'LinkUp Meeting',
    );
    print('🟢 Share result: $result');
  } catch (e) {
    print('🔴 Share error: $e');
  }  
  }

  void _showShareOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: Colors.black12,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFF),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: const Color(0xFF2563EB).withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.videocam, color: Color(0xFF2563EB), size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                                color: Color(0xFF0F172A))),
                        const SizedBox(height: 2),
                        Text(
                          'Meeting ID: $channelId',
                          style: const TextStyle(
                              fontSize: 13,
                              color: Color(0xFF2563EB),
                              fontWeight: FontWeight.w500,
                              letterSpacing: 0.5),
                        ),
                        if (isScheduled)
                          Text('$time • $date',
                              style: const TextStyle(
                                  fontSize: 11, color: Color(0xFF64748B))),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: _shareOption(
                    icon: Icons.copy_rounded,
                    label: 'ID Copy\n',
                    color: const Color(0xFF8B5CF6),
                    onTap: () {
                      Navigator.pop(context);
                      Clipboard.setData(ClipboardData(text: channelId));
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Row(children: [
                            const Icon(Icons.check_circle,
                                color: Colors.white, size: 16),
                            const SizedBox(width: 8),
                            Text('ID copied: $channelId'),
                          ]),
                          backgroundColor: const Color(0xFF8B5CF6),
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 12),

                // WhatsApp share
                Expanded(
                  child: _shareOption(
                    icon: Icons.share_rounded,
                    label: 'WhatsApp\n/ SMS',
                    color: const Color(0xFF10B981),
                    onTap: () {
                      Navigator.pop(context);
                      _shareMeeting(context);
                    },
                  ),
                ),
                const SizedBox(width: 12),

                // Full message share
                Expanded(
                  child: _shareOption(
                    icon: Icons.open_in_new_rounded,
                    label: 'Other\nApps',
                    color: const Color(0xFF2563EB),
                    onTap: () {
                      Navigator.pop(context);
                      _shareMeeting(context);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Full invite message preview
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Message preview:',
                      style: TextStyle(
                          fontSize: 11,
                          color: Color(0xFF94A3B8),
                          fontWeight: FontWeight.w500)),
                  const SizedBox(height: 6),
                  Text(
                    '$host has invited you..!\nMeeting ID: $channelId\n\nTap "Join Meeting" in the LinkUp app to join.',
                    style: const TextStyle(
                        fontSize: 12, color: Color(0xFF475569)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
  Widget _shareOption({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 6),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: color,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  height: 1.3),
            ),
          ],
        ),
      ),
    );
  }
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(
              color: Colors.black12, blurRadius: 4, offset: Offset(0, 2)),
        ],
      ),
      child: Row(
        children: [
          // Left color bar
          Container(
            width: 4,
            height: 60,
            decoration: BoxDecoration(
              color: isScheduled
                  ? const Color(0xFFF59E0B)
                  : const Color(0xFF2563EB),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 12),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1E293B))),
                const SizedBox(height: 4),
                Row(children: [
                  const Icon(Icons.access_time,
                      size: 13, color: Color(0xFF64748B)),
                  const SizedBox(width: 4),
                  Text('$time • $date',
                      style: const TextStyle(
                          fontSize: 12, color: Color(0xFF64748B))),
                ]),
                const SizedBox(height: 2),
                Row(children: [
                  const Icon(Icons.person, size: 13, color: Color(0xFF64748B)),
                  const SizedBox(width: 4),
                  Text('Host: $host',
                      style: const TextStyle(
                          fontSize: 12, color: Color(0xFF64748B))),
                ]),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.share_rounded,
                color: Color(0xFF10B981), size: 20),
            tooltip: 'Share Meeting',
            onPressed: () => _showShareOptions(context),
          ),
          IconButton(
            icon: Icon(
              Icons.videocam_rounded,
              color: isScheduled
                  ? const Color(0xFFF59E0B)
                  : const Color(0xFF2563EB),
              size: 22,
            ),
            tooltip: 'Join Meeting',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => MeetingScreen(
                    channelId: channelId,
                    userName: currentUsername,
                    uid: _generateUid(),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}