import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../core/theme.dart';
import '../../core/constants.dart';
import '../../providers/location_providers.dart';
import '../../providers/request_providers.dart';
import '../crew/widgets/crew_status_pill.dart';
import 'widgets/voice_note_recorder.dart';

class NewRequestScreen extends ConsumerStatefulWidget {
  const NewRequestScreen({super.key});

  @override
  ConsumerState<NewRequestScreen> createState() => _NewRequestScreenState();
}

class _NewRequestScreenState extends ConsumerState<NewRequestScreen> {
  final TextEditingController _noteController = TextEditingController();
  bool _isLocating = false;

  @override
  void initState() {
    super.initState();
    // Auto detect GPS location on launch if default
    Future.microtask(() => _detectGps());
  }

  Future<void> _detectGps() async {
    if (!mounted) return;
    setState(() => _isLocating = true);
    final locationService = ref.read(locationServiceProvider);
    final result = await locationService.getCurrentLocation();
    if (!mounted) return;
    ref.read(currentLocationProvider.notifier).updateLocation(
          result.latitude,
          result.longitude,
          isGps: result.isGps,
        );
    if (mounted) setState(() => _isLocating = false);
  }

  void _showMapPinDialog() {
    final currentLocation = ref.read(currentLocationProvider);
    LatLng selectedPin = LatLng(currentLocation.latitude, currentLocation.longitude);

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Set Patient Location Pin'),
              content: SizedBox(
                width: 320,
                height: 350,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: FlutterMap(
                    options: MapOptions(
                      initialCenter: selectedPin,
                      initialZoom: 13.0,
                      onTap: (_, point) {
                        setDialogState(() {
                          selectedPin = point;
                        });
                      },
                    ),
                    children: [
                      TileLayer(
                        urlTemplate:
                            'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.bedlink.bedlink',
                      ),
                      MarkerLayer(
                        markers: [
                          Marker(
                            point: selectedPin,
                            width: 40,
                            height: 40,
                            child: const Icon(
                              Icons.location_on_rounded,
                              color: AppColors.danger,
                              size: 40,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () {
                    ref.read(currentLocationProvider.notifier).updateLocation(
                          selectedPin.latitude,
                          selectedPin.longitude,
                          isGps: false,
                        );
                    Navigator.pop(ctx);
                  },
                  child: const Text('Confirm Location'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final location = ref.watch(currentLocationProvider);
    final draft = ref.watch(requestDraftProvider);
    final isPatientMode = ref.watch(isPatientModeProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(isPatientMode ? 'Find Nearby Emergency Beds' : 'New Emergency Dispatch'),
        backgroundColor: AppColors.primaryDark,
        actions: [
          if (!isPatientMode)
            const Center(
              child: Padding(
                padding: EdgeInsets.only(right: 6.0),
                child: CrewStatusPill(),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.tune_rounded),
            tooltip: 'Demo Controls',
            onPressed: () => context.push('/demo'),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (isPatientMode) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.infoTint,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.info),
                ),
                child: Row(
                  children: const [
                    Icon(Icons.info_outline_rounded, color: AppColors.info, size: 22),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Patient Search Mode: View live bed counts & hospital locations nearby. No bed hold request will be dispatched.',
                        style: TextStyle(fontSize: 12, color: AppColors.textPrimary, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
            // Location Header Card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Small Map Bar Preview
                    GestureDetector(
                      onTap: _showMapPinDialog,
                      child: Container(
                        height: 140,
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.primary.withValues(alpha: 0.3), width: 1.5),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Stack(
                            children: [
                              FlutterMap(
                                key: ValueKey('${location.latitude}_${location.longitude}'),
                                options: MapOptions(
                                  initialCenter: LatLng(location.latitude, location.longitude),
                                  initialZoom: 14.0,
                                  interactionOptions: const InteractionOptions(
                                    flags: InteractiveFlag.none,
                                  ),
                                ),
                                children: [
                                  TileLayer(
                                    urlTemplate:
                                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                                    userAgentPackageName: 'com.bedlink.bedlink',
                                  ),
                                  MarkerLayer(
                                    markers: [
                                      Marker(
                                        point: LatLng(location.latitude, location.longitude),
                                        width: 36,
                                        height: 36,
                                        child: const Icon(
                                          Icons.location_on_rounded,
                                          color: AppColors.danger,
                                          size: 36,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              Positioned(
                                right: 8,
                                top: 8,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.65),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.touch_app_rounded, color: Colors.white, size: 12),
                                      SizedBox(width: 4),
                                      Text(
                                        'Tap to adjust pin',
                                        style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              if (_isLocating)
                                Container(
                                  color: Colors.black26,
                                  child: const Center(
                                    child: CircularProgressIndicator(),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        Icon(
                          location.isGps
                              ? Icons.my_location_rounded
                              : Icons.location_on_outlined,
                          color: AppColors.primary,
                          size: 24,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          location.isGps
                              ? 'GPS Location Acquired'
                              : 'Map Pin Location',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const Spacer(),
                        if (_isLocating)
                          const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Lat: ${location.latitude.toStringAsFixed(4)}, Lng: ${location.longitude.toStringAsFixed(4)}',
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _isLocating ? null : _detectGps,
                            icon: const Icon(Icons.gps_fixed_rounded, size: 18),
                            label: const Text('Refresh GPS'),
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size.fromHeight(48),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _showMapPinDialog,
                            icon: const Icon(Icons.map_rounded, size: 18),
                            label: const Text('Set Map Pin'),
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size.fromHeight(48),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Required Bed Types Section
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Required Bed Types (Multi-select)',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Tap to select all bed types needed for patient',
                      style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: AppConstants.bedTypes.map((type) {
                        final isSelected = draft.needs.contains(type);
                        return FilterChip(
                          selected: isSelected,
                          label: Text(type),
                          avatar: Icon(
                            isSelected ? Icons.check_circle : Icons.add_circle_outline,
                            color: isSelected ? AppColors.primary : AppColors.textSecondary,
                            size: 18,
                          ),
                          onSelected: (_) {
                            ref
                                .read(requestDraftProvider.notifier)
                                .toggleNeed(type);
                          },
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Patient Severity Section
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Patient Triage Severity',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(
                          value: 'critical',
                          label: Text('Critical'),
                          icon: Icon(Icons.warning_rounded, color: AppColors.danger),
                        ),
                        ButtonSegment(
                          value: 'serious',
                          label: Text('Serious'),
                          icon: Icon(Icons.error_outline, color: AppColors.warningText),
                        ),
                        ButtonSegment(
                          value: 'stable',
                          label: Text('Stable'),
                          icon: Icon(Icons.check_circle_outline, color: AppColors.success),
                        ),
                      ],
                      selected: {draft.severity},
                      onSelectionChanged: (selection) {
                        ref
                            .read(requestDraftProvider.notifier)
                            .setSeverity(selection.first);
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Optional Patient Note Section
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Patient Summary / Clinical Note (Optional)',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _noteController,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        hintText: 'e.g. 62M, severe respiratory distress, SPO2 84%',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (val) {
                        ref.read(requestDraftProvider.notifier).setNote(val);
                      },
                    ),
                    if (!isPatientMode) ...[
                      const SizedBox(height: 16),
                      VoiceNoteRecorder(
                        initialFilePath: draft.voiceNotePath,
                        initialDurationSec: draft.voiceNoteDurationSec,
                        onRecorded: (filePath, durationSec, sizeBytes) {
                          ref.read(requestDraftProvider.notifier).setVoiceNote(
                                path: filePath,
                                durationSec: durationSec,
                                sizeBytes: sizeBytes,
                              );
                        },
                        onDeleted: () {
                          ref.read(requestDraftProvider.notifier).clearVoiceNote();
                        },
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 32),

            // Primary Find Hospitals Action Button
            ElevatedButton.icon(
              onPressed: draft.needs.isEmpty
                  ? null
                  : () {
                      context.push('/dispatch/results');
                    },
              icon: const Icon(Icons.search_rounded, size: 28),
              label: Text(isPatientMode ? 'Find & Rank Available Beds' : 'Find & Rank Hospitals'),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size.fromHeight(68),
                backgroundColor: AppColors.primary,
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
