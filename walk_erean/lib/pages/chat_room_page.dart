// lib/pages/chat_room_page.dart

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

// Import the invite page (ফাইল পাথ অনুযায়ী পরিবর্তন করো)
import 'invite_friends_page.dart';

class ChatRoomPage extends StatefulWidget {
  final String groupId;
  final String groupName;

  const ChatRoomPage({Key? key, required this.groupId, required this.groupName})
    : super(key: key);

  @override
  State<ChatRoomPage> createState() => _ChatRoomPageState();
}

class _ChatRoomPageState extends State<ChatRoomPage> {
  final FirebaseFirestore _fs = FirebaseFirestore.instance;
  final TextEditingController _msgController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  // pagination state
  List<QueryDocumentSnapshot> _docs = [];
  bool _hasMore = true;
  bool _loading = false;
  static const int pageSize = 20;

  String get _currentUid => FirebaseAuth.instance.currentUser?.uid ?? '';
  String get _currentUserName =>
      FirebaseAuth.instance.currentUser?.displayName ?? 'You';

  CollectionReference get _messagesCollection =>
      _fs.collection('groups').doc(widget.groupId).collection('messages');

  // For showing current group data (members count etc)
  late final DocumentReference _groupRef;
  Map<String, dynamic>? _groupData;
  StreamSubscription<DocumentSnapshot>? _groupSub;

  @override
  void initState() {
    super.initState();
    _groupRef = _fs.collection('groups').doc(widget.groupId);
    _listenGroup(); // listen for members / lastMessage updates
    _loadInitial();
    _scrollController.addListener(_onScroll);
  }

  void _listenGroup() {
    _groupSub = _groupRef.snapshots().listen(
      (snap) {
        if (!mounted) return;
        setState(() {
          _groupData = snap.data() as Map<String, dynamic>?;
        });
      },
      onError: (e) {
        // optional: handle permission errors etc
        // print('Group listen error: $e');
      },
    );
  }

  @override
  void dispose() {
    _groupSub?.cancel();
    _scrollController.dispose();
    _msgController.dispose();
    super.dispose();
  }

  Future<void> _loadInitial() async {
    if (_loading) return;
    _loading = true;
    try {
      final q = await _messagesCollection
          .orderBy('time', descending: true)
          .limit(pageSize)
          .get();
      _docs = q.docs;
      if (q.docs.length < pageSize) _hasMore = false;
      setState(() {});
      // keep scroll at bottom (latest messages shown at bottom)
      await Future.delayed(const Duration(milliseconds: 100));
      _scrollToBottom();
    } catch (e) {
      // handle read permission or other errors
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Load error: $e')));
    } finally {
      _loading = false;
    }
  }

  Future<void> _loadMore() async {
    if (!_hasMore || _loading) return;
    _loading = true;
    try {
      final lastDoc = _docs.isNotEmpty ? _docs.last : null;
      if (lastDoc == null) return;
      final q = await _messagesCollection
          .orderBy('time', descending: true)
          .startAfterDocument(lastDoc)
          .limit(pageSize)
          .get();
      _docs.addAll(q.docs);
      if (q.docs.length < pageSize) _hasMore = false;
      setState(() {});
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Load more error: $e')));
    } finally {
      _loading = false;
    }
  }

  void _onScroll() {
    // when user scrolls near top, load more (because we show newest at bottom, list reversed)
    if (!_scrollController.hasClients) return;
    if (_scrollController.position.pixels <=
        _scrollController.position.minScrollExtent + 200) {
      _loadMore();
    }
  }

  Future<void> _sendMessage() async {
    final text = _msgController.text.trim();
    if (text.isEmpty) return;
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Not signed in')));
      return;
    }
    final msgData = {
      'senderName': _currentUserName,
      'senderId': currentUser.uid,
      'text': text,
      'time': FieldValue.serverTimestamp(),
      'edited': false,
      'deleted': false,
    };

    try {
      await _messagesCollection.add(msgData);
      _msgController.clear();

      // update group's last message
      await _groupRef.update({
        'lastMessage': text,
        'lastMessageTime': FieldValue.serverTimestamp(),
      });

      // scroll to bottom after send
      await Future.delayed(const Duration(milliseconds: 200));
      _scrollToBottom();
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Send error: $e')));
    }
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent + 100,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  void _showMessageOptions(QueryDocumentSnapshot doc) {
    final m = doc.data() as Map<String, dynamic>;
    final isMy = (m['senderId'] ?? '') == _currentUid;
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isMy)
              ListTile(
                leading: const Icon(Icons.edit),
                title: const Text('Edit'),
                onTap: () {
                  Navigator.pop(context);
                  _showEditDialog(doc);
                },
              ),
            if (isMy)
              ListTile(
                leading: const Icon(Icons.delete),
                title: const Text('Delete'),
                onTap: () {
                  Navigator.pop(context);
                  _deleteMessage(doc);
                },
              ),
            ListTile(
              leading: const Icon(Icons.cancel),
              title: const Text('Cancel'),
              onTap: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showEditDialog(QueryDocumentSnapshot doc) async {
    final m = doc.data() as Map<String, dynamic>;
    final ctrl = TextEditingController(text: m['text'] ?? '');
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Edit message'),
        content: TextField(controller: ctrl),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final newText = ctrl.text.trim();
              if (newText.isEmpty) return;
              try {
                await doc.reference.update({
                  'text': newText,
                  'edited': true,
                  'editedAt': FieldValue.serverTimestamp(),
                });

                // If this message was the group's lastMessage, update group's lastMessage too.
                final groupSnap = await _groupRef.get();
                final data = groupSnap.data() as Map<String, dynamic>?;
                if (data != null && data['lastMessage'] == (m['text'] ?? '')) {
                  await _groupRef.update({
                    'lastMessage': newText,
                    'lastMessageTime': FieldValue.serverTimestamp(),
                  });
                }
              } catch (e) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text('Edit error: $e')));
              }
              Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteMessage(QueryDocumentSnapshot doc) async {
    final m = doc.data() as Map<String, dynamic>;
    try {
      // Soft delete: mark deleted = true and replace text
      await doc.reference.update({
        'deleted': true,
        'text': 'Message deleted',
        'edited': false,
        'editedAt': FieldValue.serverTimestamp(),
      });

      // If it was lastMessage, update group's lastMessage to previous message
      final groupSnap = await _groupRef.get();
      final data = groupSnap.data() as Map<String, dynamic>?;
      if (data != null && data['lastMessage'] == (m['text'] ?? '')) {
        // find latest non-deleted message
        final q = await _messagesCollection
            .where('deleted', isEqualTo: false)
            .orderBy('time', descending: true)
            .limit(1)
            .get();
        if (q.docs.isNotEmpty) {
          final latest = q.docs.first.data() as Map<String, dynamic>;
          await _groupRef.update({
            'lastMessage': latest['text'] ?? '',
            'lastMessageTime': latest['time'] ?? FieldValue.serverTimestamp(),
          });
        } else {
          await _groupRef.update({
            'lastMessage': 'No messages',
            'lastMessageTime': FieldValue.serverTimestamp(),
          });
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Delete error: $e')));
    }
  }

  Widget _buildMessageBubble(QueryDocumentSnapshot doc) {
    final m = doc.data() as Map<String, dynamic>;
    final bool isMe = (m['senderId'] ?? '') == _currentUid;
    final timeStamp = m['time'] as Timestamp?;
    final timeStr = timeStamp != null
        ? TimeOfDay.fromDateTime(timeStamp.toDate()).format(context)
        : '';
    final deleted = m['deleted'] ?? false;
    return GestureDetector(
      onLongPress: () => _showMessageOptions(doc),
      child: Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.all(10),
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.75,
          ),
          decoration: BoxDecoration(
            color: isMe ? Colors.green[100] : Colors.grey[200],
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                m['senderName'] ?? '',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 6),
              Text(deleted ? 'Message deleted' : (m['text'] ?? '')),
              const SizedBox(height: 6),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if ((m['edited'] ?? false) && !deleted)
                    const Text(
                      'edited',
                      style: TextStyle(fontSize: 10, color: Colors.black45),
                    ),
                  if ((m['edited'] ?? false) && !deleted)
                    const SizedBox(width: 6),
                  Text(
                    timeStr,
                    style: const TextStyle(fontSize: 10, color: Colors.black54),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Helper to open invite page
  void _openInvitePage() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => InviteFriendsPage(groupId: widget.groupId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final displayDocs = _docs.reversed.toList();
    final members = (_groupData != null && _groupData!['members'] != null)
        ? List.from(_groupData!['members'])
        : <dynamic>[];

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.groupName),
            const SizedBox(height: 2),
            Text(
              '${members.length} members',
              style: const TextStyle(fontSize: 12, color: Colors.white70),
            ),
          ],
        ),
        backgroundColor: Colors.green,
        actions: [
          IconButton(
            tooltip: 'Invite friends',
            icon: const Icon(Icons.person_add),
            onPressed: _openInvitePage,
          ),
          // optional: group info button
          IconButton(
            tooltip: 'Group info',
            icon: const Icon(Icons.info_outline),
            onPressed: () async {
              // show simple group info dialog
              showDialog(
                context: context,
                builder: (_) => AlertDialog(
                  title: Text(widget.groupName),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Members: ${members.length}'),
                      const SizedBox(height: 8),
                      if (_groupData != null &&
                          _groupData!['createdBy'] != null)
                        Text('Created by: ${_groupData!['createdBy']}'),
                    ],
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Close'),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _docs.isEmpty
                ? const Center(
                    child: Text('No messages. Start the conversation.'),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(
                      vertical: 8,
                      horizontal: 12,
                    ),
                    itemCount:
                        displayDocs.length + 1, // +1 for "load more" or spacer
                    itemBuilder: (context, index) {
                      if (index == 0) {
                        // top widget: load more indicator
                        return _hasMore
                            ? Center(
                                child: TextButton(
                                  onPressed: _loadMore,
                                  child: _loading
                                      ? const CircularProgressIndicator()
                                      : const Text('Load more'),
                                ),
                              )
                            : const SizedBox.shrink();
                      }
                      final doc = displayDocs[index - 1];
                      return _buildMessageBubble(doc);
                    },
                  ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _msgController,
                    decoration: const InputDecoration(
                      hintText: 'Write a message...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(8)),
                      ),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                CircleAvatar(
                  backgroundColor: Colors.green,
                  child: IconButton(
                    icon: const Icon(Icons.send, color: Colors.white),
                    onPressed: _sendMessage,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
