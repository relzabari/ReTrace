import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../ui/app_design.dart';

class EventLocationSelection {
  const EventLocationSelection.current()
      : useCurrentLocation = true,
        latitude = null,
        longitude = null;

  const EventLocationSelection.mapPoint(this.latitude, this.longitude)
      : useCurrentLocation = false;

  final bool useCurrentLocation;
  final double? latitude;
  final double? longitude;
}

class EventLocationPickerPage extends StatefulWidget {
  const EventLocationPickerPage({
    super.key,
    required this.initialLatitude,
    required this.initialLongitude,
  });

  final double initialLatitude;
  final double initialLongitude;

  @override
  State<EventLocationPickerPage> createState() =>
      _EventLocationPickerPageState();
}

class _EventLocationPickerPageState extends State<EventLocationPickerPage> {
  LatLng? _selectedPoint;

  void _useCurrentLocation(bool? selected) {
    if (selected == true) {
      Navigator.pop(context, const EventLocationSelection.current());
    }
  }

  void _confirmMapPoint() {
    final point = _selectedPoint;
    if (point == null) return;
    Navigator.pop(
      context,
      EventLocationSelection.mapPoint(point.latitude, point.longitude),
    );
  }

  @override
  Widget build(BuildContext context) {
    final initialPoint = LatLng(
      widget.initialLatitude,
      widget.initialLongitude,
    );
    return Scaffold(
      appBar: AppBar(title: const Text('בחירת מיקום לאירוע')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: AppCard(
              tint: AppColors.mint,
              padding: EdgeInsets.zero,
              child: CheckboxListTile(
                value: false,
                onChanged: _useCurrentLocation,
                title: const Text('בחר מיקום עצמי',
                    style: TextStyle(
                        fontWeight: FontWeight.w900, color: AppColors.forest)),
                subtitle: const Text('חזרה מיידית ושימוש במיקום הטלפון'),
                secondary: const Icon(Icons.my_location_rounded,
                    color: AppColors.teal),
                controlAffinity: ListTileControlAffinity.leading,
              ),
            ),
          ),
          Expanded(
            child: Stack(
              children: [
                FlutterMap(
                  options: MapOptions(
                    initialCenter: initialPoint,
                    initialZoom: 16,
                    onTap: (_, point) => setState(() => _selectedPoint = point),
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName:
                          'com.example.exercise_tracker_prototype',
                    ),
                    MarkerLayer(
                      markers: [
                        if (_selectedPoint != null)
                          Marker(
                            point: _selectedPoint!,
                            width: 48,
                            height: 48,
                            alignment: Alignment.topCenter,
                            child: const Icon(
                              Icons.location_pin,
                              size: 48,
                              color: Colors.red,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
                Positioned(
                  top: 12,
                  left: 12,
                  right: 12,
                  child: AppCard(
                    tint: Colors.white.withValues(alpha: .94),
                    padding: const EdgeInsets.all(10),
                    child: Padding(
                      padding: EdgeInsets.zero,
                      child: Text(
                        _selectedPoint == null
                            ? 'לחץ על המפה כדי לבחור את מיקום האירוע'
                            : 'המיקום נבחר. ניתן להזיז אותו בלחיצה נוספת.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ),
                const Positioned(
                  bottom: 4,
                  left: 6,
                  child: DecoratedBox(
                    decoration: BoxDecoration(color: Colors.white70),
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 4),
                      child: Text(
                        '© OpenStreetMap contributors',
                        style: TextStyle(fontSize: 10),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          SafeArea(
            minimum: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: GradientActionButton(
                onPressed: _selectedPoint == null ? null : _confirmMapPoint,
                icon: Icons.check_circle_rounded,
                label: 'אישור המיקום שנבחר',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
