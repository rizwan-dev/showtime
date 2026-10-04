import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart';
import '../widgets/states.dart';
import 'checkout_screen.dart';

class SeatMapScreen extends StatefulWidget {
  const SeatMapScreen({super.key, required this.api, required this.show});

  final ShowtimeApi api;
  final Show show;

  @override
  State<SeatMapScreen> createState() => _SeatMapScreenState();
}

class _SeatMapScreenState extends State<SeatMapScreen> {
  late Future<SeatMap> _map;
  final _selected = <int>{};
  bool _holding = false;

  @override
  void initState() {
    super.initState();
    _map = widget.api.seatMap(widget.show.id);
  }

  void _reload() => setState(() {
        _selected.clear();
        _map = widget.api.seatMap(widget.show.id);
      });

  Future<void> _takeHold() async {
    setState(() => _holding = true);
    try {
      final hold = await widget.api.hold(widget.show.id, _selected.toList());
      if (!mounted) return;
      final booked = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => CheckoutScreen(api: widget.api, show: widget.show, hold: hold),
        ),
      );
      if (!mounted) return;
      if (booked == true) {
        Navigator.of(context).pop();
      } else {
        // Came back without booking: the hold was released or ran out, so the
        // map on screen is already wrong.
        _reload();
      }
    } catch (e) {
      if (!mounted) return;
      // Losing the race is normal, not exceptional: somebody simply got there
      // first. Say so and show the seats as they are now.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e is ApiFailure ? e.message : 'Could not hold those seats')),
      );
      _reload();
    } finally {
      if (mounted) setState(() => _holding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.show.movieTitle),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(20),
          child: Padding(
            padding: const EdgeInsets.only(left: 16, bottom: 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(widget.show.screenName,
                  style: Theme.of(context).textTheme.labelSmall),
            ),
          ),
        ),
        actions: [IconButton(onPressed: _reload, icon: const Icon(Icons.refresh_rounded))],
      ),
      body: FutureBuilder<SeatMap>(
        future: _map,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Loading();
          }
          if (snapshot.hasError) {
            return FailureView(failure: snapshot.error!, onRetry: _reload);
          }
          final map = snapshot.data!;
          return Column(
            children: [
              const _ScreenCurve(),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                  child: Column(
                    children: [
                      for (final row in map.rows) _Row(
                        row: row,
                        selected: _selected,
                        onTap: (seat) => setState(() {
                          if (_selected.contains(seat.id)) {
                            _selected.remove(seat.id);
                          } else if (_selected.length < 10) {
                            _selected.add(seat.id);
                          }
                        }),
                      ),
                      const SizedBox(height: 20),
                      const _Legend(),
                    ],
                  ),
                ),
              ),
              _Summary(
                count: _selected.length,
                totalPaise: _selected.length * map.pricePaise,
                busy: _holding,
                onContinue: _selected.isEmpty ? null : _takeHold,
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ScreenCurve extends StatelessWidget {
  const _ScreenCurve();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(40, 8, 40, 16),
      child: Column(
        children: [
          Container(
            height: 4,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(99),
              gradient: LinearGradient(colors: [
                Colors.transparent,
                Theme.of(context).colorScheme.primary,
                Colors.transparent,
              ]),
            ),
          ),
          const SizedBox(height: 6),
          Text('SCREEN THIS WAY',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(letterSpacing: 3)),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.row, required this.selected, required this.onTap});

  final SeatRow row;
  final Set<int> selected;
  final void Function(Seat) onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 20,
            child: Text(row.label,
                style: Theme.of(context).textTheme.labelSmall,
                textAlign: TextAlign.center),
          ),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                for (final seat in row.seats)
                  _SeatTile(
                    seat: seat,
                    selected: selected.contains(seat.id),
                    onTap: () => onTap(seat),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SeatTile extends StatelessWidget {
  const _SeatTile({required this.seat, required this.selected, required this.onTap});

  final Seat seat;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    // Held is its own colour, not a shade of booked. Someone else has it *for
    // now*, and a customer who waits a moment may well get it.
    final (colour, border, enabled) = switch (seat.status) {
      SeatStatus.booked => (const Color(0xFF26262F), Colors.transparent, false),
      SeatStatus.held => (const Color(0xFF3A2A12), const Color(0xFFD97706), false),
      SeatStatus.free => selected
          ? (scheme.primary, scheme.primary, true)
          : (const Color(0xFF191922), const Color(0xFF3A3A48), true),
    };

    return Semantics(
      label: 'Seat ${seat.label}, ${seat.status.name}',
      button: enabled,
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: Container(
          width: 22,
          height: 22,
          margin: const EdgeInsets.symmetric(horizontal: 1),
          decoration: BoxDecoration(
            color: colour,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(6),
              bottom: Radius.circular(3),
            ),
            border: Border.all(color: border, width: 1),
          ),
          alignment: Alignment.center,
          child: Text(
            '${seat.number}',
            style: TextStyle(
              fontSize: 9,
              color: seat.status == SeatStatus.booked
                  ? const Color(0xFF55555F)
                  : Colors.white.withValues(alpha: 0.85),
            ),
          ),
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    Widget chip(Color colour, Color border, String label) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: colour,
                borderRadius: BorderRadius.circular(3),
                border: Border.all(color: border),
              ),
            ),
            const SizedBox(width: 6),
            Text(label, style: Theme.of(context).textTheme.labelSmall),
          ],
        );

    return Wrap(
      spacing: 18,
      runSpacing: 8,
      alignment: WrapAlignment.center,
      children: [
        chip(const Color(0xFF191922), const Color(0xFF3A3A48), 'Available'),
        chip(Theme.of(context).colorScheme.primary, Theme.of(context).colorScheme.primary,
            'Selected'),
        chip(const Color(0xFF3A2A12), const Color(0xFFD97706), 'Held by someone'),
        chip(const Color(0xFF26262F), Colors.transparent, 'Booked'),
      ],
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({
    required this.count,
    required this.totalPaise,
    required this.busy,
    required this.onContinue,
  });

  final int count;
  final int totalPaise;
  final bool busy;
  final VoidCallback? onContinue;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        decoration: const BoxDecoration(
          color: Color(0xFF14141C),
          border: Border(top: BorderSide(color: Color(0xFF26262F))),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(count == 0 ? 'No seats selected' : '$count seat${count == 1 ? '' : 's'}',
                      style: Theme.of(context).textTheme.labelMedium),
                  Text(rupees(totalPaise), style: Theme.of(context).textTheme.titleLarge),
                ],
              ),
            ),
            FilledButton(
              onPressed: busy ? null : onContinue,
              child: busy
                  ? const SizedBox(
                      width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Hold seats'),
            ),
          ],
        ),
      ),
    );
  }
}
