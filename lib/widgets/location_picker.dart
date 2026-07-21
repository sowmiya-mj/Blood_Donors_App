import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class LocationPicker extends StatefulWidget {
  final Color color;
  final Function(String state, String district, String city) onLocationChanged;

  const LocationPicker({
    super.key,
    required this.color,
    required this.onLocationChanged,
  });

  @override
  State<LocationPicker> createState() => _LocationPickerState();
}

class _LocationPickerState extends State<LocationPicker> {
  Map<String, dynamic> _locationData = {};
  List<String> _states = [];
  List<String> _districts = [];
  List<String> _cities = [];

  String? _selectedState;
  String? _selectedDistrict;
  String? _selectedCity;
  bool _typeCity = false;
  final _cityCtrl = TextEditingController();
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadLocationData();
  }

  @override
  void dispose() {
    _cityCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadLocationData() async {
    try {
      final String data = await rootBundle
          .loadString('assets/data/india_locations.json');
      final Map<String, dynamic> jsonData = jsonDecode(data);
      setState(() {
        _locationData = jsonData;
        _states = jsonData.keys.toList()..sort();
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  void _onStateChanged(String? state) {
    if (state == null) return;
    final stateData = _locationData[state] as Map<String, dynamic>? ?? {};
    setState(() {
      _selectedState = state;
      _selectedDistrict = null;
      _selectedCity = null;
      _cityCtrl.clear();
      _typeCity = false;
      _districts = stateData.keys.toList()..sort();
      _cities = [];
    });
    widget.onLocationChanged(state, '', '');
  }

  void _onDistrictChanged(String? district) {
    if (district == null || _selectedState == null) return;
    final stateData = _locationData[_selectedState] as Map<String, dynamic>? ?? {};
    final cityList = stateData[district] as List<dynamic>? ?? [];
    setState(() {
      _selectedDistrict = district;
      _selectedCity = null;
      _cityCtrl.clear();
      _typeCity = false;
      _cities = cityList.map((e) => e.toString()).toList()..sort();
    });
    widget.onLocationChanged(_selectedState ?? '', district, '');
  }

  void _onCityChanged(String city) {
    setState(() => _selectedCity = city);
    widget.onLocationChanged(_selectedState ?? '', _selectedDistrict ?? '', city);
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color;

    if (_isLoading) {
      return Center(child: CircularProgressIndicator(color: color));
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // State Dropdown
      _buildLabel('State'),
      const SizedBox(height: 8),
      _buildDropdown(
        hint: 'Select State',
        icon: Icons.map_outlined,
        value: _selectedState,
        items: _states,
        color: color,
        onChanged: _onStateChanged,
      ),
      const SizedBox(height: 16),

      // District Dropdown
      _buildLabel('District'),
      const SizedBox(height: 8),
      _buildDropdown(
        hint: _selectedState == null ? 'Select State first' : 'Select District',
        icon: Icons.location_on_outlined,
        value: _selectedDistrict,
        items: _districts,
        color: color,
        enabled: _selectedState != null,
        onChanged: _onDistrictChanged,
      ),
      const SizedBox(height: 16),

      // City
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        _buildLabel('City'),
        if (_selectedDistrict != null)
          GestureDetector(
            onTap: () => setState(() {
              _typeCity = !_typeCity;
              _selectedCity = null;
              _cityCtrl.clear();
            }),
            child: Text(
              _typeCity ? '← Choose from list' : 'Type manually →',
              style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w500),
            ),
          ),
      ]),
      const SizedBox(height: 8),

      if (_typeCity)
      // Manual type
        TextFormField(
          controller: _cityCtrl,
          style: const TextStyle(fontSize: 15),
          onChanged: _onCityChanged,
          decoration: InputDecoration(
            hintText: 'Type your city name',
            hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
            prefixIcon: Icon(Icons.location_city_outlined, color: Colors.grey.shade400, size: 20),
            filled: true, fillColor: Colors.grey.shade50,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade200)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade200)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: color, width: 1.5)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
        )
      else
        _buildDropdown(
          hint: _selectedDistrict == null ? 'Select District first' : 'Select City',
          icon: Icons.location_city_outlined,
          value: _selectedCity,
          items: _cities,
          color: color,
          enabled: _selectedDistrict != null && _cities.isNotEmpty,
          onChanged: (val) { if (val != null) _onCityChanged(val); },
        ),
    ]);
  }

  Widget _buildLabel(String text) {
    return Text(text, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1A1A2E)));
  }

  Widget _buildDropdown({
    required String hint,
    required IconData icon,
    required String? value,
    required List<String> items,
    required Color color,
    required Function(String?) onChanged,
    bool enabled = true,
  }) {
    return IgnorePointer(
      ignoring: !enabled,
      child: Opacity(
        opacity: enabled ? 1.0 : 0.5,
        child: DropdownButtonFormField<String>(
          value: value,
          isExpanded: true,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
            prefixIcon: Icon(icon, color: Colors.grey.shade400, size: 20),
            filled: true, fillColor: Colors.grey.shade50,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade200)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade200)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: color, width: 1.5)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
          items: items.map((item) => DropdownMenuItem(
            value: item,
            child: Text(item, style: const TextStyle(fontSize: 14), overflow: TextOverflow.ellipsis),
          )).toList(),
          onChanged: onChanged,
          icon: Icon(Icons.keyboard_arrow_down_rounded, color: Colors.grey.shade400),
          dropdownColor: Colors.white,
          menuMaxHeight: 300,
        ),
      ),
    );
  }
}
