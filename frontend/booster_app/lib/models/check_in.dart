/// docs/api/MVP_API_SPEC.md §8.2 (GET /api/challenges/{challengeId}/check-ins)
/// 응답 항목과 매핑되는 모델.
class CheckIn {
  final int checkInId;
  final String checkInDate; // yyyy-MM-dd
  final String status; // SUCCESS | FAILED | LATE_SUCCESS | PENDING

  CheckIn({required this.checkInId, required this.checkInDate, required this.status});

  factory CheckIn.fromJson(Map<String, dynamic> json) {
    return CheckIn(
      checkInId: json['checkInId'] as int,
      checkInDate: json['checkInDate'] as String,
      status: json['status'] as String,
    );
  }

  DateTime get date => DateTime.parse(checkInDate);
  bool get isSuccess => status == 'SUCCESS' || status == 'LATE_SUCCESS';
  bool get isRecovery => status == 'LATE_SUCCESS';
}
