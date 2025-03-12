class WarningMessage {
  final bool warning;
  final String reason;

  WarningMessage({required this.warning, required this.reason});

  factory WarningMessage.fromJson(Map<String, dynamic> json) {
    return WarningMessage(
      warning: json['warning'] as bool,
      reason: json['reason'] as String
    );
  }
}