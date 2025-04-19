import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_vector_icons/flutter_vector_icons.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:worldtriplink/screens/tracking_screen.dart';

// Professional color palette - matching login screen
const Color primaryColor = Color(0xFF2E3192);      // Deep blue
const Color secondaryColor = Color(0xFF4A90E2);    // Bright blue
const Color accentColor = Color(0xFFFFCC00);       // Yellow/gold accent

// Background colors
const Color backgroundColor = Color(0xFFF5F7FA);   // Light gray background
const Color cardColor = Colors.white;              // White card background
const Color surfaceColor = Color(0xFFF0F7FF);      // Light blue surface color

// Text colors
const Color textColor = Color(0xFF333333);         // Dark text
const Color lightTextColor = Color(0xFF666666);    // Medium gray text
const Color mutedTextColor = Color(0xFFA0A0A0);    // Light gray text

// Status colors
const Color successColor = Color(0xFF4CAF50);      // Green for success states
const Color warningColor = Color(0xFFFF9800);      // Orange for warning states
const Color dangerColor = Color(0xFFF44336);       // Red for error/danger states

// Accent shade
const Color lightAccentColor = Color(0xFFF0F7FF);  // Light blue for subtle highlights

class Trip {
  final String bookingId;
  final String fromLocation;
  final String toLocation;
  final String startDate;
  final String time;
  final String car;
  final double amount;
  final int status;
  final String name;
  final String phone;
  final double? distance;
  final Map<String, dynamic>? vendorDriver;
  final Map<String, dynamic>? vendorCab;
  final Map<String, dynamic>? carRentalUser;
  final String tripType;

  Trip({
    required this.bookingId,
    required this.fromLocation,
    required this.toLocation,
    required this.startDate,
    required this.time,
    required this.car,
    required this.amount,
    required this.status,
    required this.name,
    required this.phone,
    this.distance,
    this.vendorDriver,
    this.vendorCab,
    this.carRentalUser,
    this.tripType = 'oneWay',
  });

  factory Trip.fromJson(Map<String, dynamic> json) {
    return Trip(
      bookingId: json['bookingId'] ?? json['bookid'] ?? 'N/A',
      fromLocation:
          json['fromLocation'] ?? json['userPickup'] ?? 'Unknown location',
      toLocation: json['toLocation'] ?? json['userDrop'] ?? 'Unknown location',
      startDate: json['startDate'] ?? json['date'] ?? 'N/A',
      time: json['time'] ?? 'N/A',
      car: (json['car'] ?? json['vendorCab']?['carName'] ?? 'cab').toString(),
      amount:
          json['amount'] is num
              ? (json['amount'] as num).toDouble()
              : double.tryParse(json['amount']?.toString() ?? '') ?? 0.0,
      status:
          json['status'] is String
              ? int.tryParse(json['status']) ?? 0
              : json['status'] as int? ?? 0,
      name: json['name'] ?? json['vendorDriver']?['driverName'] ?? 'Unknown',
      phone: json['phone'] ?? json['vendorDriver']?['contactNo'] ?? 'N/A',
      distance:
          json['distance'] is num
              ? (json['distance'] as num).toDouble()
              : double.tryParse(json['distance']?.toString() ?? '') ?? 0.0,
      vendorDriver: json['vendorDriver'] as Map<String, dynamic>?,
      vendorCab: json['vendorCab'] as Map<String, dynamic>?,
      carRentalUser: json['carRentalUser'] as Map<String, dynamic>?,
      tripType: json['tripType'] ?? json['userTripType'] ?? 'oneWay',
    );
  }

  @override
  String toString() {
    return 'Trip{bookingId: $bookingId, from: $fromLocation, to: $toLocation, date: $startDate, status: $status}';
  }
}

class TripsScreen extends StatefulWidget {
  const TripsScreen({super.key});

  @override
  State<TripsScreen> createState() => _TripsScreenState();
}

class _TripsScreenState extends State<TripsScreen> {
  int _activeTab = 0;
  String _userId = '';
  List<Trip> _trips = [];
  bool _isLoading = true;
  Map<String, dynamic>? _userData;

  @override
  void initState() {
    super.initState();
    _loadUserData();
    // Add sample trip data for testing
    // _addSampleTrip();
  }

  void _addSampleTrip() {
    _trips.add(
      Trip(
        bookingId: 'WTL123456',
        fromLocation: 'Mumbai Airport, Terminal 2',
        toLocation: 'Taj Hotel, Colaba, Mumbai',
        startDate: '2023-11-15',
        time: '14:30',
        car: 'Toyota Innova',
        amount: 1500.0,
        status: 0, // Upcoming
        name: 'Rahul Sharma',
        phone: '+91 9876543210',
        distance: 25.5,
        vendorDriver: {
          'driverName': 'Rahul Sharma',
          'contactNo': '+91 9876543210',
          'altContactNo': '+91 9876543211',
          'rating': 4.8,
          'totalTrips': 256,
        },
        vendorCab: {
          'carName': 'Toyota Innova',
          'vehicleNo': 'MH 01 AB 1234',
          'carType': 'SUV',
          'carColor': 'White',
        },
        tripType: 'oneWay',
      ),
    );
  }

  Future<void> _loadUserData() async {
    final prefs = await SharedPreferences.getInstance();
    final userDataString = prefs.getString('userData');

    setState(() {
      _userId =
          prefs.getInt('userId')?.toString() ?? prefs.getString('userId') ?? '';
      if (userDataString != null) {
        try {
          _userData = json.decode(userDataString);
        } catch (e) {}
      }
    });

    _getUserTripInfo();
  }

  Future<void> _getUserTripInfo() async {
    try {
      print('Fetching trips for user: $_userId');
      final response = await http.get(
        Uri.parse('https://api.worldtriplink.com/api/by-user/$_userId'),
      );

      print('API Response: ${response.statusCode}');
      print('Response Body: ${response.body}');

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        List<dynamic> tripsData;

        if (responseData is List) {
          tripsData = responseData;
        } else if (responseData is Map &&
            responseData.containsKey('data') &&
            responseData['data'] is List) {
          tripsData = responseData['data'];
        } else {
          tripsData = [responseData];
        }

        print('Decoded JSON: ${tripsData.runtimeType}');

        final List<Trip> loadedTrips =
            tripsData.map((tripJson) {
              print(
                'Processing trip: ${tripJson['bookingId'] ?? tripJson['bookid']}',
              );
              return Trip.fromJson(tripJson);
            }).toList();

        print('Successfully loaded ${loadedTrips.length} trips');
        setState(() {
          _trips = loadedTrips;
          _isLoading = false;
        });
      } else {
        print('API Error: ${response.statusCode}');
        setState(() => _isLoading = false);
      }
    } catch (error) {
      print('Error fetching trips: $error');
      setState(() => _isLoading = false);
    }
  }

  List<Trip> _filterTrips() {
    return _trips.where((trip) {
      switch (_activeTab) {
        case 0: // Upcoming
          return trip.status == 0;
        case 1: // Completed
          return trip.status == 2;
        case 2: // Cancelled
          return trip.status == 3;
        default:
          return false;
      }
    }).toList();
  }

  // Attempt to extract coordinates from a location string (simplified approach)
  Map<String, double> _extractCoordinatesFromAddress(String address) {
    // This is a very basic implementation that looks for coordinates in the address string
    // In a real app, you would use the Geocoding API to convert addresses to coordinates
    
    // Default coordinates (Mumbai)
    double latitude = 19.0760;
    double longitude = 72.8777;
    
    // Example: if location contains "Pune", use Pune coordinates
    if (address.toLowerCase().contains('pune')) {
      latitude = 18.5204;
      longitude = 73.8567;
    } 
    // Example: if location contains "Mumbai", use Mumbai coordinates
    else if (address.toLowerCase().contains('mumbai')) {
      latitude = 19.0760;
      longitude = 72.8777;
    }
    // Example: if location contains "Delhi", use Delhi coordinates
    else if (address.toLowerCase().contains('delhi')) {
      latitude = 28.6139;
      longitude = 77.2090;
    }
    // Example: if location contains "Bangalore", use Bangalore coordinates
    else if (address.toLowerCase().contains('bangalore') || address.toLowerCase().contains('bengaluru')) {
      latitude = 12.9716;
      longitude = 77.5946;
    }
    
    return {
      'latitude': latitude,
      'longitude': longitude
    };
  }

  void _handleTrackPress(Trip trip) {
    try {
      // Extract user and driver location coordinates
      final double userLatitude = trip.carRentalUser?['userlatitude']?.toDouble() ?? 0.0;
      final double userLongitude = trip.carRentalUser?['userlongitude']?.toDouble() ?? 0.0;
      
      final double driverLatitude = trip.vendorDriver?['driverLatitude']?.toDouble() ?? 0.0;
      final double driverLongitude = trip.vendorDriver?['driverLongitude']?.toDouble() ?? 0.0;
      
      // If user coordinates not available, try to geocode from pickup address
      Map<String, double> pickupCoords = {
        'latitude': userLatitude,
        'longitude': userLongitude
      };
      
      if (userLatitude == 0.0 || userLongitude == 0.0) {
        pickupCoords = _extractCoordinatesFromAddress(trip.fromLocation);
      }
      
      // If destination coordinates not available, try to geocode from destination address
      Map<String, double> destCoords = _extractCoordinatesFromAddress(trip.toLocation);
      
      // Prepare booking data with null checks and default values
      final Map<String, dynamic> bookingData = {
        'bookingId': trip.bookingId,
        'pickup': trip.fromLocation,
        'destination': trip.toLocation,
        'tripType': trip.tripType,
        'driverInfo': {
          'name': trip.vendorDriver?['driverName'] ?? trip.name ?? 'Driver',
          'rating': trip.vendorDriver?['rating'] ?? 4.5,
          'vehicleModel': trip.vendorCab?['carName'] ?? trip.car ?? 'Vehicle',
          'vehicleColor': trip.vendorCab?['carColor'] ?? 'White',
          'licensePlate':
              trip.vendorCab?['vehicleNo'] ??
              trip.vendorCab?['rCNo'] ??
              'Not Available',
          'phoneNumber':
              trip.vendorDriver?['contactNo'] ??
              trip.vendorDriver?['altContactNo'] ??
              trip.phone ??
              'Not Available',
        },
        'tripInfo': {
          'estimatedTime': '30 mins',
          'distance':
              trip.distance != null ? '${trip.distance} km' : 'Calculating...',
          'fare': '₹${trip.amount.toStringAsFixed(2)}',
          'paymentMethod': 'Cash',
          'status': trip.status,
        },
        'currentStatus': _getTripStatus(trip.status),
        'vendorDriver': trip.vendorDriver ?? {},
        'vendorCab': trip.vendorCab ?? {},
        'carRentalUser': trip.carRentalUser ?? {},
        // Add coordinates for map
        'pickupLocation': {
          'latitude': pickupCoords['latitude'],
          'longitude': pickupCoords['longitude']
        },
        'destinationLocation': {
          'latitude': destCoords['latitude'],
          'longitude': destCoords['longitude']
        },
        'driverLocation': {
          'latitude': driverLatitude,
          'longitude': driverLongitude
        },
        'userLocation': {
          'latitude': pickupCoords['latitude'],
          'longitude': pickupCoords['longitude']
        },
      };

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => TrackingScreen(bookingData: bookingData),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error loading tracking screen: ${e.toString()}'),
          backgroundColor: dangerColor,
        ),
      );
    }
  }

  String _getTripStatus(int status) {
    switch (status) {
      case 0:
        return 'Driver Assigned';
      case 1:
        return 'On the way';
      case 2:
        return 'Completed';
      case 3:
        return 'Cancelled';
      default:
        return 'Pending';
    }
  }

  void _handleModifyPress(Trip trip) {
    // Implement modify functionality
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Modify functionality coming soon')),
    );
  }

  void _handleCancelPress(Trip trip) {
    // Implement cancel functionality
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Cancel functionality coming soon')),
    );
  }

  void _handleInvoicePress(Trip trip) {
    // Implement invoice functionality
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Invoice functionality coming soon')),
    );
  }

  void _handleRatePress(Trip trip) {
    // Implement rate functionality
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Rate functionality coming soon')),
    );
  }

  void _handleRebookPress(Trip trip) {
    // Implement rebook functionality
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Rebook functionality coming soon')),
    );
  }

  void _handleDetailsPress(Trip trip) {
    // Implement details functionality
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Details functionality coming soon')),
    );
  }

  void _handleSupportPress(Trip trip) {
    // Implement support functionality
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Support functionality coming soon')),
    );
  }

  Widget _buildStatusContainer(String status, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        status,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildActionButton(
    IconData icon,
    String text,
    Color color,
    VoidCallback onPressed,
  ) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: surfaceColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: secondaryColor.withOpacity(0.3), width: 1),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: secondaryColor),
            const SizedBox(width: 5),
            Text(
              text,
              style: TextStyle(
                fontSize: 14,
                color: secondaryColor,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filteredTrips = _filterTrips();

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        title: const Text(
          'My Trips',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
        backgroundColor: primaryColor,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFF5F7FA), Colors.white],
          ),
        ),
        child: Column(
          children: [
            Container(
              decoration: BoxDecoration(
                color: cardColor,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    offset: const Offset(0, 2),
                    blurRadius: 4,
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _buildTabButton('Upcoming', 0),
                    _buildTabButton('Completed', 1),
                    _buildTabButton('Cancelled', 2),
                  ],
                ),
              ),
            ),
            Expanded(
              child:
                  _isLoading
                      ? Center(
                        child: CircularProgressIndicator(color: accentColor),
                      )
                      : filteredTrips.isEmpty
                      ? _buildNoTrips()
                      : RefreshIndicator(
                        color: accentColor,
                        onRefresh: _getUserTripInfo,
                        child: ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: filteredTrips.length,
                          itemBuilder: (ctx, index) {
                            final trip = filteredTrips[index];
                            return _buildTripCard(trip);
                          },
                        ),
                      ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabButton(String text, int index) {
    final isActive = _activeTab == index;
    return GestureDetector(
      onTap: () => setState(() => _activeTab = index),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: isActive ? accentColor : Colors.transparent,
              width: 3,
            ),
          ),
        ),
        child: Text(
          text,
          style: TextStyle(
            color: isActive ? primaryColor : lightTextColor,
            fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
            fontSize: 15,
          ),
        ),
      ),
    );
  }

  Widget _buildNoTrips() {
    final tabNames = ['Upcoming', 'Completed', 'Cancelled'];
    final tabIcons = [
      MaterialCommunityIcons.calendar_clock,
      MaterialCommunityIcons.check_circle_outline,
      MaterialCommunityIcons.close_circle_outline,
    ];
    final tabColors = [warningColor, successColor, dangerColor];

    return Center(
      child: Container(
        width: MediaQuery.of(context).size.width * 0.9,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              tabIcons[_activeTab],
              size: 70,
              color: tabColors[_activeTab].withOpacity(0.5),
            ),
            const SizedBox(height: 20),
            Text(
              'No ${tabNames[_activeTab]} Trips',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: primaryColor,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              _activeTab == 0
                  ? 'Book a trip to see it here'
                  : 'Your ${tabNames[_activeTab].toLowerCase()} trips will appear here',
              style: const TextStyle(fontSize: 14, color: lightTextColor),
            ),
            const SizedBox(height: 30),
            if (_activeTab == 0)
              ElevatedButton(
                onPressed: () {
                  // Navigate to booking screen
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: accentColor,
                  foregroundColor: textColor,
                  minimumSize: const Size(double.infinity, 50),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text(
                  'Book a Trip',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTripCard(Trip trip) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // Header with trip type and status
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: surfaceColor,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(_getTripIcon(trip.car), size: 18, color: primaryColor),
                    const SizedBox(width: 8),
                    Text(
                      trip.car.isNotEmpty ? trip.car : 'Cab Booking',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: primaryColor,
                      ),
                    ),
                  ],
                ),
                _buildStatusContainer(
                  trip.status == 0
                      ? 'Confirmed'
                      : trip.status == 2
                      ? 'Completed'
                      : 'Cancelled',
                  _getStatusColor(trip.status),
                ),
              ],
            ),
          ),

          // Trip details
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Booking ID
                Row(
                  children: [
                    const Text(
                      'Booking ID: ',
                      style: TextStyle(fontSize: 12, color: lightTextColor),
                    ),
                    Text(
                      trip.bookingId,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: textColor,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Route information with improved design
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: surfaceColor,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: const Color(0xFFE0E0E0),
                      width: 1,
                    ),
                  ),
                  child: Column(
                    children: [
                      _buildLocationRow(
                        Icons.location_on_outlined,
                        'From',
                        trip.fromLocation,
                        secondaryColor,
                      ),
                      Padding(
                        padding: const EdgeInsets.only(left: 9),
                        child: Container(
                          height: 30,
                          width: 1,
                          color: secondaryColor.withOpacity(0.3),
                        ),
                      ),
                      _buildLocationRow(
                        Icons.location_on,
                        'To',
                        trip.toLocation,
                        primaryColor,
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // Trip details in a row
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _buildDetailItem(
                      MaterialCommunityIcons.calendar,
                      'Date',
                      trip.startDate,
                    ),
                    _buildDetailItem(
                      MaterialCommunityIcons.clock_outline,
                      'Time',
                      trip.time,
                    ),
                    _buildDetailItem(
                      MaterialCommunityIcons.currency_inr,
                      'Amount',
                      '₹${trip.amount.toStringAsFixed(0)}',
                    ),
                  ],
                ),

                const SizedBox(height: 16),
                const Divider(height: 1, color: Color(0xFFEEEEEE)),
                const SizedBox(height: 16),

                // Action buttons
                _buildActionButtons(trip),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLocationRow(
    IconData icon,
    String label,
    String location,
    Color color,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            shape: BoxShape.circle,
            border: Border.all(
              color: color.withOpacity(0.3),
              width: 1,
            ),
          ),
          child: Icon(icon, size: 14, color: color),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: color,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                location,
                style: const TextStyle(
                  fontSize: 14,
                  color: textColor,
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDetailItem(IconData icon, String label, String value) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: surfaceColor,
            shape: BoxShape.circle,
            border: Border.all(
              color: secondaryColor.withOpacity(0.3),
              width: 1,
            ),
          ),
          child: Icon(icon, size: 16, color: secondaryColor),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: lightTextColor),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: textColor,
          ),
        ),
      ],
    );
  }

  Widget _buildActionButtons(Trip trip) {
    if (trip.status == 0) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: _buildActionButton(
              MaterialCommunityIcons.map_marker,
              'Track',
              secondaryColor,
              () => _handleTrackPress(trip),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _buildActionButton(
              MaterialCommunityIcons.pencil_outline,
              'Modify',
              secondaryColor,
              () => _handleModifyPress(trip),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _buildActionButton(
              MaterialCommunityIcons.close,
              'Cancel',
              secondaryColor,
              () => _handleCancelPress(trip),
            ),
          ),
        ],
      );
    } else if (trip.status == 2) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: _buildActionButton(
              MaterialCommunityIcons.receipt,
              'Invoice',
              secondaryColor,
              () => _handleInvoicePress(trip),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _buildActionButton(
              MaterialCommunityIcons.star_outline,
              'Rate',
              secondaryColor,
              () => _handleRatePress(trip),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _buildActionButton(
              MaterialCommunityIcons.refresh,
              'Rebook',
              secondaryColor,
              () => _handleRebookPress(trip),
            ),
          ),
        ],
      );
    } else {
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: _buildActionButton(
              MaterialCommunityIcons.information_outline,
              'Details',
              secondaryColor,
              () => _handleDetailsPress(trip),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _buildActionButton(
              MaterialCommunityIcons.refresh,
              'Rebook',
              secondaryColor,
              () => _handleRebookPress(trip),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _buildActionButton(
              MaterialCommunityIcons.help_circle_outline,
              'Support',
              secondaryColor,
              () => _handleSupportPress(trip),
            ),
          ),
        ],
      );
    }
  }

  IconData _getTripIcon(String type) {
    switch (type.toLowerCase()) {
      case 'bus':
        return MaterialCommunityIcons.bus;
      case 'flight':
        return MaterialCommunityIcons.airplane;
      case 'toyota innova':
      case 'innova':
        return MaterialCommunityIcons.car_estate;
      case 'sedan':
      case 'toyota etios':
      case 'honda city':
        return MaterialCommunityIcons.car_esp;
      case 'suv':
      case 'mahindra xuv':
        return MaterialCommunityIcons.car_2_plus;
      default:
        return MaterialCommunityIcons.car;
    }
  }

  Color _getStatusColor(int status) {
    switch (status) {
      case 0:
        return warningColor; // Yellow for confirmed/upcoming
      case 2:
        return successColor; // Green for completed
      case 3:
        return dangerColor; // Red for cancelled
      default:
        return accentColor; // Blue for other statuses
    }
  }
}
