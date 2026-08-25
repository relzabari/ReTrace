import 'dart:async';
import 'package:flutter/material.dart';
import '../../data/auth_session.dart';
import '../../ui/app_design.dart';
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
  Timer? _exerciseStatusTimer;
  final _eventDescription = TextEditingController();
  bool _eventBusy = false;
  bool _locationBusy = false;
  String? _eventError;
  EventLocationSelection? _eventLocation;
  late DateTime _eventOccurredAt;
  bool _handlingExerciseClosure = false;
  bool _exerciseClosed = false;
  bool _statusCheckRunning = false;

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
    _exerciseStatusTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _checkExerciseStatus(),
    );
  }

  Future<void> _start() async {
    if (_exerciseClosed) return;
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

  Future<void> _checkExerciseStatus() async {
    if (_handlingExerciseClosure || _exerciseClosed || _statusCheckRunning) {
      return;
    }
    _statusCheckRunning = true;
    try {
      final status = await _service.exerciseStatus();
      if (status == 'ENDING' || status == 'COMPLETED' || status == 'DELETED') {
        await _handleExerciseClosure(deleted: status == 'DELETED');
      }
    } finally {
      _statusCheckRunning = false;
    }
  }

  Future<void> _handleExerciseClosure({bool deleted = false}) async {
    if (_handlingExerciseClosure || _exerciseClosed) return;
    _handlingExerciseClosure = true;
    _exerciseStatusTimer?.cancel();
    _timer?.cancel();
    final synced = deleted ? false : await _service.finishForExerciseClosure();
    if (deleted) await _service.stopForDeletedExercise();
    if (!mounted) return;
    setState(() {
      _running = false;
      _exerciseClosed = true;
      _handlingExerciseClosure = false;
    });
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(deleted ? 'התרגיל נמחק' : 'התרגיל נסגר'),
        content: Text(
          deleted
              ? 'התרגיל נמחק לצמיתות על ידי מנהל המערכת. המעקב הופסק ולא ניתן לסנכרן אליו נקודות נוספות.'
              : synced
                  ? 'התרגיל נסגר על ידי מנהל התרגיל. כל הנקודות האחרונות סונכרנו והמעקב הופסק.'
                  : 'התרגיל נסגר על ידי מנהל התרגיל והמעקב הופסק. לא ניתן היה לסנכרן את כל הנקודות האחרונות.',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('אישור'),
          ),
        ],
      ),
    );
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
    _exerciseStatusTimer?.cancel();
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
      appBar: AppBar(
        title: const Text('תרגיל פעיל'),
        leading: const Icon(Icons.route_rounded),
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const CircleAvatar(
                    radius: 27,
                    backgroundColor: AppColors.forest,
                    foregroundColor: Colors.white,
                    child: Icon(Icons.person_rounded, size: 30),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.displayName,
                            style: const TextStyle(
                                fontSize: 23,
                                fontWeight: FontWeight.w900,
                                color: AppColors.ink)),
                        Text(widget.role,
                            style: const TextStyle(
                                fontSize: 15,
                                color: AppColors.forest,
                                fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: _running && !_exerciseClosed
                          ? const Color(0xFFE2F8F4)
                          : const Color(0xFFFDE8E7),
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Row(
                      children: [
                        Icon(
                            _running && !_exerciseClosed
                                ? Icons.satellite_alt_rounded
                                : Icons.pause_circle_outline_rounded,
                            size: 18,
                            color: _running && !_exerciseClosed
                                ? AppColors.teal
                                : AppColors.danger),
                        const SizedBox(width: 6),
                        Text(
                          _exerciseClosed
                              ? 'התרגיל נסגר'
                              : _running
                                  ? 'מקליט GPS'
                                  : 'המעקב נעצר',
                          style: TextStyle(
                              fontWeight: FontWeight.w900,
                              color: _running && !_exerciseClosed
                                  ? AppColors.teal
                                  : AppColors.danger),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              AppCard(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _elapsed,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 35,
                          fontWeight: FontWeight.w900,
                          color: AppColors.forestDark,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    if (_running)
                      FilledButton.icon(
                        onPressed: _stop,
                        style: FilledButton.styleFrom(
                            backgroundColor: AppColors.danger,
                            foregroundColor: Colors.white),
                        icon: const Icon(Icons.stop_rounded),
                        label: const Text('עצור מעקב'),
                      )
                    else
                      FilledButton.icon(
                        onPressed: _exerciseClosed ? null : _start,
                        icon: const Icon(Icons.play_arrow_rounded),
                        label:
                            Text(_exerciseClosed ? 'התרגיל נסגר' : 'הפעל מחדש'),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              LayoutBuilder(
                builder: (context, constraints) {
                  final width = (constraints.maxWidth - 10) / 2;
                  return Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      _metricCard(
                          width,
                          'GPS',
                          s?.lastAccuracy == null
                              ? 'ממתין...'
                              : 'דיוק ±${s!.lastAccuracy!.toStringAsFixed(1)} מ׳',
                          Icons.gps_fixed_rounded,
                          AppColors.cyan),
                      _metricCard(
                          width,
                          'שרת',
                          s?.lastSyncOk == false
                              ? 'Offline / ינסה שוב'
                              : 'מחובר / מסונכרן',
                          Icons.cloud_done_rounded,
                          AppColors.teal),
                      _metricCard(width, 'נקודות שנשמרו', '${s?.total ?? 0}',
                          Icons.storage_rounded, const Color(0xFF388E3C)),
                      _metricCard(
                          width,
                          'ממתינות לסנכרון',
                          '${s?.pending ?? 0}',
                          Icons.sync_rounded,
                          AppColors.blue),
                    ],
                  );
                },
              ),
              if (_canReportEvents) ...[
                const SizedBox(height: 24),
                AppCard(
                  tint: const Color(0xFFFBFEFC),
                  borderColor: AppColors.forest,
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SectionTitle('דיווח אירוע',
                          icon: Icons.assignment_rounded),
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
                        style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.amber,
                            side: const BorderSide(color: AppColors.amber)),
                        icon: const Icon(Icons.calendar_month_outlined),
                        label: Text('תאריך ושעה: $_eventDateTimeLabel'),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: !_running || _eventBusy || _locationBusy
                            ? null
                            : _chooseEventLocation,
                        style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.blue,
                            side: const BorderSide(color: AppColors.blue)),
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
                      GradientActionButton(
                        onPressed: !_running ||
                                _eventBusy ||
                                _locationBusy ||
                                _eventLocation == null
                            ? null
                            : _addEvent,
                        icon: Icons.add_location_alt_rounded,
                        label: _eventBusy ? 'שומר אירוע...' : 'הוסף אירוע',
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                            color: AppColors.mint,
                            borderRadius: BorderRadius.circular(12)),
                        child: const Row(
                          children: [
                            Icon(Icons.info_outline_rounded,
                                size: 18, color: AppColors.forest),
                            SizedBox(width: 7),
                            Expanded(
                                child: Text(
                                    'הזמן ושם המדווח עם תפקידו יצורפו אוטומטית.',
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: AppColors.forest))),
                          ],
                        ),
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
              Text('Exercise ID: ${widget.exerciseId}',
                  style: const TextStyle(fontSize: 10),
                  textAlign: TextAlign.center),
            ],
          ),
        ],
      ),
    );
  }

  Widget _metricCard(double width, String label, String value, IconData icon,
          Color color) =>
      SizedBox(
        width: width,
        child: AppCard(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          child: Column(
            children: [
              Icon(icon, color: color, size: 26),
              const SizedBox(height: 6),
              Text(label,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontWeight: FontWeight.w900, color: color)),
              const SizedBox(height: 4),
              Text(value,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, color: AppColors.ink)),
            ],
          ),
        ),
      );
}
