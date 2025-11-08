import 'package:flutter/material.dart';

class ProductDetailPage extends StatelessWidget {
  final String productName; // এখানে product name হিসেবে ব্যবহার করছি
  final double km; // প্রোডাক্টে দরকার নাই, ০ দাও
  final int points; // দাম
  final VoidCallback onPurchase;

  const ProductDetailPage({
    super.key,
    required this.productName,
    required this.km,
    required this.points,
    required this.onPurchase,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Buy $productName'),
        backgroundColor: Colors.green,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Text(
              productName,
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            Text(
              'Price: $points points',
              style: const TextStyle(fontSize: 20, color: Colors.green),
            ),
            const Spacer(),
            ElevatedButton(
              onPressed: () {
                onPurchase();
                Navigator.pop(context);
              },
              child: const Text('Confirm Purchase'),
            ),
          ],
        ),
      ),
    );
  }
}
