import 'package:flutter_test/flutter_test.dart';
import 'package:showtime_app/models.dart';

void main() {
  group('money', () {
    test('formats in Indian grouping, not thousands', () {
      // 1,00,000 and not 100,000 - the audience is in Pune.
      expect(rupees(21000), '\u20B9210');
      expect(rupees(100000), '\u20B91,000');
      expect(rupees(10000000), '\u20B91,00,000');
      expect(rupees(0), '\u20B90');
    });

    test('paise are integers all the way, so totals cannot drift', () {
      // Three seats at 320.00 is exactly 960.00. A double would make this
      // 959.9999999999999 often enough to matter.
      expect(rupees(32000 * 3), '\u20B9960');
    });
  });

  group('seat status', () {
    test('a status the app has never heard of is treated as unavailable', () {
      final seat = Seat.fromJson({
        'id': 1,
        'row': 'A',
        'number': 1,
        'status': 'RESERVED_FOR_STAFF',
      });
      // Erring towards tappable would let the customer try to buy a seat the
      // server has already ruled out.
      expect(seat.status, SeatStatus.booked);
    });

    test('known statuses map through', () {
      Seat seat(String s) =>
          Seat.fromJson({'id': 1, 'row': 'A', 'number': 1, 'status': s});
      expect(seat('FREE').status, SeatStatus.free);
      expect(seat('HELD').status, SeatStatus.held);
      expect(seat('BOOKED').status, SeatStatus.booked);
    });

    test('label joins row and number the way the screen prints it', () {
      expect(Seat.fromJson({'id': 1, 'row': 'C', 'number': 12, 'status': 'FREE'}).label, 'C12');
    });
  });

  group('hold', () {
    Hold at(DateTime expiry) => Hold.fromJson({
          'token': 'abc',
          'showId': 1,
          'seatIds': [1, 2],
          'expiresAt': expiry.toUtc().toIso8601String(),
          'secondsRemaining': 300,
          'totalPaise': 42000,
        });

    test('remaining counts down to the server deadline', () {
      final hold = at(DateTime.now().add(const Duration(minutes: 4)));
      expect(hold.remaining.inSeconds, greaterThan(200));
      expect(hold.remaining.inSeconds, lessThanOrEqualTo(240));
    });

    test('an expired hold reports zero, never a negative countdown', () {
      // A negative duration formats as "-1:-30" on screen, which is how a
      // timer that has run out ends up looking like a bug.
      final hold = at(DateTime.now().subtract(const Duration(minutes: 1)));
      expect(hold.remaining, Duration.zero);
    });
  });

  test('a movie survives a field the server has not sent', () {
    final movie = Movie.fromJson({
      'id': 1,
      'title': 'Kantara',
      'language': 'Kannada',
      'durationMin': 148,
    });
    expect(movie.certificate, 'UA');
    expect(movie.synopsis, '');
  });
}
