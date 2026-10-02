import 'dart:async';

import 'package:flutter/material.dart';

import '../core/theme.dart';

/// Hold-to-send SOS. A single tap does nothing, so a pocket press cannot fire
/// it. The user must hold for [holdSeconds].
class SosButton extends StatefulWidget {
  const SosButton({
    super.key,
    required this.onActivate,
    this.label = 'Hold to send SOS',
    this.holdSeconds = 3,
  });

  final Future<void> Function() onActivate;
  final String label;
  final int holdSeconds;

  @override
  State<SosButton> createState() => _SosButtonState();
}

class _SosButtonState extends State<SosButton> {
  Timer? _timer;
  double _progress = 0;
  bool _sending = false;
  bool _sent = false;
  String? _error;

  void _start() {
    if (_sending || _sent || _timer != null) return;
    final started = DateTime.now();
    _timer = Timer.periodic(const Duration(milliseconds: 60), (timer) {
      final elapsed = DateTime.now().difference(started).inMilliseconds / 1000;
      final next = (elapsed / widget.holdSeconds).clamp(0.0, 1.0);
      setState(() => _progress = next);
      if (next >= 1) _fire();
    });
  }

  void _stop() {
    _timer?.cancel();
    _timer = null;
    if (mounted) setState(() => _progress = 0);
  }

  Future<void> _fire() async {
    _stop();
    if (_sending) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await widget.onActivate();
      if (mounted) setState(() => _sent = true);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GestureDetector(
          onTapDown: (_) => _start(),
          onTapUp: (_) => _stop(),
          onTapCancel: _stop,
          child: Stack(
            children: [
              Container(
                height: 64,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppTheme.sos500,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppTheme.sos600, width: 2),
                ),
                child: Text(
                  _sent
                      ? 'SOS sent — help is being alerted'
                      : _sending
                          ? 'Sending SOS…'
                          : widget.label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Positioned.fill(
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: _progress,
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppTheme.sos600,
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Text(
          _sent
              ? 'Keep your phone on. The city control point has your trip and last known location.'
              : 'Hold for ${widget.holdSeconds} seconds. This alerts the city responder and logs your trip.',
          style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              _error!,
              style: const TextStyle(
                fontSize: 12,
                color: AppTheme.sos600,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
      ],
    );
  }
}
