import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import '../../core/constants/crew_strings.dart';
import '../../core/theme.dart';
import '../../providers/ambulance_auth_provider.dart';

class CrewRegisterScreen extends ConsumerStatefulWidget {
  const CrewRegisterScreen({super.key});

  @override
  ConsumerState<CrewRegisterScreen> createState() => _CrewRegisterScreenState();
}

class _CrewRegisterScreenState extends ConsumerState<CrewRegisterScreen> {
  int _currentStep = 0;

  // Step 1: Vehicle Controllers
  final TextEditingController _vehiclePlateController = TextEditingController();
  final TextEditingController _chassisEngineController = TextEditingController();
  String _ambulanceType = 'PRIVATE';
  String _ais125Tier = 'TYPE_B';
  XFile? _rcImageFile;
  Uint8List? _rcImageBytes;

  // Step 2: Driver Controllers
  final TextEditingController _driverNameController = TextEditingController();
  final TextEditingController _dlNumberController = TextEditingController();
  final TextEditingController _contactController = TextEditingController();
  DateTime? _selectedDob;

  // Step 3: Account Credentials
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController = TextEditingController();
  bool _obscurePassword = true;
  bool _obscureConfirm = true;

  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _vehiclePlateController.dispose();
    _chassisEngineController.dispose();
    _driverNameController.dispose();
    _dlNumberController.dispose();
    _contactController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  // Live Vehicle plate formatter/hint helper
  String _formatPlateDisplay(String input) {
    final clean = input.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    if (clean.length <= 2) return clean;
    if (clean.length <= 4) return '${clean.substring(0, 2)}-${clean.substring(2)}';
    if (clean.length <= 6) {
      return '${clean.substring(0, 2)}-${clean.substring(2, 4)}-${clean.substring(4)}';
    }
    final prefix = '${clean.substring(0, 2)}-${clean.substring(2, 4)}-${clean.substring(4, clean.length - 4)}';
    final suffix = clean.substring(clean.length - 4);
    return '$prefix-$suffix';
  }

  Future<void> _pickRcPhoto() async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 85,
      );
      if (picked != null) {
        final bytes = await picked.readAsBytes();
        setState(() {
          _rcImageFile = picked;
          _rcImageBytes = bytes;
        });
      }
    } catch (_) {
      // Gracefully handle image picker cancellation or permissions
    }
  }

  Future<void> _selectDateOfBirth() async {
    final now = DateTime.now();
    final initialDate = _selectedDob ?? DateTime(now.year - 30, 1, 1);
    final firstDate = DateTime(now.year - 80, 1, 1);
    final lastDate = DateTime(now.year - 18, now.month, now.day);

    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: lastDate,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppColors.primary,
              onPrimary: Colors.white,
              onSurface: AppColors.textPrimary,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() => _selectedDob = picked);
    }
  }

  bool _validateStep(int step) {
    setState(() => _errorMessage = null);

    if (step == 0) {
      final plate = _vehiclePlateController.text.trim();
      final clean = plate.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
      if (clean.length < 6) {
        setState(() => _errorMessage = CrewStrings.errorVehicleRequired);
        return false;
      }
      return true;
    } else if (step == 1) {
      final name = _driverNameController.text.trim();
      final dl = _dlNumberController.text.trim();
      if (name.length < 2) {
        setState(() => _errorMessage = CrewStrings.errorDriverRequired);
        return false;
      }
      if (dl.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').length < 8) {
        setState(() => _errorMessage = CrewStrings.errorDlRequired);
        return false;
      }
      if (_selectedDob == null) {
        setState(() => _errorMessage = CrewStrings.errorDobRequired);
        return false;
      }
      return true;
    } else if (step == 2) {
      final pass = _passwordController.text;
      final confirm = _confirmPasswordController.text;
      if (pass.length < 6) {
        setState(() => _errorMessage = CrewStrings.errorPasswordLength);
        return false;
      }
      if (pass != confirm) {
        setState(() => _errorMessage = CrewStrings.errorPasswordMismatch);
        return false;
      }
      return true;
    }
    return true;
  }

  void _onNext() {
    if (_validateStep(_currentStep)) {
      if (_currentStep < 2) {
        setState(() => _currentStep++);
      } else {
        _handleSubmit();
      }
    }
  }

  void _onPrevious() {
    if (_currentStep > 0) {
      setState(() {
        _currentStep--;
        _errorMessage = null;
      });
    }
  }

  Future<void> _handleSubmit() async {
    if (!_validateStep(2)) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final controller = ref.read(ambulanceAuthControllerProvider);
      final formattedDob = DateFormat('yyyy-MM-dd').format(_selectedDob!);

      String? uploadedRcPath;
      if (_rcImageBytes != null && _rcImageFile != null) {
        uploadedRcPath = await controller.uploadRcDocument(
          tempRef: 'REG',
          fileBytes: _rcImageBytes!,
          fileName: _rcImageFile!.name,
        );
      }

      await controller.submitRegistration(
        vehicleNumber: _vehiclePlateController.text.trim().toUpperCase(),
        chassisEngineNumber: _chassisEngineController.text.trim().isEmpty
            ? null
            : _chassisEngineController.text.trim(),
        rcPhotoStoragePath: uploadedRcPath,
        driverLegalName: _driverNameController.text.trim(),
        dlNumber: _dlNumberController.text.trim().toUpperCase(),
        dob: formattedDob,
        contactNumber: _contactController.text.trim(),
        password: _passwordController.text,
        ais125Tier: _ais125Tier,
        ambulanceType: _ambulanceType,
      );

      if (!mounted) return;
      context.go('/crew/pending');
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString().replaceAll('Exception: ', '');
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(CrewStrings.registerCrewTitle),
        backgroundColor: AppColors.primaryDark,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (_currentStep > 0) {
              _onPrevious();
            } else {
              context.pop();
            }
          },
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildStepIndicator(),
              const SizedBox(height: 20),

              if (_errorMessage != null) ...[
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
                          _errorMessage!,
                          style: const TextStyle(
                            color: AppColors.danger,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: const BorderSide(color: AppColors.divider),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_currentStep == 0) _buildStep1Vehicle(),
                      if (_currentStep == 1) _buildStep2Driver(),
                      if (_currentStep == 2) _buildStep3Account(),
                      const SizedBox(height: 24),
                      _buildNavigationButtons(),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStepIndicator() {
    final steps = [
      CrewStrings.step1Title,
      CrewStrings.step2Title,
      CrewStrings.step3Title,
    ];

    return Row(
      children: List.generate(steps.length, (index) {
        final isActive = index == _currentStep;
        final isCompleted = index < _currentStep;

        return Expanded(
          child: Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: isActive
                        ? AppColors.primary
                        : (isCompleted
                            ? AppColors.primaryDark
                            : AppColors.surface),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isActive ? AppColors.primary : AppColors.divider,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        isCompleted
                            ? Icons.check_circle_rounded
                            : (index == 0
                                ? Icons.airport_shuttle_rounded
                                : (index == 1
                                    ? Icons.person_rounded
                                    : Icons.lock_rounded)),
                        size: 16,
                        color: (isActive || isCompleted)
                            ? Colors.white
                            : AppColors.textSecondary,
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          steps[index],
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: (isActive || isCompleted)
                                ? Colors.white
                                : AppColors.textSecondary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (index < steps.length - 1)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4),
                  child: Icon(Icons.chevron_right_rounded,
                      size: 16, color: AppColors.divider),
                ),
            ],
          ),
        );
      }),
    );
  }

  Widget _buildStep1Vehicle() {
    final liveFormatted = _formatPlateDisplay(_vehiclePlateController.text);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          CrewStrings.vehicleSectionTitle,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          CrewStrings.vehicleSectionSubtitle,
          style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 20),

        // Vehicle Plate with live formatting hint
        const Text(
          CrewStrings.vehicleNumberLabel,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _vehiclePlateController,
          textCapitalization: TextCapitalization.characters,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9\-]')),
          ],
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: CrewStrings.vehicleNumberHint,
            prefixIcon: const Icon(Icons.car_repair_rounded, color: AppColors.primary),
            helperText: liveFormatted.isNotEmpty
                ? 'Standard Format: $liveFormatted'
                : CrewStrings.vehicleFormatHint,
            helperStyle: const TextStyle(color: AppColors.primary, fontSize: 11),
            filled: true,
            fillColor: AppColors.background,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.divider),
            ),
          ),
        ),
        const SizedBox(height: 18),

        // Optional Chassis/Engine number
        const Text(
          CrewStrings.chassisEngineLabel,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _chassisEngineController,
          textCapitalization: TextCapitalization.characters,
          decoration: InputDecoration(
            hintText: CrewStrings.chassisEngineHint,
            prefixIcon: const Icon(Icons.qr_code_2_rounded, color: AppColors.textSecondary),
            filled: true,
            fillColor: AppColors.background,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.divider),
            ),
          ),
        ),
        const SizedBox(height: 18),

        // Optional RC Photo Upload
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              CrewStrings.rcDocumentLabel,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.primaryTint,
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text(
                CrewStrings.supportingDocBadge,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        const Text(
          CrewStrings.rcDocumentHelp,
          style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 8),

        if (_rcImageFile != null) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.successTint,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.success),
            ),
            child: Row(
              children: [
                const Icon(Icons.attach_file_rounded,
                    color: AppColors.success, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${CrewStrings.rcPhotoAttached}: ${_rcImageFile!.name}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppColors.success,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                TextButton(
                  onPressed: () {
                    setState(() {
                      _rcImageFile = null;
                      _rcImageBytes = null;
                    });
                  },
                  child: const Text(
                    CrewStrings.removePhoto,
                    style: TextStyle(color: AppColors.danger, fontSize: 11),
                  ),
                ),
              ],
            ),
          ),
        ] else ...[
          OutlinedButton.icon(
            onPressed: _pickRcPhoto,
            icon: const Icon(Icons.upload_file_rounded, color: AppColors.primary),
            label: const Text(CrewStrings.uploadRcButton),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              side: const BorderSide(color: AppColors.primary),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],

        const SizedBox(height: 18),

        // Ambulance Type
        const Text(
          CrewStrings.ambulanceTypeLabel,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          initialValue: _ambulanceType,
          isExpanded: true,
          decoration: InputDecoration(
            filled: true,
            fillColor: AppColors.background,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.divider),
            ),
          ),
          items: const [
            DropdownMenuItem(
              value: 'PRIVATE',
              child: Text(
                'Private Ambulance Service',
                overflow: TextOverflow.ellipsis,
              ),
            ),
            DropdownMenuItem(
              value: 'GOVERNMENT',
              child: Text(
                'Government / 108 Emergency Service',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
          onChanged: (val) {
            if (val != null) setState(() => _ambulanceType = val);
          },
        ),
        const SizedBox(height: 18),

        // AIS-125 Tier
        const Text(
          CrewStrings.ais125TierLabel,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          initialValue: _ais125Tier,
          isExpanded: true,
          decoration: InputDecoration(
            filled: true,
            fillColor: AppColors.background,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.divider),
            ),
          ),
          items: const [
            DropdownMenuItem(
              value: 'TYPE_A',
              child: Text(
                'Type A: First Responder / Basic Transport',
                overflow: TextOverflow.ellipsis,
              ),
            ),
            DropdownMenuItem(
              value: 'TYPE_B',
              child: Text(
                'Type B: Patient Transport (BLS)',
                overflow: TextOverflow.ellipsis,
              ),
            ),
            DropdownMenuItem(
              value: 'TYPE_C',
              child: Text(
                'Type C: Advanced Life Support (ALS)',
                overflow: TextOverflow.ellipsis,
              ),
            ),
            DropdownMenuItem(
              value: 'TYPE_D',
              child: Text(
                'Type D: Mobile Intensive Care (MICU)',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
          onChanged: (val) {
            if (val != null) setState(() => _ais125Tier = val);
          },
        ),
      ],
    );
  }

  Widget _buildStep2Driver() {
    final dobFormatted = _selectedDob != null
        ? DateFormat('yyyy-MM-dd').format(_selectedDob!)
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          CrewStrings.driverSectionTitle,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          CrewStrings.driverSectionSubtitle,
          style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 20),

        // Driver Legal Name
        const Text(
          CrewStrings.driverLegalNameLabel,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _driverNameController,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            hintText: CrewStrings.driverLegalNameHint,
            prefixIcon: const Icon(Icons.person_outline_rounded, color: AppColors.primary),
            filled: true,
            fillColor: AppColors.background,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.divider),
            ),
          ),
        ),
        const SizedBox(height: 18),

        // DL Number
        const Text(
          CrewStrings.dlNumberLabel,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _dlNumberController,
          textCapitalization: TextCapitalization.characters,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9\-]')),
          ],
          decoration: InputDecoration(
            hintText: CrewStrings.dlNumberHint,
            prefixIcon: const Icon(Icons.badge_outlined, color: AppColors.primary),
            helperText: CrewStrings.dlFormatHint,
            filled: true,
            fillColor: AppColors.background,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.divider),
            ),
          ),
        ),
        const SizedBox(height: 18),

        // Date of Birth
        const Text(
          CrewStrings.dobLabel,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        InkWell(
          onTap: _selectDateOfBirth,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.divider),
            ),
            child: Row(
              children: [
                const Icon(Icons.calendar_today_rounded,
                    size: 20, color: AppColors.primary),
                const SizedBox(width: 12),
                Text(
                  dobFormatted ?? CrewStrings.dobHint,
                  style: TextStyle(
                    fontSize: 14,
                    color: dobFormatted != null
                        ? AppColors.textPrimary
                        : AppColors.textSecondary,
                  ),
                ),
                const Spacer(),
                const Icon(Icons.arrow_drop_down, color: AppColors.textSecondary),
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),

        // Contact Number
        const Text(
          CrewStrings.contactNumberLabel,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _contactController,
          keyboardType: TextInputType.phone,
          decoration: InputDecoration(
            hintText: CrewStrings.contactNumberHint,
            prefixIcon: const Icon(Icons.phone_outlined, color: AppColors.primary),
            filled: true,
            fillColor: AppColors.background,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.divider),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStep3Account() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          CrewStrings.accountSectionTitle,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          CrewStrings.accountSectionSubtitle,
          style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 20),

        // Summary Card
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.primaryTint,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Registration Summary',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primaryDark,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Vehicle:', style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                  Text(
                    _formatPlateDisplay(_vehiclePlateController.text),
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Driver:', style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                  Text(
                    _driverNameController.text.trim(),
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Tier:', style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                  Text(
                    _ais125Tier,
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),

        // Password
        const Text(
          CrewStrings.passwordLabel,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _passwordController,
          obscureText: _obscurePassword,
          decoration: InputDecoration(
            hintText: CrewStrings.passwordHint,
            prefixIcon: const Icon(Icons.lock_outline_rounded, color: AppColors.primary),
            suffixIcon: IconButton(
              icon: Icon(
                _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                color: AppColors.textSecondary,
              ),
              onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
            ),
            filled: true,
            fillColor: AppColors.background,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.divider),
            ),
          ),
        ),
        const SizedBox(height: 18),

        // Confirm Password
        const Text(
          CrewStrings.confirmPasswordLabel,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _confirmPasswordController,
          obscureText: _obscureConfirm,
          decoration: InputDecoration(
            hintText: CrewStrings.confirmPasswordHint,
            prefixIcon: const Icon(Icons.lock_reset_rounded, color: AppColors.primary),
            suffixIcon: IconButton(
              icon: Icon(
                _obscureConfirm ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                color: AppColors.textSecondary,
              ),
              onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
            ),
            filled: true,
            fillColor: AppColors.background,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.divider),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildNavigationButtons() {
    return Row(
      children: [
        if (_currentStep > 0) ...[
          Expanded(
            child: OutlinedButton(
              onPressed: _isLoading ? null : _onPrevious,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: const Text(CrewStrings.previousStep),
            ),
          ),
          const SizedBox(width: 12),
        ],
        Expanded(
          flex: _currentStep == 0 ? 1 : 1,
          child: ElevatedButton(
            onPressed: _isLoading ? null : _onNext,
            style: ElevatedButton.styleFrom(
              minimumSize: const Size.fromHeight(50),
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: _isLoading
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Colors.white,
                    ),
                  )
                : Text(
                    _currentStep == 2
                        ? CrewStrings.submitRegistration
                        : CrewStrings.nextStep,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}
