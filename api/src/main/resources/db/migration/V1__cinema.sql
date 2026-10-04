-- The catalogue and booking tables, carried over from the Pune Cinemas data
-- layer (github.com/RizTech-Academy/cinema-booking) with its constraints intact.
-- Money is integer paise. Seats are rows, not a count, because the requirement
-- is per-seat: a count cannot say "A5 is taken but A6 is free".

CREATE TABLE movies (
  id           bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  title        text NOT NULL,
  language     text NOT NULL,
  duration_min int  NOT NULL CHECK (duration_min > 0),
  certificate  text NOT NULL DEFAULT 'UA',
  synopsis     text NOT NULL DEFAULT '',
  created_at   timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE screens (
  id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  name        text NOT NULL,
  total_seats int  NOT NULL CHECK (total_seats > 0)
);

CREATE TABLE seats (
  id        bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  screen_id bigint NOT NULL REFERENCES screens(id),
  row_label text   NOT NULL,
  seat_num  int    NOT NULL,
  UNIQUE (screen_id, row_label, seat_num)
);

CREATE TABLE shows (
  id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  movie_id    bigint NOT NULL REFERENCES movies(id),
  screen_id   bigint NOT NULL REFERENCES screens(id),
  starts_at   timestamptz NOT NULL,
  price_paise int    NOT NULL CHECK (price_paise > 0)
);

CREATE TABLE bookings (
  id           bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  reference    text   NOT NULL UNIQUE,
  show_id      bigint NOT NULL REFERENCES shows(id),
  customer_name text  NOT NULL,
  status       text   NOT NULL DEFAULT 'confirmed'
                 CHECK (status IN ('confirmed','cancelled')),
  amount_paise int    NOT NULL CHECK (amount_paise >= 0),
  created_at   timestamptz NOT NULL DEFAULT now()
);

-- The single most important line in the schema. Whatever the application layer
-- believes, the database will not accept the same seat twice for one show.
CREATE TABLE booking_seats (
  booking_id bigint NOT NULL REFERENCES bookings(id) ON DELETE CASCADE,
  show_id    bigint NOT NULL REFERENCES shows(id),
  seat_id    bigint NOT NULL REFERENCES seats(id),
  PRIMARY KEY (booking_id, seat_id),
  UNIQUE (show_id, seat_id)
);

CREATE INDEX ON shows (movie_id);
CREATE INDEX ON shows (starts_at);
CREATE INDEX ON seats (screen_id);
CREATE INDEX ON bookings (show_id);
CREATE INDEX ON booking_seats (seat_id);
