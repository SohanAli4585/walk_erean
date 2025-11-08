import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'chat_room_page.dart';

class ChatPage extends StatefulWidget {
  const ChatPage({Key? key}) : super(key: key);

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final FirebaseFirestore _fs = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Create group dialog
  void _showCreateGroupDialog() {
    final TextEditingController _controller = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Create Group'),
        content: TextField(
          controller: _controller,
          decoration: const InputDecoration(hintText: 'Enter group name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final name = _controller.text.trim();
              if (name.isEmpty) return;
              Navigator.pop(context);

              try {
                final currentUid = _auth.currentUser?.uid;
                // Create group doc with members (include current user)
                final docRef = await _fs.collection('groups').add({
                  'name': name,
                  'image':
                      'https://i.pravatar.cc/150?img=${DateTime.now().millisecondsSinceEpoch % 70}',
                  'createdAt': FieldValue.serverTimestamp(),
                  'lastMessage': 'Group created',
                  'lastMessageTime': FieldValue.serverTimestamp(),
                  'members': currentUid != null ? [currentUid] : [],
                  'createdBy': currentUid ?? '',
                });

                // Add initial system message in subcollection
                await docRef.collection('messages').add({
                  'senderName': 'System',
                  'senderId': 'system',
                  'text': 'Group "$name" created',
                  'time': FieldValue.serverTimestamp(),
                });

                // Open chat room
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        ChatRoomPage(groupId: docRef.id, groupName: name),
                  ),
                );
              } catch (e) {
                // simple error handling
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Error creating group: $e')),
                );
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  // Optionally allow current user to join group (if not already a member)
  Future<void> _joinGroupIfNeeded(
    String groupId,
    List<dynamic>? members,
  ) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    if (members == null || !members.contains(uid)) {
      await _fs.collection('groups').doc(groupId).update({
        'members': FieldValue.arrayUnion([uid]),
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Groups'),
        centerTitle: true,
        backgroundColor: Colors.green,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _fs
            .collection('groups')
            .orderBy('lastMessageTime', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError)
            return const Center(child: Text('Error loading groups'));
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final docs = snapshot.data!.docs;
          if (docs.isEmpty)
            return const Center(
              child: Text("No groups yet. Create one with +"),
            );

          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const Divider(),
            itemBuilder: (context, index) {
              final d = docs[index];
              final data = d.data() as Map<String, dynamic>;
              final lastMsg = data['lastMessage'] ?? 'No messages yet';
              final lastTime = data['lastMessageTime'] as Timestamp?;
              final members = data['members'] as List<dynamic>? ?? [];
              String subtitle = lastMsg;
              if (lastTime != null) {
                final dt = lastTime.toDate();
                final timeStr = TimeOfDay.fromDateTime(dt).format(context);
                subtitle = '$timeStr · $lastMsg';
              }

              return ListTile(
                leading: CircleAvatar(
                  backgroundImage: NetworkImage(
                    data['image'] ?? 'https://i.pravatar.cc/150',
                  ),
                ),
                title: Text(data['name'] ?? 'Unnamed'),
                subtitle: Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                // Show member count under subtitle (small badge)
                trailing: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.arrow_forward_ios, size: 16),
                    const SizedBox(height: 4),
                    Text(
                      '${members.length} members',
                      style: const TextStyle(fontSize: 11),
                    ),
                  ],
                ),
                onTap: () async {
                  // Ensure current user is member (so they receive notifications etc)
                  await _joinGroupIfNeeded(d.id, members);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ChatRoomPage(
                        groupId: d.id,
                        groupName: data['name'] ?? '',
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showCreateGroupDialog,
        child: const Icon(Icons.add),
        backgroundColor: Colors.green,
      ),
    );
  }
}
