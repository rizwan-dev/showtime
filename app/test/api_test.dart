import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:showtime_app/api.dart';

/// The status codes carry meaning, and the app acts on each one differently.
/// Collapsing them into "request failed" is what produces an app that tells a
/// customer their seats are gone when the server is simply down.
void main() {
  ShowtimeApi apiReturning(int status, Object? body) => ShowtimeApi(
        baseUrl: 'http://test',
        client: MockClient((_) async => http.Response(
              body == null ? '' : jsonEncode(body),
              status,
              headers: {'content-type': 'application/json'},
            )),
      );

  test('409 means somebody else got the seats', () async {
    final api = apiReturning(409, {'code': 'seats_unavailable', 'message': 'Seats gone: [4]'});
    expect(
      () => api.hold(1, [4]),
      throwsA(isA<SeatsUnavailable>().having((e) => e.message, 'message', contains('[4]'))),
    );
  });

  test('410 means the hold ran out, which is not the same thing', () async {
    final api = apiReturning(410, {'code': 'hold_expired', 'message': 'That hold has expired'});
    expect(() => api.confirm('token', 'Rizwan'), throwsA(isA<HoldExpired>()));
  });

  test('404 is not found', () async {
    final api = apiReturning(404, {'code': 'show_not_found', 'message': 'No show with id 9'});
    expect(() => api.seatMap(9), throwsA(isA<NotFound>()));
  });

  test('500 is a server error, not a seat problem', () async {
    final api = apiReturning(500, {'code': 'internal_error', 'message': 'boom'});
    expect(() => api.movies(), throwsA(isA<ServerError>()));
  });

  test('a dead connection is its own failure, never "seats taken"', () async {
    final api = ShowtimeApi(
      baseUrl: 'http://test',
      client: MockClient((_) async => throw http.ClientException('no route')),
    );
    expect(() => api.movies(), throwsA(isA<Unreachable>()));
  });

  test('releasing a hold swallows failures, because expiry handles it anyway', () async {
    final api = ShowtimeApi(
      baseUrl: 'http://test',
      client: MockClient((_) async => throw http.ClientException('no route')),
    );
    // Must not throw: the hold expires on its own, so an error here would be
    // noise about a problem that is already solved.
    await api.release('token');
  });

  test('a successful hold parses the server deadline', () async {
    final api = apiReturning(201, {
      'token': 'tok',
      'showId': 1,
      'seatIds': [4, 5],
      'expiresAt': '2030-01-01T00:05:00Z',
      'secondsRemaining': 300,
      'totalPaise': 42000,
    });
    final hold = await api.hold(1, [4, 5]);
    expect(hold.token, 'tok');
    expect(hold.seatIds, [4, 5]);
    expect(hold.totalPaise, 42000);
  });
}
