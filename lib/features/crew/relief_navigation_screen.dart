import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/theme.dart';
import '../../core/utils/haversine.dart';
import '../../models/emergency_request.dart';
import '../../models/relief_request.dart';
import '../../providers/ambulance_auth_provider.dart';
import '../../providers/hospital_providers.dart';
import '../../providers/location_providers.dart';
import '../../providers/relief_providers.dart';
import '../../providers/request_providers.dart';

class ReliefNavigationScreen extends ConsumerStatefulWidget {
  final String reliefRequestId;

  const ReliefNavigationScreen({
    super.key,
    required this.reliefRequestId,
  });

  @override
  ConsumerState<ReliefNavigationScreen> createState() =>
      _ReliefNavigationScreenState();
}

class _ReliefNavigationScreenState
    extends ConsumerState<ReliefNavigationScreen> {
  late final MapController _mapController;

  // Route & ETA calculation
  List<LatLng> _routePoints = [];
  bool _isDashedFallback = false;
  int? _etaMinutes;
  double? _distanceKm;

  bool _isProcessing = false;
  Timer? _routeRefreshTimer;
  StreamSubscription<EmergencyRequest?>? _requestSub;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startReliefTelemetryPublishing();
    });

    _routeRefreshTimer = Timer.periodic(const Duration(seconds: 25), (_) {
      if (mounted) _recomputeRoute();
    });
  }

  @override
  void dispose() {
    _routeRefreshTimer?.cancel();
    _requestSub?.cancel();
    _mapController.dispose();
    // Stop publishing relief telemetry and delete doc
    ref.read(liveLocationServiceProvider).stopPublishing(deleteDoc: true);
    super.dispose();
  }

  void _startReliefTelemetryPublishing() {
    final liveService = ref.read(liveLocationServiceProvider);
    final myAmb = ref.read(currentAmbulanceProvider).value;
    final myAmbId = myAmb?.ambulanceId ?? 'BL-AMB-HERO';

    liveService.startPublishing(
      requestId: widget.reliefRequestId,
      hospitalId: '',
      ambulanceId: myAmbId,
      customDocId: 'relief_${widget.reliefRequestId}',
      reliefRequestId: widget.reliefRequestId,
    );
  }

  void _listenToTripState(ReliefRequest relief) {
    if (_requestSub != null) return;
    final firestoreService = ref.read(firestoreServiceProvider);
    _requestSub = firestoreService
        .streamRequest(relief.originalRequestId)
        .listen((req) {
      if (!mounted || req == null) return;
      // Edge Case 1: Nurse marked patient Arrived while relief is en route
      if (req.status == 'arrived') {
        _handleEmergencyFinalized(
          'Patient Marked Arrived',
          'The hospital station has finalized admission for this patient. Your relief assistance is complete.',
        );
      }
    });
  }

  void _handleEmergencyFinalized(String title, String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              context.go('/crew/home');
            },
            child: const Text('Return to Fleet Dashboard'),
          ),
        ],
      ),
    );
  }

  Future<void> _makeCall(String phone) async {
    final cleanPhone = phone.replaceAll(RegExp(r'[^\d+]'), '');
    if (cleanPhone.isEmpty) return;
    final Uri uri = Uri.parse('tel:$cleanPhone');
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      }
    } catch (_) {}
  }

  Future<void> _openGoogleMaps(double lat, double lng, String name) async {
    final encodedName = Uri.encodeComponent(name);
    final Uri mapsDirUri = Uri.parse(
        'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&destination_place_id=$encodedName');
    final Uri geoUri = Uri.parse('geo:$lat,$lng?q=$lat,$lng($encodedName)');

    try {
      if (await canLaunchUrl(mapsDirUri)) {
        await launchUrl(mapsDirUri, mode: LaunchMode.externalApplication);
      } else if (await canLaunchUrl(geoUri)) {
        await launchUrl(geoUri);
      }
    } catch (_) {}
  }

  Future<void> _recomputeRoute() async {
    final reliefAsync = ref.read(reliefRequestStreamProvider(widget.reliefRequestId));
    final relief = reliefAsync.value;
    if (relief == null) return;

    final disabledLocAsync = ref.read(liveLocationStreamProvider(relief.originalRequestId));
    final disabledLoc = disabledLocAsync.value;

    final disabledLat = disabledLoc?.lat ?? relief.disabledLat;
    final disabledLng = disabledLoc?.lng ?? relief.disabledLng;

    final myLoc = ref.read(liveLocationServiceProvider).lastPublishedLocation;
    if (myLoc == null || disabledLat == 0.0) return;

    final routingService = ref.read(routingServiceProvider);
    final routeResult = await routingService.getDrivingRouteWithGeometry(
      startLat: myLoc.lat,
      startLng: myLoc.lng,
      endLat: disabledLat,
      endLng: disabledLng,
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

  @override
  Widget build(BuildContext context) {
    final reliefAsync = ref.watch(reliefRequestStreamProvider(widget.reliefRequestId));

    return reliefAsync.when(
      data: (relief) {
        if (relief == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Relief Navigation')),
            body: const Center(child: Text('Relief request not found.')),
          );
        }

        // Edge Case 2: Requester cancelled after acceptance
        if (relief.status == 'cancelled') {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _handleEmergencyFinalized(
              'Relief Request Cancelled',
              'The disabled ambulance vehicle is running again or the requester cancelled assistance. Your status is restored to Available.',
            );
          });
        }

        _listenToTripState(relief);

        // Disabled ambulance coordinates
        final disabledLiveAsync = ref.watch(liveLocationStreamProvider(relief.originalRequestId));
        final disabledLive = disabledLiveAsync.value;

        final disabledLat = disabledLive?.lat ?? relief.disabledLat;
        final disabledLng = disabledLive?.lng ?? relief.disabledLng;
        final disabledPoint = LatLng(
          disabledLat != 0 ? disabledLat : 19.0760,
          disabledLng != 0 ? disabledLng : 72.8777,
        );

        // My current location
        final liveService = ref.watch(liveLocationServiceProvider);
        final myLoc = liveService.lastPublishedLocation;
        final myPoint = myLoc != null ? LatLng(myLoc.lat, myLoc.lng) : null;

        // Proximity calculation (meters)
        double distanceMeters = 9999.0;
        if (myPoint != null && disabledLat != 0.0) {
          final distKm = calculateHaversineDistance(
            myPoint.latitude,
            myPoint.longitude,
            disabledPoint.latitude,
            disabledPoint.longitude,
          );
          distanceMeters = distKm * 1000.0;
        }

        final bool isWithinProximity = distanceMeters <= 200.0;

        // Fetch route initially if empty
        if (_routePoints.isEmpty && myPoint != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _recomputeRoute();
          });
        }

        final disabledAmb = relief.requesterAmbulance;
        final driverPhone = disabledAmb.driverPhone;

        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            backgroundColor: AppColors.primaryDark,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              tooltip: 'Back to Terminal',
              onPressed: () => context.go('/crew/home'),
            ),
            title: Text('En Route to ${disabledAmb.ambulanceId}'),
            actions: [
              IconButton(
                icon: const Icon(Icons.cancel_outlined),
                tooltip: 'Abort Relief Mission',
                onPressed: _showAbortDialog,
              ),
            ],
          ),
          body: Column(
            children: [
              // -------------------------------------------------------------
              // TOP: LIVE ROUTE MAP
              // -------------------------------------------------------------
              Expanded(
                flex: 45,
                child: Stack(
                  children: [
                    FlutterMap(
                      mapController: _mapController,
                      options: MapOptions(
                        initialCenter: disabledPoint,
                        initialZoom: 14.0,
                        interactionOptions: const InteractionOptions(
                          flags: InteractiveFlag.all,
                        ),
                      ),
                      children: [
                        TileLayer(
                          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                          userAgentPackageName: 'app.bedlink.flutter',
                        ),

                        // Route Polyline
                        if (_routePoints.isNotEmpty)
                          PolylineLayer(
                            polylines: [
                              Polyline(
                                points: _routePoints,
                                strokeWidth: 5.0,
                                color: _isDashedFallback
                                    ? AppColors.textSecondary.withAlpha(160)
                                    : AppColors.info,
                                pattern: _isDashedFallback
                                    ? StrokePattern.dashed(segments: const [8, 6])
                                    : const StrokePattern.solid(),
                              ),
                            ],
                          ),

                        // Proximity Zone Circle around disabled ambulance (200m)
                        CircleLayer(
                          circles: [
                            CircleMarker(
                              point: disabledPoint,
                              radius: 200.0,
                              useRadiusInMeter: true,
                              color: AppColors.primary.withValues(alpha: 0.12),
                              borderColor: AppColors.primary,
                              borderStrokeWidth: 1.5,
                            ),
                          ],
                        ),

                        // Markers
                        MarkerLayer(
                          markers: [
                            // Disabled Ambulance Target Marker
                            Marker(
                              point: disabledPoint,
                              width: 44,
                              height: 44,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: AppColors.danger, width: 2.5),
                                  boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
                                ),
                                child: const Icon(Icons.car_crash_rounded, color: AppColors.danger, size: 24),
                              ),
                            ),

                            // My Ambulance Marker
                            if (myPoint != null)
                              Marker(
                                point: myPoint,
                                width: 44,
                                height: 44,
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    shape: BoxShape.circle,
                                    border: Border.all(color: AppColors.info, width: 2.5),
                                    boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
                                  ),
                                  child: const Icon(Icons.navigation_rounded, color: AppColors.info, size: 26),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),

                    // Top ETA & Distance Pill
                    Positioned(
                      top: 12,
                      left: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: AppColors.surface.withValues(alpha: 0.95),
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.directions_car_filled_rounded, size: 16, color: AppColors.primary),
                            const SizedBox(width: 6),
                            Text(
                              _etaMinutes != null ? '$_etaMinutes min · ${_distanceKm?.toStringAsFixed(1)} km' : 'Calculating ETA...',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: AppColors.primaryDark,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Re-center FAB
                    Positioned(
                      right: 12,
                      bottom: 12,
                      child: FloatingActionButton.small(
                        heroTag: 'recenter_nav',
                        backgroundColor: AppColors.surface,
                        onPressed: () {
                          if (myPoint != null) {
                            final bounds = LatLngBounds.fromPoints([disabledPoint, myPoint]);
                            _mapController.fitCamera(
                              CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(36)),
                            );
                          } else {
                            _mapController.move(disabledPoint, 14.0);
                          }
                        },
                        child: const Icon(Icons.center_focus_strong_rounded, color: AppColors.primary),
                      ),
                    ),
                  ],
                ),
              ),

              // -------------------------------------------------------------
              // BOTTOM: TARGET DETAILS & ACTIONS
              // -------------------------------------------------------------
              Expanded(
                flex: 55,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Target Ambulance Info Card
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: AppColors.dangerTint,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Icon(Icons.report_problem_rounded, color: AppColors.danger, size: 24),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Disabled: ${disabledAmb.ambulanceId}',
                                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                        ),
                                        Text(
                                          '${disabledAmb.vehicleNumber} · ${relief.formattedReason}',
                                          style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: AppColors.dangerTint,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      relief.severity.toUpperCase(),
                                      style: const TextStyle(
                                        color: AppColors.danger,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const Divider(height: 20),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text('Driver Name:', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                                  Text(
                                    disabledAmb.driverName.isNotEmpty ? disabledAmb.driverName : 'Crew Paramedic',
                                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text('Patient Bed Needs:', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                                  Text(
                                    relief.needs.join(", "),
                                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.primary),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Navigation & Driver Call Buttons
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () => _openGoogleMaps(
                                disabledPoint.latitude,
                                disabledPoint.longitude,
                                'Disabled Ambulance ${disabledAmb.ambulanceId}',
                              ),
                              icon: const Icon(Icons.navigation_rounded),
                              label: const Text('Navigate'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.info,
                                minimumSize: const Size.fromHeight(48),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: driverPhone.isNotEmpty
                                  ? () => _makeCall(driverPhone)
                                  : null,
                              icon: const Icon(Icons.call_rounded),
                              label: const Text('Call Driver'),
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size.fromHeight(48),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      // Proximity Status Indicator
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: isWithinProximity ? AppColors.successTint : AppColors.background,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isWithinProximity ? AppColors.success : AppColors.divider,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              isWithinProximity ? Icons.check_circle_rounded : Icons.radar_rounded,
                              size: 18,
                              color: isWithinProximity ? AppColors.success : AppColors.primary,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                isWithinProximity
                                    ? 'Within arrival range (~${distanceMeters.toStringAsFixed(0)}m). You can confirm Help Reached.'
                                    : 'Approaching disabled vehicle (${distanceMeters > 5000 ? "> 5 km" : "${distanceMeters.toStringAsFixed(0)}m away"}).',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: isWithinProximity ? AppColors.success : AppColors.textSecondary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),

                      // "Help Reached" Button (Blue / Success)
                      ElevatedButton.icon(
                        onPressed: _isProcessing
                            ? null
                            : (isWithinProximity
                                ? () => _confirmHelpReached(isOverride: false)
                                : () => _confirmHelpReachedOverride()),
                        icon: _isProcessing
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.handshake_rounded, size: 24),
                        label: Text(
                          isWithinProximity ? 'Help Reached (Confirm Handover)' : 'I Am Here (Arrival Override)',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size.fromHeight(56),
                          backgroundColor: isWithinProximity ? AppColors.info : AppColors.primaryDark,
                          elevation: 3,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
      loading: () => Scaffold(
        appBar: AppBar(title: const Text('Connecting to Navigation...')),
        body: const Center(child: CircularProgressIndicator(color: AppColors.primary)),
      ),
      error: (err, _) => Scaffold(
        appBar: AppBar(title: const Text('Relief Navigation')),
        body: Center(child: Text('Error: $err')),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // HANDOVER & ABORT FLOWS
  // ---------------------------------------------------------------------------

  Future<void> _confirmHelpReached({required bool isOverride}) async {
    setState(() => _isProcessing = true);
    try {
      final result = await ref.read(reliefServiceProvider).confirmHelpReached(
            reliefRequestId: widget.reliefRequestId,
            override: isOverride,
          );

      if (result.success) {
        // Stop relief telemetry publishing
        await ref.read(liveLocationServiceProvider).stopPublishing(deleteDoc: true);

        // Switch active trip to the handed-over emergency request!
        final targetReqId = result.originalRequestId;
        if (targetReqId != null) {
          ref.read(selectedRequestIdProvider.notifier).select(targetReqId);
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✓ Patient Handover Complete! You now own this emergency trip.'),
              backgroundColor: AppColors.success,
              duration: Duration(seconds: 4),
            ),
          );
          // Relief crew now views the existing HoldStatusScreen for this request
          context.go('/dispatch/hold');
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to confirm handover: ${result.message}'),
              backgroundColor: AppColors.danger,
            ),
          );
        }
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  void _confirmHelpReachedOverride() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.location_on_outlined, size: 36, color: AppColors.warning),
        title: const Text('Confirm Arrival Override?'),
        content: const Text(
          'GPS reports you are outside the 200m zone. If you have physically reached the disabled vehicle and patient, you can proceed with an arrival override.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _confirmHelpReached(isOverride: true);
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            child: const Text('I Am Here (Proceed)'),
          ),
        ],
      ),
    );
  }

  void _showAbortDialog() {
    String selectedReason = 'vehicle_issue';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) {
          return AlertDialog(
            title: const Text('Abort Relief Mission?'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'The request will be returned to searching so another ambulance can be alerted. Select reason:',
                  style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 12),
                DropdownButton<String>(
                  value: selectedReason,
                  isExpanded: true,
                  items: const [
                    DropdownMenuItem(value: 'vehicle_issue', child: Text('Vehicle / Mechanical Issue')),
                    DropdownMenuItem(value: 'traffic_block', child: Text('Dense Traffic / Gridlock')),
                    DropdownMenuItem(value: 'starting_trip', child: Text('Assigned Higher Priority Emergency')),
                    DropdownMenuItem(value: 'crew_unavailable', child: Text('Crew Incapacitation')),
                  ],
                  onChanged: (val) {
                    if (val != null) setDialogState(() => selectedReason = val);
                  },
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogCtx),
                child: const Text('Keep Helping'),
              ),
              ElevatedButton(
                onPressed: () async {
                  Navigator.pop(dialogCtx);
                  await ref.read(reliefServiceProvider).cancelReliefRequest(
                        reliefRequestId: widget.reliefRequestId,
                      );
                  if (mounted) {
                    context.go('/crew/home');
                  }
                },
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
                child: const Text('Abort Mission'),
              ),
            ],
          );
        },
      ),
    );
  }
}
