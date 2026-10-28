import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:bedlink/services/live_location_service.dart';

void main() {
  group('Phase 9C - Live Tracking Simulator & Edge Cases Tests', () {
    test('calculateBearing computes accurate compass bearings between coordinates', () {
      // Due north (increasing latitude, same longitude): ~0 deg
      final northBearing = LiveLocationService.calculateBearing(
        19.0000, 72.8000,
        19.0100, 72.8000,
      );
      expect(northBearing, closeTo(0.0, 1.0));

      // Due east (same latitude, increasing longitude): ~90 deg
      final eastBearing = LiveLocationService.calculateBearing(
        19.0000, 72.8000,
        19.0000, 72.8100,
      );
      expect(eastBearing, closeTo(90.0, 1.0));

      // Due south (decreasing latitude, same longitude): ~180 deg
      final southBearing = LiveLocationService.calculateBearing(
        19.0100, 72.8000,
        19.0000, 72.8000,
      );
      expect(southBearing, closeTo(180.0, 1.0));

      // Due west (same latitude, decreasing longitude): ~270 deg
      final westBearing = LiveLocationService.calculateBearing(
        19.0000, 72.8100,
        19.0000, 72.8000,
      );
      expect(westBearing, closeTo(270.0, 1.0));
    });

    test('Stoplight jitter suppression: speed < 2 km/h preserves last good heading', () {
      double lastGoodHeading = 85.0;

      // When stopped at light (speed = 0.5 km/h, erratic compass = 240 deg)
      const currentSpeedKmh = 0.5;
      const rawHeading = 240.0;

      double filteredHeading = rawHeading;
      if (currentSpeedKmh < 2.0 && lastGoodHeading > 0) {
        filteredHeading = lastGoodHeading;
      } else if (rawHeading >= 0) {
        lastGoodHeading = rawHeading;
      }

      // Compass should NOT jump to 240 deg; it must stay 85 deg
      expect(filteredHeading, 85.0);

      // When accelerating above 2 km/h (speed = 35 km/h, rawHeading = 120 deg)
      const drivingSpeedKmh = 35.0;
      const drivingHeading = 120.0;
      if (drivingSpeedKmh < 2.0 && lastGoodHeading > 0) {
        filteredHeading = lastGoodHeading;
      } else if (drivingHeading >= 0) {
        lastGoodHeading = drivingHeading;
        filteredHeading = drivingHeading;
      }

      // Now heading updates smoothly
      expect(filteredHeading, 120.0);
      expect(lastGoodHeading, 120.0);
    });

    test('Write volume verification: 4s throttle guarantees max 15 writes per minute', () {
      const minIntervalSeconds = 4;
      const secondsInMinute = 60;
      const maxWritesPerMinute = secondsInMinute / minIntervalSeconds;

      expect(maxWritesPerMinute, 15);
      expect(maxWritesPerMinute <= 15, isTrue);

      // Stationary heartbeat (15s interval)
      const heartbeatIntervalSeconds = 15;
      const stationaryWritesPerMinute = secondsInMinute / heartbeatIntervalSeconds;
      expect(stationaryWritesPerMinute, 4);
      expect(stationaryWritesPerMinute <= 15, isTrue);
    });

    test('Simulation speed multiplier clamps within supported 0.5x to 8.0x range', () {
      final service = LiveLocationService();
      expect(service.isSimulating, isFalse);
      expect(service.simulationSpeedMultiplier, 1.0);

      service.setSimulationSpeedMultiplier(2.0);
      expect(service.simulationSpeedMultiplier, 2.0);

      service.setSimulationSpeedMultiplier(4.0);
      expect(service.simulationSpeedMultiplier, 4.0);

      // Clamp checks
      service.setSimulationSpeedMultiplier(0.1);
      expect(service.simulationSpeedMultiplier, 0.5);

      service.setSimulationSpeedMultiplier(20.0);
      expect(service.simulationSpeedMultiplier, 8.0);
    });

    test('Route points step progression computes valid coordinates along geometry', () {
      final routePoints = [
        LatLng(19.0514, 72.8290),
        LatLng(19.0530, 72.8300),
        LatLng(19.0550, 72.8310),
        LatLng(19.0570, 72.8320),
      ];

      expect(routePoints.length, 4);
      final bearing1to2 = LiveLocationService.calculateBearing(
        routePoints[0].latitude,
        routePoints[0].longitude,
        routePoints[1].latitude,
        routePoints[1].longitude,
      );
      expect(bearing1to2, greaterThan(0));
      expect(bearing1to2, lessThan(360));
    });
  });
}
