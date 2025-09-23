import 'dart:async';
import 'dart:math';

import 'package:duration/duration.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> main() async {
  Supabase.initialize(
    url: "https://bscdsdtlyrevmkoolkez.supabase.co", 
    anonKey: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJzY2RzZHRseXJldm1rb29sa2V6Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTc1OTk0OTAsImV4cCI6MjA3MzE3NTQ5MH0.FMTndUqS0wJ1-dVEh7Ftulqsq621od4gNsRKLg6wP5A"
  );

  await dotenv.load(fileName: ".env");
  runApp(const MaterialApp(
    home: MainApp(),
  ));
}

final supabase = Supabase.instance.client;

enum AppState {
  choosingLocation,
  confirmFare,
  waitingForPickup,
  riding,
  postRide
}

enum RideStatus {
  picking_up,
  riding,
  completed
}

class Driver {
  final String id;
  final String model;
  final String number;
  final bool isAvailable;
  final LatLng location;

  Driver({
    required this.id,
    required this.model,
    required this.number,
    required this.isAvailable,
    required this.location
  });

  factory Driver.fromJson(Map<String, dynamic> json) {
    return Driver(
      id: json['id'],
      model: json['model'],
      number: json['number'],
      isAvailable: json['is_available'],
      location: LatLng(json['latitude'], json['longitude'])
    );
  }
}

class Ride {
  final String id;
  final String driverId;
  final String passengerId;
  final int fare;
  final RideStatus status;

  Ride({
    required this.id,
    required this.driverId,
    required this.passengerId,
    required this.fare,
    required this.status
  });

  factory Ride.fromJson(Map<String, dynamic> json) {
    return Ride(
      id: json['id'],
      driverId: json['driver_id'],
      passengerId: json['passenger_id'],
      fare: json['fare'],
      status: RideStatus.values.firstWhere((e) => e.toString().split('.').last == json['status'])
    );
  }
}

class MainApp extends StatefulWidget {
  const MainApp({super.key});

  @override
  State<MainApp> createState() => _MainAppState();
}

class _MainAppState extends State<MainApp> {
  AppState _appState = AppState.choosingLocation;
  LatLng? _currentLocation;
  LatLng? _selectedDestination;
  CameraPosition? _initialPosition;
  
  late GoogleMapController _mapController;
  final Set <Polyline> _polylines = {};
  final Set <Marker> _markers = {};

  BitmapDescriptor? _pinIcon;
  BitmapDescriptor? _carIcon; 

  late int _fare;
  StreamSubscription? _driverSubscription;
  StreamSubscription? _rideSubscription;

  Driver? _driver;

  LatLng? _previousDriverPosition;

  @override
  void initState() {
    super.initState();
    _signInIfNotSignedIn();
    _checkLocationPermission();
    _loadIcons();
  }

  @override
  void dispose() {
    _cancelSubscriptions();
    super.dispose();
  }

  Future <void> _signInIfNotSignedIn() async {
    if(supabase.auth.currentSession == null) {
      await supabase.auth.signInAnonymously();
    }
  }

  Future <void> _loadIcons() async {
    _pinIcon = await BitmapDescriptor.asset(
      ImageConfiguration(size: Size(48, 48)),
      'assets/images/pin.png'
    );

    _carIcon = await BitmapDescriptor.asset(
      ImageConfiguration(size: Size(48, 48)),
      'assets/images/car.png'
    );
  }

  Future <void> _checkLocationPermission() async {
    final isServiceEnabled = await Geolocator.isLocationServiceEnabled();
    if(!isServiceEnabled) {
      if(mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please Enable GPS Service'))
        );

        return;
      }
    }

    var permission = await Geolocator.checkPermission();
    if(permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();

      if(permission == LocationPermission.denied) {
        if(mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Please Enable GPS Service'))
          );

          return;
        }
      }
    }

    if(permission == LocationPermission.deniedForever) {
      if(mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please Enable GPS Service'))
        );

        return;
      }
    }

    final position = await Geolocator.getCurrentPosition();
    setState(() {
      _currentLocation = LatLng(position.latitude, position.longitude);
      _initialPosition = CameraPosition(
        target: _currentLocation!,  
        zoom: 14
      );
      _mapController.animateCamera(
        CameraUpdate.newCameraPosition(_initialPosition!)
      );
    });
  }

  void _goToNextState() {
    setState(() {
      if(_appState == AppState.postRide) {
        _appState = AppState.choosingLocation;
      } else {
        _appState = AppState.values[_appState.index + 1];
      }
    });
  }

  double _calculateRotation(LatLng start, LatLng end) {
    double latDiff = end.latitude - start.latitude;
    double longDiff = end.longitude - start.longitude;
    double angle = atan2(longDiff, latDiff);

    return (angle * 180) / pi;
  }

  void _cancelSubscriptions() {
    _driverSubscription?.cancel();
    _rideSubscription?.cancel();
  }

  void _showCompletionModal() {
    showDialog(
      context: context, 
      builder: (context) {
        return AlertDialog(
          title: Text('Ride Completed'),
          content: Text('Thank you for using our services !!'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                setState(() {
                  _appState = AppState.choosingLocation;
                  _selectedDestination = null;
                  _driver = null;
                  _polylines.clear();
                  _markers.clear();
                });
              }, 
              child: Text('Close')
            )
          ],
        );
      }
    );
  }

  void _updateDriverMarker(Driver driver) {
    setState(() {
      _markers.removeWhere((marker) => marker.markerId.value == 'driver');

      double rotation = 0;
      if(_previousDriverPosition != null) {
        rotation = _calculateRotation(_previousDriverPosition!, driver.location);
      }

      _markers.add(
        Marker(
          markerId: MarkerId('driver'),
          position: driver.location,
          icon: _carIcon!,
          rotation: rotation
        )
      );
      _previousDriverPosition = driver.location;
    });
  }

  void _adjustMapView({required LatLng target}) {
    final bounds = LatLngBounds(
      southwest: LatLng(min(_driver!.location.latitude, target.latitude), min(_driver!.location.longitude, target.longitude)), 
      northeast: LatLng(max(_driver!.location.latitude, target.latitude), max(_driver!.location.longitude, target.longitude))
    );

    _mapController.animateCamera(CameraUpdate.newLatLngBounds(bounds, 50));
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Stack(
          children: [
            GoogleMap(
              polylines: _polylines,
              markers: _markers,
              myLocationEnabled: true,
              initialCameraPosition: CameraPosition(
                target: LatLng(37.7749, -122.4194),
                zoom: 14
              ),
              onMapCreated: (controller) {
                _mapController = controller;
              },
              onCameraMove: (position) {
                if(_appState == AppState.choosingLocation) {
                  _selectedDestination = position.target;
                }
              },
            ),
            
            if(_appState == AppState.choosingLocation)
              Center(
                child: Image.asset(
                  'assets/images/center-pin.png',
                  width: 100,
                  height: 100,
                ),
              )
          ]
        ),
        bottomSheet: _appState == AppState.confirmFare || _appState == AppState.waitingForPickup
          ? Container(
            width: MediaQuery.of(context).size.width,
            padding: const EdgeInsets.all(16).copyWith(bottom: MediaQuery.of(context).padding.bottom),
            decoration: const BoxDecoration(
              color: Colors.white,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                if(_appState == AppState.confirmFare) ...[
                  Text(
                    'Confirm Fare',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 16),

                  Text('Estimated Fare: ${NumberFormat.currency(
                    symbol: '\$',
                    decimalDigits: 2
                  ).format(_fare / 100)}'),
                  const SizedBox(height: 16),

                  ElevatedButton(
                    onPressed: () async {
                      try {
                        final response = await supabase.rpc('find_driver', params: {
                          'origin': 'POINT(${_currentLocation!.longitude} ${_currentLocation!.latitude})',
                          'destination': 'POINT(${_selectedDestination!.longitude} ${_selectedDestination!.latitude})',
                          'fare': _fare
                        }) as List<dynamic>;

                        if(response.isEmpty) {
                          if(mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('No Driver found. Please Try again later.'))
                            );
                          }
                        }

                        final driverId = response.first['driver_id'] as String;
                        final rideId = response.first['ride_id'] as String;

                        _driverSubscription = supabase
                          .from('drivers')
                          .stream(primaryKey: ['id'])
                          .eq('id', driverId)
                          .listen((driver) {
                            _driver = Driver.fromJson(driver.first);

                            _updateDriverMarker(_driver!);
                            _adjustMapView(target: _appState == AppState.waitingForPickup ? _currentLocation! : _selectedDestination!);
                          })
                        ;

                        _rideSubscription = supabase
                          .from('rides')
                          .stream(primaryKey: ['id'])
                          .eq('id', rideId)
                          .listen((rides) {
                            final ride = Ride.fromJson(rides.first);

                            if(ride.status == RideStatus.riding) {
                              setState(() {
                                _appState = AppState.riding;
                              });
                            } else if(ride.status == RideStatus.completed) {
                              setState(() {
                                _appState = AppState.postRide;

                                _cancelSubscriptions();
                                _showCompletionModal();
                              });
                            }
                          })
                        ;

                        _goToNextState();
                      }
                      catch(error) {
                        print(error);
                      }
                    }, 
                    child: const Text('Confirm Fare')
                  )
                ],
                if(_appState == AppState.waitingForPickup && _driver != null) ...[
                  Text(
                    'Your Driver',
                    style: Theme.of(context).textTheme.titleLarge
                  ),
                  const SizedBox(height: 8),

                  Text(
                    'Car: ${_driver!.model}',
                    style: Theme.of(context).textTheme.titleMedium
                  ),
                  const SizedBox(height: 8),

                  Text(
                    'Plate Number: ${_driver!.number}',
                    style: Theme.of(context).textTheme.titleMedium
                  ),
                  const SizedBox(height: 16),

                  Text(
                    'Your driver is on the way. Please wait at the pickup location.',
                    style: Theme.of(context).textTheme.bodyMedium
                  )
                ]
              ],
            ),
          )
          : SizedBox.shrink()
        ,
        floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
        floatingActionButton: _appState == AppState.choosingLocation 
          ? FloatingActionButton.extended(
            onPressed: () async {
              final response = await supabase.functions.invoke(
                'routes',
                body: {
                  'origin': {
                    'latitude': _currentLocation!.latitude,
                    'longitude': _currentLocation!.longitude
                  },
                  'destination': {
                    'latitude': _selectedDestination!.latitude,
                    'longitude': _selectedDestination!.longitude
                  }
                }
              );

              final data = response.data as Map <String, dynamic>;
              final coordinates = data['legs'][0]['polyline']['geoJsonLinestring']['coordinates'] as List <dynamic>;
              final duration = parseDuration(data['duration'] as String);
              _fare = (duration.inMinutes * 40).ceil();

              final polylineCoordinates = coordinates.map((coordinate) {
                return LatLng(coordinate[1], coordinate[0]);
              }).toList();

              setState(() {
                _polylines.add(
                  Polyline(
                    polylineId: const PolylineId('route'),
                    points: polylineCoordinates,
                    color: Colors.black,
                    width: 5
                  )
                );
              });

              _markers.add(
                Marker(
                  markerId: MarkerId('destination'),
                  position: _selectedDestination!,
                  icon: _pinIcon!
                )
              );

              final bounds = LatLngBounds(
                southwest: LatLng(
                  polylineCoordinates.map((e) => e.latitude).reduce((a, b) => a < b ? a : b),
                  polylineCoordinates.map((e) => e.longitude).reduce((a, b) => a < b ? a : b)
                ),
                northeast: LatLng(
                  polylineCoordinates.map((e) => e.latitude).reduce((a, b) => a > b ? a : b),
                  polylineCoordinates.map((e) => e.longitude).reduce((a, b) => a > b ? a : b)
                )
              );

              _mapController.animateCamera(
                CameraUpdate.newLatLngBounds(bounds, 100)
              );

              _goToNextState();
            }, 
            label: const Text('Confirm Destination')
          )
          : SizedBox.shrink()
        ,
      ),
    );
  }
}