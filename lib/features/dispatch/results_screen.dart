import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/theme.dart';
import '../../core/constants.dart';
import '../../core/utils/time_ago.dart';
import '../../core/widgets/freshness_badge.dart';
import '../../models/hospital.dart';
import '../../models/emergency_request.dart';
import '../../models/hospital_rank_result.dart';
import '../../providers/hospital_providers.dart';
import '../../providers/location_providers.dart';
import '../../providers/request_providers.dart';
import '../../providers/ambulance_auth_provider.dart';
import '../../providers/crew_presence_providers.dart';
import '../../core/constants/crew_presence_constants.dart';
import '../../services/ambulance_auth_service.dart';
import '../../services/voice_note_upload_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ResultsScreen extends ConsumerStatefulWidget {
  const ResultsScreen({super.key});

  @override
  ConsumerState<ResultsScreen> createState() => _ResultsScreenState();
}

class _ResultsScreenState extends ConsumerState<ResultsScreen> {
  bool _hideStaleHospitals = false;
  bool _isCreatingRequest = false;

  Future<void> _makeCall(String phone) async {
    final cleanPhone = phone.replaceAll(RegExp(r'[^\d+]'), '');
    final Uri phoneUri = Uri.parse('tel:$cleanPhone');
    try {
      if (await canLaunchUrl(phoneUri)) {
        await launchUrl(phoneUri);
      } else {
        _showToast('Could not launch dialer for $phone');
      }
    } catch (e) {
      _showToast('Dialer error: $e');
    }
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
      } else {
        await launchUrl(mapsDirUri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      _showToast('Navigation error: $e');
    }
  }

  void _showToast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _showScoreBreakdownSheet(HospitalRankResult result) {
    final breakdown = result.scoreBreakdown;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.analytics_outlined, color: AppColors.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Why Rank #${result.rank}? (${result.hospital.name})',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Text(
                'Lower overall score indicates a better emergency match.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
              const Divider(height: 24),

              _buildBreakdownRow(
                'Est. Travel Time (${result.travelMinutes} min)',
                '+${breakdown['travelScore']?.toStringAsFixed(1)}',
                Icons.directions_car_rounded,
              ),
              const SizedBox(height: 8),
              _buildBreakdownRow(
                'Data Staleness Penalty',
                '+${breakdown['stalenessPenalty']?.toStringAsFixed(1)}',
                Icons.access_time_rounded,
              ),
              const SizedBox(height: 8),
              _buildBreakdownRow(
                'ER Load Level Penalty (${result.hospital.loadLevel.toUpperCase()})',
                '+${breakdown['loadPenalty']?.toStringAsFixed(1)}',
                Icons.local_hospital_rounded,
              ),
              const SizedBox(height: 8),
              _buildBreakdownRow(
                'Partial Match Penalty',
                '+${breakdown['partialPenalty']?.toStringAsFixed(1)}',
                Icons.error_outline_rounded,
              ),
              const Divider(height: 24),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Final Match Score:',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    result.totalScore.toStringAsFixed(1),
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: AppColors.primaryDark,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBreakdownRow(String label, String value, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppColors.textSecondary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
      ],
    );
  }

  Future<void> _selectAndRequestHospital(HospitalRankResult result) async {
    setState(() => _isCreatingRequest = true);

    final location = ref.read(currentLocationProvider);
    final draft = ref.read(requestDraftProvider);
    final hospitalsAsync = ref.read(hospitalsStreamProvider);
    final firestoreService = ref.read(firestoreServiceProvider);

    final List<Hospital> allHospitals = hospitalsAsync.value ?? [];
    final rankingService = ref.read(rankingServiceProvider);

    final fullRankedList = await rankingService.rankHospitals(
      hospitals: allHospitals,
      patientLat: location.latitude,
      patientLng: location.longitude,
      needs: draft.needs,
      severity: draft.severity,
    );

    final rankedIds = fullRankedList.map((r) => r.hospital.id).toList();

    // Reorder rankedIds so selected hospital comes first
    rankedIds.remove(result.hospital.id);
    rankedIds.insert(0, result.hospital.id);

    final expiresAt = DateTime.now().add(const Duration(seconds: 120));

    final ambulanceAsync = ref.read(currentAmbulanceProvider);
    final amb = ambulanceAsync.value ?? AmbulanceAuthService.activeDemoAmbulance;

    final AmbulanceSnapshot? ambulanceSnapshot = amb != null
        ? AmbulanceSnapshot(
            ambulanceId: amb.ambulanceId ?? amb.applicationRef,
            vehicleNumber: amb.vehicleNumber,
            driverName: amb.driverLegalName,
            driverPhone: amb.contactNumber,
            ambulanceType: amb.ambulanceType,
            ais125Tier: amb.ais125Tier,
          )
        : null;

    final newRequestId =
        FirebaseFirestore.instance.collection('requests').doc().id;

    VoiceNoteMetadata? voiceNoteMetadata;
    String? voiceNoteStatus;

    if (draft.hasVoiceNote) {
      final uploadService = ref.read(voiceNoteUploadServiceProvider);
      voiceNoteMetadata = await uploadService.uploadVoiceNoteWithTimeout(
        requestId: newRequestId,
        filePath: draft.voiceNotePath!,
        durationSec: draft.voiceNoteDurationSec,
        sizeBytes: draft.voiceNoteSizeBytes,
        timeoutDuration: const Duration(seconds: 10),
      );

      if (voiceNoteMetadata == null) {
        voiceNoteStatus = 'arriving';
      } else {
        voiceNoteStatus = 'uploaded';
      }
    }

    final newRequest = EmergencyRequest(
      id: newRequestId,
      patientLat: location.latitude,
      patientLng: location.longitude,
      needs: draft.needs,
      severity: draft.severity,
      note: draft.note,
      status: 'offered',
      rankedHospitalIds: rankedIds,
      currentIndex: 0,
      currentHospitalId: result.hospital.id,
      offerExpiresAt: expiresAt,
      createdAt: DateTime.now(),
      attempts: [],
      crewUid: amb?.uid,
      ambulance: ambulanceSnapshot,
      ambulanceLive: null,
      voiceNote: voiceNoteMetadata,
      voiceNoteStatus: voiceNoteStatus,
    );

    try {
      final createdId =
          await firestoreService.createEmergencyRequest(newRequest);
      ref.read(selectedRequestIdProvider.notifier).select(createdId);
      ref.read(requestDraftProvider.notifier).clearVoiceNote();

      // Auto-rule: Transition crew status to Online – Busy
      if (amb != null) {
        try {
          await ref.read(crewPresenceServiceProvider).setCrewStatus(
                amb.uid,
                CrewPresenceStatus.busy,
                ambulance: amb,
                recordPrevious: true,
              );
        } catch (_) {}
      }

      if (mounted) {
        context.go('/dispatch/hold');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error creating request: $e'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isCreatingRequest = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final location = ref.watch(currentLocationProvider);
    final draft = ref.watch(requestDraftProvider);
    final hospitalsAsync = ref.watch(hospitalsStreamProvider);
    final rankingService = ref.watch(rankingServiceProvider);
    final isPatientMode = ref.watch(isPatientModeProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(isPatientMode ? 'Live Bed Availability & Ranking' : 'Ranked Hospital Matches'),
        backgroundColor: AppColors.primaryDark,
      ),
      body: hospitalsAsync.when(
        data: (hospitals) {
          return FutureBuilder<List<HospitalRankResult>>(
            future: rankingService.rankHospitals(
              hospitals: hospitals,
              patientLat: location.latitude,
              patientLng: location.longitude,
              needs: draft.needs,
              severity: draft.severity,
            ),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              final allRanked = snapshot.data!;
              final filteredRanked = _hideStaleHospitals
                  ? allRanked.where((r) {
                      final mins = TimeAgoUtil.getMinutesAgo(r.hospital.lastUpdated);
                      return mins <= AppConstants.staleMinutesCutoff;
                    }).toList()
                  : allRanked;

              final mapCenter = LatLng(location.latitude, location.longitude);

              return Column(
                children: [
                  // Top Map View
                  SizedBox(
                    height: 220,
                    child: FlutterMap(
                      options: MapOptions(
                        initialCenter: mapCenter,
                        initialZoom: 12.0,
                      ),
                      children: [
                        TileLayer(
                          urlTemplate:
                              'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                          userAgentPackageName: 'com.bedlink.bedlink',
                        ),
                        MarkerLayer(
                          markers: [
                            // Ambulance Pin
                            Marker(
                              point: mapCenter,
                              width: 36,
                              height: 36,
                              child: Container(
                                decoration: const BoxDecoration(
                                  color: AppColors.info,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.airport_shuttle_rounded,
                                  color: Colors.white,
                                  size: 22,
                                ),
                              ),
                            ),
                            // Hospital Pins
                            ...filteredRanked.map((r) {
                              return Marker(
                                point: LatLng(r.hospital.lat, r.hospital.lng),
                                width: 32,
                                height: 32,
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: r.rank == 1
                                        ? AppColors.primary
                                        : AppColors.primaryDark,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                        color: Colors.white, width: 2),
                                  ),
                                  child: Center(
                                    child: Text(
                                      '${r.rank}',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            }),
                          ],
                        ),
                      ],
                    ),
                  ),

                  if (isPatientMode)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      color: AppColors.primaryTint,
                      child: Row(
                        children: const [
                          Icon(Icons.shield_outlined, color: AppColors.primaryDark, size: 20),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Patient View Mode (Read Only): Viewing live bed counts. Bed hold dispatch is disabled so hospital inventory is undisturbed.',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: AppColors.primaryDark,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                  // Filter Header
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                    color: AppColors.surface,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Found ${filteredRanked.length} Hospitals',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        Row(
                          children: [
                            const Text(
                              'Hide stale (>60m)',
                              style: TextStyle(fontSize: 12),
                            ),
                            Switch(
                              value: _hideStaleHospitals,
                              onChanged: (val) {
                                setState(() => _hideStaleHospitals = val);
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),

                  // Hospital Cards List
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: filteredRanked.length,
                      itemBuilder: (context, index) {
                        final item = filteredRanked[index];
                        final isBestMatch = item.rank == 1;

                        return Container(
                          margin: const EdgeInsets.only(bottom: 16),
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: isBestMatch
                                  ? AppColors.primary
                                  : AppColors.divider,
                              width: isBestMatch ? 2 : 1,
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Top Header Row: Rank badge, Hospital Name, Best match pill
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      width: 32,
                                      height: 32,
                                      decoration: BoxDecoration(
                                        color: isBestMatch
                                            ? AppColors.primary
                                            : AppColors.primaryDark,
                                        shape: BoxShape.circle,
                                      ),
                                      child: Center(
                                        child: Text(
                                          '#${item.rank}',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            item.hospital.name,
                                            style: const TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                              color: AppColors.textPrimary,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            '${item.travelMinutes} min drive (${item.distanceKm.toStringAsFixed(1)} km)',
                                            style: const TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                              color: AppColors.textSecondary,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (isBestMatch)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: AppColors.primaryTint,
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                        child: const Text(
                                          'BEST MATCH',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                            color: AppColors.primaryDark,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),

                                const SizedBox(height: 12),

                                // Freshness & Load & Nurse Status Row
                                Row(
                                  children: [
                                    FreshnessBadge(
                                      lastUpdated: item.hospital.lastUpdated,
                                      compact: true,
                                    ),
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: item.hospital.isReachable
                                            ? AppColors.successTint
                                            : AppColors.dangerTint,
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: item.hospital.isReachable
                                              ? AppColors.success
                                              : AppColors.danger,
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            item.hospital.isReachable
                                                ? Icons.sensors_rounded
                                                : Icons.sensors_off_rounded,
                                            size: 11,
                                            color: item.hospital.isReachable
                                                ? AppColors.success
                                                : AppColors.danger,
                                          ),
                                          const SizedBox(width: 3),
                                          Text(
                                            item.hospital.isReachable
                                                ? 'Reachable'
                                                : 'Unreachable',
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                              color: item.hospital.isReachable
                                                  ? AppColors.success
                                                  : AppColors.danger,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: item.hospital.loadLevel == 'low'
                                            ? AppColors.successTint
                                            : (item.hospital.loadLevel == 'med'
                                                ? AppColors.warningTint
                                                : AppColors.dangerTint),
                                        borderRadius:
                                            BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        'ER ${item.hospital.loadLevel.toUpperCase()}',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: item.hospital.loadLevel == 'low'
                                              ? AppColors.success
                                              : (item.hospital.loadLevel == 'med'
                                                  ? AppColors.warningText
                                                  : AppColors.danger),
                                        ),
                                      ),
                                    ),
                                    const Spacer(),
                                    IconButton(
                                      icon: const Icon(Icons.info_outline,
                                          size: 20, color: AppColors.info),
                                      tooltip: 'Why this rank?',
                                      onPressed: () =>
                                          _showScoreBreakdownSheet(item),
                                    ),
                                  ],
                                ),

                                const SizedBox(height: 12),

                                // Bed Match Badges
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  children: item.bedAvailableMap.entries.map((e) {
                                    final hasBed = e.value > 0;
                                    return Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: hasBed
                                            ? AppColors.successTint
                                            : AppColors.dangerTint,
                                        borderRadius:
                                            BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        '${hasBed ? "✓" : "✗"} ${e.key}: ${e.value}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                          color: hasBed
                                              ? AppColors.success
                                              : AppColors.danger,
                                        ),
                                      ),
                                    );
                                  }).toList(),
                                ),

                                const SizedBox(height: 16),

                                // Actions: Ambulance Dispatch Hold vs Patient Navigation & Call
                                if (!isPatientMode)
                                  ElevatedButton.icon(
                                    onPressed: _isCreatingRequest
                                        ? null
                                        : () => _selectAndRequestHospital(item),
                                    icon: const Icon(Icons.send_rounded, size: 20),
                                    label: const Text('Select & Dispatch Request'),
                                    style: ElevatedButton.styleFrom(
                                      minimumSize: const Size.fromHeight(52),
                                      backgroundColor: isBestMatch
                                          ? AppColors.primary
                                          : AppColors.primaryDark,
                                    ),
                                  )
                                else
                                  Row(
                                    children: [
                                      Expanded(
                                        child: ElevatedButton.icon(
                                          onPressed: () => _openGoogleMaps(
                                            item.hospital.lat,
                                            item.hospital.lng,
                                            item.hospital.name,
                                          ),
                                          icon: const Icon(Icons.navigation_rounded, size: 20),
                                          label: const Text('Navigate'),
                                          style: ElevatedButton.styleFrom(
                                            minimumSize: const Size.fromHeight(48),
                                            backgroundColor: AppColors.info,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: OutlinedButton.icon(
                                          onPressed: () => _makeCall(item.hospital.phone),
                                          icon: const Icon(Icons.phone_rounded, size: 20),
                                          label: const Text('Call Station'),
                                          style: OutlinedButton.styleFrom(
                                            minimumSize: const Size.fromHeight(48),
                                            foregroundColor: AppColors.primary,
                                            side: const BorderSide(color: AppColors.primary),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Error loading hospitals: $err')),
      ),
    );
  }
}
