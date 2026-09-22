class BeaconContent {
  final String id, merchant, title, description;
  final DateTime? expires;
  const BeaconContent(
    this.id,
    this.merchant,
    this.title,
    this.description, {
    this.expires,
  });
}

abstract interface class ContentRepository {
  Future<BeaconContent?> find(String beaconId);
}

class LocalContentRepository implements ContentRepository {
  @override
  Future<BeaconContent?> find(String beaconId) async => beaconId == 'wookiemeat'
      ? const BeaconContent(
          'wookiemeat',
          'Acoustic Beacon Test',
          'Beacon Detected',
          'Your phone successfully decoded the Acoustic Beacon test transmission.',
        )
      : null;
}

class BeaconLocation {
  final String name, category;
  final double latitude, longitude;
  const BeaconLocation(this.name, this.category, this.latitude, this.longitude);
}

abstract interface class LocationRepository {
  Future<List<BeaconLocation>> nearby(double latitude, double longitude);
}

class LocalLocationRepository implements LocationRepository {
  @override
  Future<List<BeaconLocation>> nearby(
    double latitude,
    double longitude,
  ) async => [];
}
