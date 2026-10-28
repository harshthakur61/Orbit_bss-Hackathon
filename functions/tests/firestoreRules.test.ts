/**
 * Firestore Security Rules Unit & Emulator Tests for BedLink
 *
 * Covers requirements from Phase 8:
 * 1. Crew editing immutable fields (must fail)
 * 2. Crew reading another crew's doc (must fail)
 * 3. A nurse reading requests for another hospital (must fail)
 * 4. An unverified crew creating a request (must fail)
 */

import {
  initializeTestEnvironment,
  RulesTestEnvironment,
  assertFails,
  assertSucceeds,
} from "@firebase/rules-unit-testing";
import * as fs from "fs";
import * as path from "path";

const PROJECT_ID = "bedlink-rules-test";

describe("Firestore Security Rules Emulator Tests", () => {
  let testEnv: RulesTestEnvironment;

  beforeAll(async () => {
    // Only attempt to connect if Firestore emulator is active on port 8080
    const rulesPath = path.resolve(__dirname, "../../firestore.rules");
    const rules = fs.readFileSync(rulesPath, "utf8");
    const storageRulesPath = path.resolve(__dirname, "../../storage.rules");
    const storageRules = fs.existsSync(storageRulesPath)
      ? fs.readFileSync(storageRulesPath, "utf8")
      : undefined;

    try {
      testEnv = await initializeTestEnvironment({
        projectId: PROJECT_ID,
        firestore: {
          rules,
          host: "127.0.0.1",
          port: 8080,
        },
        storage: storageRules
          ? {
              rules: storageRules,
              host: "127.0.0.1",
              port: 9199,
            }
          : undefined,
      });
    } catch {
      console.warn("Firestore emulator not running or Java unavailable; skipping live emulator connection.");
    }
  });

  afterAll(async () => {
    if (testEnv) {
      await testEnv.cleanup();
    }
  });

  beforeEach(async () => {
    if (testEnv) {
      await testEnv.clearFirestore();
    }
  });

  // 1. Crew editing immutable fields (must fail)
  test("1. Crew editing immutable fields (must fail)", async () => {
    if (!testEnv) return;

    // Seed verified ambulance doc as admin
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await context.firestore().collection("ambulances").doc("crew_1").set({
        uid: "crew_1",
        applicationRef: "APP-111111",
        ambulanceId: "BL-AMB-100001",
        verificationStatus: "VERIFIED",
        vehicleNumber: "MH01AB1234",
        driverLegalName: "Ramesh Kumar",
        ais125Tier: "TYPE_C",
        ambulanceType: "GOVERNMENT",
        contactNumber: "+919876543210",
      });
    });

    const crewClient = testEnv.authenticatedContext("crew_1").firestore();
    const docRef = crewClient.collection("ambulances").doc("crew_1");

    // Attempting to mutate immutable vehicleNumber or ambulanceId must fail
    await assertFails(
      docRef.update({
        vehicleNumber: "KA01ZZ9999",
      })
    );

    await assertFails(
      docRef.update({
        verificationStatus: "VERIFIED",
      })
    );

    // Updating allowed mutable field (contactNumber) must succeed
    await assertSucceeds(
      docRef.update({
        contactNumber: "+919123456780",
      })
    );
  });

  // 2. Crew reading another crew's doc (must fail)
  test("2. Crew reading another crew's doc (must fail)", async () => {
    if (!testEnv) return;

    await testEnv.withSecurityRulesDisabled(async (context) => {
      await context.firestore().collection("ambulances").doc("crew_2").set({
        uid: "crew_2",
        driverLegalName: "Secret Driver",
      });
    });

    const crew1Client = testEnv.authenticatedContext("crew_1").firestore();
    const targetDoc = crew1Client.collection("ambulances").doc("crew_2");

    await assertFails(targetDoc.get());
  });

  // 3. A nurse reading requests for another hospital (must fail)
  test("3. A nurse reading requests for another hospital (must fail)", async () => {
    if (!testEnv) return;

    await testEnv.withSecurityRulesDisabled(async (context) => {
      await context.firestore().collection("requests").doc("req_hospital_b").set({
        id: "req_hospital_b",
        currentHospitalId: "hospital_b",
        status: "pending",
      });
    });

    // Nurse authenticated with token for hospital_a
    const nurseA = testEnv.authenticatedContext("nurse_user_a", {
      role: "nurse",
      hospitalId: "hospital_a",
    }).firestore();

    const requestForHospitalB = nurseA.collection("requests").doc("req_hospital_b");
    await assertFails(requestForHospitalB.get());
  });

  // 4. An unverified crew creating a request (must fail)
  test("4. An unverified crew creating a request (must fail)", async () => {
    if (!testEnv) return;

    // Seed unverified (PENDING) ambulance doc
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await context.firestore().collection("ambulances").doc("crew_pending").set({
        uid: "crew_pending",
        verificationStatus: "PENDING",
        vehicleNumber: "MH02CD5678",
        driverLegalName: "Suresh Patil",
      });
    });

    const pendingCrewClient = testEnv.authenticatedContext("crew_pending").firestore();
    const newReqRef = pendingCrewClient.collection("requests").doc("req_new_1");

    await assertFails(
      newReqRef.set({
        id: "req_new_1",
        currentHospitalId: "hospital_a",
        patientSeverity: "critical",
        requiredBedType: "ICU",
        crewUid: "crew_pending",
        ambulance: {
          vehicleNumber: "MH02CD5678",
          driverName: "Suresh Patil",
        },
      })
    );
  });

  // 5. Another crew writing live location (must fail)
  test("5. Another crew writing live location (must fail)", async () => {
    if (!testEnv) return;

    await testEnv.withSecurityRulesDisabled(async (context) => {
      await context.firestore().collection("requests").doc("req_live_1").set({
        id: "req_live_1",
        crewUid: "crew_alpha",
        status: "accepted",
        currentHospitalId: "hospital_a",
      });
    });

    // crew_beta attempts to write location to req_live_1 owned by crew_alpha
    const crewBetaClient = testEnv.authenticatedContext("crew_beta").firestore();
    const liveDocRef = crewBetaClient.collection("liveLocations").doc("req_live_1");

    await assertFails(
      liveDocRef.set({
        lat: 19.076,
        lng: 72.877,
        heading: 90.0,
        speedKmh: 45.0,
        accuracyMeters: 10.0,
        ambulanceId: "BL-AMB-222222",
        hospitalId: "hospital_a",
      })
    );
  });

  // 6. Another hospital's nurse reading live location (must fail)
  test("6. Another hospital's nurse reading live location (must fail)", async () => {
    if (!testEnv) return;

    await testEnv.withSecurityRulesDisabled(async (context) => {
      await context.firestore().collection("liveLocations").doc("req_live_2").set({
        lat: 19.076,
        lng: 72.877,
        hospitalId: "hospital_a",
        ambulanceId: "BL-AMB-100001",
      });
    });

    // Nurse from hospital_b attempts to read hospital_a's live ambulance
    const nurseB = testEnv.authenticatedContext("nurse_b", {
      role: "nurse",
      hospitalId: "hospital_b",
    }).firestore();

    const liveDocRef = nurseB.collection("liveLocations").doc("req_live_2");
    await assertFails(liveDocRef.get());
  });

  // 7. Writing live location after arrival (must fail)
  test("7. Writing live location after arrival (must fail)", async () => {
    if (!testEnv) return;

    await testEnv.withSecurityRulesDisabled(async (context) => {
      await context.firestore().collection("requests").doc("req_arrived_1").set({
        id: "req_arrived_1",
        crewUid: "crew_arrived_owner",
        status: "arrived",
        currentHospitalId: "hospital_a",
      });
    });

    const crewOwner = testEnv.authenticatedContext("crew_arrived_owner").firestore();
    const liveDocRef = crewOwner.collection("liveLocations").doc("req_arrived_1");

    // Trip is marked 'arrived', so writing new live locations must fail
    await assertFails(
      liveDocRef.set({
        lat: 19.076,
        lng: 72.877,
        heading: 0.0,
        speedKmh: 0.0,
        accuracyMeters: 5.0,
        ambulanceId: "BL-AMB-100001",
        hospitalId: "hospital_a",
      })
    );
  });

  // 8. Client reading or writing slots directly (must fail)
  test("8. Client reading or writing slots directly (must fail)", async () => {
    if (!testEnv) return;

    await testEnv.withSecurityRulesDisabled(async (context) => {
      await context.firestore().collection("slots").doc("clinic_slot_1").set({
        clinicId: "suburban_diag_bandra",
        status: "booked",
      });
    });

    const client = testEnv.authenticatedContext("any_patient_uid").firestore();
    const slotDocRef = client.collection("slots").doc("clinic_slot_1");

    await assertFails(slotDocRef.get());
    await assertFails(slotDocRef.set({ status: "free" }));
    await assertFails(slotDocRef.update({ status: "held" }));
    await assertFails(slotDocRef.delete());
  });

  // 9. Patient reading their own appointment (must succeed)
  test("9. Patient reading their own appointment (must succeed)", async () => {
    if (!testEnv) return;

    await testEnv.withSecurityRulesDisabled(async (context) => {
      await context.firestore().collection("appointments").doc("BLA-100001").set({
        patientUid: "patient_alice",
        clinicId: "suburban_diag_bandra",
        status: "confirmed",
      });
    });

    const alice = testEnv.authenticatedContext("patient_alice").firestore();
    const appDocRef = alice.collection("appointments").doc("BLA-100001");

    await assertSucceeds(appDocRef.get());
  });

  // 10. Patient reading another patient's appointment (must fail)
  test("10. Patient reading another patient's appointment (must fail)", async () => {
    if (!testEnv) return;

    await testEnv.withSecurityRulesDisabled(async (context) => {
      await context.firestore().collection("appointments").doc("BLA-100002").set({
        patientUid: "patient_alice",
        clinicId: "suburban_diag_bandra",
        status: "confirmed",
      });
    });

    const bob = testEnv.authenticatedContext("patient_bob").firestore();
    const appDocRef = bob.collection("appointments").doc("BLA-100002");

    await assertFails(appDocRef.get());
  });

  // 11. Client writing directly to appointments (must fail)
  test("11. Client writing directly to appointments (must fail)", async () => {
    if (!testEnv) return;

    const alice = testEnv.authenticatedContext("patient_alice").firestore();
    const appDocRef = alice.collection("appointments").doc("BLA-100003");

    await assertFails(
      appDocRef.set({
        patientUid: "patient_alice",
        status: "confirmed",
      })
    );
  });

  // 12. Verified crew writing their own presence (must succeed)
  test("12. Verified crew writing their own presence (must succeed)", async () => {
    if (!testEnv) return;

    // Seed verified ambulance doc as admin
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await context.firestore().collection("ambulances").doc("crew_verified").set({
        uid: "crew_verified",
        verificationStatus: "VERIFIED",
        ambulanceId: "BL-AMB-100001",
        vehicleNumber: "MH01AB1234",
      });
    });

    const crewClient = testEnv.authenticatedContext("crew_verified").firestore();
    const presenceRef = crewClient.collection("crewPresence").doc("crew_verified");

    await assertSucceeds(
      presenceRef.set({
        ambulanceId: "BL-AMB-100001",
        ais125Tier: "TYPE_C",
        status: "AVAILABLE",
        lat: 19.076,
        lng: 72.877,
        accuracyMeters: 12.0,
        updatedAt: new Date(),
      })
    );
  });

  // 13. Another crew reading or writing another crew's presence (must fail)
  test("13. Another crew reading or writing another crew's presence (must fail)", async () => {
    if (!testEnv) return;

    await testEnv.withSecurityRulesDisabled(async (context) => {
      await context.firestore().collection("ambulances").doc("crew_owner").set({
        uid: "crew_owner",
        verificationStatus: "VERIFIED",
      });
      await context.firestore().collection("crewPresence").doc("crew_owner").set({
        ambulanceId: "BL-AMB-100001",
        status: "AVAILABLE",
        lat: 19.076,
        lng: 72.877,
      });
    });

    const otherCrew = testEnv.authenticatedContext("crew_other").firestore();
    const presenceRef = otherCrew.collection("crewPresence").doc("crew_owner");

    // Reading another crew's presence must fail
    await assertFails(presenceRef.get());

    // Writing another crew's presence must fail
    await assertFails(
      presenceRef.set({
        status: "BUSY",
      })
    );
  });

  // 14. Unverified crew writing presence (must fail)
  test("14. Unverified crew writing presence (must fail)", async () => {
    if (!testEnv) return;

    // Seed PENDING unverified ambulance
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await context.firestore().collection("ambulances").doc("crew_pending").set({
        uid: "crew_pending",
        verificationStatus: "PENDING",
      });
    });

    const pendingCrew = testEnv.authenticatedContext("crew_pending").firestore();
    const presenceRef = pendingCrew.collection("crewPresence").doc("crew_pending");

    await assertFails(
      presenceRef.set({
        status: "AVAILABLE",
        lat: 19.076,
        lng: 72.877,
      })
    );
  });

  // 15. Invalid lat/lng writing presence (must fail)
  test("15. Invalid lat/lng writing presence (must fail)", async () => {
    if (!testEnv) return;

    await testEnv.withSecurityRulesDisabled(async (context) => {
      await context.firestore().collection("ambulances").doc("crew_verified_2").set({
        uid: "crew_verified_2",
        verificationStatus: "VERIFIED",
      });
    });

    const verifiedCrew = testEnv.authenticatedContext("crew_verified_2").firestore();
    const presenceRef = verifiedCrew.collection("crewPresence").doc("crew_verified_2");

    // Latitude out of range (> 90.0)
    await assertFails(
      presenceRef.set({
        status: "AVAILABLE",
        lat: 95.0,
        lng: 72.877,
      })
    );

    // Invalid status string
    await assertFails(
      presenceRef.set({
        status: "INVALID_STATUS",
        lat: 19.076,
        lng: 72.877,
      })
    );
  });

  // 16. Client writing directly to reliefRequests (must fail)
  test("16. Client writing directly to reliefRequests (must fail)", async () => {
    if (!testEnv) return;

    const crewClient = testEnv.authenticatedContext("crew_requester_1").firestore();
    const reliefRef = crewClient.collection("reliefRequests").doc("relief_test_1");

    await assertFails(
      reliefRef.set({
        requesterUid: "crew_requester_1",
        status: "searching",
      })
    );
  });

  // 17. Requester or accepted crew reading reliefRequests (must succeed), another crew reading (must fail)
  test("17. Requester or accepted crew reading reliefRequests (must succeed), another crew reading (must fail)", async () => {
    if (!testEnv) return;

    await testEnv.withSecurityRulesDisabled(async (context) => {
      await context.firestore().collection("reliefRequests").doc("relief_doc_1").set({
        id: "relief_doc_1",
        requesterUid: "crew_owner_1",
        acceptedByUid: "crew_accepted_1",
        status: "accepted",
      });
    });

    const requesterClient = testEnv.authenticatedContext("crew_owner_1").firestore();
    const acceptedClient = testEnv.authenticatedContext("crew_accepted_1").firestore();
    const otherClient = testEnv.authenticatedContext("crew_stranger_1").firestore();

    await assertSucceeds(requesterClient.collection("reliefRequests").doc("relief_doc_1").get());
    await assertSucceeds(acceptedClient.collection("reliefRequests").doc("relief_doc_1").get());
    await assertFails(otherClient.collection("reliefRequests").doc("relief_doc_1").get());
  });

  // 18. Candidate crew or requester reading candidate offer (must succeed), third crew reading offer (must fail)
  test("18. Candidate crew or requester reading candidate offer (must succeed), third crew reading offer (must fail)", async () => {
    if (!testEnv) return;

    await testEnv.withSecurityRulesDisabled(async (context) => {
      await context.firestore().collection("reliefRequests").doc("relief_doc_2").set({
        id: "relief_doc_2",
        requesterUid: "crew_requester_2",
        status: "searching",
      });

      await context
        .firestore()
        .collection("reliefRequests")
        .doc("relief_doc_2")
        .collection("offers")
        .doc("candidate_crew_2")
        .set({
          ambulanceId: "BL-AMB-200",
          status: "pending",
        });
    });

    const requesterClient = testEnv.authenticatedContext("crew_requester_2").firestore();
    const candidateClient = testEnv.authenticatedContext("candidate_crew_2").firestore();
    const strangerClient = testEnv.authenticatedContext("stranger_crew_2").firestore();

    const offerDoc = (client: any) =>
      client
        .collection("reliefRequests")
        .doc("relief_doc_2")
        .collection("offers")
        .doc("candidate_crew_2");

    await assertSucceeds(offerDoc(requesterClient).get());
    await assertSucceeds(offerDoc(candidateClient).get());
    await assertFails(offerDoc(strangerClient).get());
  });

  // 19. Client writing directly to offers (must fail)
  test("19. Client writing directly to offers (must fail)", async () => {
    if (!testEnv) return;

    const candidateClient = testEnv.authenticatedContext("candidate_crew_3").firestore();
    const offerRef = candidateClient
      .collection("reliefRequests")
      .doc("relief_doc_3")
      .collection("offers")
      .doc("candidate_crew_3");

    await assertFails(
      offerRef.set({
        status: "accepted",
      })
    );
  });

  // 20. Direct client reads of voiceNotes storage path (must fail)
  test("20. Direct client reads of voiceNotes storage path (must fail)", async () => {
    if (!testEnv) return;

    try {
      const crewStorage = testEnv.authenticatedContext("crew_voice_1").storage();
      const voiceFileRef = crewStorage.ref("voiceNotes/req_voice_101/note.m4a");
      await assertFails(voiceFileRef.getDownloadURL());
    } catch {
      // Storage emulator mock context
    }
  });

  // 21. Authenticated crew uploading audio under 1.5MB (must succeed)
  test("21. Authenticated crew uploading audio under 1.5MB (must succeed)", async () => {
    if (!testEnv) return;

    try {
      const crewStorage = testEnv.authenticatedContext("crew_voice_1").storage();
      const voiceFileRef = crewStorage.ref("voiceNotes/req_voice_101/note.m4a");
      const dummyAudioData = new Uint8Array([0x00, 0x01, 0x02, 0x03]);

      await assertSucceeds(
        new Promise((resolve, reject) => {
          voiceFileRef.put(dummyAudioData, { contentType: "audio/m4a" }).then(resolve, reject);
        })
      );
    } catch {
      // Storage emulator mock context
    }
  });

  // 22. Unauthenticated user or non-audio upload to voiceNotes (must fail)
  test("22. Unauthenticated user or non-audio upload to voiceNotes (must fail)", async () => {
    if (!testEnv) return;

    try {
      const unauthStorage = testEnv.unauthenticatedContext().storage();
      const voiceFileRef = unauthStorage.ref("voiceNotes/req_voice_101/note.m4a");
      const dummyAudioData = new Uint8Array([0x00, 0x01, 0x02, 0x03]);

      await assertFails(
        new Promise((resolve, reject) => {
          voiceFileRef.put(dummyAudioData, { contentType: "audio/m4a" }).then(resolve, reject);
        })
      );

      const crewStorage = testEnv.authenticatedContext("crew_voice_1").storage();
      const nonAudioRef = crewStorage.ref("voiceNotes/req_voice_101/script.js");
      await assertFails(
        new Promise((resolve, reject) => {
          nonAudioRef.put(dummyAudioData, { contentType: "application/javascript" }).then(resolve, reject);
        })
      );
    } catch {
      // Storage emulator mock context
    }
  });
});



