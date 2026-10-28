# 🧪 BedLink End-to-End Verification & Testing Guide

This document details the comprehensive testing procedures for **BedLink**, covering automated test suites, the 8 core manual verification test scenarios, and the end-to-end two-phone hackathon demonstration workflow.

---

## 📑 Table of Contents
1. [Prerequisites & Running Automated Tests](#1-prerequisites--running-automated-tests)
2. [Mock Verification Test Matrix](#2-mock-verification-test-matrix)
3. [Test Case 1: Ambulance Registration Pass (Golden Path)](#test-case-1-ambulance-registration-pass-golden-path)
4. [Test Case 2: Vehicle-Class Fail (Taxicab / Private Car Rejection)](#test-case-2-vehicle-class-fail-taxicab--private-car-rejection)
5. [Test Case 3: Expired Fitness Fail](#test-case-3-expired-fitness-fail)
6. [Test Case 4: Missing Transport Endorsement Fail](#test-case-4-missing-transport-endorsement-fail)
7. [Test Case 5: Name Mismatch -> NEEDS_REVIEW](#test-case-5-name-mismatch---needs_review)
8. [Test Case 6: Login While PENDING ("You are not verified yet")](#test-case-6-login-while-pending-you-are-not-verified-yet)
9. [Test Case 7: Dual Login Verification (Application Reference vs Ambulance ID)](#test-case-7-dual-login-verification-application-reference-vs-ambulance-id)
10. [Test Case 8: End-to-End Two-Phone Demo (Crew Dispatch -> Nurse Accept -> Inbound Card -> Arrived)](#test-case-8-end-to-end-two-phone-demo)
11. [Test Case 9: Live GPS Ambulance Tracking & Route Simulator](#test-case-9-live-gps-ambulance-tracking--route-simulator)
12. [Test Case 10: FCM Background Alerts, Reachability & Delivery ACK](#test-case-10-fcm-background-alerts-reachability--delivery-ack)
13. [Test Case 11: Clinic & Lab Appointment Booking, Mocked Payment & Revenue Snapshot](#test-case-11-clinic--lab-appointment-booking-mocked-payment--revenue-snapshot)
14. [Test Case 12: Ambulance Crew Availability Status, Presence Publishing & Auto-Transitions](#test-case-12-ambulance-crew-availability-status-presence-publishing--auto-transitions)
15. [Test Case 13: Disabled Emergency Relief Backend, Wave Expansion & Atomic Acceptance](#test-case-13-disabled-emergency-relief-backend-wave-expansion--atomic-acceptance)
16. [Firestore & Storage Security Rules Verification](#16-firestore--storage-security-rules-verification)
17. [Master Hackathon Real-Device Demo Script (Revenue & USP Features)](#17-master-hackathon-real-device-demo-script-revenue--usp-features)
    - [17.1 Real-Device Fleet Architecture & Role Setup](#171-real-device-fleet-architecture--role-setup)
    - [17.2 Act I: Outpatient Appointment Booking & Real-Time Dark-Yellow Slot Reflection](#172-act-i-outpatient-appointment-booking--real-time-dark-yellow-slot-reflection)
    - [17.3 Act II: Voice Note Dispatch, Lockscreen Siren Interplay & Audio Play/Resume](#173-act-ii-voice-note-dispatch-lockscreen-siren-interplay--audio-playresume)
    - [17.4 Act III: Disabled Emergency Trigger, Filtered 60s Alert & Live Route Simulator](#174-act-iii-disabled-emergency-trigger-filtered-60s-alert--live-route-simulator)
    - [17.5 Act IV: Handover Handshake, Nurse Station Ambulance Change & Trip Completion](#175-act-iv-handover-handshake-nurse-station-ambulance-change--trip-completion)
    - [17.6 Act V: Resiliency, Wave Expansion & Failure Edge Cases](#176-act-v-resiliency-wave-expansion--failure-edge-cases)
    - [17.7 Remaining Engineering TODOs & Technical Limitations](#177-remaining-engineering-todos--technical-limitations)

---

## 1. Prerequisites & Running Automated Tests

### Flutter Client Verification
Ensure your Flutter environment is configured:
```bash
# 1. Analyze entire Flutter codebase (must return 0 issues)
flutter analyze

# 2. Run all 94 unit, widget, and client security invariant tests
flutter test
```

### Cloud Functions & Rules Engine Tests
BedLink includes 84 automated tests in `functions/` (across 9 test suites) verifying Sarathi DL rules, Vahan RC rules, Levenshtein fuzzy matching, appointment slot scheduling, timezone invariance, idempotency, Razorpay webhook signature verification, demo seeding, revenue snapshot aggregation, relief candidate eligibility, disabled emergency relief callables & wave expansion, Storage security rules, and Firestore security rules:
```bash
cd functions
npm install
npm test
```

---

## 2. Mock Verification Test Matrix

When testing with the default `MOCK` provider mode (enabled in dev without external Sandbox API tokens), deterministic inputs trigger specific verification behaviors:

| Target Component | Input Value | Triggered Result | Explanation |
| :--- | :--- | :--- | :--- |
| **Vehicle RC** | Ends in anything other than `0000` or `9999` (e.g. `DL01AB1234`) | ✅ **PASS** | Vehicle is classified as `AMBULANCE`, status `ACTIVE`, fitness valid until 2028. |
| **Vehicle RC** | Ends in `0000` (e.g. `DL01AB0000`) | ❌ **FAIL** | Vehicle class is returned as `TAXICAB / MOTOR CAB`. Hard failure under AIS-125. |
| **Vehicle RC** | Ends in `9999` (e.g. `MH02CD9999`) | ❌ **FAIL** | Vehicle fitness certificate expired in 2023. |
| **Driving License** | Ends in anything other than `0000` or `9999` (e.g. `DL-0420110012345`) | ✅ **PASS** | Status `ACTIVE`, valid until 2035, `hasTransportEndorsement: true`. |
| **Driving License** | Ends in `0000` (e.g. `DL-0420110000000`) | ❌ **FAIL** | LMV only without commercial/transport endorsement. |
| **Driving License** | Ends in `9999` (e.g. `DL-0420110099999`) | ❌ **FAIL** | Driver license status is `SUSPENDED / REVOKED`. |
| **Owner / Name** | Owner matches Driver Legal Name | ✅ **PASS** | Direct individual ownership verified. |
| **Owner / Name** | Owner ends with `HOSPITAL` or `TRUST` or `AMBULANCE SERVICES` | ⚠️ **NEEDS_REVIEW** | Institutional ownership detected. Flags for manual desk verification. |
| **Owner / Name** | Completely different personal name | ⚠️ **NEEDS_REVIEW** | Driver name does not match private RC owner name. |

---

## Test Case 1: Ambulance Registration Pass (Golden Path)

**Objective**: Verify that a compliant vehicle and licensed driver receive immediate automated verification.

### Steps:
1. Launch BedLink and navigate to **Ambulance Crew Portal**.
2. Tap **"New Ambulance? Register Crew & Vehicle"**.
3. **Step 1 (Vehicle)**:
   - Vehicle Registration Number: `MH04AB1234`
   - AIS-125 Tier: Select `Type C - Mobile Intensive Care Unit`
   - Ambulance Type: Select `Government / 108 Fleet`
   - Upload RC: Tap photo button (or use mock capture).
   - Tap **"Next: Driver Profile"**.
4. **Step 2 (Driver)**:
   - Driver Full Name: `Ramesh Kumar`
   - Driving License Number: `DL-0420110012345`
   - Date of Birth: `15/08/1988`
   - Contact Mobile: `9876543210`
   - Upload DL: Tap photo button.
   - Tap **"Next: Review & Submit"**.
5. **Step 3 (Review)**:
   - Verify summary details match input.
   - Tap **"Submit for AIS-125 Verification"**.

### Expected Result:
- Progress spinner activates while Cloud Function executes.
- Success screen appears with a green checkmark:
  - **Status**: `VERIFIED`
  - **Ambulance ID**: Generated badge (e.g. `BL-AMB-100001`).
  - **Application Ref**: Generated tracking code (e.g. `APP-849201`).
- Tap **"Proceed to Crew Dashboard"** -> lands on the 2-Tab Crew Portal (Dispatch & Profile).

---

## Test Case 2: Vehicle-Class Fail (Taxicab / Private Car Rejection)

**Objective**: Ensure non-ambulance vehicles are hard-rejected.

### Steps:
1. Tap **"New Ambulance? Register Crew & Vehicle"**.
2. **Step 1 (Vehicle)**:
   - Vehicle Registration Number: `MH01AB0000` *(ends in `0000`)*
   - AIS-125 Tier: `Type B`
   - Ambulance Type: `Private Operator`
3. Fill Step 2 with valid driver details (`DL-0420110012345`, `Ramesh Kumar`, `15/08/1988`, `9876543210`).
4. Tap **"Submit for AIS-125 Verification"**.

### Expected Result:
- Verification status transitions to ❌ **REJECTED**.
- Failure reasons explicitly list:
  > *"Vehicle is registered as 'TAXICAB' in Vahan records. Only approved Ambulance / Emergency vehicles may be registered under AIS-125."*
- App offers button to edit application details.

---

## Test Case 3: Expired Fitness Fail

**Objective**: Ensure vehicles with expired fitness certificates are blocked from emergency service.

### Steps:
1. Register new crew.
2. Enter Vehicle Registration Number: `KA01CD9999` *(ends in `9999`)*.
3. Fill valid driver information.
4. Submit application.

### Expected Result:
- Verification status transitions to ❌ **REJECTED**.
- Failure reason displayed:
  > *"Vehicle fitness certificate expired on 2023-01-15. An active fitness certificate is required for patient transport."*

---

## Test Case 4: Missing Transport Endorsement Fail

**Objective**: Ensure paramedics/drivers holding only private non-transport licenses cannot operate emergency transport.

### Steps:
1. Register new crew with valid vehicle `DL01AB1234`.
2. In Step 2, enter Driving License Number: `DL-1420150000000` *(ends in `0000`)*.
3. Submit application.

### Expected Result:
- Verification status transitions to ❌ **REJECTED**.
- Failure reason displayed:
  > *"Driving license lacks a commercial / transport endorsement required for emergency ambulance operation."*

---

## Test Case 5: Name Mismatch -> NEEDS_REVIEW

**Objective**: Verify that vehicles owned by an institution or hospital are routed for manual review rather than rejected.

### Steps:
1. Register with vehicle number: `MH12EF5678`.
2. Driver Legal Name: `Suresh Patil`.
3. In Mock verification provider, RC owner is returned as `APOLLO HOSPITALS ENTERPRISE LTD`.
4. Submit application.

### Expected Result:
- Status banner shows 🟡 **NEEDS_REVIEW**.
- Message informs user:
  > *"Your application has been received and flagged for verification. Registered owner is an institution/hospital. Our desk team is reviewing your fleet documentation."*
- Application Reference number is issued (e.g. `APP-304918`).

---

## Test Case 6: Login While PENDING ("You are not verified yet")

**Objective**: Ensure unverified applications cannot access the dispatch screen.

### Steps:
1. Navigate to **Ambulance Crew Login**.
2. Enter the Application Reference of an application currently in `PENDING` or `NEEDS_REVIEW` status (e.g. `APP-304918`).
3. Enter the registered contact phone (`9876543210`).
4. Tap **"Sign In"**.

### Expected Result:
- Access to dispatch is blocked.
- Alert banner displays:
  > *"You are not verified yet. Current Status: Under Review. Please allow up to 24 hours for RTO document validation."*

---

## Test Case 7: Dual Login Verification (Application Reference vs Ambulance ID)

**Objective**: Verify that verified drivers can log in either by their application reference or by their assigned Ambulance ID badge.

### Method A: Login by Application Reference
1. On Ambulance Login screen, enter Application Reference: `APP-849201`.
2. Enter registered phone number: `9876543210`.
3. Tap **"Sign In"**.
4. **Result**: Successfully authenticated into Crew Portal.

### Method B: Login by Ambulance ID
1. Log out from Crew Profile tab.
2. On Ambulance Login screen, enter Ambulance ID: `BL-AMB-100001`.
3. Enter registered phone number: `9876543210`.
4. Tap **"Sign In"**.
5. **Result**: Successfully authenticated into Crew Portal.

---

## Test Case 8: End-to-End Two-Phone Demo

**Objective**: Demonstrate real-time multi-hospital ranking, 2-minute hold, siren alert, driver snapshot delivery, and patient arrival.

### Device 1: Ambulance Crew Phone
1. Log in as verified crew `BL-AMB-100001` (Driver: *Ramesh Kumar*, Vehicle: *MH04AB1234*).
2. Tap **"New Emergency Request"**.
3. Select bed requirements: `ICU` + `Ventilator`.
4. Patient Severity: `Critical`.
5. Note: `"Male 45, acute myocardial infarction, intubated"`.
6. Tap **"Find Hospitals"**.
7. The Ranking Engine scores nearby hospitals based on ICU availability, drive time, and emergency load. Top candidate: **Apollo Hospital**.
8. Tap **"Initiate 2-Min Hold"**.
9. The 2-minute countdown timer begins ticking on Device 1.

### Device 2: Hospital Nurse Station (Apollo Hospital)
1. Log in to **Nurse Station** -> Select **Apollo Hospital**, PIN `1234`.
2. The nurse can be on any tab (Home, Availability, Requests, or Profile).
3. **Trigger**: Within 500ms of Device 1 creating the hold, the full-screen **Siren Emergency Handshake** interrupts the screen with audio/haptic pulse.
4. **Action**: The nurse reviews the incoming request and taps **"ACCEPT HOLD"**.

### Verification across both devices:
1. **Device 1 (Ambulance)**:
   - Automatically transitions to **"HOLD ACCEPTED"** with navigation route to Apollo Hospital.
2. **Device 2 (Nurse Station)**:
   - Bottom bar navigates to the **Home Tab**.
   - Under **Active Inbound Ambulance**, an inbound card appears:
     - **Driver**: `Ramesh Kumar`
     - **Ambulance**: `MH04AB1234`
     - **Phone**: `9876543210` (with a clickable `"Call Ambulance Crew"` button)
     - **Bed**: `ICU + Ventilator`
     - **Severity**: `Critical` (red badge)
     - **Note**: `"Male 45, acute myocardial infarction, intubated"`
3. **Arrival & Inventory Discharge**:
   - Nurse taps **"MARK ARRIVED"**.
   - Confirmation dialog executes Firestore transaction:
     - Apollo Hospital's vacant ICU beds decrement by 1.
     - The request is moved from active to historical records.
4. **Requests Tab Audit**:
   - Nurse navigates to the **Requests Tab**.
   - The card appears with an `Arrived` badge.
   - Nurse taps the card -> the **Request Details Sheet** opens showing the full driver snapshot, contact button, and timestamped cascade history.

---

## Test Case 9: Live GPS Ambulance Tracking & Route Simulator

**Objective**: Verify high-frequency background GPS streaming from the ambulance, live map updates with heading rotation on the receiving nurse's device, freshness state indicators, and drive simulator playback.

### Sub-Test 9.1: Real-Device Background GPS & Google Maps Foreground
1. **Device 1 (Driver)** creates an emergency request; **Device 2 (Nurse)** accepts the hold.
2. Observe on **Device 1**:
   - Status transitions to `BED HELD SUCCESSFULLY`.
   - Green badge displays: `"Sharing live location"`.
   - Notification drawer shows persistent Android foreground notification:
     `BedLink – sharing location with hospital` | `Ambulance location is updating in real time`.
3. Tap **"Navigate with Google Maps"** on Device 1:
   - Google Maps opens in the foreground for turn-by-turn navigation.
   - Device 1 remains on road navigation for 1 minute.
4. Observe on **Device 2 (Nurse Home Tab)**:
   - The inbound request card displays an interactive OpenStreetMap.
   - Ambulance marker continuously updates every 4 seconds without freezing or dropping, proving the Android foreground service and `WAKELOCK` are operating correctly in the background.

### Sub-Test 9.2: Route Simulator with Speed Multiplier (Demo Mode)
1. On **Device 1 (Driver)** hold status screen:
   - Locate the **"Debug Route Simulator"** card.
   - Toggle **"Simulate Drive"** to `ON`.
   - Choose speed multiplier: `1x`, `2x`, or `4x`.
2. Observe on **Device 2 (Nurse)**:
   - The ambulance marker begins moving along the OSRM road polyline.
   - Marker rotates smoothly according to the calculated compass bearing.
   - Interpolated animation (1.2s ease-in-out) transitions the marker between updates without jumping.
   - Remaining distance (km) and live ETA (min) update in real time.
3. **Manual Map Interaction**:
   - Drag or pinch-to-zoom the map on Device 2.
   - Notice camera auto-fitting disables immediately and a floating **"Re-center"** button appears.
   - Tap **"Re-center"** $\rightarrow$ camera smoothly snaps back to frame both the hospital and ambulance markers.
4. **Arrival Detection**:
   - When the simulated ambulance reaches within 150 meters of the hospital, an **"Arriving now"** teal chip appears on the nurse card.
   - Simulator automatically stops upon reaching the hospital gates.

### Sub-Test 9.3: Freshness States & Connection Loss Recovery
1. On **Device 1**, disable Wi-Fi / Cellular Data (or simulate network timeout).
2. Observe on **Device 2**:
   - $0\text{s} - 20\text{s}$: Green dot displays `"Live"`.
   - $20\text{s} - 60\text{s}$: Amber dot displays `"Last updated 24s ago"`.
   - $> 60\text{s}$: Badge shifts to `"Signal lost – last seen at HH:MM"` with the vehicle marker greyed out (strictly adhering to the semantic-red clinical alarm rule).
3. Re-enable network on Device 1:
   - Firestore synchronizes queued telemetry.
   - Nurse card recovers seamlessly to green `"Live"` within one polling tick.

### Sub-Test 9.4: App Kill & Resume Recovery
1. While an emergency hold is active (`accepted`), force-quit the ambulance app on Device 1.
2. Nurse card on Device 2 eventually transitions to `"Signal lost"`.
3. Relaunch BedLink on Device 1 and navigate back to the active request:
   - Live location service detects active `accepted` state and resumes streaming automatically.
   - Nurse card immediately transitions back to `"Live"`.

---

## Test Case 10: FCM Background Alerts, Reachability & Delivery ACK

### Sub-Test 10.1: Device Token Registration & Cleanup
1. **Nurse Login & Registration**:
   - On **Device 2**, log in as Lilavati Hospital nurse (PIN `1234`).
   - Check Firestore document `hospitals/lilavati_bandra/devices/{deviceId}`:
     - Document exists with `loggedIn: true`, `platform: "android"` (or `"ios"`), and valid `token`.
     - `hospitals/lilavati_bandra` doc has `hasActiveDevices: true`.
2. **Nurse Logout & Cleanup**:
   - On **Device 2**, navigate to Profile $\rightarrow$ tap **Logout**.
   - Check Firestore: the device document has been deleted or set to `loggedIn: false`.
   - `hospitals/lilavati_bandra` doc updates `hasActiveDevices: false` if no other devices are logged in.

### Sub-Test 10.2: Background Wake-up & Sound Alert
1. Log in on Device 2 (Nurse) and press the home button (app in background, screen on or locked).
2. On Device 1 (Crew), dispatch an emergency hold to Lilavati Hospital.
3. Observe Cloud Functions:
   - `onEmergencyRequestWrite` detects status `offered` and dispatches high-priority multicast FCM push.
   - Idempotency guard prevents duplicate pushes for the same offer attempt.
4. Device 2 receives the high-priority push:
   - APNs / Android heads-up alert sounds with time-sensitive interruption.
   - Tapping the notification brings BedLink directly into the triage siren modal.

### Sub-Test 10.3: Delivery Acknowledgment (ACK)
1. Upon reception of the alert on Device 2 (foreground or background handler), the device automatically writes `alertDeliveredAt: FieldValue.serverTimestamp()` on the request document.
2. On Device 1 (Crew) `HoldStatusScreen`:
   - Under the countdown ring, an `"Alert delivered to hospital"` teal chip appears immediately.
   - Crew has real-time visual certainty that the hospital's terminal has received the notification.

### Sub-Test 10.4: Reachability vs 0-Second Auto-Skip
1. **Backgrounded Nurse with Device Token**:
   - Nurse app is minimized (foreground heartbeat $> 90\text{s}$ stale, but `hasActiveDevices: true`).
   - Crew dispatches hold $\rightarrow$ Hospital status displays `"Reachable via Push"`.
   - System **does NOT auto-skip**; it holds for the full 120s countdown waiting for the nurse to respond.
2. **Truly Unreachable Hospital**:
   - In Firestore, set both `isNurseOnline: false` (or stale) and `hasActiveDevices: false`.
   - In Results list: status badge displays `"Unreachable"`.
   - When hold is initiated: banner displays `"Unreachable (Auto-Skip)"`, the hold immediately auto-skips (0 seconds elapsed), and cascades to Hospital #2.

---

## 📱 Phase 10B - Android Background Wake-Up & Notification Test Matrix

| Scenario | State Before Push | Expected OS & App Behavior | Verification Method |
| :--- | :--- | :--- | :--- |
| **1. Foreground** | Nurse app active on any tab | No duplicate status bar notification; full-screen in-app modal opens instantly with siren and countdown ring. | Inspect screen; verify no double-siren. |
| **2. Backgrounded** | Home button pressed, phone awake | High-importance alarm heads-up notification pops with raw siren sound & vibration. Tapping launches `IncomingRequestScreen`. | Minimize app $\rightarrow$ send hold from Crew device. |
| **3. Terminated** | App swiped away from Recents | Top-level `@pragma('vm:entry-point')` handler executes. Local alarm notification shows with insistent siren sound. Tapping cold-starts app directly to the active offer. | Swipe BedLink from recent apps $\rightarrow$ dispatch hold. |
| **4. Screen Locked** | Device screen turned off / locked | Full-Screen Intent wakes the display (`showWhenLocked="true"`, `turnScreenOn="true"`), sounding the looping siren over the lock screen. | Lock phone with power button $\rightarrow$ dispatch hold. |
| **5. Android Doze Mode** | Device idle in deep sleep | High-priority FCM message (`priority: 'high'`) grants temporary network and wakelock slice, piercing Doze to sound alarm. | Run `adb shell dumpsys deviceidle force-idle` $\rightarrow$ dispatch hold. |
| **6. Airplane Reconnect** | Airplane mode enabled, then disabled | Offer delivered within 120s countdown window triggers notification; expired offers ($>120\text{s}$) display "This request is no longer active". | Toggle Airplane Mode ON for 10s $\rightarrow$ dispatch hold $\rightarrow$ toggle Airplane Mode OFF. |
| **7. Dual Nurse Devices** | 2 phones logged into same station | Both devices ring simultaneously. When Nurse on Device A taps **Accept**, Cloud Function sends `cancel_request` to Device B, immediately silencing Device B's siren and clearing the notification. | Log 2 phones into Lilavati $\rightarrow$ dispatch hold $\rightarrow$ accept on Phone A. |
| **8. Auto-Cascade Ringing** | Hospital A ringing; 120s elapses | Cloud Function sends `cancel_request` to Hospital A (silences alarm) and sends `incoming_request` to Hospital B (starts ringing). | Let 120s timer expire without accepting. |
| **9. Auto-Cancel Safety Net** | Network drops after offer starts | At `offerExpiresAt`, local timer fires automatically, clearing the persistent system notification without needing a network cancel push. | Turn off Wi-Fi while phone is ringing in background $\rightarrow$ wait for 120s expiry. |
| **10. Nurse Logout** | Nurse logged out | Device token deleted from `hospitals/{hospitalId}/devices/{deviceId}`. Subsequent offers to that hospital do not trigger pushes to that device. | Tap Logout in Profile tab $\rightarrow$ dispatch hold. |

### Useful ADB Commands for Verification:
```bash
# Force Android device into deep Doze mode
adb shell dumpsys battery unplug
adb shell dumpsys deviceidle force-idle

# Check current Doze step (should output IDLE)
adb shell dumpsys deviceidle step

# Exit Doze mode and restore battery status
adb shell dumpsys deviceidle unforce
adb shell dumpsys battery reset

# Inspect active Notification Channels for BedLink
adb shell dumpsys notification --noredact | grep -A 10 "bedlink_emergency_alerts"

# Inspect granted Full-Screen Intent permissions (Android 14)
adb shell cmd appops get app.bedlink USE_FULL_SCREEN_INTENT

# Grant Full-Screen Intent permission via shell (for testing automation)
adb shell cmd appops set app.bedlink USE_FULL_SCREEN_INTENT allow

# View BedLink FCM background process logs
adb logcat -s FcmService:V AlarmNotificationService:V flutter:V
```

```

---

## Test Case 11: Clinic & Lab Appointment Booking, Mocked Payment & Revenue Snapshot

**Objective**: Verify the outpatient monetization flow: deterministic demo booking seeding, slot calendar selection, Razorpay Checkout invocation with server fee enforcement, appointment confirmation with BLA reference, live `MyAppointments` reflection, and real-time Revenue Snapshot aggregation.

### Part A: Seed Demo Bookings & Inspect Revenue Snapshot
1. Launch BedLink, navigate to splash screen, and long-press the BedLink logo (or tap hidden demo controls).
2. Under **Database Reset & Seeding**, tap **"Seed Demo Bookings (3 Days · ~35% Booked)"**.
3. **Expected Result**:
   - Cloud Function executes deterministic slot reservation.
   - SnackBar notifies: `Seeded <N> demo bookings across 3 days! Grid is demo-ready.`
4. Scroll down to the **Revenue Snapshot** card (marked with `DEMO SANDBOX` badge).
5. **Expected Result**:
   - **Total Bookings**: e.g., `42`.
   - **Total Revenue**: e.g., `₹2,898` (computed purely from confirmed server transactions).
   - **Daily Average**: e.g., `₹966/d`.
   - **Breakdown**: Clinics (`₹79` fee) vs Diagnostic Labs (`₹49` fee) with respective counts and rupee sub-totals.
   - Tap **"Refresh Revenue"** to verify live recalculation.

### Part B: Patient Slot Booking & Razorpay Checkout Flow
1. Navigate to **Patient Hub** -> tap **"Specialty Clinics & Labs"** (Option 4).
2. Select any specialty (e.g. *Blood Tests & Pathology* or *General Physician*) and tap a clinic result card (e.g. *Metropolis Healthcare & Diagnostic Centre*).
3. Tap the full-width green CTA button: **"Book an appointment · ₹49"**.
4. On the **Appointment Booking Screen**:
   - Inspect clinic header: Name, badge, address, operating hours.
   - Select today's date or tomorrow from the horizontal 7-day strip.
   - Verify slot grid renders:
     - Free slots (white card with border).
     - Booked slots (~dark yellow `#B8860B` with `Booked` status).
     - Past slots (greyed out with past lead-time indicator).
     - If all slots today have passed, an informative banner indicates: *"All appointment slots for today have already passed. Please select an upcoming date."*
   - Tap any available free slot (turns Clinical Teal `#0E7C86`).
   - Sticky bottom bar activates: shows selected time, fee preview, and countdown timer.
5. In **Patient Details Form**:
   - Name is prefilled from patient profile (or enter full legal name).
   - Phone is prefilled with 10-digit mobile number.
   - Reason for visit is optional.
6. Tap **"Pay ₹49 & confirm"**:
   - Progress indicator appears while `createAppointmentOrder` Cloud Function acquires a 5-minute atomic lock.
   - Razorpay Checkout modal opens displaying:
     - Merchant: `BedLink Healthcare`
     - Description: `Metropolis Healthcare - Appointment Booking`
     - Exact Fee: `₹49.00`
7. Complete payment in test mode (select Netbanking / UPI Success):
   - Razorpay triggers `onSuccess` callback with `razorpay_payment_id` and `razorpay_signature`.
   - BedLink client calls `verifyAppointmentPayment` Cloud Function for cryptographic HMAC-SHA256 signature verification.
8. **Confirmation Screen**:
   - Green success checkmark renders.
   - **Booking Reference**: `BLA-XXXXXX` generated and displayed prominently.
   - **Details Card**: Clinic name, formatted IST date & time, patient name, and non-refundable policy text:
     *"Booking fee is non-refundable. Please arrive 10 minutes prior to your scheduled slot."*
   - Action buttons: **Navigate** (Google Maps) and **Call Clinic** (`tel:`).
   - Tap **"View in My Appointments"**.

### Part C: Patient Appointments Hub & Live Reflection
1. On **My Appointments Screen** (`/patient/appointments`):
   - Navigate to **"Upcoming"** tab.
   - Newly booked appointment appears with `CONFIRMED` badge, BLA reference, clinic address, and formatted Asia/Kolkata timestamp.
2. Return to **Hidden Demo Controls**:
   - Tap **"Refresh Revenue"**.
   - Verify Total Bookings increased by 1 and Total Revenue increased by the exact clinic/lab fee.
3. Tap **"Reset All Data"**:
   - Clears all active requests, resets hospital beds, and invokes `resetDemoBookings` to purge demo slots and demo appointments.

456: 
457: ---
458: 
459: ## Test Case 12: Ambulance Crew Availability Status, Presence Publishing & Auto-Transitions
460: 
461: **Objective**: Verify that verified ambulance crews can manage operational availability, observe reactive status indicator pills, publish throttled GPS presence in `crewPresence/{uid}`, trigger auto-transitions across dispatch lifecycle events, and validate relief candidate eligibility.
462: 
463: ### Part A: Manual Availability Status Selector
464: 1. Launch BedLink on **Device 1** and log in as a verified ambulance crew (or complete registration to reach `VERIFIED`).
465: 2. Navigate to the **Profile Tab** (`CrewProfileTab`).
466: 3. Scroll to **"Editable details"**:
467:    - Observe the **Availability Status** card showing three colored chips:
468:      - **Available** (Go Green `#1E9E5A` background with check icon when active).
469:      - **Online – Busy** (Caution Amber `#E8A317` background with clock icon when active).
470:      - **Offline** (Alert Red `#D32F2F` background with slash icon when active).
471:    - Verify dynamic description updates below the chips:
472:      - When *Available*: `"Ready to take a relief request."`
473:      - When *Online – Busy*: `"Online but on a trip / not available."`
474:      - When *Offline*: `"Off duty / not taking requests."`
475: 4. Tap **"Available"**:
476:    - Crew status persists locally in `SharedPreferences` and in Firestore (`crewPresence/{uid}`).
477:    - Observe the `CrewStatusPill` in the AppBar update immediately to a green `"Available"` pill.
478: 5. Tap **"Online – Busy"**:
479:    - Pill updates to yellow `"Online – Busy"`.
480: 6. Tap **"Offline"**:
481:    - Pill updates to semantic red `"Offline"`.
482: 
483: ### Part B: Location Permission Warning Banner
484: 1. Disable location permissions for BedLink in Android device settings.
485: 2. Return to the **Profile Tab** with status set to **"Available"**.
486: 3. **Expected Result**:
487:    - A prominent amber warning banner renders immediately below the status selector:
488:      *"Location off – you won't receive relief requests"*.
489: 4. Re-enable location permissions: banner disappears automatically.
490: 
491: ### Part C: Automatic State Transitions Lifecycle
492: 1. Ensure crew status is set to **"Available"**.
493: 2. Navigate to the **Dispatch Tab** -> tap **"New Emergency Request"**.
494: 3. Fill in patient vitals and initiate hospital search. Tap **"Initiate 2-Min Hold"**:
495:    - **Expected Result**:
496:      - Background state machine triggers: crew status transitions automatically to `BUSY`.
497:      - Prior status (`AVAILABLE`) is saved in memory and storage.
498:      - The header status pill transitions to `"Online – Busy"`.
4. In **Hold Status Screen**, tap **"Cancel Hold"** (or allow countdown to expire / nurse to reject):
   - **Expected Result**:
     - Prior status is restored: status returns automatically to `AVAILABLE`.
     - Header status pill switches back to green `"Available"`.
5. In **Crew Profile Tab**, scroll to bottom and tap **"Sign Out"**:
   - **Expected Result**:
     - Status is automatically updated to `OFFLINE` in Firestore (`crewPresence/{uid}`).
     - Location publisher stops immediately.

### Part D: Relief Candidate Eligibility Engine
1. Verify candidate qualification logic (`isCrewEligibleForRelief`):
   - Crew is eligible ONLY if:
     - `status == AVAILABLE`
     - `updatedAt` location age $\le 120\text{s}$ (fresh presence ping)
     - Active FCM tokens count $\ge 1$ (device can receive multicast alerts).
   - Candidates with status `BUSY` or `OFFLINE`, location pings $>120\text{s}$ old, or $0$ FCM tokens are immediately disqualified from relief cascades.

---

## Test Case 13: Disabled Emergency Relief Backend, Wave Expansion & Atomic Acceptance

**Objective**: Verify that when an active ambulance breaks down on an accepted trip, `createReliefRequest` queries eligible nearby ambulances, filters by AIS-125 tier hierarchy, expands radius waves [5, 10, 15] km, broadcasts high-priority data-only FCM alerts without PII, guarantees strictly one winner under simultaneous accepts, advances waves upon timer expiration, and supports dual-path cancellation/abortion.

### Part A: Relief Request Creation & Tier Filtering
1. Log in as a verified ambulance crew with an active trip in status `accepted` or `en_route`.
2. Invoke `createReliefRequest({ originalRequestId, reason: "breakdown" })`:
   - **Expected Result**:
     - Cloud Function verifies caller ownership and verified crew status.
     - Resolves disabled ambulance coordinates server-side from `liveLocations` or `crewPresence`.
     - Filters candidates in `crewPresence`:
       - `status == "AVAILABLE"`
       - Location freshness $\le 120\text{s}$
       - Accuracy $\le 100\text{m}$
       - Candidate AIS-125 tier $\ge$ original ambulance tier (`Type A < Type B < Type C < Type D`).
     - Wave 0 checks radius $5\text{ km}$; if no candidates, auto-expands to wave 1 ($10\text{ km}$) or wave 2 ($15\text{ km}$).
     - Creates `reliefRequests/{id}` with `status: "searching"` and `offerExpiresAt = now + 60s`.
     - Creates `reliefRequests/{id}/offers/{candidateUid}` with `status: "pending"`.
     - Dispatches data-only FCM push (`type: "relief_request"`, TTL 60s) without patient name or hospital destination.
     - Original emergency request is updated with `reliefState: "searching"`.

### Part B: First-Accept Wins Concurrency & Presence Transition
1. Two candidate ambulances (`candidate_A` and `candidate_B`) receive the offer and attempt to accept simultaneously.
2. Both invoke `respondToReliefRequest({ reliefRequestId, action: "accept" })`:
   - **Expected Result**:
     - Firestore atomic transaction guarantees strictly one winner.
     - Winner receives `{ success: true, code: "ACCEPTED" }`.
     - Winner's presence is automatically updated to `status: "BUSY"`.
     - Competing crew receives `{ success: false, code: "ALREADY_TAKEN" }`.
     - Other offers under `reliefRequests/{id}/offers` are marked `status: "taken"`.
     - `relief_cancel` FCM alert is multicast to losing candidates to silence alerts.

### Part C: Wave Advancement & Expiration
1. If the 60s offer window passes without acceptance, requester invokes `advanceReliefWave({ reliefRequestId })`:
   - **Expected Result**:
     - Server verifies that `offerExpiresAt` has actually passed.
     - Pending offers from the previous wave are marked `status: "expired"`.
     - `relief_cancel` alert is sent to expired candidates.
     - Radius expands to next wave (e.g. 5 km $\rightarrow$ 10 km $\rightarrow$ 15 km).
     - If wave 2 is exhausted with 0 candidates, request transitions to `status: "no_ambulance"`.

### Part D: Dual-Path Cancellation & Mission Abort
1. **Requester Cancellation**:
   - Requester vehicle recovers and invokes `cancelReliefRequest({ reliefRequestId })`.
   - Relief request transitions to `status: "cancelled"`.
   - Original emergency request resets `reliefState: null`.
   - If an ambulance had accepted, their presence is automatically restored to `AVAILABLE`.
2. **Accepted Relief Crew Abort**:
   - Accepted relief ambulance encounters an issue before reaching disabled vehicle and invokes `cancelReliefRequest`.
   - Aborting crew presence is restored to `AVAILABLE`.
   - Relief request transitions back to `status: "searching"` with a fresh 60s offer window.
   - Original request returns to `reliefState: "searching"`.

---

## 16. Firestore & Storage Security Rules Verification

### Running Firestore Emulator Rules Test Suite
When Java Runtime is installed:
```bash
# Start Firestore emulator and run Jest rules test suite
cd /Users/harsh_thakur/Desktop/Bedlink
firebase emulators:exec --only firestore "cd functions && npm test -- tests/firestoreRules.test.ts"
```

### Invariants Enforced by Rules:
1. **Crew Immutability**:
   `request.resource.data.diff(resource.data).affectedKeys().hasOnly(['ais125Tier', 'ambulanceType', 'contactNumber'])`
   Attempts by crew clients to alter `ambulanceId`, `vehicleNumber`, or `verificationStatus` return `PERMISSION_DENIED`.
2. **Crew Document Isolation**:
   `request.auth.uid == uid`
   A crew member reading another crew's document returns `PERMISSION_DENIED`.
3. **Nurse Hospital Isolation**:
   `resource.data.currentHospitalId == request.auth.token.hospitalId`
   A nurse reading requests addressed to another hospital returns `PERMISSION_DENIED`.
4. **Unverified Crew Block**:
   `get(/databases/$(database)/documents/ambulances/$(request.auth.uid)).data.verificationStatus == 'VERIFIED'`
   Unverified crew (`PENDING`, `REJECTED`, or `NEEDS_REVIEW`) attempting to create a request returns `PERMISSION_DENIED`.
5. **Slot Inventory Direct Read/Write Block**:
   `match /slots/{slotId} { allow read, write: if false; }`
   Prevents untrusted clients from directly reading, scraping, or writing slot documents. All slot availability is computed server-side via `getClinicDaySlots`.
6. **Appointment Isolation & Server-Only Creation**:
   `match /appointments/{appId} { allow read: if request.auth != null && request.auth.uid == resource.data.patientUid; allow write: if false; }`
   Restricts appointment read access to the authenticated owning patient (`patientUid`), and blocks all direct client writes (creates, updates, deletes). Appointments can ONLY be created by the server via `verifyAppointmentPayment` or verified Razorpay webhooks.
7. **Crew Presence Ownership & Coordinate Validation**:
   `match /crewPresence/{uid} { allow read: if request.auth != null && request.auth.uid == uid; allow write: if request.auth != null && request.auth.uid == uid && isVerifiedCrew() && ...; }`
   Restricts read/write access to the owning crew member, enforces that only verified crew can publish presence, validates `status` values (`AVAILABLE`, `BUSY`, `OFFLINE`), and enforces valid latitude/longitude coordinate bounds ($-90 \le \text{lat} \le 90$, $-180 \le \text{lng} \le 180$). Client attempts by unverified crews, another crew member, or payloads with invalid coordinates return `PERMISSION_DENIED`.
8. **Relief Requests & Offers Server-Only Isolation**:
   `match /reliefRequests/{id} { allow read: if isRequesterOrAcceptedCrew(); allow write: if false; match /offers/{candidateUid} { allow read: if isCandidateOrRequester(); allow write: if false; } }`
   Restricts `reliefRequests/{id}` read access strictly to the requester or the accepted relief crew; restricts offer docs to the candidate crew or requester; and blocks all direct client writes (creates, updates, deletes) to guarantee that relief operations can only be executed via verified Cloud Functions.
9. **Voice Notes Cloud Storage Rules**:
   `match /voiceNotes/{requestId}/{fileName} { allow read: if false; allow write: if isAuthenticated() && request.resource.size <= 1572864 && request.resource.contentType.matches('audio/.*'); }`
   Direct client reads are completely blocked (all reads go via `getVoiceNoteUrl` callable for secure signed URL generation); uploads require authentication, max file size is strictly capped at $1.5\text{MB}$ (1,572,864 bytes), and MIME type must match `audio/*`.

---

## 17. Master Hackathon Real-Device Demo Script (Revenue & USP Features)

This script provides the step-by-step physical device execution flow for the live hackathon demonstration of BedLink's new revenue monetization, disabled emergency relief, and voice note dispatch features.

### 17.1 Real-Device Fleet Architecture & Role Setup

For the complete multi-stakeholder demonstration, prepare physical devices (or test devices/emulators) assigned as follows:

| Role Name | Device Type | Auth Identity | Pre-Condition State |
| :--- | :--- | :--- | :--- |
| **Phone 1 (Patient A)** | Physical Smartphone | Patient Alice (`patient_alice`) | Logged into Patient Hub; searching clinics. |
| **Phone 2 (Patient B)** | Physical Smartphone / Browser | Patient Bob (`patient_bob`) | Viewing the same clinic's appointment slot grid. |
| **Phone 3 (Crew A)** | Physical Smartphone | Ambulance Crew A (`BL-AMB-100001`, `MH04AB1234`) | Verified Type C Mobile ICU; logged into Crew Portal. |
| **Phone 4 (Nurse Station)** | Physical Smartphone | Nurse Station (Lilavati Hospital, PIN `1234`) | Logged into 4-Tab Portal; screen locked or backgrounded. |
| **Phone 5 (Crew B - Available)** | Physical Smartphone | Ambulance Crew B (`BL-AMB-200002`, `MH02CD5678`) | Verified Type C Mobile ICU; Status set to **Available (Green)**. |
| **Phone 6 (Crew C - Busy)** | Device / Test Profile | Ambulance Crew C (`BL-AMB-300003`) | Verified Type B; Status set to **Online – Busy (Amber)**. |
| **Phone 7 (Crew D - Offline)** | Device / Test Profile | Ambulance Crew D (`BL-AMB-400004`) | Verified Type C; Status set to **Offline (Red)**. |

---

### 17.2 Act I: Outpatient Appointment Booking & Real-Time Dark-Yellow Slot Reflection

**Objective**: Demonstrate end-to-end appointment slot locking, Razorpay test checkout, instant BLA confirmation, and real-time reflection of the booked slot as dark yellow on a concurrent second patient's phone without refresh.

#### Execution Steps:
1. **Side-by-Side Slot Grid Preparation**:
   - On **Phone 1 (Patient A)**, launch BedLink $\rightarrow$ Select **"I'm a Patient"** $\rightarrow$ Tap **"Specialty Clinics & Diagnostic Labs"**.
   - Select **"Suburban Diagnostics - Bandra West"** $\rightarrow$ Tap the full-width green CTA: **"Book an appointment · ₹49"**.
   - On **Phone 2 (Patient B)**, navigate to the exact same screen for **Suburban Diagnostics**.
   - Observe both phones displaying the 7-day date strip and the IST slot grid.
   - Pick tomorrow's date on both phones. Identify a vacant morning slot (e.g., **10:30 AM**, styled with a white background and Fog `#D5E2E5` border).

2. **Patient A Selects & Holds Slot**:
   - On **Phone 1**, tap **10:30 AM**.
   - The slot highlights in Clinical Teal (`#0E7C86`).
   - The sticky bottom bar updates: `"10:30 AM · Tomorrow · Pay ₹49 & confirm"`.
   - Tap **"Pay ₹49 & confirm"**.
   - The 5-minute countdown hold begins (`heldUntil`), and the native Razorpay Checkout sheet opens.

3. **Patient A Completes Razorpay Test Payment**:
   - In the Razorpay modal:
     - Select **Card**.
     - Enter standard Razorpay test card:
       - **Card Number**: `4111 1111 1111 1111`
       - **Expiry**: `12/30`
       - **CVV**: `123`
     - Tap **"Pay Now"** $\rightarrow$ In the test OTP screen, tap **"Success"**.
   - Progress indicator spins briefly while Cloud Function `verifyAppointmentPayment` validates the HMAC-SHA256 signature and commits the appointment.

4. **Verify Immediate Confirmation on Phone 1**:
   - Phone 1 navigates to the **Appointment Confirmation Screen**:
     - Green success badge with reference: `BLA-XXXXXX` (e.g. `BLA-849201`).
     - Clinic Name: *Suburban Diagnostics - Bandra West*.
     - Scheduled Time: *Tomorrow, 10:30 AM IST*.
     - Amount Paid: *₹49.00*.
     - Non-refundable notice: *"Booking fee is non-refundable"*.
     - Action buttons: **Navigate** and **Call Clinic**.

5. **Verify Real-Time Dark-Yellow Slot Reflection on Phone 2**:
   - Look at **Phone 2 (Patient B)** immediately (without manual refresh or reloading).
   - Observe the **10:30 AM** slot:
     - The background has dynamically transitioned from white to **Dark Yellow / Dark Amber (`#B8860B` / `#D97706` tinted)** with a lock icon.
     - Tapping the 10:30 AM slot on Phone 2 displays the disabled tooltip: *"This slot has already been booked"*.

---

### 17.3 Act II: Voice Note Dispatch, Lockscreen Siren Interplay & Audio Play/Resume

**Objective**: Paramedic attaches a voice note describing acute patient vitals; nurse phone is locked; incoming FCM alert wakes the screen and triggers the insisted looping siren; nurse taps Play, siren pauses cleanly; when voice note finishes, siren automatically resumes; nurse accepts hold.

#### Execution Steps:
1. **Prepare Locked Nurse Station Phone**:
   - On **Phone 4 (Nurse Station)**:
     - Log in as **Lilavati Hospital & Research Centre** (PIN `1234`).
     - Navigate to the **Profile Tab** $\rightarrow$ verify all 4 Emergency Alerts setup checkmarks are green.
     - Press the power button to **LOCK Phone 4**. Place Phone 4 flat on the demo desk.

2. **Crew A Formulates Dispatch with Voice Note**:
   - On **Phone 3 (Crew A)**:
     - Select **Ambulance Crew Portal** $\rightarrow$ Tap **"New Emergency Request"**.
     - Select Needs: **ICU Bed** + **Ventilator**.
     - Severity: **Critical**.
     - Tap the microphone button on the **Voice Note Recorder**:
       - Red recording dot pulses; live waveform animates; timer ticks: `00:01`, `00:02`, `00:06`.
       - Paramedic speaks: *"Lilavati triage, male 45, acute ST-elevation MI, crushing retrosternal pain radiating to left jaw, O2 sat 88% on reservoir, BP 85 over 50, preparing for immediate catheterization."*
       - Tap Stop (■) $\rightarrow$ Audio card renders with playback duration `00:07`, Play button, and Delete trashcan.
     - Tap **"Find Hospitals"** $\rightarrow$ Lilavati Hospital ranks #1.
     - Tap **"Initiate 2-Min Hold"**.
     - Voice note uploads to `voiceNotes/{requestId}/note.m4a` under 1.5MB Storage security rules, and 120s countdown ring starts.

3. **Lockscreen Wake-up & Insistent Looping Siren**:
   - On **Phone 4 (Locked Nurse Station)**:
     - High-priority FCM wake-up arrives within milliseconds.
     - Phone 4's display turns ON automatically via full-screen intent.
     - Full-screen emergency modal interrupts the lockscreen.
     - High-urgency looping siren audio and vibration begin immediately without echo.
   - On **Phone 3 (Crew A)**:
     - Observe the `"Alert delivered to hospital"` green confirmation chip appear under the countdown ring.

4. **Siren & Voice Note Audio Interplay**:
   - On **Phone 4 (Nurse Station)**:
     - Nurse observes the voice note card on the triage sheet: `"Paramedic Voice Note (0:07)"`.
     - Nurse taps **Play (▶)**:
       - **Crucial Invariant Check**: The looping siren audio and vibration immediately **PAUSE**.
       - Paramedic's clear voice plays through the speaker: *"Lilavati triage, male 45, acute ST-elevation MI..."*
       - When the 7-second voice note finishes playing:
       - **Crucial Invariant Check**: The insistent siren audio and repeating vibration **AUTOMATICALLY RESUME** without user intervention because the 120s offer is still active.
     - Nurse reviews bed inventory and taps **"ACCEPT HOLD"**.
     - Looping siren stops completely; system notification tray item is dismissed cleanly.

---

### 17.4 Act III: Disabled Emergency Trigger, Filtered 60s Alert & Live Route Simulator

**Objective**: Crew A suffers an en-route breakdown and taps "Disabled Emergency"; candidate selection filters by availability and tier, dispatching a 60s siren alert ONLY to Crew B (Available); Crew C (Busy) and Crew D (Offline) receive nothing; B accepts; A tracks B approaching live via the route simulator.

#### Execution Steps:
1. **Pre-Flight Crew Status Configuration**:
   - **Phone 5 (Crew B)**: Profile $\rightarrow$ set status to **Available (Green)**.
   - **Phone 6 (Crew C)**: Profile $\rightarrow$ set status to **Online – Busy (Amber)**.
   - **Phone 7 (Crew D)**: Profile $\rightarrow$ set status to **Offline (Red)**.

2. **Crew A Triggers Disabled Emergency**:
   - On **Phone 3 (Crew A)**, while in active accepted transit:
     - Tap the high-visibility red badge button: **"DISABLED EMERGENCY"**.
     - Select Breakdown Reason: **"Mechanical Breakdown"** (e.g. radiator burst / engine failure).
     - Tap **"Request Colleague Backup"**.
   - Cloud Function `createReliefRequest`:
     - Resolves Crew A's live coordinates.
     - Queries `crewPresence` within Wave 0 ($5\text{ km}$).
     - Filters:
       - Crew B: `status == AVAILABLE`, tier `TYPE_C >= TYPE_C` $\rightarrow$ **QUALIFIES**.
       - Crew C: `status == BUSY` $\rightarrow$ **FILTERED OUT (Disqualified)**.
       - Crew D: `status == OFFLINE` $\rightarrow$ **FILTERED OUT (Disqualified)**.

3. **Verify Alert Delivery Isolation**:
   - **Phone 6 (Crew C)** and **Phone 7 (Crew D)**: Remain completely silent. No siren, no modal.
   - **Phone 5 (Crew B - Available)**:
     - Screen interrupts immediately with the dark-urgency **Relief Request Alert Screen**.
     - Dedicated peer relief siren sounds.
     - Display shows:
       - *"Colleague ambulance needs help"*.
       - Reason: *"Mechanical Breakdown"*.
       - Distance: e.g. *2.4 km* · Estimated ETA: *5 min*.
       - Patient Severity: *CRITICAL* (patient name, phone, and destination hospital are strictly hidden).
       - Vehicle Tier: *Type C (MICU)*.
       - 60-second synchronized countdown ring ticking down.

4. **Crew B Accepts & Crew A Monitors Approach**:
   - On **Phone 5 (Crew B)**: Tap **"ACCEPT RELIEF"**.
   - Transaction commits atomically; Crew B's status automatically transitions to `BUSY`.
   - Phone 5 transitions to **Relief Navigation View**, plotting the route to Crew A's stationary breakdown coordinates.
   - On **Phone 3 (Crew A)**:
     - Screen automatically transitions to **Relief Tracking Mode**.
     - Status updates to: *"Backup ambulance BL-AMB-200002 accepted! En route to your position"*.
     - Live map shows Crew A (red stationary breakdown marker) and Crew B (green moving ambulance marker).

5. **Drive Simulator for Approaching Backup**:
   - On **Phone 5 (Crew B)**:
     - In the debug drawer, toggle **"Debug Route Simulator"** ON.
     - Select speed: **2x** or **4x**.
   - On **Phone 3 (Crew A)**:
     - Watch Crew B's marker navigate along the street grid towards Crew A in real time.
     - Distance and ETA update dynamically ($2.4\text{ km} \rightarrow 1.2\text{ km} \rightarrow 0.3\text{ km}$).

---

### 17.5 Act IV: Handover Handshake, Nurse Station Ambulance Change & Trip Completion

**Objective**: Crew B arrives at Crew A's location, taps "Help Reached", unlocks hospital destination details; Nurse Station Home screen dynamically updates to show the new relief vehicle; Crew B drives to Lilavati Hospital; Nurse marks arrived; trip completes with bed decrement.

#### Execution Steps:
1. **Crew B Arrives at Disabled Ambulance**:
   - When Phone 5 (Crew B) reaches within 150m of Crew A:
   - Tap **"Help Reached (Transfer Patient)"**.
   - The security veil lifts: Phone 5 now displays the full hospital destination:
     - **Destination**: *Lilavati Hospital & Research Centre*.
     - **Reserved Bed**: *ICU Bed #4 (Ventilator attached)*.
     - **Patient Details**: *Male 45, acute MI*.
   - Tap **"Confirm Handover & Resume Route"**.

2. **Nurse Station Real-Time Ambulance Update**:
   - On **Phone 4 (Nurse Station)**, navigate to the **Home Tab**:
   - In the **Active Inbound Ambulance** section:
     - Observe the vehicle badge dynamically switch:
       - Previous: `BL-AMB-100001 (MH04AB1234 - Ramesh Kumar)`
       - **Updated**: `BL-AMB-200002 (MH02CD5678 - Backup Crew B)`
     - A blue pill displays: *"Relief Vehicle Handover Completed"*.
     - The live map now tracks Crew B approaching Lilavati Hospital.

3. **Trip Completion & Final Bed Handshake**:
   - Simulated Crew B arrives at Lilavati Hospital gate ($<150\text{m}$).
   - On **Phone 4 (Nurse Station)**:
     - Card displays: `"Arriving now"`.
     - Nurse taps **"MARK ARRIVED"**.
     - Atomic Firestore transaction executes:
       - Lilavati Hospital's available ICU beds decrement from `3` to `2`.
       - Trip status transitions to `arrived`.
       - Telemetry stream is cleanly terminated.
   - On **Phone 5 (Crew B)**:
     - Screen displays: *"Patient admitted successfully at Lilavati Hospital"*.
     - Status automatically restores to **Available (Green)**.

---

### 17.6 Act V: Resiliency, Wave Expansion & Failure Edge Cases

#### Pathway 1: Nobody Accepts (Wave Expansion to "No Ambulance")
1. Crew A triggers Disabled Emergency.
2. If all candidates in Wave 0 (5 km) reject or let the 60s timer expire:
   - Server-side `advanceReliefWave` executes.
   - Wave expands to Wave 1 (10 km) $\rightarrow$ fresh 60s countdown begins.
3. If Wave 1 expires without acceptance:
   - Wave expands to Wave 2 (15 km).
4. If Wave 2 expires with zero acceptances:
   - Request status cleanly transitions to `no_ambulance`.
   - Crew A's screen displays prominent emergency guidance: *"No nearby relief ambulance available. Contacting central EMS control room (108)..."* with direct dialer button.

#### Pathway 2: Simultaneous Acceptance Collision
1. Two nearby available crews (Crew B and Crew E) receive the relief alert simultaneously.
2. Both crews tap **"ACCEPT RELIEF"** within milliseconds of each other.
3. **Firestore Atomic Transaction Invariant**:
   - Crew B's transaction commits first: wins mission, status transitions to `accepted`.
   - Crew E's transaction evaluates `current.status != 'searching'`: transaction aborts cleanly.
   - Crew E receives an immediate friendly toast: *"Another ambulance accepted"*.
   - Crew E's screen dismisses cleanly, and Crew E remains in `AVAILABLE` status.

#### Pathway 3: Requester Vehicle Recovers & Cancels
1. Crew A triggers Disabled Emergency.
2. Crew B accepts and begins routing towards Crew A.
3. Crew A's mechanic clears the radiator airlock and the vehicle restarts.
4. Crew A taps **"Cancel Relief Request (Vehicle Recovered)"**.
5. Server commits `status: 'cancelled'`, and dispatches high-priority data-only `relief_cancel` push to Crew B.
6. Crew B's phone displays: *"Relief request cancelled by colleague (Vehicle recovered)"*.
7. Crew B's navigation dismisses cleanly, and Crew B's operational status is restored to **Available**.

---

### 17.7 Remaining Engineering TODOs & Technical Limitations

The following items are scheduled for upcoming release cycles beyond Phase 14:

| Feature / Limitation | Current State | Required Engineering Work | Effort Est. |
| :--- | :--- | :--- | :--- |
| **Clinic-Side Booking Portal** | No web interface for clinic receptionists to manage schedules. | Build Flutter Web / React admin portal with Firebase Auth custom claims (`role: clinic_admin`) allowing clinics to block doctor leave dates, configure slot intervals, and export daily patient rosters. | 3–4 Days |
| **Cancellation & Refund Policy Engine** | Appointments are strictly confirmed with non-refundable fee. | Add `cancelAppointment` Cloud Function with tiered refund logic (100% refund $>4\text{h}$ before slot, 50% $>2\text{h}$, 0% $<2\text{h}$) integrating Razorpay Refund REST API (`POST /v1/payments/{id}/refund`). | 2 Days |
| **GST Invoice Generation** | Simple digital confirmation screen with Razorpay payment ID. | Implement Cloud Function with PDF generator (`pdfkit` or Dart `pdf`) generating GST-compliant tax invoices (18% GST on platform convenience fees) dispatched via SendGrid email. | 2 Days |
| **iOS Background Siren Limitation (Relief Alerts)** | iOS devices play a single chime instead of continuous looping siren when locked. | Apple `UNNotificationSound` does not support `FLAG_INSISTENT` looping in the background without Apple's proprietary **Critical Alerts** entitlement (`com.apple.developer.usernotifications.critical-alerts`). Requires formal healthcare provider application to Apple. Android is fully supported with native full-screen intent alarms. | Apple Review Dependent |

