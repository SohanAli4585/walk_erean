import 'package:flutter/material.dart';
import 'package:pedometer/pedometer.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'weekly_stats_page.dart'; // WeeklyStatsPage এখানে ইম্পোর্ট করো

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int steps = 0;
  double distance = 0.0;
  int points = 0;

  int? initialSteps;
  String todayInfo = '';

  Stream<StepCount>? _stepCountStream;
  StreamSubscription<StepCount>? _stepSubscription;

  bool isTracking = false;

  void startTracking() {
    _stepCountStream = Pedometer.stepCountStream;
    _stepSubscription = _stepCountStream!.listen(_onStepCount);
    setState(() {
      isTracking = true;
      steps = 0;
      distance = 0.0;
      points = 0;
      initialSteps = null;
    });
  }

  void stopTracking() {
    _stepSubscription?.cancel();
    _stepSubscription = null;
    setState(() {
      isTracking = false;
    });
  }

  void _onStepCount(StepCount event) {
    setState(() {
      if (initialSteps == null) {
        initialSteps = event.steps;
      }
      steps = event.steps - initialSteps!;
      if (steps < 0) steps = 0;

      distance = steps * 0.000625;
      points = (distance * 1000).toInt();
    });
  }

  Future<void> saveData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('User not logged in!')));
      return;
    }

    final uid = user.uid;
    final today = DateTime.now();
    final dayName = DateFormat('EEEE').format(today);
    final todayDateStr = DateFormat('yyyy-MM-dd').format(today);

    final todayKm = double.parse(distance.toStringAsFixed(2));
    final todayPoints = points;

    try {
      final collRef = FirebaseFirestore.instance.collection('weekly_stats');

      // আজকের ডেটা আপডেট বা নতুন ডকুমেন্ট যোগ করা
      final query = await collRef
          .where('uid', isEqualTo: uid)
          .where('date', isEqualTo: todayDateStr)
          .limit(1)
          .get();

      if (query.docs.isNotEmpty) {
        final docId = query.docs.first.id;
        final data = query.docs.first.data();

        final prevKm = (data['km'] ?? 0).toDouble();
        final prevPoints = (data['points'] ?? 0).toInt();

        // Update current km and points (যোগ হবে)
        await collRef.doc(docId).update({
          'km': double.parse((prevKm + todayKm).toStringAsFixed(2)),
          'points': prevPoints + todayPoints,
          'timestamp': Timestamp.fromDate(today),
        });
      } else {
        // নতুন ডকুমেন্ট
        await collRef.add({
          'uid': uid,
          'day': dayName,
          'date': todayDateStr,
          'km': todayKm,
          'points': todayPoints,
          'timestamp': Timestamp.fromDate(today),
        });
      }

      // users কালেকশনে points আপডেট (মোট পয়েন্ট বাড়ানো)
      final userRef = FirebaseFirestore.instance.collection('users').doc(uid);
      await userRef.set({
        'points': FieldValue.increment(todayPoints),
      }, SetOptions(merge: true));

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Saved: $dayName — ${todayKm.toStringAsFixed(2)} km, $todayPoints points',
          ),
        ),
      );

      setState(() {
        todayInfo =
            'Today\'s data: ${todayKm.toStringAsFixed(2)} km, $todayPoints points';
      });
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to save: $e')));
    }
  }

  @override
  void dispose() {
    _stepSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("WALK & EARN"),
        centerTitle: true,
        backgroundColor: Colors.blue,
        elevation: 0,
      ),
      body: Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 180,
                height: 180,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.green, width: 8),
                ),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '$steps',
                        style: const TextStyle(
                          fontSize: 36,
                          fontWeight: FontWeight.bold,
                          color: Colors.black,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${distance.toStringAsFixed(2)} km',
                        style: const TextStyle(
                          fontSize: 18,
                          color: Colors.black54,
                        ),
                      ),
                      Text(
                        '$points points',
                        style: const TextStyle(
                          fontSize: 18,
                          color: Colors.deepPurple,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 40),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton(
                    onPressed: isTracking ? null : startTracking,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 30,
                        vertical: 14,
                      ),
                    ),
                    child: const Text(
                      'START',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 20),
                  ElevatedButton(
                    onPressed: isTracking ? stopTracking : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 30,
                        vertical: 14,
                      ),
                    ),
                    child: const Text(
                      'STOP',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: saveData,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 60,
                    vertical: 14,
                  ),
                ),
                child: const Text(
                  'SAVE',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const WeeklyStatsPage(),
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 50,
                    vertical: 14,
                  ),
                ),
                child: const Text(
                  'SHOW WEEKLY STATS',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(height: 16),
              if (todayInfo.isNotEmpty)
                Text(
                  todayInfo,
                  style: const TextStyle(
                    fontSize: 16,
                    color: Colors.black87,
                    fontWeight: FontWeight.w500,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
