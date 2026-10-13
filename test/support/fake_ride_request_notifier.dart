import 'package:driver/services/ride_request_notifier.dart';

class FakeRideRequestNotifier implements RideRequestNotifier {
  final List<String> notified = [];
  int cancelAllCalls = 0;

  @override
  Future<void> notifyRideRequest(String eventId) async => notified.add(eventId);

  @override
  Future<void> cancelAll() async => cancelAllCalls++;
}
