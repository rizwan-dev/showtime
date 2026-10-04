import 'package:flutter/material.dart';

import '../api.dart';

/// One place that turns a failure into words a customer can act on.
///
/// The three cases read differently on purpose. "Those seats went" invites
/// picking again; "we cannot reach the server" does not, because trying another
/// seat will not help.
class FailureView extends StatelessWidget {
  const FailureView({super.key, required this.failure, this.onRetry});

  final Object failure;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final (icon, title, detail) = switch (failure) {
      Unreachable(:final message) => (
          Icons.cloud_off_rounded,
          'Cannot reach the box office',
          message,
        ),
      SeatsUnavailable(:final message) => (
          Icons.event_busy_rounded,
          'Those seats just went',
          message,
        ),
      HoldExpired() => (
          Icons.timer_off_rounded,
          'Your seats were released',
          'Holds last five minutes. Pick again and you will likely get them back.',
        ),
      ApiFailure(:final message) => (Icons.error_outline_rounded, 'Something went wrong', message),
      _ => (Icons.error_outline_rounded, 'Something went wrong', failure.toString()),
    };

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(height: 16),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              detail,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 20),
              FilledButton.tonal(onPressed: onRetry, child: const Text('Try again')),
            ],
          ],
        ),
      ),
    );
  }
}

class Loading extends StatelessWidget {
  const Loading({super.key});

  @override
  Widget build(BuildContext context) =>
      const Center(child: CircularProgressIndicator(strokeWidth: 2));
}
