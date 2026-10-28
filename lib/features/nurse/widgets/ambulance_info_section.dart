import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/theme.dart';
import '../../../models/emergency_request.dart';

class AmbulanceInfoSection extends StatelessWidget {
  final EmergencyRequest request;
  final bool showCallButton;

  const AmbulanceInfoSection({
    super.key,
    required this.request,
    this.showCallButton = true,
  });

  Future<void> _callDriver(BuildContext context, String phone) async {
    final cleanPhone = phone.replaceAll(RegExp(r'[^\d+]'), '');
    final uri = Uri.parse('tel:$cleanPhone');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not open dialer for $phone'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    }
  }

  Color _severityColor(String severity) {
    switch (severity.toLowerCase()) {
      case 'critical':
        return AppColors.danger;
      case 'serious':
        return AppColors.warning;
      case 'stable':
      default:
        return AppColors.success;
    }
  }

  @override
  Widget build(BuildContext context) {
    final amb = request.ambulance;

    final driverName = amb != null && amb.driverName.trim().isNotEmpty
        ? amb.driverName.trim()
        : 'Not available';
    final vehicleNumber = amb != null && amb.vehicleNumber.trim().isNotEmpty
        ? amb.vehicleNumber.trim()
        : 'Not available';
    final driverPhone = amb != null && amb.driverPhone.trim().isNotEmpty
        ? amb.driverPhone.trim()
        : 'Not available';
    final ambulanceType = amb != null && amb.ambulanceType.trim().isNotEmpty
        ? amb.ambulanceType.trim()
        : 'Not available';
    final aisTier = amb != null && amb.ais125Tier.trim().isNotEmpty
        ? amb.ais125Tier.trim()
        : 'Not available';

    final hasValidPhone = driverPhone != 'Not available' &&
        driverPhone.replaceAll(RegExp(r'[^\d]'), '').isNotEmpty;

    final sevColor = _severityColor(request.severity);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Driver & Vehicle Card
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.divider),
          ),
          child: Column(
            children: [
              if (request.handover != null) ...[
                Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.primaryTint,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.swap_horiz_rounded, size: 16, color: AppColors.primary),
                      const SizedBox(width: 6),
                      Text(
                        'Relief Ambulance • Transferred from ${request.handover!.fromAmbulanceId}',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primaryDark,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.primaryTint,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.airport_shuttle_rounded,
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
                          vehicleNumber,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '$driverName • $aisTier ($ambulanceType)',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (showCallButton && hasValidPhone)
                    IconButton.filledTonal(
                      onPressed: () => _callDriver(context, driverPhone),
                      icon: const Icon(Icons.phone_in_talk_rounded),
                      tooltip: 'Call Driver ($driverPhone)',
                      style: IconButton.styleFrom(
                        backgroundColor: AppColors.primaryTint,
                        foregroundColor: AppColors.primary,
                      ),
                    ),
                ],
              ),
              if (driverPhone != 'Not available') ...[
                const Divider(height: 18),
                Row(
                  children: [
                    const Icon(
                      Icons.call_outlined,
                      size: 15,
                      color: AppColors.textSecondary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Driver Contact: $driverPhone',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),

        const SizedBox(height: 12),

        // Bed Requirements & Severity Row
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: request.needs.map((need) {
                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withAlpha(20),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: AppColors.primary.withAlpha(80),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.hotel_rounded,
                          size: 14,
                          color: AppColors.primary,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          need,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primaryDark,
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: sevColor,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                request.severity.toUpperCase(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),

        // Clinical Note
        if (request.note != null && request.note!.trim().isNotEmpty) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.divider),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.note_alt_outlined,
                  size: 16,
                  color: AppColors.textSecondary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '"${request.note!}"',
                    style: const TextStyle(
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
