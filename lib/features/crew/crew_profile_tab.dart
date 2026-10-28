import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../core/constants/crew_constants.dart';
import '../../core/constants/crew_presence_constants.dart';
import '../../core/constants/crew_strings.dart';
import '../../core/theme.dart';
import '../../models/ambulance.dart';
import '../../providers/ambulance_auth_provider.dart';
import '../../providers/crew_presence_providers.dart';
import '../../providers/relief_providers.dart';
import '../../services/alarm_notification_service.dart';
import 'widgets/crew_status_pill.dart';

class CrewProfileTab extends ConsumerStatefulWidget {
  const CrewProfileTab({super.key});

  @override
  ConsumerState<CrewProfileTab> createState() => _CrewProfileTabState();
}

class _CrewProfileTabState extends ConsumerState<CrewProfileTab> {
  final TextEditingController _contactController = TextEditingController();
  String? _selectedTier;
  String? _selectedType;
  bool _isInitialized = false;
  bool _isSaving = false;
  String? _saveErrorMessage;
  String? _saveSuccessMessage;

  // Emergency Alerts Setup State
  bool _notificationsAllowed = false;
  bool _fullScreenIntentAllowed = false;
  bool _batteryOptimizationExempt = false;
  bool _isCheckingAlertSetup = false;
  bool _showOemHelp = false;

  @override
  void initState() {
    super.initState();
    _checkAlertSetup();
  }

  Future<void> _checkAlertSetup() async {
    try {
      final notif =
          await AlarmNotificationService.instance.isNotificationPermissionGranted();
      final fsi =
          await AlarmNotificationService.instance.requestFullScreenIntentPermission();
      final batt =
          await AlarmNotificationService.instance.isBatteryOptimizationExempt();
      if (mounted) {
        setState(() {
          _notificationsAllowed = notif;
          _fullScreenIntentAllowed = fsi;
          _batteryOptimizationExempt = batt;
          _isCheckingAlertSetup = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isCheckingAlertSetup = false);
      }
    }
  }

  Future<void> _requestNotification() async {
    final granted =
        await AlarmNotificationService.instance.requestNotificationPermission();
    if (mounted) {
      setState(() => _notificationsAllowed = granted);
    }
  }

  Future<void> _openFullScreenSettings() async {
    await AlarmNotificationService.instance.openFullScreenIntentSettings();
    await _checkAlertSetup();
  }

  Future<void> _requestBatteryExemption() async {
    final granted = await AlarmNotificationService.instance
        .requestBatteryOptimizationExemption();
    if (mounted) {
      setState(() => _batteryOptimizationExempt = granted);
    }
  }

  @override
  void dispose() {
    _contactController.dispose();
    super.dispose();
  }

  void _initFromAmbulance(Ambulance ambulance) {
    if (!_isInitialized) {
      _selectedTier = ambulance.ais125Tier;
      _selectedType = ambulance.ambulanceType;
      _contactController.text = ambulance.contactNumber;
      _isInitialized = true;
      ref.read(crewPresenceServiceProvider).initializeStatus(ambulance.uid);
    }
  }

  String _formatPlate(String raw) {
    final clean = raw.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    if (clean.length <= 4) return clean;
    if (clean.length <= 6) return '${clean.substring(0, 2)}-${clean.substring(2)}';
    if (clean.length <= 8) {
      return '${clean.substring(0, 2)}-${clean.substring(2, 4)}-${clean.substring(4)}';
    }
    final prefix = '${clean.substring(0, 2)}-${clean.substring(2, 4)}-${clean.substring(4, clean.length - 4)}';
    final suffix = clean.substring(clean.length - 4);
    return '$prefix-$suffix';
  }

  bool _validateIndianMobile(String phone) {
    final clean = phone.trim().replaceAll(RegExp(r'[\s\-]'), '');
    final match = RegExp(r'^(?:\+91)?[6-9]\d{9}$');
    return match.hasMatch(clean);
  }

  Future<void> _handleSave(Ambulance ambulance) async {
    final contact = _contactController.text.trim();

    if (contact.isNotEmpty && !_validateIndianMobile(contact)) {
      setState(() {
        _saveErrorMessage = 'Please enter a valid 10-digit Indian mobile number.';
        _saveSuccessMessage = null;
      });
      return;
    }

    setState(() {
      _isSaving = true;
      _saveErrorMessage = null;
      _saveSuccessMessage = null;
    });

    try {
      final controller = ref.read(ambulanceAuthControllerProvider);
      await controller.updateCrewMutableFields(
        uid: ambulance.uid,
        ais125Tier: _selectedTier ?? 'TYPE_B',
        ambulanceType: _selectedType ?? 'PRIVATE',
        contactNumber: contact,
      );

      if (!mounted) return;
      setState(() {
        _saveSuccessMessage = 'Profile updated successfully.';
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Profile specifications saved!'),
          backgroundColor: AppColors.success,
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _saveErrorMessage = 'Failed to save changes: ${e.toString()}';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _handleSignOut() async {
    await ref.read(ambulanceAuthControllerProvider).signOut();
    if (mounted) {
      context.go('/crew/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    final ambulanceAsync = ref.watch(currentAmbulanceProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Ambulance Profile'),
        backgroundColor: AppColors.primaryDark,
        automaticallyImplyLeading: false,
        actions: [
          const Center(
            child: Padding(
              padding: EdgeInsets.only(right: 8.0),
              child: CrewStatusPill(),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.logout_rounded),
            tooltip: CrewStrings.signOutButton,
            onPressed: _handleSignOut,
          ),
        ],
      ),
      body: SafeArea(
        child: ambulanceAsync.when(
          loading: () => const Center(
            child: CircularProgressIndicator(color: AppColors.primary),
          ),
          error: (err, _) => Center(
            child: Text('Error loading profile: $err'),
          ),
          data: (ambulance) {
            if (ambulance == null) {
              return const Center(child: Text('No ambulance profile found.'));
            }

            _initFromAmbulance(ambulance);

            return SingleChildScrollView(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Section 1: Verified Details (Read-only)
                  _buildVerifiedDetailsSection(ambulance),

                  const SizedBox(height: 24),

                  // Feedback Banners
                  if (_saveErrorMessage != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.dangerTint,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.danger),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline_rounded,
                              color: AppColors.danger, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _saveErrorMessage!,
                              style: const TextStyle(
                                color: AppColors.danger,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  if (_saveSuccessMessage != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.successTint,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.success),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.check_circle_outline_rounded,
                              color: AppColors.success, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _saveSuccessMessage!,
                              style: const TextStyle(
                                color: AppColors.success,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Section 2: Editable Details
                  _buildEditableDetailsSection(ambulance),

                  const SizedBox(height: 20),

                  // Section 3: Emergency Alerts Setup
                  _buildEmergencyAlertsSetupCard(),

                  const SizedBox(height: 28),

                  // Logout Button
                  OutlinedButton.icon(
                    onPressed: _handleSignOut,
                    icon: const Icon(Icons.logout_rounded, color: AppColors.danger),
                    label: const Text(
                      CrewStrings.signOutButton,
                      style: TextStyle(color: AppColors.danger, fontWeight: FontWeight.bold),
                    ),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                      side: const BorderSide(color: AppColors.danger),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildVerifiedDetailsSection(Ambulance ambulance) {
    final formattedPlate = _formatPlate(ambulance.vehicleNumber);
    final vehicleClassDisplay = ambulance.vehicleClass.isNotEmpty
        ? ambulance.vehicleClass.replaceAll('_', ' ')
        : 'Commercial Ambulance';

    final dobString = ambulance.dob != null
        ? DateFormat('dd MMM yyyy').format(ambulance.dob!)
        : 'Verified on Record';

    final ambId = ambulance.ambulanceId ?? 'BL-AMB-PENDING';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section Header with Lock icon & Verified Caption
        Row(
          children: [
            const Icon(Icons.lock_rounded, size: 18, color: AppColors.primary),
            const SizedBox(width: 6),
            const Text(
              'Verified Details',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.successTint,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppColors.success.withValues(alpha: 0.5)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Icon(Icons.verified_rounded, size: 12, color: AppColors.success),
                  SizedBox(width: 4),
                  Text(
                    'Verified via RTO/Sarathi',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: AppColors.success,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // Verified Card
        Card(
          elevation: 0,
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: AppColors.divider),
          ),
          child: Padding(
            padding: const EdgeInsets.all(18.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Ambulance ID with Verified badge
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'AMBULANCE ID',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textSecondary,
                            letterSpacing: 0.8,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          ambId,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primaryDark,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.successTint,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppColors.success),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Icon(Icons.check_circle_rounded,
                              size: 14, color: AppColors.success),
                          SizedBox(width: 4),
                          Text(
                            'Verified Ambulance',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: AppColors.success,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const Divider(height: 22),

                // Vehicle Registration & Class
                _buildReadOnlyRow(
                  icon: Icons.airport_shuttle_rounded,
                  label: 'Vehicle Registration',
                  value: '$formattedPlate – $vehicleClassDisplay',
                ),
                const SizedBox(height: 12),

                // Driver Legal Name & DOB
                _buildReadOnlyRow(
                  icon: Icons.person_rounded,
                  label: "Driver's Legal Name & DOB",
                  value: '${ambulance.driverLegalName} (DOB: $dobString)',
                ),
                const SizedBox(height: 12),

                // Driving License & Transport Endorsement
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.badge_rounded, size: 18, color: AppColors.primary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "Driver's License Number",
                            style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            ambulance.dlNumber,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.primaryTint,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'Commercial Transport: Active / Endorsed',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: AppColors.primaryDark,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildReadOnlyRow({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: AppColors.primary),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStatusChip({
    required CrewPresenceStatus status,
    required CrewPresenceStatus currentStatus,
    required Ambulance ambulance,
  }) {
    final isSelected = status == currentStatus;
    Color activeColor;
    Color activeBg;
    IconData icon;

    switch (status) {
      case CrewPresenceStatus.available:
        activeColor = const Color(0xFF1E9E5A);
        activeBg = const Color(0xFFE8F5E9);
        icon = Icons.check_circle_rounded;
        break;
      case CrewPresenceStatus.busy:
        activeColor = const Color(0xFFD97706);
        activeBg = const Color(0xFFFEF3C7);
        icon = Icons.timelapse_rounded;
        break;
      case CrewPresenceStatus.offline:
        activeColor = AppColors.danger;
        activeBg = const Color(0xFFFFEBEE);
        icon = Icons.power_settings_new_rounded;
        break;
    }

    return Expanded(
      child: InkWell(
        onTap: () {
          ref.read(crewPresenceServiceProvider).setCrewStatus(
                ambulance.uid,
                status,
                ambulance: ambulance,
              );
        },
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
          decoration: BoxDecoration(
            color: isSelected ? activeBg : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? activeColor : AppColors.divider,
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 20,
                color: isSelected ? activeColor : AppColors.textSecondary,
              ),
              const SizedBox(height: 6),
              Text(
                status.label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  color: isSelected ? activeColor : AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEditableDetailsSection(Ambulance ambulance) {
    final currentStatus = ref.watch(currentCrewPresenceStatusProvider);
    final isLocationDenied = ref.watch(isCrewLocationDeniedProvider);
    final activeReliefMission = ref.watch(activeCrewReliefMissionProvider).value;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Editable Details',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Adjust dynamic operational settings for bed dispatch matching.',
          style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 12),

        Card(
          elevation: 0,
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: AppColors.divider),
          ),
          child: Padding(
            padding: const EdgeInsets.all(18.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Availability Status Selector
                Row(
                  children: const [
                    Icon(Icons.radio_button_checked_rounded, size: 16, color: AppColors.primary),
                    SizedBox(width: 6),
                    Text(
                      'Availability Status',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // Colored Chips Row
                Row(
                  children: [
                    _buildStatusChip(
                      status: CrewPresenceStatus.available,
                      currentStatus: currentStatus,
                      ambulance: ambulance,
                    ),
                    const SizedBox(width: 8),
                    _buildStatusChip(
                      status: CrewPresenceStatus.busy,
                      currentStatus: currentStatus,
                      ambulance: ambulance,
                    ),
                    const SizedBox(width: 8),
                    _buildStatusChip(
                      status: CrewPresenceStatus.offline,
                      currentStatus: currentStatus,
                      ambulance: ambulance,
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                // Description text
                Text(
                  currentStatus.description,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: currentStatus == CrewPresenceStatus.available
                        ? const Color(0xFF1E9E5A)
                        : (currentStatus == CrewPresenceStatus.busy
                            ? const Color(0xFFD97706)
                            : AppColors.textSecondary),
                  ),
                ),

                if (activeReliefMission != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFF0E7C86), width: 1.5),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.navigation_rounded, color: Color(0xFF0E7C86), size: 24),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Active Backup Route',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                              Text(
                                'Assisting ${activeReliefMission.requesterAmbulance.ambulanceId}',
                                style: const TextStyle(
                                  color: Color(0xFF94A3B8),
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                        ElevatedButton(
                          onPressed: () {
                            context.go('/crew/relief_nav?reliefRequestId=${activeReliefMission.id}');
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0E7C86),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: const Text('Open Map', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                  ),
                ],

                // Amber Location Off Warning
                if (currentStatus == CrewPresenceStatus.available && isLocationDenied) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFFBEB),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFFDE68A)),
                    ),
                    child: Row(
                      children: const [
                        Icon(Icons.warning_amber_rounded, color: Color(0xFFD97706), size: 20),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            CrewPresenceConstants.locationOffWarning,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFFB45309),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 18),
                const Divider(height: 1, color: AppColors.divider),
                const SizedBox(height: 16),

                // AIS-125 Homologation / Vehicle Tier Dropdown
                const Text(
                  'AIS-125 Homologation / Vehicle Tier',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: _selectedTier ?? 'TYPE_B',
                  isExpanded: true,
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: AppColors.background,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppColors.divider),
                    ),
                  ),
                  items: kAis125Tiers.map((tier) {
                    return DropdownMenuItem<String>(
                      value: tier.code,
                      child: Text(
                        tier.label,
                        style: const TextStyle(fontSize: 13),
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) setState(() => _selectedTier = val);
                  },
                ),
                const SizedBox(height: 18),

                // Government or Private Ambulance Segmented Toggle
                const Text(
                  'Ambulance Operator Type',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(
                      value: 'PRIVATE',
                      label: Text('Private Ambulance'),
                      icon: Icon(Icons.business_rounded, size: 18),
                    ),
                    ButtonSegment(
                      value: 'GOVERNMENT',
                      label: Text('Government (108)'),
                      icon: Icon(Icons.account_balance_rounded, size: 18),
                    ),
                  ],
                  selected: {_selectedType ?? 'PRIVATE'},
                  onSelectionChanged: (set) {
                    setState(() => _selectedType = set.first);
                  },
                  style: ButtonStyle(
                    backgroundColor: WidgetStateProperty.resolveWith((states) {
                      if (states.contains(WidgetState.selected)) {
                        return AppColors.primary;
                      }
                      return AppColors.background;
                    }),
                    foregroundColor: WidgetStateProperty.resolveWith((states) {
                      if (states.contains(WidgetState.selected)) {
                        return Colors.white;
                      }
                      return AppColors.textPrimary;
                    }),
                  ),
                ),
                const SizedBox(height: 18),

                // Contact Number
                const Text(
                  'Contact Number',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _contactController,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    hintText: 'e.g. 9876543210 or +91 9876543210',
                    helperText: 'Valid 10-digit Indian emergency contact number',
                    prefixIcon: const Icon(Icons.phone_outlined, color: AppColors.primary),
                    filled: true,
                    fillColor: AppColors.background,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppColors.divider),
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // Save Button
                ElevatedButton(
                  onPressed: _isSaving ? null : () => _handleSave(ambulance),
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size.fromHeight(50),
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _isSaving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Save Changes',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmergencyAlertsSetupCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: const [
                  Icon(Icons.notification_important_rounded,
                      color: AppColors.primary, size: 20),
                  SizedBox(width: 8),
                  Text(
                    'EMERGENCY ALERTS SETUP',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
              IconButton(
                icon: const Icon(Icons.refresh_rounded, size: 18),
                color: AppColors.primary,
                tooltip: 'Refresh Status',
                onPressed: _isCheckingAlertSetup
                    ? null
                    : () {
                        setState(() => _isCheckingAlertSetup = true);
                        _checkAlertSetup();
                      },
              ),
            ],
          ),
          const SizedBox(height: 12),

          // 1. Notifications Status
          _buildSetupCheckItem(
            icon: Icons.notifications_active_rounded,
            title: 'Push Notifications',
            subtitle:
                'Receives high-priority relief alerts for nearby disabled ambulances',
            isAllowed: _notificationsAllowed,
            allowedText: 'Permitted',
            restrictedText: 'Blocked',
            actionLabel: 'Allow',
            onAction: _requestNotification,
          ),

          const Divider(height: 20, color: AppColors.divider),

          // 2. Full-Screen Intent Status
          _buildSetupCheckItem(
            icon: Icons.screen_lock_portrait_rounded,
            title: 'Lock Screen Full-Screen Intent',
            subtitle: 'Wakes phone screen and sounds siren when phone is locked',
            isAllowed: _fullScreenIntentAllowed,
            allowedText: 'Allowed',
            restrictedText: 'Action Needed',
            actionLabel: 'Configure',
            onAction: _openFullScreenSettings,
          ),

          const Divider(height: 20, color: AppColors.divider),

          // 3. Battery Optimization Status
          _buildSetupCheckItem(
            icon: Icons.battery_charging_full_rounded,
            title: 'Battery Optimization Exemption',
            subtitle:
                'Prevents OS from killing background relief alarm during active duty',
            isAllowed: _batteryOptimizationExempt,
            allowedText: 'Exempt',
            restrictedText: 'Optimized',
            actionLabel: 'Exempt',
            onAction: _requestBatteryExemption,
          ),

          const SizedBox(height: 12),

          // OEM Battery Killer Guide Expandable Tile
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => setState(() => _showOemHelp = !_showOemHelp),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6.0),
              child: Row(
                children: [
                  const Icon(Icons.info_outline_rounded,
                      size: 16, color: AppColors.textSecondary),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'OEM Battery Savers (Xiaomi, Samsung, Vivo, Oppo)',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                  Icon(
                    _showOemHelp
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    size: 18,
                    color: AppColors.textSecondary,
                  ),
                ],
              ),
            ),
          ),

          if (_showOemHelp) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'To ensure relief alerts ring while device is unattended:',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  SizedBox(height: 6),
                  Text(
                    '• Xiaomi / Redmi / POCO: Settings → Apps → BedLink → Turn ON "Autostart", set Battery Saver to "No Restrictions".\n'
                    '• Samsung (OneUI): Settings → Battery → Background usage limits → Add BedLink to "Never sleeping apps".\n'
                    '• Oppo / Vivo / Realme: App Info → Battery usage → Enable "Allow background activity" & "Allow auto-launch".\n'
                    '• iOS: Background looping sirens require Apple Critical Alerts approval. Push notifications ring standard chime.',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSetupCheckItem({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool isAllowed,
    required String allowedText,
    required String restrictedText,
    required String actionLabel,
    required VoidCallback onAction,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(
          icon,
          size: 22,
          color: isAllowed ? AppColors.success : AppColors.warning,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        if (isAllowed)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.check_circle_rounded,
                  size: 14,
                  color: AppColors.success,
                ),
                const SizedBox(width: 4),
                Text(
                  allowedText,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: AppColors.success,
                  ),
                ),
              ],
            ),
          )
        else
          OutlinedButton(
            onPressed: onAction,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primary,
              side: const BorderSide(color: AppColors.primary),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              minimumSize: const Size(60, 30),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: Text(
              actionLabel,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
            ),
          ),
      ],
    );
  }
}
