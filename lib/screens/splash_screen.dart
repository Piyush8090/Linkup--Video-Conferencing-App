import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:math' as math;
import 'main_wrapper.dart';
import 'login_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  // ── Animation controllers ────────────────────────────────────────────
  late AnimationController _bgController;
  late AnimationController _logoController;
  late AnimationController _ringController;
  late AnimationController _textController;
  late AnimationController _dotsController;
  late AnimationController _exitController;

  // Background gradient shift
  late Animation<double> _bgAnim;

  // Logo scale + fade
  late Animation<double> _logoScale;
  late Animation<double> _logoOpacity;

  // Pulse ring
  late Animation<double> _ringScale;
  late Animation<double> _ringOpacity;

  // Text slide up
  late Animation<double> _textSlide;
  late Animation<double> _textOpacity;

  // Loading dots
  late Animation<double> _dotsAnim;

  // Exit fade
  late Animation<double> _exitFade;

  @override
  void initState() {
    super.initState();

    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ));

    _bgController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 3000))
      ..repeat(reverse: true);
    _bgAnim = Tween<double>(begin: 0, end: 1).animate(
        CurvedAnimation(parent: _bgController, curve: Curves.easeInOut));

    _ringController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1800))
      ..repeat();
    _ringScale = Tween<double>(begin: 0.6, end: 1.8).animate(
        CurvedAnimation(parent: _ringController, curve: Curves.easeOut));
    _ringOpacity = Tween<double>(begin: 0.6, end: 0.0).animate(
        CurvedAnimation(parent: _ringController, curve: Curves.easeOut));

    _logoController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900));
    _logoScale = Tween<double>(begin: 0.3, end: 1.0).animate(
        CurvedAnimation(parent: _logoController, curve: Curves.elasticOut));
    _logoOpacity = Tween<double>(begin: 0, end: 1).animate(
        CurvedAnimation(parent: _logoController, curve: Curves.easeIn));

    _textController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700));
    _textSlide = Tween<double>(begin: 30, end: 0).animate(
        CurvedAnimation(parent: _textController, curve: Curves.easeOutCubic));
    _textOpacity = Tween<double>(begin: 0, end: 1).animate(
        CurvedAnimation(parent: _textController, curve: Curves.easeIn));

    _dotsController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat();
    _dotsAnim = Tween<double>(begin: 0, end: 1).animate(_dotsController);

    _exitController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500));
    _exitFade = Tween<double>(begin: 1, end: 0).animate(
        CurvedAnimation(parent: _exitController, curve: Curves.easeIn));

    _startSequence();
  }

  Future<void> _startSequence() async {
    await Future.delayed(const Duration(milliseconds: 200));
    await _logoController.forward();
    await Future.delayed(const Duration(milliseconds: 200));
    await _textController.forward();
    await Future.delayed(const Duration(milliseconds: 1400));

    // Check auth
    final session = Supabase.instance.client.auth.currentSession;

    await _exitController.forward();

    if (mounted) {
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (_, __, ___) =>
              session != null ? const MainWrapper() : const LoginScreen(),
          transitionsBuilder: (_, anim, __, child) =>
              FadeTransition(opacity: anim, child: child),
          transitionDuration: const Duration(milliseconds: 400),
        ),
      );
    }
  }

  @override
  void dispose() {
    _bgController.dispose();
    _logoController.dispose();
    _ringController.dispose();
    _textController.dispose();
    _dotsController.dispose();
    _exitController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return FadeTransition(
      opacity: _exitFade,
      child: Scaffold(
        body: AnimatedBuilder(
          animation: Listenable.merge(
              [_bgAnim, _logoController, _textController, _ringController, _dotsAnim]),
          builder: (context, _) {
            return Container(
              width: size.width,
              height: size.height,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color.lerp(const Color(0xFF0D1B4B), const Color(0xFF12265E), _bgAnim.value)!,
                    Color.lerp(const Color(0xFF1A3A8F), const Color(0xFF0F2B7A), _bgAnim.value)!,
                    Color.lerp(const Color(0xFF0A1533), const Color(0xFF091228), _bgAnim.value)!,
                  ],
                  stops: const [0.0, 0.5, 1.0],
                ),
              ),
              child: Stack(
                children: [
                  // ── Decorative background orbs ──────────────────────
                  Positioned(
                    top: -size.height * 0.12,
                    right: -size.width * 0.2,
                    child: _GlowOrb(size: size.width * 0.85, color: const Color(0xFF2563EB), opacity: 0.12),
                  ),
                  Positioned(
                    bottom: -size.height * 0.1,
                    left: -size.width * 0.25,
                    child: _GlowOrb(size: size.width * 0.75, color: const Color(0xFF3B82F6), opacity: 0.10),
                  ),
                  Positioned(
                    top: size.height * 0.55,
                    right: size.width * 0.05,
                    child: _GlowOrb(size: size.width * 0.35, color: const Color(0xFF60A5FA), opacity: 0.07),
                  ),

                  // ── Floating particles ──────────────────────────────
                  ..._buildParticles(size),

                  // ── Grid overlay (subtle) ───────────────────────────
                  CustomPaint(
                    size: size,
                    painter: _GridPainter(opacity: 0.03),
                  ),

                  // ── Center content ──────────────────────────────────
                  Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Pulse ring + Logo
                        SizedBox(
                          width: 140,
                          height: 140,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              // Outer pulse ring
                              Transform.scale(
                                scale: _ringScale.value,
                                child: Container(
                                  width: 120,
                                  height: 120,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: const Color(0xFF3B82F6)
                                          .withOpacity(_ringOpacity.value),
                                      width: 2,
                                    ),
                                  ),
                                ),
                              ),
                              // Inner ring
                              Transform.scale(
                                scale: _logoScale.value,
                                child: Container(
                                  width: 110,
                                  height: 110,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Colors.white.withOpacity(0.04),
                                    border: Border.all(color: Colors.white.withOpacity(0.12), width: 1),
                                  ),
                                ),
                              ),
                              // Logo container
                              Opacity(
                                opacity: _logoOpacity.value,
                                child: Transform.scale(
                                  scale: _logoScale.value,
                                  child: Container(
                                    width: 88,
                                    height: 88,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      gradient: const LinearGradient(
                                        colors: [Color(0xFF2563EB), Color(0xFF1D4ED8)],
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: const Color(0xFF2563EB).withOpacity(0.5),
                                          blurRadius: 32,
                                          spreadRadius: 2,
                                        ),
                                        BoxShadow(
                                          color: const Color(0xFF2563EB).withOpacity(0.2),
                                          blurRadius: 60,
                                          spreadRadius: 10,
                                        ),
                                      ],
                                    ),
                                    child: const Icon(
                                      Icons.video_call_rounded,
                                      color: Colors.white,
                                      size: 42,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 36),

                        // App name
                        Transform.translate(
                          offset: Offset(0, _textSlide.value),
                          child: Opacity(
                            opacity: _textOpacity.value,
                            child: Column(
                              children: [
                                // LinkUp wordmark
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.baseline,
                                  textBaseline: TextBaseline.alphabetic,
                                  children: [
                                    const Text(
                                      'Link',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 40,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: -1.5,
                                        height: 1,
                                      ),
                                    ),
                                    Text(
                                      'Up',
                                      style: TextStyle(
                                        color: const Color(0xFF60A5FA),
                                        fontSize: 40,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: -1.5,
                                        height: 1,
                                      ),
                                    ),
                                  ],
                                ),

                                const SizedBox(height: 10),

                                // Tagline
                                Text(
                                  'Connect · Collaborate · Create',
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.45),
                                    fontSize: 13,
                                    fontWeight: FontWeight.w400,
                                    letterSpacing: 1.8,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                        const SizedBox(height: 72),

                        // Loading dots
                        Opacity(
                          opacity: _textOpacity.value,
                          child: _LoadingDots(animation: _dotsAnim),
                        ),
                      ],
                    ),
                  ),

                  // ── Bottom branding ─────────────────────────────────
                  Positioned(
                    bottom: 40,
                    left: 0,
                    right: 0,
                    child: Opacity(
                      opacity: _textOpacity.value * 0.4,
                      child: const Text(
                        'v1.0.0',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white, fontSize: 11, letterSpacing: 1.5),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  List<Widget> _buildParticles(Size size) {
    final particles = <_ParticleData>[
      _ParticleData(left: 0.08, top: 0.18, size: 3, opacity: 0.25),
      _ParticleData(left: 0.82, top: 0.12, size: 4, opacity: 0.20),
      _ParticleData(left: 0.15, top: 0.72, size: 2.5, opacity: 0.18),
      _ParticleData(left: 0.88, top: 0.65, size: 3.5, opacity: 0.22),
      _ParticleData(left: 0.42, top: 0.08, size: 2, opacity: 0.15),
      _ParticleData(left: 0.65, top: 0.85, size: 3, opacity: 0.18),
      _ParticleData(left: 0.05, top: 0.45, size: 2, opacity: 0.12),
      _ParticleData(left: 0.92, top: 0.38, size: 2.5, opacity: 0.15),
    ];

    return particles.map((p) {
      return Positioned(
        left: size.width * p.left,
        top: size.height * p.top,
        child: Opacity(
          opacity: p.opacity * _textOpacity.value,
          child: Container(
            width: p.size,
            height: p.size,
            decoration: const BoxDecoration(
              color: Color(0xFF60A5FA),
              shape: BoxShape.circle,
            ),
          ),
        ),
      );
    }).toList();
  }
}

class _ParticleData {
  final double left, top, size, opacity;
  const _ParticleData({required this.left, required this.top, required this.size, required this.opacity});
}

class _GlowOrb extends StatelessWidget {
  final double size;
  final Color color;
  final double opacity;

  const _GlowOrb({required this.size, required this.color, required this.opacity});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [color.withOpacity(opacity), color.withOpacity(0)],
          stops: const [0.0, 1.0],
        ),
      ),
    );
  }
}

class _LoadingDots extends StatelessWidget {
  final Animation<double> animation;
  const _LoadingDots({required this.animation});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (i) {
        return AnimatedBuilder(
          animation: animation,
          builder: (_, __) {
            final phase = ((animation.value - i * 0.22) % 1.0).clamp(0.0, 1.0);
            final scale = 0.6 + 0.6 * math.sin(phase * math.pi).clamp(0.0, 1.0);
            final opacity = 0.25 + 0.75 * math.sin(phase * math.pi).clamp(0.0, 1.0);
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 4),
              child: Transform.scale(
                scale: scale,
                child: Container(
                  width: 7, height: 7,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF3B82F6).withOpacity(opacity),
                  ),
                ),
              ),
            );
          },
        );
      }),
    );
  }
}

class _GridPainter extends CustomPainter {
  final double opacity;
  _GridPainter({required this.opacity});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(opacity)
      ..strokeWidth = 0.5;

    const step = 44.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_GridPainter old) => false;
}