import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:geofence_service/geofence_service.dart';

void main() => runApp(const CheckInApp());

class CheckInApp extends StatefulWidget {
  const CheckInApp({Key? key}) : super(key: key);

  @override
  State<CheckInApp> createState() => _CheckInAppState();
}

class _CheckInAppState extends State<CheckInApp> {
  final _activityStreamController = StreamController<Activity>();
  final _geofenceStreamController = StreamController<Geofence>();

  // Store check-in/out records
  final List<String> _records = [];

  // Create a GeofenceService instance
  final _geofenceService = GeofenceService.instance.setup(
    interval: 5000,
    accuracy: 100,
    loiteringDelayMs: 60000,
    statusChangeDelayMs: 10000,
    useActivityRecognition: true,
    allowMockLocations: false,
    printDevLog: false,
  );

  late List<Geofence> _geofenceList;

  @override
  void initState() {
    super.initState();
    _initializeGeofences();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _geofenceService.addGeofenceStatusChangeListener(_onGeofenceStatusChanged);
      _geofenceService.addActivityChangeListener(_onActivityChanged);
      _geofenceService.addStreamErrorListener(_onError);
      _geofenceService.start(_geofenceList).catchError(_onError);
    });
  }

  void _initializeGeofences() {
    final data = json.decode(locationsJson);
    _geofenceList = (data['data'][0]['buildings'] as List).map((building) {
      return Geofence(
        id: building['name'],
        latitude: building['latitude'],
        longitude: building['longitude'],
        radius: [
          GeofenceRadius(id: 'radius_${building['radius']}', length: building['radius']),
        ],
      );
    }).toList();
  }

  Future<void> _onGeofenceStatusChanged(
      Geofence geofence,
      GeofenceRadius geofenceRadius,
      GeofenceStatus geofenceStatus,
      Location location) async {
    final currentTime = DateTime.now().toString();
    String record;
    if (geofenceStatus == GeofenceStatus.ENTER) {
      record = 'Checked in to ${geofence.id} at $currentTime';
    } else if (geofenceStatus == GeofenceStatus.EXIT) {
      record = 'Checked out of ${geofence.id} at $currentTime';
    } else {
      return;
    }
    setState(() {
      _records.add(record);
    });
    print(record);
  }

  void _onActivityChanged(Activity prevActivity, Activity currActivity) {
    print('Activity changed: ${currActivity.toJson()}');
  }

  void _onError(error) {
    print('Error: $error');
  }

  @override
  void dispose() {
    _activityStreamController.close();
    _geofenceStreamController.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Check-In/Out App'),
          centerTitle: true,
        ),
        body: ListView.builder(
          itemCount: _records.length,
          itemBuilder: (context, index) {
            return ListTile(
              title: Text(_records[index]),
            );
          },
        ),
      ),
    );
  }
}
const String locationsJson = '''
{
  "data": [
    {
      "buildings": [
        {
          "id": 1,
          "name": "Building 1(Blossom Heights)",
          "latitude": 17.4470042,
          "longitude": 78.3810862,
          "radius": 10.0,
          "radiusUnit": "meter",
          "assets": [
            {
              "id": 101,
              "assetsName": "Assets 1(Conference Hall)",
              "latitude": 17.4470362,
              "longitude": 78.3811563,
              "radius": 1.0
            },
            {
              "id": 102,
              "assetsName": "Assets 2(RK Sir Cabin)",
              "latitude": 17.447003,
              "longitude": 78.3811143,
              "radius": 1.0
            },
            {
              "id": 103,
              "assetsName": "Assets 3(MD Cabin)",
              "latitude": 17.4469637,
              "longitude": 78.3811912,
              "radius": 0.0
            }
          ]
        },
        {
          "id": 1,
          "name": "Building 2(Blossom Heights)",
          "latitude": 28.6868032,
          "longitude": 77.3386944,
          "radius": 10.0,
          "radiusUnit": "meter",
          "assets": [
            {
              "id": 101,
              "assetsName": "Assets 1(Conference Hall)",
              "latitude": 28.5868032,
              "longitude": 77.3586944,
              "radius": 1.0
            }
            
          ]
        }
      ]
    }
  ]
}
''';
