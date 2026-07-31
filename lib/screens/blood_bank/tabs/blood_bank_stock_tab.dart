import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class BloodBankStockTab extends StatefulWidget {
  final Map<String, dynamic>? bankData;
  final Color primaryColor;
  final VoidCallback onDataUpdated;

  const BloodBankStockTab({
    super.key,
    required this.bankData,
    required this.primaryColor,
    required this.onDataUpdated,
  });

  @override
  State<BloodBankStockTab> createState() => _BloodBankStockTabState();
}

class _BloodBankStockTabState extends State<BloodBankStockTab> {
  static const List<String> _bloodGroups = ['A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-'];
  static const int _lowStockThreshold = 5;

  bool _isSaving = false;
  late Map<String, int> _editedStock;

  @override
  void initState() {
    super.initState();
    _editedStock = _stockFromData();
  }

  @override
  void didUpdateWidget(covariant BloodBankStockTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Re-sync local edits whenever fresh data comes in from parent (e.g. after save)
    if (oldWidget.bankData != widget.bankData) {
      _editedStock = _stockFromData();
    }
  }

  Map<String, int> _stockFromData() {
    final raw = widget.bankData?['stock'] as Map<String, dynamic>? ?? {};
    return {for (final g in _bloodGroups) g: (raw[g] ?? 0) as int};
  }

  void _adjust(String group, int delta) {
    setState(() {
      final current = _editedStock[group] ?? 0;
      _editedStock[group] = (current + delta).clamp(0, 9999);
    });
  }

  Future<void> _saveStock() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    setState(() => _isSaving = true);
    try {
      await FirebaseFirestore.instance.collection('blood_banks').doc(uid).update({
        'stock': _editedStock,
      });
      widget.onDataUpdated();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Stock updated successfully'), duration: Duration(seconds: 2)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.primaryColor;
    final totalUnits = _editedStock.values.fold<int>(0, (a, b) => a + b);

    return SafeArea(
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
          child: Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Stock Management', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF1A1A2E))),
              const SizedBox(height: 4),
              Text('$totalUnits total units', style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
            ])),
          ]),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
            itemCount: _bloodGroups.length,
            itemBuilder: (context, index) {
              final group = _bloodGroups[index];
              final units = _editedStock[group] ?? 0;
              final isLow = units < _lowStockThreshold;

              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: isLow ? Colors.red.shade200 : Colors.grey.shade200),
                ),
                child: Row(children: [
                  Container(
                    width: 46, height: 46,
                    decoration: BoxDecoration(
                      color: (isLow ? Colors.red : color).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(child: Text(group,
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: isLow ? Colors.red.shade700 : color))),
                  ),
                  const SizedBox(width: 14),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('$units units', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFF1A1A2E))),
                    if (isLow) Text('Low stock', style: TextStyle(fontSize: 11, color: Colors.red.shade400, fontWeight: FontWeight.w500)),
                  ])),
                  _StepperButton(icon: Icons.remove, color: color, onTap: () => _adjust(group, -1)),
                  const SizedBox(width: 8),
                  _StepperButton(icon: Icons.add, color: color, onTap: () => _adjust(group, 1)),
                ]),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: SizedBox(
            width: double.infinity, height: 52,
            child: ElevatedButton(
              onPressed: _isSaving ? null : _saveStock,
              style: ElevatedButton.styleFrom(
                backgroundColor: color, foregroundColor: Colors.white,
                disabledBackgroundColor: color.withValues(alpha: 0.6), elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: _isSaving
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                  : const Text('Save Stock Changes', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            ),
          ),
        ),
      ]),
    );
  }
}

class _StepperButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _StepperButton({required this.icon, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 34, height: 34,
        decoration: BoxDecoration(color: color.withValues(alpha: 0.1), shape: BoxShape.circle),
        child: Icon(icon, size: 18, color: color),
      ),
    );
  }
}
