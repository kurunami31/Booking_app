import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../data/api.dart';
import '../../data/auth_controller.dart';
import '../../widgets/ui.dart';

/// Mock in-app wallet (GrabPay-style). No real money moves.
class WalletPage extends StatefulWidget {
  const WalletPage({super.key});

  @override
  State<WalletPage> createState() => _WalletPageState();
}

class _WalletPageState extends State<WalletPage> {
  bool _busy = false;
  String? _message;

  Future<void> _topup(double amount) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await context.read<Api>().walletTopup(amount);
      if (mounted) setState(() => _message = 'Added ${formatPeso(amount)} (simulated).');
    } catch (e) {
      if (mounted) setState(() => _message = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final api = context.read<Api>();
    final userId = context.watch<AuthController>().userId ?? '';

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('SakayTa Wallet',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
        const Text('Simulated balance for testing cashless rides.',
            style: TextStyle(color: Color(0xFF64748B))),
        const SizedBox(height: 12),
        if (_message != null) ...[
          ErrorBanner(_message!, tone: Tone.info),
          const SizedBox(height: 12),
        ],
        StreamBuilder<double>(
          stream: api.walletBalance(userId),
          builder: (context, snapshot) {
            final balance = snapshot.data ?? 0;
            return InfoCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('BALANCE',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF64748B))),
                  Text(formatPeso(balance),
                      style: const TextStyle(
                          fontSize: 34, fontWeight: FontWeight.w800)),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 12),
        const SectionTitle('Top up (simulated)'),
        Row(
          children: [
            for (final amount in [100.0, 200.0, 500.0]) ...[
              Expanded(
                child: OutlinedButton(
                  onPressed: _busy ? null : () => _topup(amount),
                  child: Text('+${formatPeso(amount)}'),
                ),
              ),
              if (amount != 500.0) const SizedBox(width: 8),
            ],
          ],
        ),
        const SizedBox(height: 16),
        const SectionTitle('Transactions'),
        StreamBuilder<List<Map<String, dynamic>>>(
          stream: api.walletTransactions(userId),
          builder: (context, snapshot) {
            final rows = snapshot.data ?? const [];
            if (rows.isEmpty) {
              return const EmptyState(title: 'No transactions yet');
            }
            return Column(
              children: [
                for (final row in rows)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: InfoCard(
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  switch (row['kind']) {
                                    'topup' => 'Top-up',
                                    'ride_payment' => 'Ride payment',
                                    'refund' => 'Refund',
                                    _ => '${row['kind']}',
                                  },
                                  style: const TextStyle(fontWeight: FontWeight.w700),
                                ),
                                Text(
                                  formatDateTime(DateTime.tryParse('${row['created_at']}')),
                                  style: const TextStyle(
                                      fontSize: 12, color: Color(0xFF64748B)),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            '${row['kind'] == 'topup' ? '+' : '-'}${formatPeso((row['amount'] as num).toDouble())}',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              color: row['kind'] == 'topup'
                                  ? const Color(0xFF047857)
                                  : const Color(0xFF0F172A),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 8),
        const Text(
          'No real money moves. A real gateway (PayMongo/Xendit) can replace this later.',
          style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
        ),
      ],
    );
  }
}
