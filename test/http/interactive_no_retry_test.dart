import 'dart:typed_data';

import 'package:Pilipili/http/retry_interceptor.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

class FailedSubmissionAdapter implements HttpClientAdapter {
  int attempts = 0;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    attempts++;
    return Future.error(
      DioException.connectionError(
        requestOptions: options,
        reason: 'test connection lost',
      ),
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  test(
    'interactive POST is never retried on an ambiguous connection failure',
    () async {
      final dio = Dio();
      final adapter = FailedSubmissionAdapter();
      dio.httpClientAdapter = adapter;
      dio.interceptors.add(RetryInterceptor(dio, 3, 0));
      try {
        await dio.post(
          'https://api.bilibili.com/x/v2/dm/command/grade/post',
          data: {'grade_score': 10},
          options: Options(
            extra: {'disableRetry': true},
            followRedirects: false,
          ),
        );
        fail('request should fail');
      } on DioException {
        expect(adapter.attempts, 1);
      } finally {
        dio.close(force: true);
      }
    },
  );
}
