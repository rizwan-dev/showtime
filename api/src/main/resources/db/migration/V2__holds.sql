-- Holds: the part a ticketing system lives or dies on.
--
-- Picking a seat does not book it. It reserves it for a few minutes while the
-- customer pays, and the reservation expires on its own. Three properties have
-- to hold at once, and they pull against each other:
--
--   1. Two customers tapping the same seat at the same instant: exactly one
--      hold is created. Enforced by a unique index over unreleased holds, so
--      the second insert collides in the database rather than relying on the
--      application to check first and write second.
--
--   2. An expired hold frees its seat immediately, with no sweeper involved.
--      Postgres cannot index on now(), so the index alone cannot express
--      "live": taking a hold is therefore an INSERT ... ON CONFLICT DO UPDATE
--      that takes the row over only when the existing hold has already expired.
--      One statement, so the takeover cannot race. A background job that dies
--      must never be able to lock a seat forever, and here none is required.
--
--   3. Confirming a hold that expired a millisecond ago must fail, and must
--      fail *before* money is taken. That check belongs in the same
--      transaction as the booking insert, which is why confirmation is one
--      statement and not a read followed by a write.

CREATE TABLE seat_holds (
  id         bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  token      uuid   NOT NULL,
  show_id    bigint NOT NULL REFERENCES shows(id),
  seat_id    bigint NOT NULL REFERENCES seats(id),
  expires_at timestamptz NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  released_at timestamptz
);

-- One unreleased hold per seat per show. Expiry is not in the predicate
-- (now() is not immutable); it is handled by the ON CONFLICT takeover and by
-- every availability query comparing expires_at to now().
CREATE UNIQUE INDEX seat_holds_live
  ON seat_holds (show_id, seat_id)
  WHERE released_at IS NULL;

CREATE INDEX ON seat_holds (token);
CREATE INDEX ON seat_holds (expires_at);
