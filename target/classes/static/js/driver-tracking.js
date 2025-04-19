// Global variables
let map;
let userMarker;
let driverMarker;
let userLatitude;
let userLongitude;
let driverLatitude;
let driverLongitude;
let stompClient;
let bookingId;
let driverId;
let userId;
const userType = "DRIVER";

// Initialize map when the page loads
document.addEventListener('DOMContentLoaded', function() {
    // Get booking information from URL parameters
    const urlParams = new URLSearchParams(window.location.search);
    bookingId = urlParams.get('bookingId');
    driverId = urlParams.get('driverId');
    userId = urlParams.get('userId');
    
    // Initialize Google Maps
    initializeMap();
    
    // Connect to WebSocket server
    connectToWebSocket();
    
    // Setup driver controls
    setupDriverControls();
});

// Initialize Google Maps
function initializeMap() {
    // Default center (will be updated with actual location)
    const defaultCenter = { lat: 12.9716, lng: 77.5946 }; // Bangalore
    
    // Create map
    map = new google.maps.Map(document.getElementById('map'), {
        zoom: 15,
        center: defaultCenter,
        mapTypeId: google.maps.MapTypeId.ROADMAP,
        disableDefaultUI: true,
        zoomControl: true,
        streetViewControl: true
    });
    
    // Start location updates for driver
    startDriverLocationUpdates();
}

// Connect to WebSocket server
function connectToWebSocket() {
    const socket = new SockJS('/ws');
    stompClient = Stomp.over(socket);
    
    stompClient.connect({}, function(frame) {
        console.log('Connected to WebSocket: ' + frame);
        
        // Subscribe to user location updates
        stompClient.subscribe('/topic/user-location/' + bookingId, function(message) {
            onUserLocationUpdate(JSON.parse(message.body));
        });
        
        // Subscribe to booking status updates
        stompClient.subscribe('/topic/booking-status/' + bookingId, function(message) {
            onBookingStatusUpdate(JSON.parse(message.body));
        });
    });
}

// Setup driver controls
function setupDriverControls() {
    // Show driver UI elements
    document.getElementById('driver-controls').style.display = 'block';
    document.getElementById('user-controls').style.display = 'none';
    
    // Set up event listeners for driver controls
    document.getElementById('send-otp-btn').addEventListener('click', sendOtp);
    document.getElementById('start-trip-btn').addEventListener('click', startTrip);
    document.getElementById('end-trip-btn').addEventListener('click', endTrip);
}

// Start location updates for driver
function startDriverLocationUpdates() {
    if (navigator.geolocation) {
        const locationOptions = {
            enableHighAccuracy: true,
            timeout: 10000,
            maximumAge: 0
        };
        
        // Watch driver position
        navigator.geolocation.watchPosition(
            function(position) {
                driverLatitude = position.coords.latitude;
                driverLongitude = position.coords.longitude;
                
                // Update driver marker
                updateDriverMarker();
                
                // Send driver location to server
                sendDriverLocation();
            },
            function(error) {
                console.error('Error getting location:', error);
                showNotification('Error getting location. Please enable location services.', 'error');
            },
            locationOptions
        );
    } else {
        showNotification('Geolocation is not supported by this browser.', 'error');
    }
}

// Send driver location to server
function sendDriverLocation() {
    if (!stompClient || !bookingId || !driverLatitude || !driverLongitude) return;
    
    const locationUpdate = {
        bookingId: bookingId,
        latitude: driverLatitude,
        longitude: driverLongitude,
        timestamp: new Date().getTime()
    };
    
    stompClient.send("/app/driver-location", {}, JSON.stringify(locationUpdate));
}

// Handle user location update
function onUserLocationUpdate(locationUpdate) {
    userLatitude = locationUpdate.latitude;
    userLongitude = locationUpdate.longitude;
    
    // Update user marker
    updateUserMarker();
}

// Handle booking status update
function onBookingStatusUpdate(statusUpdate) {
    const status = statusUpdate.status;
    const message = statusUpdate.message;
    
    // Update UI based on booking status
    switch (status) {
        case 'CONFIRMED':
            document.getElementById('booking-status').textContent = 'Booking Confirmed';
            break;
        case 'OTP_SENT':
            document.getElementById('otp-input-container').style.display = 'block';
            document.getElementById('booking-status').textContent = 'OTP Sent - Verify OTP';
            break;
        case 'TRIP_STARTED':
            document.getElementById('otp-input-container').style.display = 'none';
            document.getElementById('booking-status').textContent = 'Trip Started';
            document.getElementById('end-trip-btn').disabled = false;
            document.getElementById('start-trip-btn').disabled = true;
            break;
        case 'TRIP_COMPLETED':
            document.getElementById('booking-status').textContent = 'Trip Completed';
            document.getElementById('end-trip-btn').disabled = true;
            break;
    }
    
    // Show notification
    showNotification(message, 'info');
}

// Update driver marker on map
function updateDriverMarker() {
    if (!map || !driverLatitude || !driverLongitude) return;
    
    const position = {
        lat: driverLatitude,
        lng: driverLongitude
    };
    
    // SVG car icon for driver
    const carIconSvg = {
        path: 'M29.395,0H17.636c-3.117,0-5.643,3.467-5.643,6.584v34.804c0,3.116,2.526,5.644,5.643,5.644h11.759   c3.116,0,5.644-2.527,5.644-5.644V6.584C35.037,3.467,32.511,0,29.395,0z M34.05,14.188v11.665l-2.729,0.351v-4.806L34.05,14.188z    M32.618,10.773c-1.016,3.9-2.219,8.51-2.219,8.51H16.631l-2.222-8.51C14.41,10.773,23.293,7.755,32.618,10.773z M15.741,21.713   v4.492l-2.73-0.349V14.502L15.741,21.713z M13.011,37.938V27.579l2.73,0.343v8.196L13.011,37.938z M14.568,40.882l2.218-3.336   h13.771l2.219,3.336H14.568z M31.321,35.805v-7.872l2.729-0.355v10.048L31.321,35.805z',
        fillColor: '#4285F4',
        fillOpacity: 1,
        strokeWeight: 1,
        strokeColor: '#263238',
        scale: 0.6,
        anchor: new google.maps.Point(24, 24),
        rotation: 0
    };
    
    if (!driverMarker) {
        // Create marker if it doesn't exist
        driverMarker = new google.maps.Marker({
            position: position,
            map: map,
            icon: carIconSvg,
            title: 'You (Driver)'
        });
        
        // Add info window with driver information
        const infoWindow = new google.maps.InfoWindow({
            content: '<div style="font-weight:bold;">You (Driver)</div>'
        });
        
        driverMarker.addListener('click', function() {
            infoWindow.open(map, driverMarker);
        });
    } else {
        // Update marker position
        driverMarker.setPosition(position);
    }
    
    // Always show driver marker
    driverMarker.setMap(map);
    
    // Center map on driver marker
    map.setCenter(position);
}

// Update user marker on map
function updateUserMarker() {
    if (!map || !userLatitude || !userLongitude) return;
    
    const position = {
        lat: userLatitude,
        lng: userLongitude
    };
    
    // SVG person icon for user
    const personIconSvg = {
        path: 'M12,0C5.4,0,0,5.4,0,12c0,6.6,5.4,12,12,12s12-5.4,12-12C24,5.4,18.6,0,12,0z M12,3.6c2,0,3.6,1.6,3.6,3.6  c0,2-1.6,3.6-3.6,3.6c-2,0-3.6-1.6-3.6-3.6C8.4,5.2,10,3.6,12,3.6z M12,21.6c-3,0-5.7-1.5-7.2-4c0-2.4,4.8-3.7,7.2-3.7  c2.4,0,7.2,1.3,7.2,3.7C17.7,20.1,15,21.6,12,21.6z',
        fillColor: '#FF5252',
        fillOpacity: 1,
        strokeWeight: 1,
        strokeColor: '#263238',
        scale: 1.2,
        anchor: new google.maps.Point(12, 12),
        rotation: 0
    };
    
    if (!userMarker) {
        // Create marker if it doesn't exist
        userMarker = new google.maps.Marker({
            position: position,
            map: map,
            icon: personIconSvg,
            title: 'User'
        });
        
        // Add info window with user information
        const infoWindow = new google.maps.InfoWindow({
            content: '<div style="font-weight:bold;">User</div>'
        });
        
        userMarker.addListener('click', function() {
            infoWindow.open(map, userMarker);
        });
    } else {
        // Update marker position
        userMarker.setPosition(position);
    }
    
    // Always show user marker
    userMarker.setMap(map);
}

// Send OTP to user
function sendOtp() {
    if (!stompClient || !bookingId) return;
    
    const sendOtpRequest = {
        bookingId: bookingId,
        driverId: driverId
    };
    
    stompClient.send("/app/send-otp", {}, JSON.stringify(sendOtpRequest));
    document.getElementById('send-otp-btn').disabled = true;
}

// Start trip after OTP verification
function startTrip() {
    if (!stompClient || !bookingId) return;
    
    const otpValue = document.getElementById('otp-input').value;
    
    if (!otpValue) {
        showNotification('Please enter OTP', 'error');
        return;
    }
    
    const startTripRequest = {
        bookingId: bookingId,
        driverId: driverId,
        otp: otpValue
    };
    
    stompClient.send("/app/start-trip", {}, JSON.stringify(startTripRequest));
}

// End trip
function endTrip() {
    if (!stompClient || !bookingId) return;
    
    const endTripRequest = {
        bookingId: bookingId,
        driverId: driverId
    };
    
    stompClient.send("/app/end-trip", {}, JSON.stringify(endTripRequest));
}

// Show notification
function showNotification(message, type) {
    const notification = document.getElementById('notification');
    
    // Set notification content
    notification.textContent = message;
    
    // Set notification type class
    notification.className = 'notification';
    notification.classList.add(`notification-${type}`);
    
    // Show notification
    notification.style.display = 'block';
    
    // Hide notification after 5 seconds
    setTimeout(function() {
        notification.style.display = 'none';
    }, 5000);
} 