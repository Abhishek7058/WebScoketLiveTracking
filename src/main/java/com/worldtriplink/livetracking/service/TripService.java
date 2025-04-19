package com.worldtriplink.livetracking.service;

import com.worldtriplink.livetracking.model.TripStatusMessage;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.messaging.simp.SimpMessagingTemplate;
import org.springframework.stereotype.Service;

import java.util.HashMap;
import java.util.Map;
import java.util.Random;

@Service
public class TripService {
    
    private final SimpMessagingTemplate messagingTemplate;
    private final Map<String, String> bookingOtps = new HashMap<>();
    
    @Autowired
    public TripService(SimpMessagingTemplate messagingTemplate) {
        this.messagingTemplate = messagingTemplate;
    }
    
    /**
     * Generates and sends OTP to user for trip verification
     */
    public void sendOtp(TripStatusMessage message) {
        // Generate a random 4-digit OTP
        String otp = generateOtp();
        
        // Store OTP for verification
        bookingOtps.put(message.getBookingId(), otp);
        
        // Create response with OTP for user
        TripStatusMessage userResponse = new TripStatusMessage();
        userResponse.setBookingId(message.getBookingId());
        userResponse.setAction("OTP_GENERATED");
        userResponse.setOtp(otp);
        
        // Send OTP to user's device
        messagingTemplate.convertAndSend(
            "/topic/booking/" + message.getBookingId() + "/user-notifications", 
            userResponse
        );
        
        // Create notification for driver (without OTP)
        TripStatusMessage driverResponse = new TripStatusMessage();
        driverResponse.setBookingId(message.getBookingId());
        driverResponse.setAction("OTP_GENERATED");
        
        // Notify driver that OTP was sent
        messagingTemplate.convertAndSend(
            "/topic/booking/" + message.getBookingId() + "/driver-notifications", 
            driverResponse
        );
    }
    
    /**
     * Verifies OTP entered by driver
     */
    public void verifyOtp(TripStatusMessage message) {
        String storedOtp = bookingOtps.get(message.getBookingId());
        boolean isValid = storedOtp != null && storedOtp.equals(message.getOtp());
        
        TripStatusMessage response = new TripStatusMessage();
        response.setBookingId(message.getBookingId());
        response.setAction(isValid ? "OTP_VERIFIED" : "OTP_INVALID");
        
        // Notify both user and driver about verification result
        messagingTemplate.convertAndSend(
            "/topic/booking/" + message.getBookingId() + "/user-notifications", 
            response
        );
        
        messagingTemplate.convertAndSend(
            "/topic/booking/" + message.getBookingId() + "/driver-notifications", 
            response
        );
        
        // If OTP is verified, remove it from storage
        if (isValid) {
            bookingOtps.remove(message.getBookingId());
        }
    }
    
    /**
     * Records start odometer and begins the trip
     */
    public void startTrip(TripStatusMessage message) {
        // In a real implementation, save the odometer reading and destination to the database
        // Update the trip status in your system
        
        TripStatusMessage response = new TripStatusMessage();
        response.setBookingId(message.getBookingId());
        response.setAction("TRIP_STARTED");
        response.setStartOdometer(message.getStartOdometer());
        response.setDestination(message.getDestination());
        response.setDestinationLatitude(message.getDestinationLatitude());
        response.setDestinationLongitude(message.getDestinationLongitude());
        
        // Notify both user and driver that trip has started
        messagingTemplate.convertAndSend(
            "/topic/booking/" + message.getBookingId() + "/user-notifications", 
            response
        );
        
        messagingTemplate.convertAndSend(
            "/topic/booking/" + message.getBookingId() + "/driver-notifications", 
            response
        );
    }
    
    /**
     * Records end odometer and completes the trip, calculating final trip details
     */
    public void endTrip(TripStatusMessage message) {
        // In a real implementation, save the end odometer reading to the database
        // Calculate final trip distance, fare, etc.
        // Update the trip status in your system
        
        double startOdo = message.getStartOdometer() != null ? message.getStartOdometer() : 0;
        double endOdo = message.getEndOdometer() != null ? message.getEndOdometer() : 0;
        double distance = endOdo - startOdo;
        
        TripStatusMessage response = new TripStatusMessage();
        response.setBookingId(message.getBookingId());
        response.setAction("TRIP_COMPLETED");
        response.setStartOdometer(startOdo);
        response.setEndOdometer(endOdo);
        
        // Notify both user and driver that trip has ended
        messagingTemplate.convertAndSend(
            "/topic/booking/" + message.getBookingId() + "/user-notifications", 
            response
        );
        
        messagingTemplate.convertAndSend(
            "/topic/booking/" + message.getBookingId() + "/driver-notifications", 
            response
        );
    }
    
    /**
     * Generates a 4-digit OTP
     */
    private String generateOtp() {
        Random random = new Random();
        int otp = 1000 + random.nextInt(9000); // 4-digit number between 1000 and 9999
        return String.valueOf(otp);
    }
} 