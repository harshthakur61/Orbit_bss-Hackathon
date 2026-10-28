class CrewStrings {
  // Navigation & Headers
  static const String registerCrewTitle = 'Ambulance Crew Registration';
  static const String crewLoginTitle = 'Ambulance Crew Login';
  static const String verificationStatusTitle = 'Verification Status';
  static const String crewTerminalTitle = 'Ambulance Crew Terminal';

  // Wizard Steps
  static const String step1Title = 'Vehicle';
  static const String step2Title = 'Driver';
  static const String step3Title = 'Account';

  // Step 1: Vehicle
  static const String vehicleSectionTitle = 'Step 1: Vehicle Details';
  static const String vehicleSectionSubtitle =
      'Enter official transport registration details of the ambulance vehicle.';
  static const String vehicleNumberLabel = 'Vehicle Registration Number';
  static const String vehicleNumberHint = 'e.g. MH-04-AB-1234';
  static const String vehicleFormatHint = 'Format: MH-04-AB-1234 (Auto-formatted)';
  static const String chassisEngineLabel = 'Chassis / Engine Number';
  static const String chassisEngineHint = 'Optional (e.g. MA3E...)';
  static const String rcDocumentLabel = 'Registration Certificate (RC)';
  static const String supportingDocBadge = 'Supporting Document';
  static const String rcDocumentHelp =
      'Optional supporting document for transport audit records.';
  static const String uploadRcButton = 'Upload RC Photo';
  static const String rcPhotoAttached = 'RC Photo attached';
  static const String removePhoto = 'Remove';
  static const String ambulanceTypeLabel = 'Ambulance Service Type';
  static const String ais125TierLabel = 'AIS-125 Ambulance Tier';

  // Step 2: Driver
  static const String driverSectionTitle = 'Step 2: Driver Credentials';
  static const String driverSectionSubtitle =
      'Official credentials of the assigned driver for government verification.';
  static const String driverLegalNameLabel = 'Driver Legal Name';
  static const String driverLegalNameHint = 'Full name as printed on Driving License';
  static const String dlNumberLabel = 'Driving License (DL) Number';
  static const String dlNumberHint = 'e.g. DL-0420110012345 or MH0420110012345';
  static const String dlFormatHint = 'Must be a valid State RTO Driving License number';
  static const String dobLabel = 'Date of Birth (DOB)';
  static const String dobHint = 'Select Date of Birth (YYYY-MM-DD)';
  static const String selectDobButton = 'Select Date';
  static const String contactNumberLabel = 'Contact Mobile Number';
  static const String contactNumberHint = 'e.g. +91 98765 43210';

  // Step 3: Account
  static const String accountSectionTitle = 'Step 3: Crew Credentials';
  static const String accountSectionSubtitle =
      'Set a secure password for this ambulance crew terminal account.';
  static const String passwordLabel = 'Account Password';
  static const String passwordHint = 'Minimum 6 characters';
  static const String confirmPasswordLabel = 'Confirm Password';
  static const String confirmPasswordHint = 'Re-enter your password';

  // Form Actions & Errors
  static const String nextStep = 'Next Step';
  static const String previousStep = 'Previous';
  static const String submitRegistration = 'Submit Application';
  static const String submittingRegistration = 'Submitting & Verifying...';
  static const String errorVehicleRequired = 'Please enter a valid vehicle registration number.';
  static const String errorDriverRequired = 'Please enter driver legal name.';
  static const String errorDlRequired = 'Please enter a valid Driving License number.';
  static const String errorDobRequired = 'Please select the driver date of birth.';
  static const String errorPasswordLength = 'Password must be at least 6 characters.';
  static const String errorPasswordMismatch = 'Passwords do not match.';

  // Login Screen
  static const String loginHeaderTitle = 'Ambulance Terminal Access';
  static const String loginHeaderSubtitle =
      'Sign in with your verified Ambulance ID or Application Reference to access emergency dispatch.';
  static const String identifierLabel = 'Ambulance ID / Application Reference';
  static const String identifierHint = 'e.g. APP-102938 or BL-AMB-100001';
  static const String signInButton = 'Sign In to Crew Terminal';
  static const String signingIn = 'Signing in...';
  static const String newCrewQuestion = 'New ambulance service? ';
  static const String registerLink = 'Register Application';
  static const String invalidCredentialsError =
      'Invalid Ambulance ID / Application Reference or Password. Please try again.';

  // Verification Waiting / Pending Screen
  static const String notVerifiedYetMessage = 'You are not verified yet';
  static const String liveProgressHint =
      'Live stream connected. Verifying vehicle fitness, commercial class & driver transport endorsement...';
  static const String manualReviewTitle = 'Application Under Review';
  static const String manualReviewMessage = 'Your application needs manual review.';
  static const String defaultReviewDetails =
      'Your application requires additional manual scrutiny by the health authority.';
  static const String applicationRejectedTitle = 'Application Rejected';
  static const String defaultRejectionDetails =
      'The provided vehicle or driver credentials could not be verified against transport databases.';
  static const String registerAgainButton = 'Register again with corrected details';
  static const String appRefLabel = 'Application Reference';
  static const String appRefSaveGuidance =
      "Save this reference. You'll use it to log in until you're verified.";
  static const String copyButton = 'Copy Reference';
  static const String copiedToClipboard = 'Application Reference copied to clipboard';
  static const String signOutButton = 'Sign Out';
  static const String liveWaitingNotice =
      'This terminal will automatically transition to the dashboard once approved.';

  // First-time Verified Celebration
  static const String verifiedAmbulanceBadge = 'Verified Ambulance';
  static const String congratulationsTitle = 'Ambulance Approved & Active!';
  static const String firstTimeVerifiedNotice =
      'Use this Ambulance ID to log in from now on.';
  static const String proceedToTerminal = 'Proceed to Terminal';
}
