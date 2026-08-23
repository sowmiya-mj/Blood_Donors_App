// PLACEMENT: lib/screens/donor/hospital_certificate_helper.dart
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';

// Per-donation certificate for donations completed through an SOS request
// (source: 'sos' in Firestore — covers both hospital-posted blood requests
// and SOS raised by other roles, since a hospital name/location is always
// attached at accept time). Mirrors CampCertificateHelper's per-event
// pattern and LifetimeCertificateHelper's visual style, so all three
// certificate types feel like the same family.
class HospitalCertificateHelper {
  static Future<void> generateAndShare({
    required String donorName,
    required String bloodGroup,
    required String hospitalOrLocation,
    required DateTime date,
  }) async {
    final doc = pw.Document();
    final issueDate = DateFormat('d MMMM yyyy').format(date);

    pw.MemoryImage? logo;
    try {
      final logoBytes = await rootBundle.load('assets/images/bloodlink_logo.png');
      logo = pw.MemoryImage(logoBytes.buffer.asUint8List());
    } catch (_) {
      logo = null;
    }

    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      build: (context) => pw.Container(
        padding: const pw.EdgeInsets.all(40),
        decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.red400, width: 3)),
        child: pw.Center(
          child: pw.Column(
            mainAxisAlignment: pw.MainAxisAlignment.center,
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              if (logo != null) ...[
                pw.Image(logo, width: 70, height: 70),
                pw.SizedBox(height: 10),
              ],
              pw.Text('BloodLink', style: pw.TextStyle(fontSize: 26, fontWeight: pw.FontWeight.bold, color: PdfColors.red700)),
              pw.Text("Your Blood. Someone's Tomorrow.", style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600)),
              pw.SizedBox(height: 30),
              pw.Text('CERTIFICATE OF BLOOD DONATION', style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 30),
              pw.Text('This certificate is proudly presented to', style: const pw.TextStyle(fontSize: 12, color: PdfColors.grey700)),
              pw.SizedBox(height: 10),
              pw.Text(donorName, style: pw.TextStyle(fontSize: 28, fontWeight: pw.FontWeight.bold, color: PdfColors.red700)),
              pw.SizedBox(height: 10),
              pw.Text('Blood Group: $bloodGroup', style: const pw.TextStyle(fontSize: 12)),
              pw.SizedBox(height: 20),
              pw.Text(
                'For responding to an urgent blood request and donating at\n'
                    '$hospitalOrLocation,\nhelping save a life through BloodLink.',
                textAlign: pw.TextAlign.center,
                style: const pw.TextStyle(fontSize: 13),
              ),
              pw.SizedBox(height: 40),
              pw.Text('Donated on $issueDate', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600)),
              pw.SizedBox(height: 24),
              pw.Container(width: 130, height: 1, color: PdfColors.grey400),
              pw.SizedBox(height: 6),
              pw.Text('BloodLink Team', style: pw.TextStyle(fontSize: 12, fontStyle: pw.FontStyle.italic, color: PdfColors.grey700)),
            ],
          ),
        ),
      ),
    ));

    await Printing.sharePdf(
      bytes: await doc.save(),
      filename: 'BloodLink_HospitalCertificate_${donorName.replaceAll(' ', '_')}_${DateFormat('yyyyMMdd').format(date)}.pdf',
    );
  }
}