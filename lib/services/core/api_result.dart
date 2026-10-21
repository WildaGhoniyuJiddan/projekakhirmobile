/// Hasil panggilan API yang type-safe.
///
/// Pola pakai:
/// ```dart
/// final ApiResult<User> result = await repo.getUser();
/// switch (result) {
///   case ApiSuccess(:final data):
///   case ApiError(:final message):
/// }
/// ```
sealed class ApiResult<T> {
  const ApiResult();
}

/// Operasi masih berjalan.
final class ApiLoading<T> extends ApiResult<T> {
  const ApiLoading();
}

/// Operasi berhasil.
final class ApiSuccess<T> extends ApiResult<T> {
  const ApiSuccess(this.data);
  final T data;
}

/// Operasi gagal — [message] sudah diterjemahkan ke Bahasa Indonesia
/// bila memungkinkan; [statusCode] opsional untuk branching (mis. 401).
final class ApiError<T> extends ApiResult<T> {
  const ApiError(this.message, [this.statusCode]);
  final String message;
  final int? statusCode;
}
