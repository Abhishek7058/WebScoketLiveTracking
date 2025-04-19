package com.worldtriplink.livetracking.controller;

import com.worldtriplink.livetracking.model.LocationMessage;
import com.worldtriplink.livetracking.model.TripStatusMessage;
import com.worldtriplink.livetracking.service.LocationService;
import com.worldtriplink.livetracking.service.TripService;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.messaging.handler.annotation.MessageMapping;
import org.springframework.messaging.handler.annotation.Payload;
import org.springframework.stereotype.Controller;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class LiveTrackingController {

    private final LocationService locationService;
    private final TripService tripService;

    @Autowired
    public LiveTrackingController(LocationService locationService, TripService tripService) {
        this.locationService = locationService;
        this.tripService = tripService;
    }

    /**
     * Handles driver location updates
     */
    @MessageMapping("/driver-location")
    public void updateDriverLocation(@Payload LocationMessage locationMessage) {
        // Save driver location to database
        locationService.saveDriverLocation(
                locationMessage.getDriverId(),
                locationMessage.getLatitude(),
                locationMessage.getLongitude()
        );
        
        // Broadcast to relevant user
        locationService.updateDriverLocation(locationMessage);
    }

    /**
     * Handles user location updates
     */
    @MessageMapping("/user-location")
    public void updateUserLocation(@Payload LocationMessage locationMessage) {
        // Save user location to database
        locationService.saveUserLocation(
                locationMessage.getUserId(),
                locationMessage.getLatitude(),
                locationMessage.getLongitude()
        );
        
        // Broadcast to relevant driver
        locationService.updateUserLocation(locationMessage);
    }

    /**
     * Handles OTP sending request from driver
     */
    @MessageMapping("/send-otp")
    public void sendOtp(@Payload TripStatusMessage message) {
        tripService.sendOtp(message);
    }

    /**
     * Handles OTP verification from driver
     */
    @MessageMapping("/verify-otp")
    public void verifyOtp(@Payload TripStatusMessage message) {
        tripService.verifyOtp(message);
    }

    /**
     * Handles trip start (recording odometer and destination)
     */
    @MessageMapping("/start-trip")
    public void startTrip(@Payload TripStatusMessage message) {
        tripService.startTrip(message);
    }

    /**
     * Handles trip end (recording odometer and calculating final details)
     */
    @MessageMapping("/end-trip")
    public void endTrip(@Payload TripStatusMessage message) {
        tripService.endTrip(message);
    }
} 