import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';

// Extracted out of donor_profile_tab.dart's old inline _downloadCertificate
// so both the Profile tab and the new "My Certificates" list screen can
// generate this same lifetime-summary certificate without duplicating the
// PDF layout code.
class LifetimeCertificateHelper {
  static Future<void> generateAndShare({
    required String donorName,
    required String bloodGroup,
    required int verifiedCount,
  }) async {
    final doc = pw.Document();
    final issueDate = DateFormat('d MMMM yyyy').format(DateTime.now());
    final livesHelped = verifiedCount * 3;

    // Logo is bundled as an app asset. If it's ever missing for some
    // reason, the certificate still renders fine without it rather than
    // crashing the whole download.
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
              pw.Text('CERTIFICATE OF APPRECIATION', style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 30),
              pw.Text('This certificate is proudly presented to', style: const pw.TextStyle(fontSize: 12, color: PdfColors.grey700)),
              pw.SizedBox(height: 10),
              pw.Text(donorName, style: pw.TextStyle(fontSize: 28, fontWeight: pw.FontWeight.bold, color: PdfColors.red700)),
              pw.SizedBox(height: 10),
              pw.Text('Blood Group: $bloodGroup', style: const pw.TextStyle(fontSize: 12)),
              pw.SizedBox(height: 20),
              pw.Text(
                'In recognition of $verifiedCount verified blood donation${verifiedCount == 1 ? '' : 's'},\n'
                    'helping save up to $livesHelped ${livesHelped == 1 ? 'life' : 'lives'}.',
                textAlign: pw.TextAlign.center,
                style: const pw.TextStyle(fontSize: 13),
              ),
              pw.SizedBox(height: 40),
              pw.Text('Issued on $issueDate', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600)),
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
      filename: 'BloodLink_Certificate_${donorName.replaceAll(' ', '_')}.pdf',
    );
  }
}