import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../../core/theme.dart';
import '../../models/hospital.dart';
import '../../providers/hospital_providers.dart';
import '../../providers/location_providers.dart';
import '../../services/alarm_notification_service.dart';

class HospitalProfileScreen extends ConsumerStatefulWidget {
  final Hospital hospital;

  const HospitalProfileScreen({
    super.key,
    required this.hospital,
  });

  @override
  ConsumerState<HospitalProfileScreen> createState() =>
      _HospitalProfileScreenState();
}

class _HospitalProfileScreenState extends ConsumerState<HospitalProfileScreen> {
  final _contactFormKey = GlobalKey<FormState>();
  final _passwordFormKey = GlobalKey<FormState>();

  late TextEditingController _contactController;
  final TextEditingController _currentPassController = TextEditingController();
  final TextEditingController _newPassController = TextEditingController();
  final TextEditingController _confirmPassController = TextEditingController();

  bool _isSavingContact = false;
  bool _isUpdatingPassword = false;
  bool _obscureCurrent = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;

  // Emergency Alerts Setup State
  bool _notificationsAllowed = false;
  bool _fullScreenIntentAllowed = false;
  bool _batteryOptimizationExempt = false;
  bool _isCheckingAlertSetup = true;
  bool _isSendingTestAlert = false;
  bool _showOemHelp = false;

  @override
  void initState() {
    super.initState();
    _contactController = TextEditingController(text: widget.hospital.phone);
    _checkAlertSetup();
  }

  Future<void> _checkAlertSetup() async {
    setState(() => _isCheckingAlertSetup = true);
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
  }

  Future<void> _requestNotification() async {
    await AlarmNotificationService.instance.requestNotificationPermission();
    await _checkAlertSetup();
  }

  Future<void> _openFullScreenSettings() async {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.fullscreen_rounded, color: AppColors.primary),
            SizedBox(width: 8),
            Text('Full-Screen Alerts'),
          ],
        ),
        content: const Text(
          'On Android 14+, full-screen intents require manual authorization to let incoming bed hold alerts wake your screen and sound the siren when your device is locked.\n\nTap "Open Settings", then enable "Full-screen intent" or "Alarms & Reminders" for BedLink.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              AlarmNotificationService.instance.openFullScreenIntentSettings();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  Future<void> _requestBatteryExemption() async {
    await AlarmNotificationService.instance
        .requestBatteryOptimizationExemption();
    await _checkAlertSetup();
  }

  Future<void> _sendTestAlert() async {
    setState(() => _isSendingTestAlert = true);
    try {
      final callable =
          FirebaseFunctions.instance.httpsCallable('sendTestFcmAlert');
      await callable.call({
        'hospitalId': widget.hospital.id,
        'title': '🚨 BedLink Test Alert',
        'body': 'Emergency siren and full-screen alarm notification test',
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                '✓ Test alert dispatched! Lock device or minimize to test background siren.'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Test alert failed: $e'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSendingTestAlert = false);
    }
  }

  @override
  void didUpdateWidget(covariant HospitalProfileScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.hospital.phone != widget.hospital.phone &&
        !_isSavingContact) {
      _contactController.text = widget.hospital.phone;
    }
  }

  @override
  void dispose() {
    _contactController.dispose();
    _currentPassController.dispose();
    _newPassController.dispose();
    _confirmPassController.dispose();
    super.dispose();
  }

  Future<void> _saveContact() async {
    if (!_contactFormKey.currentState!.validate()) return;

    setState(() => _isSavingContact = true);
    final newPhone = _contactController.text.trim();

    try {
      final firestoreService = ref.read(firestoreServiceProvider);
      await firestoreService.updateHospitalContact(widget.hospital.id, newPhone);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✓ Hospital contact number updated!'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error updating contact: $e'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSavingContact = false);
    }
  }

  Future<void> _updatePassword() async {
    if (!_passwordFormKey.currentState!.validate()) return;

    final currentPass = _currentPassController.text.trim();
    final newPass = _newPassController.text.trim();

    // Verify current password against salted hash or legacy pin
    if (!widget.hospital.verifyPin(currentPass)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Current password is incorrect'),
          backgroundColor: AppColors.danger,
        ),
      );
      return;
    }

    setState(() => _isUpdatingPassword = true);

    try {
      final firestoreService = ref.read(firestoreServiceProvider);
      await firestoreService.updateHospitalPassword(widget.hospital.id, newPass);

      _currentPassController.clear();
      _newPassController.clear();
      _confirmPassController.clear();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✓ Password updated securely!'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error updating password: $e'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isUpdatingPassword = false);
    }
  }

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log Out?'),
        content: const Text(
          'This will disconnect your nurse terminal session and mark your station offline.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            child: const Text('Log Out'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final firestoreService = ref.read(firestoreServiceProvider);
    await ref.read(fcmServiceProvider).unregisterNurseDevice(widget.hospital.id);
    await firestoreService.updateNursePresence(widget.hospital.id, false);
    ref.read(selectedHospitalIdProvider.notifier).select(null);
    if (mounted) {
      context.go('/nurse/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Read-Only Hospital Identification Card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.divider),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppColors.primaryTint,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.local_hospital_rounded,
                          color: AppColors.primary,
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.hospital.name,
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 2),
                            const Text(
                              'Station ID: Official Health Facility',
                              style: TextStyle(
                                fontSize: 11,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.lock_outline_rounded,
                          size: 18, color: AppColors.textSecondary),
                    ],
                  ),
                  const Divider(height: 24),
                  const Text(
                    'FACILITY ADDRESS (IMMUTABLE)',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.place_outlined,
                        size: 16,
                        color: AppColors.primary,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          widget.hospital.address,
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.textPrimary,
                            height: 1.3,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Editable Hospital Contact Number
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.divider),
              ),
              child: Form(
                key: _contactFormKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'HOSPITAL CONTACT NUMBER',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _contactController,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        hintText: '+91 22 1234 5678',
                        prefixIcon: Icon(Icons.phone_outlined),
                        border: OutlineInputBorder(),
                      ),
                      validator: (val) {
                        if (val == null || val.trim().isEmpty) {
                          return 'Please enter a contact phone number';
                        }
                        final clean = val.replaceAll(RegExp(r'[^\d]'), '');
                        if (clean.length < 8) {
                          return 'Enter a valid telephone or mobile number';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerRight,
                      child: ElevatedButton.icon(
                        onPressed: _isSavingContact ? null : _saveContact,
                        icon: _isSavingContact
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.check_rounded, size: 16),
                        label: Text(_isSavingContact ? 'Saving...' : 'Save Contact'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Change Password Form
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.divider),
              ),
              child: Form(
                key: _passwordFormKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: const [
                        Icon(Icons.shield_outlined,
                            size: 18, color: AppColors.primary),
                        SizedBox(width: 8),
                        Text(
                          'SECURITY & ACCESS PASSWORD',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _currentPassController,
                      obscureText: _obscureCurrent,
                      decoration: InputDecoration(
                        labelText: 'Current Password / PIN',
                        prefixIcon: const Icon(Icons.lock_open_rounded),
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          icon: Icon(_obscureCurrent
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined),
                          onPressed: () =>
                              setState(() => _obscureCurrent = !_obscureCurrent),
                        ),
                      ),
                      validator: (val) {
                        if (val == null || val.trim().isEmpty) {
                          return 'Enter current password';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: _newPassController,
                      obscureText: _obscureNew,
                      decoration: InputDecoration(
                        labelText: 'New Password / PIN',
                        prefixIcon: const Icon(Icons.lock_rounded),
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          icon: Icon(_obscureNew
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined),
                          onPressed: () =>
                              setState(() => _obscureNew = !_obscureNew),
                        ),
                      ),
                      validator: (val) {
                        if (val == null || val.trim().length < 4) {
                          return 'Password must be at least 4 characters';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: _confirmPassController,
                      obscureText: _obscureConfirm,
                      decoration: InputDecoration(
                        labelText: 'Confirm New Password',
                        prefixIcon: const Icon(Icons.lock_outline_rounded),
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          icon: Icon(_obscureConfirm
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined),
                          onPressed: () =>
                              setState(() => _obscureConfirm = !_obscureConfirm),
                        ),
                      ),
                      validator: (val) {
                        if (val != _newPassController.text.trim()) {
                          return 'Passwords do not match';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),
                    Align(
                      alignment: Alignment.centerRight,
                      child: ElevatedButton.icon(
                        onPressed:
                            _isUpdatingPassword ? null : _updatePassword,
                        icon: _isUpdatingPassword
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.key_rounded, size: 16),
                        label: Text(_isUpdatingPassword
                            ? 'Updating...'
                            : 'Update Password'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Emergency Alerts Setup Card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surface,
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
                      _isCheckingAlertSetup
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.primary,
                              ),
                            )
                          : IconButton(
                              icon: const Icon(Icons.refresh_rounded, size: 18),
                              color: AppColors.primary,
                              tooltip: 'Refresh Status',
                              onPressed: _checkAlertSetup,
                            ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // 1. Notifications Status
                  _buildSetupCheckItem(
                    icon: Icons.notifications_active_rounded,
                    title: 'Push Notifications',
                    subtitle: 'Receives high-priority triage alerts from dispatch',
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
                    subtitle: 'Wakes phone screen and sounds siren when locked',
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
                    subtitle: 'Prevents system from killing background siren during shifts',
                    isAllowed: _batteryOptimizationExempt,
                    allowedText: 'Exempt',
                    restrictedText: 'Optimized',
                    actionLabel: 'Exempt',
                    onAction: _requestBatteryExemption,
                  ),

                  const SizedBox(height: 16),

                  // Send Test Alert Button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _isSendingTestAlert ? null : _sendTestAlert,
                      icon: _isSendingTestAlert
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.campaign_rounded, size: 18),
                      label: Text(_isSendingTestAlert
                          ? 'Dispatching Test Alert...'
                          : 'Send Test Alert to This Terminal'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
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
                            'To ensure alarms ring while device is unattended:',
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
                            '• iOS: Background looping sirens require Apple Critical Alerts approval. Push notifications ring standard chime; open app to activate siren.',
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
            ),

            const SizedBox(height: 24),

            // Logout Button
            OutlinedButton.icon(
              onPressed: _logout,
              icon: const Icon(Icons.logout_rounded, color: AppColors.danger),
              label: const Text(
                'Log Out of Station Terminal',
                style: TextStyle(
                  color: AppColors.danger,
                  fontWeight: FontWeight.bold,
                ),
              ),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: AppColors.danger, width: 1.5),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
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
