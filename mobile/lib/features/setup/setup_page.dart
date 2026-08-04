import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../data/api_client.dart';
import '../../data/auth_session.dart';
import '../tracking/tracking_page.dart';

class SetupPage extends StatefulWidget {
  const SetupPage({
    super.key,
    required this.session,
    required this.onLogout,
  });

  final AuthSession session;
  final VoidCallback onLogout;

  @override
  State<SetupPage> createState() => _SetupPageState();
}

class _SetupPageState extends State<SetupPage> {
  static const _roles = ['רבשץ', 'כיתת כוננות', 'חמל', 'מנהל תרגיל'];

  final _exerciseName = TextEditingController(text: 'תרגיל ניסוי GPS');
  final _displayName = TextEditingController(text: 'משתתף 1');
  String _selectedRole = 'כיתת כוננות';
  List<Map<String, dynamic>> _activeExercises = [];
  String? _selectedExerciseId;
  bool _loadingExercises = false;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadActiveExercises();
  }

  Future<void> _loadActiveExercises() async {
    if (_loadingExercises) return;
    setState(() {
      _loadingExercises = true;
      _error = null;
    });
    try {
      final exercises = await ApiClient(widget.session).listActiveExercises();
      if (!mounted) return;
      setState(() {
        _activeExercises = exercises;
        if (!exercises.any(
            (exercise) => exercise['id'].toString() == _selectedExerciseId)) {
          _selectedExerciseId = null;
        }
      });
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loadingExercises = false);
    }
  }

  Future<void> _createAndStart() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final api = ApiClient(widget.session);
      final exercise = await api.createExercise(_exerciseName.text.trim());
      await _continueWithExercise(api, exercise['id'].toString(),
          startExercise: true);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _joinExisting() async {
    final exerciseId = _selectedExerciseId;
    if (exerciseId == null) {
      setState(() => _error = 'יש לבחור תרגיל פעיל.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final api = ApiClient(widget.session);
      await _continueWithExercise(api, exerciseId, startExercise: false);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _closeSelectedExercise() async {
    final exerciseId = _selectedExerciseId;
    if (exerciseId == null) return;
    final exercise = _activeExercises.firstWhere(
      (item) => item['id'].toString() == exerciseId,
    );
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('סגירת תרגיל'),
        content: Text(
          'לסגור את "${exercise['name']}"? לאחר הסגירה לא יהיה ניתן להצטרף אליו.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('ביטול'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('סגור תרגיל'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ApiClient(widget.session).closeExercise(exerciseId);
      if (!mounted) return;
      setState(() => _selectedExerciseId = null);
      await _loadActiveExercises();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('התרגיל נסגר בהצלחה.')),
        );
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _renameSelectedExercise() async {
    final exerciseId = _selectedExerciseId;
    if (exerciseId == null) return;
    final exercise = _activeExercises.firstWhere(
      (item) => item['id'].toString() == exerciseId,
    );
    final controller = TextEditingController(text: exercise['name'].toString());
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('שינוי שם התרגיל'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'שם התרגיל'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('ביטול'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('שמור'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.isEmpty || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ApiClient(widget.session).renameExercise(exerciseId, name);
      await _loadActiveExercises();
      if (mounted) setState(() => _selectedExerciseId = exerciseId);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _exerciseLabel(Map<String, dynamic> exercise) {
    final name = exercise['name'].toString();
    final rawStart = exercise['actualStart']?.toString();
    final start =
        rawStart == null ? null : DateTime.tryParse(rawStart)?.toLocal();
    if (start == null) return name;
    String two(int value) => value.toString().padLeft(2, '0');
    return '$name — ${two(start.day)}/${two(start.month)} ${two(start.hour)}:${two(start.minute)}';
  }

  Future<void> _continueWithExercise(ApiClient api, String exerciseId,
      {required bool startExercise}) async {
    final participant = await api.addParticipant(
      exerciseId: exerciseId,
      displayName: _displayName.text.trim(),
      role: _selectedRole,
    );
    final session = await api.createDeviceSession(
      exerciseId: exerciseId,
      participantId: participant['id'].toString(),
      deviceId: const Uuid().v4(),
    );
    if (startExercise) await api.startExercise(exerciseId);
    if (!mounted) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => TrackingPage(
        session: widget.session,
        exerciseId: exerciseId,
        deviceSessionId: session['deviceSessionId'].toString(),
        displayName: _displayName.text.trim(),
        role: _selectedRole,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Exercise Tracker 0.2'),
        actions: [
          IconButton(
            onPressed: widget.onLogout,
            tooltip: 'יציאה',
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            '${widget.session.user.email} · ${widget.session.user.role}',
            style: const TextStyle(fontSize: 13),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 18),
          const Text('פרטי המשתתף',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          TextField(
              controller: _displayName,
              decoration: const InputDecoration(
                  labelText: 'שם', border: OutlineInputBorder())),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: _selectedRole,
            decoration: const InputDecoration(
              labelText: 'סוג כוח',
              border: OutlineInputBorder(),
            ),
            items: _roles
                .map((role) => DropdownMenuItem(value: role, child: Text(role)))
                .toList(),
            onChanged: _busy
                ? null
                : (role) {
                    if (role != null) setState(() => _selectedRole = role);
                  },
          ),
          if (widget.session.user.canManageExercises) ...[
            const SizedBox(height: 24),
            const Divider(),
            const Text('אפשרות א׳ — צור תרגיל ניסוי חדש',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            TextField(
                controller: _exerciseName,
                decoration: const InputDecoration(
                    labelText: 'שם התרגיל', border: OutlineInputBorder())),
            const SizedBox(height: 8),
            FilledButton(
                onPressed: _busy ? null : _createAndStart,
                child: const Text('צור, התחל ועבור למעקב')),
          ],
          const SizedBox(height: 24),
          const Text('אפשרות ב׳ — הצטרף לתרגיל פעיל קיים',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  key: ValueKey(
                    '$_selectedExerciseId-${_activeExercises.map((item) => item['id']).join(',')}',
                  ),
                  initialValue: _selectedExerciseId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'תרגיל פעיל',
                    border: OutlineInputBorder(),
                  ),
                  hint: Text(_activeExercises.isEmpty
                      ? 'אין תרגילים פעילים'
                      : 'בחר תרגיל'),
                  items: _activeExercises
                      .map(
                        (exercise) => DropdownMenuItem(
                          value: exercise['id'].toString(),
                          child: Text(
                            _exerciseLabel(exercise),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: _busy || _loadingExercises
                      ? null
                      : (value) => setState(() => _selectedExerciseId = value),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                onPressed:
                    _busy || _loadingExercises ? null : _loadActiveExercises,
                tooltip: 'רענן תרגילים פעילים',
                icon: _loadingExercises
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh),
              ),
            ],
          ),
          if (widget.session.user.canManageExercises) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _busy || _selectedExerciseId == null
                  ? null
                  : _renameSelectedExercise,
              icon: const Icon(Icons.edit_outlined),
              label: const Text('שנה את שם התרגיל'),
            ),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _busy || _selectedExerciseId == null
                      ? null
                      : _joinExisting,
                  child: const Text('הצטרף ועבור למעקב'),
                ),
              ),
              if (widget.session.user.canManageExercises) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: _busy || _selectedExerciseId == null
                        ? null
                        : _closeSelectedExercise,
                    icon: const Icon(Icons.lock_outline),
                    label: const Text('סגור תרגיל'),
                  ),
                ),
              ],
            ],
          ),
          if (_busy)
            const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator())),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(_error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
        ],
      ),
    );
  }
}
