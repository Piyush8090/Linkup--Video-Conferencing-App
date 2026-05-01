import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final supabase = Supabase.instance.client;

  String username = 'User';
  String email = '';
  String? avatarUrl;
  bool isLoading = true;
  bool _isUploadingAvatar = false;

  int _totalMeetings = 0;
  int _scheduledMeetings = 0;
  int _totalMinutes = 0;
  int _screenShares = 0;
  int _chatMessages = 0;
  int _participationRate = 0;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final user = supabase.auth.currentUser;
    if (user == null) { setState(() => isLoading = false); return; }
    email = user.email ?? '';

    try {
      final data = await supabase.from('profiles').select().eq('id', user.id).maybeSingle();
      final allMeetings = await supabase.from('meetings').select('id, scheduled_at, duration_minutes, meeting_type').eq('host_id', user.id);
      final meetingList = allMeetings as List;
      final scheduled = meetingList.where((m) => m['scheduled_at'] != null).length;
      final totalMinutes = meetingList.fold<int>(0, (sum, m) => sum + ((m['duration_minutes'] ?? 0) as int));
      final events = await supabase.from('meeting_events').select('event_type, meeting_code').eq('actor_name', data?['username'] ?? 'User');
      final eventList = events as List;
      final screenShares = eventList.where((e) => e['event_type'] == 'screen_share_started').length;
      final chatMessages = eventList.where((e) => e['event_type'] == 'chat_message').length;
      final participationRate = meetingList.isEmpty ? 0 : ((eventList.length / (meetingList.length * 5)) * 100).clamp(0, 100).round();

      setState(() {
        username = data?['username'] ?? 'User';
        avatarUrl = data?['avatar_url'];
        _totalMeetings = meetingList.length;
        _scheduledMeetings = scheduled;
        _totalMinutes = totalMinutes;
        _screenShares = screenShares;
        _chatMessages = chatMessages;
        _participationRate = participationRate;
        isLoading = false;
      });
    } catch (e) {
      debugPrint('Load profile error: $e');
      setState(() => isLoading = false);
    }
  }

  Future<void> _pickAndUploadAvatar() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.black12, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 20),
            const Text('Update Profile Photo', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(child: _sourceOption(icon: Icons.camera_alt_rounded, label: 'Camera', color: const Color(0xFF2563EB), onTap: () => Navigator.pop(context, ImageSource.camera))),
                const SizedBox(width: 12),
                Expanded(child: _sourceOption(icon: Icons.photo_library_rounded, label: 'Gallery', color: const Color(0xFF8B5CF6), onTap: () => Navigator.pop(context, ImageSource.gallery))),
              ],
            ),
            if (avatarUrl != null) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: TextButton.icon(
                  icon: const Icon(Icons.delete_outline_rounded, color: Colors.red),
                  label: const Text('Remove Photo', style: TextStyle(color: Colors.red)),
                  onPressed: () => Navigator.pop(context, null),
                  style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12)),
                ),
              ),
            ],
          ],
        ),
      ),
    );

    if (!mounted) return;
    if (source == null && avatarUrl != null) { await _removeAvatar(); return; }
    if (source == null) return;

    final picker = ImagePicker();
    final picked = await picker.pickImage(source: source, maxWidth: 512, maxHeight: 512, imageQuality: 85);
    if (picked == null) return;

    setState(() => _isUploadingAvatar = true);
    try {
      final user = supabase.auth.currentUser!;
      final file = File(picked.path);
      final ext = picked.path.split('.').last.toLowerCase();
      final fileName = 'avatar_${user.id}.$ext';
      await supabase.storage.from('avatars').upload(fileName, file, fileOptions: const FileOptions(upsert: true));
      final publicUrl = supabase.storage.from('avatars').getPublicUrl(fileName);
      final urlWithCacheBust = '$publicUrl?t=${DateTime.now().millisecondsSinceEpoch}';
      await supabase.from('profiles').update({'avatar_url': urlWithCacheBust}).eq('id', user.id);
      setState(() { avatarUrl = urlWithCacheBust; _isUploadingAvatar = false; });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Row(children: [Icon(Icons.check_circle, color: Colors.white, size: 16), SizedBox(width: 8), Text('Profile photo updated.')]),
          backgroundColor: Color(0xFF10B981),
        ));
      }
    } catch (e) {
      setState(() => _isUploadingAvatar = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Failed to upload photo. Please try again.'), backgroundColor: Colors.red,
        ));
      }
    }
  }

  Future<void> _removeAvatar() async {
    setState(() => _isUploadingAvatar = true);
    try {
      await supabase.from('profiles').update({'avatar_url': null}).eq('id', supabase.auth.currentUser!.id);
      setState(() { avatarUrl = null; _isUploadingAvatar = false; });
    } catch (e) {
      setState(() => _isUploadingAvatar = false);
    }
  }

  Widget _sourceOption({required IconData icon, required String label, required Color color, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        decoration: BoxDecoration(color: color.withOpacity(0.08), borderRadius: BorderRadius.circular(14), border: Border.all(color: color.withOpacity(0.2))),
        child: Column(
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 8),
            Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 13)),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmLogout() async {
    final shouldLogout = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Sign Out', style: TextStyle(fontWeight: FontWeight.bold)),
        content: const Text('Are you sure you want to sign out?', style: TextStyle(color: Colors.black54)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );
    if (shouldLogout == true) {
      await supabase.auth.signOut();
      if (!mounted) return;
      Navigator.of(context).pushNamedAndRemoveUntil('/login', (_) => false);
    }
  }

  void _showEditProfileSheet() {
    final nameCtrl = TextEditingController(text: username);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Container(
          decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.black12, borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 20),
              const Text('Edit Profile', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
              const SizedBox(height: 20),
              TextField(
                controller: nameCtrl,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  labelText: 'Display Name',
                  prefixIcon: const Icon(Icons.person_outline_rounded, color: Color(0xFF2563EB)),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF2563EB), width: 2)),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity, height: 50,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2563EB), foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                  onPressed: () async {
                    final newName = nameCtrl.text.trim();
                    if (newName.isEmpty) return;
                    Navigator.pop(context);
                    try {
                      final user = supabase.auth.currentUser;
                      if (user == null) return;
                      await supabase.from('profiles').update({'username': newName}).eq('id', user.id);
                      setState(() => username = newName);
                      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profile updated successfully.'), backgroundColor: Color(0xFF10B981)));
                    } catch (e) {
                      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to update profile. Please try again.'), backgroundColor: Colors.red));
                    }
                  },
                  child: const Text('Save Changes'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openPage(Widget page) => Navigator.push(context, MaterialPageRoute(builder: (_) => page));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      body: isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF2563EB)))
          : CustomScrollView(
              slivers: [
                _buildSliverHeader(),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildAnalyticsSection(),
                        const SizedBox(height: 24),
                        _buildSectionLabel('Account'),
                        const SizedBox(height: 8),
                        _buildMenuCard([
                          _MenuItem(icon: Icons.person_outline_rounded, label: 'Edit Profile', onTap: _showEditProfileSheet),
                          _MenuItem(icon: Icons.lock_outline_rounded, label: 'Privacy & Security', onTap: () => _openPage(const _PrivacyPage())),
                        ]),
                        const SizedBox(height: 20),
                        _buildSectionLabel('Support'),
                        const SizedBox(height: 8),
                        _buildMenuCard([
                          _MenuItem(icon: Icons.help_outline_rounded, label: 'Help & Support', onTap: () => _openPage(const _HelpPage())),
                          _MenuItem(icon: Icons.info_outline_rounded, label: 'About LinkUp', onTap: () => _openPage(const _AboutPage())),
                        ]),
                        const SizedBox(height: 20),
                        _buildMenuCard([
                          _MenuItem(icon: Icons.logout_rounded, label: 'Sign Out', onTap: _confirmLogout, isDestructive: true),
                        ]),
                        const SizedBox(height: 32),
                        const Center(child: Text('LinkUp v1.0.0', style: TextStyle(color: Colors.black26, fontSize: 12))),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildSliverHeader() {
    return SliverAppBar(
      expandedHeight: 280,
      pinned: true,
      backgroundColor: const Color(0xFF1D4ED8),
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(colors: [Color(0xFF1D4ED8), Color(0xFF3B82F6)], begin: Alignment.topLeft, end: Alignment.bottomRight),
          ),
          child: SafeArea(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(height: 12),
                GestureDetector(
                  onTap: _pickAndUploadAvatar,
                  child: Stack(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(colors: [Colors.white.withOpacity(0.8), Colors.white.withOpacity(0.3)]),
                        ),
                        child: CircleAvatar(
                          radius: 48,
                          backgroundColor: Colors.white24,
                          backgroundImage: avatarUrl != null ? NetworkImage(avatarUrl!) : null,
                          child: _isUploadingAvatar
                              ? const CircularProgressIndicator(color: Colors.white, strokeWidth: 2)
                              : avatarUrl == null
                                  ? Text(username.isNotEmpty ? username[0].toUpperCase() : 'U',
                                      style: const TextStyle(fontSize: 38, fontWeight: FontWeight.bold, color: Colors.white))
                                  : null,
                        ),
                      ),
                      Positioned(
                        bottom: 2, right: 2,
                        child: Container(
                          padding: const EdgeInsets.all(7),
                          decoration: BoxDecoration(color: const Color(0xFF1D4ED8), shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2.5)),
                          child: const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 13),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Text(username, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(email, style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 13)),
                const SizedBox(height: 12),
                // Quick stats row
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _headerStat('$_totalMeetings', 'Meetings'),
                      Container(height: 24, width: 1, color: Colors.white24),
                      _headerStat('${(_totalMinutes ~/ 60)}h', 'Time'),
                      Container(height: 24, width: 1, color: Colors.white24),
                      _headerStat('$_participationRate%', 'Activity'),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      title: const Text('Profile', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
    );
  }

  Widget _headerStat(String value, String label) {
    return Column(
      children: [
        Text(value, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
        Text(label, style: TextStyle(color: Colors.white.withOpacity(0.65), fontSize: 11)),
      ],
    );
  }

  Widget _buildAnalyticsSection() {
    final hours = _totalMinutes ~/ 60;
    final mins = _totalMinutes % 60;
    final timeStr = hours > 0 ? '${hours}h ${mins}m' : '${mins}m';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Your Analytics', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
        const SizedBox(height: 12),
        // Top row
        Row(
          children: [
            Expanded(child: _statCard(icon: Icons.videocam_rounded, value: '$_totalMeetings', label: 'Meetings', color: const Color(0xFF2563EB))),
            const SizedBox(width: 10),
            Expanded(child: _statCard(icon: Icons.timer_outlined, value: _totalMinutes > 0 ? timeStr : '—', label: 'Time Spent', color: const Color(0xFF8B5CF6))),
            const SizedBox(width: 10),
            Expanded(child: _statCard(icon: Icons.calendar_today_rounded, value: '$_scheduledMeetings', label: 'Scheduled', color: const Color(0xFFF59E0B))),
          ],
        ),
        const SizedBox(height: 10),
        // Bottom row
        Row(
          children: [
            Expanded(child: _statCard(icon: Icons.screen_share_rounded, value: '$_screenShares', label: 'Screens', color: const Color(0xFF10B981))),
            const SizedBox(width: 10),
            Expanded(child: _statCard(icon: Icons.chat_bubble_outline_rounded, value: '$_chatMessages', label: 'Messages', color: const Color(0xFFEF4444))),
            const SizedBox(width: 10),
            Expanded(child: _participationCard()),
          ],
        ),
      ],
    );
  }

  Widget _statCard({required IconData icon, required String value, required String label, required Color color}) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 10),
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
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(height: 8),
          Text(value, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(fontSize: 10, color: Color(0xFF94A3B8), fontWeight: FontWeight.w500), textAlign: TextAlign.center),
        ],
      ),
    );
  }

  Widget _participationCard() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 3))],
      ),
      child: Column(
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 38, height: 38,
                child: CircularProgressIndicator(
                  value: _participationRate / 100,
                  backgroundColor: const Color(0xFFF1F5F9),
                  valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF2563EB)),
                  strokeWidth: 4.5,
                ),
              ),
              Text('$_participationRate%', style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
            ],
          ),
          const SizedBox(height: 8),
          const Text('Activity', style: TextStyle(fontSize: 10, color: Color(0xFF94A3B8), fontWeight: FontWeight.w500), textAlign: TextAlign.center),
        ],
      ),
    );
  }

  Widget _buildSectionLabel(String label) {
    return Text(label.toUpperCase(),
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF94A3B8), letterSpacing: 1.2));
  }

  Widget _buildMenuCard(List<_MenuItem> items) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 3))],
      ),
      child: Column(
        children: items.asMap().entries.map((entry) {
          final i = entry.key;
          final item = entry.value;
          return Column(
            children: [
              _buildMenuItem(item),
              if (i < items.length - 1) const Divider(height: 1, indent: 56, endIndent: 16, color: Color(0xFFF1F5F9)),
            ],
          );
        }).toList(),
      ),
    );
  }

  Widget _buildMenuItem(_MenuItem item) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: item.onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: item.isDestructive ? Colors.red.withOpacity(0.08) : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(item.icon, size: 18, color: item.isDestructive ? Colors.red : const Color(0xFF475569)),
            ),
            const SizedBox(width: 14),
            Expanded(child: Text(item.label, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: item.isDestructive ? Colors.red : const Color(0xFF0F172A)))),
            Icon(Icons.chevron_right_rounded, size: 20, color: item.isDestructive ? Colors.red.withOpacity(0.5) : const Color(0xFFCBD5E1)),
          ],
        ),
      ),
    );
  }
}

class _MenuItem {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isDestructive;
  const _MenuItem({required this.icon, required this.label, required this.onTap, this.isDestructive = false});
}

// ─── Sub Pages ────────────────────────────────────────────────────────────────
class _PrivacyPage extends StatelessWidget {
  const _PrivacyPage();
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(title: const Text('Privacy & Security'), backgroundColor: const Color(0xFF2563EB), foregroundColor: Colors.white, elevation: 0),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: const [
          _InfoCard(icon: Icons.lock_outline_rounded, title: 'End-to-End Encryption', subtitle: 'Your meetings and messages are secured with encryption.'),
          SizedBox(height: 12),
          _InfoCard(icon: Icons.visibility_off_outlined, title: 'Data Privacy', subtitle: 'We do not share your personal data with third parties.'),
          SizedBox(height: 12),
          _InfoCard(icon: Icons.delete_outline_rounded, title: 'Chat Auto-Delete', subtitle: 'Chat messages are deleted when a meeting ends.'),
        ],
      ),
    );
  }
}

class _HelpPage extends StatelessWidget {
  const _HelpPage();
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(title: const Text('Help & Support'), backgroundColor: const Color(0xFF2563EB), foregroundColor: Colors.white, elevation: 0),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: const [
          _InfoCard(icon: Icons.email_outlined, title: 'Email Support', subtitle: 'support.linkup.app@gmail.com'),
          SizedBox(height: 12),
          _InfoCard(icon: Icons.videocam_outlined, title: 'Starting a Meeting', subtitle: 'Tap "New Meeting" on the home screen to instantly start a video call.'),
          SizedBox(height: 12),
          _InfoCard(icon: Icons.people_outline_rounded, title: 'Joining a Meeting', subtitle: 'Tap "Join Meeting" and enter the Meeting ID shared by the host.'),
          SizedBox(height: 12),
          _InfoCard(icon: Icons.calendar_today_outlined, title: 'Scheduling a Meeting', subtitle: 'Go to the Schedule tab to plan meetings in advance.'),
        ],
      ),
    );
  }
}

class _AboutPage extends StatelessWidget {
  const _AboutPage();
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(title: const Text('About LinkUp'), backgroundColor: const Color(0xFF2563EB), foregroundColor: Colors.white, elevation: 0),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 3))]),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: const Color(0xFF2563EB).withOpacity(0.1), shape: BoxShape.circle),
                  child: const Icon(Icons.video_call_rounded, size: 48, color: Color(0xFF2563EB)),
                ),
                const SizedBox(height: 16),
                const Text('LinkUp', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
                const SizedBox(height: 4),
                const Text('Version 1.0.0', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13)),
                const SizedBox(height: 16),
                const Text('LinkUp is a simple, fast, and secure video conferencing app. Connect with anyone, anywhere.',
                    textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF64748B), fontSize: 14, height: 1.5)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const _InfoCard(icon: Icons.code_rounded, title: 'Built With', subtitle: 'Flutter • Supabase • Agora RTC Engine'),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  const _InfoCard({required this.icon, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: const Color(0xFF2563EB).withOpacity(0.08), borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: const Color(0xFF2563EB), size: 18),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: Color(0xFF0F172A))),
                const SizedBox(height: 3),
                Text(subtitle, style: const TextStyle(color: Color(0xFF64748B), fontSize: 13, height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}