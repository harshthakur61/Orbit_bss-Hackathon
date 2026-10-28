import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/theme.dart';
import '../../core/utils/haversine.dart';
import '../../core/widgets/countdown_ring.dart';
import '../../models/emergency_request.dart';
import '../../models/hospital.dart';
import '../../models/relief_request.dart';
import '../../providers/hospital_providers.dart';
import '../../providers/location_providers.dart';
import '../../providers/relief_providers.dart';
import '../../providers/request_providers.dart';

class ReliefStatusScreen extends ConsumerStatefulWidget {
  final String? reliefRequestId;

  const ReliefStatusScreen({
    super.key,
    this.reliefRequestId,
  });

  @override
  ConsumerState<ReliefStatusScreen> createState() => _ReliefStatusScreenState();
}

class _ReliefStatusScreenState extends ConsumerState<ReliefStatusScreen>
    with TickerProviderStateMixin {
  late final MapController _mapController;
  late final AnimationController _pulseController;
  late final AnimationController _staggerController;

  // Relief approaching live route state
  List<LatLng> _routePoints = [];
  bool _isDashedFallback = false;
  int? _routeEtaMinutes;
  double? _routeDistanceKm;
  DateTime? _lastRouteFetchTime;
  LatLng? _lastReliefPoint;

  // Freshness check periodic timer
  Timer? _freshnessTimer;
  bool _waveAdvancing = false;
  int _lastWaveToasted = -1;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat();

    _staggerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..forward();

    _freshnessTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (mounted) setState(() {});
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ensureTelemetryRunning();
    });
  }

  @override
  void dispose() {
    _freshnessTimer?.cancel();
    _pulseController.dispose();
    _staggerController.dispose();
    _mapController.dispose();
    super.dispose();
  }

  /// Ensure disabled ambulance continues broadcasting its own GPS coordinates
  /// during relief search and approach so nurse station and relief crew can track it.
  void _ensureTelemetryRunning() {
    final liveService = ref.read(liveLocationServiceProvider);
    final req = ref.read(currentRequestProvider).value;
    if (req != null && !liveService.isPublishing && !liveService.isSimulating) {
      final ambId = req.ambulance?.ambulanceId.isNotEmpty == true
          ? req.ambulance!.ambulanceId
          : (req.crewUid ?? 'AMB-DISABLED');
      liveService.startPublishing(
        requestId: req.id,
        hospitalId: req.currentHospitalId,
        ambulanceId: ambId,
      );
    }
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

  Future<void> _fetchReliefRouteIfNeeded({
    required LatLng reliefPoint,
    required LatLng disabledPoint,
    bool force = false,
  }) async {
    final now = DateTime.now();
    final elapsedSec = _lastRouteFetchTime == null
        ? 999
        : now.difference(_lastRouteFetchTime!).inSeconds;

    final distanceSinceFetchKm = _lastReliefPoint == null
        ? 999.0
        : calculateHaversineDistance(
            _lastReliefPoint!.latitude,
            _lastReliefPoint!.longitude,
            reliefPoint.latitude,
            reliefPoint.longitude,
          );

    if (!force && elapsedSec < 30 && distanceSinceFetchKm < 0.25) {
      return;
    }

    _lastRouteFetchTime = now;
    _lastReliefPoint = reliefPoint;

    final routingService = ref.read(routingServiceProvider);
    final routeResult = await routingService.getDrivingRouteWithGeometry(
      startLat: reliefPoint.latitude,
      startLng: reliefPoint.longitude,
      endLat: disabledPoint.latitude,
      endLng: disabledPoint.longitude,
    );

    if (mounted) {
      setState(() {
        _routePoints = routeResult.points;
        _isDashedFallback = !routeResult.isOsrm;
        _routeEtaMinutes = routeResult.travelMinutes;
        _routeDistanceKm = routeResult.distanceKm;
      });
    }
  }

  void _recenterMap(LatLng center, {double zoom = 13.0}) {
    try {
      _mapController.move(center, zoom);
    } catch (_) {}
  }

  void _fitWaveRadius(LatLng center, int radiusKm) {
    try {
      // Approximate delta degrees for wave radius
      final latDelta = (radiusKm * 1000) / 111320.0;
      final bounds = LatLngBounds(
        LatLng(center.latitude - latDelta, center.longitude - latDelta),
        LatLng(center.latitude + latDelta, center.longitude + latDelta),
      );
      _mapController.fitCamera(
        CameraFit.bounds(
          bounds: bounds,
          padding: const EdgeInsets.all(24),
        ),
      );
    } catch (_) {}
  }

  void _checkWaveTimeout(ReliefRequest relief) async {
    if (relief.status != 'searching') return;
    if (relief.isExpired && !_waveAdvancing) {
      _waveAdvancing = true;
      try {
        final result = await ref
            .read(reliefServiceProvider)
            .advanceReliefWave(reliefRequestId: relief.id);

        if (result.success && mounted) {
          final nextWave = relief.wave + 1;
          final nextRadius = nextWave == 1 ? 10 : (nextWave == 2 ? 15 : 15);
          if (_lastWaveToasted != nextWave) {
            _lastWaveToasted = nextWave;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Expanding search to $nextRadius km (Wave ${nextWave + 1} of 3)'),
                backgroundColor: AppColors.primary,
                duration: const Duration(seconds: 3),
              ),
            );
          }
        }
      } finally {
        if (mounted) _waveAdvancing = false;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final activeRequestAsync = ref.watch(currentRequestProvider);
    final hospitalsAsync = ref.watch(hospitalsStreamProvider);

    final req = activeRequestAsync.value;
    final resolvedReliefId = widget.reliefRequestId ?? req?.reliefRequestId;

    if (resolvedReliefId == null || resolvedReliefId.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Relief Radar')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.emergency_outlined, size: 56, color: AppColors.textSecondary),
              const SizedBox(height: 16),
              const Text('No active relief request found.'),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => context.pop(),
                child: const Text('Return to Trip'),
              ),
            ],
          ),
        ),
      );
    }

    final reliefAsync = ref.watch(reliefRequestStreamProvider(resolvedReliefId));
    final offersAsync = ref.watch(reliefOffersStreamProvider(resolvedReliefId));
    final reliefLiveAsync = ref.watch(reliefLiveLocationStreamProvider(resolvedReliefId));

    return reliefAsync.when(
      data: (relief) {
        if (relief == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Relief Status')),
            body: const Center(child: Text('Relief request not found.')),
          );
        }

        // Automatic wave timeout evaluation
        if (relief.status == 'searching') {
          _checkWaveTimeout(relief);
        }

        final List<Hospital> hospitals = hospitalsAsync.value ?? [];
        Hospital? hospital;
        if (req != null) {
          try {
            hospital = hospitals.firstWhere((h) => h.id == req.currentHospitalId);
          } catch (_) {}
        }
        final hospitalName = hospital?.name ?? 'Assigned Hospital';

        // Coordinates resolution
        final disabledPoint = LatLng(
          relief.disabledLat != 0 ? relief.disabledLat : 19.0760,
          relief.disabledLng != 0 ? relief.disabledLng : 72.8777,
        );

        final candidateOffers = offersAsync.value ?? [];
        final reliefLiveLoc = reliefLiveAsync.value;

        // Trigger route fetch if accepted
        if (relief.status == 'accepted' && reliefLiveLoc != null) {
          final reliefPoint = LatLng(reliefLiveLoc.lat, reliefLiveLoc.lng);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _fetchReliefRouteIfNeeded(
              reliefPoint: reliefPoint,
              disabledPoint: disabledPoint,
            );
          });
        }

        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            backgroundColor: AppColors.primaryDark,
            title: Text(
              relief.status == 'accepted'
                  ? 'Relief Ambulance En Route'
                  : (relief.status == 'completed'
                      ? 'Patient Handed Over'
                      : 'Relief Search Radar'),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            automaticallyImplyLeading: relief.status != 'searching',
            leading: relief.status == 'searching'
                ? IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () => context.pop(),
                    tooltip: 'Back to trip',
                  )
                : null,
          ),
          body: Column(
            children: [
              // -------------------------------------------------------------
              // TOP 30%: FLUTTER MAP
              // -------------------------------------------------------------
              Expanded(
                flex: 30,
                child: Stack(
                  children: [
                    FlutterMap(
                      mapController: _mapController,
                      options: MapOptions(
                        initialCenter: disabledPoint,
                        initialZoom: 13.0,
                        interactionOptions: const InteractionOptions(
                          flags: InteractiveFlag.all,
                        ),
                        onMapReady: () {
                          if (relief.status == 'searching') {
                            _fitWaveRadius(disabledPoint, relief.radiusKm);
                          }
                        },
                      ),
                      children: [
                        TileLayer(
                          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                          userAgentPackageName: 'app.bedlink.flutter',
                        ),

                        // Route Polyline (When accepted)
                        if (relief.status == 'accepted' && _routePoints.isNotEmpty)
                          PolylineLayer(
                            polylines: [
                              Polyline(
                                points: _routePoints,
                                strokeWidth: 4.5,
                                color: AppColors.primary,
                                pattern: _isDashedFallback
                                  ? StrokePattern.dashed(segments: const [8, 6])
                                  : const StrokePattern.solid(),
                              ),
                            ],
                          ),

                        // Radar pulse circle & Wave Radius Circle (When searching)
                        if (relief.status == 'searching')
                          CircleLayer(
                            circles: [
                              // Pulsing radar animation
                              CircleMarker(
                                point: disabledPoint,
                                radius: 25.0 + (_pulseController.value * 45.0),
                                useRadiusInMeter: false,
                                color: AppColors.primary.withValues(alpha: 0.3 * (1.0 - _pulseController.value)),
                                borderColor: AppColors.primary,
                                borderStrokeWidth: 1.5,
                              ),
                              // Wave Radius Circle
                              CircleMarker(
                                point: disabledPoint,
                                radius: relief.radiusKm * 1000.0,
                                useRadiusInMeter: true,
                                color: AppColors.primary.withValues(alpha: 0.06),
                                borderColor: AppColors.primary,
                                borderStrokeWidth: 1.5,
                              ),
                            ],
                          ),

                        // Markers Layer
                        MarkerLayer(
                          markers: [
                            // 1. My Disabled Ambulance Marker
                            Marker(
                              point: disabledPoint,
                              width: 44,
                              height: 44,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: AppColors.danger, width: 2.5),
                                  boxShadow: const [
                                    BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2)),
                                  ],
                                ),
                                child: const Icon(Icons.car_crash_rounded, color: AppColors.danger, size: 24),
                              ),
                            ),

                            // 2. Candidate Ambulance Markers (Searching)
                            if (relief.status == 'searching')
                              ...candidateOffers.map((c) {
                                Color markerColor;
                                switch (c.status.toLowerCase()) {
                                  case 'accepted':
                                    markerColor = AppColors.success;
                                    break;
                                  case 'rejected':
                                  case 'expired':
                                  case 'taken':
                                    markerColor = Colors.grey.shade500;
                                    break;
                                  case 'pending':
                                  default:
                                    markerColor = AppColors.primary;
                                }

                                return Marker(
                                  point: LatLng(c.lat, c.lng),
                                  width: 32,
                                  height: 32,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      shape: BoxShape.circle,
                                      border: Border.all(color: markerColor, width: 2.0),
                                      boxShadow: const [
                                        BoxShadow(color: Colors.black12, blurRadius: 3),
                                      ],
                                    ),
                                    child: Icon(Icons.airport_shuttle_rounded, color: markerColor, size: 18),
                                  ),
                                );
                              }),

                            // 3. Approaching Relief Ambulance Marker (Accepted)
                            if (relief.status == 'accepted' && reliefLiveLoc != null)
                              Marker(
                                point: LatLng(reliefLiveLoc.lat, reliefLiveLoc.lng),
                                width: 44,
                                height: 44,
                                child: Transform.rotate(
                                  angle: (reliefLiveLoc.heading * (math.pi / 180.0)),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      shape: BoxShape.circle,
                                      border: Border.all(color: AppColors.success, width: 2.5),
                                      boxShadow: const [
                                        BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2)),
                                      ],
                                    ),
                                    child: const Icon(Icons.navigation_rounded, color: AppColors.success, size: 26),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),

                    // Top Wave Badge or Freshness Badge
                    Positioned(
                      top: 12,
                      left: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppColors.surface.withValues(alpha: 0.92),
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)],
                        ),
                        child: relief.status == 'accepted'
                            ? _buildReliefFreshnessPill(reliefLiveLoc)
                            : Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.radar_rounded, size: 14, color: AppColors.primary),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Radar: ${relief.radiusKm} km radius',
                                    style: const TextStyle(
                                      fontSize: 12,
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
                      child: Material(
                        color: AppColors.surface,
                        elevation: 3,
                        borderRadius: BorderRadius.circular(20),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(20),
                          onTap: () {
                            if (relief.status == 'searching') {
                              _fitWaveRadius(disabledPoint, relief.radiusKm);
                            } else if (reliefLiveLoc != null) {
                              final p1 = LatLng(reliefLiveLoc.lat, reliefLiveLoc.lng);
                              final bounds = LatLngBounds.fromPoints([disabledPoint, p1]);
                              _mapController.fitCamera(
                                CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(32)),
                              );
                            } else {
                              _recenterMap(disabledPoint);
                            }
                          },
                          child: const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.center_focus_strong_rounded, size: 16, color: AppColors.primary),
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

              // -------------------------------------------------------------
              // BOTTOM 70%: RELIEF DETAILS & CANDIDATES PANEL
              // -------------------------------------------------------------
              Expanded(
                flex: 70,
                child: Container(
                  color: AppColors.background,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Compact Main Trip Context Banner
                        _buildTripContextBanner(req, hospitalName),
                        const SizedBox(height: 12),

                        // STATE 1: SEARCHING FOR CANDIDATES
                        if (relief.status == 'searching') ...[
                          _buildSearchingPanel(relief, candidateOffers),
                        ],

                        // STATE 2: NO AMBULANCE AVAILABLE
                        if (relief.status == 'no_ambulance') ...[
                          _buildNoAmbulancePanel(relief),
                        ],

                        // STATE 3: RELIEF AMBULANCE ACCEPTED & APPROACHING
                        if (relief.status == 'accepted') ...[
                          _buildAcceptedPanel(relief, reliefLiveLoc),
                        ],

                        // STATE 4: HANDOVER COMPLETED (Phase 12E)
                        if (relief.status == 'completed') ...[
                          _buildCompletedPanel(relief, req),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
      loading: () => Scaffold(
        appBar: AppBar(title: const Text('Connecting to Relief Engine...')),
        body: const Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
      ),
      error: (err, _) => Scaffold(
        appBar: AppBar(title: const Text('Relief Error')),
        body: Center(child: Text('Error loading relief state: $err')),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // SUB-PANELS
  // ---------------------------------------------------------------------------

  Widget _buildTripContextBanner(EmergencyRequest? req, String hospitalName) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          const Icon(Icons.local_hospital_rounded, size: 20, color: AppColors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Hospital: $hospitalName',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  'Bed held: ${req?.needs.join(", ") ?? "ICU"} · Severity: ${(req?.severity ?? "serious").toUpperCase()}',
                  style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.successTint,
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Text(
              'BED HELD',
              style: TextStyle(
                color: AppColors.success,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchingPanel(
    ReliefRequest relief,
    List<ReliefCandidateOffer> offers,
  ) {
    final waveNum = relief.wave + 1; // 1-indexed

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Wave Header & Countdown
        Card(
          elevation: 2,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Finding a relief ambulance',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Searching within ${relief.radiusKm} km · Wave $waveNum of 3',
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Reason: ${relief.formattedReason}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                CountdownRing(
                  offerExpiresAt: relief.offerExpiresAt,
                  totalDurationSeconds: 60,
                  onExpired: () => _checkWaveTimeout(relief),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Count Header
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Alerted ${offers.length} ambulances nearby',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            if (_waveAdvancing)
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
              ),
          ],
        ),
        const SizedBox(height: 8),

        // Candidate Offers List
        if (offers.isEmpty)
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.divider),
            ),
            child: const Center(
              child: Text(
                'Contacting eligible AIS-125 ambulances in range...',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
            ),
          )
        else
          ...offers.map((offer) => _buildCandidateOfferRow(offer)),

        const SizedBox(height: 20),

        // Cancel Relief Button
        OutlinedButton(
          onPressed: () => _confirmCancelRelief(relief.id),
          style: OutlinedButton.styleFrom(
            side: const BorderSide(color: AppColors.divider),
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          child: const Text(
            'Vehicle running again? Cancel relief',
            style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }

  Widget _buildCandidateOfferRow(ReliefCandidateOffer offer) {
    Color chipBg;
    Color chipText;
    String statusLabel;

    switch (offer.status.toLowerCase()) {
      case 'accepted':
        chipBg = AppColors.successTint;
        chipText = AppColors.success;
        statusLabel = 'Accepted';
        break;
      case 'rejected':
        chipBg = Colors.grey.shade100;
        chipText = Colors.grey.shade700;
        final reason = offer.reason != null ? ' · ${offer.reason!.replaceAll('_', ' ')}' : '';
        statusLabel = 'Rejected$reason';
        break;
      case 'expired':
        chipBg = Colors.grey.shade100;
        chipText = Colors.grey.shade600;
        statusLabel = 'Expired';
        break;
      case 'taken':
        chipBg = Colors.grey.shade100;
        chipText = Colors.grey.shade600;
        statusLabel = 'Taken';
        break;
      case 'pending':
      default:
        chipBg = AppColors.primaryTint;
        chipText = AppColors.primaryDark;
        statusLabel = 'Alerted';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.primaryTint,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.airport_shuttle_rounded, size: 20, color: AppColors.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  offer.ambulanceId,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 2),
                Text(
                  '${offer.formattedTier} · ${offer.distanceKm.toStringAsFixed(1)} km away',
                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: chipBg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              statusLabel,
              style: TextStyle(
                color: chipText,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoAmbulancePanel(ReliefRequest relief) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.danger,
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Column(
            children: [
              Icon(Icons.report_problem_rounded, color: Colors.white, size: 48),
              SizedBox(height: 10),
              Text(
                'No ambulance available nearby',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: 6),
              Text(
                'All candidate ambulances in the 15 km perimeter are busy, unverified, or out of range.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        ElevatedButton.icon(
          onPressed: () async {
            await ref.read(reliefServiceProvider).createReliefRequest(
                  originalRequestId: relief.originalRequestId,
                  reason: relief.reason,
                );
          },
          icon: const Icon(Icons.refresh_rounded, size: 22),
          label: const Text('Retry Search', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            minimumSize: const Size.fromHeight(52),
          ),
        ),
        const SizedBox(height: 12),

        ElevatedButton.icon(
          onPressed: () => _makeCall('108'),
          icon: const Icon(Icons.phone_in_talk_rounded, size: 22),
          label: const Text('Call 108 Emergency Control', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.danger,
            minimumSize: const Size.fromHeight(52),
          ),
        ),
      ],
    );
  }

  Widget _buildAcceptedPanel(
    ReliefRequest relief,
    AmbulanceLiveLocation? loc,
  ) {
    final acceptedAmb = relief.acceptedAmbulance;
    final driverName = acceptedAmb?.driverName.isNotEmpty == true
        ? acceptedAmb!.driverName
        : 'Relief Paramedic';
    final ambulanceId = acceptedAmb?.ambulanceId.isNotEmpty == true
        ? acceptedAmb!.ambulanceId
        : 'BL-AMB-HERO';
    final tier = acceptedAmb?.ais125Tier ?? 'Type B';
    final vehicleNum = acceptedAmb?.vehicleNumber ?? '';
    final phone = acceptedAmb?.driverPhone ?? '';

    final isSignalLost = _isSignalLost(loc);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Hero Arrival Banner
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.successTint,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.success),
          ),
          child: const Row(
            children: [
              Icon(Icons.health_and_safety_rounded, color: AppColors.success, size: 32),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Help is on the way.',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppColors.success,
                      ),
                    ),
                    Text(
                      'Stay with the patient. Relief crew is en route.',
                      style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Relief Crew Profile Card
        Card(
          elevation: 2,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.primaryTint,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.airport_shuttle_rounded, color: AppColors.primary, size: 28),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            driverName,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                          Text(
                            '$ambulanceId · $tier',
                            style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                          ),
                          if (vehicleNum.isNotEmpty)
                            Text(
                              vehicleNum,
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                            ),
                        ],
                      ),
                    ),
                    if (phone.isNotEmpty)
                      IconButton.filledTonal(
                        onPressed: () => _makeCall(phone),
                        icon: const Icon(Icons.phone_in_talk_rounded),
                        tooltip: 'Call Relief Driver',
                        style: IconButton.styleFrom(
                          backgroundColor: AppColors.successTint,
                          foregroundColor: AppColors.success,
                        ),
                      ),
                  ],
                ),
                const Divider(height: 24),

                // ETA & Distance
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    Column(
                      children: [
                        const Text('ESTIMATED ARRIVAL', style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                        const SizedBox(height: 4),
                        Text(
                          _routeEtaMinutes != null ? '$_routeEtaMinutes min' : '-- min',
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.primary),
                        ),
                      ],
                    ),
                    Container(width: 1, height: 32, color: AppColors.divider),
                    Column(
                      children: [
                        const Text('DISTANCE', style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                        const SizedBox(height: 4),
                        Text(
                          _routeDistanceKm != null ? '${_routeDistanceKm!.toStringAsFixed(1)} km' : '-- km',
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.primary),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Signal Lost Warning & Re-broadcast action (Requirement 5)
        if (isSignalLost) ...[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.grey.shade400),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(Icons.wifi_off_rounded, color: Colors.grey.shade700, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'Signal lost (> 60s without telemetry)',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: Colors.grey.shade800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                const Text(
                  'The approaching ambulance has stopped transmitting coordinates. You can cancel acceptance and re-broadcast to nearby crews.',
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 10),
                ElevatedButton(
                  onPressed: () async {
                    await ref.read(reliefServiceProvider).cancelReliefRequest(
                          reliefRequestId: relief.id,
                          action: 'find_another',
                        );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    minimumSize: const Size.fromHeight(40),
                  ),
                  child: const Text('Find Another Ambulance'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],

        // Cancel Relief Option
        OutlinedButton(
          onPressed: () => _confirmCancelRelief(relief.id),
          child: const Text('Cancel Relief Request (Vehicle Running Again)'),
        ),
      ],
    );
  }

  Widget _buildCompletedPanel(ReliefRequest relief, EmergencyRequest? req) {
    final handover = req?.handover;
    final toAmbId = handover?.toAmbulanceId ?? relief.acceptedAmbulance?.ambulanceId ?? 'BL-AMB-RELIEF';
    final handoverTime = handover != null
        ? DateFormat('HH:mm · dd MMM yyyy').format(handover.at)
        : 'Just now';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: const BoxDecoration(
              color: AppColors.successTint,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.handshake_rounded, size: 40, color: AppColors.success),
          ),
          const SizedBox(height: 16),
          const Text(
            'Patient Successfully Handed Over',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.primaryDark,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Patient has been transferred to relief ambulance $toAmbId. The relief crew is now continuing transit to the hospital.',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
          const Divider(height: 24),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Handover Completed At:', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
              Text(handoverTime, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Relief Ambulance ID:', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
              Text(toAmbId, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.primary)),
            ],
          ),
          const SizedBox(height: 24),

          ElevatedButton(
            onPressed: () {
              ref.read(selectedRequestIdProvider.notifier).select(null);
              context.go('/crew/home');
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              minimumSize: const Size.fromHeight(48),
            ),
            child: const Text('Return to Crew Fleet Dashboard'),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // HELPERS
  // ---------------------------------------------------------------------------

  bool _isSignalLost(AmbulanceLiveLocation? loc) {
    if (loc == null || loc.updatedAt == null) return false;
    final ageSeconds = DateTime.now().difference(loc.updatedAt!).inSeconds;
    return ageSeconds > 60;
  }

  Widget _buildReliefFreshnessPill(AmbulanceLiveLocation? loc) {
    Color dotColor;
    String label;

    if (loc == null || loc.updatedAt == null) {
      dotColor = AppColors.textSecondary;
      label = 'Waiting for relief location...';
    } else {
      final age = DateTime.now().difference(loc.updatedAt!).inSeconds;
      if (age < 20) {
        dotColor = AppColors.success;
        label = 'Live';
      } else if (age <= 60) {
        dotColor = AppColors.warning;
        label = 'Delayed (${age}s)';
      } else {
        dotColor = Colors.grey.shade500; // Neutral grey, NEVER red per design system
        label = 'Signal lost';
      }
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: dotColor == Colors.grey.shade500 ? Colors.grey.shade700 : AppColors.textPrimary,
          ),
        ),
      ],
    );
  }

  void _confirmCancelRelief(String reliefRequestId) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel Relief Request?'),
        content: const Text(
          'Vehicle running again? This will cancel the relief assistance and return candidates to active fleet.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Keep Relief Active'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final result = await ref
                  .read(reliefServiceProvider)
                  .cancelReliefRequest(reliefRequestId: reliefRequestId);
              if (result.success && mounted) {
                context.pop();
              }
            },
            child: const Text('Cancel Request'),
          ),
        ],
      ),
    );
  }
}
