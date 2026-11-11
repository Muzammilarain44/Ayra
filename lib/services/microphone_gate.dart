import 'package:permission_handler/permission_handler.dart';

/// What the ON flow must do about the microphone permission before
/// starting the background service.
///
/// Why this exists: the app runs a microphone-type foreground service
/// (Android 14+). Android refuses to start it without RECORD_AUDIO
/// granted — startForeground throws a SecurityException and the
/// service start fails. On a fresh install no runtime permission is
/// granted yet, so ON must ask for the mic FIRST, in the UI isolate
/// (a permission dialog cannot be shown from the background isolate).
/// Pure and unit-tested: the UI passes the current status in and
/// follows the decision out.
enum MicGate {
  /// Mic is granted — start the service.
  proceed,

  /// Mic is denied (can still ask) — request it once, then re-check.
  request,

  /// Mic is permanently denied / restricted — do not start; send the
  /// user to the app Settings page instead.
  openSettings,
}

/// Decides the next mic step from the current permission status.
MicGate micGateDecision(PermissionStatus status) {
  if (status.isGranted) return MicGate.proceed;
  if (status.isPermanentlyDenied || status.isRestricted) {
    return MicGate.openSettings;
  }
  return MicGate.request;
}
