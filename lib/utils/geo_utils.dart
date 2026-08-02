import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;

/// Shared location helpers — used by the search-tab map view and by
/// NearbySosSection for radius filtering, so there's one Nominatim
/// integration to maintain instead of copies in every screen.
class GeoUtils {
  /// Great-circle distance between two points, in kilometers.
  static double distanceKm(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371.0; // Earth radius in km
    final dLat = _deg2rad(lat2 - lat1);
    final dLon = _deg2rad(lon2 - lon1);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_deg2rad(lat1)) * cos(_deg2rad(lat2)) * sin(dLon / 2) * sin(dLon / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return r * c;
  }

  static double _deg2rad(double deg) => deg * (pi / 180);

  /// Geocodes a free-text location ("city, district, state") via Nominatim.
  /// Returns null if it can't be resolved — caller should handle that
  /// gracefully rather than crash (e.g. skip radius filtering for that item).
  static Future<({double lat, double lng})?> geocode(String query) async {
    try {
      final uri = Uri.parse(
          'https://nominatim.openstreetmap.org/search?format=json&limit=1&countrycodes=in&q=${Uri.encodeComponent(query)}');
      final res = await http.get(uri, headers: {'User-Agent': 'BloodLinkApp/1.0'});
      if (res.statusCode == 200) {
        final List data = jsonDecode(res.body);
        if (data.isNotEmpty) {
          final lat = double.tryParse(data[0]['lat'].toString());
          final lon = double.tryParse(data[0]['lon'].toString());
          if (lat != null && lon != null) return (lat: lat, lng: lon);
        }
      }
    } catch (_) {}
    return null;
  }
}
