import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme.dart';
import '../../models/clinic.dart';
import '../../providers/location_providers.dart';
import '../../providers/clinic_providers.dart';

class ClinicResultsScreen extends ConsumerStatefulWidget {
  const ClinicResultsScreen({super.key});

  @override
  ConsumerState<ClinicResultsScreen> createState() =>
      _ClinicResultsScreenState();
}

class _ClinicResultsScreenState extends ConsumerState<ClinicResultsScreen> {
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

  void _showClinicDetailsSheet(ClinicRankResult item) {
    final c = item.clinic;
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
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
                  Icon(
                    c.type == 'pathology_lab' ? Icons.science_rounded : Icons.medical_services_rounded,
                    color: AppColors.primary,
                    size: 28,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          c.name,
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          c.address,
                          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const Divider(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.star_rounded, color: AppColors.warning, size: 20),
                      const SizedBox(width: 4),
                      Text(
                        '${c.rating} Rating',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: c.isOpen ? AppColors.successTint : AppColors.dangerTint,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      c.isOpen ? 'OPEN NOW' : 'CLOSED',
                      style: TextStyle(
                        color: c.isOpen ? AppColors.success : AppColors.danger,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'Operating Hours: ${c.operatingHours}',
                style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 16),
              const Text(
                'Specialties & Available Diagnostics:',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  ...c.specialties.map((s) => Chip(
                        label: Text(s, style: const TextStyle(fontSize: 12)),
                        backgroundColor: AppColors.primaryTint,
                      )),
                  ...c.testsAvailable.map((t) => Chip(
                        label: Text('🔬 $t', style: const TextStyle(fontSize: 12)),
                        backgroundColor: AppColors.infoTint,
                      )),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        _makeCall(c.phone);
                      },
                      icon: const Icon(Icons.phone),
                      label: const Text('Call Station'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        _openGoogleMaps(c.lat, c.lng, c.name);
                      },
                      icon: const Icon(Icons.navigation_rounded),
                      label: const Text('Navigate'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    context.push('/patient/clinics/book', extra: c);
                  },
                  icon: const Icon(Icons.calendar_month_rounded, size: 18),
                  label: Text(
                    'Book an appointment · ₹${c.bookingFeeRupees}',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1E9E5A),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    elevation: 0,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final location = ref.watch(currentLocationProvider);
    final draft = ref.watch(clinicFilterDraftProvider);
    final clinicsAsync = ref.watch(clinicsStreamProvider);
    final rankingService = ref.watch(clinicRankingServiceProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Ranked Clinics & Pathology Labs'),
        backgroundColor: AppColors.primaryDark,
      ),
      body: clinicsAsync.when(
        data: (allClinics) {
          return FutureBuilder<List<ClinicRankResult>>(
            future: rankingService.rankClinics(
              clinics: allClinics,
              patientLat: location.latitude,
              patientLng: location.longitude,
              selectedSpecialties: draft.selectedSpecialties,
              filterType: draft.filterType,
            ),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              final rankedClinics = snapshot.data!;
              final mapCenter = LatLng(location.latitude, location.longitude);

              if (rankedClinics.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.search_off_rounded,
                          size: 64, color: AppColors.textSecondary),
                      const SizedBox(height: 16),
                      const Text(
                        'No matching clinics or labs found.',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () => context.pop(),
                        child: const Text('Broaden Search Criteria'),
                      ),
                    ],
                  ),
                );
              }

              return Column(
                children: [
                  // Top Map View
                  SizedBox(
                    height: 200,
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
                            // Patient Pin
                            Marker(
                              point: mapCenter,
                              width: 36,
                              height: 36,
                              child: Container(
                                decoration: const BoxDecoration(
                                  color: AppColors.primary,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.person_pin_circle_rounded,
                                  color: Colors.white,
                                  size: 22,
                                ),
                              ),
                            ),
                            // Clinic Pins
                            ...rankedClinics.map((r) {
                              return Marker(
                                point: LatLng(r.clinic.lat, r.clinic.lng),
                                width: 32,
                                height: 32,
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: r.clinic.type == 'pathology_lab'
                                        ? AppColors.info
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

                  // Patient Read-Only Notice
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                    color: AppColors.infoTint,
                    child: Row(
                      children: const [
                        Icon(Icons.info_outline_rounded,
                            color: AppColors.info, size: 18),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Patient Mode: Direct OP Contact & Live Directions. Call or navigate to book sample collection or consultation.',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Header bar
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                    color: AppColors.surface,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Found ${rankedClinics.length} Clinics & Labs',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        Text(
                          'Filter: ${draft.filterType.toUpperCase()}',
                          style: const TextStyle(
                              fontSize: 12, color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),

                  // Clinic Cards List
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: rankedClinics.length,
                      itemBuilder: (context, index) {
                        final item = rankedClinics[index];
                        final c = item.clinic;
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
                                // Top Header Row
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
                                            c.name,
                                            style: const TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                              color: AppColors.textPrimary,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            '${item.travelMinutes} min drive (${item.distanceKm.toStringAsFixed(1)} km) • ${c.address}',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontSize: 12,
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

                                // Ratings & Open Status Row
                                Row(
                                  children: [
                                    Row(
                                      children: [
                                        const Icon(Icons.star_rounded,
                                            color: AppColors.warning, size: 18),
                                        const SizedBox(width: 4),
                                        Text(
                                          '${c.rating}',
                                          style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 13),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(width: 12),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: c.type == 'pathology_lab'
                                            ? AppColors.infoTint
                                            : AppColors.primaryTint,
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        c.type == 'pathology_lab'
                                            ? 'PATHOLOGY LAB'
                                            : 'CLINIC',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: c.type == 'pathology_lab'
                                              ? AppColors.info
                                              : AppColors.primaryDark,
                                        ),
                                      ),
                                    ),
                                    const Spacer(),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: c.isOpen
                                            ? AppColors.successTint
                                            : AppColors.dangerTint,
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        c.isOpen ? 'OPEN NOW' : 'CLOSED',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: c.isOpen
                                              ? AppColors.success
                                              : AppColors.danger,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),

                                // Specialties & Tests Chips
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  children: [
                                    ...c.specialties.take(3).map((s) => Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: AppColors.background,
                                            borderRadius:
                                                BorderRadius.circular(8),
                                            border: Border.all(
                                                color: AppColors.divider),
                                          ),
                                          child: Text(
                                            s,
                                            style: const TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w600),
                                          ),
                                        )),
                                    ...c.testsAvailable.take(2).map((t) => Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: AppColors.infoTint,
                                            borderRadius:
                                                BorderRadius.circular(8),
                                          ),
                                          child: Text(
                                            '🔬 $t',
                                            style: const TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w600,
                                                color: AppColors.info),
                                          ),
                                        )),
                                  ],
                                ),

                                const SizedBox(height: 16),

                                // Action Buttons: Navigate, Call, Book/Details
                                Row(
                                  children: [
                                    Expanded(
                                      child: ElevatedButton.icon(
                                        onPressed: () => _openGoogleMaps(
                                            c.lat, c.lng, c.name),
                                        icon: const Icon(
                                            Icons.navigation_rounded,
                                            size: 18),
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
                                        onPressed: () => _makeCall(c.phone),
                                        icon: const Icon(Icons.phone_rounded,
                                            size: 18),
                                        label: const Text('Call'),
                                        style: OutlinedButton.styleFrom(
                                          minimumSize: const Size.fromHeight(48),
                                          foregroundColor: AppColors.primary,
                                          side: const BorderSide(
                                              color: AppColors.primary),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    IconButton(
                                      icon: const Icon(Icons.info_outline_rounded,
                                          color: AppColors.primary),
                                      tooltip: 'View Details & Timing',
                                      onPressed: () =>
                                          _showClinicDetailsSheet(item),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton.icon(
                                    onPressed: () {
                                      context.push('/patient/clinics/book', extra: c);
                                    },
                                    icon: const Icon(Icons.calendar_month_rounded, size: 18),
                                    label: Text(
                                      'Book an appointment · ₹${c.bookingFeeRupees}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                      ),
                                    ),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF1E9E5A),
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(vertical: 12),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      elevation: 0,
                                    ),
                                  ),
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
        error: (err, _) => Center(child: Text('Error loading clinics: $err')),
      ),
    );
  }
}
