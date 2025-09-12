import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> main() async {
  Supabase.initialize(
    url: "https://bscdsdtlyrevmkoolkez.supabase.co", 
    anonKey: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJzY2RzZHRseXJldm1rb29sa2V6Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTc1OTk0OTAsImV4cCI6MjA3MzE3NTQ5MH0.FMTndUqS0wJ1-dVEh7Ftulqsq621od4gNsRKLg6wP5A"
  );

  await dotenv.load(fileName: ".env");
  runApp(const MainApp());
}

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
  CameraPosition? _initialPosition;
  late GoogleMapController _mapController;

  @override
  void initState() {
    super.initState();
    _checkLocationPermission();
  }

  @override
  void dispose() {
    super.dispose();
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

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Stack(
          children: [
            GoogleMap(
              myLocationEnabled: true,
              initialCameraPosition: CameraPosition(
                target: LatLng(37.7749, -122.4194),
                zoom: 14
              ),
              onMapCreated: (controller) {
                _mapController = controller;
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
        floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () async {
            
          }, 
          label: const Text('Confirm Destination')
        ),
      ),
    );
  }
}