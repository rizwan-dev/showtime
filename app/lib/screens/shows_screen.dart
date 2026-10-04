import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart';
import '../widgets/states.dart';
import 'seat_map_screen.dart';

class ShowsScreen extends StatefulWidget {
  const ShowsScreen({super.key, required this.api, required this.movie});

  final ShowtimeApi api;
  final Movie movie;

  @override
  State<ShowsScreen> createState() => _ShowsScreenState();
}

class _ShowsScreenState extends State<ShowsScreen> {
  late Future<List<Show>> _shows;

  @override
  void initState() {
    super.initState();
    _shows = widget.api.shows(widget.movie.id);
  }

  void _reload() => setState(() => _shows = widget.api.shows(widget.movie.id));

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(widget.movie.title)),
      body: FutureBuilder<List<Show>>(
        future: _shows,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Loading();
          }
          if (snapshot.hasError) {
            return FailureView(failure: snapshot.error!, onRetry: _reload);
          }
          final shows = snapshot.data ?? const [];
          if (shows.isEmpty) {
            return const Center(child: Text('No shows scheduled.'));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: shows.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, i) {
              final show = shows[i];
              final soldOut = show.seatsAvailable == 0;
              return Material(
                color: const Color(0xFF14141C),
                borderRadius: BorderRadius.circular(16),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  // A sold-out show is not tappable, rather than tappable and
                  // then disappointing.
                  onTap: soldOut
                      ? null
                      : () async {
                          await Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => SeatMapScreen(api: widget.api, show: show),
                            ),
                          );
                          // Availability has very likely changed while we were
                          // away, so re-read it rather than showing a stale count.
                          _reload();
                        },
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(_time(show.startsAt),
                                style: Theme.of(context).textTheme.titleLarge),
                            Text(_day(show.startsAt),
                                style: Theme.of(context)
                                    .textTheme
                                    .labelSmall
                                    ?.copyWith(color: scheme.onSurfaceVariant)),
                          ],
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(show.screenName,
                                  style: Theme.of(context).textTheme.bodyMedium),
                              const SizedBox(height: 4),
                              Text(
                                soldOut
                                    ? 'Sold out'
                                    : '${show.seatsAvailable} seats available',
                                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                      color: soldOut ? scheme.error : const Color(0xFF34D399),
                                    ),
                              ),
                            ],
                          ),
                        ),
                        Text(rupees(show.pricePaise),
                            style: Theme.of(context).textTheme.titleMedium),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  static String _time(DateTime t) {
    final hour = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final minute = t.minute.toString().padLeft(2, '0');
    return '$hour:$minute ${t.hour < 12 ? 'AM' : 'PM'}';
  }

  static String _day(DateTime t) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return '${days[t.weekday - 1]} ${t.day}';
  }
}
