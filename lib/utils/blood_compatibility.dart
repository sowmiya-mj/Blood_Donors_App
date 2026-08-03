/// Standard donor → recipient blood compatibility chart.
/// Key = donor's blood group, Value = set of blood groups that donor
/// can safely give blood to.
///
/// O-  is the universal donor (can give to everyone).
/// AB+ is the universal recipient (can receive from everyone).
class BloodCompatibility {
  BloodCompatibility._();

  static const Map<String, List<String>> _canDonateTo = {
    'O-': ['O-', 'O+', 'A-', 'A+', 'B-', 'B+', 'AB-', 'AB+'],
    'O+': ['O+', 'A+', 'B+', 'AB+'],
    'A-': ['A-', 'A+', 'AB-', 'AB+'],
    'A+': ['A+', 'AB+'],
    'B-': ['B-', 'B+', 'AB-', 'AB+'],
    'B+': ['B+', 'AB+'],
    'AB-': ['AB-', 'AB+'],
    'AB+': ['AB+'],
  };

  /// Returns true if [donorGroup] can donate to a patient needing [requestGroup].
  /// Unknown/blank groups default to false (fail closed — never suggest an
  /// unsafe match just because data is missing).
  static bool canDonate(String donorGroup, String requestGroup) {
    final donor = donorGroup.trim().toUpperCase();
    final request = requestGroup.trim().toUpperCase();
    if (donor.isEmpty || request.isEmpty) return false;
    return _canDonateTo[donor]?.contains(request) ?? false;
  }
}