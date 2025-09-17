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
  runApp(const MainApp());
}

final supabase = Supabase.instance.client;

enum AppState {
  choosingLocation,
  confirmFare,
  waitingForPickup,
  riding,
  postRide
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
  late int _fare;

  @override
  void initState() {
    super.initState();
    _checkLocationPermission();
    _loadPinIcon();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future <void> _loadPinIcon() async {
    _pinIcon = await BitmapDescriptor.asset(
      ImageConfiguration(size: Size(48, 48)),
      'assets/images/pin.png'
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
        bottomSheet: _appState == AppState.confirmFare
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
                  onPressed: () async {}, 
                  child: const Text('Confirm Fare')
                )
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