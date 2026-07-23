import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../data/api_client.dart';
import '../tracking/tracking_page.dart';

class SetupPage extends StatefulWidget {
  const SetupPage({super.key});

  @override
  State<SetupPage> createState() => _SetupPageState();
}

class _SetupPageState extends State<SetupPage> {
  final _server = TextEditingController(text: 'http://10.0.2.2:8000');
  final _exerciseName = TextEditingController(text: 'תרגיל ניסוי GPS');
  final _displayName = TextEditingController(text: 'משתתף 1');
  final _callsign = TextEditingController(text: 'כוח 1');
  final _existingExercise = TextEditingController();
  bool _busy = false;
  String? _error;

  Future<void> _createAndStart() async {
    setState(() { _busy = true; _error = null; });
    try {
      final api = ApiClient(_server.text.trim());
      final exercise = await api.createExercise(_exerciseName.text.trim());
      await _continueWithExercise(api, exercise['id'].toString(), startExercise: true);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _joinExisting() async {
    setState(() { _busy = true; _error = null; });
    try {
      final api = ApiClient(_server.text.trim());
      await _continueWithExercise(api, _existingExercise.text.trim(), startExercise: false);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _continueWithExercise(ApiClient api, String exerciseId, {required bool startExercise}) async {
    final participant = await api.addParticipant(
      exerciseId: exerciseId,
      displayName: _displayName.text.trim(),
      callsign: _callsign.text.trim(),
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
        apiBaseUrl: _server.text.trim(),
        exerciseId: exerciseId,
        deviceSessionId: session['deviceSessionId'].toString(),
        displayName: _displayName.text.trim(),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Exercise Tracker 0.2')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text('חיבור לשרת', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          TextField(controller: _server, decoration: const InputDecoration(labelText: 'כתובת השרת', border: OutlineInputBorder())),
          const SizedBox(height: 18),
          const Text('פרטי המשתתף', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          TextField(controller: _displayName, decoration: const InputDecoration(labelText: 'שם', border: OutlineInputBorder())),
          const SizedBox(height: 8),
          TextField(controller: _callsign, decoration: const InputDecoration(labelText: 'אות קריאה', border: OutlineInputBorder())),
          const SizedBox(height: 24),
          const Divider(),
          const Text('אפשרות א׳ — צור תרגיל ניסוי חדש', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          TextField(controller: _exerciseName, decoration: const InputDecoration(labelText: 'שם התרגיל', border: OutlineInputBorder())),
          const SizedBox(height: 8),
          FilledButton(onPressed: _busy ? null : _createAndStart, child: const Text('צור, התחל ועבור למעקב')),
          const SizedBox(height: 24),
          const Text('אפשרות ב׳ — הצטרף לתרגיל פעיל קיים', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          TextField(controller: _existingExercise, decoration: const InputDecoration(labelText: 'Exercise ID', border: OutlineInputBorder())),
          const SizedBox(height: 8),
          OutlinedButton(onPressed: _busy ? null : _joinExisting, child: const Text('הצטרף ועבור למעקב')),
          if (_busy) const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
          if (_error != null) Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
          const SizedBox(height: 20),
          const Text('Android Emulator: השתמש ב־http://10.0.2.2:8000. בטלפון אמיתי יש להזין את כתובת ה־IP של המחשב באותה רשת.', style: TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}
