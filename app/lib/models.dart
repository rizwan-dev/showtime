// The wire format, mirrored from the Ktor API.
//
// Every model parses defensively: a field the server adds tomorrow must not
// crash an app that is already installed, and a field it renames should fail
// here, loudly, rather than three screens later as a null.

enum SeatStatus { free, held, booked }

SeatStatus _seatStatus(String raw) => switch (raw) {
      'FREE' => SeatStatus.free,
      'HELD' => SeatStatus.held,
      'BOOKED' => SeatStatus.booked,
      // An unknown status is safest treated as unavailable: showing a seat as
      // tappable when the server meant something else sells a seat twice.
      _ => SeatStatus.booked,
    };

class Movie {
  const Movie({
    required this.id,
    required this.title,
    required this.language,
    required this.durationMin,
    required this.certificate,
    required this.synopsis,
  });

  final int id;
  final String title;
  final String language;
  final int durationMin;
  final String certificate;
  final String synopsis;

  factory Movie.fromJson(Map<String, dynamic> json) => Movie(
        id: json['id'] as int,
        title: json['title'] as String,
        language: json['language'] as String,
        durationMin: json['durationMin'] as int,
        certificate: json['certificate'] as String? ?? 'UA',
        synopsis: json['synopsis'] as String? ?? '',
      );
}

class Show {
  const Show({
    required this.id,
    required this.movieTitle,
    required this.screenName,
    required this.startsAt,
    required this.pricePaise,
    required this.seatsAvailable,
  });

  final int id;
  final String movieTitle;
  final String screenName;
  final DateTime startsAt;
  final int pricePaise;
  final int seatsAvailable;

  factory Show.fromJson(Map<String, dynamic> json) => Show(
        id: json['id'] as int,
        movieTitle: json['movieTitle'] as String,
        screenName: json['screenName'] as String,
        startsAt: DateTime.parse(json['startsAt'] as String).toLocal(),
        pricePaise: json['pricePaise'] as int,
        seatsAvailable: json['seatsAvailable'] as int,
      );
}

class Seat {
  const Seat({
    required this.id,
    required this.row,
    required this.number,
    required this.status,
  });

  final int id;
  final String row;
  final int number;
  final SeatStatus status;

  String get label => '$row$number';

  factory Seat.fromJson(Map<String, dynamic> json) => Seat(
        id: json['id'] as int,
        row: json['row'] as String,
        number: json['number'] as int,
        status: _seatStatus(json['status'] as String),
      );
}

class SeatRow {
  const SeatRow({required this.label, required this.seats});
  final String label;
  final List<Seat> seats;

  factory SeatRow.fromJson(Map<String, dynamic> json) => SeatRow(
        label: json['label'] as String,
        seats: (json['seats'] as List<dynamic>)
            .map((e) => Seat.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class SeatMap {
  const SeatMap({
    required this.showId,
    required this.movieTitle,
    required this.screenName,
    required this.startsAt,
    required this.pricePaise,
    required this.rows,
  });

  final int showId;
  final String movieTitle;
  final String screenName;
  final DateTime startsAt;
  final int pricePaise;
  final List<SeatRow> rows;

  factory SeatMap.fromJson(Map<String, dynamic> json) => SeatMap(
        showId: json['showId'] as int,
        movieTitle: json['movieTitle'] as String,
        screenName: json['screenName'] as String,
        startsAt: DateTime.parse(json['startsAt'] as String).toLocal(),
        pricePaise: json['pricePaise'] as int,
        rows: (json['rows'] as List<dynamic>)
            .map((e) => SeatRow.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class Hold {
  const Hold({
    required this.token,
    required this.showId,
    required this.seatIds,
    required this.expiresAt,
    required this.totalPaise,
  });

  final String token;
  final int showId;
  final List<int> seatIds;

  /// Absolute, from the server. The countdown is computed against this rather
  /// than trusting a duration the client started counting at an unknown moment.
  final DateTime expiresAt;
  final int totalPaise;

  Duration get remaining {
    final left = expiresAt.difference(DateTime.now());
    return left.isNegative ? Duration.zero : left;
  }

  factory Hold.fromJson(Map<String, dynamic> json) => Hold(
        token: json['token'] as String,
        showId: json['showId'] as int,
        seatIds: (json['seatIds'] as List<dynamic>).cast<int>(),
        expiresAt: DateTime.parse(json['expiresAt'] as String).toLocal(),
        totalPaise: json['totalPaise'] as int,
      );
}

class Booking {
  const Booking({
    required this.reference,
    required this.movieTitle,
    required this.screenName,
    required this.startsAt,
    required this.seats,
    required this.amountPaise,
    required this.customerName,
  });

  final String reference;
  final String movieTitle;
  final String screenName;
  final DateTime startsAt;
  final List<String> seats;
  final int amountPaise;
  final String customerName;

  factory Booking.fromJson(Map<String, dynamic> json) => Booking(
        reference: json['reference'] as String,
        movieTitle: json['movieTitle'] as String,
        screenName: json['screenName'] as String,
        startsAt: DateTime.parse(json['startsAt'] as String).toLocal(),
        seats: (json['seats'] as List<dynamic>).cast<String>(),
        amountPaise: json['amountPaise'] as int,
        customerName: json['customerName'] as String,
      );
}

/// Rupees from paise. Money is integer throughout; a double would introduce
/// rounding error into a total the server already computed exactly.
String rupees(int paise) {
  final whole = paise ~/ 100;
  final buffer = StringBuffer();
  final digits = whole.toString();
  // Indian grouping: last three digits, then pairs.
  if (digits.length <= 3) {
    buffer.write(digits);
  } else {
    final head = digits.substring(0, digits.length - 3);
    final tail = digits.substring(digits.length - 3);
    final grouped = <String>[];
    var rest = head;
    while (rest.length > 2) {
      grouped.insert(0, rest.substring(rest.length - 2));
      rest = rest.substring(0, rest.length - 2);
    }
    if (rest.isNotEmpty) grouped.insert(0, rest);
    buffer.write('${grouped.join(',')},$tail');
  }
  return '\u20B9$buffer';
}
