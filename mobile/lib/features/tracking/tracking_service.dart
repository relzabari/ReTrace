import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geolocator_android/geolocator_android.dart';
import 'package:geolocator_apple/geolocator_apple.dart';
import 'package:http/http.dart' as http;

import '../../data/local_location_store.dart';

class TrackingSnapshot {
  const TrackingSnapshot({
    required this.total,
    required this.pending,
    required this.lastAccuracy,
    required this.lastPositionAt,
    required this.lastSyncOk,
  });

  final int total;
  final int pending;
  final double? lastAccuracy;
  final DateTime? lastPositionAt;
  final bool lastSyncOk;
}

class TrackingService {
  TrackingService({required this.apiBaseUrl, required this.exerciseId, required this.deviceSessionId});

  final String apiBaseUrl;
  final String exerciseId;
  final String deviceSessionId;
  final LocalLocationStore _store = LocalLocationStore();
  final StreamController<TrackingSnapshot> _status = StreamController.broadcast();
  StreamSubscription<Position>? _subscription;
  Timer? _syncTimer;
  int _sequence = DateTime.now().millisecondsSinceEpoch;
  double? _lastAccuracy;
  DateTime? _lastPositionAt;
  bool _lastSyncOk = true;

  Stream<TrackingSnapshot> get status => _status.stream;

  Future<void> ensurePermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw StateError('שירותי המיקום כבויים במכשיר.');
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
      throw StateError('נדרשת הרשאת מיקום כדי לתעד את התרגיל.');
    }
  }

  LocationSettings _locationSettings() {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return AndroidSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 0,
        intervalDuration: const Duration(seconds: 2),
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'תרגיל פעיל',
          notificationText: 'האפליקציה ממשיכה לתעד מיקום ברקע',
          notificationChannelName: 'מעקב מיקום',
          enableWakeLock: true,
          setOngoing: true,
        ),
      );
    }
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return AppleSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 0,
        activityType: ActivityType.fitness,
        pauseLocationUpdatesAutomatically: false,
        showBackgroundLocationIndicator: true,
        allowBackgroundLocationUpdates: true,
      );
    }
    return const LocationSettings(
      accuracy: LocationAccuracy.best,
      distanceFilter: 0,
    );
  }

  Future<void> start() async {
    await ensurePermission();

    final settings = _locationSettings();

    _subscription = Geolocator.getPositionStream(locationSettings: settings).listen((position) async {
      final sequence = _sequence++;
      _lastAccuracy = position.accuracy;
      _lastPositionAt = position.timestamp;
      await _store.insertPoint({
        'sequence_number': sequence,
        'captured_at': position.timestamp.toUtc().toIso8601String(),
        'latitude': position.latitude,
        'longitude': position.longitude,
        'accuracy': position.accuracy,
        'speed': position.speed,
        'heading': position.heading,
        'sync_status': 'PENDING',
      });
      await _emit();
    });

    _syncTimer = Timer.periodic(const Duration(seconds: 10), (_) => syncPending());
    await _emit();
  }

  Future<void> _emit() async {
    if (_status.isClosed) return;
    _status.add(TrackingSnapshot(
      total: await _store.totalCount(),
      pending: await _store.pendingCount(),
      lastAccuracy: _lastAccuracy,
      lastPositionAt: _lastPositionAt,
      lastSyncOk: _lastSyncOk,
    ));
  }

  Future<void> syncPending() async {
    final pending = await _store.pending(limit: 20);
    if (pending.isEmpty) {
      _lastSyncOk = true;
      await _emit();
      return;
    }

    final body = {
      'device_session_id': deviceSessionId,
      'points': pending.map((p) => {
        'sequence': p['sequence_number'],
        'captured_at': p['captured_at'],
        'latitude': p['latitude'],
        'longitude': p['longitude'],
        'horizontal_accuracy': p['accuracy'],
        'speed': p['speed'],
        'heading': p['heading'],
      }).toList(),
    };

    try {
      final response = await http.post(
        Uri.parse('$apiBaseUrl/api/v1/exercises/$exerciseId/locations/batch'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );
      if (response.statusCode >= 200 && response.statusCode < 300) {
        await _store.markSynced(pending.map((p) => p['sequence_number'] as int).toList());
        _lastSyncOk = true;
      } else {
        _lastSyncOk = false;
      }
    } catch (_) {
      _lastSyncOk = false;
      // Offline-first: rows remain PENDING and are retried later.
    }
    await _emit();
  }

  Future<void> stop() async {
    _syncTimer?.cancel();
    await _subscription?.cancel();
    await syncPending();
  }

  Future<void> dispose() async {
    await _status.close();
  }
}
