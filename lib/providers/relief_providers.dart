import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/emergency_request.dart';
import '../models/relief_offer_data.dart';
import '../models/relief_request.dart';
import '../services/ambulance_auth_service.dart';

/// Result wrapper for relief callables
class ReliefResponseResult {
  final bool success;
  final String? code;
  final String message;
  final String? reliefRequestId;
  final String? originalRequestId;
  final String? status;

  const ReliefResponseResult({
    required this.success,
    this.code,
    required this.message,
    this.reliefRequestId,
    this.originalRequestId,
    this.status,
  });

  bool get isAlreadyTaken =>
      code == 'ALREADY_TAKEN' || message.toLowerCase().contains('taken');

  bool get isExpired =>
      code == 'OFFER_EXPIRED' || message.toLowerCase().contains('expired');
}

/// Active incoming relief request offer shown over the crew terminal
class ActiveReliefOfferNotifier extends Notifier<ReliefOfferData?> {
  StreamSubscription<ReliefOfferData?>? _sub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _firestoreSub;

  @override
  ReliefOfferData? build() {
    _sub?.cancel();
    _sub = ReliefService.reliefAlertStream.listen((offer) {
      state = offer;
    });

    _listenToIncomingOffers();

    ref.onDispose(() {
      _sub?.cancel();
      _firestoreSub?.cancel();
    });
    return null;
  }

  void _listenToIncomingOffers() {
    _firestoreSub?.cancel();
    try {
      if (Firebase.apps.isEmpty) return;
      _firestoreSub = FirebaseFirestore.instance
          .collection('reliefRequests')
          .where('status', isEqualTo: 'searching')
          .snapshots()
          .listen((snapshot) async {
        final currentUid = AmbulanceAuthService.currentSessionUid;
        if (currentUid == null || currentUid.isEmpty) return;

        for (final doc in snapshot.docs) {
          final data = doc.data();
          if (data['requesterUid'] == currentUid) continue;

          DateTime? expiresAt;
          final rawExpires = data['offerExpiresAt'];
          if (rawExpires is Timestamp) {
            expiresAt = rawExpires.toDate();
          } else if (rawExpires is String) {
            expiresAt = DateTime.tryParse(rawExpires);
          }

          if (expiresAt != null && DateTime.now().isAfter(expiresAt)) {
            continue;
          }

          // Check if candidate offer exists for this crew
          final offerDoc = await doc.reference.collection('offers').doc(currentUid).get();
          if (offerDoc.exists && offerDoc.data()?['status'] == 'pending') {
            final offerMap = offerDoc.data()!;
            final requesterAmb = data['requesterAmbulance'] as Map<String, dynamic>? ?? {};

            final offerData = ReliefOfferData(
              reliefRequestId: doc.id,
              distanceKm: (offerMap['distanceKm'] as num?)?.toDouble() ?? 1.2,
              etaMin: (offerMap['etaMin'] as num?)?.toInt() ?? 4,
              reason: data['reason']?.toString() ?? 'Breakdown',
              severity: data['severity']?.toString() ?? 'serious',
              offerExpiresAt: expiresAt ?? DateTime.now().add(const Duration(seconds: 60)),
              wave: (data['wave'] as num?)?.toInt() ?? 0,
              ais125Tier: requesterAmb['ais125Tier']?.toString(),
              disabledAmbulanceId: requesterAmb['ambulanceId']?.toString(),
              disabledAmbulanceVehicleNumber: requesterAmb['vehicleNumber']?.toString(),
              originalRequestId: data['originalRequestId']?.toString(),
            );

            if (state?.reliefRequestId != offerData.reliefRequestId) {
              ReliefService.postReliefOffer(offerData);
            }
            break;
          }
        }
      });
    } catch (e) {
      debugPrint('[ActiveReliefOfferNotifier] listener error: $e');
    }
  }

  void setOffer(ReliefOfferData offer) {
    state = offer;
  }

  void clear() {
    state = null;
  }
}

final activeReliefOfferProvider =
    NotifierProvider<ActiveReliefOfferNotifier, ReliefOfferData?>(
  ActiveReliefOfferNotifier.new,
);

/// Service providing operations for relief requests
class ReliefService {
  final FirebaseFunctions? _injectedFunctions;
  final FirebaseFirestore? _injectedFirestore;

  static final StreamController<ReliefOfferData?> _reliefAlertController =
      StreamController<ReliefOfferData?>.broadcast();

  static Stream<ReliefOfferData?> get reliefAlertStream =>
      _reliefAlertController.stream;

  static void postReliefOffer(ReliefOfferData offer) {
    _reliefAlertController.add(offer);
  }

  static void clearReliefOffer() {
    _reliefAlertController.add(null);
  }

  ReliefService({
    FirebaseFunctions? functions,
    FirebaseFirestore? firestore,
  })  : _injectedFunctions = functions,
        _injectedFirestore = firestore;

  FirebaseFunctions get _functions =>
      _injectedFunctions ?? FirebaseFunctions.instance;
  FirebaseFirestore get _firestore =>
      _injectedFirestore ?? FirebaseFirestore.instance;

  /// Creates a relief request for a disabled ambulance trip
  Future<ReliefResponseResult> createReliefRequest({
    required String originalRequestId,
    required String reason, // 'breakdown' | 'accident' | 'flat_tyre' | 'fuel' | 'other'
  }) async {
    try {
      final callable = _functions.httpsCallable('createReliefRequest');
      final response = await callable.call<Map<dynamic, dynamic>>({
        'originalRequestId': originalRequestId,
        'reason': reason,
      });

      final data = Map<String, dynamic>.from(response.data);
      return ReliefResponseResult(
        success: data['success'] == true,
        reliefRequestId: data['reliefRequestId'] as String?,
        status: data['status'] as String?,
        message: (data['message'] as String?) ?? 'Relief request created',
      );
    } catch (e) {
      debugPrint('[ReliefService] createReliefRequest Cloud Function failed; executing direct Firestore fallback: $e');
      return _fallbackCreateReliefRequest(
        originalRequestId: originalRequestId,
        reason: reason,
      );
    }
  }

  Future<ReliefResponseResult> _fallbackCreateReliefRequest({
    required String originalRequestId,
    required String reason,
  }) async {
    try {
      final callerUid = AmbulanceAuthService.currentSessionUid ?? 'demo-crew-100';

      // 1. Get original emergency request safely
      Map<String, dynamic> reqData = {};
      try {
        final reqDoc = await _firestore.collection('requests').doc(originalRequestId).get();
        if (reqDoc.exists && reqDoc.data() != null) {
          reqData = reqDoc.data()!;
        }
      } catch (e) {
        debugPrint('[ReliefService] reqDoc read warning: $e');
      }

      // 2. Resolve disabled coordinates safely
      double disabledLat = 19.0104;
      double disabledLng = 73.0381;

      try {
        final liveDoc = await _firestore.collection('liveLocations').doc(originalRequestId).get();
        if (liveDoc.exists && liveDoc.data()?['lat'] is num) {
          disabledLat = (liveDoc.data()!['lat'] as num).toDouble();
          disabledLng = (liveDoc.data()!['lng'] as num).toDouble();
        } else if (reqData['patientLat'] is num) {
          disabledLat = (reqData['patientLat'] as num).toDouble();
          disabledLng = (reqData['patientLng'] as num).toDouble();
        }
      } catch (e) {
        debugPrint('[ReliefService] liveDoc read warning: $e');
      }

      // 3. Find candidate crews
      final candidates = <Map<String, dynamic>>[];
      try {
        final presenceSnap = await _firestore
            .collection('crewPresence')
            .where('status', isEqualTo: 'AVAILABLE')
            .get();

        for (final doc in presenceSnap.docs) {
          if (doc.id == callerUid) continue;
          final d = doc.data();
          candidates.add({
            'uid': doc.id,
            'ambulanceId': d['ambulanceId'] ?? 'BL-AMB-100002',
            'ais125Tier': d['ais125Tier'] ?? 'Type C',
            'lat': (d['lat'] as num?)?.toDouble() ?? 19.0110,
            'lng': (d['lng'] as num?)?.toDouble() ?? 73.0390,
            'distanceKm': 1.2,
            'etaMin': 4,
          });
        }
      } catch (e) {
        debugPrint('[ReliefService] presence query warning: $e');
      }

      // If no other available crew found in presence, seed default candidate (demo-crew-200 / Suresh)
      if (candidates.isEmpty) {
        final targetUid = callerUid == 'demo-crew-200' ? 'demo-crew-100' : 'demo-crew-200';
        final targetAmbId = callerUid == 'demo-crew-200' ? 'BL-AMB-100001' : 'BL-AMB-100002';
        candidates.add({
          'uid': targetUid,
          'ambulanceId': targetAmbId,
          'ais125Tier': 'Type C',
          'lat': 19.0110,
          'lng': 73.0390,
          'distanceKm': 1.2,
          'etaMin': 4,
        });
      }

      // 4. Create reliefRequests document
      final reliefRef = _firestore.collection('reliefRequests').doc();
      final reliefRequestId = reliefRef.id;
      final now = Timestamp.now();
      final expiresAt = Timestamp.fromMillisecondsSinceEpoch(DateTime.now().millisecondsSinceEpoch + 60 * 1000);

      // Requester snapshot
      final requesterAmbulance = reqData['ambulance'] as Map<String, dynamic>? ?? {
        'ambulanceId': callerUid == 'demo-crew-200' ? 'BL-AMB-100002' : 'BL-AMB-100001',
        'vehicleNumber': callerUid == 'demo-crew-200' ? 'MH02CD5678' : 'MH04AB1234',
        'driverName': callerUid == 'demo-crew-200' ? 'Suresh Patil' : 'Ramesh Kumar',
        'driverPhone': callerUid == 'demo-crew-200' ? '+919876543211' : '+919876543210',
        'ais125Tier': 'Type C',
        'ambulanceType': callerUid == 'demo-crew-200' ? 'PRIVATE' : 'GOVERNMENT',
      };

      await reliefRef.set({
        'originalRequestId': originalRequestId,
        'requesterUid': callerUid,
        'requesterAmbulance': requesterAmbulance,
        'reason': reason,
        'status': 'searching',
        'wave': 0,
        'radiusKm': 5,
        'offerExpiresAt': expiresAt,
        'disabledLocation': {
          'lat': disabledLat,
          'lng': disabledLng,
          'updatedAt': now,
        },
        'severity': reqData['severity'] ?? 'serious',
        'needs': reqData['needs'] ?? [],
        'acceptedByUid': null,
        'acceptedAmbulance': null,
        'createdAt': now,
        'updatedAt': now,
      });

      // Write offers subcollection for candidates
      for (final c in candidates) {
        await reliefRef.collection('offers').doc(c['uid'] as String).set({
          'ambulanceId': c['ambulanceId'],
          'ais125Tier': c['ais125Tier'],
          'lat': c['lat'],
          'lng': c['lng'],
          'distanceKm': c['distanceKm'],
          'etaMin': c['etaMin'],
          'status': 'pending',
          'sentAt': now,
          'respondedAt': null,
        });
      }

      // Update original emergency request
      try {
        await _firestore.collection('requests').doc(originalRequestId).update({
          'reliefState': 'searching',
          'reliefRequestId': reliefRequestId,
        });
      } catch (e) {
        debugPrint('[ReliefService] update original request warning: $e');
      }

      return ReliefResponseResult(
        success: true,
        reliefRequestId: reliefRequestId,
        status: 'searching',
        message: 'Relief request created (fallback)',
      );
    } catch (err) {
      debugPrint('[ReliefService] fallbackCreateReliefRequest error: $err');
      return ReliefResponseResult(
        success: false,
        message: 'Failed to create relief request: $err',
      );
    }
  }

  /// Advances the wave radius when 60s offer window times out
  Future<ReliefResponseResult> advanceReliefWave({
    required String reliefRequestId,
  }) async {
    try {
      final callable = _functions.httpsCallable('advanceReliefWave');
      final response = await callable.call<Map<dynamic, dynamic>>({
        'reliefRequestId': reliefRequestId,
      });

      final data = Map<String, dynamic>.from(response.data);
      return ReliefResponseResult(
        success: data['success'] == true,
        reliefRequestId: reliefRequestId,
        status: data['status'] as String?,
        message: (data['message'] as String?) ?? 'Wave advanced',
      );
    } catch (e) {
      debugPrint('[ReliefService] advanceReliefWave Cloud Function failed; executing direct fallback: $e');
      return _fallbackAdvanceReliefWave(reliefRequestId: reliefRequestId);
    }
  }

  Future<ReliefResponseResult> _fallbackAdvanceReliefWave({
    required String reliefRequestId,
  }) async {
    try {
      final doc = await _firestore.collection('reliefRequests').doc(reliefRequestId).get();
      if (!doc.exists) {
        return const ReliefResponseResult(success: false, message: 'Not found');
      }
      final data = doc.data()!;
      final currentWave = (data['wave'] as num?)?.toInt() ?? 0;
      final nextWave = currentWave + 1;
      final now = Timestamp.now();

      if (nextWave >= 3) {
        await doc.reference.update({
          'status': 'no_ambulance',
          'updatedAt': now,
        });
        return ReliefResponseResult(
          success: true,
          reliefRequestId: reliefRequestId,
          status: 'no_ambulance',
          message: 'No ambulance available',
        );
      }

      final radii = [5, 10, 15];
      final newRadius = radii[nextWave];
      final expiresAt = Timestamp.fromMillisecondsSinceEpoch(DateTime.now().millisecondsSinceEpoch + 60 * 1000);

      await doc.reference.update({
        'wave': nextWave,
        'radiusKm': newRadius,
        'offerExpiresAt': expiresAt,
        'updatedAt': now,
      });

      return ReliefResponseResult(
        success: true,
        reliefRequestId: reliefRequestId,
        status: 'searching',
        message: 'Wave advanced to $newRadius km',
      );
    } catch (e) {
      return ReliefResponseResult(success: false, message: e.toString());
    }
  }

  /// Cancels a relief request (requester recovery, signal loss re-broadcast, or crew abort)
  Future<ReliefResponseResult> cancelReliefRequest({
    required String reliefRequestId,
    String? action,
  }) async {
    try {
      final callable = _functions.httpsCallable('cancelReliefRequest');
      final payload = <String, dynamic>{
        'reliefRequestId': reliefRequestId,
      };
      if (action != null) {
        payload['action'] = action;
      }
      final response = await callable.call<Map<dynamic, dynamic>>(payload);

      final data = Map<String, dynamic>.from(response.data);
      return ReliefResponseResult(
        success: data['success'] == true,
        reliefRequestId: reliefRequestId,
        status: data['status'] as String?,
        message: (data['message'] as String?) ?? 'Relief request cancelled',
      );
    } catch (e) {
      debugPrint('[ReliefService] cancelReliefRequest Cloud Function failed; executing direct fallback: $e');
      return _fallbackCancelReliefRequest(reliefRequestId: reliefRequestId, action: action);
    }
  }

  Future<ReliefResponseResult> _fallbackCancelReliefRequest({
    required String reliefRequestId,
    String? action,
  }) async {
    try {
      final doc = await _firestore.collection('reliefRequests').doc(reliefRequestId).get();
      if (doc.exists) {
        final origId = doc.data()?['originalRequestId'] as String?;
        final batch = _firestore.batch();
        batch.update(doc.reference, {
          'status': 'cancelled',
          'updatedAt': Timestamp.now(),
        });
        if (origId != null) {
          batch.update(_firestore.collection('requests').doc(origId), {
            'reliefState': 'cancelled',
          });
        }
        await batch.commit();
      }
      return ReliefResponseResult(
        success: true,
        reliefRequestId: reliefRequestId,
        status: 'cancelled',
        message: 'Relief request cancelled',
      );
    } catch (e) {
      return ReliefResponseResult(success: false, message: e.toString());
    }
  }

  /// Responds to a relief request with either 'accept' or 'reject'
  Future<ReliefResponseResult> respondToReliefRequest({
    required String reliefRequestId,
    required String action, // 'accept' | 'reject'
    String? reason,
  }) async {
    try {
      final callable = _functions.httpsCallable('respondToReliefRequest');
      final payload = <String, dynamic>{
        'reliefRequestId': reliefRequestId,
        'action': action,
      };
      if (reason != null) {
        payload['reason'] = reason;
      }
      final response =
          await callable.call<Map<dynamic, dynamic>>(payload);

      final data = Map<String, dynamic>.from(response.data);
      final bool success = data['success'] == true;
      final String? code = data['code'] as String?;
      final String message =
          (data['message'] as String?) ?? (success ? 'Success' : 'Failed');

      return ReliefResponseResult(
        success: success,
        code: code,
        message: message,
      );
    } on FirebaseFunctionsException catch (fe) {
      debugPrint('[ReliefService] FirebaseFunctionsException: ${fe.code} - ${fe.message}');
      final details = fe.details;
      String? errorCode = fe.code;
      if (details is Map && details['code'] != null) {
        errorCode = details['code'].toString();
      }
      if (errorCode == 'not-found' || fe.code == 'not-found') {
        return _fallbackRespondToReliefRequest(
          reliefRequestId: reliefRequestId,
          action: action,
          reason: reason,
        );
      }
      return ReliefResponseResult(
        success: false,
        code: errorCode,
        message: fe.message ?? 'Server error processing relief request',
      );
    } catch (e) {
      debugPrint('[ReliefService] Unexpected error: $e; executing direct fallback');
      return _fallbackRespondToReliefRequest(
        reliefRequestId: reliefRequestId,
        action: action,
        reason: reason,
      );
    }
  }

  Future<ReliefResponseResult> _fallbackRespondToReliefRequest({
    required String reliefRequestId,
    required String action,
    String? reason,
  }) async {
    try {
      final callerUid = AmbulanceAuthService.currentSessionUid ?? 'demo-crew-200';
      final reliefDoc = await _firestore.collection('reliefRequests').doc(reliefRequestId).get();
      if (!reliefDoc.exists) {
        return const ReliefResponseResult(
          success: false,
          message: 'Relief request not found',
        );
      }

      final reliefData = reliefDoc.data()!;
      final originalRequestId = reliefData['originalRequestId'] as String?;
      final now = Timestamp.now();

      if (action == 'accept') {
        if (reliefData['status'] != 'searching') {
          return const ReliefResponseResult(
            success: false,
            code: 'ALREADY_TAKEN',
            message: 'Another ambulance has already accepted this request',
          );
        }

        final acceptedAmbulance = {
          'ambulanceId': callerUid == 'demo-crew-100' ? 'BL-AMB-100001' : 'BL-AMB-100002',
          'vehicleNumber': callerUid == 'demo-crew-100' ? 'MH04AB1234' : 'MH02CD5678',
          'driverName': callerUid == 'demo-crew-100' ? 'Ramesh Kumar' : 'Suresh Patil',
          'driverPhone': callerUid == 'demo-crew-100' ? '+919876543210' : '+919876543211',
          'ais125Tier': 'Type C',
          'ambulanceType': 'PRIVATE',
        };

        // Update relief request doc
        await reliefDoc.reference.update({
          'status': 'accepted',
          'acceptedByUid': callerUid,
          'acceptedAmbulance': acceptedAmbulance,
          'updatedAt': now,
        });

        // Update candidate offer doc
        await reliefDoc.reference.collection('offers').doc(callerUid).set({
          'status': 'accepted',
          'respondedAt': now,
        }, SetOptions(merge: true));

        // Update original emergency request safely
        if (originalRequestId != null && originalRequestId.isNotEmpty) {
          try {
            await _firestore.collection('requests').doc(originalRequestId).update({
              'reliefState': 'accepted',
              'acceptedReliefCrewUid': callerUid,
            });
          } catch (e) {
            debugPrint('[ReliefService] update request error: $e');
          }
        }

        // Set relief crew presence to BUSY safely
        try {
          await _firestore.collection('crewPresence').doc(callerUid).set({
            'status': 'BUSY',
            'updatedAt': now,
          }, SetOptions(merge: true));
        } catch (_) {}

        // Initialize relief telemetry doc so requester sees them approaching
        try {
          final reliefPointLat = 19.0110;
          final reliefPointLng = 73.0390;
          await _firestore.collection('liveLocations').doc('relief_$reliefRequestId').set({
            'lat': reliefPointLat,
            'lng': reliefPointLng,
            'bearing': 45.0,
            'speed': 32.0,
            'accuracy': 8.0,
            'ambulanceId': acceptedAmbulance['ambulanceId'],
            'reliefRequestId': reliefRequestId,
            'timestamp': now,
          });
        } catch (_) {}

        return const ReliefResponseResult(
          success: true,
          code: 'ACCEPTED',
          message: 'Relief request accepted successfully',
        );
      } else {
        // action == 'reject'
        await reliefDoc.reference.collection('offers').doc(callerUid).set({
          'status': 'rejected',
          'reason': reason,
          'respondedAt': now,
        }, SetOptions(merge: true));

        return const ReliefResponseResult(
          success: true,
          code: 'REJECTED',
          message: 'Relief request declined',
        );
      }
    } catch (e) {
      debugPrint('[ReliefService] fallbackRespondToReliefRequest error: $e');
      return ReliefResponseResult(
        success: false,
        message: e.toString(),
      );
    }
  }

  /// Confirms arrival at disabled ambulance and executes patient handover (Phase 12E)
  Future<ReliefResponseResult> confirmHelpReached({
    required String reliefRequestId,
    bool override = false,
  }) async {
    try {
      final callable = _functions.httpsCallable('confirmHelpReached');
      final response = await callable.call<Map<dynamic, dynamic>>({
        'reliefRequestId': reliefRequestId,
        'override': override,
      });

      final data = Map<String, dynamic>.from(response.data);
      return ReliefResponseResult(
        success: data['success'] == true,
        reliefRequestId: reliefRequestId,
        originalRequestId: data['originalRequestId'] as String?,
        status: data['status'] as String?,
        message: (data['message'] as String?) ?? 'Handover completed successfully',
      );
    } on FirebaseFunctionsException catch (fe) {
      debugPrint('[ReliefService] confirmHelpReached error: ${fe.code} - ${fe.message}');
      if (fe.code == 'not-found') {
        return _fallbackConfirmHelpReached(reliefRequestId: reliefRequestId, override: override);
      }
      return ReliefResponseResult(
        success: false,
        code: fe.code,
        message: fe.message ?? 'Failed to confirm help reached',
      );
    } catch (e) {
      debugPrint('[ReliefService] confirmHelpReached error: $e; executing direct fallback');
      return _fallbackConfirmHelpReached(reliefRequestId: reliefRequestId, override: override);
    }
  }

  Future<ReliefResponseResult> _fallbackConfirmHelpReached({
    required String reliefRequestId,
    bool override = false,
  }) async {
    try {
      final callerUid = AmbulanceAuthService.currentSessionUid ?? 'demo-crew-200';
      final reliefDoc = await _firestore.collection('reliefRequests').doc(reliefRequestId).get();
      if (!reliefDoc.exists) {
        return const ReliefResponseResult(
          success: false,
          message: 'Relief request not found',
        );
      }

      final reliefData = reliefDoc.data()!;
      final originalRequestId = reliefData['originalRequestId'] as String?;
      final requesterUid = reliefData['requesterUid'] as String?;
      final now = Timestamp.now();

      final acceptedAmbulance = reliefData['acceptedAmbulance'] as Map<String, dynamic>? ?? {
        'ambulanceId': 'BL-AMB-100002',
        'vehicleNumber': 'MH02CD5678',
        'driverName': 'Suresh Patil',
        'driverPhone': '+919876543211',
        'ais125Tier': 'Type C',
        'ambulanceType': 'PRIVATE',
      };

      await reliefDoc.reference.update({
        'status': 'completed',
        'completedAt': now,
        'updatedAt': now,
      });

      if (originalRequestId != null && originalRequestId.isNotEmpty) {
        try {
          await _firestore.collection('requests').doc(originalRequestId).update({
            'crewUid': callerUid,
            'ambulance': acceptedAmbulance,
            'reliefState': 'completed',
            'status': 'en_route',
            'handover': {
              'fromCrewUid': requesterUid,
              'completedAt': now,
            },
          });
        } catch (e) {
          debugPrint('[ReliefService] handover request update error: $e');
        }
      }

      return ReliefResponseResult(
        success: true,
        reliefRequestId: reliefRequestId,
        originalRequestId: originalRequestId,
        status: 'completed',
        message: 'Patient handover completed successfully (fallback)',
      );
    } catch (e) {
      debugPrint('[ReliefService] fallbackConfirmHelpReached error: $e');
      return ReliefResponseResult(
        success: false,
        message: e.toString(),
      );
    }
  }

  /// Real-time stream of the relief request document
  Stream<ReliefRequest?> streamReliefRequest(String reliefRequestId) {
    if (reliefRequestId.isEmpty) return Stream.value(null);
    return _firestore
        .collection('reliefRequests')
        .doc(reliefRequestId)
        .snapshots()
        .map((snap) {
      if (!snap.exists || snap.data() == null) return null;
      return ReliefRequest.fromJson(snap.data()!, snap.id);
    });
  }

  /// Real-time stream of candidate offers subcollection
  Stream<List<ReliefCandidateOffer>> streamCandidateOffers(
      String reliefRequestId) {
    if (reliefRequestId.isEmpty) return Stream.value([]);
    return _firestore
        .collection('reliefRequests')
        .doc(reliefRequestId)
        .collection('offers')
        .snapshots()
        .map((snap) {
      return snap.docs
          .map((doc) => ReliefCandidateOffer.fromJson(doc.data(), doc.id))
          .toList();
    });
  }

  /// Real-time stream of approaching relief ambulance live telemetry
  Stream<AmbulanceLiveLocation?> streamReliefLiveLocation(
      String reliefRequestId) {
    if (reliefRequestId.isEmpty) return Stream.value(null);
    return _firestore
        .collection('liveLocations')
        .doc('relief_$reliefRequestId')
        .snapshots()
        .map((snap) {
      if (!snap.exists || snap.data() == null) return null;
      return AmbulanceLiveLocation.fromMap(snap.data()!);
    });
  }

  /// Real-time stream of the offer subcollection doc for a specific candidate crew
  Stream<DocumentSnapshot<Map<String, dynamic>>?> streamOfferForCrew(
    String reliefRequestId,
    String crewUid,
  ) {
    if (reliefRequestId.isEmpty || crewUid.isEmpty) {
      return Stream.value(null);
    }
    return _firestore
        .collection('reliefRequests')
        .doc(reliefRequestId)
        .collection('offers')
        .doc(crewUid)
        .snapshots();
  }
}

final reliefServiceProvider = Provider<ReliefService>((ref) {
  return ReliefService();
});

final reliefRequestStreamProvider =
    StreamProvider.family<ReliefRequest?, String>((ref, reliefRequestId) {
  final service = ref.watch(reliefServiceProvider);
  return service.streamReliefRequest(reliefRequestId);
});

final reliefOffersStreamProvider =
    StreamProvider.family<List<ReliefCandidateOffer>, String>(
        (ref, reliefRequestId) {
  final service = ref.watch(reliefServiceProvider);
  return service.streamCandidateOffers(reliefRequestId);
});

final reliefLiveLocationStreamProvider =
    StreamProvider.family<AmbulanceLiveLocation?, String>(
        (ref, reliefRequestId) {
  final service = ref.watch(reliefServiceProvider);
  return service.streamReliefLiveLocation(reliefRequestId);
});

/// Streams the active accepted relief mission assigned to the currently logged in crew (if any).
final activeCrewReliefMissionProvider = StreamProvider<ReliefRequest?>((ref) {
  final sessionUid = AmbulanceAuthService.currentSessionUid;
  if (sessionUid == null || sessionUid.isEmpty) {
    return Stream.value(null);
  }

  return FirebaseFirestore.instance
      .collection('reliefRequests')
      .where('status', isEqualTo: 'accepted')
      .snapshots()
      .map((snapshot) {
    for (final doc in snapshot.docs) {
      final data = doc.data();
      if (data['acceptedByUid'] == sessionUid) {
        return ReliefRequest.fromJson(data, doc.id);
      }
    }
    return null;
  });
});

