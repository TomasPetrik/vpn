import 'package:equatable/equatable.dart';

class DiagnosticReportResult extends Equatable {
  const DiagnosticReportResult({
    required this.id,
    required this.createdAt,
    required this.summary,
  });

  final String id;
  final DateTime createdAt;
  final String summary;

  factory DiagnosticReportResult.fromJson(Map<String, dynamic> json) {
    final rawCreated = json['created_at']?.toString();
    return DiagnosticReportResult(
      id: '${json['id']}',
      createdAt: rawCreated == null || rawCreated.isEmpty
          ? DateTime.now().toUtc()
          : DateTime.tryParse(rawCreated)?.toUtc() ?? DateTime.now().toUtc(),
      summary: json['summary']?.toString() ?? 'Diagnostic report',
    );
  }

  @override
  List<Object?> get props => [id, createdAt, summary];
}
