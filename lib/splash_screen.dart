import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'main.dart'; // Make sure this points to your file containing MainNavigationScreen

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  double _opacity = 0.0;
  double _offsetY = 20.0;

  @override
  void initState() {
    super.initState();
    // Start the entry animation almost immediately
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) {
        setState(() {
          _opacity = 1.0;
          _offsetY = 0.0;
        });
      }
    });

    // Navigate to the Main Screen after 3 seconds
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        Navigator.pushReplacement(
          context,
          PageRouteBuilder(
            pageBuilder:
                (context, animation, secondaryAnimation) =>
                    const MainNavigationScreen(),
            transitionsBuilder: (
              context,
              animation,
              secondaryAnimation,
              child,
            ) {
              return FadeTransition(opacity: animation, child: child);
            },
            transitionDuration: const Duration(milliseconds: 800),
          ),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC), // Matches your app's background
      body: Stack(
        children: [
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // LOGO ANIMATION
                AnimatedOpacity(
                  opacity: _opacity,
                  duration: const Duration(milliseconds: 1500),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 1500),
                    curve: Curves.easeOutCubic,
                    transform: Matrix4.translationValues(0, _offsetY, 0),
                    child: Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(28),
                        boxShadow: [
                          BoxShadow(
                            // ignore: deprecated_member_use
                            color: Colors.black.withOpacity(0.04),
                            blurRadius: 20,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.asset(
                          '../assets/logo/app_logo.jpg',
                          width: 80,
                          height: 80,
                          // Fallback if logo is missing during dev
                          errorBuilder:
                              (context, error, stackTrace) => const Icon(
                                Icons.layers_rounded,
                                size: 80,
                                color: Colors.teal,
                              ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 30),
                // APP NAME ANIMATION
                AnimatedOpacity(
                  opacity: _opacity,
                  duration: const Duration(milliseconds: 1800),
                  child: Column(
                    children: [
                      Text(
                        'StackIt',
                        style: GoogleFonts.poppins(
                          fontSize: 32,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0,
                          color: const Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Crafted by Bhadri Prabhu K',
                        style: GoogleFonts.poppins(
                          fontSize: 18,
                          fontWeight: FontWeight.w400,
                          color: Colors.blueGrey[300],
                          letterSpacing: 0,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
