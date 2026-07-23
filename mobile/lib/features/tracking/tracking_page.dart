import 'dart:ui';
import 'dart:async';
import 'package:flutter/material.dart';
import 'tracking_service.dart';

class TrackingPage extends StatefulWidget {
  const TrackingPage({
    super.key,
    required this.apiBaseUrl,
    required this.exerciseId,
    required this.deviceSessionId,
    required this.displayName,
  });
  final String apiBaseUrl;
  final String exerciseId;
  final String deviceSessionId;
  final String displayName;

  @override
  State<TrackingPage> createState() => _TrackingPageState();
}

class _TrackingPageState extends State<TrackingPage> {
  late final TrackingService _service;
  StreamSubscription<TrackingSnapshot>? _sub;
  TrackingSnapshot? _snapshot;
  String? _error;
  bool _running = false;
  DateTime? _startedAt;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _service = TrackingService(
      apiBaseUrl: widget.apiBaseUrl,
      exerciseId: widget.exerciseId,
      deviceSessionId: widget.deviceSessionId,
    );
    _sub = _service.status.listen((s) { if (mounted) setState(() => _snapshot = s); });
    _start();
  }

  Future<void> _start() async {
    try {
      await _service.start();
      _startedAt = DateTime.now();
      _timer = Timer.periodic(const Duration(seconds: 1), (_) { if (mounted) setState(() {}); });
      if (mounted) setState(() => _running = true);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _stop() async {
    await _service.stop();
    _timer?.cancel();
    if (mounted) setState(() => _running = false);
  }

  String get _elapsed {
    if (_startedAt == null) return '00:00:00';
    final d = DateTime.now().difference(_startedAt!);
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.inHours)}:${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}';
  }

  @override
  void dispose() {
    _timer?.cancel();
    _sub?.cancel();
    _service.stop();
    _service.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = _snapshot;
    return Scaffold(
      appBar: AppBar(title: const Text('תרגיל פעיל')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.displayName, textAlign: TextAlign.center, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Text(_running ? '● מקליט GPS' : 'המעקב נעצר', textAlign: TextAlign.center, style: TextStyle(fontSize: 20, color: _running ? Colors.green : Colors.red)),
            const SizedBox(height: 12),
            Text(_elapsed, textAlign: TextAlign.center, style: const TextStyle(fontSize: 40, fontFeatures: [FontFeature.tabularFigures()])),
            const SizedBox(height: 28),
            _row('GPS', s?.lastAccuracy == null ? 'ממתין...' : 'דיוק ±${s!.lastAccuracy!.toStringAsFixed(1)} מ׳'),
            _row('שרת', s?.lastSyncOk == false ? 'Offline / ינסה שוב' : 'מחובר / מסונכרן'),
            _row('נקודות שנשמרו', '${s?.total ?? 0}'),
            _row('ממתינות לסנכרון', '${s?.pending ?? 0}'),
            const Spacer(),
            if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            if (_running)
              FilledButton.tonal(onPressed: _stop, child: const Text('עצור מעקב'))
            else
              FilledButton(onPressed: _start, child: const Text('הפעל מעקב מחדש')),
            const SizedBox(height: 8),
            Text('Exercise ID: ${widget.exerciseId}', style: const TextStyle(fontSize: 10), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(label, style: const TextStyle(fontWeight: FontWeight.bold)), Flexible(child: Text(value))]),
  );
}
