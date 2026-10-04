import 'dart:async';

import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart';
import 'ticket_screen.dart';

/// Pay before the timer runs out.
///
/// The countdown ticks against the server's absolute [Hold.expiresAt], not a
/// duration the client started counting on arrival. A phone that sleeps, a slow
/// network or a wrong device clock would all desynchronise a locally counted
/// timer, and the first the customer would know of it is a confirmation that
/// fails for no visible reason.
class CheckoutScreen extends StatefulWidget {
  const CheckoutScreen({
    super.key,
    required this.api,
    required this.show,
    required this.hold,
  });

  final ShowtimeApi api;
  final Show show;
  final Hold hold;

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  late Timer _ticker;
  final _name = TextEditingController(text: 'Rizwan');
  bool _confirming = false;
  String? _error;

  Duration get _left => widget.hold.remaining;
  bool get _expired => _left == Duration.zero;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker.cancel();
    _name.dispose();
    super.dispose();
  }

  Future<void> _abandon() async {
    // Hand the seats back rather than making everyone else wait out the timer
    // for a customer who has already walked away.
    await widget.api.release(widget.hold.token);
    if (mounted) Navigator.of(context).pop(false);
  }

  Future<void> _confirm() async {
    setState(() {
      _confirming = true;
      _error = null;
    });
    try {
      final booking = await widget.api.confirm(widget.hold.token, _name.text.trim());
      if (!mounted) return;
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => TicketScreen(booking: booking)),
      );
    } on HoldExpired {
      // The server is the authority on expiry, and it can disagree with the
      // countdown on screen by a second either way. This is the real answer.
      if (mounted) {
        setState(() => _error = 'Your hold ran out. The seats are free again - pick once more.');
      }
    } on ApiFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _confirming = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final urgent = _left.inSeconds <= 60;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _abandon();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Confirm booking'),
          leading: IconButton(
            icon: const Icon(Icons.close_rounded),
            onPressed: _abandon,
          ),
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _expired
                    ? scheme.errorContainer
                    : (urgent ? const Color(0xFF3A2A12) : const Color(0xFF14141C)),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  Icon(
                    _expired ? Icons.timer_off_rounded : Icons.timer_outlined,
                    color: _expired ? scheme.onErrorContainer : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _expired
                          ? 'Your hold has expired'
                          : 'Seats held for ${_format(_left)}',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: _expired ? scheme.onErrorContainer : null,
                          ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            _Line(label: 'Film', value: widget.show.movieTitle),
            _Line(label: 'Screen', value: widget.show.screenName),
            _Line(label: 'Seats', value: '${widget.hold.seatIds.length} selected'),
            const Divider(height: 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Total', style: Theme.of(context).textTheme.titleMedium),
                Text(rupees(widget.hold.totalPaise),
                    style: Theme.of(context).textTheme.headlineSmall),
              ],
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _name,
              enabled: !_expired,
              decoration: const InputDecoration(
                labelText: 'Booking name',
                border: OutlineInputBorder(),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(_error!, style: TextStyle(color: scheme.error)),
            ],
            const SizedBox(height: 24),
            FilledButton(
              // Disabled once the countdown hits zero, so the customer is not
              // invited to pay for seats that are already gone.
              onPressed: (_confirming || _expired) ? null : _confirm,
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              child: _confirming
                  ? const SizedBox(
                      width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(_expired ? 'Hold expired' : 'Pay ${rupees(widget.hold.totalPaise)}'),
            ),
            if (_expired) ...[
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => Navigator.of(context).pop(false),
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                child: const Text('Pick seats again'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _format(Duration d) {
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
            Flexible(child: Text(value, textAlign: TextAlign.right)),
          ],
        ),
      );
}
