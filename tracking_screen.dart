import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_vector_icons/flutter_vector_icons.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:location/location.dart';
import 'package:permission_handler/permission_handler.dart' as permission;
import 'package:url_launcher/url_launcher.dart';

class TrackingScreen extends StatefulWidget {
  final Map<String, dynamic> bookingData;

  const TrackingScreen({super.key, required this.bookingData});

  @override
  State<TrackingScreen> createState() => _TrackingScreenState();
}

class _TrackingScreenState extends State<TrackingScreen>
    with SingleTickerProviderStateMixin {
  // Controllers and references
  final Completer<GoogleMapController> _mapController = Completer();
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _slideAnimation;

  // Location and map state
  final Location _location = Location();
  LatLng? _userLocation;
  LatLng? _driverLocation;
  LatLng? _destinationLocation;
  final LatLng _defaultUserLocation = const LatLng(19.0760, 72.8777); // Mumbai
  CameraPosition _initialCameraPosition = const CameraPosition(
    target: LatLng(19.0760, 72.8777), // Mumbai
    zoom: 14.0,
  );

  // Route data
  List<LatLng> _driverToPickupRoute = [];
  List<LatLng> _pickupToDestinationRoute = [];

  // UI state
  bool _isLoading = true;
  bool _isFetchingRoute = false;
  bool _hasLocationPermission = false;
  bool _driverNearby = false;
  bool _tripStarted = false;
  final bool _tripCompleted = false;
  bool _notificationShown = false;
  bool _otpVerified = false;
  bool _showOtpModal = false;

  // OTP state
  String _otp = '';
  String _generatedOtp = '';

  // Trip info
  String? _locationError;

  // Booking data
  late String _bookingId;

  late String _tripType;

  late String _pickup;
  late String _destination;
  late String _distance = 'Calculating...';
  late String _duration = 'Calculating...';
  late Map<String, dynamic> _driverInfo = {};
  late Map<String, dynamic> _tripInfo = {};
  late String _statusMessage = 'Connecting to driver...';

  @override
  void initState() {
    super.initState();

    _animationController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(_animationController);
    _slideAnimation = Tween<double>(
      begin: 50.0,
      end: 0.0,
    ).animate(_animationController);

    // Initialize booking data
    _initializeBookingData();

    // Start location tracking
    _initializeLocationTracking();

    // Start driver movement simulation
    _startDriverSimulation();

    // Show first OTP after 30 seconds
    Future.delayed(const Duration(seconds: 30), () {
      if (mounted) {
        _showStartTripOtp();
      }
    });
  }

  void _initializeBookingData() {
    _bookingId = widget.bookingData['bookingId'] ?? '';
    _tripType = widget.bookingData['tripType'] ?? 'oneWay';
    _pickup = widget.bookingData['pickup'] ?? '';
    _destination = widget.bookingData['destination'] ?? '';

    // Initialize source and destination coordinates
    final sourceLat =
        widget.bookingData['pickupLocation']?['latitude'] ?? 19.0760;
    final sourceLng =
        widget.bookingData['pickupLocation']?['longitude'] ?? 72.8777;
    final destLat =
        widget.bookingData['destinationLocation']?['latitude'] ?? 19.0860;
    final destLng =
        widget.bookingData['destinationLocation']?['longitude'] ?? 72.8877;

    // Initialize driver location if available from API
    final driverLat = 
        widget.bookingData['driverLocation']?['latitude'] ?? 0.0;
    final driverLng = 
        widget.bookingData['driverLocation']?['longitude'] ?? 0.0;
    
    // Initialize user location if available from API
    final userLat = 
        widget.bookingData['userLocation']?['latitude'] ?? 0.0;
    final userLng = 
        widget.bookingData['userLocation']?['longitude'] ?? 0.0;

    debugPrint('Driver location: $driverLat, $driverLng');
    debugPrint('User location: $userLat, $userLng');

    // Set destination location
    _destinationLocation = LatLng(destLat.toDouble(), destLng.toDouble());

    // Set initial camera position to pickup location
    _initialCameraPosition = CameraPosition(
      target: LatLng(sourceLat.toDouble(), sourceLng.toDouble()),
      zoom: 14.0,
    );

    // If user location is available from API, use it
    if (userLat != 0.0 && userLng != 0.0) {
      _userLocation = LatLng(userLat.toDouble(), userLng.toDouble());
    }

    // If driver location is available from API, use it
    if (driverLat != 0.0 && driverLng != 0.0) {
      _driverLocation = LatLng(driverLat.toDouble(), driverLng.toDouble());
      
      // If both driver and user locations are available, 
      // fetch route between them immediately
      if (_userLocation != null) {
        Future.delayed(Duration.zero, () {
          _fetchDriverToUserRoute(_driverLocation!, _userLocation!);
        });
      }
    }

    // Extract booking data
    _extractBookingData();
  }

  Future<void> _initializeLocationTracking() async {
    try {
      await _requestLocationPermission();
      await _getCurrentLocation();
      _setupLocationTracking();
    } catch (e) {
      setState(() {
        _locationError = 'Error initializing location tracking: $e';
        _isLoading = false;
      });
    }
  }

  void _showStartTripOtp() {
    final startOtp = _generateOtp();
    setState(() {
      _generatedOtp = startOtp;
      _showOtpModal = true;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Your start trip OTP is $startOtp'),
        duration: const Duration(seconds: 5),
      ),
    );
  }

  void _extractBookingData() {
    try {
      final bookingData = widget.bookingData;

      _pickup = bookingData['pickup'] ?? 'Pickup location';
      _destination = bookingData['destination'] ?? 'Destination location';
      _driverInfo =
          bookingData['driverInfo'] ??
          {
            'name': 'Driver',
            'phoneNumber': '',
            'rating': 4.5,
            'vehicleModel': 'Car',
            'vehicleColor': 'White',
            'licensePlate': 'XX-XX-XXXX',
          };
      _tripInfo =
          bookingData['tripInfo'] ??
          {'fare': '₹0', 'distance': '0 km', 'duration': '0 min'};

      // Set initial status message
      _statusMessage = 'Connecting to driver...';

      debugPrint('Booking data extracted successfully');
    } catch (e) {
      debugPrint('Error extracting booking data: $e');
      // Set default values if extraction fails
      _pickup = 'Pickup location';
      _destination = 'Destination location';
      _driverInfo = {
        'name': 'Driver',
        'phoneNumber': '',
        'rating': 4.5,
        'vehicleModel': 'Car',
        'vehicleColor': 'White',
        'licensePlate': 'XX-XX-XXXX',
      };
      _tripInfo = {'fare': '₹0', 'distance': '0 km', 'duration': '0 min'};
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  // Location permission handling
  Future<void> _requestLocationPermission() async {
    try {
      final status = await permission.Permission.location.request();
      setState(() {
        _hasLocationPermission = status.isGranted;
      });

      if (status.isGranted) {
        _getCurrentLocation();
      } else {
        setState(() {
          _locationError =
              'Location permission denied. Cannot track your ride.';
          _userLocation = _defaultUserLocation;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error requesting location permission: $e');
      setState(() {
        _locationError = 'Failed to request location permission';
        _userLocation = _defaultUserLocation;
        _isLoading = false;
      });
    }
  }

  // Get current location
  Future<void> _getCurrentLocation() async {
    setState(() => _isLoading = true);

    try {
      final locationData = await _location.getLocation();
      final userCurrentLocation = LatLng(
        locationData.latitude!,
        locationData.longitude!,
      );

      debugPrint('User location obtained: $userCurrentLocation');

      // Only set user location if not already set from API
      if (_userLocation == null) {
        setState(() {
          _userLocation = userCurrentLocation;
        });
      }

      // Only simulate driver position if not already set from API
      if (_driverLocation == null) {
        // Simulate initial driver position slightly away from user
        final driverInitialLocation = LatLng(
          userCurrentLocation.latitude - 0.015,
          userCurrentLocation.longitude - 0.010,
        );

        setState(() {
          _driverLocation = driverInitialLocation;
        });

        // Fetch initial route: Driver to User
        _fetchDriverToUserRoute(driverInitialLocation, _userLocation!);
      }

      setState(() {
        _locationError = null;
        _isLoading = false;
      });

      // Start location tracking
      _setupLocationTracking();
    } catch (e) {
      debugPrint('Error getting location: $e');

      // If user and driver locations are not set from API, use default locations
      if (_userLocation == null) {
        setState(() {
          _userLocation = _defaultUserLocation;
        });
      }

      if (_driverLocation == null) {
        final driverInitialLocation = LatLng(
          _defaultUserLocation.latitude - 0.02,
          _defaultUserLocation.longitude - 0.01,
        );

        setState(() {
          _driverLocation = driverInitialLocation;
        });

        // Fetch route with default locations
        _fetchDriverToUserRoute(driverInitialLocation, _userLocation!);
      }

      setState(() {
        _isLoading = false;
      });
    }
  }

  // Setup continuous location tracking
  void _setupLocationTracking() {
    if (!_hasLocationPermission) return;

    _location.onLocationChanged.listen((locationData) {
      if (locationData.latitude != null && locationData.longitude != null) {
        // Only update user location from device if it was not provided by API
        // or if we want real-time tracking (always update)
        final bool shouldUpdateUserLocation = true; // Set to false if you only want to use API data
        
        if (shouldUpdateUserLocation || _userLocation == null) {
          setState(() {
            _userLocation = LatLng(
              locationData.latitude!,
              locationData.longitude!,
            );
          });
          
          // If driver location is available and user location changes, update the route
          if (_driverLocation != null && !_tripStarted) {
            _fetchDriverToUserRoute(_driverLocation!, _userLocation!);
          } else if (_tripStarted && _destinationLocation != null) {
            // If trip has started, update route to destination
            _fetchUserToDestinationRoute(_userLocation!, _destinationLocation!);
          }
          
          debugPrint('User location updated: $_userLocation');
        }
      }
    });
  }

  // Start driver simulation
  void _startDriverSimulation() {
    if (_otpVerified || _driverLocation == null) return;

    Timer.periodic(const Duration(seconds: 5), (timer) {
      if (!mounted || _otpVerified || _userLocation == null || _driverLocation == null) {
        timer.cancel();
        return;
      }

      setState(() {
        if (_driverLocation != null && _userLocation != null) {
          // Simple linear interpolation towards the user
          final moveFactor = 0.15; // How much closer the driver gets each interval
          final newLat = _driverLocation!.latitude +
              (_userLocation!.latitude - _driverLocation!.latitude) * moveFactor;
          final newLng = _driverLocation!.longitude +
              (_userLocation!.longitude - _driverLocation!.longitude) * moveFactor;

          final currentDriverLoc = LatLng(newLat, newLng);

          // Calculate distance to user in meters
          final distanceToUser = _calculateDistance(currentDriverLoc, _userLocation!);

          // Check if driver is close enough to trigger "nearby" actions
          const arrivalThreshold = 150.0; // meters
          if (distanceToUser < arrivalThreshold && !_notificationShown) {
            debugPrint('Driver is nearby!');
            _showDriverNearbyActions();
            _notificationShown = true;
            _statusMessage = 'Driver has arrived!';
          }

          // Update status based on progress
          if (!_driverNearby && !_notificationShown) {
            if (distanceToUser < 500) {
              _statusMessage = 'Driver is approaching';
            } else {
              _statusMessage = 'Driver is on the way';
            }
          }

          _driverLocation = currentDriverLoc;
          
          // Update the route
          _fetchDriverToUserRoute(_driverLocation!, _userLocation!);
        }
      });
    });
  }

  // Calculate distance between two coordinates
  double _calculateDistance(LatLng loc1, LatLng loc2) {
    const R = 6371e3; // Earth radius in meters
    final phi1 = loc1.latitude * pi / 180;
    final phi2 = loc2.latitude * pi / 180;
    final deltaPhi = (loc2.latitude - loc1.latitude) * pi / 180;
    final deltaLambda = (loc2.longitude - loc1.longitude) * pi / 180;

    final a =
        sin(deltaPhi / 2) * sin(deltaPhi / 2) +
        cos(phi1) * cos(phi2) * sin(deltaLambda / 2) * sin(deltaLambda / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));

    return R * c;
  }

  // Fetch route between two points
  Future<List<LatLng>> _getDirections(LatLng origin, LatLng destination) async {
    setState(() => _isFetchingRoute = true);

    try {
      final apiKey =
          'AIzaSyCelDo4I5cPQ72TfCTQW-arhPZ7ALNcp8w'; // Replace with your API key
      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/directions/json?'
        'origin=${origin.latitude},${origin.longitude}'
        '&destination=${destination.latitude},${destination.longitude}'
        '&key=$apiKey',
      );

      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data['status'] == 'OK') {
          // Extract route polyline
          final points = data['routes'][0]['overview_polyline']['points'];
          final decodedCoords = _decodePolyline(points);

          // Extract distance and duration
          if (data['routes'][0]['legs'] != null &&
              data['routes'][0]['legs'].isNotEmpty) {
            setState(() {
              _distance = data['routes'][0]['legs'][0]['distance']['text'];
              _duration = data['routes'][0]['legs'][0]['duration']['text'];
            });
          }

          debugPrint('Directions fetched successfully.');
          return decodedCoords;
        } else {
          debugPrint(
            'No routes found or error in Directions API response: ${data['status']}',
          );
          setState(() {
            _locationError = 'Could not get directions: ${data['status']}';
          });
          return [];
        }
      } else {
        debugPrint('Error fetching directions: ${response.statusCode}');
        setState(() {
          _locationError =
              'Failed to fetch directions. Check network or API key.';
        });
        return [];
      }
    } catch (e) {
      debugPrint('Error fetching directions: $e');
      setState(() {
        _locationError =
            'Failed to fetch directions. Check network or API key.';
      });
      return [];
    } finally {
      setState(() => _isFetchingRoute = false);
    }
  }

  // Decode Google Maps polyline
  List<LatLng> _decodePolyline(String encoded) {
    List<LatLng> poly = [];
    int index = 0, len = encoded.length;
    int lat = 0, lng = 0;

    while (index < len) {
      int b, shift = 0, result = 0;

      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);

      int dlat = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lat += dlat;

      shift = 0;
      result = 0;

      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);

      int dlng = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lng += dlng;

      final p = LatLng(lat / 1E5, lng / 1E5);
      poly.add(p);
    }

    return poly;
  }

  // Fetch and update the Driver -> User route
  Future<void> _fetchDriverToUserRoute(LatLng driverLoc, LatLng userLoc) async {
    setState(() => _statusMessage = 'Finding route for driver...');

    final route = await _getDirections(driverLoc, userLoc);

    if (route.isNotEmpty) {
      setState(() {
        _driverToPickupRoute = route;
        _statusMessage = 'Driver is on the way';
      });

      // Fit map to the fetched route
      _fitMapToCoordinates([driverLoc, userLoc]);
    } else {
      // Handle error case
      final mapController = await _mapController.future;
      mapController.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: LatLng(
              (driverLoc.latitude + userLoc.latitude) / 2,
              (driverLoc.longitude + userLoc.longitude) / 2,
            ),
            zoom: 12.0,
          ),
        ),
      );
    }
  }

  // Fetch and update the User -> Destination route
  Future<void> _fetchUserToDestinationRoute(
    LatLng userLoc,
    LatLng destLoc,
  ) async {
    setState(() => _statusMessage = 'Calculating route to destination...');

    final route = await _getDirections(userLoc, destLoc);

    if (route.isNotEmpty) {
      setState(() {
        _pickupToDestinationRoute = route;
        _statusMessage = 'On the way to destination';
      });

      // Fit map to the new route
      _fitMapToCoordinates([userLoc, destLoc]);
    } else {
      setState(() => _statusMessage = 'Could not calculate destination route');
    }
  }

  // Fit map to show specific coordinates
  Future<void> _fitMapToCoordinates(List<LatLng> coordinates) async {
    if (coordinates.isEmpty) return;

    final mapController = await _mapController.future;

    final bounds = _calculateBounds(coordinates);

    mapController.animateCamera(
      CameraUpdate.newLatLngBounds(bounds, 100.0), // 100 is padding
    );
  }

  // Calculate bounds for a list of coordinates
  LatLngBounds _calculateBounds(List<LatLng> coordinates) {
    double? minLat, maxLat, minLng, maxLng;

    for (final coord in coordinates) {
      minLat = minLat == null ? coord.latitude : min(minLat, coord.latitude);
      maxLat = maxLat == null ? coord.latitude : max(maxLat, coord.latitude);
      minLng = minLng == null ? coord.longitude : min(minLng, coord.longitude);
      maxLng = maxLng == null ? coord.longitude : max(maxLng, coord.longitude);
    }

    return LatLngBounds(
      southwest: LatLng(minLat!, minLng!),
      northeast: LatLng(maxLat!, maxLng!),
    );
  }

  // Generate OTP
  String _generateOtp() {
    final randomOtp = (1000 + Random().nextInt(9000)).toString();
    setState(() => _generatedOtp = randomOtp);
    return randomOtp;
  }

  // Show driver nearby notification and OTP modal
  void _showDriverNearbyActions() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Your driver is nearby! Get ready for pickup.'),
        duration: Duration(seconds: 3),
      ),
    );

    setState(() => _driverNearby = true);

    // Generate OTP and show modal
    final otpCode = _generateOtp();
    setState(() => _showOtpModal = true);

    // Show OTP notification
    Future.delayed(const Duration(seconds: 1), () {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Your OTP is $otpCode. Share with driver to start the trip.',
          ),
          duration: const Duration(seconds: 5),
        ),
      );
    });
  }

  // Verify OTP
  void _verifyOtp() {
    if (_userLocation == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cannot start trip without your location.'),
        ),
      );
      return;
    }

    if (_otp == _generatedOtp) {
      setState(() {
        _otpVerified = true;
        _showOtpModal = false;
        _tripStarted = true;
        _driverNearby = false;
        _notificationShown = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('OTP verified successfully! Your trip has started.'),
          duration: Duration(seconds: 3),
        ),
      );

      // Fetch route from User to Destination
      if (_destinationLocation != null && _userLocation != null) {
        _fetchUserToDestinationRoute(_userLocation!, _destinationLocation!);
      } else {
        // If we don't have destination coordinates, try to geocode the destination address
        // For now, we'll just show an error
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not determine destination coordinates.'),
            duration: Duration(seconds: 3),
          ),
        );
      }

      // Animate the "Trip Started" notification
      _animateNotification();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Invalid OTP. Please try again.'),
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  // Animate notification banner
  void _animateNotification() {
    _animationController.reset();
    _animationController.forward();
  }

  // Handle call driver
  void _handleCallDriver() async {
    final phoneNumber = _driverInfo['phoneNumber'] ?? '';
    if (phoneNumber.isNotEmpty) {
      final url = 'tel:$phoneNumber';
      if (await canLaunch(url)) {
        await launch(url);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not launch phone dialer')),
        );
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Driver phone number not available')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;

    if (_isLoading && _userLocation == null) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Getting your location...', style: TextStyle(fontSize: 16)),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      body: Stack(
        children: [
          // Map View
          GoogleMap(
            initialCameraPosition: _initialCameraPosition,
            myLocationEnabled: true,
            myLocationButtonEnabled: true,
            mapType: MapType.normal,
            zoomControlsEnabled: false,
            onMapCreated: (GoogleMapController controller) {
              _mapController.complete(controller);

              // Fit map initially when user location is ready
              if (_userLocation != null &&
                  _driverLocation != null &&
                  !_otpVerified) {
                _fitMapToCoordinates([_driverLocation!, _userLocation!]);
              } else if (_userLocation != null &&
                  _destinationLocation != null &&
                  _otpVerified) {
                _fitMapToCoordinates([_userLocation!, _destinationLocation!]);
              }
            },
            markers: _buildMarkers(),
            polylines: _buildPolylines(),
          ),

          // Loading Indicator for Route Fetching
          if (_isFetchingRoute)
            Positioned(
              top: 120,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.white,
                          ),
                        ),
                      ),
                      SizedBox(width: 10),
                      Text(
                        'Calculating route...',
                        style: TextStyle(color: Colors.white, fontSize: 14),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // Location Error Message
          if (_locationError != null)
            Positioned(
              top: 120,
              left: 20,
              right: 20,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade700,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _locationError!,
                  style: const TextStyle(color: Colors.white),
                  textAlign: TextAlign.center,
                ),
              ),
            ),

          // Status Bar
          Positioned(
            top: 100,
            left: 20,
            right: 20,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
              decoration: BoxDecoration(
                color:
                    _driverNearby
                        ? Colors.blue.withOpacity(0.9)
                        : _tripStarted
                        ? Colors.green.withOpacity(0.9)
                        : Colors.black.withOpacity(0.7),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                _statusMessage,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),

          // Trip Started Notification Banner
          if (_tripStarted)
            AnimatedBuilder(
              animation: _animationController,
              builder: (context, child) {
                return Positioned(
                  bottom: _slideAnimation.value,
                  left: 20,
                  right: 20,
                  child: Opacity(
                    opacity: _fadeAnimation.value,
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.green,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: const [
                          Icon(
                            MaterialCommunityIcons.car_connected,
                            color: Colors.white,
                            size: 24,
                          ),
                          SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Trip has started! Enjoy your ride.',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),

          // Header
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              color: const Color(0xFF002B80).withOpacity(0.8),
              padding: EdgeInsets.only(
                top: MediaQuery.of(context).padding.top + 10,
                bottom: 20,
                left: 20,
                right: 20,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Icon(
                        MaterialCommunityIcons.arrow_left,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                  ),
                  const Text(
                    'Track Your Ride',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: 40), // Placeholder for symmetry
                ],
              ),
            ),
          ),

          // Trip Info Card (Bottom Sheet Style)
          Positioned(
            bottom: 20,
            left: 20,
            right: 20,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.all(15),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Driver Info
                    Row(
                      children: [
                        Container(
                          width: 50,
                          height: 50,
                          decoration: BoxDecoration(
                            color: const Color(0xFFF0F7FF),
                            borderRadius: BorderRadius.circular(25),
                          ),
                          child: const Icon(
                            MaterialCommunityIcons.account_circle,
                            size: 45,
                            color: Color(0xFF4A90E2),
                          ),
                        ),
                        const SizedBox(width: 15),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _driverInfo['name'] ?? 'Driver',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF333333),
                                ),
                              ),
                              Text(
                                '${_driverInfo['vehicleColor'] ?? 'White'} ${_driverInfo['vehicleModel'] ?? 'Car'} • ${_driverInfo['licensePlate'] ?? 'MH-XX-XXXX'}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF666666),
                                ),
                              ),
                              Row(
                                children: [
                                  const Icon(
                                    MaterialCommunityIcons.star,
                                    size: 16,
                                    color: Color(0xFFFFC107),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    (_driverInfo['rating'] ?? 4.5)
                                        .toStringAsFixed(1),
                                    style: const TextStyle(
                                      fontSize: 14,
                                      color: Color(0xFF666666),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        GestureDetector(
                          onTap: _handleCallDriver,
                          child: Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: const Color(0xFF4CAF50),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Icon(
                              MaterialCommunityIcons.phone,
                              color: Colors.white,
                              size: 22,
                            ),
                          ),
                        ),
                      ],
                    ),

                    const Divider(height: 30, color: Color(0xFFEEEEEE)),

                    // Trip Details (Pickup/Destination)
                    Column(
                      children: [
                        Row(
                          children: [
                            const Icon(
                              MaterialCommunityIcons.circle_slice_8,
                              size: 18,
                              color: Color(0xFF4A90E2),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                _pickup,
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: Color(0xFF666666),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        Container(
                          margin: const EdgeInsets.only(left: 9),
                          height: 20,
                          width: 1,
                          color: const Color(0xFFE0E0E0),
                        ),
                        Row(
                          children: [
                            const Icon(
                              MaterialCommunityIcons.map_marker,
                              size: 18,
                              color: Color(0xFF4A90E2),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                _destination,
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: Color(0xFF666666),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),

                    const SizedBox(height: 15),

                    // Trip Stats
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _buildTripStat(
                          MaterialCommunityIcons.clock_outline,
                          _duration,
                          'Est. Time',
                        ),
                        _buildTripStat(
                          MaterialCommunityIcons.map_marker_distance,
                          _distance,
                          'Distance',
                        ),
                        _buildTripStat(
                          MaterialCommunityIcons.cash,
                          _tripInfo['fare'] ?? '₹0',
                          'Fare',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),

          // OTP Modal
          if (_showOtpModal)
            Positioned.fill(
              child: GestureDetector(
                onTap: () => setState(() => _showOtpModal = false),
                child: Container(
                  color: Colors.black.withOpacity(0.5),
                  child: Center(
                    child: GestureDetector(
                      onTap: () {}, // Prevent tap through
                      child: Container(
                        width: MediaQuery.of(context).size.width * 0.85,
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              'Enter OTP',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF333333),
                              ),
                            ),
                            const SizedBox(height: 10),
                            const Text(
                              'Please enter the OTP shared with the driver to start your trip',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 14,
                                color: Color(0xFF666666),
                              ),
                            ),
                            const SizedBox(height: 20),
                            TextField(
                              keyboardType: TextInputType.number,
                              maxLength: 4,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 8,
                              ),
                              decoration: InputDecoration(
                                counterText: '',
                                hintText: '0000',
                                hintStyle: TextStyle(
                                  color: Colors.grey.shade400,
                                  fontSize: 24,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(
                                    color: Colors.grey.shade300,
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: const BorderSide(
                                    color: Color(0xFF4A90E2),
                                    width: 2,
                                  ),
                                ),
                              ),
                              onChanged: (value) {
                                setState(() => _otp = value);
                              },
                            ),
                            const SizedBox(height: 20),
                            Row(
                              children: [
                                Expanded(
                                  child: ElevatedButton(
                                    onPressed:
                                        () => setState(
                                          () => _showOtpModal = false,
                                        ),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.grey.shade200,
                                      foregroundColor: Colors.black87,
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 12,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                    ),
                                    child: const Text('Cancel'),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: ElevatedButton(
                                    onPressed: _verifyOtp,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF4A90E2),
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 12,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                    ),
                                    child: const Text('Verify'),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // Build trip stat item
  Widget _buildTripStat(IconData icon, String? value, String label) {
    return Column(
      children: [
        Icon(icon, size: 20, color: const Color(0xFF4A90E2)),
        const SizedBox(height: 5),
        Text(
          value ?? 'N/A',
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: Color(0xFF333333),
          ),
        ),
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: Color(0xFF666666)),
        ),
      ],
    );
  }

  // Build map markers
  Set<Marker> _buildMarkers() {
    final Set<Marker> markers = {};

    // Add user marker
    if (_userLocation != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('user_location'),
          position: _userLocation!,
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueAzure,
          ),
          infoWindow: const InfoWindow(title: 'Your Location'),
        ),
      );
    }

    // Add driver marker
    if (_driverLocation != null && !_otpVerified) {
      markers.add(
        Marker(
          markerId: const MarkerId('driver_location'),
          position: _driverLocation!,
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueGreen,
          ),
          infoWindow: InfoWindow(
            title: 'Driver: ${_driverInfo['name'] ?? 'Driver'}',
          ),
        ),
      );
    }

    // Add destination marker
    if (_destinationLocation != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('destination_location'),
          position: _destinationLocation!,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
          infoWindow: const InfoWindow(title: 'Destination'),
        ),
      );
    }

    return markers;
  }

  // Build map polylines
  Set<Polyline> _buildPolylines() {
    final Set<Polyline> polylines = {};

    // Add driver to pickup route
    if (_driverToPickupRoute.isNotEmpty && !_otpVerified) {
      polylines.add(
        Polyline(
          polylineId: const PolylineId('driver_to_pickup'),
          points: _driverToPickupRoute,
          color: const Color(0xFF4A90E2),
          width: 5,
        ),
      );
    }

    // Add pickup to destination route
    if (_pickupToDestinationRoute.isNotEmpty && _otpVerified) {
      polylines.add(
        Polyline(
          polylineId: const PolylineId('pickup_to_destination'),
          points: _pickupToDestinationRoute,
          color: const Color(0xFF4CAF50),
          width: 5,
        ),
      );
    }

    return polylines;
  }
}
