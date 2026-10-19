enum ApiErrorKind {
  unauthorized,
  badRequest,
  conflict,
  notFound,
  server,
  network,
  timeout,
  invalidResponse,
  invalidServer,
}

class ApiException implements Exception {
  const ApiException(this.kind, this.message, {this.statusCode});

  final ApiErrorKind kind;
  final String message;
  final int? statusCode;

  bool get isUnauthorized => kind == ApiErrorKind.unauthorized;

  factory ApiException.fromStatus(int status, String? serverMessage) {
    final message = (serverMessage == null || serverMessage.trim().isEmpty)
        ? null
        : serverMessage.trim();
    return switch (status) {
      401 => ApiException(
        ApiErrorKind.unauthorized,
        message ?? '登录已过期，请重新输入管理员密码',
        statusCode: status,
      ),
      400 => ApiException(
        ApiErrorKind.badRequest,
        message ?? '请求无效',
        statusCode: status,
      ),
      404 => ApiException(
        ApiErrorKind.notFound,
        message ?? '请求的数据不存在',
        statusCode: status,
      ),
      409 => ApiException(
        ApiErrorKind.conflict,
        message ?? '该数据已被引用，无法删除',
        statusCode: status,
      ),
      _ => ApiException(
        ApiErrorKind.server,
        message ?? '服务器错误，请稍后重试',
        statusCode: status,
      ),
    };
  }

  static const network = ApiException(ApiErrorKind.network, '无法连接服务器，请检查地址与网络');
  static const timeout = ApiException(ApiErrorKind.timeout, '请求超时，请稍后重试');
  static const invalidResponse = ApiException(
    ApiErrorKind.invalidResponse,
    '服务器返回了无法识别的数据',
  );
  static const invalidServer = ApiException(
    ApiErrorKind.invalidServer,
    '请输入以 http:// 或 https:// 开头的服务器地址，仅填协议、域名与端口',
  );

  @override
  String toString() => message;
}
