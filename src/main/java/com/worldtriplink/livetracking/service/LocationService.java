package com.worldtriplink.livetracking.service;

import com.worldtriplink.livetracking.model.LocationMessage;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.messaging.simp.SimpMessagingTemplate;
import org.springframework.stereotype.Service;

@Service
public class LocationService {
    
    private final SimpMessagingTemplate messagingTemplate;
    
    @Autowired
    public LocationService(SimpMessagingTemplate messagingTemplate) {
        this.messagingTemplate = messagingTemplate;
    }
    
    /**
     * Updates driver location and broadcasts to the user
     */
    public void updateDriverLocation(LocationMessage locationMessage) {
        // In a real implementation, save the location in the database
        // Calculate distance and estimated time based on driver and user locations
        
        // Send location to the specific user subscribed to this booking
        messagingTemplate.convertAndSend(
            "/topic/booking/" + locationMessage.getBookingId() + "/driver-location", 
            locationMessage
        );
    }
    
    /**
     * Updates user location and broadcasts to the driver
     */
    public void updateUserLocation(LocationMessage locationMessage) {
        // In a real implementation, save the location in the database
        
        // Send location to the specific driver subscribed to this booking
        messagingTemplate.convertAndSend(
            "/topic/booking/" + locationMessage.getBookingId() + "/user-location", 
            locationMessage
        );
    }
    
    /**
     * Updates the database with the driver's location
     */
    public void saveDriverLocation(Long driverId, double latitude, double longitude) {
        // Code to update driver's location in the database
        // This would make a call to your existing API:
        // api.worldtriplink.com/api/update-driver-location/{driverId}?latitude={latitude}&longitude={longitude}
    }
    
    /**
     * Updates the database with the user's location
     */
    public void saveUserLocation(Long userId, double latitude, double longitude) {
        // Code to update user's location in the database
        // This would make a call to your existing API:
        // api.worldtriplink.com/api/update-Location/{userId}?latitude={latitude}&longitude={longitude}
    }
    
    /**
     * Calculates distance between two points using Haversine formula
     */
    public double calculateDistance(double lat1, double lon1, double lat2, double lon2) {
        final int R = 6371; // Radius of the earth in km
        
        double latDistance = Math.toRadians(lat2 - lat1);
        double lonDistance = Math.toRadians(lon2 - lon1);
        double a = Math.sin(latDistance / 2) * Math.sin(latDistance / 2)
                + Math.cos(Math.toRadians(lat1)) * Math.cos(Math.toRadians(lat2))
                * Math.sin(lonDistance / 2) * Math.sin(lonDistance / 2);
        double c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
        
        return R * c; // Distance in km
    }
    
    /**
     * Estimate time based on distance and average speed
     */
    public int estimateTime(double distanceInKm, double avgSpeedKmh) {
        if (avgSpeedKmh <= 0) {
            avgSpeedKmh = 40; // Default average speed in city
        }
        
        // Time in minutes = (distance / speed) * 60
        return (int) ((distanceInKm / avgSpeedKmh) * 60);
    }
} 