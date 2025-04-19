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

class DriverTrackingScreen extends StatefulWidget {
  final Map<String, dynamic> arguments;

  const DriverTrackingScreen({super.key, required this.arguments});

  @override
  State<DriverTrackingScreen> createState() => _DriverTrackingScreenState();
}

class _DriverTrackingScreenState extends State<DriverTrackingScreen>
    with SingleTickerProviderStateMixin {
  // Google Maps controller
  final Completer<GoogleMapController> _mapController = Completer();

  // Initial camera position (will be updated with driver's location)
  CameraPosition _initialCameraPosition = const CameraPosition(
    target: LatLng(18.5619, 73.9447),
    zoom: 14.0,
  );

  // Location data
  LatLng? _driverLocation;
  LatLng? _pickupLocation;
  LatLng? _destinationLocation;

  // Route data
  List<LatLng> _driverToPickupRoute = [];
  List<LatLng> _pickupToDestinationRoute = [];

  // Trip info
  String _pickup = '';
  String _destination = '';
  String _distance = '';
  String _duration = '';
  String _bookingId = '';
  Map<String, dynamic> _passengerInfo = {};
  Map<String, dynamic> _tripInfo = {};

  // State variables
  bool _isLoading = true;
  bool _isFetchingRoute = false;
  String _statusMessage = 'Heading to pickup';
  bool _arrivedAtPickup = false;
  bool _tripStarted = false;
  String? _locationError;

  // Odometer and OTP state
  bool _showOdometerModal = false;
  bool _showOtpModal = false;
  String _startOdometer = '';
  String _endOdometer = '';
  String _otp = '';
  String _generatedOtp = '';
  bool _isCompletingTrip = false;
  Map<String, dynamic>? _tripSummary;
  bool _showTripSummary = false;

  // Animation controller for notifications
  late AnimationController _animationController;
  late Animation<Offset> _offsetAnimation;

  @override
  void initState() {
    super.initState();

    // Initialize animation controller
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );

    _offsetAnimation = Tween<Offset>(
      begin: const Offset(0, -1.5),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
    );

    // Extract route parameters
    _extractRouteParams();

    // Request location permission
    _requestLocationPermission();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  // Extract route parameters
  void _extractRouteParams() {
    final args = widget.arguments;

    setState(() {
      _bookingId = args['bookingId'] ?? '';
      _pickup = args['pickup'] ?? '';
      _destination = args['destination'] ?? '';
      _passengerInfo = args['passengerInfo'] ?? {};
      _tripInfo = args['tripInfo'] ?? {};
      _distance = _tripInfo['distance'] ?? '';
      _duration = _tripInfo['estimatedTime'] ?? '';
      _statusMessage = args['currentStatus'] ?? 'Heading to pickup';

      // Set pickup and destination locations
      if (args['pickupLocation'] != null) {
        _pickupLocation = LatLng(
          args['pickupLocation']['latitude'] ?? 21.1458,
          args['pickupLocation']['longitude'] ?? 79.0882,
        );
      } else {
        _pickupLocation = const LatLng(21.1458, 79.0882); // Default
      }

      if (args['destinationLocation'] != null) {
        _destinationLocation = LatLng(
          args['destinationLocation']['latitude'] ?? 18.5284,
          args['destinationLocation']['longitude'] ?? 73.8739,
        );
      } else {
        _destinationLocation = const LatLng(18.5284, 73.8739); // Default
      }
    });
  }

  // Request location permission
  Future<void> _requestLocationPermission() async {
    final status = await permission.Permission.location.request();

    if (status.isGranted) {
      _getCurrentLocation();
    } else {
      setState(() {
        _locationError =
            'Location permission denied. Please enable it in app settings.';
        _isLoading = false;
      });
    }
  }

  // Get current location
  Future<void> _getCurrentLocation() async {
    final location = Location();

    try {
      final currentLocation = await location.getLocation();
      final latLng = LatLng(
        currentLocation.latitude!,
        currentLocation.longitude!,
      );

      setState(() {
        _driverLocation = latLng;
        _initialCameraPosition = CameraPosition(target: latLng, zoom: 14.0);
        _isLoading = false;
      });

      // Start location updates
      _startLocationUpdates();

      // Fetch route to pickup
      _fetchRoute(_driverLocation!, _pickupLocation!, true);

      // Also fetch route from pickup to destination for display
      _fetchRoute(_pickupLocation!, _destinationLocation!, false);
    } catch (e) {
      setState(() {
        _locationError = 'Could not get current location: $e';
        _isLoading = false;
      });
    }
  }

  // Start location updates
  void _startLocationUpdates() {
    final location = Location();

    location.onLocationChanged.listen((locationData) {
      if (locationData.latitude != null && locationData.longitude != null) {
        final newLocation = LatLng(
          locationData.latitude!,
          locationData.longitude!,
        );

        setState(() {
          _driverLocation = newLocation;
        });

        // Update route if needed
        if (_driverLocation != null) {
          if (!_tripStarted && _pickupLocation != null) {
            _fetchRoute(_driverLocation!, _pickupLocation!, true);
          } else if (_tripStarted && _destinationLocation != null) {
            _fetchRoute(_driverLocation!, _destinationLocation!, false);
          }
        }
      }
    });
  }

  // Fetch route between two points
  Future<void> _fetchRoute(
    LatLng origin,
    LatLng destination,
    bool isToPickup,
  ) async {
    setState(() {
      _isFetchingRoute = true;
    });

    try {
      final originStr = '${origin.latitude},${origin.longitude}';
      final destinationStr = '${destination.latitude},${destination.longitude}';
      final url =
          'https://maps.googleapis.com/maps/api/directions/json?origin=$originStr&destination=$destinationStr&key=AIzaSyCelDo4I5cPQ72TfCTQW-arhPZ7ALNcp8w&mode=driving';

      final response = await http.get(Uri.parse(url));
      final result = json.decode(response.body);

      if (result['status'] == 'OK' && result['routes'].isNotEmpty) {
        final route = result['routes'][0];

        // Update trip info if needed
        if (route['legs'] != null && route['legs'].isNotEmpty) {
          final leg = route['legs'][0];
          if (leg['distance'] != null && leg['duration'] != null) {
            setState(() {
              _distance = leg['distance']['text'];
              _duration = leg['duration']['text'];
            });
          }
        }

        // Decode and set the polyline coordinates
        final points = route['overview_polyline']['points'];
        final decodedCoords = _decodePolyline(points);

        setState(() {
          if (isToPickup) {
            _driverToPickupRoute = decodedCoords;
          } else {
            _pickupToDestinationRoute = decodedCoords;
          }
        });
      } else {
        print('No routes found: ${result['status']}');
        // Fallback to straight line if no route is found
        setState(() {
          if (isToPickup) {
            _driverToPickupRoute = [origin, destination];
          } else {
            _pickupToDestinationRoute = [origin, destination];
          }
        });
      }
    } catch (e) {
      print('Error fetching route: $e');
      // Fallback to straight line on error
      setState(() {
        if (isToPickup) {
          _driverToPickupRoute = [origin, destination];
        } else {
          _pickupToDestinationRoute = [origin, destination];
        }
      });
    } finally {
      setState(() {
        _isFetchingRoute = false;
      });
    }
  }

  // Decode Google's polyline algorithm
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

      final point = LatLng(lat / 1e5, lng / 1e5);
      poly.add(point);
    }

    return poly;
  }

  // Fit map to show all coordinates
  Future<void> _fitMapToCoordinates(List<LatLng> coordinates) async {
    if (coordinates.isEmpty) return;

    final controller = await _mapController.future;

    double minLat = coordinates[0].latitude;
    double maxLat = coordinates[0].latitude;
    double minLng = coordinates[0].longitude;
    double maxLng = coordinates[0].longitude;

    for (final coord in coordinates) {
      if (coord.latitude < minLat) minLat = coord.latitude;
      if (coord.latitude > maxLat) maxLat = coord.latitude;
      if (coord.longitude < minLng) minLng = coord.longitude;
      if (coord.longitude > maxLng) maxLng = coord.longitude;
    }

    final bounds = LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );

    await controller.animateCamera(CameraUpdate.newLatLngBounds(bounds, 50.0));
  }

  // Handle call passenger
  Future<void> _handleCallPassenger() async {
    final phoneNumber = _passengerInfo['phoneNumber'] ?? '';
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
        const SnackBar(content: Text('Passenger phone number not available')),
      );
    }
  }

  // Handle arrived at pickup
  void _handleArrivedAtPickup() {
    setState(() {
      _arrivedAtPickup = true;
      _statusMessage = "Arrived at pickup location";
    });

    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Arrived at Pickup'),
            content: const Text('Please wait for the passenger to arrive.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          ),
    );
  }

  // Generate OTP
  String _generateOtp() {
    final newOtp = (1000 + Random().nextInt(9000)).toString();
    setState(() {
      _generatedOtp = newOtp;
    });
    return newOtp;
  }

  // Handle start trip
  void _handleStartTrip() {
    setState(() {
      _showOdometerModal = true;
      _isCompletingTrip = false;
    });
  }

  // Handle complete trip
  void _handleCompleteTrip() {
    setState(() {
      _showOdometerModal = true;
      _isCompletingTrip = true;
    });
  }

  // Handle odometer submit
  void _handleOdometerSubmit() {
    if (_isCompletingTrip) {
      if (_endOdometer.isEmpty || _endOdometer.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enter the odometer reading')),
        );
        return;
      }

      // Validate that end odometer is greater than start odometer
      if (int.parse(_endOdometer) <= int.parse(_startOdometer)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'End odometer reading must be greater than start reading',
            ),
          ),
        );
        return;
      }

      setState(() {
        _showOdometerModal = false;
      });

      final newOtp = _generateOtp();
      setState(() {
        _showOtpModal = true;
      });

      // In a real app, you would send this OTP to the passenger
      showDialog(
        context: context,
        builder:
            (context) => AlertDialog(
              title: const Text('OTP Generated'),
              content: Text(
                'OTP $newOtp has been sent to the passenger for verification.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('OK'),
                ),
              ],
            ),
      );
    } else {
      if (_startOdometer.isEmpty || _startOdometer.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enter the odometer reading')),
        );
        return;
      }

      setState(() {
        _showOdometerModal = false;
      });

      final newOtp = _generateOtp();
      setState(() {
        _showOtpModal = true;
      });

      // In a real app, you would send this OTP to the passenger
      showDialog(
        context: context,
        builder:
            (context) => AlertDialog(
              title: const Text('OTP Generated'),
              content: Text(
                'OTP $newOtp has been sent to the passenger for verification.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('OK'),
                ),
              ],
            ),
      );
    }
  }

  // Handle OTP verification
  void _handleOtpVerify() {
    if (_otp == _generatedOtp) {
      setState(() {
        _showOtpModal = false;
        _otp = '';
      });

      if (_isCompletingTrip) {
        // Calculate trip summary
        final distanceTraveled =
            (int.parse(_endOdometer) - int.parse(_startOdometer)).toString();
        final estimatedFare =
            (int.parse(distanceTraveled) * 10).toString(); // Simple calculation

        setState(() {
          _tripSummary = {
            'startOdometer': _startOdometer,
            'endOdometer': _endOdometer,
            'distanceTraveled': '$distanceTraveled km',
            'fare': '₹$estimatedFare',
          };
          _showTripSummary = true;
        });
      } else {
        // Start the trip
        setState(() {
          _tripStarted = true;
          _statusMessage = "Trip started";
        });

        // Fetch route to destination
        if (_driverLocation != null && _destinationLocation != null) {
          _fetchRoute(_driverLocation!, _destinationLocation!, false);
        }
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invalid OTP. Please try again.')),
      );
    }
  }

  // Handle trip summary confirmation
  void _handleTripSummaryConfirm() {
    setState(() {
      _showTripSummary = false;
    });

    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Trip Completed'),
            content: const Text('Trip has been successfully completed.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('OK'),
              ),
            ],
          ),
    ).then((value) {
      if (value == true) {
        Navigator.pop(context);
      }
    });
  }

  // Handle cancel trip
  void _handleCancelTrip() {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Cancel Trip'),
            content: const Text(
              'Are you sure you want to cancel this trip? This may affect your ratings.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('No'),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  showDialog(
                    context: context,
                    builder:
                        (context) => AlertDialog(
                          title: const Text('Trip Cancelled'),
                          content: const Text('Trip has been cancelled.'),
                          actions: [
                            TextButton(
                              onPressed: () {
                                Navigator.pop(context);
                                Navigator.pop(context);
                              },
                              child: const Text('OK'),
                            ),
                          ],
                        ),
                  );
                },
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: const Text('Yes, Cancel'),
              ),
            ],
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              CircularProgressIndicator(color: Color(0xFF4A90E2)),
              SizedBox(height: 16),
              Text('Loading map...', style: TextStyle(fontSize: 16)),
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

              // Fit map initially when driver location is ready
              if (_driverLocation != null &&
                  _pickupLocation != null &&
                  !_tripStarted) {
                _fitMapToCoordinates([_driverLocation!, _pickupLocation!]);
              } else if (_driverLocation != null &&
                  _destinationLocation != null &&
                  _tripStarted) {
                _fitMapToCoordinates([_driverLocation!, _destinationLocation!]);
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
                  color: Colors.red.shade100,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade300),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline, color: Colors.red.shade700),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _locationError!,
                        style: TextStyle(color: Colors.red.shade700),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // Status Bar
          Positioned(
            top: MediaQuery.of(context).padding.top + 60,
            left: 20,
            right: 20,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.7),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                _statusMessage,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),

          // Header
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              color: const Color(0xFF002B80),
              padding: EdgeInsets.only(
                top: MediaQuery.of(context).padding.top,
                bottom: 15,
                left: 20,
                right: 20,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(
                      MaterialCommunityIcons.arrow_left,
                      color: Colors.white,
                      size: 24,
                    ),
                    onPressed: () => Navigator.pop(context),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                  const Text(
                    'Trip Navigation',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 24), // Placeholder for balance
                ],
              ),
            ),
          ),

          // Trip Info Card
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 10,
                    offset: Offset(0, -2),
                  ),
                ],
              ),
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Passenger Info Section
                  Row(
                    children: [
                      Container(
                        width: 50,
                        height: 50,
                        decoration: const BoxDecoration(
                          color: Color(0xFFF0F7FF),
                          shape: BoxShape.circle,
                        ),
                        child: const Center(
                          child: Icon(
                            MaterialCommunityIcons.account,
                            size: 40,
                            color: Color(0xFF4A90E2),
                          ),
                        ),
                      ),
                      const SizedBox(width: 15),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _passengerInfo['name'] ?? 'Passenger',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF333333),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                const Icon(
                                  MaterialCommunityIcons.star,
                                  size: 16,
                                  color: Color(0xFFFFD700),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  _passengerInfo['rating']?.toString() ?? '4.5',
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
                        onTap: _handleCallPassenger,
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: const BoxDecoration(
                            color: Color(0xFF4A90E2),
                            shape: BoxShape.circle,
                          ),
                          child: const Center(
                            child: Icon(
                              MaterialCommunityIcons.phone,
                              color: Colors.white,
                              size: 22,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 15),
                  const Divider(height: 1, color: Color(0xFFE0E0E0)),
                  const SizedBox(height: 15),

                  // Trip Details
                  Column(
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 12,
                            height: 12,
                            decoration: const BoxDecoration(
                              color: Color(0xFF4A90E2),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _pickup,
                              style: const TextStyle(
                                fontSize: 15,
                                color: Color(0xFF333333),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      Container(
                        margin: const EdgeInsets.only(left: 6),
                        height: 25,
                        width: 1,
                        color: const Color(0xFFE0E0E0),
                      ),
                      Row(
                        children: [
                          Container(
                            width: 12,
                            height: 12,
                            decoration: const BoxDecoration(
                              color: Color(0xFFFF6B6B),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _destination,
                              style: const TextStyle(
                                fontSize: 15,
                                color: Color(0xFF333333),
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
                  const Divider(height: 1, color: Color(0xFFE0E0E0)),
                  const SizedBox(height: 15),

                  // Trip Stats
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildTripStat('Distance', _distance),
                      _buildTripStat('ETA', _duration),
                      _buildTripStat('Fare', _tripInfo['fare'] ?? '₹0'),
                    ],
                  ),

                  const SizedBox(height: 15),

                  // Payment Method
                  Row(
                    children: [
                      const Icon(
                        MaterialCommunityIcons.credit_card_outline,
                        size: 18,
                        color: Color(0xFF666666),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _tripInfo['paymentMethod'] ?? 'Cash',
                        style: const TextStyle(
                          fontSize: 14,
                          color: Color(0xFF666666),
                        ),
                      ),
                      const SizedBox(width: 15),
                      Text(
                        'Booking ID: $_bookingId',
                        style: const TextStyle(
                          fontSize: 14,
                          color: Color(0xFF666666),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // Action Buttons
                  Row(
                    children: [
                      if (!_arrivedAtPickup && !_tripStarted)
                        Expanded(
                          child: ElevatedButton(
                            onPressed: _handleArrivedAtPickup,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF4A90E2),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            child: const Text('Arrived at Pickup'),
                          ),
                        ),
                      if (_arrivedAtPickup && !_tripStarted)
                        Expanded(
                          child: ElevatedButton(
                            onPressed: _handleStartTrip,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF4A90E2),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            child: const Text('Start Trip'),
                          ),
                        ),
                      if (_tripStarted)
                        Expanded(
                          child: ElevatedButton(
                            onPressed: _handleCompleteTrip,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF4A90E2),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            child: const Text('Complete Trip'),
                          ),
                        ),
                      const SizedBox(width: 10),
                      ElevatedButton(
                        onPressed: _handleCancelTrip,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.red,
                          padding: const EdgeInsets.symmetric(
                            vertical: 12,
                            horizontal: 20,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                            side: const BorderSide(color: Colors.red),
                          ),
                        ),
                        child: const Text('Cancel'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Trip Started Notification
          SlideTransition(
            position: _offsetAnimation,
            child: Visibility(
              visible: _tripStarted,
              child: Positioned(
                top: MediaQuery.of(context).padding.top + 10,
                left: 20,
                right: 20,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF4CAF50),
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    children: const [
                      Icon(
                        MaterialCommunityIcons.check_circle,
                        color: Colors.white,
                        size: 24,
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Trip Started',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Odometer Modal
          if (_showOdometerModal)
            Positioned.fill(
              child: Container(
                color: Colors.black.withOpacity(0.5),
                child: Center(
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
                        Text(
                          _isCompletingTrip
                              ? 'End Odometer Reading'
                              : 'Start Odometer Reading',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF333333),
                          ),
                        ),
                        const SizedBox(height: 20),
                        if (!_isCompletingTrip)
                          TextField(
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Enter odometer reading (km)',
                              border: OutlineInputBorder(),
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 16,
                              ),
                            ),
                            onChanged: (value) {
                              setState(() {
                                _startOdometer = value;
                              });
                            },
                          ),
                        if (_isCompletingTrip) ...[
                          TextField(
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: 'Start odometer reading (km)',
                              border: const OutlineInputBorder(),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 16,
                              ),
                              enabled: false,
                              hintText: _startOdometer,
                            ),
                          ),
                          const SizedBox(height: 15),
                          TextField(
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Enter end odometer reading (km)',
                              border: OutlineInputBorder(),
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 16,
                              ),
                            ),
                            onChanged: (value) {
                              setState(() {
                                _endOdometer = value;
                              });
                            },
                          ),
                        ],
                        const SizedBox(height: 20),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton(
                              onPressed: () {
                                setState(() {
                                  _showOdometerModal = false;
                                });
                              },
                              child: const Text('Cancel'),
                            ),
                            const SizedBox(width: 10),
                            ElevatedButton(
                              onPressed: _handleOdometerSubmit,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF4A90E2),
                              ),
                              child: const Text('Submit'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

          // OTP Modal
          if (_showOtpModal)
            Positioned.fill(
              child: Container(
                color: Colors.black.withOpacity(0.5),
                child: Center(
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
                        Text(
                          _isCompletingTrip
                              ? 'Verify End Trip OTP'
                              : 'Verify Start Trip OTP',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF333333),
                          ),
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'Ask the passenger for the OTP sent to their phone',
                          style: TextStyle(
                            fontSize: 14,
                            color: Color(0xFF666666),
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 20),
                        TextField(
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Enter 4-digit OTP',
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 16,
                            ),
                          ),
                          onChanged: (value) {
                            setState(() {
                              _otp = value;
                            });
                          },
                        ),
                        const SizedBox(height: 20),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton(
                              onPressed: () {
                                setState(() {
                                  _showOtpModal = false;
                                });
                              },
                              child: const Text('Cancel'),
                            ),
                            const SizedBox(width: 10),
                            ElevatedButton(
                              onPressed: _handleOtpVerify,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF4A90E2),
                              ),
                              child: const Text('Verify'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

          // Trip Summary Modal
          if (_showTripSummary && _tripSummary != null)
            Positioned.fill(
              child: Container(
                color: Colors.black.withOpacity(0.5),
                child: Center(
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
                          'Trip Summary',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF333333),
                          ),
                        ),
                        const SizedBox(height: 20),
                        _buildSummaryItem(
                          'Start Odometer',
                          _tripSummary!['startOdometer'] + ' km',
                        ),
                        _buildSummaryItem(
                          'End Odometer',
                          _tripSummary!['endOdometer'] + ' km',
                        ),
                        _buildSummaryItem(
                          'Distance Traveled',
                          _tripSummary!['distanceTraveled'],
                        ),
                        const Divider(height: 30),
                        _buildSummaryItem(
                          'Total Fare',
                          _tripSummary!['fare'],
                          isTotal: true,
                        ),
                        const SizedBox(height: 20),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _handleTripSummaryConfirm,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF4A90E2),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            child: const Text('Confirm'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // Build trip stat widget
  Widget _buildTripStat(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: Color(0xFF999999)),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Color(0xFF333333),
          ),
        ),
      ],
    );
  }

  // Build summary item widget
  Widget _buildSummaryItem(String label, String value, {bool isTotal = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: isTotal ? 16 : 14,
              fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
              color: const Color(0xFF666666),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: isTotal ? 18 : 14,
              fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
              color:
                  isTotal ? const Color(0xFF4A90E2) : const Color(0xFF333333),
            ),
          ),
        ],
      ),
    );
  }

  // Build map markers
  Set<Marker> _buildMarkers() {
    final Set<Marker> markers = {};

    // Add driver marker
    if (_driverLocation != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('driver'),
          position: _driverLocation!,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
          infoWindow: const InfoWindow(title: 'Your Location'),
        ),
      );
    }

    // Add pickup marker
    if (_pickupLocation != null && !_tripStarted) {
      markers.add(
        Marker(
          markerId: const MarkerId('pickup'),
          position: _pickupLocation!,
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueGreen,
          ),
          infoWindow: InfoWindow(title: 'Pickup: $_pickup'),
        ),
      );
    }

    // Add destination marker
    if (_destinationLocation != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('destination'),
          position: _destinationLocation!,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
          infoWindow: InfoWindow(title: 'Destination: $_destination'),
        ),
      );
    }

    return markers;
  }

  // Build map polylines
  Set<Polyline> _buildPolylines() {
    final Set<Polyline> polylines = {};

    // Add driver to pickup route
    if (_driverToPickupRoute.isNotEmpty && !_tripStarted) {
      polylines.add(
        Polyline(
          polylineId: const PolylineId('driverToPickup'),
          points: _driverToPickupRoute,
          color: const Color(0xFF4A90E2),
          width: 5,
        ),
      );
    }

    // Add pickup to destination route
    if (_pickupToDestinationRoute.isNotEmpty) {
      polylines.add(
        Polyline(
          polylineId: const PolylineId('pickupToDestination'),
          points: _pickupToDestinationRoute,
          color:
              _tripStarted ? const Color(0xFF4A90E2) : const Color(0xFFAAAAAA),
          width: _tripStarted ? 5 : 3,
        ),
      );
    }

    return polylines;
  }
}
