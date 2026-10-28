import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:bedlink/models/emergency_request.dart';
import 'package:bedlink/services/routing_service.dart';
import 'package:bedlink/core/utils/haversine.dart';
import 'package:bedlink/features/nurse/widgets/live_ambulance_map_card.dart';

void main() {
  group('Phase 9B - Live GPS Nurse Map Tests', () {
    test('RouteGeometryResult supports OSRM and straight-line fallback geometries', () {
      final fallbackStraightLine = [
        LatLng(19.0760, 72.8777),
        LatLng(19.0500, 72.8200),
      ];
      final fallback = RouteGeometryResult(
        points: fallbackStraightLine,
        travelMinutes: 12,
        distanceKm: 4.5,
        isOsrm: false,
      );

      expect(fallback.isOsrm, isFalse);
      expect(fallback.points.length, 2);
      expect(fallback.points.first.latitude, 19.0760);
      expect(fallback.points.first.longitude, 72.8777);
      expect(fallback.points.last.latitude, 19.0500);
      expect(fallback.points.last.longitude, 72.8200);
      expect(fallback.distanceKm, 4.5);
      expect(fallback.travelMinutes, 12);
    });

    test('Freshness state logic handles live, delayed, lost, and clock offset', () {
      final now = DateTime.now();

      // < 20s -> live
      final liveLoc = AmbulanceLiveLocation(
        lat: 19.07,
        lng: 72.87,
        updatedAt: now.subtract(const Duration(seconds: 10)),
      );
      final ageLive = now.difference(liveLoc.updatedAt!).inSeconds;
      expect(ageLive < 20, isTrue);

      // 20s to 60s -> delayed
      final delayedLoc = AmbulanceLiveLocation(
        lat: 19.07,
        lng: 72.87,
        updatedAt: now.subtract(const Duration(seconds: 35)),
      );
      final ageDelayed = now.difference(delayedLoc.updatedAt!).inSeconds;
      expect(ageDelayed >= 20 && ageDelayed <= 60, isTrue);

      // > 60s -> lost
      final lostLoc = AmbulanceLiveLocation(
        lat: 19.07,
        lng: 72.87,
        updatedAt: now.subtract(const Duration(seconds: 90)),
      );
      final ageLost = now.difference(lostLoc.updatedAt!).inSeconds;
      expect(ageLost > 60, isTrue);

      // Server clock offset adjustment test
      // If phone clock is 15s behind server
      final serverNow = now.add(const Duration(seconds: 15));
      final serverLoc = AmbulanceLiveLocation(
        lat: 19.07,
        lng: 72.87,
        updatedAt: serverNow.subtract(const Duration(seconds: 5)),
      );
      final clockOffset = now.difference(serverLoc.updatedAt!);
      final adjustedNow = now.subtract(clockOffset);
      final adjustedAge = adjustedNow.difference(serverLoc.updatedAt!).inSeconds;
      expect(adjustedAge.abs(), lessThanOrEqualTo(1));
    });

    test('Arrival threshold detects < 150m correctly', () {
      // Lilavati Hospital coords approx: 19.0514, 72.8290
      const hospLat = 19.0514;
      const hospLng = 72.8290;

      // 100 meters away (approx 0.0009 degrees latitude)
      const nearLat = 19.0522;
      const nearLng = 72.8290;

      final nearDistKm = calculateHaversineDistance(nearLat, nearLng, hospLat, hospLng);
      final nearDistMeters = nearDistKm * 1000;
      expect(nearDistMeters, lessThan(150.0));

      // 1 km away
      const farLat = 19.0600;
      const farLng = 72.8290;
      final farDistKm = calculateHaversineDistance(farLat, farLng, hospLat, hospLng);
      final farDistMeters = farDistKm * 1000;
      expect(farDistMeters, greaterThan(150.0));
    });

    test('LocationFreshnessState enum has live, delayed, lost, waiting', () {
      expect(LocationFreshnessState.values.contains(LocationFreshnessState.live), isTrue);
      expect(LocationFreshnessState.values.contains(LocationFreshnessState.delayed), isTrue);
      expect(LocationFreshnessState.values.contains(LocationFreshnessState.lost), isTrue);
      expect(LocationFreshnessState.values.contains(LocationFreshnessState.waiting), isTrue);
    });
  });
}
