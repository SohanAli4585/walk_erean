import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';

// তোমার পেজগুলো (পথ ঠিক আছে কিনা চেক করো)
import 'pages/auth_page.dart';
import 'pages/home_page.dart';
import 'pages/map_page.dart';
import 'pages/chat_page.dart';
import 'pages/marketplace_page.dart';

// -------------------
// FCM background handler (top-level)
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  // এখানে background এ notification handle করতে পারবে
  // print('Handling a background message: ${message.messageId}');
}

// navigator key (নোটিফিকেশন থেকে নেভিগেট করার জন্য)
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Firebase initialize
  await Firebase.initializeApp(
    // যদি FlutterFire CLI ব্যবহার করে থাকো তবে options: DefaultFirebaseOptions.currentPlatform
  );

  // register background handler
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  // Hive initialize and open boxes
  // (optional: getApplicationDocumentsDirectory used by hive init in some setups)
  final appDocDir = await getApplicationDocumentsDirectory();
  await Hive.initFlutter(appDocDir.path);

  // উদাহরণ হিসেবে দুটি box খুললাম — প্রয়োজনমত নাম পরিবর্তন করো
  await Hive.openBox('statsBox');
  await Hive.openBox('settingsBox');

  runApp(const WalkAndEarnApp());
}

class WalkAndEarnApp extends StatelessWidget {
  const WalkAndEarnApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'Walk & Earn',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(primarySwatch: Colors.green),
      home: const AuthWrapper(),
    );
  }
}

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({Key? key}) : super(key: key);

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  @override
  void initState() {
    super.initState();
    _setupFCMAndSaveToken();
  }

  Future<void> _setupFCMAndSaveToken() async {
    try {
      final fcm = FirebaseMessaging.instance;

      // Request permission (iOS)
      await fcm.requestPermission(
        alert: true,
        badge: true,
        provisional: false,
        sound: true,
      );
      // print('User granted permission: ${settings.authorizationStatus}');

      // get token
      final token = await fcm.getToken();
      // print('FCM token: $token');

      // save token if user logged in
      final user = _auth.currentUser;
      if (token != null && user != null) {
        final userRef = FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid);
        await userRef.set({
          'fcmTokens': FieldValue.arrayUnion([token]),
          'displayName': user.displayName ?? '',
          'lastSeen': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }

      // foreground message handling
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        final notification = message.notification;
        if (notification != null && navigatorKey.currentState != null) {
          final ctx = navigatorKey.currentState!.overlay!.context;
          ScaffoldMessenger.of(ctx).showSnackBar(
            SnackBar(
              content: Text(notification.body ?? 'New message'),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      });

      // when user taps notification to open app
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        final data = message.data;
        final groupId = data['groupId'] as String?;
        if (groupId != null && navigatorKey.currentState != null) {
          navigatorKey.currentState!.push(
            MaterialPageRoute(
              builder: (_) => ChatPage(), // যদি চান সরাসরি ChatRoomPage খুলবে
            ),
          );
        }
      });
    } catch (e) {
      // print('FCM setup error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: _auth.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasData) return const MainAppPage();
        return AuthPage();
      },
    );
  }
}

class MainAppPage extends StatefulWidget {
  const MainAppPage({Key? key}) : super(key: key);

  @override
  State<MainAppPage> createState() => _MainAppPageState();
}

class _MainAppPageState extends State<MainAppPage> {
  int _selectedIndex = 0;

  final List<Widget> _pages = [
    const HomePage(),
    const MapPage(),
    const ChatPage(),
    MarketplacePage(),
  ];

  void _onItemTapped(int index) {
    setState(() => _selectedIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(child: _pages[_selectedIndex]),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        selectedItemColor: Colors.green[700],
        unselectedItemColor: Colors.grey,
        onTap: _onItemTapped,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.map), label: 'Map'),
          BottomNavigationBarItem(icon: Icon(Icons.chat), label: 'Chat'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Market'),
        ],
      ),
    );
  }
}
