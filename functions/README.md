# 🚑 BedLink Cloud Functions — Ambulance Verification & Auth

Backend verification and authentication services for BedLink Ambulance Crew registration, automated RTO compliance checks, and secure credential resolution.

---

## ⚙️ Architecture & Verification Modes

The verification engine abstracts external transport verification providers behind a unified `VerificationProvider` interface:

```
                  ┌───────────────────────────────┐
                  │     VerificationProvider      │
                  │  - verifyVehicle(plate)       │
                  │  - verifyLicense(dl, dob)     │
                  └───────────────┬───────────────┘
                                  │
                 ┌────────────────┴────────────────┐
                 ▼                                 ▼
      ┌─────────────────────┐           ┌─────────────────────┐
      │    MockProvider     │           │   SandboxProvider   │
      │  (Default / Local)  │           │   (Sandbox.co.in)   │
      └─────────────────────┘           └─────────────────────┘
```

The active provider is chosen automatically via the `VERIFICATION_MODE` environment variable.

### 1. Mock Mode (`VERIFICATION_MODE=mock`)
Default mode when no configuration is specified. Suitable for local testing, CI/CD, and offline demonstrations.

#### Mock Provider Test Matrix
| Field | Value Suffix | Simulated Outcome | Resulting Status |
| :--- | :--- | :--- | :--- |
| **Vehicle Plate** | Ends in `0000` (e.g. `MH02AB0000`) | Returns class `TAXICAB` | 🔴 `REJECTED` |
| **Vehicle Plate** | Ends in `9999` (e.g. `MH02AB9999`) | Returns fitness expired yesterday | 🔴 `REJECTED` |
| **Driving License** | Ends in `0000` (e.g. `DL-0000`) | Missing commercial Transport (`TRANS`) endorsement | 🔴 `REJECTED` |
| **Driving License** | Ends in `9999` (e.g. `DL-9999`) | Returns license status `SUSPENDED` | 🔴 `REJECTED` |
| **Owner Name** | Does not match driver name (e.g. Hospital / Trust owned) | Non-matching or institutional owner detected | 🟡 `NEEDS_REVIEW` |
| **Compliant Data** | Standard numbers (e.g. `MH02AB1234` + `MH0220180012345`) | All rules pass | 🟢 `VERIFIED` |

### 2. Sandbox Mode (`VERIFICATION_MODE=sandbox`)
Connects to the Sandbox.co.in API aggregator for real Indian RTO / Parivahan lookups.

To configure for production / cloud deployment:
```bash
# Set the secret key in Google Secret Manager via Firebase CLI
firebase functions:secrets:set SANDBOX_API_KEY

# Set the environment variable in Cloud Functions configuration
# In functions/.env or Cloud Console:
VERIFICATION_MODE=sandbox
```

---

## 🔒 Security & Privacy Guarantees

1. **Zero PII Logging**: Driver License numbers, Date of Birth, Phone Numbers, and Vehicle numbers are never logged in function standard output or error traces.
2. **Rate Limiting**: Endpoints enforce windowed call frequency limits per IP/UID to prevent enumeration attacks.
3. **Duplicate Prevention**: Re-registering plates or DL numbers already in `VERIFIED` or `PENDING` status is rejected.
4. **Collision-Safe Ambulance IDs**: `BL-AMB-XXXXXX` IDs are generated inside atomic Firestore transactions.

---

## 🧪 Running Unit Tests

Unit tests verify all rule engines (vehicle compliance, commercial license endorsements, fuzzy name similarity, and owner reviews) without contacting external APIs:

```bash
cd functions

# Install dependencies
npm install

# Run Jest unit test suite
npm test
```

---

## 📦 Cloud Functions Catalog

### 1. `submitAmbulanceRegistration` (Callable)
- **Input**:
  - `vehicleNumber`: Indian vehicle plate (e.g. `MH02AB1234`)
  - `dlNumber`: Driving License number
  - `dob`: Date of birth (`YYYY-MM-DD`)
  - `driverLegalName`: Driver full name
  - `password`: Account password (min 6 characters)
  - `contactNumber`: Crew contact phone number
  - `ambulanceType`: `"PRIVATE"` | `"GOVERNMENT"`
  - `ais125Tier`: `"TYPE_A"` | `"TYPE_B"` | `"TYPE_C"` | `"TYPE_D"`
- **Actions**:
  1. Sanitizes plate and DL formats.
  2. Creates Firebase Auth user with synthetic email `<appRef>@crew.bedlink.app`.
  3. Writes initial `ambulances/{uid}` document with `PENDING` status.
  4. Runs verification engine and updates document to `VERIFIED`, `NEEDS_REVIEW`, or `REJECTED`.
- **Output**: `{ applicationRef, status, ambulanceId, rejectionReason, reviewReason }`

### 2. `resolveCrewLogin` (Callable)
- **Input**: `{ identifier: string }`
  - Accepts either Application Reference (`APP-XXXXXX`) or verified Ambulance ID (`BL-AMB-XXXXXX`).
- **Actions**:
  1. Resolves identifier against Firestore records.
  2. Returns application reference and current verification status without leaking other credentials.
- **Output**: `{ applicationRef, ambulanceId, status }`

---

## 💳 Phase 11A: Clinic & Lab Appointment Booking & Razorpay Secrets

### 1. Razorpay Secret Configuration via Firebase CLI

All Razorpay verification and order transactions execute strictly on the server in Cloud Functions (v2 TypeScript) using Google Secret Manager. Secret keys are never bundled in the Flutter mobile application.

```bash
# Configure Razorpay Test Key ID
firebase functions:secrets:set RAZORPAY_KEY_ID

# Configure Razorpay Test Key Secret
firebase functions:secrets:set RAZORPAY_KEY_SECRET

# Configure Razorpay Webhook Secret (for verifying incoming X-Razorpay-Signature)
firebase functions:secrets:set RAZORPAY_WEBHOOK_SECRET
```

*For local testing or offline development, fallback test credentials (`rzp_test_...`) and mock modes (`MOCK_RAZORPAY=true`) are supported out of the box.*

### 2. Phase 11A Cloud Functions Catalog

#### A. `getClinicDaySlots` (Callable)
- **Input**: `{ clinicId: string, dateKey: string }` (e.g. `dateKey: "20261030"`)
- **Actions**:
  1. Validates `dateKey` in `Asia/Kolkata` timezone.
  2. Reads clinic operating hours (`openTime`, `closeTime`, `slotDurationMin`, `weeklyOffDays`).
  3. Queries `slots` collection to identify booked slots or active holds.
  4. Returns complete slot grid with status: `"free"`, `"booked"`, or `"past"`.
  5. Decouples client from reading the `slots` collection directly.

#### B. `createAppointmentOrder` (Callable)
- **Input**: `{ clinicId: string, startTime: string, patientName: string, patientPhone: string }`
- **Actions**:
  1. Enforces min 30-min lead time, max 7-day advance booking window, and operating hours.
  2. Reads server-side clinic booking fee (e.g., ₹79 for clinics, ₹49 for labs); **ignores any client-supplied amount**.
  3. Executes an atomic Firestore transaction: acquires a 5-minute temporary hold (`holdExpiresAt = now + 5m`) in `slots/{clinicId_YYYYMMDD_HHmm}` and creates `appointments/{appointmentId}` with status `"pending_payment"`.
  4. Calls Razorpay REST API (`/v1/orders`) to generate an order.
  5. If order creation fails, rolls back the slot hold automatically.
- **Output**: `{ appointmentId, orderId, amountPaise, keyId, holdExpiresAt }`

#### C. `verifyAppointmentPayment` (Callable)
- **Input**: `{ appointmentId: string, razorpayOrderId: string, razorpayPaymentId: string, razorpaySignature: string }`
- **Actions**:
  1. Validates HMAC-SHA256 signature (`orderId|paymentId`) using constant-time comparison (`crypto.timingSafeEqual`).
  2. In an atomic transaction, checks if the slot is still held for this appointment (or free):
     - If available: marks slot `"booked"`, marks appointment `"confirmed"`.
     - If conflict occurred (hold expired and another patient claimed the slot): marks appointment `"refunded"` and invokes Razorpay Refund REST API.
  3. Fully idempotent: repeated verification calls return the confirmed result without duplicate actions.

#### D. `releaseAppointmentHold` (Callable)
- **Input**: `{ appointmentId: string }`
- **Actions**:
  1. Verifies caller is the owning patient (`patientUid == request.auth.uid`).
  2. Deletes or releases the temporary hold in `slots`, returning the slot to `"free"`.
  3. Updates appointment status to `"payment_failed"`.

#### E. `razorpayWebhook` (HTTPS Endpoint)
- **URL**: `https://<region>-<project>.cloudfunctions.net/razorpayWebhook`
- **Actions**:
  1. Validates `X-Razorpay-Signature` against the raw payload using `RAZORPAY_WEBHOOK_SECRET`.
  2. Handles `payment.captured` and `order.paid` events.
  3. Confirms appointments in the background if the mobile application was dismissed or killed before checkout redirected.

---

## 🎙️ Cloud Storage Lifecycle Rule for Voice Notes (Phase 13A)

Emergency dispatch voice notes are stored under `voiceNotes/{requestId}/note.m4a`. To preserve storage quotas and enforce data retention hygiene, all objects under the `voiceNotes/` prefix must be automatically deleted after 3 days (72 hours).

### Step 1: Create a Lifecycle JSON Configuration (`gcs-lifecycle.json`)

```json
{
  "rule": [
    {
      "action": {
        "type": "Delete"
      },
      "condition": {
        "age": 3,
        "matchesPrefix": ["voiceNotes/"]
      }
    }
  ]
}
```

### Step 2: Apply the Lifecycle Rule via Google Cloud CLI

Run the following command in terminal targeting your Firebase project bucket:

```bash
# Using gcloud storage (recommended):
gcloud storage buckets update gs://<YOUR_FIREBASE_STORAGE_BUCKET> --lifecycle-file=gcs-lifecycle.json

# Or using gsutil:
gsutil lifecycle set gcs-lifecycle.json gs://<YOUR_FIREBASE_STORAGE_BUCKET>
```

To verify the lifecycle rule is applied:

```bash
gcloud storage buckets describe gs://<YOUR_FIREBASE_STORAGE_BUCKET> --format="default(lifecycle_rules)"
```

