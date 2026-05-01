import 'package:flutter/material.dart';

/// Meeting type theme system
/// Each meeting type gets its own visual identity
class MeetingTheme {
  final Color primary;
  final Color secondary;
  final Color background;
  final Color surface;
  final Color headerStart;
  final Color headerEnd;
  final Color controlBar;
  final String label;
  final IconData icon;
  final String emoji;
  final String tagline;

  const MeetingTheme({
    required this.primary,
    required this.secondary,
    required this.background,
    required this.surface,
    required this.headerStart,
    required this.headerEnd,
    required this.controlBar,
    required this.label,
    required this.icon,
    required this.emoji,
    required this.tagline,
  });

  static const MeetingTheme classroom = MeetingTheme(
    primary: Color(0xFF6D28D9),
    secondary: Color(0xFF8B5CF6),
    background: Color(0xFF1A1035),
    surface: Color(0xFF241A4A),
    headerStart: Color(0xFF1A0A3B),
    headerEnd: Color(0xFF2D1B69),
    controlBar: Color(0xFF1A0A3B),
    label: 'Class',
    icon: Icons.school_rounded,
    emoji: '🎓',
    tagline: 'Classroom Session',
  );

  static const MeetingTheme casual = MeetingTheme(
    primary: Color(0xFF059669),
    secondary: Color(0xFF10B981),
    background: Color(0xFF0F2419),
    surface: Color(0xFF163324),
    headerStart: Color(0xFF062517),
    headerEnd: Color(0xFF0D3D21),
    controlBar: Color(0xFF062517),
    label: 'Casual',
    icon: Icons.emoji_emotions_rounded,
    emoji: '😄',
    tagline: 'Casual Chat',
  );

  static const MeetingTheme team = MeetingTheme(
    primary: Color(0xFF1D4ED8),
    secondary: Color(0xFF3B82F6),
    background: Color(0xFF0F1A2E),
    surface: Color(0xFF162440),
    headerStart: Color(0xFF0A1628),
    headerEnd: Color(0xFF0F3460),
    controlBar: Color(0xFF0A1628),
    label: 'Team',
    icon: Icons.work_rounded,
    emoji: '💼',
    tagline: 'Team Meeting',
  );

  static MeetingTheme fromType(String type) {
    switch (type) {
      case 'class': return classroom;
      case 'casual': return casual;
      default: return team;
    }
  }
}