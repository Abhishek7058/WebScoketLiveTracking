// Global variables
let stompClient = null;
let map = null;
let userMarker = null;
let driverMarker = null;
let destinationMarker = null;
let directionsService = null;
let directionsRenderer = null;
let userLatitude = null;
let userLongitude = null;
let driverLatitude = null;
let driverLongitude = null;
let destinationLatitude = null;
let destinationLongitude = null;
let bookingId = null;
let userId = null;
let driverId = null;
let userType = null;
let geocoder = null;

// Initialize page when DOM is loaded
$(document).ready(function() {
    // Initialize Google Maps components
    initializeMap();
    
    // Connect button click handler
    $("#connect-button").click(function() {
        bookingId = $("#bookingId").val();
        userType = $("#userType").val();
        userId = $("#userId").val();
        
        if (!bookingId || !userId) {
            alert("Please enter both Booking ID and your ID");
            return;
        }
        
        connectWebSocket();
    });
    
    // Driver: Send OTP button click handler
    $("#send-otp-button").click(function() {
        sendOtp();
    });
    
    // Driver: Verify OTP button click handler (moved to driver side)
    $("#verify-otp-button").click(function() {
        verifyOtp();
    });
    
    // Driver: Start Trip button click handler
    $("#start-trip-button").click(function() {
        startTrip();
    });
    
    // Driver: End Trip button click handler
    $("#end-trip-button").click(function() {
        endTrip();
    });
    
    // Auto-complete for destination input
    if (document.getElementById("destination")) {
        const destinationInput = document.getElementById("destination");
        const autocomplete = new google.maps.places.Autocomplete(destinationInput);
        autocomplete.addListener("place_changed", function() {
            const place = autocomplete.getPlace();
            if (place && place.geometry && place.geometry.location) {
                destinationLatitude = place.geometry.location.lat();
                destinationLongitude = place.geometry.location.lng();
                updateDestinationMarker();
            }
        });
    }
});

// Initialize Google Map
function initializeMap() {
    // Create map centered on a default location (e.g., Pune)
    const defaultLocation = { lat: 18.5204, lng: 73.8567 }; // Pune coordinates
    
    map = new google.maps.Map(document.getElementById("map"), {
        zoom: 12,
        center: defaultLocation,
    });
    
    // Initialize directions service and renderer
    directionsService = new google.maps.DirectionsService();
    directionsRenderer = new google.maps.DirectionsRenderer({
        map: map,
        suppressMarkers: true // We'll use custom markers
    });
    
    // Initialize geocoder
    geocoder = new google.maps.Geocoder();
}

// Connect to WebSocket server
function connectWebSocket() {
    const socket = new SockJS('/ws-trip-tracking');
    stompClient = Stomp.over(socket);
    
    stompClient.connect({}, function(frame) {
        console.log('Connected: ' + frame);
        
        // Show tracking container and hide connection form
        $("#connection-form").addClass("hidden");
        $("#tracking-container").removeClass("hidden");
        $("#display-booking-id").text(bookingId);
        
        // Subscribe to the appropriate topics based on user type
        if (userType === "DRIVER") {
            // Show driver controls and subscribe to user location updates
            $("#driver-controls").removeClass("hidden");
            
            stompClient.subscribe('/topic/booking/' + bookingId + '/user-location', onUserLocationUpdate);
            stompClient.subscribe('/topic/booking/' + bookingId + '/driver-notifications', onDriverNotification);
            
            // Start sending driver location updates
            startDriverLocationUpdates();
        } else {
            // Show user controls and subscribe to driver location updates
            $("#user-controls").removeClass("hidden");
            
            stompClient.subscribe('/topic/booking/' + bookingId + '/driver-location', onDriverLocationUpdate);
            stompClient.subscribe('/topic/booking/' + bookingId + '/user-notifications', onUserNotification);
            
            // Start sending user location updates
            startUserLocationUpdates();
        }
    });
}

// Start periodic driver location updates
function startDriverLocationUpdates() {
    // Use browser geolocation to get current position
    if (navigator.geolocation) {
        // Update location every 5 seconds
        navigator.geolocation.watchPosition(
            function(position) {
                driverLatitude = position.coords.latitude;
                driverLongitude = position.coords.longitude;
                
                // Send location update to server
                sendDriverLocation();
                
                // Update driver marker on map
                updateDriverMarker();
                
                // Update route if all positions are known
                updateRoute();
            },
            function(error) {
                console.error("Error getting geolocation: ", error);
            },
            {
                enableHighAccuracy: true,
                maximumAge: 0,
                timeout: 5000
            }
        );
    } else {
        alert("Geolocation is not supported by this browser.");
    }
}

// Start periodic user location updates
function startUserLocationUpdates() {
    // Use browser geolocation to get current position
    if (navigator.geolocation) {
        // Update location every 5 seconds
        navigator.geolocation.watchPosition(
            function(position) {
                userLatitude = position.coords.latitude;
                userLongitude = position.coords.longitude;
                
                // Send location update to server
                sendUserLocation();
                
                // Update user marker on map
                updateUserMarker();
                
                // Update route if all positions are known
                updateRoute();
            },
            function(error) {
                console.error("Error getting geolocation: ", error);
            },
            {
                enableHighAccuracy: true,
                maximumAge: 0,
                timeout: 5000
            }
        );
    } else {
        alert("Geolocation is not supported by this browser.");
    }
}

// Send driver location update to server
function sendDriverLocation() {
    if (!stompClient || !driverLatitude || !driverLongitude) return;
    
    const locationMessage = {
        bookingId: bookingId,
        latitude: driverLatitude,
        longitude: driverLongitude,
        userType: "DRIVER",
        driverId: userId // In driver mode, userId is actually driverId
    };
    
    stompClient.send("/app/driver-location", {}, JSON.stringify(locationMessage));
}

// Send user location update to server
function sendUserLocation() {
    if (!stompClient || !userLatitude || !userLongitude) return;
    
    const locationMessage = {
        bookingId: bookingId,
        latitude: userLatitude,
        longitude: userLongitude,
        userType: "USER",
        userId: userId
    };
    
    stompClient.send("/app/user-location", {}, JSON.stringify(locationMessage));
}

// Handle driver location updates from server
function onDriverLocationUpdate(payload) {
    const message = JSON.parse(payload.body);
    
    driverLatitude = message.latitude;
    driverLongitude = message.longitude;
    driverId = message.driverId;
    
    // Update driver marker
    updateDriverMarker();
    
    // Update distance and ETA
    if (message.distance) {
        $("#distance").text(message.distance.toFixed(1) + " km");
    }
    
    if (message.estimatedTime) {
        $("#eta").text(message.estimatedTime + " minutes");
    }
    
    // Update route if positions are known
    updateRoute();
}

// Handle user location updates from server
function onUserLocationUpdate(payload) {
    const message = JSON.parse(payload.body);
    
    userLatitude = message.latitude;
    userLongitude = message.longitude;
    
    // Update user marker
    updateUserMarker();
    
    // Update route if positions are known
    updateRoute();
}

// Update driver marker on map
function updateDriverMarker() {
    if (!map || !driverLatitude || !driverLongitude) return;
    
    const position = {
        lat: driverLatitude,
        lng: driverLongitude
    };
    
    if (!driverMarker) {
        // Create marker if it doesn't exist
        driverMarker = new google.maps.Marker({
            position: position,
            map: map,
            icon: {
                url: 'http://maps.google.com/mapfiles/ms/icons/blue-dot.png',
                scaledSize: new google.maps.Size(40, 40)
            },
            title: 'Driver'
        });
    } else {
        // Update marker position
        driverMarker.setPosition(position);
    }
    
    // Center map on driver marker if in user mode
    if (userType === "USER") {
        map.setCenter(position);
    }
}

// Update user marker on map
function updateUserMarker() {
    if (!map || !userLatitude || !userLongitude) return;
    
    const position = {
        lat: userLatitude,
        lng: userLongitude
    };
    
    if (!userMarker) {
        // Create marker if it doesn't exist
        userMarker = new google.maps.Marker({
            position: position,
            map: map,
            icon: {
                url: 'http://maps.google.com/mapfiles/ms/icons/red-dot.png',
                scaledSize: new google.maps.Size(40, 40)
            },
            title: 'User'
        });
    } else {
        // Update marker position
        userMarker.setPosition(position);
    }
    
    // Center map on user marker if in driver mode
    if (userType === "DRIVER") {
        map.setCenter(position);
    }
}

// Update destination marker on map
function updateDestinationMarker() {
    if (!map || !destinationLatitude || !destinationLongitude) return;
    
    const position = {
        lat: destinationLatitude,
        lng: destinationLongitude
    };
    
    if (!destinationMarker) {
        // Create marker if it doesn't exist
        destinationMarker = new google.maps.Marker({
            position: position,
            map: map,
            icon: {
                url: 'http://maps.google.com/mapfiles/ms/icons/green-dot.png',
                scaledSize: new google.maps.Size(40, 40)
            },
            title: 'Destination'
        });
    } else {
        // Update marker position
        destinationMarker.setPosition(position);
    }
    
    // Update route with the new destination
    updateRoute();
}

// Update route between positions
function updateRoute() {
    if (!directionsService || !directionsRenderer) return;
    
    // Check if we have driver and destination or user coordinates
    if (driverLatitude && driverLongitude) {
        const driverPos = { lat: driverLatitude, lng: driverLongitude };
        let destination;
        
        // Determine destination (either destination marker or user location)
        if (destinationLatitude && destinationLongitude) {
            destination = { lat: destinationLatitude, lng: destinationLongitude };
        } else if (userLatitude && userLongitude) {
            destination = { lat: userLatitude, lng: userLongitude };
        } else {
            // Neither destination nor user location is available
            return;
        }
        
        directionsService.route({
            origin: driverPos,
            destination: destination,
            travelMode: google.maps.TravelMode.DRIVING
        }, function(response, status) {
            if (status === 'OK') {
                directionsRenderer.setDirections(response);
                
                // Update distance and ETA based on route
                const route = response.routes[0];
                if (route && route.legs && route.legs.length > 0) {
                    const leg = route.legs[0];
                    $("#distance").text(leg.distance.text);
                    $("#eta").text(leg.duration.text);
                }
            } else {
                console.error('Directions request failed due to ' + status);
            }
        });
    }
}

// Send OTP to user (driver action)
function sendOtp() {
    if (!stompClient) return;
    
    const tripStatusMessage = {
        bookingId: bookingId,
        action: "SEND_OTP",
        driverId: userId // In driver mode, userId is actually driverId
    };
    
    stompClient.send("/app/send-otp", {}, JSON.stringify(tripStatusMessage));
}

// Verify OTP (now driver action)
function verifyOtp() {
    if (!stompClient) return;
    
    const otp = $("#otp-input").val();
    if (!otp) {
        alert("Please enter the OTP you received from the user");
        return;
    }
    
    const tripStatusMessage = {
        bookingId: bookingId,
        action: "VERIFY_OTP",
        otp: otp,
        driverId: userId // In driver mode, userId is actually driverId
    };
    
    stompClient.send("/app/verify-otp", {}, JSON.stringify(tripStatusMessage));
}

// Start trip (driver action)
function startTrip() {
    if (!stompClient) return;
    
    const startOdometer = $("#start-odometer").val();
    const destination = $("#destination").val();
    
    if (!startOdometer) {
        alert("Please enter the start odometer reading");
        return;
    }
    
    if (!destination) {
        alert("Please enter the destination");
        return;
    }
    
    // If destination coordinates are not set, try to geocode
    if (!destinationLatitude || !destinationLongitude) {
        geocoder.geocode({ 'address': destination }, function(results, status) {
            if (status === 'OK' && results[0]) {
                destinationLatitude = results[0].geometry.location.lat();
                destinationLongitude = results[0].geometry.location.lng();
                updateDestinationMarker();
                
                // Send trip start message with destination
                sendTripStartMessage(startOdometer, destination, destinationLatitude, destinationLongitude);
            } else {
                alert("Could not find destination coordinates. Please try a different address.");
            }
        });
    } else {
        // Use existing destination coordinates
        sendTripStartMessage(startOdometer, destination, destinationLatitude, destinationLongitude);
    }
}

// Send trip start message
function sendTripStartMessage(startOdometer, destination, destLat, destLng) {
    const tripStatusMessage = {
        bookingId: bookingId,
        action: "START_TRIP",
        startOdometer: parseFloat(startOdometer),
        destination: destination,
        destinationLatitude: destLat,
        destinationLongitude: destLng,
        driverId: userId // In driver mode, userId is actually driverId
    };
    
    stompClient.send("/app/start-trip", {}, JSON.stringify(tripStatusMessage));
}

// End trip (driver action)
function endTrip() {
    if (!stompClient) return;
    
    const endOdometer = $("#end-odometer").val();
    if (!endOdometer) {
        alert("Please enter the end odometer reading");
        return;
    }
    
    const startOdometer = parseFloat($("#start-odometer").val() || "0");
    
    const tripStatusMessage = {
        bookingId: bookingId,
        action: "END_TRIP",
        startOdometer: startOdometer,
        endOdometer: parseFloat(endOdometer),
        driverId: userId // In driver mode, userId is actually driverId
    };
    
    stompClient.send("/app/end-trip", {}, JSON.stringify(tripStatusMessage));
}

// Handle driver notifications
function onDriverNotification(payload) {
    const message = JSON.parse(payload.body);
    
    switch (message.action) {
        case "OTP_GENERATED":
            $("#trip-status").text("OTP sent to user");
            $("#send-otp-container").addClass("hidden");
            $("#verify-otp-container").removeClass("hidden");
            break;
            
        case "OTP_VERIFIED":
            $("#trip-status").text("OTP verified");
            $("#verify-otp-container").addClass("hidden");
            $("#start-trip-container").removeClass("hidden");
            break;
            
        case "OTP_INVALID":
            $("#trip-status").text("OTP verification failed");
            alert("OTP verification failed. Please enter the correct OTP from the user.");
            break;
            
        case "TRIP_STARTED":
            $("#trip-status").text("Trip in progress");
            $("#start-trip-container").addClass("hidden");
            $("#end-trip-container").removeClass("hidden");
            
            // If message contains destination coordinates, update the map
            if (message.destinationLatitude && message.destinationLongitude) {
                destinationLatitude = message.destinationLatitude;
                destinationLongitude = message.destinationLongitude;
                updateDestinationMarker();
            }
            break;
            
        case "TRIP_COMPLETED":
            $("#trip-status").text("Trip completed");
            $("#end-trip-container").addClass("hidden");
            alert("Trip has been completed successfully!");
            break;
    }
}

// Handle user notifications
function onUserNotification(payload) {
    const message = JSON.parse(payload.body);
    
    switch (message.action) {
        case "OTP_GENERATED":
            $("#trip-status").text("OTP received");
            $("#otp-display-container").removeClass("hidden");
            $("#otp-display").text(message.otp);
            break;
            
        case "OTP_VERIFIED":
            $("#trip-status").text("OTP verified");
            break;
            
        case "OTP_INVALID":
            $("#trip-status").text("OTP verification failed");
            break;
            
        case "TRIP_STARTED":
            $("#trip-status").text("Trip in progress");
            
            // If message contains destination coordinates, update the map
            if (message.destinationLatitude && message.destinationLongitude) {
                destinationLatitude = message.destinationLatitude;
                destinationLongitude = message.destinationLongitude;
                updateDestinationMarker();
            }
            break;
            
        case "TRIP_COMPLETED":
            $("#trip-status").text("Trip completed");
            alert("Your trip has been completed!");
            break;
    }
}