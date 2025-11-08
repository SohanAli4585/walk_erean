import 'package:flutter/material.dart';

class DetailPage extends StatelessWidget {
  final String day;
  final double km;
  final int points;

  const DetailPage({
    Key? key,
    required this.day,
    required this.km,
    required this.points,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Details for $day'),
        centerTitle: true,
        backgroundColor: Colors.deepPurple,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Day: $day', style: const TextStyle(fontSize: 20)),
            const SizedBox(height: 12),
            Text(
              'Distance walked: ${km.toStringAsFixed(2)} km',
              style: const TextStyle(fontSize: 18),
            ),
            const SizedBox(height: 12),
            Text(
              'Points earned: $points pts',
              style: const TextStyle(fontSize: 18),
            ),
          ],
        ),
      ),
    );
  }
}
