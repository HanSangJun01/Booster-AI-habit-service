package com.booster.shared.gps;

import org.springframework.stereotype.Component;

/** Haversine 공식 기반 GPS 반경 판정. A/B 공유 컴포넌트. */
@Component
public class GpsVerificationEvaluator {

    private static final double EARTH_RADIUS_METERS = 6_371_000.0;

    public boolean isWithinRadius(double registeredLat, double registeredLng,
                                  int radiusMeters,
                                  double currentLat, double currentLng) {
        double distance = haversineDistance(registeredLat, registeredLng, currentLat, currentLng);
        return distance <= radiusMeters;
    }

    public boolean isWithinRadius(GpsCoordinates registered, int radiusMeters, GpsCoordinates current) {
        return isWithinRadius(registered.lat(), registered.lng(), radiusMeters, current.lat(), current.lng());
    }

    private double haversineDistance(double lat1, double lng1, double lat2, double lng2) {
        double dLat = Math.toRadians(lat2 - lat1);
        double dLng = Math.toRadians(lng2 - lng1);
        double a = Math.sin(dLat / 2) * Math.sin(dLat / 2)
                + Math.cos(Math.toRadians(lat1)) * Math.cos(Math.toRadians(lat2))
                * Math.sin(dLng / 2) * Math.sin(dLng / 2);
        double c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
        return EARTH_RADIUS_METERS * c;
    }
}
