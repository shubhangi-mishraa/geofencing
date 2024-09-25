import 'dart:async';
import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geofence_service/geofence_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:shared_preferences/shared_preferences.dart';

void main() => runApp(const CheckInApp());

class CheckInApp extends StatefulWidget {
  const CheckInApp({Key? key}) : super(key: key);

  @override
  State<CheckInApp> createState() => _CheckInAppState();
}

class _CheckInAppState extends State<CheckInApp> {
  final _geofenceStreamController = StreamController<Geofence>();
  final List<Map<String, dynamic>> _records = [];
  final _geofenceService = GeofenceService.instance.setup(
    interval: 5000,
    accuracy: 100,
    loiteringDelayMs: 60000,
    statusChangeDelayMs: 10000,
    useActivityRecognition: false,
    allowMockLocations: false,
    printDevLog: false,
  );

  late List<Geofence> _geofenceList = [];
  double? _distanceFromGeofence;
  String? _currentCoordinates;

  @override
  void initState() {
    super.initState();
    checkPermissionStatus();
    _loadGeofences();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _geofenceService
          .addGeofenceStatusChangeListener(_onGeofenceStatusChanged);
      _geofenceService.addStreamErrorListener(_onError);
      _geofenceService.start(_geofenceList).catchError(_onError);
    });

    _getUserDistanceFromGeofence();
    Timer.periodic(const Duration(seconds: 5), (timer) {
      _getUserLocation();
    });
  }

  Future<void> initializeService() async {
    final service = FlutterBackgroundService();

    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: onStart,
        autoStart: true,
        isForegroundMode: true,
        notificationChannelId: 'my_foreground',
        initialNotificationTitle: 'Geofence Service',
        initialNotificationContent: 'Tracking geofences',
        foregroundServiceNotificationId: 888,
      ),
      iosConfiguration: IosConfiguration(
        autoStart: true,
        onForeground: onStart,
      ),
    );

    service.startService();
  }

  void onStart(ServiceInstance service) async {
    DartPluginRegistrant.ensureInitialized();

    Timer.periodic(const Duration(seconds: 10), (timer) async {
      Position position = await Geolocator.getCurrentPosition();
      await checkGeofenceStatus(position);
    });
  }

  Future<void> checkGeofenceStatus(Position position) async {
    final geofenceList = await loadGeofences();

    for (var geofence in geofenceList) {
      double distance = Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        geofence.latitude,
        geofence.longitude,
      );

      if (distance < geofence.radius.first.length) {
        await updateCheckInTime(geofence.id);
      } else {
        await updateCheckOutTime(geofence.id);
      }
    }
  }

  Future<void> updateCheckInTime(String geofenceId) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String checkInTime =
        DateFormat('dd/MM/yyyy HH:mm:ss').format(DateTime.now());
    prefs.setString('check_in_time_$geofenceId', checkInTime);
    print("checkInTime :: $checkInTime");

  }

  Future<void> updateCheckOutTime(String geofenceId) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String checkOutTime =
        DateFormat('dd/MM/yyyy HH:mm:ss').format(DateTime.now());
    prefs.setString('check_out_time_$geofenceId', checkOutTime);
    print("checkOutTime :: $checkOutTime");
  }

  Future<void> getPermission() async {
    if (await Permission.location.request().isGranted) {}
  }

  Future<void> checkPermissionStatus() async {
    var status = await Permission.location.status;
    if (status.isDenied) {
      getPermission();
    }
  }

  Future<void> _loadGeofences() async {
    final String response = await rootBundle.loadString('assets/location.json');
    final data = json.decode(response);

    for (var building in data['data'][0]['buildings']) {
      double radiusValue = building['radius']?.toDouble() ?? 0.0;
      if (radiusValue > 0.0) {
        _geofenceList.add(Geofence(
          id: building['name'],
          latitude: building['latitude'],
          longitude: building['longitude'],
          radius: [
            GeofenceRadius(
                id: 'radius_${building['radius']}', length: radiusValue),
          ],
        ));
      } else {
        print('Invalid radius for building: ${building['name']}');
      }

      for (var asset in building['assets']) {
        double assetRadiusValue = asset['radius']?.toDouble() ?? 0.0;
        if (assetRadiusValue > 0.0) {
          _geofenceList.add(Geofence(
            id: asset['assetsName'],
            latitude: asset['latitude'],
            longitude: asset['longitude'],
            radius: [
              GeofenceRadius(
                  id: 'radius_${asset['radius']}', length: assetRadiusValue),
            ],
          ));
        } else {
          print('Invalid radius for asset: ${asset['assetsName']}');
        }
      }
    }

    _geofenceService.start(_geofenceList).catchError(_onError);
  }

  Future<void> _getUserDistanceFromGeofence() async {
    try {
      Position position = await Geolocator.getCurrentPosition();
      setState(() {
        _currentCoordinates =
            'Lat: ${position.latitude}, Lng: ${position.longitude}';
      });

      print('Current User Location: $_currentCoordinates');

      if (_geofenceList.isNotEmpty) {
        final geofence = _geofenceList[0];
        _calculateDistanceFromGeofence(position.latitude, position.longitude,
            geofence.latitude, geofence.longitude);
      }
    } catch (e) {
      print('Error fetching user location: $e');
    }
  }

  Future<List<Geofence>> loadGeofences() async {
    return _geofenceList;
  }

  Future<void> _getUserLocation() async {
    try {
      Position position = await Geolocator.getCurrentPosition();
      setState(() {
        _currentCoordinates =
            'Lat: ${position.latitude}, Lng: ${position.longitude}';
      });

      print('Updated User Location: $_currentCoordinates');

      if (_geofenceList.isNotEmpty) {
        final geofence = _geofenceList[0];
        _calculateDistanceFromGeofence(position.latitude, position.longitude,
            geofence.latitude, geofence.longitude);
      }
    } catch (e) {
      print('Error fetching user location: $e');
    }
  }
  Future<void> _onGeofenceStatusChanged(
      Geofence geofence,
      GeofenceRadius geofenceRadius,
      GeofenceStatus geofenceStatus,
      Location location) async {
    final currentTime = DateTime.now();
    String formattedTime =
        DateFormat('dd/MM/yyyy HH:mm:ss').format(currentTime);

    print('Geofence: ${geofence.id}, Status: $geofenceStatus');

    if (geofenceStatus == GeofenceStatus.ENTER) {
      setState(() {
        _records.add({
          'status': 'Checked in',
          'geofenceId': geofence.id,
          'time': formattedTime,
        });
        _distanceFromGeofence = null;
      });
    } else if (geofenceStatus == GeofenceStatus.EXIT) {
      setState(() {
        _records.add({
          'status': 'Checked out',
          'geofenceId': geofence.id,
          'time': formattedTime,
        });
        _calculateDistanceFromGeofence(location.latitude, location.longitude,
            geofence.latitude, geofence.longitude);
      });
    }
  }

  void _calculateDistanceFromGeofence(double userLat, double userLng,
      double geofenceLat, double geofenceLng) async {
    final distance =
        Geolocator.distanceBetween(userLat, userLng, geofenceLat, geofenceLng);

    setState(() {
      _distanceFromGeofence = distance;
    });
  }

  void _onError(error) {
    print('Error: $error');
  }

  @override
  void dispose() {
    _geofenceStreamController.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Check-In/Out App'),
          centerTitle: true,
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                _currentCoordinates ?? 'Fetching coordinates...',
                style: TextStyle(fontSize: 16, color: Colors.blue),
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: _records.length,
                itemBuilder: (context, index) {
                  final record = _records[index];
                  return Card(
                    margin:
                        const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                    elevation: 4,
                    child: ListTile(
                      title: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          RichText(
                            text: TextSpan(
                              children: [
                                TextSpan(
                                  text: '${record['status']} ',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: record['status'] == 'Checked in'
                                        ? Colors.green
                                        : Colors.red,
                                    fontSize: 16,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          RichText(
                            text: TextSpan(
                              children: [
                                TextSpan(
                                  text: '${record['geofenceId']} \n',
                                  style: TextStyle(
                                      fontSize: 16, color: Colors.black),
                                ),
                                TextSpan(
                                  text: record['time'],
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                      color: Colors.black),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            if (_distanceFromGeofence != null)
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  'You are ${_distanceFromGeofence!.toStringAsFixed(2)} meters away from the geofence.',
                  style: TextStyle(color: Colors.red, fontSize: 16),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
