import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/project_with_time.dart';

/// Provider to handle navigation requests from floating widget
final navigationRequestProvider = StateNotifierProvider<NavigationRequestNotifier, NavigationRequest?>((ref) {
  return NavigationRequestNotifier();
});

/// Provider to store data for project switch (the project being switched FROM)
final projectSwitchDataProvider = StateProvider<ProjectWithTime?>((ref) => null);

/// Provider to track if we should return to floating mode after dialog
final returnToFloatingProvider = StateProvider<bool>((ref) => false);

class NavigationRequestNotifier extends StateNotifier<NavigationRequest?> {
  NavigationRequestNotifier() : super(null);

  void requestSubmissionForm() {
    state = NavigationRequest.submissionForm;
  }

  void requestCheckout() {
    state = NavigationRequest.checkout;
  }

  void requestProjectSwitch() {
    state = NavigationRequest.projectSwitch;
  }

  void clearRequest() {
    state = null;
  }
}

enum NavigationRequest {
  submissionForm,
  checkout,
  projectSwitch,
}
