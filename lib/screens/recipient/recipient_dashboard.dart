import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'tabs/recipient_home_tab.dart';
import 'tabs/recipient_search_tab.dart';
import 'tabs/recipient_profile_tab.dart';

class RecipientDashboard extends StatefulWidget {
  const RecipientDashboard({super.key});

  @override
  State<RecipientDashboard> createState() => _RecipientDashboardState();
}

class _RecipientDashboardState extends State<RecipientDashboard>
    with TickerProviderStateMixin {
  int _currentIndex = 0;
  Map<String, dynamic>? _recipientData;
  bool _isLoading = true;

  late List<AnimationController> _tabControllers;
  late PageController _pageController;

  final Color _primaryColor = const Color(0xFF7B1FA2);

  final List<_NavItem> _navItems = [
    _NavItem(icon: Icons.home_rounded, label: 'Home'),
    _NavItem(icon: Icons.search_rounded, label: 'Search'),
    _NavItem(icon: Icons.person_rounded, label: 'Profile'),
  ];

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _tabControllers = List.generate(
      3,
          (i) => AnimationController(vsync: this, duration: const Duration(milliseconds: 200)),
    );
    _tabControllers[0].forward();
    _fetchRecipientData();
  }

  @override
  void dispose() {
    _pageController.dispose();
    for (var c in _tabControllers) c.dispose();
    super.dispose();
  }

  Future<void> _fetchRecipientData() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;
      final doc = await FirebaseFirestore.instance
          .collection('recipients')
          .doc(uid)
          .get();
      if (doc.exists) {
        setState(() {
          _recipientData = doc.data();
          _isLoading = false;
        });
      }
    } catch (_) {
      setState(() => _isLoading = false);
    }
  }

  void _onTabTap(int index) {
    if (index == _currentIndex) return;
    HapticFeedback.lightImpact();
    _tabControllers[_currentIndex].reverse();
    setState(() => _currentIndex = index);
    _tabControllers[index].forward();
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: const Color(0xFFF8F9FA),
        body: Center(child: CircularProgressIndicator(color: _primaryColor)),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      body: PageView(
        controller: _pageController,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          RecipientHomeTab(recipientData: _recipientData, primaryColor: _primaryColor),
          RecipientSearchTab(recipientData: _recipientData, primaryColor: _primaryColor),
          RecipientProfileTab(recipientData: _recipientData, primaryColor: _primaryColor, onDataUpdated: _fetchRecipientData),
        ],
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildBottomNav() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 20, offset: const Offset(0, -5)),
        ],
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: List.generate(_navItems.length, (index) {
              final isActive = _currentIndex == index;
              return GestureDetector(
                onTap: () => _onTabTap(index),
                behavior: HitTestBehavior.opaque,
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    decoration: BoxDecoration(
                      color: isActive ? _primaryColor.withValues(alpha: 0.12) : Colors.transparent,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Icon(_navItems[index].icon,
                        color: isActive ? _primaryColor : Colors.grey.shade400, size: 24),
                  ),
                  const SizedBox(height: 4),
                  AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 300),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                      color: isActive ? _primaryColor : Colors.grey.shade400,
                    ),
                    child: Text(_navItems[index].label),
                  ),
                ]),
              );
            }),
          ),
        ),
      ),
    );
  }
}

class _NavItem {
  final IconData icon;
  final String label;
  _NavItem({required this.icon, required this.label});
}
