import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';

enum CertificateType { donation, volunteer }

// Generates a simple, print-ready certificate PDF and opens the native
// share/print sheet so the organizer (or donor, if you wire this into the
// donor side too) can save or send it immediately.
//
// NOTE: Sowmi — if you already have a certificate generator from the
// donation-history feature, prefer merging this into that file instead of
// keeping two generators. This one intentionally mirrors that pattern
// (same libraries: pdf + printing) so merging should be low-friction.
// The bloodlink_logo.png wiring TODO from earlier sessions applies here
// too — swap the placeholder circle below for a pw.Image once the asset
// is in pubspec.yaml.
class CampCertificateHelper {
  static Future<void> generateAndShare({
    required String donorName,
    required String campTitle,
    required String organizerName,
    required DateTime date,
    required CertificateType type,
  }) async {
    final doc = pw.Document();
    final isDonation = type == CertificateType.donation;
    final dateStr = DateFormat('d MMMM yyyy').format(date);

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4.landscape,
        build: (context) => pw.Container(
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColor.fromHex('#E8483B'), width: 3),
          ),
          margin: const pw.EdgeInsets.all(16),
          padding: const pw.EdgeInsets.all(40),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            mainAxisAlignment: pw.MainAxisAlignment.center,
            children: [
              // TODO: replace with pw.Image(logoImage) once bloodlink_logo.png is wired in.
              pw.Container(
                width: 56, height: 56,
                decoration: pw.BoxDecoration(
                  shape: pw.BoxShape.circle,
                  color: PdfColor.fromHex('#E8483B'),
                ),
                alignment: pw.Alignment.center,
                child: pw.Text('BL', style: pw.TextStyle(color: PdfColors.white, fontSize: 20, fontWeight: pw.FontWeight.bold)),
              ),
              pw.SizedBox(height: 14),
              pw.Text('BloodLink', style: pw.TextStyle(fontSize: 14, color: PdfColor.fromHex('#888888'), letterSpacing: 2)),
              pw.SizedBox(height: 24),
              pw.Text(
                isDonation ? 'Certificate of Blood Donation' : 'Certificate of Appreciation',
                style: pw.TextStyle(fontSize: 26, fontWeight: pw.FontWeight.bold, color: PdfColor.fromHex('#1A1A2E')),
              ),
              pw.SizedBox(height: 28),
              pw.Text('This is proudly presented to', style: pw.TextStyle(fontSize: 12, color: PdfColor.fromHex('#888888'))),
              pw.SizedBox(height: 8),
              pw.Text(donorName, style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold, color: PdfColor.fromHex('#E8483B'))),
              pw.SizedBox(height: 20),
              pw.Text(
                isDonation
                    ? 'for generously donating blood at "$campTitle" on $dateStr,\nhelping save lives in the community.'
                    : 'for volunteering their time and effort at "$campTitle" on $dateStr,\nsupporting this life-saving initiative.',
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(fontSize: 13, color: PdfColor.fromHex('#444444'), lineSpacing: 4),
              ),
              pw.SizedBox(height: 36),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.center,
                children: [
                  pw.Column(children: [
                    pw.Container(width: 160, height: 1, color: PdfColor.fromHex('#CCCCCC')),
                    pw.SizedBox(height: 6),
                    pw.Text(organizerName, style: const pw.TextStyle(fontSize: 11)),
                    pw.Text('Organizer', style: pw.TextStyle(fontSize: 9, color: PdfColor.fromHex('#999999'))),
                  ]),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    await Printing.sharePdf(
      bytes: await doc.save(),
      filename: '${donorName.replaceAll(' ', '_')}_${isDonation ? 'donation' : 'volunteer'}_certificate.pdf',
    );
  }
}