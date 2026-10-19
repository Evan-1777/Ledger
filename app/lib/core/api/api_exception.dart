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
    final message = _localize(serverMessage);
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

  static String? _localize(String? raw) {
    final message = raw?.trim();
    if (message == null || message.isEmpty) return null;
    return switch (message) {
      'payment method already exists' => '该渠道名称已存在',
      'category already exists' => '分类名称已存在',
      'tag already exists in this category' => '该分类下已存在同名标签',
      'duplicate tag name or invalid update' => '标签名称已存在或更新无效',
      _ => message,
    };
  }

  @override
  String toString() => message;
}
