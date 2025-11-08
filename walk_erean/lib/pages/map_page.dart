// MapPage.dart
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

class MapPage extends StatefulWidget {
  const MapPage({super.key});

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  String? deviceId;
  Position? myPosition;
  List<_NearbyUser> nearby = [];
  bool loading = true;

  // settings
  final double maxShowDistanceKm = 5.0; // ৫ কিমি এর মধ্যে যাকে দেখাবে
  final double avatarRadius = 28;

  @override
  void initState() {
    super.initState();
    _initEverything();
  }

  Future<void> _initEverything() async {
    await _ensureDeviceId();
    await _getAndSaveLocation();
    await _loadNearbyUsers();
    setState(() => loading = false);
  }

  Future<void> _ensureDeviceId() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? id = prefs.getString('deviceId');
    if (id == null) {
      id = const Uuid().v4();
      await prefs.setString('deviceId', id);
    }
    deviceId = id;
  }

  Future<void> _getAndSaveLocation() async {
    try {
      Position pos = await _getCurrentLocation();
      myPosition = pos;

      // Save to Firestore (merge to not overwrite other fields)
      await FirebaseFirestore.instance.collection('users').doc(deviceId).set({
        'lat': pos.latitude,
        'lon': pos.longitude,
        'lastUpdated': DateTime.now().toUtc(),
        // demo photo (change if you want)
        'photo': 'https://i.pravatar.cc/150?u=$deviceId',
        'name': 'Guest', // optional
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Location error: $e');
    }
  }

  Future<Position> _getCurrentLocation() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw Exception('Location services are disabled.');
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        throw Exception('Location permission denied.');
      }
    }

    return await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.best,
    );
  }

  double _haversineDistanceKm(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const p = 0.017453292519943295;
    final a =
        0.5 -
        cos((lat2 - lat1) * p) / 2 +
        cos(lat1 * p) * cos(lat2 * p) * (1 - cos((lon2 - lon1) * p)) / 2;
    return 12742 * asin(sqrt(a));
  }

  // bearing from me to other (radians)
  double _bearingRad(double lat1, double lon1, double lat2, double lon2) {
    final phi1 = lat1 * pi / 180;
    final phi2 = lat2 * pi / 180;
    final dLon = (lon2 - lon1) * pi / 180;
    final y = sin(dLon) * cos(phi2);
    final x = cos(phi1) * sin(phi2) - sin(phi1) * cos(phi2) * cos(dLon);
    return atan2(y, x); // radians
  }

  Future<void> _loadNearbyUsers() async {
    if (myPosition == null) return;
    final snapshot = await FirebaseFirestore.instance.collection('users').get();

    final List<_NearbyUser> temp = [];

    for (var doc in snapshot.docs) {
      if (doc.id == deviceId) continue; // নিজের ডেটা বাদ
      if (!doc.data().containsKey('lat') || !doc.data().containsKey('lon'))
        continue;

      final double lat = (doc['lat'] as num).toDouble();
      final double lon = (doc['lon'] as num).toDouble();
      final double dist = _haversineDistanceKm(
        myPosition!.latitude,
        myPosition!.longitude,
        lat,
        lon,
      );

      if (dist <= maxShowDistanceKm) {
        final bearing = _bearingRad(
          myPosition!.latitude,
          myPosition!.longitude,
          lat,
          lon,
        );
        temp.add(
          _NearbyUser(
            id: doc.id,
            lat: lat,
            lon: lon,
            distanceKm: dist,
            bearingRad: bearing,
            photo: doc.data().containsKey('photo')
                ? doc['photo'] as String
                : 'https://i.pravatar.cc/150?u=${doc.id}',
            name: doc.data().containsKey('name')
                ? doc['name'] as String
                : 'Guest',
          ),
        );
      }
    }

    // sort by distance (closest first)
    temp.sort((a, b) => a.distanceKm.compareTo(b.distanceKm));
    setState(() => nearby = temp);
  }

  // map distance (0..maxShowDistanceKm) to pixel radius (0..maxRadiusPx)
  Offset _computeOffset(
    double bearingRad,
    double distanceKm,
    double maxRadiusPx,
  ) {
    final ratio = (distanceKm / maxShowDistanceKm).clamp(0.0, 1.0);
    final r = ratio * maxRadiusPx;
    final dx = r * cos(bearingRad);
    final dy = r * sin(bearingRad);
    // Note: bearingRad uses atan2(y,x) where +x is east, +y is north; screen y increases downward,
    // so invert dy to put north as up: use -dy.
    return Offset(dx, -dy);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.green[50],
      appBar: AppBar(
        backgroundColor: Colors.green,
        title: const Text(
          'Nearby Users',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        elevation: 0,
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final centerX = constraints.maxWidth / 2;
          // reserve some top space (appBar), so use maxHeight directly because LayoutBuilder gives available height
          final centerY = constraints.maxHeight / 2;
          final maxRadius =
              (min(constraints.maxWidth, constraints.maxHeight) / 2) - 80;

          return Stack(
            children: [
              // background/map style
              Positioned.fill(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      color: Colors.white,
                      child: CustomPaint(painter: _BackgroundPainter()),
                    ),
                  ),
                ),
              ),

              // center marker (you)
              Positioned(
                left: centerX - 36,
                top: centerY - 36,
                child: Column(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.green[100],
                        shape: BoxShape.circle,
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black12,
                            blurRadius: 6,
                            offset: Offset(2, 2),
                          ),
                        ],
                      ),
                      child: const Padding(
                        padding: EdgeInsets.all(8.0),
                        child: Icon(
                          Icons.my_location,
                          size: 40,
                          color: Colors.green,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'You',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),

              // nearby avatars positioned using bearing+distance
              if (loading) const Center(child: CircularProgressIndicator()),
              if (!loading)
                for (var u in nearby)
                  Positioned(
                    left:
                        (centerX +
                            _computeOffset(
                              u.bearingRad,
                              u.distanceKm,
                              maxRadius,
                            ).dx) -
                        avatarRadius,
                    top:
                        (centerY +
                            _computeOffset(
                              u.bearingRad,
                              u.distanceKm,
                              maxRadius,
                            ).dy) -
                        avatarRadius,
                    child: GestureDetector(
                      onTap: () => _showUserBottomSheet(u),
                      child: Column(
                        children: [
                          Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                              boxShadow: const [
                                BoxShadow(
                                  color: Colors.black12,
                                  blurRadius: 6,
                                  offset: Offset(2, 2),
                                ),
                              ],
                            ),
                            child: CircleAvatar(
                              radius: avatarRadius,
                              backgroundColor: Colors.white,
                              child: CircleAvatar(
                                radius: avatarRadius - 3,
                                backgroundImage: NetworkImage(u.photo),
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.green,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '${u.distanceKm.toStringAsFixed(1)} km',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

              // refresh floating action
              Positioned(
                right: 14,
                bottom: 18,
                child: FloatingActionButton.extended(
                  onPressed: () async {
                    setState(() => loading = true);
                    await _getAndSaveLocation();
                    await _loadNearbyUsers();
                    setState(() => loading = false);
                  },
                  icon: const Icon(Icons.refresh),
                  label: const Text('Refresh'),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showUserBottomSheet(_NearbyUser u) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 30,
                    backgroundImage: NetworkImage(u.photo),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        u.name ?? 'Guest',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${u.distanceKm.toStringAsFixed(2)} km away',
                        style: const TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        // chat logic বা profile open লিংক প্লাগ করো এখানে
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Chat (add logic)')),
                        );
                      },
                      icon: const Icon(Icons.chat_bubble_outline),
                      label: const Text('Message'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      // directions logic
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Open directions (add logic)'),
                        ),
                      );
                    },
                    icon: const Icon(Icons.directions),
                    label: const Text('Go'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }
}

class _NearbyUser {
  final String id;
  final double lat;
  final double lon;
  final double distanceKm;
  final double bearingRad;
  final String photo;
  final String? name;

  _NearbyUser({
    required this.id,
    required this.lat,
    required this.lon,
    required this.distanceKm,
    required this.bearingRad,
    required this.photo,
    this.name,
  });
}

class _BackgroundPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.green.withOpacity(0.03);
    final center = Offset(size.width / 2, size.height / 2);
    for (int i = 1; i <= 4; i++) {
      canvas.drawCircle(center, (size.shortestSide / 6) * i, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
