import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../core/theme.dart';
import '../../models/appointment.dart';
import '../../providers/appointment_providers.dart';

class MyAppointmentsScreen extends ConsumerStatefulWidget {
  const MyAppointmentsScreen({super.key});

  @override
  ConsumerState<MyAppointmentsScreen> createState() => _MyAppointmentsScreenState();
}

class _MyAppointmentsScreenState extends ConsumerState<MyAppointmentsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    // Ensure an anonymous session exists so the patient stream can read Firestore
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(appointmentServiceProvider).ensureAuthenticatedUid();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appointmentsAsync = ref.watch(patientAppointmentsStreamProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('My Appointments'),
        backgroundColor: AppColors.primaryDark,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          indicatorWeight: 3,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white.withValues(alpha: 0.7),
          labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          tabs: const [
            Tab(text: 'Upcoming'),
            Tab(text: 'Past & Completed'),
          ],
        ),
      ),
      body: appointmentsAsync.when(
        data: (appointments) {
          final upcoming = appointments.where((a) => a.isUpcoming).toList();
          final past = appointments.where((a) => !a.isUpcoming).toList();

          return TabBarView(
            controller: _tabController,
            children: [
              _buildAppointmentsList(
                context,
                upcoming,
                emptyTitle: 'No Upcoming Appointments',
                emptySubtitle:
                    'You have no scheduled appointments. Book a verified clinic or diagnostic lab visit.',
                showBrowseButton: true,
              ),
              _buildAppointmentsList(
                context,
                past,
                emptyTitle: 'No Past Appointments',
                emptySubtitle: 'Your previous appointment history will appear here.',
                showBrowseButton: false,
              ),
            ],
          );
        },
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
        error: (err, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline_rounded, color: AppColors.warning, size: 40),
                const SizedBox(height: 12),
                Text(
                  'Failed to load appointments: $err',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: () => ref.refresh(patientAppointmentsStreamProvider),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAppointmentsList(
    BuildContext context,
    List<Appointment> list, {
    required String emptyTitle,
    required String emptySubtitle,
    required bool showBrowseButton,
  }) {
    if (list.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: AppColors.primaryTint,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.calendar_today_rounded,
                  size: 40,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                emptyTitle,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                emptySubtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.4),
              ),
              if (showBrowseButton) ...[
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  onPressed: () => context.push('/patient/clinics/search'),
                  icon: const Icon(Icons.search_rounded, size: 18),
                  label: const Text('Find Clinics & Labs'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }

    final dateFmt = DateFormat('EEE, d MMM yyyy');
    final timeFmt = DateFormat('h:mm a');

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: list.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final item = list[index];
        final isLab = item.clinicType.toLowerCase().contains('lab');
        final isConfirmed = item.status == 'confirmed';
        final isRefunded = item.status == 'refunded';

        Color statusBg = AppColors.successTint;
        Color statusColor = AppColors.success;
        String statusLabel = 'CONFIRMED';

        if (isRefunded) {
          statusBg = AppColors.warningTint;
          statusColor = AppColors.warningText;
          statusLabel = 'REFUNDED';
        } else if (!isConfirmed) {
          statusBg = const Color(0xFFF0F4F5);
          statusColor = AppColors.textSecondary;
          statusLabel = item.status.toUpperCase();
        }

        return Card(
          child: InkWell(
            onTap: () {
              context.push(
                '/patient/appointments/confirmation',
                extra: item,
              );
            },
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
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
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: statusBg,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          statusLabel,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: statusColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    item.clinicName,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Builder(
                    builder: (context) {
                      final kolkataTime = item.startTime.toUtc().add(const Duration(hours: 5, minutes: 30));
                      return Row(
                        children: [
                          const Icon(Icons.access_time_rounded,
                              size: 15, color: AppColors.textSecondary),
                          const SizedBox(width: 6),
                          Text(
                            '${dateFmt.format(kolkataTime)} at ${timeFmt.format(kolkataTime)} IST',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Ref: ${item.id}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontFamily: 'monospace',
                          color: AppColors.textSecondary,
                        ),
                      ),
                      Text(
                        '₹${item.amountRupees} Paid',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primaryDark,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
