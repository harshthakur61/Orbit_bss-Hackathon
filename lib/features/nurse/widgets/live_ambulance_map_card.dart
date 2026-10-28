import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:intl/intl.dart';
import '../../../core/theme.dart';
import '../../../core/utils/haversine.dart';
import '../../../models/emergency_request.dart';
import '../../../models/hospital.dart';
import '../../../providers/location_providers.dart';
import '../../../providers/request_providers.dart';

enum LocationFreshnessState { live, delayed, lost, waiting }

class LiveAmbulanceMapCard extends ConsumerStatefulWidget {
  final EmergencyRequest request;
  final Hospital hospital;

  const LiveAmbulanceMapCard({
    super.key,
    required this.request,
    required this.hospital,
  });

  @override
  ConsumerState<LiveAmbulanceMapCard> createState() => _LiveAmbulanceMapCardState();
}

class _LiveAmbulanceMapCardState extends ConsumerState<LiveAmbulanceMapCard>
    with SingleTickerProviderStateMixin {
  late final MapController _mapController;
  late final AnimationController _animController;
  late final Animation<double> _animCurve;

  Timer? _freshnessTimer;

  // Telemetry coordinates & animation
  LatLng? _currentAmbulancePoint;
  LatLng? _targetAmbulancePoint;
  LatLng? _previousAmbulancePoint;
  double _currentHeading = 0.0;
  double _targetHeading = 0.0;
  double _previousHeading = 0.0;

  // Route caching & OSRM throttling
  List<LatLng> _routePoints = [];
  bool _isDashedFallback = false;
  DateTime? _lastRouteFetchTime;
  LatLng? _lastRouteFetchPoint;
  int? _etaMinutes;
  double? _distanceKm;

  // Camera & User Gesture Handling
  bool _userHasPannedOrZoomed = false;

  // Server clock offset tracking
  Duration _serverClockOffset = Duration.zero;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _animCurve = CurvedAnimation(parent: _animController, curve: Curves.easeInOut);

    _animController.addListener(() {
      if (_previousAmbulancePoint != null && _targetAmbulancePoint != null) {
        final t = _animCurve.value;
        final lat = _previousAmbulancePoint!.latitude +
            (_targetAmbulancePoint!.latitude - _previousAmbulancePoint!.latitude) * t;
        final lng = _previousAmbulancePoint!.longitude +
            (_targetAmbulancePoint!.longitude - _previousAmbulancePoint!.longitude) * t;

        double heading = _currentHeading;
        if ((_targetHeading - _previousHeading).abs() < 180) {
          heading = _previousHeading + (_targetHeading - _previousHeading) * t;
        } else {
          heading = _targetHeading;
        }

        setState(() {
          _currentAmbulancePoint = LatLng(lat, lng);
          _currentHeading = heading;
        });
      }
    });

    // Freshness check every 4s
    _freshnessTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _freshnessTimer?.cancel();
    _animController.dispose();
    _mapController.dispose();
    super.dispose();
  }

  void _onNewLocation(AmbulanceLiveLocation loc) {
    final hospPoint = LatLng(widget.hospital.lat, widget.hospital.lng);
    final newPoint = LatLng(loc.lat, loc.lng);

    // Track server clock offset
    if (loc.updatedAt != null) {
      final now = DateTime.now();
      _serverClockOffset = now.difference(loc.updatedAt!);
      if (_serverClockOffset.inSeconds.abs() > 300) {
        // Limit extreme offsets
        _serverClockOffset = Duration.zero;
      }
    }

    if (_currentAmbulancePoint == null) {
      // First fix
      _currentAmbulancePoint = newPoint;
      _targetAmbulancePoint = newPoint;
      _currentHeading = loc.speedKmh > 2.0 && loc.heading >= 0 ? loc.heading : 0.0;
      _targetHeading = _currentHeading;
      _fitBounds(hospPoint, newPoint, immediate: true);
      _fetchRouteIfNeeded(newPoint, hospPoint, force: true);
    } else {
      final distanceMoved = calculateHaversineDistance(
        _targetAmbulancePoint!.latitude,
        _targetAmbulancePoint!.longitude,
        newPoint.latitude,
        newPoint.longitude,
      );

      // Only animate if moved >= 3m
      if (distanceMoved > 0.003) {
        _previousAmbulancePoint = _currentAmbulancePoint;
        _targetAmbulancePoint = newPoint;
        _previousHeading = _currentHeading;
        _targetHeading = loc.speedKmh > 2.0 && loc.heading >= 0 ? loc.heading : _currentHeading;

        _animController.reset();
        _animController.forward();

        if (!_userHasPannedOrZoomed) {
          _fitBounds(hospPoint, newPoint);
        }

        _fetchRouteIfNeeded(newPoint, hospPoint);
      }
    }
  }

  Future<void> _fetchRouteIfNeeded(
    LatLng ambPoint,
    LatLng hospPoint, {
    bool force = false,
  }) async {
    final now = DateTime.now();
    final elapsedSec = _lastRouteFetchTime == null
        ? 999
        : now.difference(_lastRouteFetchTime!).inSeconds;

    final distanceSinceLastFetchKm = _lastRouteFetchPoint == null
        ? 999.0
        : calculateHaversineDistance(
            _lastRouteFetchPoint!.latitude,
            _lastRouteFetchPoint!.longitude,
            ambPoint.latitude,
            ambPoint.longitude,
          );

    // Recompute at most every ~30s or when moved > 300m
    if (!force && elapsedSec < 30 && distanceSinceLastFetchKm < 0.3) {
      return;
    }

    _lastRouteFetchTime = now;
    _lastRouteFetchPoint = ambPoint;

    final routingService = ref.read(routingServiceProvider);
    final routeResult = await routingService.getDrivingRouteWithGeometry(
      startLat: ambPoint.latitude,
      startLng: ambPoint.longitude,
      endLat: hospPoint.latitude,
      endLng: hospPoint.longitude,
    );

    if (mounted) {
      setState(() {
        _routePoints = routeResult.points;
        _isDashedFallback = !routeResult.isOsrm;
        _etaMinutes = routeResult.travelMinutes;
        _distanceKm = routeResult.distanceKm;
      });
    }
  }

  void _fitBounds(LatLng p1, LatLng p2, {bool immediate = false}) {
    if (!mounted) return;
    try {
      final bounds = LatLngBounds.fromPoints([p1, p2]);
      _mapController.fitCamera(
        CameraFit.bounds(
          bounds: bounds,
          padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 28),
        ),
      );
    } catch (_) {}
  }

  LocationFreshnessState _getFreshness(AmbulanceLiveLocation? loc) {
    if (loc == null || loc.updatedAt == null) {
      return LocationFreshnessState.waiting;
    }

    final adjustedNow = DateTime.now().subtract(_serverClockOffset);
    final ageSeconds = adjustedNow.difference(loc.updatedAt!).inSeconds;

    if (ageSeconds < 20) {
      return LocationFreshnessState.live;
    } else if (ageSeconds <= 60) {
      return LocationFreshnessState.delayed;
    } else {
      return LocationFreshnessState.lost;
    }
  }

  @override
  Widget build(BuildContext context) {
    final liveAsync = ref.watch(liveLocationStreamProvider(widget.request.id));
    final hospPoint = LatLng(widget.hospital.lat, widget.hospital.lng);

    return liveAsync.when(
      data: (loc) {
        if (loc != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _onNewLocation(loc);
          });
        }

        final freshness = _getFreshness(loc);
        final ambPoint = _currentAmbulancePoint ??
            (loc != null ? LatLng(loc.lat, loc.lng) : null);

        // Calculate arrival distance
        final distanceToHospKm = ambPoint != null
            ? calculateHaversineDistance(
                ambPoint.latitude, ambPoint.longitude, hospPoint.latitude, hospPoint.longitude)
            : null;
        final isArrivingNow = distanceToHospKm != null && distanceToHospKm <= 0.15;

        return Container(
          margin: const EdgeInsets.only(top: 14),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.divider),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(8),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header Status Strip
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                color: AppColors.background,
                child: Row(
                  children: [
                    _buildFreshnessIndicator(freshness, loc),
                    const Spacer(),
                    if (isArrivingNow)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.warning.withAlpha(30),
                          border: Border.all(color: AppColors.warning),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.near_me_rounded, size: 14, color: AppColors.warning),
                            SizedBox(width: 4),
                            Text(
                              'Arriving now',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF8A5A00),
                              ),
                            ),
                          ],
                        ),
                      )
                    else if (_etaMinutes != null)
                      Text(
                        'ETA: $_etaMinutes min (${_distanceKm?.toStringAsFixed(1)} km)',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primaryDark,
                        ),
                      ),
                  ],
                ),
              ),

              // Interactive Map Layer
              SizedBox(
                height: 200,
                child: Stack(
                  children: [
                    FlutterMap(
                      mapController: _mapController,
                      options: MapOptions(
                        initialCenter: hospPoint,
                        initialZoom: 13.0,
                        onPositionChanged: (pos, hasGesture) {
                          if (hasGesture && !_userHasPannedOrZoomed) {
                            setState(() => _userHasPannedOrZoomed = true);
                          }
                        },
                      ),
                      children: [
                        TileLayer(
                          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                          userAgentPackageName: 'com.bedlink.bedlink',
                        ),

                        // Route Polyline Layer
                        if (_routePoints.isNotEmpty)
                          PolylineLayer(
                            polylines: [
                              Polyline(
                                points: _routePoints,
                                strokeWidth: 4.0,
                                color: _isDashedFallback
                                    ? AppColors.textSecondary.withAlpha(160)
                                    : AppColors.primary,
                                pattern: _isDashedFallback
                                    ? StrokePattern.dashed(segments: const [8, 6])
                                    : const StrokePattern.solid(),
                              ),
                            ],
                          ),

                        // Markers Layer (Hospital + Ambulance)
                        MarkerLayer(
                          markers: [
                            // 1. Hospital Marker (Clinical Teal)
                            Marker(
                              point: hospPoint,
                              width: 42,
                              height: 42,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: AppColors.primary,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.white, width: 2),
                                  boxShadow: const [
                                    BoxShadow(
                                      color: Colors.black26,
                                      blurRadius: 4,
                                      offset: Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: const Icon(
                                  Icons.local_hospital_rounded,
                                  color: Colors.white,
                                  size: 24,
                                ),
                              ),
                            ),

                            // 2. Ambulance Marker (Rotated by heading, greyed if lost)
                            if (ambPoint != null)
                              Marker(
                                point: ambPoint,
                                width: 44,
                                height: 44,
                                child: _buildAmbulanceMarker(
                                  heading: _currentHeading,
                                  isLost: freshness == LocationFreshnessState.lost,
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),

                    // Re-center Floating Action Button
                    if (_userHasPannedOrZoomed && ambPoint != null)
                      Positioned(
                        right: 12,
                        bottom: 12,
                        child: Material(
                          color: AppColors.surface,
                          elevation: 3,
                          borderRadius: BorderRadius.circular(20),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(20),
                            onTap: () {
                              setState(() => _userHasPannedOrZoomed = false);
                              _fitBounds(hospPoint, ambPoint);
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: const [
                                  Icon(Icons.center_focus_strong_rounded,
                                      size: 16, color: AppColors.primary),
                                  SizedBox(width: 4),
                                  Text(
                                    'Re-center',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.primary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
      loading: () => _buildPlaceholderCard(
        message: 'Connecting to live ambulance telemetry...',
        isLoading: true,
      ),
      error: (err, stack) => _buildPlaceholderCard(
        message: 'Telemetry unavailable',
        isLoading: false,
      ),
    );
  }

  Widget _buildAmbulanceMarker({required double heading, required bool isLost}) {
    final markerColor = isLost ? Colors.grey.shade600 : AppColors.primary;
    final headingRad = (heading >= 0 && heading <= 360) ? (heading * (math.pi / 180.0)) : 0.0;

    return Transform.rotate(
      angle: headingRad,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          border: Border.all(color: markerColor, width: 2.5),
          boxShadow: const [
            BoxShadow(
              color: Colors.black26,
              blurRadius: 4,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Icon(
          Icons.navigation_rounded,
          color: markerColor,
          size: 26,
        ),
      ),
    );
  }

  Widget _buildFreshnessIndicator(
    LocationFreshnessState freshness,
    AmbulanceLiveLocation? loc,
  ) {
    Color dotColor;
    String label;

    switch (freshness) {
      case LocationFreshnessState.live:
        dotColor = AppColors.success;
        label = 'Live';
        break;
      case LocationFreshnessState.delayed:
        dotColor = AppColors.warning;
        final age = loc?.updatedAt != null
            ? DateTime.now().subtract(_serverClockOffset).difference(loc!.updatedAt!).inSeconds
            : 25;
        label = 'Last updated ${age}s ago';
        break;
      case LocationFreshnessState.lost:
        dotColor = Colors.grey.shade500;
        final timeStr = loc?.updatedAt != null
            ? DateFormat('HH:mm').format(loc!.updatedAt!)
            : '--:--';
        label = 'Signal lost – last seen at $timeStr';
        break;
      case LocationFreshnessState.waiting:
        dotColor = AppColors.textSecondary;
        label = 'Waiting for ambulance location…';
        break;
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: dotColor,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: freshness == LocationFreshnessState.lost
                ? Colors.grey.shade700
                : AppColors.textPrimary,
          ),
        ),
      ],
    );
  }

  Widget _buildPlaceholderCard({required String message, required bool isLoading}) {
    return Container(
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.primaryTint,
              borderRadius: BorderRadius.circular(10),
            ),
            child: isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  )
                : const Icon(Icons.gps_fixed_rounded, color: AppColors.primary, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  message,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                const Text(
                  'GPS telemetry will stream automatically once en route.',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
