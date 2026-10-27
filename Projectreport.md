# 🏥 BedLink: Real-Time Emergency Healthcare, Bed Allocation & AI Diagnostics
## Comprehensive Project Engineering & Architectural Report

---

## 📌 Executive Summary

**BedLink** is an end-to-end mission-critical healthtech platform designed to resolve one of emergency medicine's most fatal bottlenecks: **finding and reserving the right hospital bed for critical patients in real time**. 

In high-acuity medical emergencies (such as cardiac arrest, acute respiratory failure, polytrauma, or severe burns), every elapsed minute drastically compounds mortality risk. Yet, the status quo across many healthcare systems remains stubbornly analogue: paramedics and families frantically call hospital switchboards or drive from emergency room to emergency room without knowing if an Intensive Care Unit (ICU), ventilator, or cardiac bed is actually vacant. 

BedLink eliminates this fatal latency through a unified, reactive software ecosystem spanning three major stakeholders:
1. **Ambulance Dispatch Crews & Paramedics**: Utilizing dynamic multi-criteria ranking algorithms to match critical patient needs with optimal nearby hospitals and executing an automated **2-Minute Confirm-and-Hold** protocol with zero-overhead auto-cascading.
2. **Hospital Nursing & Bed-Management Staff**: Empowered with an ultra-lightweight **10-Second Bed Update Dashboard** that enables instantaneous inventory adjustment on low-cost mobile hardware, complete with real-time freshness timestamps and intrusive emergency alert handshakes.
3. **Patients & Outpatient Healthcare Seekers**: Providing a comprehensive **Healthcare Hub** that includes multimodal **AI Medical Test Report Analysis** (translating lab values into plain English and triaging severity), specialist clinic and diagnostic lab discovery, and tele-consultations with certified doctors via integrated digital payments.

---

## 🚨 Problem Statement & Domain Context

### 1. The Emergency Room Dilemma: The "Golden Hour" Crisis
In emergency medical services (EMS), the *"Golden Hour"* refers to the initial 60-minute window following trauma or acute illness during which definitive medical treatment can prevent irreversible organ failure or death. However, standard ambulance workflows frequently suffer from the following systemic breakdowns:
- **Blind Transports**: Paramedics transport unstable patients toward the geographically closest hospital without verified knowledge of critical equipment availability.
- **The "Beds Exist, But Where?" Paradox**: While a hospital may advertise 20 open general beds, its 4 ICU beds and 2 ventilators may be occupied. Arriving at a facility that lacks the required modality results in catastrophic patient transfers.
- **Data Decay (Staleness)**: Hospital bed statuses change minute-by-minute as patients are discharged, admitted, or pass away. Centralized municipal bed boards often rely on manual spreadsheets updated once every 12 to 24 hours, making the data dangerously outdated.
- **Handshake Void**: Even if an ambulance identifies a vacant bed via telephone, there is no reservation guarantee. By the time the ambulance navigates city traffic to arrive, the bed is often assigned to an internal emergency walk-in.
- **High Cognitive Load on Nurses**: Emergency nurses face severe burnout and intense clinical workloads. Complex desktop Hospital Information Systems (HIS) with multi-screen authentication and nested forms lead nurses to abandon bed updating altogether.

### 2. The Patient Diagnostic & Discovery Gap
Outside emergency ambulances, ambulatory patients face a parallel dilemma:
- **Lab Report Incomprehensibility**: Diagnostic reports (CBC, Thyroid Profiles, ECGs, Biopsies) are packed with clinical terminology and numeric reference ranges that create anxiety or lead patients to ignore life-threatening markers (e.g., elevated Troponin I or critical hypoxia).
- **Misallocated Healthcare Utilization**: Patients with minor, localized ailments (such as mild dermatitis or routine iron deficiency) frequently overwhelm hospital emergency rooms, while patients with emergent pathologies delay seeking critical care.
- **Fragmented Clinic Discovery**: Patients needing routine pathology or specialist consultations struggle to locate nearby clinics with transparent pricing, verified ratings, and operating hours.

---

## 💡 The Solution Implemented by BedLink

BedLink solves these structural inefficiencies through an interconnected, role-responsive mobile architecture built on **Flutter**, **Firebase Cloud Firestore**, **OpenRouter Multimodal AI (Gemini 2.5 Flash Lite)**, **Open Source Routing Machine (OSRM)**, and **Razorpay**:

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                                 BEDLINK PLATFORM                                │
└───────────────┬─────────────────────────┬─────────────────────────┬─────────────┘
                │                         │                         │
                ▼                         ▼                         ▼
   ┌─────────────────────────┐  ┌────────────────────────┐  ┌─────────────────────────┐
   │   AMBULANCE DISPATCH    │  │     HOSPITAL NURSE     │  │   PATIENT HEALTH HUB    │
   │  - Multi-Bed Match Form │  │  - 10-Second Bed Tiles │  │  - AI Report Analyzer   │
   │  - Weighted Rank Engine │  │  - 1-Tap Timestamp Touch│ │  - Clinic/Lab Discovery │
   │  - 2-Min Hold Stepper   │  │  - Full-Screen Siren   │  │  - Tele-Consultations   │
   │  - Auto-Cascade Failover│  │  - Atomic Accept/Reject│  │  - Digital Vitals Card  │
   │  - Turn-by-Turn Nav     │  │  - Hold Release/Arrive │  │  - Razorpay Checkout    │
   └────────────┬────────────┘  └───────────┬────────────┘  └────────────┬────────────┘
                │                           │                            │
                └───────────────────┬───────┴────────────────────────────┘
                                    │ Real-Time Streams & Atomic Transactions
                                    ▼
                     ┌─────────────────────────────┐
                     │     FIREBASE FIRESTORE      │
                     │  - hospitals/{hospitalId}   │
                     │  - requests/{requestId}     │
                     │  - clinics/{clinicId}       │
                     └──────────────┬──────────────┘
                                    │
           ┌────────────────────────┼────────────────────────┐
           ▼                        ▼                        ▼
┌─────────────────────┐  ┌─────────────────────┐  ┌─────────────────────┐
│  OSRM ROUTING API   │  │   OPENROUTER AI     │  │   RAZORPAY GATEWAY  │
│ - Real-time Driving │  │ - Gemini Vision/NLP │  │ - Orders & Links    │
│ - Distance & ETA    │  │ - Report Triage     │  │ - Verified Payment  │
└─────────────────────┘  └─────────────────────┘  └─────────────────────┘
```

---

## 🏛️ System Architecture & Technical Approach

### 1. Architectural Philosophy: Reactive, Resilient, Zero-Key Fallback
BedLink is engineered around four core technical principles:
- **Real-Time Reactive Streaming**: Built using Flutter Riverpod `StreamProvider` subscribing to Cloud Firestore document and collection snapshots. Whenever a nurse modifies bed counts or a dispatch request changes state, all connected clients re-render instantaneously without polling.
- **Fail-Safe Offline Autonomy**: Mission-critical operations must never fail due to third-party outages. If the external OSRM driving engine times out, BedLink automatically falls back to an internal **Haversine Distance Engine** adjusted with urban traffic coefficients. If the OpenRouter AI API fails or is offline, the system seamlessly transitions to an internal **Heuristic Rule & Regex Medical Engine**.
- **Atomic Concurrency Guarantees**: Bed reservation operations utilize Firestore transactions (`runTransaction`). Multiple ambulances competing for a single remaining ICU bed cannot trigger race conditions; the transaction verifies availability, decrements inventory, and marks the hold atomically.
- **Single-Codebase, Role-Segregated UI**: A single Flutter application binary services all roles (Nurse, Ambulance, Patient, and Hackathon Judge Demo), maximizing deployment agility while strictly isolating state and workflows.

---

## 🧩 Comprehensive Feature-by-Feature Breakdown

### Module 1: Ambulance Dispatcher & Emergency Bed Allocation

#### 1.1 Multi-Bed Needs Selection & Severity Formulation
- **File**: [`lib/features/dispatch/new_request_screen.dart`](file:///Users/harsh_thakur/Desktop/Bedlink/lib/features/dispatch/new_request_screen.dart)
- **Features**:
  - **Bed Modality Selector**: Multi-select toggle chips for **ICU**, **Ventilator**, **Oxygen**, **Cardiac**, **Burns**, and **General**. Multiple beds can be co-demanded for a single patient (e.g., a patient requiring both an ICU bed and a Ventilator).
  - **Triage Acuity Level**: Three-tier patient condition selector:
    - 🔴 **Critical**: Weighting travel time 1.5× more heavily in the ranking algorithm.
    - 🟡 **Serious**: Standard 1.0× baseline travel time weighting.
    - 🟢 **Stable**: Lower travel urgency (0.8× weighting).
  - **Clinical Field Notes**: Text field allowing paramedics to input acute observations (e.g., *"Crush injury, bilateral pneumothorax, intubated"*).
  - **GPS Auto-Detection with Map Pin Override**: Automatically retrieves coordinates using device GPS (`geolocator`); includes an interactive Leaflet/OpenStreetMap modal dialog allowing paramedics to manually tap and position a custom origin pin anywhere in the metropolitan area.

#### 1.2 Multi-Factor Hospital Bed Ranking Engine
- **Files**: [`lib/services/ranking_service.dart`](file:///Users/harsh_thakur/Desktop/Bedlink/lib/services/ranking_service.dart), [`lib/features/dispatch/results_screen.dart`](file:///Users/harsh_thakur/Desktop/Bedlink/lib/features/dispatch/results_screen.dart)
- **Features**:
  - **Weighted Scoring Algorithm**: Evaluates all hospitals in the database against four dynamic penalty vectors.
  - **Driving Time & Distance Calculation**: Queries the Open Source Routing Machine (OSRM) HTTP API (`router.project-osrm.org`) for precise street-level driving duration and kilometers.
  - **Staleness Tracking**: Evaluates how many minutes have passed since the hospital's last inventory confirmation.
  - **Emergency Room Load Level**: Ingests hospital operational strain (Low, Medium, High) into penalty calculations.
  - **"Why this rank?" Transparency Modal**: Every hospital card features an information sheet revealing the exact mathematical formula components:
    $$\text{Final Score} = \text{Travel Score} + \text{Staleness Penalty} + \text{Load Penalty} + \text{Partial Match Penalty}$$
  - **Stale Data Filter**: A toggle button allowing dispatchers to hide any facility whose inventory has not been updated within 60 minutes.
  - **One-Tap Dialing & External Navigation**: Direct `tel:` intent execution to call the hospital emergency desk and `geo:` / Google Maps navigation intent launching.

#### 1.3 Confirm-and-Hold Protocol & Cascading Engine
- **Files**: [`lib/features/dispatch/hold_status_screen.dart`](file:///Users/harsh_thakur/Desktop/Bedlink/lib/features/dispatch/hold_status_screen.dart), [`lib/services/firestore_service.dart`](file:///Users/harsh_thakur/Desktop/Bedlink/lib/services/firestore_service.dart)
- **Features**:
  - **Synchronized 2-Minute Circular Countdown**: Built with [`CountdownRing`](file:///Users/harsh_thakur/Desktop/Bedlink/lib/core/widgets/countdown_ring.dart). Both the ambulance screen and the receiving hospital nurse dashboard count down from an authoritative Firestore server timestamp (`offerExpiresAt`).
  - **Status Stepper Visualization**: 5-stage progress indicator:
    $$\text{Requested} \longrightarrow \text{Offered} \longrightarrow \text{Bed Held} \longrightarrow \text{En route} \longrightarrow \text{Arrived}$$
  - **Automated Cascading Failover**: If the targeted hospital rejects the request or fails to respond before the 120-second timer hits zero:
    1. The rejection/timeout attempt is appended to the request's audit log.
    2. The system automatically shifts `currentIndex` to $N+1$ in the pre-ranked hospital list.
    3. A new 120-second window is provisioned for the next best hospital.
    4. An in-app toast alerts the ambulance crew: *"Offering to next best hospital"*.
  - **Zero-Second Auto-Skip**: If the targeted hospital has zero available beds for the requested modality or if the hospital's nurse terminal is flagged offline (`isNurseOnline: false`), BedLink immediately skips to the next hospital without wasting 120 seconds.
  - **Manual Skip Override**: Allows the paramedic to manually bypass the active hospital if informed via telephone that the facility cannot accept patients.
  - **Arrival Finalization**: Marking *"Patient Arrived"* locks the bed hold permanently into the hospital's physical admissions log.

#### 1.4 Post-Trip Performance Analytics
- **File**: [`lib/features/dispatch/trip_complete_screen.dart`](file:///Users/harsh_thakur/Desktop/Bedlink/lib/features/dispatch/trip_complete_screen.dart)
- **Features**:
  - Displays total elapsed trip time from initial search to hospital arrival.
  - Time-to-acceptance metric (seconds taken for a hospital to hold the bed).
  - Attempt chain log displaying all traversed hospitals (e.g., *"Lilavati (Timeout) ➔ KEM Hospital (Accepted)"*).

---

### Module 2: Hospital Nurse 10-Second Bed Management Dashboard

#### 2.1 Rapid Bed Inventory Manipulation
- **File**: [`lib/features/nurse/bed_update_screen.dart`](file:///Users/harsh_thakur/Desktop/Bedlink/lib/features/nurse/bed_update_screen.dart)
- **Features**:
  - **Tactile Bed Tiles ([`BedTile`](file:///Users/harsh_thakur/Desktop/Bedlink/lib/core/widgets/bed_tile.dart))**: Dedicated cards for **ICU**, **Ventilator**, **Oxygen**, **Cardiac**, **Burns**, and **General**.
  - **1-Tap Increment & Decrement**: Large, finger-friendly `+` and `−` buttons with active haptics.
  - **1-Tap Available / Full Toggle**: Tapping the body of any tile instantly drops available beds to zero or restores previous capacity.
  - **Dynamic Status Visuals**:
    - 🟢 **Available** ($>2$ beds): Go Green background and border.
    - 🟡 **Low** ($1-2$ beds remaining): Caution Amber badge.
    - 🔴 **Full** ($0$ beds): Alert Red card with white text.
  - **"✓ Everything is up to date" Button**: A sticky 1-second touch action that updates `lastUpdated: FieldValue.serverTimestamp()` without altering numerical counts, allowing busy nurses to confirm accuracy in passing.
  - **Emergency Room Load Level Selector**: Quick-select chips (Low / Med / High) to signal operational congestion to the central ranking engine.

#### 2.2 Intrusive Emergency Alert Modal
- **File**: [`lib/features/nurse/incoming_request_screen.dart`](file:///Users/harsh_thakur/Desktop/Bedlink/lib/features/nurse/incoming_request_screen.dart)
- **Features**:
  - **Auto-Triggering Full-Screen Modal**: Subscribes to `streamActiveRequestForHospital(hospitalId)`. When a dispatch request targets this hospital, the screen automatically overrides current UI.
  - **Acoustic & Haptic Alarm Loop**: Uses `audioplayers` to play an emergency siren audio alert and `vibration` to pulse the device's vibration motor indefinitely until the nurse responds.
  - **Emergency Vitals Display**: Displays patient severity, requested bed types, ambulance ETA, distance, and clinical notes.
  - **Synchronized Countdown Ring**: 120-second circular countdown showing exact time remaining before the offer cascades away.
  - **Structured Rejection Flow**: Pressing "Reject" prompts a bottom sheet requiring a reason code:
    - *"No bed available"*
    - *"Staff busy"*
    - *"Equipment down"*
  - **Atomic Transaction Hold**: Accepting runs a Firestore transaction that validates bed counts, decrements the specific bed inventory, transitions the request status to `'accepted'`, and terminates the audio alarm.

#### 2.3 Nurse Presence & Request Audit History
- **Files**: [`lib/features/nurse/request_history_screen.dart`](file:///Users/harsh_thakur/Desktop/Bedlink/lib/features/nurse/request_history_screen.dart), [`lib/services/firestore_service.dart`](file:///Users/harsh_thakur/Desktop/Bedlink/lib/services/firestore_service.dart)
- **Features**:
  - Tracks nurse online/offline status via heartbeats (`updateNursePresence`).
  - Request history tab listing all past transactions categorized into Accepted, Rejected, Timed-out, and Arrived.
  - Active hold management allowing the nurse to manually release a held bed if an ambulance diverts.

---

### Module 3: Patient Healthcare Hub & Medical Profile

#### 3.1 Patient Hub Central Navigation
- **File**: [`lib/features/patient/patient_hub_screen.dart`](file:///Users/harsh_thakur/Desktop/Bedlink/lib/features/patient/patient_hub_screen.dart)
- **Features**:
  - Unified consumer interface providing frictionless access to 4 key healthcare pillars:
    1. **Emergency Hospital Beds**: Direct access to the live emergency ranking and booking system.
    2. **Clinics & Pathology Diagnostic Labs**: Discovery of specialized outpatient facilities.
    3. **AI Medical Test Report Analyzer**: Multimodal document and photo analysis.
    4. **Call Consultation**: Live tele-consultation with verified MD/MS physicians.
  - Direct Patient Access Mode: Real-time queries and report analyses can be conducted with or without account authentication.

#### 3.2 Comprehensive Digital Patient Profile
- **Files**: [`lib/models/patient_profile.dart`](file:///Users/harsh_thakur/Desktop/Bedlink/lib/models/patient_profile.dart), [`lib/providers/patient_auth_provider.dart`](file:///Users/harsh_thakur/Desktop/Bedlink/lib/providers/patient_auth_provider.dart)
- **Features**:
  - Demographics: Age, Gender, Blood Group, Height ($cm$), Weight ($kg$).
  - Chronic Conditions & Past History: Chronic disease tags (e.g., *Mild Asthma, Primary Hypertension*).
  - Allergy Register: Critical drug and environmental allergies (e.g., *Penicillin, Dust/Pollen*).
  - Active Medications: Regimen tracker (e.g., *Amlodipine 5mg Daily, Salbutamol Inhaler*).
  - Emergency SOS Contact: Direct phone dialer and relationship badge for primary next-of-kin.
  - Current Health State Pill: Real-time physiological status indicator.

---

### Module 4: Specialty Clinics & Pathology Lab Discovery Engine

#### 4.1 Multi-Specialty Outpatient Search
- **File**: [`lib/features/patient/clinic_search_screen.dart`](file:///Users/harsh_thakur/Desktop/Bedlink/lib/features/patient/clinic_search_screen.dart)
- **Features**:
  - Filter across 10 specialized domains:
    - *Dermatology (Skin)*
    - *Blood Tests & Pathology*
    - *Gynecology & Maternity*
    - *Dental Care*
    - *Pediatrics (Child)*
    - *Orthopedics (Bone & Joint)*
    - *Ophthalmology (Eye)*
    - *X-Ray & Imaging*
    - *MRI / CT Scan*
    - *Ultrasound*
  - Facility Category Toggles: Filter by *All Facilities*, *Specialist Clinics*, or *Pathology & Diagnostic Labs*.
  - GPS-based proximity calculation with interactive OpenStreetMap pin placement.

#### 4.2 Clinic Proximity & Service Ranking Engine
- **Files**: [`lib/services/clinic_ranking_service.dart`](file:///Users/harsh_thakur/Desktop/Bedlink/lib/services/clinic_ranking_service.dart), [`lib/features/patient/clinic_results_screen.dart`](file:///Users/harsh_thakur/Desktop/Bedlink/lib/features/patient/clinic_results_screen.dart)
- **Features**:
  - **Tokenized Specialty Matching**: Tokenizes user queries and matches against clinical specialties and diagnostic test catalogs.
  - **Scoring Model**: Combines travel time, rating bonuses, operating status (open/closed), and specialty match depth:
    $$\text{Score} = (\text{Travel Mins} \times 1.5) - (\text{Matched Specialties} \times 15.0) - (\text{Rating} \times 1.0) \pm \text{Open/Closed Status}$$
  - Direct calling, address routing via Google Maps, and operating hours verification.

---

### Module 5: Multimodal AI Medical Test Report Analyzer

#### 5.1 Multimodal Document & Photo Ingestion Pipeline
- **File**: [`lib/features/patient/report_list_screen.dart`](file:///Users/harsh_thakur/Desktop/Bedlink/lib/features/patient/report_list_screen.dart)
- **Features**:
  - **Camera Capture**: Paramedics or patients photograph paper laboratory printouts using the device camera (`image_picker`).
  - **Device Gallery Selection**: Upload scanned report images (`.png`, `.jpeg`, `.webp`).
  - **Digital PDF Ingestion**: Process digital diagnostic lab reports.
  - **Pre-Loaded Clinical Preset Demonstrations**: Pre-seeded clinical test reports for instant judge demonstration:
    - *Complete Blood Count (CBC) & Anemia Screen*
    - *Thyroid Hormone Profile (T3, T4, TSH)*
    - *Emergency Cardiac Markers & Low SPO2 Screen*
    - *Skin Biopsy & Allergy Panel*
    - *Routine Annual Wellness Checkup*

#### 5.2 OpenRouter AI Intelligence Pipeline
- **File**: [`lib/services/openrouter_service.dart`](file:///Users/harsh_thakur/Desktop/Bedlink/lib/services/openrouter_service.dart)
- **Features**:
  - **Model**: `google/gemini-2.5-flash-lite` via the OpenRouter API.
  - **Multimodal Payload**: Encodes image scans into Base64 data URIs and combines them with extracted text content.
  - **Enforced JSON Output Schema**: Formats clinical findings strictly into machine-parseable JSON containing:
    - `severity`: `"normal"` | `"attention"` | `"critical"`
    - `headline`: Friendly, clear summary title
    - `simpleExplanation`: Jargon-free explanation in non-technical English
    - `keyFindings`: Bullet points highlighting abnormal markers
    - `recommendationType`: `"none"` | `"clinic"` | `"hospital"`
    - `recommendationReason`: Clinical rationale
    - `recommendedSpecialty`: Suggested clinical domain
  - **Resilient Regex Markdown Cleansing**: Strips markdown backticks (````json ... ````) before deserializing into Dart domain models.

#### 5.3 Offline Heuristic Fallback Engine
- **File**: [`lib/services/report_analysis_service.dart`](file:///Users/harsh_thakur/Desktop/Bedlink/lib/services/report_analysis_service.dart)
- **Features**:
  - Operates autonomously with zero network connectivity or missing API keys.
  - Evaluates regex rules across critical biomarkers:
    - **Hypoxia & Cardiac Alert**: Detects $\text{SPO2} < 90\%$, Troponin I, ST elevation, or acute myocardial indicators $\rightarrow$ triggers **Critical Severity**.
    - **Dermatology Alert**: Detects *eczema, psoriasis, dermatitis, epidermal inflammation, IgE* $\rightarrow$ triggers **Specialist Attention (Skin)**.
    - **Pathology & Endocrinology Alert**: Detects *low hemoglobin ($<11\text{ g/dL}$), elevated TSH ($>5.5\text{ uIU/mL}$), elevated HbA1c* $\rightarrow$ triggers **Specialist Attention (Lab/Endocrine)**.
    - **Normal Panel**: Detects standard healthy limits $\rightarrow$ triggers **Normal ("Fit for now")**.

#### 5.4 Report Triage Presentation & Direct Action Flow
- **File**: [`lib/features/patient/report_analysis_screen.dart`](file:///Users/harsh_thakur/Desktop/Bedlink/lib/features/patient/report_analysis_screen.dart)
- **Features**:
  - 🚨 **Critical Alert**: Renders red emergency banners and provides a single-tap button: *"Find Emergency Hospital Bed"* (navigates directly to the bed dispatch screen with ICU/Cardiac pre-selected).
  - 🟡 **Requires Attention**: Renders amber warning banners and provides a button: *"Find Specialist Clinic"* (navigates directly to the clinic search screen with relevant specialty pre-filtered).
  - 🟢 **Normal**: Renders green checkmarks with *"You are fit for now!"* wellness advice.

---

### Module 6: Tele-Consultations & Razorpay Payment Integration

#### 6.1 Doctor Consultation Directory
- **Files**: [`lib/models/doctor_consultation.dart`](file:///Users/harsh_thakur/Desktop/Bedlink/lib/models/doctor_consultation.dart), [`lib/features/patient/doctor_consultation_screen.dart`](file:///Users/harsh_thakur/Desktop/Bedlink/lib/features/patient/doctor_consultation_screen.dart)
- **Features**:
  - Directory of verified senior MD/MS/DNB specialists across General Medicine, Cardiology, Pediatrics, Dermatology, and Orthopedic Trauma.
  - Profiles detail years of experience, total patient consultations, verified ratings, hospital affiliations (e.g., *Lilavati, KEM, Kokilaben*), spoken languages, wait times, and consultation rates (e.g., *₹350 / 10 mins*).
  - Search and category filters for instant triage.

#### 6.2 Razorpay Payment Gateway Integration
- **File**: [`lib/services/razorpay_service.dart`](file:///Users/harsh_thakur/Desktop/Bedlink/lib/services/razorpay_service.dart)
- **Features**:
  - **REST API Order Generation**: Generates real Razorpay Orders (`https://api.razorpay.com/v1/orders`) using Basic Authentication headers:
    $$\text{Authorization: Basic } \text{base64}(\text{keyId} : \text{keySecret})$$
  - **Hosted Payment Links**: Generates customer-specific payment links (`https://api.razorpay.com/v1/payment_links`) with amount specified in paise ($\text{INR} \times 100$).
  - **Simulated Offline Fallback**: In case of network drops or sandbox test errors, provides an offline mock transaction sequence to ensure hackathon presentations are never disrupted.
  - **Post-Payment Tele-Call Initiation**: Verifies transaction ID and launches direct phone dialers or web tele-consultation channels.

---

### Module 7: Hackathon Demonstration Controls & System Utilities

#### 7.1 Hidden Demo Control Center
- **File**: [`lib/features/demo/demo_controls_screen.dart`](file:///Users/harsh_thakur/Desktop/Bedlink/lib/features/demo/demo_controls_screen.dart)
- **Features**:
  - **Hidden Trigger**: Accessible by long-pressing the BedLink hospital cross logo on the splash screen.
  - **Seed All Data**: Batched insertion of 10 major Mumbai hospitals (Lilavati, KEM, Nanavati, Kokilaben, Fortis, H.N. Reliance, Hinduja, Sion, Global Parel, etc.) with pre-configured coordinates, bed capacities, and load levels, plus 8 specialized clinics and pathology labs.
  - **Reset All Data**: Purges active emergency requests and re-seeds clean test data.
  - **Simulate Aging Data**: Artificially degrades the `lastUpdated` timestamp of any hospital (e.g., sets a hospital to 50 minutes old) to demonstrate staleness penalties and color shifts (from green to amber to red).
  - **Simulate Hospital Rejection**: Triggers an automated rejection on behalf of any hospital with custom reason codes, demonstrating real-time cascading across multiple devices.
  - **Simulate Nurse Offline / Online**: Toggles nurse presence flags to demonstrate instant 0-second auto-skip.

---

## 🧮 Mathematical Formulations & Algorithms

### 1. The Hospital Bed Allocation Ranking Algorithm

The hospital ranking score $S_h$ is a **minimization objective** (where lower numerical score represents a superior emergency match):

$$S_h = S_{\text{travel}} + P_{\text{staleness}} + P_{\text{load}} + P_{\text{partial}}$$

#### A. Travel Score ($S_{\text{travel}}$)
Computed using estimated driving duration $T_{\text{drive}}$ in minutes, weighted by patient severity multiplier $\mu_{\text{sev}}$:

$$S_{\text{travel}} = T_{\text{drive}} \times \mu_{\text{sev}}$$

Where:
$$\mu_{\text{sev}} = \begin{cases} 
1.5 & \text{if Severity is Critical (travel speed prioritized)} \\ 
1.0 & \text{if Severity is Serious (standard urgency)} \\ 
0.8 & \text{if Severity is Stable (lower travel penalty)} 
\end{cases}$$

#### B. Staleness Penalty ($P_{\text{staleness}}$)
Penalizes facilities whose inventory updates are out of date:

$$P_{\text{staleness}} = \begin{cases} 
0.0 & \text{if } \Delta t \le 15\text{ minutes (Fresh)} \\ 
\min\left(30.0, \, (\Delta t - 15) \times 0.3\right) & \text{if } \Delta t > 15\text{ minutes} 
\end{cases}$$

*(Where $\Delta t$ is the elapsed minutes since the hospital's last inventory confirmation).*

#### C. Emergency Room Load Penalty ($P_{\text{load}}$)
Reflects operational congestion:

$$P_{\text{load}} = \begin{cases} 
0.0 & \text{if Load Level is Low} \\ 
5.0 & \text{if Load Level is Medium} \\ 
12.0 & \text{if Load Level is High} 
\end{cases}$$

#### D. Partial Match Penalty ($P_{\text{partial}}$)
Guarantees hospitals with missing modalities are deprioritized:

$$P_{\text{partial}} = \begin{cases} 
0.0 & \text{if } \forall b \in \text{Needs}, \, \text{Available}(b) > 0 \\ 
50.0 & \text{if } \exists b \in \text{Needs}, \, \text{Available}(b) = 0 
\end{cases}$$

---

### 2. The Driving Route & Distance Engine (OSRM vs. Haversine)

1. **Primary Route Query (OSRM)**:
   Sends an asynchronous HTTP GET request to:
   $$\text{https://router.project-osrm.org/route/v1/driving/}\text{Lng}_1,\text{Lat}_1;\text{Lng}_2,\text{Lat}_2\text{?overview=false}$$
   Extracts `duration` (seconds) and `distance` (meters) with a 3-second network timeout.

2. **Zero-Downtime Fallback (Haversine Formula)**:
   If OSRM fails or times out, BedLink executes the Haversine equation:
   $$a = \sin^2\left(\frac{\Delta \phi}{2}\right) + \cos(\phi_1)\cos(\phi_2)\sin^2\left(\frac{\Delta \lambda}{2}\right)$$
   $$d = 2 \cdot R \cdot \text{atan2}\left(\sqrt{a}, \sqrt{1-a}\right) \quad (\text{with } R = 6371\text{ km})$$
   Driving time is estimated using an empirical urban congestion speed ($V_{\text{city}} = 25\text{ km/h}$):
   $$T_{\text{fallback}} = \max\left(1, \, \left\lceil \frac{d}{25} \times 60 \right\rceil\right)$$

---

## 🗄️ Database Architecture & Firestore Schema

BedLink utilizes a denormalized, read-optimized document structure in Google Cloud Firestore:

### 1. `hospitals/{hospitalId}`
```json
{
  "name": "Lilavati Hospital & Research Centre",
  "lat": 19.0512,
  "lng": 72.8290,
  "phone": "+91 22 2675 1000",
  "pin": "1234",
  "loadLevel": "med",
  "isNurseOnline": true,
  "lastNurseActive": "Timestamp",
  "lastUpdated": "Timestamp (ServerTimestamp)",
  "beds": {
    "icu":        { "available": 3,  "total": 12 },
    "ventilator": { "available": 2,  "total": 6  },
    "oxygen":     { "available": 14, "total": 25 },
    "cardiac":    { "available": 1,  "total": 8  },
    "burns":      { "available": 0,  "total": 4  },
    "general":    { "available": 18, "total": 40 }
  }
}
```

### 2. `requests/{requestId}`
```json
{
  "patientLat": 19.0760,
  "patientLng": 72.8777,
  "needs": ["ICU", "Ventilator"],
  "severity": "critical",
  "note": "Severe respiratory distress, intubated",
  "status": "offered",
  "rankedHospitalIds": [
    "lilavati_bandra",
    "kem_parel",
    "nanavati_vileparle"
  ],
  "currentIndex": 0,
  "currentHospitalId": "lilavati_bandra",
  "offerExpiresAt": "Timestamp (ServerTimestamp + 120s)",
  "createdAt": "Timestamp (ServerTimestamp)",
  "rejectReason": null,
  "attempts": [
    {
      "hospitalId": "lilavati_bandra",
      "hospitalName": "Lilavati Hospital & Research Centre",
      "result": "pending",
      "reason": null,
      "at": "Timestamp"
    }
  ]
}
```

### 3. `clinics/{clinicId}`
```json
{
  "name": "Suburban Diagnostics & Pathology Lab",
  "type": "pathology_lab",
  "lat": 19.0550,
  "lng": 72.8320,
  "phone": "+91 22 6170 0000",
  "address": "Hill Road, Bandra West, Mumbai",
  "rating": 4.8,
  "isOpen": true,
  "operatingHours": "07:00 AM - 09:00 PM",
  "specialties": [
    "Blood Tests & Pathology",
    "X-Ray & Imaging",
    "MRI/CT Scan",
    "Ultrasound"
  ],
  "testsAvailable": [
    "CBC Blood Count",
    "Lipid Profile",
    "Thyroid Profile",
    "HbA1c Glucose",
    "RTPCR Test"
  ]
}
```

---

## 🎨 UI/UX Design System & Color Aesthetics

In mission-critical clinical environments, visual design directly affects decision speed and cognitive load. BedLink implements a purpose-built design system adhering to strict color psychology rules:

```
┌────────────────────────────────────────────────────────────────────────┐
│                        BEDLINK COLOR PALETTE                           │
├──────────────────┬─────────────────┬───────────┬───────────────────────┤
│ Role             │ Name            │ Hex Code  │ Usage                 │
├──────────────────┼─────────────────┼───────────┼───────────────────────┤
│ Primary Brand    │ Clinical Teal   │ #0E7C86   │ Brand identity, icons │
│ Primary Dark     │ Deep Teal       │ #0A5560   │ Headers, active appbar│
│ Primary Tint     │ Mist Teal       │ #E0F2F4   │ Chips, card backgrounds│
│ Background       │ Cool White      │ #F5F9FA   │ Scaffold background   │
│ Surface          │ Pure White      │ #FFFFFF   │ Elevated cards        │
│ Text Primary     │ Ink             │ #12262B   │ High-contrast headers │
│ Text Secondary   │ Slate           │ #55696E   │ Subtitles, captions   │
│ Dividers         │ Fog             │ #D5E2E5   │ Subtle structural lines│
│ Available/Go     │ Go Green        │ #1E9E5A   │ Fresh data, bed open  │
│ Warning/Caution  │ Caution Amber   │ #E8A317   │ Aging data, med load  │
│ Danger/Alert     │ Alert Red       │ #D32F2F   │ Full beds, emergency  │
│ Info/Action      │ Info Blue       │ #2B7BD6   │ Labs, diagnostic links│
└──────────────────┴─────────────────┴───────────┴───────────────────────┘
```

> [!IMPORTANT]
> **Strict Semantic Red Rule**: Red is never used as a decorative accent in BedLink. It is strictly reserved for critical alerts, exhausted bed counts, and emergency situations so that nurses and paramedics immediately recognize high-priority signals.

---

## 💻 Technology Stack Summary

| Layer | Technology | Version | Key Justification |
| :--- | :--- | :--- | :--- |
| **Framework** | Flutter | `^3.13.5` | Cross-platform compiled native performance on Android & iOS. |
| **Language** | Dart | `^3.0.0` | Strong null-safety, expressive asynchronous primitives, fast runtime. |
| **State Management** | Flutter Riverpod | `^3.4.3` | Reactive stream subscriptions, modularity, zero widget-tree coupling. |
| **Routing** | GoRouter | `^18.0.2` | Declarative, URL-driven routing with deep-link support. |
| **Database** | Firebase Firestore | `^6.10.0` | Real-time WebSocket subscriptions, offline cache, atomic transactions. |
| **AI LLM Vision** | OpenRouter API | REST | Google Gemini 2.5 Flash Lite multimodal report analysis. |
| **Maps & Tiles** | `flutter_map` + OSM | `^8.3.2` | OpenStreetMap rendering without Google Maps billing or API keys. |
| **Routing API** | OSRM Project | REST | Turn-by-turn driving durations and geometry calculations. |
| **Payments** | Razorpay REST API | REST | Order generation and payment link creation for Indian rupees. |
| **Audio Alerting** | `audioplayers` | `^6.8.1` | Foreground looping audio sirens for incoming emergency triage. |
| **Haptics** | `vibration` | `^3.2.1` | Physical vibration sequences for emergency notification. |
| **Typography** | Google Fonts (Inter) | `^9.0.0` | High-legibility clinical typography. |

---

## 🛡️ Edge Cases & Resiliency Engineering

| Failure Vector | Potential Impact | Implemented Resiliency Mechanism |
| :--- | :--- | :--- |
| **OSRM Server Latency / Outage** | Hospital ranking blocked | 3-second timeout triggers fallback to **Haversine Distance Engine** scaled by urban velocity ($25\text{ km/h}$). |
| **OpenRouter AI Network Drop** | Patient report analysis hangs | Automatic fallback to **Local Heuristic Rule & Regex Engine** within milliseconds. |
| **Simultaneous Bed Requests** | Two ambulances book the last bed | Managed via **Firestore Atomic Transactions** (`runTransaction`); bed availability is validated before decrementing. |
| **Nurse Terminal Closed / Offline** | Request stuck waiting 120s | Background presence heartbeat (`isNurseOnline`); system executes **0-Second Auto-Skip** immediately. |
| **Device Clock Skew** | Timers desynchronized across phones | All timestamp evaluations utilize Firestore server timestamps (`FieldValue.serverTimestamp()`). |
| **Accidental Nurse App Dismissal** | Emergency requests missed | Audible siren loop and persistent vibration persist until an explicit accept/reject decision is made. |

---

## 🚀 Setup & Execution Guide

### Prerequisites
- Flutter SDK (`>= 3.13.5`)
- Dart SDK (`>= 3.0.0`)
- Android Studio / Xcode with connected mobile device or emulator

### Installation Steps
```bash
# 1. Clone the repository
git clone https://github.com/harshthakur61/T20-BedLink.git
cd Bedlink

# 2. Install all Flutter package dependencies
flutter pub get

# 3. Verify static analysis
flutter analyze

# 4. Launch the application
flutter run
```

### Two-Phone Live Demonstration Instructions
1. **Device 1 (Nurse Station)**:
   - Launch app $\rightarrow$ Select **"I'm a Hospital Nurse"**.
   - Select **Lilavati Hospital & Research Centre** $\rightarrow$ Enter PIN `1234`.
   - The **10-Second Bed Management Dashboard** appears.
2. **Device 2 (Ambulance Dispatch)**:
   - Launch app $\rightarrow$ Select **"I'm an Ambulance Crew"**.
   - Select bed needs (e.g., **ICU** + **Ventilator**) $\rightarrow$ Tap **"Find Hospitals"**.
   - Select top-ranked **Lilavati Hospital** $\rightarrow$ Tap **"Select & Request Bed"**.
3. **The Live Handshake**:
   - Device 1 immediately sounds an audible alarm and displays the full-screen emergency alert modal with the 2-minute countdown ring.
   - Tap **"ACCEPT"** on Device 1.
   - Device 2 immediately flips to the bright green **"BED HELD"** banner, displays turn-by-turn navigation, and decrements Lilavati's available bed count live across both screens.

---

## 🔮 Limitations & Future Roadmap

1. **Firebase Cloud Messaging (FCM) Background Push**: Currently, incoming alerts trigger while the nurse application is active in foreground/memory. Future enterprise releases will integrate high-priority FCM data messages for background wake-ups.
2. **Hospital Electronic Health Record (EHR) Integration**: Direct bidirectional HL7/FHIR integrations to synchronize bed admissions automatically from Hospital Information Systems (HIS).
3. **IoT Ambulance Telemetry Streaming**: Real-time Bluetooth streaming of patient vitals (multipara monitors, ECG, SPO2) from the ambulance directly into the receiving hospital's triage screen.
4. **Regional Language Localizations**: Expanding AI report explanations into Hindi, Marathi, Gujarati, Tamil, and other regional Indian languages.

---
*Report Compiled for Project: BedLink HealthTech Platform — 2026*
