import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class MarketplacePage extends StatefulWidget {
  const MarketplacePage({super.key});

  @override
  State<MarketplacePage> createState() => _MarketplacePageState();
}

class _MarketplacePageState extends State<MarketplacePage> {
  int userPoints = 0;

  final List<Map<String, dynamic>> items = [
    {
      'name': 'Badge',
      'pts': 200,
      'img': 'https://cdn-icons-png.flaticon.com/512/616/616408.png',
    },
    {
      'name': 'Gift Card',
      'pts': 750,
      'img': 'https://cdn-icons-png.flaticon.com/512/833/833472.png',
    },
    {
      'name': 'Sneakers',
      'pts': 1200,
      'img': 'https://cdn-icons-png.flaticon.com/512/892/892458.png',
    },
  ];

  @override
  void initState() {
    super.initState();
    _loadUserPoints();
  }

  /// Firestore থেকে রিয়েলটাইমে পয়েন্ট আনা
  void _loadUserPoints() {
    FirebaseFirestore.instance
        .collection('users')
        .doc(FirebaseAuth.instance.currentUser!.uid)
        .snapshots()
        .listen((doc) {
          if (doc.exists) {
            setState(() {
              userPoints = (doc['points'] ?? 0) as int;
            });
          }
        });
  }

  /// পণ্য কেনা এবং পয়েন্ট কমানো
  void _buyProduct(int cost, String productName) async {
    if (userPoints >= cost) {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(FirebaseAuth.instance.currentUser!.uid)
          .update({'points': userPoints - cost});

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '$productName purchased! Remaining points: ${userPoints - cost}',
          ),
          backgroundColor: Colors.green,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Not enough points!'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Marketplace (Points: $userPoints)'),
        centerTitle: true,
        backgroundColor: Colors.green,
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: items.length,
        itemBuilder: (context, index) {
          final item = items[index];
          final cost = item['pts'] as int;
          final imgUrl = item['img'] as String;
          final name = item['name'] as String;

          return Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            elevation: 6,
            margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
            shadowColor: Colors.green.withOpacity(0.4),
            child: ListTile(
              leading: Image.network(
                imgUrl,
                width: 60,
                height: 60,
                fit: BoxFit.cover,
              ),
              title: Text(
                name,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
              subtitle: Text(
                '$cost pts',
                style: const TextStyle(color: Colors.green),
              ),
              trailing: ElevatedButton(
                onPressed: () {
                  _buyProduct(cost, name);
                },
                child: const Text('Buy'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 10,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
