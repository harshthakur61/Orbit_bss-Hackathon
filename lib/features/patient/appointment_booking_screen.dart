import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import '../../core/constants/booking_constants.dart';
import '../../core/theme.dart';
import '../../models/appointment.dart';
import '../../models/clinic.dart';
import '../../providers/appointment_providers.dart';
import '../../providers/patient_auth_provider.dart';

class AppointmentBookingScreen extends ConsumerStatefulWidget {
  final Clinic clinic;

  const AppointmentBookingScreen({
    super.key,
    required this.clinic,
  });

  @override
  ConsumerState<AppointmentBookingScreen> createState() =>
      _AppointmentBookingScreenState();
}

class _AppointmentBookingScreenState
    extends ConsumerState<AppointmentBookingScreen>
    with WidgetsBindingObserver {
  late DateTime _selectedDate;
  late List<DateTime> _next7Days;
  DaySlotItem? _selectedSlot;

  List<DaySlotItem> _slots = [];
  bool _isLoadingSlots = false;
  String? _slotsError;

  // Form controllers
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _phoneController;

  // Hold Countdown & Submission State
  bool _isSubmitting = false;
  Timer? _holdTimer;
  int _holdSecondsLeft = 0;
  String? _activeAppointmentId;

  static const Color _bookedSlotColor = Color(0xFFB8860B); // Dark Yellow
  static const Color _bookedSlotBg = Color(0xFFFFF9E6);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Compute next 7 days in Asia/Kolkata
    final kolkataNow = _getKolkataNow();
    _selectedDate = DateTime(kolkataNow.year, kolkataNow.month, kolkataNow.day);
    _next7Days = List.generate(
      BookingConstants.maxAdvanceBookingDays,
      (i) => DateTime(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day + i,
      ),
    );

    // Prefill patient details
    final profile = ref.read(patientAuthProvider).profile;
    _nameController = TextEditingController(text: profile.name);

    // Clean Indian phone to 10 digits
    final rawPhone = profile.phone.replaceAll(RegExp(r'[^0-9]'), '');
    final cleanPhone = rawPhone.length > 10 ? rawPhone.substring(rawPhone.length - 10) : rawPhone;
    _phoneController = TextEditingController(text: cleanPhone);

    _fetchSlotsForDate(_selectedDate);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _holdTimer?.cancel();
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Refresh slot grid when user resumes screen
      _fetchSlotsForDate(_selectedDate);
    }
  }

  DateTime _getKolkataNow() {
    final utc = DateTime.now().toUtc();
    return utc.add(const Duration(hours: 5, minutes: 30));
  }

  String _formatDateKey(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y$m$d';
  }

  Future<void> _fetchSlotsForDate(DateTime date) async {
    setState(() {
      _isLoadingSlots = true;
      _slotsError = null;
      // Clear selection if date changed or on refresh
      if (_selectedSlot != null && _formatDateKey(date) != _formatDateKey(_selectedDate)) {
        _selectedSlot = null;
      }
    });

    final dateKey = _formatDateKey(date);
    try {
      final service = ref.read(appointmentServiceProvider);
      final fetched = await service.getClinicDaySlots(
        clinicId: widget.clinic.id,
        dateKey: dateKey,
      );

      if (mounted) {
        setState(() {
          _slots = fetched;
          _isLoadingSlots = false;
          // Re-validate previously selected slot in newly fetched slots
          if (_selectedSlot != null) {
            final match = _slots.where((s) => s.slotId == _selectedSlot!.slotId).firstOrNull;
            if (match == null || match.status != SlotStatus.free) {
              _selectedSlot = null;
            }
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingSlots = false;
          _slotsError = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  void _startHoldTimer(int seconds) {
    _holdTimer?.cancel();
    setState(() {
      _holdSecondsLeft = seconds;
    });

    _holdTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_holdSecondsLeft <= 1) {
        timer.cancel();
        _onHoldExpired();
      } else {
        setState(() {
          _holdSecondsLeft--;
        });
      }
    });
  }

  void _stopHoldTimer() {
    _holdTimer?.cancel();
    _holdTimer = null;
    if (mounted) {
      setState(() {
        _holdSecondsLeft = 0;
      });
    }
  }

  void _onHoldExpired() {
    if (_activeAppointmentId != null) {
      ref.read(appointmentServiceProvider).releaseAppointmentHold(_activeAppointmentId!);
    }
    setState(() {
      _holdSecondsLeft = 0;
      _selectedSlot = null;
      _activeAppointmentId = null;
      _isSubmitting = false;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Your 5-minute slot hold has expired. Please pick a slot again.'),
        backgroundColor: AppColors.warning,
      ),
    );

    _fetchSlotsForDate(_selectedDate);
  }

  Future<void> _handlePaymentFlow() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    if (_selectedSlot == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select an available appointment time slot.')),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    final appointmentService = ref.read(appointmentServiceProvider);
    final patientName = _nameController.text.trim();
    final patientPhone = _phoneController.text.trim();

    try {
      // 1. Create appointment hold & Razorpay Order on server
      final orderResult = await appointmentService.createAppointmentOrder(
        clinicId: widget.clinic.id,
        startTime: _selectedSlot!.startTime,
        patientName: patientName,
        patientPhone: patientPhone,
      );

      final appointmentId = orderResult['appointmentId'] as String;
      final orderId = orderResult['orderId'] as String;
      final amountPaise = (orderResult['amountPaise'] as num).toInt();
      final keyId = orderResult['keyId'] as String;

      _activeAppointmentId = appointmentId;

      // 2. Start 5-minute hold timer
      _startHoldTimer(BookingConstants.slotHoldDurationMinutes * 60);

      // 3. Open Razorpay Checkout via delegate
      appointmentService.paymentDelegate.openCheckout(
        keyId: keyId,
        orderId: orderId,
        amountPaise: amountPaise,
        clinicName: widget.clinic.name,
        patientName: patientName,
        patientPhone: patientPhone,
        onSuccess: (PaymentSuccessResponse response) async {
          await _onPaymentSuccess(
            appointmentId: appointmentId,
            orderId: response.orderId ?? orderId,
            paymentId: response.paymentId ?? '',
            signature: response.signature ?? '',
          );
        },
        onError: (PaymentFailureResponse response) async {
          await _onPaymentCancelledOrFailed(
            appointmentId: appointmentId,
            errorMessage: response.message ?? 'Payment cancelled',
          );
        },
        onExternalWallet: (ExternalWalletResponse response) {
          // External wallet selected
        },
      );
    } catch (e) {
      if (mounted) {
        final msg = e.toString().replaceFirst('Exception: ', '');
        if (msg.contains('That slot was just booked')) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('That slot was just booked. Pick another'),
              backgroundColor: AppColors.warning,
            ),
          );
          _fetchSlotsForDate(_selectedDate);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(msg)),
          );
        }
        setState(() => _isSubmitting = false);
      }
    }
  }

  Future<void> _onPaymentSuccess({
    required String appointmentId,
    required String orderId,
    required String paymentId,
    required String signature,
  }) async {
    try {
      final appointmentService = ref.read(appointmentServiceProvider);
      final verifyResult = await appointmentService.verifyAppointmentPayment(
        appointmentId: appointmentId,
        razorpayOrderId: orderId,
        razorpayPaymentId: paymentId,
        razorpaySignature: signature,
      );

      _stopHoldTimer();

      if (verifyResult['success'] == true && verifyResult['status'] == 'confirmed') {
        final confirmedAppointment = Appointment(
          id: appointmentId,
          patientUid: '',
          patientName: _nameController.text.trim(),
          patientPhone: _phoneController.text.trim(),
          clinicId: widget.clinic.id,
          clinicName: widget.clinic.name,
          clinicType: widget.clinic.type,
          slotId: _selectedSlot?.slotId ?? '',
          startTime: _selectedSlot?.startTime ?? DateTime.now(),
          status: 'confirmed',
          amountPaise: widget.clinic.bookingFeeRupees * 100,
          razorpayOrderId: orderId,
          razorpayPaymentId: paymentId,
          confirmedAt: DateTime.now(),
          clinicAddress: widget.clinic.address,
          clinicPhone: widget.clinic.phone,
          clinicLat: widget.clinic.lat,
          clinicLng: widget.clinic.lng,
        );

        if (mounted) {
          context.pushReplacement(
            '/patient/appointments/confirmation',
            extra: confirmedAppointment,
          );
        }
      } else {
        // Refunded due to slot hold collision
        final reason = verifyResult['reason'] ?? 'Hold expired and slot was claimed; payment was refunded.';
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(reason),
              backgroundColor: AppColors.warning,
            ),
          );
          setState(() {
            _isSubmitting = false;
            _selectedSlot = null;
          });
          _fetchSlotsForDate(_selectedDate);
        }
      }
    } catch (e) {
      _stopHoldTimer();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Payment verification error: $e')),
        );
        setState(() => _isSubmitting = false);
      }
    }
  }

  Future<void> _onPaymentCancelledOrFailed({
    required String appointmentId,
    required String errorMessage,
  }) async {
    _stopHoldTimer();
    final appointmentService = ref.read(appointmentServiceProvider);
    await appointmentService.releaseAppointmentHold(appointmentId);

    if (mounted) {
      setState(() {
        _isSubmitting = false;
        _activeAppointmentId = null;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Payment cancelled. Slot hold released.'),
          action: SnackBarAction(
            label: 'OK',
            textColor: Colors.white,
            onPressed: () {},
          ),
        ),
      );
      _fetchSlotsForDate(_selectedDate);
    }
  }

  String _formatTimerCountdown(int totalSeconds) {
    final m = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final s = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final isLab = widget.clinic.type.toLowerCase().contains('lab');
    final fee = widget.clinic.bookingFeeRupees;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Book Appointment'),
        backgroundColor: AppColors.primaryDark,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: RefreshIndicator(
                onRefresh: () => _fetchSlotsForDate(_selectedDate),
                color: AppColors.primary,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Clinic Header Info Card
                      _buildClinicHeader(isLab),

                      const SizedBox(height: 16),

                      // 7-Day Date Strip
                      _buildDateStrip(),

                      const SizedBox(height: 20),

                      // Hold Timer Banner (if active)
                      if (_holdSecondsLeft > 0) _buildHoldBanner(),

                      // Slot Grid Header & Legend
                      _buildSlotGridHeader(),

                      const SizedBox(height: 12),

                      // Slot Grid / Skeleton Loader / Empty State
                      _buildSlotGrid(),

                      const SizedBox(height: 24),

                      // Patient Details Form
                      _buildPatientDetailsForm(),

                      const SizedBox(height: 80), // Padding for sticky bottom bar
                    ],
                  ),
                ),
              ),
            ),

            // Sticky Bottom Bar
            _buildStickyBottomBar(fee),
          ],
        ),
      ),
    );
  }

  Widget _buildClinicHeader(bool isLab) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    widget.clinic.name,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: isLab ? AppColors.infoTint : AppColors.primaryTint,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    isLab ? 'PATHOLOGY LAB' : 'CLINIC',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: isLab ? AppColors.info : AppColors.primaryDark,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.location_on_outlined, size: 15, color: AppColors.textSecondary),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    widget.clinic.address,
                    style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.access_time_rounded, size: 15, color: AppColors.textSecondary),
                const SizedBox(width: 4),
                Text(
                  'Operating Hours: ${widget.clinic.operatingHours}',
                  style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDateStrip() {
    final dayNameFmt = DateFormat('EEE');
    final dayNumFmt = DateFormat('d');
    final monthFmt = DateFormat('MMM');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Select Date (Next 7 Days)',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 90,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _next7Days.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final date = _next7Days[index];
              final isSelected = _formatDateKey(date) == _formatDateKey(_selectedDate);
              final isToday = index == 0;

              return InkWell(
                onTap: () {
                  if (_formatDateKey(date) != _formatDateKey(_selectedDate)) {
                    setState(() {
                      _selectedDate = date;
                    });
                    _fetchSlotsForDate(date);
                  }
                },
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  width: 68,
                  padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                  decoration: BoxDecoration(
                    color: isSelected ? AppColors.primary : AppColors.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isSelected ? AppColors.primary : AppColors.divider,
                      width: isSelected ? 2 : 1,
                    ),
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                              color: AppColors.primary.withValues(alpha: 0.25),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ]
                        : null,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      Text(
                        isToday ? 'Today' : dayNameFmt.format(date),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: isSelected ? Colors.white : AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        dayNumFmt.format(date),
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: isSelected ? Colors.white : AppColors.textPrimary,
                        ),
                      ),
                      Text(
                        monthFmt.format(date),
                        style: TextStyle(
                          fontSize: 10,
                          color: isSelected ? Colors.white.withValues(alpha: 0.9) : AppColors.textSecondary,
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
  }

  Widget _buildHoldBanner() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.warningTint,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.timer_outlined, color: AppColors.warningText, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Slot reserved for ${_formatTimerCountdown(_holdSecondsLeft)}. Complete payment before timer expires.',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.warningText,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSlotGridHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Available Slots (IST)',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
            ),
            if (_isLoadingSlots)
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
          ],
        ),
        const SizedBox(height: 8),
        // Small Legend Row
        Row(
          children: [
            _buildLegendItem(
              color: AppColors.surface,
              borderColor: AppColors.divider,
              label: 'Available',
            ),
            const SizedBox(width: 12),
            _buildLegendItem(
              color: _bookedSlotColor,
              label: 'Booked',
            ),
            const SizedBox(width: 12),
            _buildLegendItem(
              color: AppColors.primary,
              label: 'Selected',
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildLegendItem({
    required Color color,
    Color? borderColor,
    required String label,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
            border: borderColor != null ? Border.all(color: borderColor) : null,
          ),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
        ),
      ],
    );
  }

  Widget _buildSlotGrid() {
    if (_isLoadingSlots) {
      // Skeleton loader
      return GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 4,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 2.1,
        ),
        itemCount: 12,
        itemBuilder: (_, _) => Container(
          decoration: BoxDecoration(
            color: const Color(0xFFEAEFF0),
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      );
    }

    if (_slotsError != null) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.divider),
        ),
        child: Column(
          children: [
            const Icon(Icons.info_outline_rounded, color: AppColors.warning, size: 32),
            const SizedBox(height: 8),
            Text(
              _slotsError!,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: () => _fetchSlotsForDate(_selectedDate),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_slots.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.divider),
        ),
        child: Column(
          children: const [
            Icon(Icons.event_busy_rounded, color: AppColors.textSecondary, size: 36),
            SizedBox(height: 8),
            Text(
              'Clinic Closed',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            SizedBox(height: 4),
            Text(
              'The clinic is closed on this day. Please pick another date.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          ],
        ),
      );
    }

    final allSlotsPast = _slots.isNotEmpty && _slots.every((s) => s.status == SlotStatus.past);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (allSlotsPast)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.warningTint,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: const [
                Icon(Icons.nightlight_round, color: AppColors.warningText, size: 18),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'All appointment slots for today have already passed. Please select an upcoming date.',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.warningText,
                    ),
                  ),
                ),
              ],
            ),
          ),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 4,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 2.1,
          ),
          itemCount: _slots.length,
          itemBuilder: (context, index) {
            final slot = _slots[index];
            final isSelected = _selectedSlot?.slotId == slot.slotId;
            final isFree = slot.status == SlotStatus.free;
            final isBooked = slot.status == SlotStatus.booked;
            final isPast = slot.status == SlotStatus.past;

            Color bgColor;
            Color textColor;
            Border? border;

            if (isSelected) {
              bgColor = AppColors.primary;
              textColor = Colors.white;
              border = Border.all(color: AppColors.primaryDark, width: 1.5);
            } else if (isBooked) {
              bgColor = _bookedSlotBg;
              textColor = _bookedSlotColor;
              border = Border.all(color: _bookedSlotColor.withValues(alpha: 0.6));
            } else if (isPast) {
              bgColor = const Color(0xFFF0F4F5);
              textColor = const Color(0xFF9E9E9E);
              border = Border.all(color: const Color(0xFFE0E5E7));
            } else {
              // Free
              bgColor = AppColors.surface;
              textColor = AppColors.textPrimary;
              border = Border.all(color: AppColors.divider);
            }

            return InkWell(
              onTap: isFree && !_isSubmitting
                  ? () {
                      setState(() {
                        _selectedSlot = slot;
                      });
                    }
                  : null,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: BorderRadius.circular(8),
                  border: border,
                ),
                alignment: Alignment.center,
                child: Text(
                  slot.time,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: isSelected || isBooked ? FontWeight.bold : FontWeight.w500,
                    color: textColor,
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildPatientDetailsForm() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Patient Details',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _nameController,
            decoration: InputDecoration(
              labelText: 'Full Legal Name *',
              prefixIcon: const Icon(Icons.person_outline_rounded, color: AppColors.primary),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              filled: true,
              fillColor: AppColors.surface,
            ),
            validator: (val) {
              if (val == null || val.trim().isEmpty) {
                return 'Please enter patient name.';
              }
              if (val.trim().length < 2) {
                return 'Name must be at least 2 characters.';
              }
              return null;
            },
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _phoneController,
            keyboardType: TextInputType.phone,
            maxLength: 10,
            decoration: InputDecoration(
              labelText: '10-Digit Mobile Number *',
              prefixText: '+91 ',
              prefixIcon: const Icon(Icons.phone_android_rounded, color: AppColors.primary),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              filled: true,
              fillColor: AppColors.surface,
              counterText: '',
            ),
            validator: (val) {
              if (val == null || val.trim().isEmpty) {
                return 'Please enter 10-digit mobile number.';
              }
              final clean = val.trim();
              if (!RegExp(r'^[6-9]\d{9}$').hasMatch(clean)) {
                return 'Enter a valid 10-digit Indian mobile (starts with 6-9).';
              }
              return null;
            },
          ),
        ],
      ),
    );
  }

  Widget _buildStickyBottomBar(int fee) {
    final timeStr = _selectedSlot?.time;
    final dateFmt = DateFormat('EEE, d MMM');
    final formattedDate = dateFmt.format(_selectedDate);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  timeStr != null ? '$formattedDate · $timeStr' : 'No slot selected',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: timeStr != null ? AppColors.textPrimary : AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Convenience fee: ₹$fee',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          ElevatedButton(
            onPressed: (_selectedSlot != null && !_isSubmitting)
                ? _handlePaymentFlow
                : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: _isSubmitting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : Text(
                    'Pay ₹$fee & confirm',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
          ),
        ],
      ),
    );
  }
}
