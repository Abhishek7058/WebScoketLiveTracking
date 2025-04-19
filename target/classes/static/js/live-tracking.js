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
let isLocationUpdating = false;

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
        mapTypeControl: true,
        fullscreenControl: true,
        streetViewControl: false,
        mapTypeId: google.maps.MapTypeId.ROADMAP
    });
    
    // Initialize directions service and renderer
    directionsService = new google.maps.DirectionsService();
    directionsRenderer = new google.maps.DirectionsRenderer({
        map: map,
        suppressMarkers: true, // We'll use custom markers
        polylineOptions: {
            strokeColor: '#4285F4',
            strokeWeight: 5,
            strokeOpacity: 0.8
        }
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
    }, function(error) {
        // Connection error handling
        console.error("STOMP connection error:", error);
        alert("Failed to connect to the server. Please try again.");
    });
}

// Start periodic driver location updates
function startDriverLocationUpdates() {
    // Use browser geolocation to get current position
    if (navigator.geolocation) {
        isLocationUpdating = true;
        
        // Update location every 5 seconds
        navigator.geolocation.watchPosition(
            function(position) {
                driverLatitude = position.coords.latitude;
                driverLongitude = position.coords.longitude;
                
                console.log("Driver location updated:", driverLatitude, driverLongitude);
                
                // Send location update to server
                sendDriverLocation();
                
                // Update driver marker on map
                updateDriverMarker();
                
                // Update route if all positions are known
                updateRoute();
            },
            function(error) {
                console.error("Error getting geolocation: ", error);
                
                // Fallback to hardcoded location for testing (Pune)
                if (!isLocationUpdating) {
                    driverLatitude = 18.5204;
                    driverLongitude = 73.8567;
                    sendDriverLocation();
                    updateDriverMarker();
                }
            },
            {
                enableHighAccuracy: true,
                maximumAge: 10000,
                timeout: 5000
            }
        );
        
        // Backup timer to ensure location is sent regularly
        setInterval(function() {
            if (driverLatitude && driverLongitude) {
                sendDriverLocation();
            }
        }, 5000);
    } else {
        alert("Geolocation is not supported by this browser.");
        
        // Fallback to hardcoded location for testing (Pune)
        driverLatitude = 18.5204;
        driverLongitude = 73.8567;
        sendDriverLocation();
        updateDriverMarker();
    }
}

// Start periodic user location updates
function startUserLocationUpdates() {
    // Use browser geolocation to get current position
    if (navigator.geolocation) {
        isLocationUpdating = true;
        
        // Update location every 5 seconds
        navigator.geolocation.watchPosition(
            function(position) {
                userLatitude = position.coords.latitude;
                userLongitude = position.coords.longitude;
                
                console.log("User location updated:", userLatitude, userLongitude);
                
                // Send location update to server
                sendUserLocation();
                
                // Update user marker on map
                updateUserMarker();
                
                // Update route if all positions are known
                updateRoute();
            },
            function(error) {
                console.error("Error getting geolocation: ", error);
                
                // Fallback to hardcoded location for testing (Mumbai)
                if (!isLocationUpdating) {
                    userLatitude = 19.0760;
                    userLongitude = 72.8777;
                    sendUserLocation();
                    updateUserMarker();
                }
            },
            {
                enableHighAccuracy: true,
                maximumAge: 10000,
                timeout: 5000
            }
        );
        
        // Backup timer to ensure location is sent regularly
        setInterval(function() {
            if (userLatitude && userLongitude) {
                sendUserLocation();
            }
        }, 5000);
    } else {
        alert("Geolocation is not supported by this browser.");
        
        // Fallback to hardcoded location for testing (Mumbai)
        userLatitude = 19.0760;
        userLongitude = 72.8777;
        sendUserLocation();
        updateUserMarker();
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
    console.log("Driver location sent to server:", locationMessage);
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
    console.log("User location sent to server:", locationMessage);
}

// Handle driver location updates from server
function onDriverLocationUpdate(payload) {
    const message = JSON.parse(payload.body);
    console.log("Received driver location update:", message);
    
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
    console.log("Received user location update:", message);
    
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
    
    // SVG car icon - updated to be more recognizable
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
    
    // Always show driver marker regardless of user type
    driverMarker.setMap(map);
    
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
    
    // SVG person icon - updated to be more recognizable
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
    
    // Always show user marker regardless of user type
    userMarker.setMap(map);
    
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
    
    // SVG flag/pin icon
    const flagIconSvg = {
        path: 'M14.4,6L14,4H5V21H7V14H12.6L13,16H20V6H14.4Z',
        fillColor: '#4CAF50',
        fillOpacity: 1,
        strokeWeight: 1,
        strokeColor: '#263238',
        scale: 1.5,
        anchor: new google.maps.Point(12, 20),
        rotation: 0
    };
    
    if (!destinationMarker) {
        // Create marker if it doesn't exist
        destinationMarker = new google.maps.Marker({
            position: position,
            map: map,
            icon: flagIconSvg,
            title: 'Destination'
        });
        
        // Add info window with destination information
        const infoWindow = new google.maps.InfoWindow({
            content: '<div style="font-weight:bold;">Destination</div>'
        });
        
        destinationMarker.addListener('click', function() {
            infoWindow.open(map, destinationMarker);
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