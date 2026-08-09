import 'dart:async';
import 'package:flutter/material.dart';
import '../../data/auth_session.dart';
import 'event_location_picker_page.dart';
import 'tracking_service.dart';

class TrackingPage extends StatefulWidget {
  const TrackingPage({
    super.key,
    required this.session,
    required this.exerciseId,
    required this.deviceSessionId,
    required this.displayName,
    required this.role,
    required this.exerciseCreatedAt,
  });
  final AuthSession session;
  final String exerciseId;
  final String deviceSessionId;
  final String displayName;
  final String role;
  final DateTime exerciseCreatedAt;

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
  final _eventDescription = TextEditingController();
  bool _eventBusy = false;
  bool _locationBusy = false;
  String? _eventError;
  EventLocationSelection? _eventLocation;
  late DateTime _eventOccurredAt;

  bool get _canReportEvents => widget.role != 'כיתת כוננות';

  @override
  void initState() {
    super.initState();
    _eventOccurredAt = DateTime.now();
    _service = TrackingService(
      session: widget.session,
      exerciseId: widget.exerciseId,
      deviceSessionId: widget.deviceSessionId,
    );
    _sub = _service.status.listen((s) {
      if (mounted) setState(() => _snapshot = s);
    });
    _start();
  }

  Future<void> _start() async {
    try {
      await _service.start();
      _startedAt = DateTime.now();
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
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

  Future<void> _addEvent() async {
    if (_eventDescription.text.trim().isEmpty) {
      setState(() => _eventError = 'יש להזין תיאור לאירוע.');
      return;
    }
    if (_eventLocation == null) {
      setState(() => _eventError = 'יש לבחור מיקום לאירוע.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _eventBusy = true;
      _eventError = null;
    });
    try {
      final location = _eventLocation!;
      await _service.addEvent(
        _eventDescription.text,
        occurredAt: _eventOccurredAt,
        selectedLocation: location.useCurrentLocation
            ? null
            : EventCoordinates(location.latitude!, location.longitude!),
      );
      if (mounted) {
        _eventDescription.clear();
        setState(() {
          _eventLocation = null;
          _eventOccurredAt = DateTime.now();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('האירוע נשמר בהצלחה.')),
        );
      }
    } catch (error) {
      if (mounted) setState(() => _eventError = error.toString());
    } finally {
      if (mounted) setState(() => _eventBusy = false);
    }
  }

  Future<void> _chooseEventLocation() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _locationBusy = true;
      _eventError = null;
    });
    try {
      EventCoordinates initialLocation;
      final previousLocation = _eventLocation;
      if (previousLocation != null && !previousLocation.useCurrentLocation) {
        initialLocation = EventCoordinates(
          previousLocation.latitude!,
          previousLocation.longitude!,
        );
      } else {
        try {
          initialLocation = await _service.currentEventCoordinates();
        } catch (_) {
          initialLocation = const EventCoordinates(31.95, 35.13);
        }
      }
      if (!mounted) return;
      final selection = await Navigator.push<EventLocationSelection>(
        context,
        MaterialPageRoute(
          builder: (_) => EventLocationPickerPage(
            initialLatitude: initialLocation.latitude,
            initialLongitude: initialLocation.longitude,
          ),
        ),
      );
      if (selection != null && mounted) {
        setState(() => _eventLocation = selection);
      }
    } catch (error) {
      if (mounted) {
        setState(() => _eventError = 'לא ניתן לפתוח את בחירת המיקום: $error');
      }
    } finally {
      if (mounted) setState(() => _locationBusy = false);
    }
  }

  Future<void> _chooseEventDateTime() async {
    FocusScope.of(context).unfocus();
    final earliest = widget.exerciseCreatedAt.toLocal();
    final now = DateTime.now();
    final initial = _eventOccurredAt.isBefore(earliest)
        ? earliest
        : _eventOccurredAt.isAfter(now)
            ? now
            : _eventOccurredAt;
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(earliest.year, earliest.month, earliest.day),
      lastDate: DateTime(now.year, now.month, now.day),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null || !mounted) return;
    var selected =
        DateTime(date.year, date.month, date.day, time.hour, time.minute);
    if (selected.isBefore(earliest) &&
        selected.year == earliest.year &&
        selected.month == earliest.month &&
        selected.day == earliest.day &&
        selected.hour == earliest.hour &&
        selected.minute == earliest.minute) {
      selected = earliest;
    }
    final currentNow = DateTime.now();
    if (selected.isBefore(earliest)) {
      setState(() =>
          _eventError = 'זמן האירוע לא יכול להיות מוקדם ממועד יצירת התרגיל.');
      return;
    }
    if (selected.isAfter(currentNow)) {
      setState(
          () => _eventError = 'זמן האירוע לא יכול להיות מאוחר מהזמן הנוכחי.');
      return;
    }
    setState(() {
      _eventOccurredAt = selected;
      _eventError = null;
    });
  }

  String get _eventDateTimeLabel {
    String two(int value) => value.toString().padLeft(2, '0');
    final value = _eventOccurredAt;
    return '${two(value.day)}/${two(value.month)}/${value.year}  ${two(value.hour)}:${two(value.minute)}';
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
    _eventDescription.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = _snapshot;
    return Scaffold(
      appBar: AppBar(title: const Text('תרגיל פעיל')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(widget.displayName,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 24, fontWeight: FontWeight.bold)),
              Text(widget.role,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 16)),
              const SizedBox(height: 12),
              Text(_running ? '● מקליט GPS' : 'המעקב נעצר',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 20,
                      color: _running ? Colors.green : Colors.red)),
              const SizedBox(height: 12),
              Text(_elapsed,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 40,
                      fontFeatures: [FontFeature.tabularFigures()])),
              const SizedBox(height: 28),
              _row(
                  'GPS',
                  s?.lastAccuracy == null
                      ? 'ממתין...'
                      : 'דיוק ±${s!.lastAccuracy!.toStringAsFixed(1)} מ׳'),
              _row(
                  'שרת',
                  s?.lastSyncOk == false
                      ? 'Offline / ינסה שוב'
                      : 'מחובר / מסונכרן'),
              _row('נקודות שנשמרו', '${s?.total ?? 0}'),
              _row('ממתינות לסנכרון', '${s?.pending ?? 0}'),
              if (_canReportEvents) ...[
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: const Color(0xFF1B5E20),
                      width: 2,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'דיווח אירוע',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1B5E20),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _eventDescription,
                        minLines: 2,
                        maxLines: 5,
                        textInputAction: TextInputAction.newline,
                        decoration: const InputDecoration(
                          labelText: 'תיאור האירוע',
                          hintText: 'כתוב מה קרה...',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: !_running || _eventBusy
                            ? null
                            : _chooseEventDateTime,
                        icon: const Icon(Icons.calendar_month_outlined),
                        label: Text('תאריך ושעה: $_eventDateTimeLabel'),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: !_running || _eventBusy || _locationBusy
                            ? null
                            : _chooseEventLocation,
                        icon: _locationBusy
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.map_outlined),
                        label: Text(
                          _eventLocation == null ? 'הוסף מיקום' : 'שנה מיקום',
                        ),
                      ),
                      Text(
                        _eventLocation == null
                            ? 'לא נבחר מיקום לאירוע'
                            : _eventLocation!.useCurrentLocation
                                ? 'נבחר: מיקום עצמי'
                                : 'נבחר מיקום על גבי המפה',
                        style: TextStyle(
                          fontSize: 12,
                          color: _eventLocation == null
                              ? Theme.of(context).colorScheme.error
                              : Theme.of(context).colorScheme.primary,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      FilledButton.icon(
                        onPressed: !_running ||
                                _eventBusy ||
                                _locationBusy ||
                                _eventLocation == null
                            ? null
                            : _addEvent,
                        icon: _eventBusy
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.add_location_alt_outlined),
                        label: const Text('הוסף אירוע'),
                      ),
                      const Text(
                        'הזמן ושם המדווח עם תפקידו יצורפו אוטומטית.',
                        style: TextStyle(fontSize: 12),
                        textAlign: TextAlign.center,
                      ),
                      if (_eventError != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            _eventError!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 24),
              if (_error != null)
                Text(_error!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
              if (_running)
                FilledButton.tonal(
                    onPressed: _stop, child: const Text('עצור מעקב'))
              else
                FilledButton(
                    onPressed: _start, child: const Text('הפעל מעקב מחדש')),
              const SizedBox(height: 8),
              Text('Exercise ID: ${widget.exerciseId}',
                  style: const TextStyle(fontSize: 10),
                  textAlign: TextAlign.center),
            ],
          ),
        ],
      ),
    );
  }

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child:
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
          Flexible(child: Text(value))
        ]),
      );
}
