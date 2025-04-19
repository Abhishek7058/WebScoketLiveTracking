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
const userType = "USER";

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
    
    // Setup user controls
    setupUserControls();
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
    
    // Start location updates for user
    startUserLocationUpdates();
}

// Connect to WebSocket server
function connectToWebSocket() {
    const socket = new SockJS('/ws');
    stompClient = Stomp.over(socket);
    
    stompClient.connect({}, function(frame) {
        console.log('Connected to WebSocket: ' + frame);
        
        // Subscribe to driver location updates
        stompClient.subscribe('/topic/driver-location/' + bookingId, function(message) {
            onDriverLocationUpdate(JSON.parse(message.body));
        });
        
        // Subscribe to booking status updates
        stompClient.subscribe('/topic/booking-status/' + bookingId, function(message) {
            onBookingStatusUpdate(JSON.parse(message.body));
        });
    });
}

// Setup user controls
function setupUserControls() {
    // Show user UI elements
    document.getElementById('user-controls').style.display = 'block';
    document.getElementById('driver-controls').style.display = 'none';
    
    // Set up event listeners for user controls
    document.getElementById('verify-otp-btn').addEventListener('click', verifyOtp);
    document.getElementById('cancel-trip-btn').addEventListener('click', cancelTrip);
    document.getElementById('submit-rating-btn').addEventListener('click', submitRating);
}

// Start location updates for user
function startUserLocationUpdates() {
    if (navigator.geolocation) {
        const locationOptions = {
            enableHighAccuracy: true,
            timeout: 10000,
            maximumAge: 0
        };
        
        // Watch user position
        navigator.geolocation.watchPosition(
            function(position) {
                userLatitude = position.coords.latitude;
                userLongitude = position.coords.longitude;
                
                // Update user marker
                updateUserMarker();
                
                // Send user location to server
                sendUserLocation();
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

// Send user location to server
function sendUserLocation() {
    if (!stompClient || !bookingId || !userLatitude || !userLongitude) return;
    
    const locationUpdate = {
        bookingId: bookingId,
        latitude: userLatitude,
        longitude: userLongitude,
        timestamp: new Date().getTime()
    };
    
    stompClient.send("/app/user-location", {}, JSON.stringify(locationUpdate));
}

// Handle driver location update
function onDriverLocationUpdate(locationUpdate) {
    driverLatitude = locationUpdate.latitude;
    driverLongitude = locationUpdate.longitude;
    
    // Update driver marker
    updateDriverMarker();
}

// Handle booking status update
function onBookingStatusUpdate(statusUpdate) {
    const status = statusUpdate.status;
    const message = statusUpdate.message;
    
    // Update UI based on booking status
    switch (status) {
        case 'CONFIRMED':
            document.getElementById('booking-status').textContent = 'Booking Confirmed';
            document.getElementById('cancel-trip-btn').disabled = false;
            break;
        case 'OTP_SENT':
            document.getElementById('otp-input-container').style.display = 'block';
            document.getElementById('booking-status').textContent = 'OTP Received - Verify with Driver';
            break;
        case 'TRIP_STARTED':
            document.getElementById('otp-input-container').style.display = 'none';
            document.getElementById('cancel-trip-btn').disabled = true;
            document.getElementById('booking-status').textContent = 'Trip Started';
            break;
        case 'TRIP_COMPLETED':
            document.getElementById('rating-container').style.display = 'block';
            document.getElementById('booking-status').textContent = 'Trip Completed';
            break;
    }
    
    // Show notification
    showNotification(message, 'info');
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
            title: 'You (User)'
        });
        
        // Add info window with user information
        const infoWindow = new google.maps.InfoWindow({
            content: '<div style="font-weight:bold;">You (User)</div>'
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
    
    // Center map on user marker
    map.setCenter(position);
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
            title: 'Driver'
        });
        
        // Add info window with driver information
        const infoWindow = new google.maps.InfoWindow({
            content: '<div style="font-weight:bold;">Driver</div>'
        });
        
        driverMarker.addListener('click', function() {
            infoWindow.open(map, driverMarker);
        });
    } else {
        // Update marker position
        driverMarker.setPosition(position);
    }
    
    // Always show driver marker if the driver location is available
    driverMarker.setMap(map);
}

// Verify OTP
function verifyOtp() {
    const otpValue = document.getElementById('otp-input').value;
    
    if (!otpValue) {
        showNotification('Please enter OTP', 'error');
        return;
    }
    
    if (!stompClient || !bookingId) return;
    
    const verifyOtpRequest = {
        bookingId: bookingId,
        userId: userId,
        otp: otpValue
    };
    
    stompClient.send("/app/verify-otp", {}, JSON.stringify(verifyOtpRequest));
}

// Cancel trip
function cancelTrip() {
    if (!stompClient || !bookingId) return;
    
    const cancelTripRequest = {
        bookingId: bookingId,
        userId: userId
    };
    
    stompClient.send("/app/cancel-trip", {}, JSON.stringify(cancelTripRequest));
}

// Submit rating
function submitRating() {
    if (!stompClient || !bookingId) return;
    
    const ratingValue = document.querySelector('input[name="rating"]:checked');
    const feedbackText = document.getElementById('feedback-text').value;
    
    if (!ratingValue) {
        showNotification('Please select a rating', 'error');
        return;
    }
    
    const ratingRequest = {
        bookingId: bookingId,
        userId: userId,
        rating: parseInt(ratingValue.value),
        feedback: feedbackText
    };
    
    stompClient.send("/app/submit-rating", {}, JSON.stringify(ratingRequest));
    
    // Hide rating container after submission
    document.getElementById('rating-container').style.display = 'none';
    showNotification('Thank you for your rating!', 'success');
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