import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class RecipientSearchTab extends StatefulWidget {
  final Map<String, dynamic>? recipientData;
  final Color primaryColor;

  const RecipientSearchTab({super.key, required this.recipientData, required this.primaryColor});

  @override
  State<RecipientSearchTab> createState() => _RecipientSearchTabState();
}

class _RecipientSearchTabState extends State<RecipientSearchTab>
    with SingleTickerProviderStateMixin {
  String? _selectedBloodGroup;
  final TextEditingController _cityCtrl = TextEditingController();
  bool _isSearching = false;
  List<Map<String, dynamic>> _donors = [];
  int _searchMode = 0; // 0 = donors, 1 = blood banks

  late AnimationController _fadeController;
  late Animation<double> _fadeAnim;

  final List<String> _bloodGroups = ['A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-'];

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _fadeAnim = CurvedAnimation(parent: _fadeController, curve: Curves.easeOut);
    _fadeController.forward();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _cityCtrl.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    if (_selectedBloodGroup == null && _searchMode == 0) return;
    setState(() { _isSearching = true; _donors = []; });
    try {
      QuerySnapshot snap;
      if (_searchMode == 0) {
        Query query = FirebaseFirestore.instance
            .collection('donors')
            .where('blood_group', isEqualTo: _selectedBloodGroup)
            .where('is_available', isEqualTo: true);
        if (_cityCtrl.text.isNotEmpty) {
          query = query.where('city', isEqualTo: _cityCtrl.text.trim());
        }
        snap = await query.limit(20).get();
      } else {
        Query query = FirebaseFirestore.instance.collection('blood_banks');
        if (_cityCtrl.text.isNotEmpty) {
          query = query.where('city', isEqualTo: _cityCtrl.text.trim());
        }
        snap = await query.limit(20).get();
      }
      setState(() {
        _donors = snap.docs.map((d) => d.data() as Map<String, dynamic>).toList();
      });
    } catch (_) {} finally {
      setState(() => _isSearching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.primaryColor;

    return SafeArea(
      child: FadeTransition(
        opacity: _fadeAnim,
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Search', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF1A1A2E))),
            const SizedBox(height: 4),
            Text('Find donors or blood banks near you',
                style: TextStyle(fontSize: 14, color: Colors.grey.shade500)),
            const SizedBox(height: 20),

            // Toggle — Donors / Blood Banks
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(children: [
                _buildToggle('Donors', 0, color),
                _buildToggle('Blood Banks', 1, color),
              ]),
            ),

            const SizedBox(height: 20),

            // Blood group (donors only)
            if (_searchMode == 0) ...[
              const Text('Blood Group', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1A1A2E))),
              const SizedBox(height: 10),
              Wrap(
                spacing: 10, runSpacing: 10,
                children: _bloodGroups.map((g) {
                  final sel = _selectedBloodGroup == g;
                  return GestureDetector(
                    onTap: () { HapticFeedback.lightImpact(); setState(() => _selectedBloodGroup = g); },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 58, height: 42,
                      decoration: BoxDecoration(
                        color: sel ? color : Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: sel ? color : Colors.grey.shade200, width: sel ? 2 : 1),
                        boxShadow: sel ? [BoxShadow(color: color.withValues(alpha: 0.3), blurRadius: 8)] : [],
                      ),
                      child: Center(child: Text(g,
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                              color: sel ? Colors.white : Colors.grey.shade700))),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
            ],

            // City
            TextField(
              controller: _cityCtrl,
              decoration: InputDecoration(
                hintText: _searchMode == 0 ? 'City (optional)' : 'City',
                hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
                prefixIcon: Icon(Icons.location_city_outlined, color: Colors.grey.shade400),
                filled: true, fillColor: Colors.white,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade200)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade200)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: color, width: 1.5)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
            ),

            const SizedBox(height: 16),

            SizedBox(
              width: double.infinity, height: 50,
              child: ElevatedButton.icon(
                onPressed: _isSearching ? null : _search,
                icon: _isSearching
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.search_rounded),
                label: Text(_isSearching ? 'Searching...' : 'Search'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: color, foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
              ),
            ),

            const SizedBox(height: 20),

            // Results
            if (_donors.isNotEmpty) ...[
              Text('${_donors.length} results found',
                  style: TextStyle(fontSize: 14, color: Colors.grey.shade600, fontWeight: FontWeight.w500)),
              const SizedBox(height: 12),
              ..._donors.asMap().entries.map((entry) {
                final i = entry.key;
                final d = entry.value;
                return TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: 1),
                  duration: Duration(milliseconds: 300 + i * 80),
                  builder: (context, val, child) => Opacity(
                    opacity: val,
                    child: Transform.translate(offset: Offset(0, 20 * (1 - val)), child: child),
                  ),
                  child: _searchMode == 0
                      ? _buildDonorCard(d, color)
                      : _buildBankCard(d, color),
                );
              }),
            ],

            if (_donors.isEmpty && !_isSearching)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(30),
                  child: Column(children: [
                    Icon(Icons.search_rounded, size: 50, color: Colors.grey.shade200),
                    const SizedBox(height: 12),
                    Text('Search to find results',
                        style: TextStyle(color: Colors.grey.shade400, fontSize: 15)),
                  ]),
                ),
              ),
          ]),
        ),
      ),
    );
  }

  Widget _buildToggle(String label, int index, Color color) {
    final active = _searchMode == index;
    return Expanded(
      child: GestureDetector(
        onTap: () { HapticFeedback.lightImpact(); setState(() { _searchMode = index; _donors = []; }); },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: active ? color : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w600,
                color: active ? Colors.white : Colors.grey.shade500,
              )),
        ),
      ),
    );
  }

  Widget _buildDonorCard(Map<String, dynamic> d, Color color) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Row(children: [
        Container(
          width: 46, height: 46,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color.withValues(alpha: 0.1)),
          child: Center(child: Text(d['blood_group'] ?? '?',
              style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 14))),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(d['name'] ?? 'Anonymous',
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: Color(0xFF1A1A2E))),
          Text('${d['city'] ?? ''} • Age ${d['age'] ?? 'N/A'}',
              style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
        ])),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(8)),
          child: Text('Available', style: TextStyle(color: Colors.green.shade600, fontSize: 11, fontWeight: FontWeight.w600)),
        ),
      ]),
    );
  }

  Widget _buildBankCard(Map<String, dynamic> d, Color color) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Row(children: [
        Container(
          width: 46, height: 46,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color.withValues(alpha: 0.1)),
          child: Icon(Icons.local_hospital_rounded, color: color, size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(d['bank_name'] ?? 'Blood Bank',
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: Color(0xFF1A1A2E))),
          Text('${d['city'] ?? ''}, ${d['state'] ?? ''}',
              style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
          Text(d['phone'] ?? '', style: TextStyle(color: Colors.grey.shade400, fontSize: 12)),
        ])),
        Icon(Icons.arrow_forward_ios_rounded, color: Colors.grey.shade300, size: 16),
      ]),
    );
  }
}
