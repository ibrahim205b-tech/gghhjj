/// Domain error carrying an Arabic user-facing message.
class DomainException implements Exception {
  final String code;
  final String message;
  const DomainException(this.code, this.message);
  @override
  String toString() => 'DomainException($code): $message';
}

class PermissionDenied extends DomainException {
  const PermissionDenied(String permission)
      : super('PERMISSION_DENIED', 'ليست لديك صلاحية لتنفيذ هذه العملية ($permission).');
}

DomainException validation(String message) => DomainException('VALIDATION', message);
