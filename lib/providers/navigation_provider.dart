import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Provider to handle navigation requests from floating widget
final navigationRequestProvider = StateNotifierProvider<NavigationRequestNotifier, NavigationRequest?>((ref) {
  return NavigationRequestNotifier();
});

class NavigationRequestNotifier extends StateNotifier<NavigationRequest?> {
  NavigationRequestNotifier() : super(null);

  void requestSubmissionForm() {
    state = NavigationRequest.submissionForm;
  }

  void clearRequest() {
    state = null;
  }
}

enum NavigationRequest {
  submissionForm,
}
