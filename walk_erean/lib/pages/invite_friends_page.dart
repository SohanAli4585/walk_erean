import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class InviteFriendsPage extends StatelessWidget {
  final String groupId;
  InviteFriendsPage({required this.groupId});

  final FirebaseFirestore _fs = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  Future<void> _addMember(String uid) async {
    await _fs.collection('groups').doc(groupId).update({
      'members': FieldValue.arrayUnion([uid]),
    });
  }

  @override
  Widget build(BuildContext context) {
    final currentUid = _auth.currentUser?.uid;

    return Scaffold(
      appBar: AppBar(
        title: Text("Invite Friends"),
        backgroundColor: Colors.green,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _fs.collection('users').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError)
            return Center(child: Text("Error loading users"));
          if (!snapshot.hasData)
            return Center(child: CircularProgressIndicator());

          final users = snapshot.data!.docs;

          return ListView.builder(
            itemCount: users.length,
            itemBuilder: (context, index) {
              final data = users[index].data() as Map<String, dynamic>;
              final uid = users[index].id;

              // নিজেকে দেখাবে না
              if (uid == currentUid) return SizedBox.shrink();

              return ListTile(
                leading: CircleAvatar(
                  backgroundImage: NetworkImage(
                    data['photoUrl'] ?? 'https://i.pravatar.cc/150',
                  ),
                ),
                title: Text(data['name'] ?? 'Unknown'),
                subtitle: Text(data['email'] ?? ''),
                trailing: IconButton(
                  icon: Icon(Icons.person_add, color: Colors.green),
                  onPressed: () async {
                    await _addMember(uid);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text("${data['name']} added to group")),
                    );
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}
