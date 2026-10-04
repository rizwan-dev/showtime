import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'models.dart';

/// What went wrong, in terms the screen can act on.
///
/// The API distinguishes "someone else has that seat" (409) from "your hold
/// ran out" (410) on purpose, and flattening them into one error would throw
/// away the only thing that tells the customer what to do next.
sealed class ApiFailure implements Exception {
  const ApiFailure(this.message);
  final String message;
}

class SeatsUnavailable extends ApiFailure {
  const SeatsUnavailable(super.message);
}

class HoldExpired extends ApiFailure {
  const HoldExpired() : super('Your seats were released. Please pick again.');
}

class NotFound extends ApiFailure {
  const NotFound(super.message);
}

class Unreachable extends ApiFailure {
  const Unreachable(super.message);
}

class ServerError extends ApiFailure {
  const ServerError(super.message);
}

class ShowtimeApi {
  ShowtimeApi({String? baseUrl, http.Client? client})
      : baseUrl = baseUrl ?? _defaultBaseUrl(),
        _client = client ?? http.Client();

  final String baseUrl;
  final http.Client _client;

  /// The emulator and the simulator reach the development machine by different
  /// names: 10.0.2.2 is the host as seen from an Android emulator, while the
  /// iOS simulator shares the host's own loopback. Getting this wrong produces
  /// a connection error that looks like a server problem.
  static String _defaultBaseUrl() {
    const override = String.fromEnvironment('SHOWTIME_API');
    if (override.isNotEmpty) return override;
    if (Platform.isAndroid) return 'http://10.0.2.2:9193';
    return 'http://localhost:9193';
  }

  Future<List<Movie>> movies() async =>
      (await _get('/api/movies') as List<dynamic>)
          .map((e) => Movie.fromJson(e as Map<String, dynamic>))
          .toList();

  Future<List<Show>> shows(int movieId) async =>
      (await _get('/api/shows?movieId=$movieId') as List<dynamic>)
          .map((e) => Show.fromJson(e as Map<String, dynamic>))
          .toList();

  Future<SeatMap> seatMap(int showId) async =>
      SeatMap.fromJson(await _get('/api/shows/$showId/seats') as Map<String, dynamic>);

  Future<Hold> hold(int showId, List<int> seatIds) async => Hold.fromJson(
      await _post('/api/shows/$showId/holds', {'seatIds': seatIds})
          as Map<String, dynamic>);

  Future<Booking> confirm(String token, String customerName) async =>
      Booking.fromJson(await _post(
        '/api/bookings',
        {'token': token, 'customerName': customerName},
      ) as Map<String, dynamic>);

  /// Give the seats back when the customer walks away.
  ///
  /// Best effort on purpose: if this fails the hold still expires on its own,
  /// so surfacing an error here would be noise about something already handled.
  Future<void> release(String token) async {
    try {
      await _client
          .delete(Uri.parse('$baseUrl/api/holds/$token'))
          .timeout(const Duration(seconds: 5));
    } catch (_) {}
  }

  Future<Object?> _get(String path) => _send(() =>
      _client.get(Uri.parse('$baseUrl$path')).timeout(const Duration(seconds: 10)));

  Future<Object?> _post(String path, Map<String, Object?> body) => _send(() => _client
      .post(
        Uri.parse('$baseUrl$path'),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      )
      .timeout(const Duration(seconds: 10)));

  Future<Object?> _send(Future<http.Response> Function() request) async {
    final http.Response response;
    try {
      response = await request();
    } catch (e) {
      // The server never answered. Deliberately its own failure: "the API is
      // down" must never reach the customer as "those seats are taken".
      throw Unreachable('Could not reach the server. Is it running on $baseUrl?');
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (response.body.isEmpty) return null;
      return jsonDecode(response.body);
    }

    final message = _messageFrom(response.body);
    throw switch (response.statusCode) {
      409 => SeatsUnavailable(message ?? 'Those seats have just been taken.'),
      410 => const HoldExpired(),
      404 => NotFound(message ?? 'Not found'),
      _ => ServerError(message ?? 'Something went wrong (${response.statusCode})'),
    };
  }

  String? _messageFrom(String body) {
    if (body.isEmpty) return null;
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) return decoded['message'] as String?;
    } catch (_) {}
    return null;
  }
}
