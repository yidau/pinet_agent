typedef Json = Map<String, dynamic>;

Json jsonObject(Object? value, String field) {
  if (value is! Json) {
    throw FormatException('响应字段无效（$field）');
  }
  return value;
}
