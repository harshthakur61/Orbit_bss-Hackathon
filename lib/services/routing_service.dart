import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import '../core/constants.dart';
import '../core/utils/haversine.dart';

class RouteEtaResult {
  final int travelMinutes;
  final double distanceKm;
  final bool isOsrm;

  const RouteEtaResult({
    required this.travelMinutes,
    required this.distanceKm,
    required this.isOsrm,
  });
}

class RouteGeometryResult {
  final List<LatLng> points;
  final int travelMinutes;
  final double distanceKm;
  final bool isOsrm;

  const RouteGeometryResult({
    required this.points,
    required this.travelMinutes,
    required this.distanceKm,
    required this.isOsrm,
  });
}

class RoutingService {
  final http.Client _client;

  RoutingService({http.Client? client}) : _client = client ?? http.Client();

  /// Calculates driving duration in minutes and distance in km between two GPS points.
  /// Always falls back to Haversine straight-line distance * city traffic factor if OSRM fails/times out.
  Future<RouteEtaResult> getDrivingEta({
    required double startLat,
    required double startLng,
    required double endLat,
    required double endLng,
  }) async {
    final double haversineKm =
        calculateHaversineDistance(startLat, startLng, endLat, endLng);
    final int fallbackMinutes = estimateDrivingTimeMinutes(haversineKm);

    try {
      final url = Uri.parse(
        'https://router.project-osrm.org/route/v1/driving/'
        '$startLng,$startLat;$endLng,$endLat?overview=false',
      );

      final response = await _client.get(url).timeout(
        const Duration(seconds: AppConstants.osrmTimeoutSeconds),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['routes'] != null && (data['routes'] as List).isNotEmpty) {
          final route = data['routes'][0];
          final double durationSeconds = (route['duration'] as num).toDouble();
          final double distanceMeters = (route['distance'] as num).toDouble();

          final int osrmMinutes = (durationSeconds / 60).round().clamp(1, 999);
          final double osrmKm = (distanceMeters / 1000);

          return RouteEtaResult(
            travelMinutes: osrmMinutes,
            distanceKm: osrmKm,
            isOsrm: true,
          );
        }
      }
    } catch (e) {
      debugPrint('OSRM routing request failed/timed out ($e). Using Haversine fallback.');
    }

    return RouteEtaResult(
      travelMinutes: fallbackMinutes,
      distanceKm: haversineKm,
      isOsrm: false,
    );
  }

  /// Calculates driving route geometry and duration.
  /// Queries OSRM with overview=full&geometries=geojson with a 3-second timeout.
  /// Falls back to straight line and Haversine ETA on network failure or timeout.
  Future<RouteGeometryResult> getDrivingRouteWithGeometry({
    required double startLat,
    required double startLng,
    required double endLat,
    required double endLng,
  }) async {
    final double haversineKm =
        calculateHaversineDistance(startLat, startLng, endLat, endLng);
    final int fallbackMinutes = estimateDrivingTimeMinutes(haversineKm);
    final fallbackStraightLine = [
      LatLng(startLat, startLng),
      LatLng(endLat, endLng),
    ];

    try {
      final url = Uri.parse(
        'https://router.project-osrm.org/route/v1/driving/'
        '$startLng,$startLat;$endLng,$endLat?overview=full&geometries=geojson',
      );

      final response = await _client.get(url).timeout(
        const Duration(seconds: AppConstants.osrmTimeoutSeconds),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['routes'] != null && (data['routes'] as List).isNotEmpty) {
          final route = data['routes'][0];
          final double durationSeconds = (route['duration'] as num).toDouble();
          final double distanceMeters = (route['distance'] as num).toDouble();

          final int osrmMinutes = (durationSeconds / 60).round().clamp(1, 999);
          final double osrmKm = (distanceMeters / 1000);

          final rawCoords = route['geometry']?['coordinates'] as List? ?? [];
          final polylinePoints = rawCoords
              .map((c) => LatLng(
                    (c[1] as num).toDouble(),
                    (c[0] as num).toDouble(),
                  ))
              .toList();

          return RouteGeometryResult(
            points: polylinePoints.isNotEmpty ? polylinePoints : fallbackStraightLine,
            travelMinutes: osrmMinutes,
            distanceKm: osrmKm,
            isOsrm: true,
          );
        }
      }
    } catch (e) {
      debugPrint('[RoutingService] OSRM geometry query failed/timed out ($e). Using straight line fallback.');
    }

    return RouteGeometryResult(
      points: fallbackStraightLine,
      travelMinutes: fallbackMinutes,
      distanceKm: haversineKm,
      isOsrm: false,
    );
  }
}
