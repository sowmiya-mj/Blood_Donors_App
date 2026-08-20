import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback, rootBundle;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
// NOTE: adjust this relative path if your services folder sits somewhere
// else — this assumes lib/screens/common/camps/create_edit_camp_screen.dart
// and lib/services/notification_service.dart.
import '../../../services/notification_service.dart';

// Shared by Hospital and Blood Bank roles — pass organizerRole to tag who
// created the camp. Donor-facing DonorBloodCampsScreen reads organizer_name
// + organizer_role + organizer_phone + organizer_email straight off the
// saved doc, so no role-specific UI here.
class CreateEditCampScreen extends StatefulWidget {
  final Color primaryColor;
  final String organizerRole; // 'hospital' or 'blood_bank'
  final String organizerName;
  final String? organizerPhone;
  final String? organizerEmail;
  final Map<String, dynamic>? existingCamp; // null = create, non-null = edit
  final String? campId; // required when existingCamp is non-null

  const CreateEditCampScreen({
    super.key,
    required this.primaryColor,
    required this.organizerRole,
    required this.organizerName,
    this.organizerPhone,
    this.organizerEmail,
    this.existingCamp,
    this.campId,
  });

  @override
  State<CreateEditCampScreen> createState() => _CreateEditCampScreenState();
}

class _CreateEditCampScreenState extends State<CreateEditCampScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _startTimeCtrl = TextEditingController();
  final _endTimeCtrl = TextEditingController();
  final _maxSlotsCtrl = TextEditingController();

  DateTime? _selectedDate;
  String? _filterState;
  String? _filterDistrict;
  Map<String, dynamic> _locationData = {};
  List<String> _states = [];
  List<String> _districts = [];
  bool _loadingLocation = true;
  bool _isSaving = false;

  bool get _isEditing => widget.existingCamp != null;

  @override
  void initState() {
    super.initState();
    _loadLocationData();
    if (_isEditing) _prefill();
  }

  void _prefill() {
    final c = widget.existingCamp!;
    _titleCtrl.text = c['title'] ?? '';
    _descCtrl.text = c['description'] ?? '';
    _addressCtrl.text = c['address'] ?? '';
    _cityCtrl.text = c['city'] ?? '';
    _startTimeCtrl.text = c['start_time'] ?? '';
    _endTimeCtrl.text = c['end_time'] ?? '';
    final maxSlots = (c['max_slots'] as num?)?.toInt() ?? 0;
    if (maxSlots > 0) _maxSlotsCtrl.text = maxSlots.toString();
    _filterState = c['state'] as String?;
    _filterDistrict = c['district'] as String?;
    final ts = c['date'];
    if (ts is Timestamp) _selectedDate = ts.toDate();
  }

  Future<void> _loadLocationData() async {
    try {
      final String data = await rootBundle.loadString('assets/data/india_locations.json');
      final Map<String, dynamic> json = jsonDecode(data);
      setState(() {
        _locationData = json;
        _states = json.keys.toList()..sort();
        if (_filterState != null) {
          final stateData = json[_filterState] as Map<String, dynamic>? ?? {};
          _districts = stateData.keys.toList()..sort();
        }
        _loadingLocation = false;
      });
    } catch (_) {
      setState(() => _loadingLocation = false);
    }
  }

  void _onStateChanged(String? state) {
    setState(() {
      _filterState = state;
      _filterDistrict = null;
      if (state != null) {
        final stateData = _locationData[state] as Map<String, dynamic>? ?? {};
        _districts = stateData.keys.toList()..sort();
      } else {
        _districts = [];
      }
    });
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? today.add(const Duration(days: 7)),
      firstDate: today,
      lastDate: today.add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _selectedDate = picked);
  }

  Future<Map<String, double>?> _geocodeLocation(String query) async {
    try {
      final uri = Uri.parse(
          'https://nominatim.openstreetmap.org/search?format=json&limit=1&countrycodes=in&q=${Uri.encodeComponent(query)}');
      final res = await http.get(uri, headers: {'User-Agent': 'BloodLinkApp/1.0'});
      if (res.statusCode == 200) {
        final List data = jsonDecode(res.body);
        if (data.isNotEmpty) {
          final lat = double.tryParse(data[0]['lat'].toString());
          final lon = double.tryParse(data[0]['lon'].toString());
          if (lat != null && lon != null) return {'lat': lat, 'lng': lon};
        }
      }
    } catch (_) {}
    return null;
  }

  Future<void> _saveCamp() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedDate == null) {
      _showSnack('Please pick a camp date', isError: true);
      return;
    }
    if (_filterState == null || _filterDistrict == null) {
      _showSnack('Please select state and district', isError: true);
      return;
    }
    setState(() => _isSaving = true);

    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;

      final locationQuery = [_cityCtrl.text.trim(), _filterDistrict, _filterState]
          .where((e) => e != null && e.toString().isNotEmpty)
          .join(', ');
      final geo = locationQuery.isNotEmpty ? await _geocodeLocation(locationQuery) : null;

      final campData = <String, dynamic>{
        'organizer_uid': uid,
        'organizer_role': widget.organizerRole,
        'organizer_name': widget.organizerName,
        'organizer_phone': widget.organizerPhone ?? '',
        'organizer_email': widget.organizerEmail ?? '',
        'title': _titleCtrl.text.trim(),
        'description': _descCtrl.text.trim(),
        'date': Timestamp.fromDate(_selectedDate!),
        'start_time': _startTimeCtrl.text.trim(),
        'end_time': _endTimeCtrl.text.trim(),
        'address': _addressCtrl.text.trim(),
        'city': _cityCtrl.text.trim(),
        'district': _filterDistrict,
        'state': _filterState,
        'status': 'active',
        'max_slots': int.tryParse(_maxSlotsCtrl.text.trim()) ?? 0, // 0 = unlimited
      };
      if (geo != null) {
        campData['lat'] = geo['lat'];
        campData['lng'] = geo['lng'];
      }

      if (_isEditing) {
        await FirebaseFirestore.instance.collection('blood_camps').doc(widget.campId).update(campData);
      } else {
        campData['registered_count'] = 0;
        campData['waitlist_count'] = 0;
        campData['created_at'] = FieldValue.serverTimestamp();
        final campRef = await FirebaseFirestore.instance.collection('blood_camps').add(campData);
        // Fire-and-forget: notification failure should never block camp
        // creation from succeeding.
        _notifyNearbyDonors(campRef.id, campData);
      }

      if (mounted) {
        _showSnack(_isEditing ? 'Camp updated' : 'Camp published');
        Navigator.pop(context);
      }
    } catch (e) {
      _showSnack('Could not save camp: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // Notifies donors in the same district as the camp. District-level match
  // (not radius/state) keeps this simple and avoids spamming everyone —
  // easy to widen to state-level later if district match returns too few.
  Future<void> _notifyNearbyDonors(String campId, Map<String, dynamic> campData) async {
    try {
      final district = (campData['district'] ?? '').toString();
      if (district.isEmpty) return;

      final donorsSnap = await FirebaseFirestore.instance
          .collection('donors')
          .where('district', isEqualTo: district)
          .get();
      if (donorsSnap.docs.isEmpty) return;

      final dateStr = _formatDate(campData['date']);
      final title = 'New Blood Camp near you';
      final body = '${campData['title']} on $dateStr at ${campData['city']}. Tap to register!';

      await Future.wait(donorsSnap.docs.map((d) => NotificationService.send(
        toUid: d.id,
        type: 'new_camp',
        title: title,
        body: body,
        relatedId: campId,
      )));
    } catch (_) {
      // Never let a notification failure surface to the organizer.
    }
  }

  String _formatDate(dynamic ts) {
    if (ts is Timestamp) {
      final d = ts.toDate();
      return '${d.day}/${d.month}/${d.year}';
    }
    return '';
  }

  void _showSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? Colors.red.shade600 : Colors.green.shade600,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _addressCtrl.dispose();
    _cityCtrl.dispose();
    _startTimeCtrl.dispose();
    _endTimeCtrl.dispose();
    _maxSlotsCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.primaryColor;
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        backgroundColor: color,
        foregroundColor: Colors.white,
        title: Text(_isEditing ? 'Edit Camp' : 'Create Blood Camp'),
      ),
      body: _loadingLocation
          ? Center(child: CircularProgressIndicator(color: color))
          : Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _label('Camp Title'),
            TextFormField(
              controller: _titleCtrl,
              decoration: _inputDecoration('e.g. Community Blood Donation Drive', color),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 16),
            _label('Description'),
            TextFormField(
              controller: _descCtrl,
              maxLines: 3,
              decoration: _inputDecoration('What to expect, eligibility, etc.', color),
            ),
            const SizedBox(height: 16),
            _label('Camp Date'),
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: _pickDate,
              child: InputDecorator(
                decoration: _inputDecoration('Select date', color),
                child: Text(
                  _selectedDate == null ? 'Tap to select' : '${_selectedDate!.day}/${_selectedDate!.month}/${_selectedDate!.year}',
                  style: TextStyle(color: _selectedDate == null ? Colors.grey.shade400 : const Color(0xFF1A1A2E)),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _label('Start Time'),
                TextFormField(controller: _startTimeCtrl, decoration: _inputDecoration('9:00 AM', color)),
              ])),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _label('End Time'),
                TextFormField(controller: _endTimeCtrl, decoration: _inputDecoration('4:00 PM', color)),
              ])),
            ]),
            const SizedBox(height: 16),
            _label('Expected / Max Donors (optional)'),
            TextFormField(
              controller: _maxSlotsCtrl,
              keyboardType: TextInputType.number,
              decoration: _inputDecoration('e.g. 50 — leave blank for unlimited', color),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('Once this many donors confirm, new registrations go to a waitlist automatically.',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
            ),
            const SizedBox(height: 16),
            _label('State'),
            DropdownButtonFormField<String>(
              initialValue: _filterState,
              isExpanded: true,
              decoration: _inputDecoration('Select state', color),
              items: _states.map((s) => DropdownMenuItem(value: s, child: Text(s, overflow: TextOverflow.ellipsis))).toList(),
              onChanged: _onStateChanged,
              validator: (v) => v == null ? 'Required' : null,
            ),
            const SizedBox(height: 16),
            _label('District'),
            DropdownButtonFormField<String>(
              initialValue: _filterDistrict,
              isExpanded: true,
              decoration: _inputDecoration('Select district', color),
              items: _districts.map((d) => DropdownMenuItem(value: d, child: Text(d, overflow: TextOverflow.ellipsis))).toList(),
              onChanged: (v) => setState(() => _filterDistrict = v),
              validator: (v) => v == null ? 'Required' : null,
            ),
            const SizedBox(height: 16),
            _label('City / Town'),
            TextFormField(
              controller: _cityCtrl,
              decoration: _inputDecoration('e.g. Bhavani', color),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 16),
            _label('Venue Address'),
            TextFormField(
              controller: _addressCtrl,
              maxLines: 2,
              decoration: _inputDecoration('Full venue address', color),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isSaving ? null : _saveCamp,
                style: ElevatedButton.styleFrom(
                  backgroundColor: color,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: _isSaving
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : Text(_isEditing ? 'Save Changes' : 'Publish Camp', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(text, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey.shade600)),
  );

  InputDecoration _inputDecoration(String hint, Color color) => InputDecoration(
    hintText: hint,
    filled: true,
    fillColor: Colors.white,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade200)),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade200)),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: color, width: 1.5)),
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
  );
}