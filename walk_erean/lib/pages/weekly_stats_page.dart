import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'marketplace_page.dart'; // মার্কেটপ্লেস পেজ ইম্পোর্ট করো
import 'detail_page.dart'; // ডিটেইল পেজ

class WeeklyStatsPage extends StatefulWidget {
  const WeeklyStatsPage({Key? key}) : super(key: key);

  @override
  State<WeeklyStatsPage> createState() => _WeeklyStatsPageState();
}

class _WeeklyStatsPageState extends State<WeeklyStatsPage> {
  final user = FirebaseAuth.instance.currentUser;
  late DateTime startOfWeek;
  late DateTime endOfWeek;

  double totalKm = 0;
  int totalPoints = 0;

  @override
  void initState() {
    super.initState();
    _calculateWeekRange();
  }

  void _calculateWeekRange() {
    final now = DateTime.now();

    startOfWeek = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(Duration(days: now.weekday - 1)); // সোমবার সকাল ১২:০০ AM
    endOfWeek = startOfWeek.add(
      const Duration(days: 6, hours: 23, minutes: 59, seconds: 59),
    ); // রবিবার রাত ১১:৫৯:৫৯ PM

    // যদি UTC টাইমজোনে ফিল্টার করতে চান, uncomment করুন:
    // startOfWeek = startOfWeek.toUtc();
    // endOfWeek = endOfWeek.toUtc();

    print('Start of week: $startOfWeek');
    print('End of week: $endOfWeek');
  }

  String dayName(String dateStr) {
    try {
      final dt = DateTime.parse(dateStr);
      return DateFormat('EEEE').format(dt);
    } catch (_) {
      return dateStr;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (user == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Weekly Stats')),
        body: const Center(child: Text('Please login first')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Weekly Stats'),
        centerTitle: true,
        backgroundColor: Colors.blue,
        actions: [
          IconButton(
            icon: const Icon(Icons.store),
            tooltip: 'Marketplace',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => MarketplacePage()),
              );
            },
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('weekly_stats')
            .where('uid', isEqualTo: user!.uid)
            .where(
              'timestamp',
              isGreaterThanOrEqualTo: Timestamp.fromDate(startOfWeek),
            )
            .where(
              'timestamp',
              isLessThanOrEqualTo: Timestamp.fromDate(endOfWeek),
            )
            .orderBy('timestamp', descending: false)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snapshot.data?.docs ?? [];

          // Debug prints
          print('Found docs: ${docs.length}');
          for (var doc in docs) {
            print(doc.data());
          }

          if (docs.isEmpty) {
            totalKm = 0;
            totalPoints = 0;
            return const Center(child: Text('No data found for this week.'));
          }

          totalKm = 0;
          totalPoints = 0;

          for (var doc in docs) {
            final data = doc.data() as Map<String, dynamic>;

            final kmRaw = data['km'] ?? 0;
            final km = (kmRaw is double)
                ? kmRaw
                : (kmRaw is int)
                ? kmRaw.toDouble()
                : 0.0;

            final pointsRaw = data['points'] ?? 0;
            final points = (pointsRaw is int)
                ? pointsRaw
                : (pointsRaw is double)
                ? pointsRaw.toInt()
                : 0;

            totalKm += km;
            totalPoints += points;
          }

          return Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                Card(
                  color: Colors.blue[50],
                  elevation: 3,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: 16,
                      horizontal: 24,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        Column(
                          children: [
                            const Text(
                              'Total Km',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                              ),
                            ),
                            Text(
                              totalKm.toStringAsFixed(2),
                              style: const TextStyle(fontSize: 22),
                            ),
                          ],
                        ),
                        Column(
                          children: [
                            const Text(
                              'Total Points',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                              ),
                            ),
                            Text(
                              '$totalPoints',
                              style: const TextStyle(fontSize: 22),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Expanded(
                  child: ListView.separated(
                    itemCount: docs.length,
                    separatorBuilder: (context, index) =>
                        const Divider(height: 1, color: Colors.grey),
                    itemBuilder: (context, index) {
                      final data = docs[index].data() as Map<String, dynamic>;
                      final day = data['day'] ?? dayName(data['date'] ?? '');

                      final kmRaw = data['km'] ?? 0;
                      final km = (kmRaw is double)
                          ? kmRaw
                          : (kmRaw is int)
                          ? kmRaw.toDouble()
                          : 0.0;

                      final pointsRaw = data['points'] ?? 0;
                      final points = (pointsRaw is int)
                          ? pointsRaw
                          : (pointsRaw is double)
                          ? pointsRaw.toInt()
                          : 0;

                      return ListTile(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) =>
                                  DetailPage(day: day, km: km, points: points),
                            ),
                          );
                        },
                        leading: CircleAvatar(
                          backgroundColor: Colors.blue,
                          child: Text(
                            day.substring(0, 1),
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                        title: Text(day),
                        subtitle: Text('${km.toStringAsFixed(2)} km'),
                        trailing: Text(
                          '$points pts',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.deepPurple,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
