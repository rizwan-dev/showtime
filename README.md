# Showtime — Pune Cinemas

A cinema ticket-booking system: **Ktor** API in Kotlin, **Flutter** app for
Android and iOS.

> **Status: backend complete and verified; app written but not yet run on a
> device.** 13 Kotlin tests pass against real PostgreSQL, 15 Dart tests pass,
> `flutter analyze` is clean. What remains is building and running the app on an
> emulator — see [Where this stopped](#where-this-stopped).

## The actual problem

Listing films and tapping seats is the easy half, and every tutorial stops
there. The part a ticketing system lives or dies on is **the hold**: picking a
seat reserves it for five minutes while you pay. Three properties have to be
true at once, and they pull against each other.

**Two people tap seat A5 at the same instant — exactly one gets it.** Enforced by
a unique index over unreleased holds, so the second insert collides in the
database rather than relying on the application to check first and write second.
There is a 20-thread test that asserts exactly one winner.

**An expired hold frees its seat immediately, with no sweeper.** A background job
that dies must never be able to lock a seat forever. Postgres cannot index on
`now()`, so "live" cannot live in the index predicate — taking a hold is an
`INSERT ... ON CONFLICT DO NOTHING` preceded by a release of lapsed holds, in
one transaction. Availability asks `expires_at > now()`, so a seat comes back
the instant its hold lapses.

**Confirming a hold that expired a millisecond ago must fail — before money
moves.** Reading the hold, deciding it is valid, then inserting the booking
leaves a window in which somebody else takes the seat and the customer is
charged for a seat they do not have. So the expiry check is a `WHERE` clause on
the insert itself. If the hold lapsed, nothing is inserted and the caller is
told so.

Underneath all of it, `UNIQUE (show_id, seat_id)` on `booking_seats` means that
whatever the application believes, the database will not accept the same seat
twice.

## Two bugs the tests caught

**The takeover destroyed its own evidence.** The first version used
`ON CONFLICT DO UPDATE` to reuse the row, overwriting the previous holder's
token. The customer whose hold had just lapsed then got "no such hold" instead
of "your hold expired" — a worse message, and the history was gone. Now the
lapsed row is marked released and a new row inserted.

**The test container died halfway through the suite.** An `@AfterAll` stopping a
shared Testcontainer runs when the *first* test class finishes, leaving every
later class without a database. Separately, a connection pool per test that was
never closed exhausted Postgres around test twelve — and "too many clients"
points at the database rather than at the leak.

## Layout

```
api/   Ktor 3.1 · PostgreSQL 16 · Flyway · 13 tests (Testcontainers)
app/   Flutter 3.47 · 15 tests
```

The schema builds on the Pune Cinemas data layer from
[cinema-booking](https://github.com/RizTech-Academy/cinema-booking), which has
the constraints but no service layer.

## Decisions worth defending

**409 and 410 mean different things.** "Someone else has those seats" invites
picking again; "your hold ran out" does not mean the seats are gone — they are
very likely free. The app shows different words for each, and a third for "the
server did not answer", because telling a customer their seats went when the API
is simply down is a lie.

**The countdown runs against the server's absolute deadline**, not a duration
the client started counting on arrival. A phone that sleeps, a slow network or a
wrong device clock all desynchronise a locally counted timer, and the first the
customer learns of it is a confirmation that fails for no visible reason.

**Held is not booked.** A held seat gets its own colour, because somebody has it
*for now* and a customer who waits a moment may well get it.

**Holding is all or nothing.** Winning three seats out of four is worse than
winning none: the customer cannot use them, and nobody else can either until
they expire.

**Money is integer paise everywhere**, formatted in Indian grouping
(₹1,00,000, not ₹100,000). A double introduces rounding error into a total the
server already computed exactly.

## Running it

```bash
docker compose up --build        # Postgres on 55433, API on 9193
cd app && flutter run            # 10.0.2.2 on Android, localhost on iOS
```

Ports are deliberately unusual: 8080 and 5432 are the two most likely to be
taken already.

## Tests

```bash
cd api && ./gradlew test         # 13, against real PostgreSQL
cd app && flutter test           # 15
```

The Kotlin tests use Testcontainers rather than an in-memory stand-in: every
guarantee here is a database guarantee — a unique index, an `ON CONFLICT`
takeover, `now()` evaluated server-side — and a fake would only be testing the
fake.

## Where this stopped

The API is verified end to end over HTTP: hold `201`, a second holder `409`,
confirm `201`, re-confirming the same hold `410 Gone`, holding a booked seat
`409`.

The Flutter app analyses clean and its tests pass, but it has **not yet been run
on a device**. Two toolchain problems, both on the machine rather than in the
code:

- **iOS**: the installed simulator runtime is 26.1 while the SDK is 26.2, so
  `xcodebuild` resolves zero destinations. Fixed by installing the matching
  simulator runtime.
- **Android**: `cmdline-tools` is missing from the SDK and the licences are
  unaccepted, so Gradle cannot fetch what the Flutter build asks for.
