import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

Future<void> main() async {
  await dotenv.load(fileName: ".env");
  runApp(const MyApp());
}

enum AppState {
  choosingLocation,
  confirmFare,
  waitingForPickup,
  riding,
  postRide
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
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
    LatLng? _currentLocation;
    CameraPosition? _initialPosition;

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
    });
  }

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: Scaffold(
        body: GoogleMap(
          myLocationEnabled: true,
          initialCameraPosition: CameraPosition(
            target: LatLng(37.7749, -122.4194),
            zoom: 14
          )
        )
      ),
    );
  }
}