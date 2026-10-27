import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/hospital.dart';
import '../models/bed_inventory.dart';
import '../models/emergency_request.dart';
import '../models/attempt.dart';
import '../models/clinic.dart';

class FirestoreService {
  final FirebaseFirestore _firestore;

  FirestoreService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _hospitalsRef =>
      _firestore.collection('hospitals');

  CollectionReference<Map<String, dynamic>> get _requestsRef =>
      _firestore.collection('requests');

  CollectionReference<Map<String, dynamic>> get _clinicsRef =>
      _firestore.collection('clinics');

  // Stream of all hospitals sorted by name
  Stream<List<Hospital>> streamHospitals() {
    return _hospitalsRef.snapshots().map((snapshot) {
      final list = snapshot.docs.map((doc) {
        return Hospital.fromJson(doc.data(), doc.id);
      }).toList();
      list.sort((a, b) => a.name.compareTo(b.name));
      return list;
    });
  }

  // Stream of all clinics & pathology labs (auto-seeds if empty)
  Stream<List<Clinic>> streamClinics() {
    return _clinicsRef.snapshots().asyncMap((snapshot) async {
      if (snapshot.docs.isEmpty) {
        debugPrint('Clinics collection is empty. Auto-seeding 8 Mumbai clinics...');
        await seedClinics();
        final newSnap = await _clinicsRef.get();
        final list = newSnap.docs.map((doc) {
          return Clinic.fromJson(doc.data(), doc.id);
        }).toList();
        list.sort((a, b) => a.name.compareTo(b.name));
        return list;
      }
      final list = snapshot.docs.map((doc) {
        return Clinic.fromJson(doc.data(), doc.id);
      }).toList();
      list.sort((a, b) => a.name.compareTo(b.name));
      return list;
    });
  }

  // Stream single hospital
  Stream<Hospital?> streamHospital(String hospitalId) {
    if (hospitalId.isEmpty) return Stream.value(null);
    return _hospitalsRef.doc(hospitalId).snapshots().map((doc) {
      if (!doc.exists || doc.data() == null) return null;
      return Hospital.fromJson(doc.data()!, doc.id);
    });
  }

  // Stream of all emergency requests
  Stream<List<EmergencyRequest>> streamRequests() {
    return _requestsRef
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) => EmergencyRequest.fromJson(doc.data(), doc.id))
          .toList();
    });
  }

  // Stream specific request by ID
  Stream<EmergencyRequest?> streamRequest(String requestId) {
    if (requestId.isEmpty) return Stream.value(null);
    return _requestsRef.doc(requestId).snapshots().map((doc) {
      if (!doc.exists || doc.data() == null) return null;
      return EmergencyRequest.fromJson(doc.data()!, doc.id);
    });
  }

  // Stream active request directed to a specific hospital
  Stream<EmergencyRequest?> streamActiveRequestForHospital(String hospitalId) {
    if (hospitalId.isEmpty) return Stream.value(null);
    return _requestsRef
        .where('currentHospitalId', isEqualTo: hospitalId)
        .snapshots()
        .map((snapshot) {
      final activeDocs = snapshot.docs.map((doc) {
        return EmergencyRequest.fromJson(doc.data(), doc.id);
      }).where((req) {
        return req.status == 'offered' ||
            req.status == 'accepted' ||
            req.status == 'searching';
      }).toList();
      return activeDocs.isNotEmpty ? activeDocs.first : null;
    });
  }

  // Nurse: Update bed counts
  Future<void> updateHospitalBeds(String hospitalId, BedInventory beds) async {
    try {
      await _hospitalsRef.doc(hospitalId).update({
        'beds': beds.toJson(),
        'lastUpdated': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('Error updating hospital beds: $e');
      rethrow;
    }
  }

  // Nurse: "Everything is up to date" (refreshes lastUpdated timestamp only)
  Future<void> touchHospitalTimestamp(String hospitalId) async {
    try {
      await _hospitalsRef.doc(hospitalId).update({
        'lastUpdated': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('Error touching hospital timestamp: $e');
      rethrow;
    }
  }

  // Nurse: Update load level (low/med/high)
  Future<void> updateHospitalLoad(String hospitalId, String loadLevel) async {
    try {
      await _hospitalsRef.doc(hospitalId).update({
        'loadLevel': loadLevel,
        'lastUpdated': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('Error updating load level: $e');
      rethrow;
    }
  }

  // Seed 10 realistic Mumbai hospitals
  Future<void> seedHospitals() async {
    final now = DateTime.now();

    final List<Map<String, dynamic>> seedData = [
      {
        'id': 'lilavati_bandra',
        'name': 'Lilavati Hospital & Research Centre',
        'lat': 19.0512,
        'lng': 72.8285,
        'phone': '+91 22 2675 1000',
        'pin': '1234',
        'loadLevel': 'med',
        'beds': const BedInventory(
          icu: BedCount(available: 5, total: 12),
          ventilator: BedCount(available: 2, total: 5),
          oxygen: BedCount(available: 15, total: 20),
          cardiac: BedCount(available: 3, total: 8),
          burns: BedCount(available: 0, total: 2),
          general: BedCount(available: 18, total: 30),
        ).toJson(),
        'lastUpdated': Timestamp.fromDate(now.subtract(const Duration(minutes: 2))),
      },
      {
        'id': 'kem_parel',
        'name': 'KEM Hospital (Parel)',
        'lat': 19.0024,
        'lng': 72.8427,
        'phone': '+91 22 2410 7000',
        'pin': '1234',
        'loadLevel': 'high',
        'beds': const BedInventory(
          icu: BedCount(available: 1, total: 15),
          ventilator: BedCount(available: 0, total: 8),
          oxygen: BedCount(available: 8, total: 35),
          cardiac: BedCount(available: 1, total: 10),
          burns: BedCount(available: 2, total: 5),
          general: BedCount(available: 10, total: 50),
        ).toJson(),
        'lastUpdated': Timestamp.fromDate(now.subtract(const Duration(minutes: 5))),
      },
      {
        'id': 'nanavati_vileparle',
        'name': 'Nanavati Max Super Speciality Hospital',
        'lat': 19.0963,
        'lng': 72.8401,
        'phone': '+91 22 6836 0000',
        'pin': '1234',
        'loadLevel': 'low',
        'beds': const BedInventory(
          icu: BedCount(available: 8, total: 10),
          ventilator: BedCount(available: 4, total: 6),
          oxygen: BedCount(available: 22, total: 25),
          cardiac: BedCount(available: 6, total: 8),
          burns: BedCount(available: 1, total: 3),
          general: BedCount(available: 25, total: 30),
        ).toJson(),
        'lastUpdated': Timestamp.fromDate(now.subtract(const Duration(minutes: 8))),
      },
      {
        'id': 'hinduja_mahim',
        'name': 'P. D. Hinduja Hospital (Mahim)',
        'lat': 19.0330,
        'lng': 72.8384,
        'phone': '+91 22 2445 1515',
        'pin': '1234',
        'loadLevel': 'med',
        'beds': const BedInventory(
          icu: BedCount(available: 3, total: 10),
          ventilator: BedCount(available: 1, total: 4),
          oxygen: BedCount(available: 12, total: 20),
          cardiac: BedCount(available: 2, total: 6),
          burns: BedCount(available: 0, total: 2),
          general: BedCount(available: 15, total: 25),
        ).toJson(),
        'lastUpdated': Timestamp.fromDate(now.subtract(const Duration(minutes: 22))),
        'isNurseOnline': false,
      },
      {
        'id': 'kokilaben_andheri',
        'name': 'Kokilaben Dhirubhai Ambani Hospital',
        'lat': 19.1312,
        'lng': 72.8252,
        'phone': '+91 22 4269 6969',
        'pin': '1234',
        'loadLevel': 'low',
        'beds': const BedInventory(
          icu: BedCount(available: 7, total: 14),
          ventilator: BedCount(available: 3, total: 6),
          oxygen: BedCount(available: 25, total: 30),
          cardiac: BedCount(available: 5, total: 10),
          burns: BedCount(available: 3, total: 4),
          general: BedCount(available: 28, total: 40),
        ).toJson(),
        'lastUpdated': Timestamp.fromDate(now.subtract(const Duration(minutes: 4))),
      },
      {
        'id': 'breach_candy',
        'name': 'Breach Candy Hospital',
        'lat': 18.9718,
        'lng': 72.8052,
        'phone': '+91 22 2366 7788',
        'pin': '1234',
        'loadLevel': 'med',
        'beds': const BedInventory(
          icu: BedCount(available: 4, total: 8),
          ventilator: BedCount(available: 2, total: 3),
          oxygen: BedCount(available: 10, total: 15),
          cardiac: BedCount(available: 3, total: 5),
          burns: BedCount(available: 0, total: 1),
          general: BedCount(available: 12, total: 20),
        ).toJson(),
        'lastUpdated': Timestamp.fromDate(now.subtract(const Duration(minutes: 35))),
      },
      {
        'id': 'hn_reliance_girgaon',
        'name': 'Sir H. N. Reliance Foundation Hospital',
        'lat': 18.9568,
        'lng': 72.8193,
        'phone': '+91 22 6130 5000',
        'pin': '1234',
        'loadLevel': 'low',
        'beds': const BedInventory(
          icu: BedCount(available: 6, total: 10),
          ventilator: BedCount(available: 3, total: 5),
          oxygen: BedCount(available: 18, total: 20),
          cardiac: BedCount(available: 4, total: 6),
          burns: BedCount(available: 2, total: 3),
          general: BedCount(available: 20, total: 25),
        ).toJson(),
        'lastUpdated': Timestamp.fromDate(now.subtract(const Duration(minutes: 10))),
      },
      {
        'id': 'fortis_mulund',
        'name': 'Fortis Hospital (Mulund)',
        'lat': 19.1663,
        'lng': 72.9526,
        'phone': '+91 22 6799 4444',
        'pin': '1234',
        'loadLevel': 'high',
        'beds': const BedInventory(
          icu: BedCount(available: 0, total: 10),
          ventilator: BedCount(available: 0, total: 4),
          oxygen: BedCount(available: 5, total: 20),
          cardiac: BedCount(available: 0, total: 5),
          burns: BedCount(available: 0, total: 2),
          general: BedCount(available: 8, total: 30),
        ).toJson(),
        'lastUpdated': Timestamp.fromDate(now.subtract(const Duration(minutes: 55))),
      },
      {
        'id': 'sion_hospital',
        'name': 'L. T. M. G. Hospital (Sion)',
        'lat': 19.0365,
        'lng': 72.8601,
        'phone': '+91 22 2407 6381',
        'pin': '1234',
        'loadLevel': 'high',
        'beds': const BedInventory(
          icu: BedCount(available: 2, total: 16),
          ventilator: BedCount(available: 1, total: 8),
          oxygen: BedCount(available: 14, total: 40),
          cardiac: BedCount(available: 1, total: 8),
          burns: BedCount(available: 1, total: 6),
          general: BedCount(available: 15, total: 60),
        ).toJson(),
        'lastUpdated': Timestamp.fromDate(now.subtract(const Duration(minutes: 30))),
      },
      {
        'id': 'global_parel',
        'name': 'Global Hospitals (Parel)',
        'lat': 19.0068,
        'lng': 72.8398,
        'phone': '+91 22 6767 0101',
        'pin': '1234',
        'loadLevel': 'med',
        'beds': const BedInventory(
          icu: BedCount(available: 4, total: 10),
          ventilator: BedCount(available: 2, total: 4),
          oxygen: BedCount(available: 16, total: 25),
          cardiac: BedCount(available: 3, total: 6),
          burns: BedCount(available: 0, total: 2),
          general: BedCount(available: 18, total: 25),
        ).toJson(),
        'lastUpdated': Timestamp.fromDate(now.subtract(const Duration(minutes: 70))),
      },
    ];

    final batch = _firestore.batch();
    for (final h in seedData) {
      final docId = h['id'] as String;
      final docRef = _hospitalsRef.doc(docId);
      final data = Map<String, dynamic>.from(h)..remove('id');
      batch.set(docRef, data, SetOptions(merge: true));
    }
    await batch.commit();
    await seedClinics();
  }

  // Reset all request data & re-seed hospitals
  Future<void> resetAllData() async {
    final reqDocs = await _requestsRef.get();
    final batch = _firestore.batch();
    for (final doc in reqDocs.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();
    await seedHospitals();
    await seedClinics();
  }

  // Demo: Age a hospital's lastUpdated by X minutes
  Future<void> ageHospitalData(String hospitalId, int minutesOld) async {
    final agedDate = DateTime.now().subtract(Duration(minutes: minutesOld));
    await _hospitalsRef.doc(hospitalId).update({
      'lastUpdated': Timestamp.fromDate(agedDate),
    });
  }

  // Demo: Auto-reject active offer as a specific hospital
  Future<void> autoRejectAsHospital(String hospitalId, String reason) async {
    final snapshot = await _requestsRef
        .where('currentHospitalId', isEqualTo: hospitalId)
        .where('status', isEqualTo: 'offered')
        .get();

    if (snapshot.docs.isEmpty) return;

    final reqDoc = snapshot.docs.first;
    final req = EmergencyRequest.fromJson(reqDoc.data(), reqDoc.id);
    await rejectRequestTransaction(req.id, hospitalId, reason);
  }

  // Create Emergency Request
  Future<String> createEmergencyRequest(EmergencyRequest request) async {
    final docRef = await _requestsRef.add(request.toJson());
    return docRef.id;
  }

  // Accept request transaction: checks beds, decrements, sets status to accepted
  Future<bool> acceptRequestTransaction(
      String requestId, String hospitalId) async {
    return _firestore.runTransaction((transaction) async {
      final reqRef = _requestsRef.doc(requestId);
      final reqSnapshot = await transaction.get(reqRef);
      if (!reqSnapshot.exists) return false;

      final req = EmergencyRequest.fromJson(reqSnapshot.data()!, reqSnapshot.id);
      if (req.currentHospitalId != hospitalId || req.status != 'offered') {
        return false;
      }

      final hospRef = _hospitalsRef.doc(hospitalId);
      final hospSnapshot = await transaction.get(hospRef);
      if (!hospSnapshot.exists) return false;

      final hosp = Hospital.fromJson(hospSnapshot.data()!, hospSnapshot.id);

      // Verify availability of requested bed types
      BedInventory currentBeds = hosp.beds;
      for (final need in req.needs) {
        final count = currentBeds.getForType(need);
        if (count.available <= 0) {
          // Bed vanished! Auto-reject and return false
          return false;
        }
      }

      // Decrement bed availability for each needed bed type
      for (final need in req.needs) {
        final count = currentBeds.getForType(need);
        final updatedCount = count.copyWith(available: count.available - 1);
        currentBeds = currentBeds.updateForType(need, updatedCount);
      }

      final updatedAttempts = List<Attempt>.from(req.attempts)
        ..add(Attempt(
          hospitalId: hospitalId,
          hospitalName: hosp.name,
          result: 'accepted',
          at: DateTime.now(),
        ));

      // Update hospital beds
      transaction.update(hospRef, {
        'beds': currentBeds.toJson(),
        'lastUpdated': FieldValue.serverTimestamp(),
      });

      // Update request status to accepted
      transaction.update(reqRef, {
        'status': 'accepted',
        'attempts': updatedAttempts.map((a) => a.toJson()).toList(),
      });

      return true;
    });
  }

  // Reject request transaction & trigger cascade to next hospital
  Future<void> rejectRequestTransaction(
      String requestId, String hospitalId, String reason) async {
    final reqRef = _requestsRef.doc(requestId);
    final reqSnapshot = await reqRef.get();
    if (!reqSnapshot.exists) return;

    final req = EmergencyRequest.fromJson(reqSnapshot.data()!, reqSnapshot.id);
    final hospRef = _hospitalsRef.doc(hospitalId);
    final hospDoc = await hospRef.get();
    final hospName = hospDoc.exists ? (hospDoc.data()?['name'] ?? 'Hospital') : 'Hospital';

    final updatedAttempts = List<Attempt>.from(req.attempts)
      ..add(Attempt(
        hospitalId: hospitalId,
        hospitalName: hospName,
        result: 'rejected',
        reason: reason,
        at: DateTime.now(),
      ));

    final nextIndex = req.currentIndex + 1;
    if (nextIndex < req.rankedHospitalIds.length) {
      final nextHospitalId = req.rankedHospitalIds[nextIndex];
      final nextExpiresAt =
          DateTime.now().add(const Duration(seconds: 120));

      await reqRef.update({
        'status': 'offered',
        'currentIndex': nextIndex,
        'currentHospitalId': nextHospitalId,
        'offerExpiresAt': Timestamp.fromDate(nextExpiresAt),
        'attempts': updatedAttempts.map((a) => a.toJson()).toList(),
        'rejectReason': reason,
      });
    } else {
      // All hospitals rejected / failed
      await reqRef.update({
        'status': 'failed',
        'attempts': updatedAttempts.map((a) => a.toJson()).toList(),
        'rejectReason': reason,
      });
    }
  }

  // Handle timeout cascade
  Future<void> handleTimeoutCascade(String requestId, String hospitalId) async {
    final reqRef = _requestsRef.doc(requestId);
    final reqSnapshot = await reqRef.get();
    if (!reqSnapshot.exists) return;

    final req = EmergencyRequest.fromJson(reqSnapshot.data()!, reqSnapshot.id);
    if (req.status != 'offered' || req.currentHospitalId != hospitalId) return;

    final hospRef = _hospitalsRef.doc(hospitalId);
    final hospDoc = await hospRef.get();
    final hospName = hospDoc.exists ? (hospDoc.data()?['name'] ?? 'Hospital') : 'Hospital';

    final updatedAttempts = List<Attempt>.from(req.attempts)
      ..add(Attempt(
        hospitalId: hospitalId,
        hospitalName: hospName,
        result: 'timeout',
        at: DateTime.now(),
      ));

    final nextIndex = req.currentIndex + 1;
    if (nextIndex < req.rankedHospitalIds.length) {
      final nextHospitalId = req.rankedHospitalIds[nextIndex];
      final nextExpiresAt =
          DateTime.now().add(const Duration(seconds: 120));

      await reqRef.update({
        'status': 'offered',
        'currentIndex': nextIndex,
        'currentHospitalId': nextHospitalId,
        'offerExpiresAt': Timestamp.fromDate(nextExpiresAt),
        'attempts': updatedAttempts.map((a) => a.toJson()).toList(),
      });
    } else {
      await reqRef.update({
        'status': 'failed',
        'attempts': updatedAttempts.map((a) => a.toJson()).toList(),
      });
    }
  }

  // Handle instant auto-skip (0s delay auto-cascade for offline nurse or 0 available beds)
  Future<void> handleAutoSkip(String requestId, String hospitalId, [String? reason]) async {
    final reqRef = _requestsRef.doc(requestId);
    final reqSnapshot = await reqRef.get();
    if (!reqSnapshot.exists) return;

    final req = EmergencyRequest.fromJson(reqSnapshot.data()!, reqSnapshot.id);
    if (req.status != 'offered' || req.currentHospitalId != hospitalId) return;

    final hospRef = _hospitalsRef.doc(hospitalId);
    final hospDoc = await hospRef.get();
    final hospName = hospDoc.exists ? (hospDoc.data()?['name'] ?? 'Hospital') : 'Hospital';

    final skipReason = reason ?? 'Auto-skipped (0s delay)';

    final updatedAttempts = List<Attempt>.from(req.attempts)
      ..add(Attempt(
        hospitalId: hospitalId,
        hospitalName: hospName,
        result: 'auto_skip',
        reason: skipReason,
        at: DateTime.now(),
      ));

    final nextIndex = req.currentIndex + 1;
    if (nextIndex < req.rankedHospitalIds.length) {
      final nextHospitalId = req.rankedHospitalIds[nextIndex];
      final nextExpiresAt =
          DateTime.now().add(const Duration(seconds: 120));

      await reqRef.update({
        'status': 'offered',
        'currentIndex': nextIndex,
        'currentHospitalId': nextHospitalId,
        'offerExpiresAt': Timestamp.fromDate(nextExpiresAt),
        'attempts': updatedAttempts.map((a) => a.toJson()).toList(),
      });
    } else {
      await reqRef.update({
        'status': 'failed',
        'attempts': updatedAttempts.map((a) => a.toJson()).toList(),
      });
    }
  }

  Future<void> handleOfflineSkip(String requestId, String hospitalId) async {
    await handleAutoSkip(requestId, hospitalId, 'Nurse terminal offline (0s auto-skip)');
  }

  // Nurse: Update presence (online / offline)
  Future<void> updateNursePresence(String hospitalId, bool isOnline) async {
    try {
      await _hospitalsRef.doc(hospitalId).update({
        'isNurseOnline': isOnline,
        'lastNurseActive': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('Error updating nurse presence: $e');
    }
  }

  // Release hold transaction (restore bed counts if cancelled or released by nurse)
  Future<void> releaseHoldTransaction(String requestId) async {
    return _firestore.runTransaction((transaction) async {
      final reqRef = _requestsRef.doc(requestId);
      final reqSnapshot = await transaction.get(reqRef);
      if (!reqSnapshot.exists) return;

      final req = EmergencyRequest.fromJson(reqSnapshot.data()!, reqSnapshot.id);
      if (req.status != 'accepted') return;

      final hospRef = _hospitalsRef.doc(req.currentHospitalId);
      final hospSnapshot = await transaction.get(hospRef);
      if (hospSnapshot.exists) {
        final hosp = Hospital.fromJson(hospSnapshot.data()!, hospSnapshot.id);
        BedInventory currentBeds = hosp.beds;

        for (final need in req.needs) {
          final count = currentBeds.getForType(need);
          final updatedCount = count.copyWith(available: count.available + 1);
          currentBeds = currentBeds.updateForType(need, updatedCount);
        }

        transaction.update(hospRef, {
          'beds': currentBeds.toJson(),
        });
      }

      transaction.update(reqRef, {
        'status': 'cancelled',
      });
    });
  }

  // Mark arrived transaction (hold becomes permanent)
  Future<void> markArrivedTransaction(String requestId) async {
    await _requestsRef.doc(requestId).update({
      'status': 'arrived',
    });
  }

  // Seed 8 realistic Mumbai clinics & pathology labs
  Future<void> seedClinics() async {
    final List<Map<String, dynamic>> clinicSeedData = [
      {
        'id': 'suburban_diag_bandra',
        'name': 'Suburban Diagnostics & Pathology Lab',
        'type': 'pathology_lab',
        'lat': 19.0550,
        'lng': 72.8320,
        'phone': '+91 22 6170 0000',
        'address': 'Hill Road, Bandra West, Mumbai',
        'rating': 4.8,
        'isOpen': true,
        'operatingHours': '07:00 AM - 09:00 PM',
        'specialties': ['Blood Tests & Pathology', 'X-Ray & Imaging', 'MRI/CT Scan', 'Ultrasound'],
        'testsAvailable': ['CBC Blood Count', 'Lipid Profile', 'Thyroid Profile', 'HbA1c Glucose', 'RTPCR Test', 'Full Body Checkup'],
      },
      {
        'id': 'skincraft_juhu',
        'name': 'SkinCraft Dermatology & Aesthetic Clinic',
        'type': 'clinic',
        'lat': 19.1020,
        'lng': 72.8260,
        'phone': '+91 22 2620 4455',
        'address': 'JVPD Scheme, Juhu, Mumbai',
        'rating': 4.9,
        'isOpen': true,
        'operatingHours': '10:00 AM - 08:00 PM',
        'specialties': ['Dermatology (Skin)', 'Cosmetic Dermatology', 'General Physician'],
        'testsAvailable': ['Skin Allergy Test', 'Skin Biopsy'],
      },
      {
        'id': 'metropolis_andheri',
        'name': 'Metropolis Healthcare & Diagnostic Centre',
        'type': 'pathology_lab',
        'lat': 19.1190,
        'lng': 72.8470,
        'phone': '+91 22 2636 8899',
        'address': 'SV Road, Andheri West, Mumbai',
        'rating': 4.7,
        'isOpen': true,
        'operatingHours': '07:30 AM - 08:30 PM',
        'specialties': ['Blood Tests & Pathology', 'X-Ray & Imaging', 'Ultrasound'],
        'testsAvailable': ['Liver Function Test', 'Kidney Function Test', 'Vitamin D & B12', 'ECG Test'],
      },
      {
        'id': 'lotus_women_parel',
        'name': 'Lotus Women & Gynecology Care Clinic',
        'type': 'clinic',
        'lat': 19.0080,
        'lng': 72.8410,
        'phone': '+91 22 2415 3322',
        'address': 'Dr. Ambedkar Road, Parel, Mumbai',
        'rating': 4.8,
        'isOpen': true,
        'operatingHours': '09:00 AM - 07:00 PM',
        'specialties': ['Gynecology & Maternity', 'Ultrasound', 'General Physician'],
        'testsAvailable': ['Pap Smear Test', 'Pelvic Ultrasound', 'Pregnancy Screening'],
      },
      {
        'id': 'apex_dental_mahim',
        'name': 'Apex Dental & Maxillofacial Care',
        'type': 'clinic',
        'lat': 19.0380,
        'lng': 72.8400,
        'phone': '+91 22 2446 7711',
        'address': 'LJ Road, Mahim West, Mumbai',
        'rating': 4.6,
        'isOpen': true,
        'operatingHours': '09:30 AM - 08:30 PM',
        'specialties': ['Dental Care', 'Oral Surgery'],
        'testsAvailable': ['Dental X-Ray OPG', 'Root Canal Screening'],
      },
      {
        'id': 'little_angels_powai',
        'name': 'Little Angels Pediatric & Child Care Clinic',
        'type': 'clinic',
        'lat': 19.1170,
        'lng': 72.9050,
        'phone': '+91 22 2570 9988',
        'address': 'Hiranandani Gardens, Powai, Mumbai',
        'rating': 4.9,
        'isOpen': true,
        'operatingHours': '09:00 AM - 06:00 PM',
        'specialties': ['Pediatrics (Child)', 'General Physician'],
        'testsAvailable': ['Child Vaccination Profile', 'Growth Assessment'],
      },
      {
        'id': 'orthomotion_dadar',
        'name': 'OrthoMotion Bone & Joint Clinic',
        'type': 'clinic',
        'lat': 19.0180,
        'lng': 72.8430,
        'phone': '+91 22 2418 5544',
        'address': 'Ranade Road, Dadar West, Mumbai',
        'rating': 4.7,
        'isOpen': true,
        'operatingHours': '10:00 AM - 07:30 PM',
        'specialties': ['Orthopedics (Bone & Joint)', 'X-Ray & Imaging'],
        'testsAvailable': ['Bone Density DEXA Scan', 'Digital X-Ray'],
      },
      {
        'id': 'sightcare_vileparle',
        'name': 'SightCare Eye & Ophthalmology Centre',
        'type': 'clinic',
        'lat': 19.0980,
        'lng': 72.8450,
        'phone': '+91 22 2611 2233',
        'address': 'Nehru Road, Vile Parle East, Mumbai',
        'rating': 4.8,
        'isOpen': true,
        'operatingHours': '10:00 AM - 07:00 PM',
        'specialties': ['Ophthalmology (Eye)'],
        'testsAvailable': ['Retinal Scan', 'Corneal Topography', 'Eye Pressure OCT'],
      },
    ];

    final batch = _firestore.batch();
    for (final c in clinicSeedData) {
      final docId = c['id'] as String;
      final docRef = _clinicsRef.doc(docId);
      final data = Map<String, dynamic>.from(c)..remove('id');
      batch.set(docRef, data, SetOptions(merge: true));
    }
    await batch.commit();
  }
}
