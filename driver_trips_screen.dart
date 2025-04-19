import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:math';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_vector_icons/flutter_vector_icons.dart';
// Add this import at the top of the file
import 'driver_profile_screen.dart';
import 'driver_tracking_screen.dart';

// Professional color palette
const Color primaryColor = Color(0xFF2E3192);
const Color secondaryColor = Color(0xFF4A90E2);
const Color accentColor = Color(0xFFFFCC00);
const Color backgroundColor = Color(0xFFF8F9FA);
const Color cardColor = Colors.white;
const Color textColor = Color(0xFF333333);
const Color lightTextColor = Color(0xFF666666);
const Color mutedTextColor = Color(0xFF999999);
const Color successColor = Color(0xFF4CAF50);
const Color errorColor = Color(0xFFFF5252);
const Color warningColor = Color(0xFFFF9800);

class DummyTrip {
  final String bookingId;
  final String passengerName;
  final String passengerPhone;
  final String pickup;
  final String destination;
  final double pickupLat;
  final double pickupLng;
  final double destLat;
  final double destLng;
  final String status;
  final String fare;
  final String date;
  final String time;

  DummyTrip({
    required this.bookingId,
    required this.passengerName,
    required this.passengerPhone,
    required this.pickup,
    required this.destination,
    required this.pickupLat,
    required this.pickupLng,
    required this.destLat,
    required this.destLng,
    required this.status,
    required this.fare,
    required this.date,
    required this.time,
  });
}


class DriverTripsScreen extends StatefulWidget {
  const DriverTripsScreen({super.key});

  @override
  State<DriverTripsScreen> createState() => _DriverTripsScreenState();
}

class _DriverTripsScreenState extends State<DriverTripsScreen> with SingleTickerProviderStateMixin {
  String activeTab = 'upcoming';
  Map<String, dynamic>? driver;
  String _userId = '';
  List<dynamic> tripInfo = [];
  List<DummyTrip> dummyTrips = [
    DummyTrip(
      bookingId: 'TRIP001',
      passengerName: 'John Doe',
      passengerPhone: '+91 9876543210',
      pickup: 'Pune Station',
      destination: 'Hinjewadi Phase 1',
      pickupLat: 18.5294,
      pickupLng: 73.8744,
      destLat: 18.5912,
      destLng: 73.7380,
      status: 'upcoming',
      fare: '₹350',
      date: '2024-02-20',
      time: '14:30',
    ),
  ];
  bool isLoading = true;
  bool isRefreshing = false;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  int _selectedIndex = 0; 

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeIn,
    );
    getDriverData();
  }

  void _onItemTapped(int index) {
    if (index == 1) {
      // Navigate to profile screen
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => const DriverProfileScreen(),
        ),
      );
    } else {
      setState(() {
        _selectedIndex = index;
      });
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> getDriverData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userDataString = prefs.getString('userData');
      debugPrint('Fetched userData from SharedPreferences: $userDataString');
      
      // First try to get userId from userData
      String userId = '';
      if (userDataString != null) {
        final userData = json.decode(userDataString);
        setState(() {
          driver = userData;
          userId = userData['userId']?.toString() ?? '';
        });
      }
      
      // If userId is still empty, try other sources
      if (userId.isEmpty) {
        userId = prefs.getInt('userId')?.toString() ?? '';
      }
      
      setState(() {
        _userId = userId;
      });
      
      debugPrint('Driver ID after all checks: $_userId');
      
      if (_userId.isNotEmpty) {
        await getTripInfoByDriverId();
      } else {
        debugPrint('No valid userId found in any storage location');
        // Navigate back to login if no valid user data is found
        Navigator.pushReplacementNamed(context, '/login');
      }
    } catch (error) {
      debugPrint('Error fetching driver data: $error');
      _showErrorSnackBar('Could not load driver data. Please try again.');
    } finally {
      setState(() {
        isLoading = false;
      });
      _animationController.forward();
    }
  }

  Future<void> getTripInfoByDriverId() async {
    try {
      if (_userId.isNotEmpty) {
        debugPrint('Fetching trips for userId: $_userId');
        setState(() {
          isRefreshing = true;
        });
        final response = await http.get(
          Uri.parse('https://api.worldtriplink.com/api/by-driver/$_userId'),
        );
        debugPrint('Trip API response status: ${response.statusCode}');
        debugPrint('Trip API response body: ${response.body.substring(0, response.body.length > 300 ? 300 : response.body.length)}');
        if (response.statusCode == 200) {
          setState(() {
            tripInfo = json.decode(response.body);
            isRefreshing = false;
          });
          debugPrint('Decoded tripInfo: ${tripInfo.toString()}');
        } else {
          _showErrorSnackBar('Server error: ${response.statusCode}');
          setState(() {
            isRefreshing = false;
          });
        }
      } else {
        debugPrint('UserId is null or empty, cannot fetch trips.');
      }
    } catch (error) {
      debugPrint('Error fetching trip info: $error');
      _showErrorSnackBar('Network error. Please check your connection.');
      setState(() {
        isRefreshing = false;
      });
    }
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: errorColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        action: SnackBarAction(
          label: 'Retry',
          textColor: Colors.white,
          onPressed: () => getDriverData(),
        ),
      ),
    );
  }

  void handleNavigateToTracking(String bookingId) {
    final booking = tripInfo.firstWhere(
      (trip) => trip['bookingId'] == bookingId || trip['bookid'] == bookingId,
      orElse: () => null,
    );
    
    debugPrint("booking: $booking");
    
    if (booking == null) {
      debugPrint("Booking not found for ID: $bookingId");
      _showErrorSnackBar('Booking details not found');
      return;
    }
    
    // Create approximate coordinates for pickup and destination based on addresses
    final Random random = Random();
    final double pickupLat = 18.5204 + (random.nextDouble() * 0.05);
    final double pickupLng = 73.8567 + (random.nextDouble() * 0.05);
    final double destLat = 18.5204 + (random.nextDouble() * 0.05);
    final double destLng = 73.8567 + (random.nextDouble() * 0.05);
    
    // Generate a random OTP for trip verification
    final String generatedOtp = (1000 + random.nextInt(9000)).toString();
    
    // Navigate to tracking screen with proper data mapping
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DriverTrackingScreen(
          arguments: {
            'bookingId': booking['bookingId'] ?? booking['bookid'] ?? "",
            'pickup': booking['userPickup'] ?? booking['fromLocation'] ?? "",
            'destination': booking['userDrop'] ?? booking['toLocation'] ?? "",
            'pickupLocation': {
              'latitude': pickupLat,
              'longitude': pickupLng,
            },
            'destinationLocation': {
              'latitude': destLat,
              'longitude': destLng,
            },
            'passengerInfo': {
              'name': booking['name'] ?? (booking['email'] != null ? booking['email'].split('@')[0] : 'Unknown User'),
              'rating': 4.5, // Default rating since it's not in the API
              'phoneNumber': booking['phone'] ?? 'N/A',
            },
            'tripInfo': {
              'estimatedTime': "35 mins", // Estimated time not in API
              'distance': "${booking['distance'] ?? 0} km",
              'fare': "₹${booking['amount'] ?? 0}",
              'paymentMethod': booking['payment'] ?? "Cash"
            },
            'currentStatus': "Heading to pickup",
            'tripType': booking['tripType'] ?? booking['userTripType'] ?? "oneWay",
            'generatedOtp': generatedOtp // Add OTP for verification
          },
        ),
      ),
    );
  }

  Future<void> makePhoneCall(String phoneNumber) async {
    final Uri launchUri = Uri(
      scheme: 'tel',
      path: phoneNumber,
    );
    if (await canLaunchUrl(launchUri)) {
      await launchUrl(launchUri);
    } else {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Error', style: TextStyle(fontWeight: FontWeight.bold)),
          content: const Text('Phone number not available'),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor,
      body: Column(
        children: [
          // App Bar
          Container(
            decoration: BoxDecoration(
              color: primaryColor,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            padding: EdgeInsets.only(
              top: MediaQuery.of(context).padding.top,
              bottom: 20,
              left: 20,
              right: 20,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const SizedBox(width: 24), // Placeholder for back button
                const Expanded(
                  child: Text(
                    'My Trips',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                IconButton(
                  icon: const Icon(MaterialCommunityIcons.refresh, size: 24, color: Colors.white),
                  onPressed: () => getTripInfoByDriverId(),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),
          
          // Driver Info Card
          if (driver != null && !isLoading)
            Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 30,
                    backgroundColor: secondaryColor.withOpacity(0.2),
                    child: Text(
                      driver!['name'] != null 
                          ? driver!['name'].toString().substring(0, 1).toUpperCase()
                          : 'D',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: secondaryColor,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          driver!['name'] ?? 'Driver',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: textColor,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          driver!['email'] ?? '',
                          style: const TextStyle(
                            fontSize: 14,
                            color: lightTextColor,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                children: [
                                  Icon(MaterialCommunityIcons.check_circle, size: 12, color: successColor),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Active',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                      color: successColor,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          
          // Tabs
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                _buildTab('upcoming', 'Upcoming'),
                _buildTab('completed', 'Completed'),
                _buildTab('cancelled', 'Cancelled'),
              ],
            ),
          ),
          
          // Trip List
          Expanded(
            child: isLoading
                ? const Center(child: CircularProgressIndicator(color: secondaryColor))
                : isRefreshing
                    ? Stack(
                        children: [
                          _buildTripList(),
                          Positioned(
                            top: 16,
                            left: 0,
                            right: 0,
                            child: Center(
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor: AlwaysStoppedAnimation<Color>(secondaryColor),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    const Text(
                                      'Refreshing...',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                        color: lightTextColor,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      )
                    : FadeTransition(
                        opacity: _fadeAnimation,
                        child: _buildTripList(),
                      ),
          ),
        ],
      ),
     bottomNavigationBar: BottomNavigationBar(
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(
            icon: Icon(MaterialCommunityIcons.car_multiple),
            label: 'Trips',
          ),
          BottomNavigationBarItem(
            icon: Icon(MaterialCommunityIcons.account_circle),
            label: 'Profile',
          ),
        ],
        currentIndex: _selectedIndex,
        selectedItemColor: secondaryColor,
        unselectedItemColor: mutedTextColor,
        backgroundColor: Colors.transparent,
        elevation: 0,
        onTap: _onItemTapped,
      ),
    );
  }
  Widget _buildTab(String tabId, String label) {
    final isActive = activeTab == tabId;
    
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => activeTab = tabId),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: isActive ? secondaryColor.withOpacity(0.1) : cardColor,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              Icon(
                tabId == 'upcoming'
                    ? MaterialCommunityIcons.calendar_clock
                    : tabId == 'completed'
                        ? MaterialCommunityIcons.check_circle
                        : MaterialCommunityIcons.close_circle,
                size: 18,
                color: isActive ? secondaryColor : mutedTextColor,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
                  color: isActive ? secondaryColor : lightTextColor,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTripList() {
    List<dynamic> filteredTrips = [];
    
    if (activeTab == 'upcoming') {
      filteredTrips = tripInfo.where((trip) => trip['status'] == 0 || trip['status'] == null).toList();
    } else if (activeTab == 'completed') {
      filteredTrips = tripInfo.where((trip) => trip['status'] == 1).toList();
    } else if (activeTab == 'cancelled') {
      filteredTrips = tripInfo.where((trip) => trip['status'] == 2).toList();
    }
    
    if (filteredTrips.isEmpty) {
      return _buildEmptyState();
    }
    
    return RefreshIndicator(
      color: secondaryColor,
      onRefresh: getTripInfoByDriverId,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: filteredTrips.length,
        itemBuilder: (context, index) {
          final trip = filteredTrips[index];
          return _buildTripCard(trip);
        },
      ),
    );
  }

  Widget _buildEmptyState() {
    IconData iconData;
    String message;
    String submessage;
    
    if (activeTab == 'upcoming') {
      iconData = MaterialCommunityIcons.calendar_blank;
      message = 'No upcoming trips';
      submessage = 'You have no upcoming trips scheduled';
    } else if (activeTab == 'completed') {
      iconData = MaterialCommunityIcons.check_circle_outline;
      message = 'No completed trips';
      submessage = 'You haven\'t completed any trips yet';
    } else {
      iconData = MaterialCommunityIcons.close_circle_outline;
      message = 'No cancelled trips';
      submessage = 'You don\'t have any cancelled trips';
    }
    
    return RefreshIndicator(
      color: secondaryColor,
      onRefresh: getTripInfoByDriverId,
      child: ListView(
        children: [
          SizedBox(
            height: MediaQuery.of(context).size.height * 0.5,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(30),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        color: secondaryColor.withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(iconData, size: 40, color: secondaryColor),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      message,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: textColor,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      submessage,
                      style: const TextStyle(
                        fontSize: 14,
                        color: lightTextColor,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      onPressed: getTripInfoByDriverId,
                      icon: const Icon(MaterialCommunityIcons.refresh),
                      label: const Text('Refresh'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: secondaryColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTripCard(Map<String, dynamic> trip) {
    final Color statusColor = activeTab == 'upcoming'
        ? secondaryColor
        : activeTab == 'completed'
            ? successColor
            : errorColor;
            
    final String statusText = activeTab == 'upcoming'
        ? 'Pickup Request'
        : activeTab == 'completed'
            ? 'Completed'
            : 'Cancelled';
    
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // Trip Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.1),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(
                      activeTab == 'upcoming'
                          ? MaterialCommunityIcons.car
                          : activeTab == 'completed'
                              ? MaterialCommunityIcons.check_circle
                              : MaterialCommunityIcons.close_circle,
                      size: 18,
                      color: statusColor,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      statusText,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: statusColor,
                      ),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: statusColor.withOpacity(0.3)),
                  ),
                  child: Text(
                    trip['date'] ?? trip['startDate'] ?? 'Today',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: statusColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Passenger Info (only for upcoming trips)
                if (activeTab == 'upcoming') ...[
                  Row(
                    children: [
                      Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          trip['name'] != null
                              ? trip['name'].toString().substring(0, 1).toUpperCase()
                              : trip['email'] != null
                                  ? trip['email'].toString().substring(0, 1).toUpperCase()
                                  : '?',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: secondaryColor,
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              trip['name'] ??
                                  (trip['email'] != null
                                      ? trip['email'].toString().split('@')[0]
                                      : 'Unknown User'),
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: textColor,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                const Icon(
                                  MaterialCommunityIcons.star,
                                  size: 14,
                                  color: Color(0xFFFFD700),
                                ),
                                const SizedBox(width: 4),
                                const Text(
                                  '4.5',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: lightTextColor,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Icon(
                                  MaterialCommunityIcons.phone,
                                  size: 14,
                                  color: secondaryColor,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  trip['phone'] ?? 'N/A',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: lightTextColor,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      InkWell(
                        onTap: () {
                          if (trip['phone'] != null) {
                            makePhoneCall(trip['phone'].toString());
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Phone number not available')),
                            );
                          }
                        },
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            MaterialCommunityIcons.phone,
                            size: 20,
                            color: secondaryColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 16),
                ],
                
                // Trip Details
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Column(
                      children: [
                        Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                            boxShadow: [
                              BoxShadow(
                                color: secondaryColor.withOpacity(0.3),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          width: 2,
                          height: 30,
                          color: Colors.grey[300],
                        ),
                        Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                            boxShadow: [
                              BoxShadow(
                                color: errorColor.withOpacity(0.3),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'PICKUP',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: mutedTextColor,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                trip['userPickup'] ?? trip['fromLocation'] ?? 'N/A',
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w500,
                                  color: textColor,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'DESTINATION',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: mutedTextColor,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                trip['userDrop'] ?? trip['toLocation'] ?? 'N/A',
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w500,
                                  color: textColor,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 16),
                
                // Trip Info
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _buildInfoItem(
                      MaterialCommunityIcons.map_marker_distance,
                      'Distance',
                      '${trip['distance'] ?? 0} km',
                    ),
                    _buildInfoItem(
                      MaterialCommunityIcons.swap_horizontal,
                      'Trip Type',
                      _formatTripType(trip['tripType'] ?? trip['userTripType'] ?? 'oneWay'),
                    ),
                    _buildInfoItem(
                      MaterialCommunityIcons.currency_inr,
                      activeTab == 'cancelled' ? 'Cancellation Fee' : 'Fare',
                      '₹${activeTab == 'cancelled' ? (trip['penalty'] ?? 0) : (trip['amount'] ?? 0)}',
                    ),
                  ],
                ),
                
                // Trip Actions (only for upcoming trips)
                if (activeTab == 'upcoming') ...[
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => handleNavigateToTracking(
                            trip['bookingId'] ?? trip['bookid'] ?? '',
                          ),
                          icon: const Icon(MaterialCommunityIcons.navigation, size: 18),
                          label: const Text('Navigate'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: secondaryColor,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            elevation: 0,
                                                    ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            if (trip['phone'] != null) {
                              makePhoneCall(trip['phone'].toString());
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Phone number not available')),
                              );
                            }
                          },
                          icon: const Icon(MaterialCommunityIcons.phone, size: 18),
                          label: const Text('Call Passenger'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: secondaryColor,
                            side: BorderSide(color: secondaryColor),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }


 

void _handleTrackTrip(DummyTrip trip) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DriverTrackingScreen(
          arguments: {
            'bookingId': trip.bookingId,
            'pickup': trip.pickup,
            'destination': trip.destination,
            'pickupLocation': {
              'latitude': trip.pickupLat,
              'longitude': trip.pickupLng,
            },
            'destinationLocation': {
              'latitude': trip.destLat,
              'longitude': trip.destLng,
            },
            'passengerInfo': {
              'name': trip.passengerName,
              'phoneNumber': trip.passengerPhone,
              'rating': '4.5',
            },
            'tripInfo': {
              'fare': trip.fare,
              'date': trip.date,
              'time': trip.time,
              'paymentMethod': 'Cash',
            },
          },
        ),
      ),
    );
  }

 Widget _buildLocationRow(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 18, color: lightTextColor),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 14),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }



  Widget _buildInfoItem(IconData icon, String label, String value) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, size: 20, color: secondaryColor),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: mutedTextColor,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: textColor,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  String _formatTripType(String tripType) {
    if (tripType.toLowerCase() == 'oneway') {
      return 'One Way';
    } else if (tripType.toLowerCase() == 'roundtrip') {
      return 'Round Trip';
    } else if (tripType.toLowerCase() == 'rental') {
      return 'Rental';
    } else {
      return tripType;
    }
  }
}
                          