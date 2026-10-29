import 'dart:async';
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import 'firebase_options.dart';

const background = Color(0xFF05051B);
const unreadNotificationCount = 6;

final ValueNotifier<Campaign?> activeCampaign = ValueNotifier<Campaign?>(null);
final ValueNotifier<LatLng?> userLocation = ValueNotifier<LatLng?>(null);
StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
  activeCampaignSubscription;

const fallbackLocation = LatLng(28.6139, 77.2090);

Future<void> loadUserLocation() async {
  if (!await Geolocator.isLocationServiceEnabled()) return;
  var permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
  }
  if (permission == LocationPermission.denied ||
      permission == LocationPermission.deniedForever) {
    return;
  }
  final position = await Geolocator.getCurrentPosition();
  userLocation.value = LatLng(position.latitude, position.longitude);
}

class Campaign {
  const Campaign({
    this.id,
    required this.shopName,
    required this.description,
    required this.radiusKm,
    required this.durationDays,
    required this.platforms,
    this.videoLength,
    this.budget,
    this.spent,
    this.totalPhones,
    this.activeDevices,
    this.androidPhones,
    this.iphonePhones,
    this.totalViews,
    this.reach,
    this.websiteClicks,
    this.shares,
  });

  factory Campaign.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data() ?? <String, dynamic>{};
    return Campaign(
      id: snapshot.id,
      shopName: data['shopName'] as String? ?? '',
      description: data['description'] as String? ?? '',
      radiusKm: (data['radiusKm'] as num?)?.toDouble() ?? 0,
      durationDays: (data['durationDays'] as num?)?.toInt() ?? 0,
      platforms: (data['platforms'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .toSet(),
      videoLength: data['videoLength'] as String?,
      budget: (data['budget'] as num?)?.toInt(),
      spent: (data['spent'] as num?)?.toInt(),
      totalPhones: (data['totalPhones'] as num?)?.toInt(),
      activeDevices: (data['activeDevices'] as num?)?.toInt(),
      androidPhones: (data['androidPhones'] as num?)?.toInt(),
      iphonePhones: (data['iphonePhones'] as num?)?.toInt(),
      totalViews: (data['totalViews'] as num?)?.toInt(),
      reach: (data['reach'] as num?)?.toInt(),
      websiteClicks: (data['websiteClicks'] as num?)?.toInt(),
      shares: (data['shares'] as num?)?.toInt(),
    );
  }

  Map<String, dynamic> toFirestore() => {
    'ownerId': FirebaseAuth.instance.currentUser!.uid,
    'shopName': shopName,
    'description': description,
    'radiusKm': radiusKm,
    'durationDays': durationDays,
    'platforms': platforms.toList(),
    'videoLength': videoLength,
    'budget': budget,
    'spent': spent,
    'totalPhones': totalPhones,
    'activeDevices': activeDevices,
    'androidPhones': androidPhones,
    'iphonePhones': iphonePhones,
    'totalViews': totalViews,
    'reach': reach,
    'websiteClicks': websiteClicks,
    'shares': shares,
    'status': 'active',
    'createdAt': FieldValue.serverTimestamp(),
  };

  final String? id;
  final String shopName;
  final String description;
  final double radiusKm;
  final int durationDays;
  final Set<String> platforms;
  final String? videoLength;
  final int? budget;
  final int? spent;
  final int? totalPhones;
  final int? activeDevices;
  final int? androidPhones;
  final int? iphonePhones;
  final int? totalViews;
  final int? reach;
  final int? websiteClicks;
  final int? shares;
}

String formatCount(int? value) => value == null
    ? '—'
    : value.toString().replaceAllMapped(
        RegExp(r'\B(?=(\d{3})+(?!\d))'),
        (match) => ',',
      );

String formatRadius(double radiusKm) => radiusKm == radiusKm.roundToDouble()
    ? '${radiusKm.toInt()} km'
    : '$radiusKm km';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  await FirebaseAuth.instance.signInAnonymously();
  await FirebaseMessaging.instance.requestPermission();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: background,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) =>
      const MaterialApp(debugShowCheckedModeBanner: false, home: SplashPage());
}

class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController animationController;
  late final Animation<double> fadeAnimation;
  late final Animation<double> scaleAnimation;
  Timer? dotsTimer;
  int activeDot = 0;

  @override
  void initState() {
    super.initState();
    animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    fadeAnimation = CurvedAnimation(
      parent: animationController,
      curve: Curves.easeOut,
    );
    scaleAnimation = Tween<double>(begin: 1.04, end: 1).animate(
      CurvedAnimation(parent: animationController, curve: Curves.easeOutCubic),
    );
    animationController.forward();
    var elapsedSeconds = 0;
    dotsTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      elapsedSeconds++;
      setState(() => activeDot = elapsedSeconds.clamp(0, 4));

      if (elapsedSeconds >= 5) {
        timer.cancel();
        _openTerms();
      }
    });
  }

  void _openTerms() {
    if (!mounted) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: .42),
      builder: (context) => const TermsSheet(),
    );
  }

  @override
  void dispose() {
    dotsTimer?.cancel();
    animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: background,
    body: FadeTransition(
      opacity: fadeAnimation,
      child: ScaleTransition(
        scale: scaleAnimation,
        child: LayoutBuilder(
          builder: (context, constraints) => Stack(
            fit: StackFit.expand,
            children: [
              Image.asset(
                'assets/illustration.png',
                fit: BoxFit.fill,
                alignment: Alignment.center,
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: constraints.maxHeight * .115,
                child: Center(child: Dots(activeDot: activeDot)),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class Dots extends StatelessWidget {
  const Dots({super.key, required this.activeDot});

  final int activeDot;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: List.generate(5, (index) {
      final isActive = index == activeDot;
      return AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        margin: const EdgeInsets.symmetric(horizontal: 5),
        width: isActive ? 22 : 13,
        height: isActive ? 22 : 13,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: isActive
              ? const LinearGradient(
                  colors: [Color(0xFF1CC7FF), Color(0xFFFF00C8)],
                )
              : null,
          color: isActive ? null : const Color(0xFF38228C),
        ),
      );
    }),
  );
}

class TermsSheet extends StatefulWidget {
  const TermsSheet({super.key});

  @override
  State<TermsSheet> createState() => _TermsSheetState();
}

class _TermsSheetState extends State<TermsSheet> {
  bool accepted = false;

  void continueToNextPage() {
    if (!accepted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder<void>(
        pageBuilder: (context, animation, secondaryAnimation) =>
            const NextPage(),
        transitionDuration: const Duration(milliseconds: 450),
        transitionsBuilder: (context, animation, secondaryAnimation, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => FractionallySizedBox(
    heightFactor: .68,
    child: Material(
      color: const Color(0xFFFCFDFF),
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.only(top: 14),
              width: 58,
              height: 6,
              decoration: BoxDecoration(
                color: const Color(0xFFDDE3EE),
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(22, 12, 22, 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Terms & Conditions',
                            style: TextStyle(
                              color: Color(0xFF102143),
                              fontSize: 28,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close, size: 29),
                          color: const Color(0xFF52688E),
                        ),
                      ],
                    ),
                    const Text(
                      'Please read and agree before\ncontinuing.',
                      style: TextStyle(color: Color(0xFF52688E), fontSize: 18),
                    ),
                    const SizedBox(height: 18),
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      decoration: BoxDecoration(
                        border: Border.all(color: const Color(0xFFE0E6F0)),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Column(
                        children: [
                          TermRow(
                            Icons.block,
                            Color(0xFFFFDCE6),
                            Color(0xFFD93062),
                            'Illegal, harmful, fraudulent or prohibited\nads are not allowed.',
                          ),
                          TermRow(
                            Icons.balance,
                            Color(0xFFE9DDFF),
                            Color(0xFF7139E7),
                            'You are responsible for your ad\nand its legality.',
                          ),
                          TermRow(
                            Icons.credit_card,
                            Color(0xFFD4F5E4),
                            Color(0xFF18A865),
                            'Once a campaign starts, the payment\nis non-refundable.',
                          ),
                          TermRow(
                            Icons.warning_rounded,
                            Color(0xFFFFE9BC),
                            Color(0xFFE49A16),
                            'Fake or misleading claims and offers\nare not allowed.',
                          ),
                          TermRow(
                            Icons.lock,
                            Color(0xFFDCEEFF),
                            Color(0xFF147BD1),
                            'Keep your account secure.\nMisuse may lead to suspension.',
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    InkWell(
                      onTap: () => setState(() => accepted = !accepted),
                      child: Row(
                        children: [
                          Icon(
                            accepted
                                ? Icons.check_box
                                : Icons.check_box_outline_blank,
                            color: accepted
                                ? const Color(0xFF6639E9)
                                : const Color(0xFF52688E),
                            size: 27,
                          ),
                          const SizedBox(width: 10),
                          const Text(
                            'I agree to the Terms & Conditions.',
                            style: TextStyle(
                              color: Color(0xFF52688E),
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      height: 58,
                      width: double.infinity,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: accepted
                              ? const LinearGradient(
                                  colors: [
                                    Color(0xFF168CF0),
                                    Color(0xFFE83DDB),
                                  ],
                                )
                              : const LinearGradient(
                                  colors: [
                                    Color(0xFFB7C1D0),
                                    Color(0xFFD1D6DE),
                                  ],
                                ),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: accepted ? continueToNextPage : null,
                            child: const Center(
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    'Continue',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 18,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  SizedBox(width: 14),
                                  Icon(
                                    Icons.arrow_forward,
                                    color: Colors.white,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class TermRow extends StatelessWidget {
  const TermRow(
    this.icon,
    this.background,
    this.iconColor,
    this.message, {
    super.key,
  });

  final IconData icon;
  final Color background;
  final Color iconColor;
  final String message;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
    child: Row(
      children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: iconColor, size: 29),
        ),
        const SizedBox(width: 18),
        Expanded(
          child: Text(
            message,
            style: const TextStyle(
              color: Color(0xFF52688E),
              fontSize: 15,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    ),
  );
}

class NextPage extends StatelessWidget {
  const NextPage({super.key});

  @override
  Widget build(BuildContext context) => const HomePage();
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int selectedTab = 0;
  final List<DemoVideo> videos = List.generate(
    60,
    (index) => DemoVideo.fromIndex(index),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFF06143D),
    body: SafeArea(
      bottom: false,
      child: Column(
        children: [
          _HomeHeader(
            onMenu: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (context) => const DashboardPage(),
                ),
              );
            },
            notificationCount: unreadNotificationCount,
            onNotifications: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (context) => const NotificationCenter(),
                ),
              );
            },
          ),
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: selectedTab == 0
                      ? _VideoFeed(videos: videos)
                      : selectedTab == 1
                      ? const CreateAdPage()
                      : const ProfilePage(),
                ),
                if (selectedTab == 0)
                  Positioned(
                    bottom: 12,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: SizedBox(
                        width: 312,
                        height: 104,
                        child: _CreateAdCallout(
                          onTap: () => setState(() => selectedTab = 1),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
    bottomNavigationBar: _BottomNavigation(
      selectedIndex: selectedTab,
      onSelected: (index) => setState(() => selectedTab = index),
    ),
  );

}

class _HomeHeader extends StatelessWidget {
  const _HomeHeader({
    required this.onMenu,
    required this.onNotifications,
    required this.notificationCount,
  });

  final VoidCallback onMenu;
  final VoidCallback onNotifications;
  final int notificationCount;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(18, 12, 18, 8),
    child: Row(
      children: [
        IconButton(
          onPressed: onMenu,
          icon: const Icon(Icons.menu, size: 34),
          color: Colors.white,
          tooltip: 'Open dashboard',
        ),
        const Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: Image(
              image: AssetImage('assets/icon.png'),
              width: 320,
              height: 61,
              fit: BoxFit.fill,
              alignment: Alignment.centerLeft,
            ),
          ),
        ),
        IconButton(
          onPressed: () =>
              ScaffoldMessenger.of(context)
                  .showSnackBar(const SnackBar(content: Text('Back'))),
          icon: const Icon(Icons.chevron_left, size: 38),
          color: Colors.white,
          tooltip: 'Back',
        ),
        IconButton(
          onPressed: onNotifications,
          icon: _NotificationIconBadge(count: notificationCount),
          tooltip: 'Open notifications',
        ),
        const SizedBox(width: 12),
        const CircleAvatar(
          radius: 21,
          backgroundColor: Color(0xFF9B39FF),
          child: Icon(Icons.person, color: Colors.white, size: 27),
        ),
      ],
    ),
  );
}

class _NotificationIconBadge extends StatelessWidget {
  const _NotificationIconBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) => Stack(
    clipBehavior: Clip.none,
    children: [
      const Icon(Icons.notifications, color: Colors.white, size: 27),
      if (count > 0)
        Positioned(
          right: -8,
          top: -8,
          child: Container(
            constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
            padding: const EdgeInsets.symmetric(horizontal: 4),
            decoration: const BoxDecoration(
              color: Color(0xFFFF416C),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                count > 99 ? '99+' : '$count',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ),
    ],
  );
}

class NotificationCenter extends StatefulWidget {
  const NotificationCenter({super.key});

  @override
  State<NotificationCenter> createState() => _NotificationCenterState();
}

class _NotificationCenterState extends State<NotificationCenter> {
  final List<String> filterTabs = const [
    'All',
    'Campaigns',
    'Payments',
    'Security',
  ];

  String selectedFilter = 'All';

  final List<AppNotification> notifications = [
    AppNotification(
      title: 'AI Videos Ready',
      message: 'Your ad for Chai Shop has been generated. Choose your favorite video.',
      time: '2 min ago',
      icon: Icons.video_library_rounded,
      color: Color(0xFF9B39FF),
      category: 'Campaigns',
    ),
    AppNotification(
      title: 'Your Ad is Now Running',
      message: 'Your Fashion Store advertisement is being shown to customers within 3.2 km.',
      time: '15 min ago',
      icon: Icons.rocket_launch_rounded,
      color: Color(0xFF3B82F6),
      category: 'Campaigns',
    ),
    AppNotification(
      title: 'Payment Successful',
      message: 'Your campaign payment of ₹499 was successful.',
      time: '1 hour ago',
      icon: Icons.credit_card,
      color: Color(0xFF20B875),
      category: 'Payments',
    ),
    AppNotification(
      title: 'Campaign Completed',
      message: 'Your Restaurant campaign has completed successfully.',
      time: 'Yesterday',
      icon: Icons.location_on,
      color: Color(0xFF635BFF),
      category: 'Campaigns',
    ),
    AppNotification(
      title: 'New Videos Generated',
      message: '5 new AI-generated videos are ready for your campaign.',
      time: 'Yesterday',
      icon: Icons.video_library_rounded,
      color: Color(0xFF9B39FF),
      category: 'Campaigns',
    ),
    AppNotification(
      title: 'OTP Verified Successfully',
      message:
          'Your mobile number has been verified successfully. Welcome to BOLO!',
      time: 'Yesterday',
      icon: Icons.verified_user,
      color: Color(0xFF3478E5),
      category: 'Security',
    ),
  ];

  List<AppNotification> get filteredNotifications {
    if (selectedFilter == 'All') {
      return notifications;
    }
    return notifications
        .where((notification) => notification.category == selectedFilter)
        .toList();
  }

  bool paused = false;
  String? openNotificationKey;
  final Map<String, bool> notificationSettings = {
    'Campaign updates': true,
    'AI video updates': true,
    'Payment updates': true,
    'Security & OTP': true,
    'Offers & announcements': true,
  };

  void markAllRead() => setState(() {
    for (final notification in notifications) {
      notification.read = true;
    }
  });

  void deleteAll() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF0B2257),
        title: const Text(
          'Delete all notifications?',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'This will permanently delete all your notifications. This cannot be undone.',
          style: TextStyle(color: Color(0xFFB9C4E9)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFFF416C),
            ),
            onPressed: () {
              setState(notifications.clear);
              Navigator.pop(context);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void showPauseOptions() {
    var selectedOption = '1 Hour';
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF0B2257),
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: const Text(
                  'Pause Notifications',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                subtitle: const Text(
                  'Choose how long notifications should be paused.',
                  style: TextStyle(color: Color(0xFFB9C4E9)),
                ),
                trailing: IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, color: Colors.white),
                  tooltip: 'Close',
                ),
              ),
              for (final option in ['1 Hour', '8 Hours', 'Until Tomorrow'])
                ListTile(
                  leading: Icon(
                    selectedOption == option
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    color: const Color(0xFF8D63FF),
                  ),
                  onTap: () => setSheetState(() => selectedOption = option),
                  title: Text(
                    option,
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF8047FF),
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () {
                      setState(() => paused = true);
                      Navigator.pop(context);
                    },
                    child: const Text('Apply'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void showSettings() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF0B2257),
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: const Text(
                  'Notification Settings',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                subtitle: const Text(
                  'Choose which updates you want to receive.',
                  style: TextStyle(color: Color(0xFFB9C4E9)),
                ),
                trailing: IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, color: Colors.white),
                  tooltip: 'Close',
                ),
              ),
              for (final label in notificationSettings.keys)
                SwitchListTile(
                  value: notificationSettings[label]!,
                  onChanged: (value) {
                    setSheetState(() => notificationSettings[label] = value);
                    setState(() {});
                  },
                  title: Text(
                    label,
                    style: const TextStyle(color: Colors.white),
                  ),
                  activeThumbColor: const Color(0xFF8047FF),
                ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFF06143D),
    appBar: AppBar(
      backgroundColor: const Color(0xFF06143D),
      foregroundColor: Colors.white,
      title: const Text(
        'Notifications',
        style: TextStyle(fontWeight: FontWeight.w800),
      ),
      actions: [
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert),
          color: const Color(0xFF0B2257),
          onSelected: (value) {
            if (value == 'read') markAllRead();
            if (value == 'delete') deleteAll();
            if (value == 'settings') showSettings();
            if (value == 'pause') showPauseOptions();
          },
          itemBuilder: (context) => const [
            PopupMenuItem(
              value: 'read',
              child: Text(
                'Mark all as read',
                style: TextStyle(color: Colors.white),
              ),
            ),
            PopupMenuItem(
              value: 'delete',
              child: Text(
                'Delete all notifications',
                style: TextStyle(color: Colors.white),
              ),
            ),
            PopupMenuItem(
              value: 'settings',
              child: Text(
                'Notification settings',
                style: TextStyle(color: Colors.white),
              ),
            ),
            PopupMenuItem(
              value: 'pause',
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Expanded(
                    child: Text(
                      'Pause notifications',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                  SizedBox(width: 20),
                  Icon(
                    Icons.chevron_right,
                    color: Colors.white,
                    size: 20,
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    ),
    body: Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: filterTabs.map((tab) {
                final isSelected = tab == selectedFilter;
                return Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: GestureDetector(
                    onTap: () => setState(() => selectedFilter = tab),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? const Color(0xFF8D63FF)
                            : const Color(0xFF102A5C),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSelected
                              ? const Color(0xFF8D63FF)
                              : const Color(0xFF2A437A),
                        ),
                      ),
                      child: Text(
                        tab,
                        style: TextStyle(
                          color: isSelected ? Colors.white : const Color(0xFFB9C4E9),
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
        Expanded(
          child: filteredNotifications.isEmpty
              ? const Center(
                  child: Text(
                    'No notifications',
                    style: TextStyle(color: Color(0xFFB9C4E9), fontSize: 18),
                  ),
                )
              : ListView.builder(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  itemCount: filteredNotifications.length,
                  itemBuilder: (context, index) {
                    final notification = filteredNotifications[index];
                    return SwipeableNotificationCard(
                      key: ValueKey(notification),
                      notification: notification,
                      onRead: () => setState(() => notification.read = true),
                      onLongPress: () => showNotificationActions(notification),
                      onDelete: () => _deleteNotification(notification),
                    );
                  },
                ),
        ),
      ],
    ),
  );

  void showNotificationActions(AppNotification notification) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF0B2257),
        title: Text(
          notification.title,
          style: const TextStyle(color: Colors.white),
        ),
        content: const Text(
          'Choose an action for this notification.',
          style: TextStyle(color: Color(0xFFB9C4E9)),
        ),
        actions: [
          TextButton.icon(
            onPressed: () {
              setState(() => notification.read = true);
              Navigator.pop(dialogContext);
            },
            icon: const Icon(Icons.mark_email_read, color: Colors.white),
            label: const Text(
              'Mark as read',
              style: TextStyle(color: Colors.white),
            ),
          ),
          TextButton.icon(
            onPressed: () {
              Navigator.pop(dialogContext);
              _deleteNotification(notification);
            },
            icon: const Icon(Icons.delete, color: Color(0xFFFF416C)),
            label: const Text(
              'Delete',
              style: TextStyle(color: Color(0xFFFF416C)),
            ),
          ),
        ],
      ),
    );
  }

  void _deleteNotification(AppNotification notification) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        notifications.remove(notification);
        openNotificationKey = null;
      });
    });
  }

}

class AppNotification {
  AppNotification({
    required this.title,
    required this.message,
    required this.time,
    required this.icon,
    required this.color,
    required this.category,
  });

  final String title;
  final String message;
  final String time;
  final IconData icon;
  final Color color;
  final String category;
  bool read = false;
}

class SwipeableNotificationCard extends StatefulWidget {
  const SwipeableNotificationCard({
    super.key,
    required this.notification,
    required this.onRead,
    required this.onLongPress,
    required this.onDelete,
  });

  final AppNotification notification;
  final VoidCallback onRead;
  final VoidCallback onLongPress;
  final VoidCallback onDelete;

  @override
  State<SwipeableNotificationCard> createState() =>
      _SwipeableNotificationCardState();
}

class _SwipeableNotificationCardState extends State<SwipeableNotificationCard> {
  static const double _maxDrag = 110;
  double _dragOffset = 0;

  void _handleDragUpdate(DragUpdateDetails details) {
    final delta = details.primaryDelta ?? 0;
    setState(() {
      _dragOffset = (_dragOffset + delta).clamp(-_maxDrag, _maxDrag);
    });
  }

  void _handleDragEnd(DragEndDetails details) {
    if (_dragOffset < -_maxDrag * 0.55) {
      setState(() => _dragOffset = -_maxDrag);
      return;
    }
    if (_dragOffset > _maxDrag * 0.55) {
      setState(() => _dragOffset = _maxDrag);
      return;
    }
    setState(() => _dragOffset = 0);
  }

  void _reset() => setState(() => _dragOffset = 0);

  @override
  Widget build(BuildContext context) {
    final card = _NotificationCard(
      notification: widget.notification,
      onRead: widget.onRead,
      onLongPress: widget.onLongPress,
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.only(left: 22),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2DBD85),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: GestureDetector(
                      onTap: () {
                        _reset();
                        Clipboard.setData(
                          ClipboardData(
                            text:
                                '${widget.notification.title}\n${widget.notification.message}',
                          ),
                        );
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Copied')),
                        );
                      },
                      child: const Icon(
                        Icons.copy_rounded,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: Container(
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 22),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF416C),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: GestureDetector(
                      onTap: () {
                        _reset();
                        widget.onDelete();
                      },
                      child: const Icon(
                        Icons.delete_outline_rounded,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          AnimatedBuilder(
            animation: AlwaysStoppedAnimation<double>(_dragOffset),
            builder: (context, _) => Transform.translate(
              offset: Offset(_dragOffset, 0),
              child: GestureDetector(
                onTap: () {
                  if (_dragOffset != 0) {
                    _reset();
                    return;
                  }
                  widget.onRead();
                },
                onLongPress: () {
                  if (_dragOffset == 0) {
                    widget.onLongPress();
                  }
                },
                onHorizontalDragUpdate: _handleDragUpdate,
                onHorizontalDragEnd: _handleDragEnd,
                child: card,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NotificationCard extends StatelessWidget {
  const _NotificationCard({
    required this.notification,
    required this.onRead,
    required this.onLongPress,
  });

  final AppNotification notification;
  final VoidCallback onRead;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onRead,
    onLongPress: onLongPress,
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0A2052),
        border: Border.all(color: const Color(0xFF164995)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 25,
            backgroundColor: notification.color,
            child: Icon(notification.icon, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  notification.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  notification.message,
                  style: const TextStyle(
                    color: Color(0xFFB9C4E9),
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  notification.time,
                  style: const TextStyle(
                    color: Color(0xFF8295C8),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          if (!notification.read)
            const Icon(Icons.circle, color: Color(0xFFFF248F), size: 9),
        ],
      ),
    ),
  );
}

class _VideoFeed extends StatelessWidget {
  const _VideoFeed({required this.videos});

  final List<DemoVideo> videos;

  @override
  Widget build(BuildContext context) => CustomScrollView(
    physics: const BouncingScrollPhysics(),
    slivers: [
      const SliverToBoxAdapter(child: _FeedTitle()),
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 112),
        sliver: SliverList.builder(
          itemCount: videos.length,
          itemBuilder: (context, index) => DemoVideoCard(video: videos[index]),
        ),
      ),
    ],
  );
}

class _FeedTitle extends StatelessWidget {
  const _FeedTitle();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.fromLTRB(28, 4, 22, 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: 'AI ',
                style: TextStyle(color: Color(0xFFB536FF)),
              ),
              TextSpan(text: 'Generated Videos'),
            ],
          ),
          style: TextStyle(
            color: Colors.white,
            fontSize: 29,
            fontWeight: FontWeight.w800,
          ),
        ),
        SizedBox(height: 2),
        Text(
          'Scroll and choose the best video for your business',
          style: TextStyle(color: Color(0xFFB9C4E9), fontSize: 15),
        ),
      ],
    ),
  );
}

class DemoVideoCard extends StatelessWidget {
  const DemoVideoCard({super.key, required this.video});

  final DemoVideo video;

  @override
  Widget build(BuildContext context) => Container(
    height: 145,
    margin: const EdgeInsets.only(bottom: 12),
    decoration: BoxDecoration(
      color: const Color(0xFF0A2052),
      border: Border.all(color: const Color(0xFF164995)),
      borderRadius: BorderRadius.circular(18),
    ),
    clipBehavior: Clip.antiAlias,
    child: Row(
      children: [
        Expanded(flex: 5, child: _VideoThumbnail(video: video)),
        Expanded(
          flex: 5,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 8, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  video.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  video.subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFFAAB9DF),
                    fontSize: 13,
                  ),
                ),
                const Spacer(),
                const Row(
                  children: [
                    _SocialIcon(icon: Icons.smart_display, color: Colors.red),
                    _SocialIcon(icon: Icons.facebook, color: Color(0xFF1689F5)),
                    _SocialIcon(
                      icon: Icons.camera_alt,
                      color: Color(0xFFE737B7),
                    ),
                  ],
                ),
                const Spacer(),
                Row(
                  children: [
                    const Icon(
                      Icons.location_on,
                      color: Color(0xFFB8B9FF),
                      size: 17,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Local Radius  |  ${video.radius} km',
                      style: const TextStyle(
                        color: Color(0xFFB5C1E6),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

class _VideoThumbnail extends StatelessWidget {
  const _VideoThumbnail({required this.video});

  final DemoVideo video;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: [video.color, const Color(0xFF071438)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
    ),
    child: Stack(
      children: [
        Positioned(
          right: -18,
          bottom: -30,
          child: Icon(
            video.imageIcon,
            size: 145,
            color: Colors.white.withValues(alpha: .14),
          ),
        ),
        Center(
          child: Text(
            video.category,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w900,
              shadows: [Shadow(color: Colors.black54, blurRadius: 5)],
            ),
          ),
        ),
        const Center(
          child: CircleAvatar(
            radius: 21,
            backgroundColor: Color(0xB8000018),
            child: Icon(Icons.play_arrow, color: Colors.white, size: 29),
          ),
        ),
        Positioned(
          right: 7,
          bottom: 7,
          child: Text(
            video.duration,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    ),
  );
}

class _SocialIcon extends StatelessWidget {
  const _SocialIcon({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 7),
    child: Icon(icon, color: color, size: 24),
  );
}

class DemoVideo {
  const DemoVideo({
    required this.title,
    required this.subtitle,
    required this.category,
    required this.radius,
    required this.duration,
    required this.color,
    required this.imageIcon,
  });

  final String title;
  final String subtitle;
  final String category;
  final String radius;
  final String duration;
  final Color color;
  final IconData imageIcon;

  factory DemoVideo.fromIndex(int index) {
    const entries = [
      ('Chai Shop', 'Desi Chai, Desi Swad', 'CHAI\nSHOP', Icons.local_cafe),
      (
        'Fashion Store',
        'Latest Fashion, Best Deals',
        'TRENDY\nFASHION',
        Icons.shopping_bag,
      ),
      (
        'School Admission',
        'Quality Education for Your Child',
        'BETTER\nEDUCATION',
        Icons.school,
      ),
      ('Restaurant', 'Fresh Food, Happy Mood', 'DESI\nKHANA', Icons.restaurant),
      (
        'Gym & Fitness',
        'Fit Body, Healthy Life',
        'FITNESS',
        Icons.fitness_center,
      ),
      ('Local Salon', 'Style That Speaks', 'NEW\nSTYLE', Icons.content_cut),
    ];
    final entry = entries[index % entries.length];
    final colors = [
      const Color(0xFFB55A1C),
      const Color(0xFFAD2368),
      const Color(0xFF1971A4),
      const Color(0xFF9B481D),
      const Color(0xFF164D72),
      const Color(0xFF6B2D9F),
    ];
    return DemoVideo(
      title: entry.$1,
      subtitle: entry.$2,
      category: entry.$3,
      radius: '${2 + (index % 5)}.${index % 10}',
      duration: '0:${(18 + (index % 5)).toString().padLeft(2, '0')}',
      color: colors[index % colors.length],
      imageIcon: entry.$4,
    );
  }
}

class _BottomNavigation extends StatelessWidget {
  const _BottomNavigation({
    required this.selectedIndex,
    required this.onSelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) => Container(
    height: 84,
    decoration: const BoxDecoration(
      color: Color(0xFF06143D),
      border: Border(top: BorderSide(color: Color(0xFF193A78))),
    ),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        _NavItem(
          icon: Icons.home_rounded,
          label: 'Home',
          selected: selectedIndex == 0,
          onTap: () => onSelected(0),
        ),
        _NavItem(
          icon: Icons.add_circle_outline,
          label: 'Create',
          selected: selectedIndex == 1,
          onTap: () => onSelected(1),
        ),
        _NavItem(
          icon: Icons.person_outline,
          label: 'Profile',
          selected: selectedIndex == 2,
          onTap: () => onSelected(2),
        ),
      ],
    ),
  );
}

class _CreateAdCallout extends StatelessWidget {
  const _CreateAdCallout({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: Container(
        width: double.infinity,
        height: 104,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF1B53F7), Color(0xFFE719D8)],
          ),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: const Color(0xFF884FFF), width: 1.5),
          boxShadow: const [
            BoxShadow(
              color: Color(0x66000000),
              blurRadius: 16,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .2),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(
                Icons.video_library_rounded,
                color: Colors.white,
                size: 31,
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Create Your Own Ad',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  SizedBox(height: 5),
                  Text(
                    'Upload your own video and reach\nlocal customers',
                    style: TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios, color: Colors.white, size: 18),
          ],
        ),
      ),
    ),
  );
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: SizedBox(
      width: 90,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            color: selected ? const Color(0xFF9B55FF) : const Color(0xFFB8C1E6),
            size: 31,
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: TextStyle(
              color: selected
                  ? const Color(0xFF5C8BFF)
                  : const Color(0xFFB8C1E6),
              fontWeight: FontWeight.w700,
            ),
          ),
          if (selected)
            Container(
              width: 45,
              height: 3,
              margin: const EdgeInsets.only(top: 4),
              color: const Color(0xFF8C35FF),
            ),
        ],
      ),
    ),
  );
}

class CreateAdPage extends StatefulWidget {
  const CreateAdPage({super.key});

  @override
  State<CreateAdPage> createState() => _CreateAdPageState();
}

class _CreateAdPageState extends State<CreateAdPage> {
  final shopNameController = TextEditingController();
  final descriptionController = TextEditingController();
  final radiusController = TextEditingController(text: '2.5');
  final durationController = TextEditingController(text: '7');
  final selectedPlatforms = <String>{'YouTube', 'Facebook', 'Instagram'};

  @override
  void dispose() {
    shopNameController.dispose();
    descriptionController.dispose();
    radiusController.dispose();
    durationController.dispose();
    super.dispose();
  }

  void createCampaign() {
    final shopName = shopNameController.text.trim();
    final radius = double.tryParse(radiusController.text.trim());
    final duration = int.tryParse(durationController.text.trim());
    if (shopName.isEmpty || radius == null || radius <= 0 || duration == null || duration <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a shop name, radius, and duration.')),
      );
      return;
    }

    activeCampaign.value = Campaign(
      shopName: shopName,
      description: descriptionController.text.trim().isEmpty
          ? 'Reach local customers near your shop'
          : descriptionController.text.trim(),
      radiusKm: radius,
      durationDays: duration,
      platforms: Set.unmodifiable(selectedPlatforms),
      videoLength: '20 sec',
      budget: 1000,
      spent: 640,
      totalPhones: 1248,
      activeDevices: 842,
      androidPhones: 1084,
      iphonePhones: 164,
      totalViews: 12480,
      reach: 8320,
      websiteClicks: 1230,
      shares: 540,
    );
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Campaign added to your dashboard.')),
    );
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.all(20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Create Your Own Ad',
          style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        const Text(
          'Add your campaign details and they will appear in Dashboard.',
          style: TextStyle(color: Color(0xFFB6C5F0)),
        ),
        const SizedBox(height: 24),
        _CampaignInput(controller: shopNameController, label: 'Shop name', hint: 'Chai Shop'),
        const SizedBox(height: 14),
        _CampaignInput(
          controller: descriptionController,
          label: 'Shop description',
          hint: 'Desi Chai, Desi Swad',
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: _CampaignInput(
                controller: radiusController,
                label: 'Radius (km)',
                hint: '2.5',
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _CampaignInput(
                controller: durationController,
                label: 'Duration (days)',
                hint: '7',
                keyboardType: TextInputType.number,
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        const Text('Choose platforms', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        for (final platform in ['YouTube', 'Facebook', 'Instagram'])
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            activeColor: const Color(0xFF9B55FF),
            checkColor: Colors.white,
            title: Text(platform, style: const TextStyle(color: Colors.white)),
            value: selectedPlatforms.contains(platform),
            onChanged: (selected) => setState(() {
              if (selected == true) {
                selectedPlatforms.add(platform);
              } else {
                selectedPlatforms.remove(platform);
              }
            }),
          ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: createCampaign,
            icon: const Icon(Icons.campaign_rounded),
            label: const Text('Add Campaign to Dashboard'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF8C35FF),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 15),
            ),
          ),
        ),
      ],
    ),
  );
}

class _CampaignInput extends StatelessWidget {
  const _CampaignInput({
    required this.controller,
    required this.label,
    required this.hint,
    this.keyboardType,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    keyboardType: keyboardType,
    style: const TextStyle(color: Colors.white),
    decoration: InputDecoration(
      labelText: label,
      hintText: hint,
      labelStyle: const TextStyle(color: Color(0xFFB6C5F0)),
      hintStyle: const TextStyle(color: Color(0xFF7184B8)),
      filled: true,
      fillColor: const Color(0xFF111F4B),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF3B6EDF)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF294F9E)),
      ),
    ),
  );
}

class _CreateCampaignBottomBar extends StatelessWidget {
  const _CreateCampaignBottomBar();

  @override
  Widget build(BuildContext context) => Container(
    height: 70,
    decoration: const BoxDecoration(color: Color(0xFF071B4D), border: Border(top: BorderSide(color: Color(0xFF1D4FB0)))),
    child: const Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        _BottomNavItem(icon: Icons.home_rounded, label: 'Home', selected: false),
        _BottomNavItem(icon: Icons.add_circle_rounded, label: 'Create', selected: true),
        _BottomNavItem(icon: Icons.person_rounded, label: 'Profile', selected: false),
      ],
    ),
  );
}

class CampaignDetailsPage extends StatelessWidget {
  const CampaignDetailsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final campaign = activeCampaign.value;
    final shopName = campaign?.shopName ?? 'No Campaign Yet';
    final description = campaign?.description ?? 'Create a campaign to see its details';
    final radius = campaign == null ? '—' : formatRadius(campaign.radiusKm);
    final duration = campaign == null ? '—' : '${campaign.durationDays} Days';
    final platforms = campaign == null ? '—' : campaign.platforms.join(' + ');
    final videoLength = campaign?.videoLength ?? '—';
    final budget = campaign?.budget;
    final spent = campaign?.spent;
    final remaining = budget != null && spent != null ? budget - spent : null;
    final progress = budget != null && budget > 0 && spent != null
      ? (spent / budget).clamp(0.0, 1.0)
      : 0.0;
    return Scaffold(
      backgroundColor: const Color(0xFF06143D),
      appBar: AppBar(
        backgroundColor: const Color(0xFF06143D),
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: const Text('Campaign Details', style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 12, top: 10, bottom: 10),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF064B4A),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFF20D7A6)),
            ),
            child: Row(
              children: [
                Icon(Icons.circle, color: Color(0xFF00F09D), size: 9),
                SizedBox(width: 6),
                Text(
                  campaign == null ? 'No Campaign' : 'Campaign Live',
                  style: TextStyle(color: Color(0xFF8BF5D5), fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: _DetailsPanel(
                      title: 'Business & Creative Info',
                      icon: Icons.campaign_rounded,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.storefront_rounded, color: Color(0xFFB66CFF), size: 34),
                              const SizedBox(width: 9),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(shopName, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
                                    Text(description, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFFB6C5F0), fontSize: 10)),
                                  ],
                                ),
                              ),
                                  Icon(
                                  campaign == null
                                    ? Icons.remove_circle_outline_rounded
                                    : Icons.play_circle_fill_rounded,
                                  color: campaign == null
                                    ? const Color(0xFF7184B8)
                                    : const Color(0xFFE4A341),
                                  size: 38,
                                  ),
                            ],
                          ),
                          const Divider(color: Color(0xFF294C91), height: 18),
                          Text(
                            campaign == null
                                ? 'Started: —  |  Ends: —'
                                : 'Started: 2 Sept  |  Ends: 9 Sept',
                            style: const TextStyle(color: Colors.white, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _DetailsPanel(
                      title: 'Campaign Settings',
                      icon: Icons.tune_rounded,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [Expanded(child: _DetailValue(icon: Icons.calendar_month_rounded, label: 'Radius', value: radius)), Expanded(child: _DetailValue(icon: Icons.movie_rounded, label: 'Video', value: videoLength))]),
                          const SizedBox(height: 10),
                          _DetailValue(icon: Icons.phone_android_rounded, label: 'Platforms', value: platforms),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  Expanded(
                    child: _DetailsPanel(
                      title: 'Campaign Settings',
                      icon: Icons.settings_rounded,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _DetailValue(icon: Icons.location_on_rounded, label: 'Radius', value: radius),
                          _DetailValue(icon: Icons.calendar_month_rounded, label: 'Duration', value: duration),
                          _DetailValue(icon: Icons.movie_rounded, label: 'Video', value: videoLength),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _DetailsPanel(
                      title: 'Budget & Spending',
                      icon: Icons.wallet_rounded,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            budget == null ? 'Total Campaign Budget: —' : 'Total Campaign Budget: ₹$budget',
                            style: const TextStyle(color: Colors.white, fontSize: 12),
                          ),
                          const SizedBox(height: 8),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(5),
                            child: LinearProgressIndicator(
                              value: progress,
                              minHeight: 7,
                              backgroundColor: const Color(0xFF24457D),
                              color: const Color(0xFF4B8CFF),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('Spent: ${spent == null ? '—' : '₹$spent'}', style: const TextStyle(color: Colors.white, fontSize: 11)),
                              Text('Remaining: ${remaining == null ? '—' : '₹$remaining'}', style: const TextStyle(color: Colors.white, fontSize: 11)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              _DetailsPanel(
                title: 'Selected Location & Radius',
                icon: Icons.location_on_rounded,
                child: SizedBox(
                  height: 220,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: _DashboardMapPreview(
                      radiusKm: campaign?.radiusKm ?? 0,
                    ),
                  ),
                ),
              ),
              _DetailsPanel(
                title: 'Platform Performance',
                icon: Icons.bar_chart_rounded,
                child: _PlatformPerformanceTable(campaign: campaign),
              ),
              _DetailsPanel(
                title: 'Performance Over Time',
                icon: Icons.bar_chart_rounded,
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(child: _MetricTile(title: 'Total Phones', value: formatCount(campaign?.totalPhones), trend: campaign == null ? '—' : '↑ 45%', color: const Color(0xFF1D8B91))),
                        const SizedBox(width: 7),
                        Expanded(child: _MetricTile(title: 'Total Views', value: formatCount(campaign?.totalViews), trend: campaign == null ? '—' : '↑ 68%', color: const Color(0xFF245ACB))),
                        const SizedBox(width: 7),
                        Expanded(child: _MetricTile(title: 'Total Reach', value: formatCount(campaign?.reach), trend: campaign == null ? '—' : '↑ 54%', color: const Color(0xFF8E3EC5))),
                        const SizedBox(width: 7),
                        Expanded(child: _MetricTile(title: 'Shares', value: formatCount(campaign?.shares), trend: campaign == null ? '—' : '↑ 49%', color: const Color(0xFF159B82))),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Align(alignment: Alignment.centerLeft, child: Text('Daily Performance Graph', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800))),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 145,
                      child: campaign == null
                          ? const Center(
                              child: Text(
                                'No performance data yet',
                                style: TextStyle(color: Color(0xFFB6C5F0)),
                              ),
                            )
                          : CustomPaint(painter: _PerformanceGraphPainter()),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: const _CreateCampaignBottomBar(),
    );
  }
}

class _DetailsPanel extends StatelessWidget {
  const _DetailsPanel({required this.title, required this.icon, required this.child});

  final String title;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: const Color(0xFF102D6B),
      borderRadius: BorderRadius.circular(15),
      border: Border.all(color: const Color(0xFF1D5BC0)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [Icon(icon, color: const Color(0xFFB66CFF), size: 24), const SizedBox(width: 8), Text(title, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800))]),
        const SizedBox(height: 10),
        child,
      ],
    ),
  );
}

class _DetailValue extends StatelessWidget {
  const _DetailValue({required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, color: const Color(0xFFB66CFF), size: 22),
      const SizedBox(width: 6),
      Flexible(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label, style: const TextStyle(color: Color(0xFFB6C5F0), fontSize: 10)), Text(value, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800))])),
    ],
  );
}

class _PlatformPerformanceTable extends StatelessWidget {
  const _PlatformPerformanceTable({required this.campaign});

  final Campaign? campaign;

  @override
  Widget build(BuildContext context) {
    final rows = [
      ('YouTube', '4,820', '3,210', 'assets/youtube.png'),
      ('Facebook', '3,760', '2,840', 'assets/facebook.png'),
      ('Instagram', '3,900', '2,270', 'assets/intagram.png'),
    ];
    final visibleRows = rows
        .where((row) => campaign?.platforms.contains(row.$1) ?? false)
        .toList();
    final totalViews = visibleRows.fold<int>(
      0,
      (total, row) => total + int.parse(row.$2.replaceAll(',', '')),
    );
    final totalReach = visibleRows.fold<int>(
      0,
      (total, row) => total + int.parse(row.$3.replaceAll(',', '')),
    );
    return Column(
      children: [
        const Row(children: [Expanded(child: Text('Platform', style: TextStyle(color: Color(0xFFB6C5F0), fontWeight: FontWeight.w700))), Expanded(child: Text('Views', style: TextStyle(color: Color(0xFFB6C5F0), fontWeight: FontWeight.w700))), Expanded(child: Text('Reach', style: TextStyle(color: Color(0xFFB6C5F0), fontWeight: FontWeight.w700)))]),
        const Divider(color: Color(0xFF31599D)),
        for (final row in visibleRows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              children: [
                Expanded(child: Row(children: [Image.asset(row.$4, width: 18, height: 18), const SizedBox(width: 7), Text(row.$1, style: const TextStyle(color: Colors.white, fontSize: 12))])),
                Expanded(child: Text(campaign == null ? '—' : row.$2, style: const TextStyle(color: Colors.white, fontSize: 12))),
                Expanded(child: Text(campaign == null ? '—' : row.$3, style: const TextStyle(color: Colors.white, fontSize: 12))),
              ],
            ),
          ),
        const Divider(color: Color(0xFF31599D)),
        Row(children: [
          const Expanded(child: Text('Total', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800))),
          Expanded(child: Text(campaign == null ? '—' : _formatCount(totalViews), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800))),
          Expanded(child: Text(campaign == null ? '—' : _formatCount(totalReach), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800))),
        ]),
      ],
    );
  }

  String _formatCount(int value) => value.toString().replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (match) => ',',
  );
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({required this.title, required this.value, required this.trend, required this.color});

  final String title;
  final String value;
  final String trend;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(8),
    decoration: BoxDecoration(color: color.withValues(alpha: .65), borderRadius: BorderRadius.circular(10), border: Border.all(color: color)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFFCEE0FF), fontSize: 9)), Text(value, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)), Text(trend, style: const TextStyle(color: Color(0xFF65E6B3), fontSize: 9))]),
  );
}

class _PerformanceGraphPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()..color = const Color(0xFF31599D)..strokeWidth = 1;
    for (var index = 1; index < 4; index++) {
      final y = size.height * index / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    final phones = Paint()..color = const Color(0xFF398BFF)..strokeWidth = 3..style = PaintingStyle.stroke;
    final views = Paint()..color = const Color(0xFFA844C9)..strokeWidth = 3..style = PaintingStyle.stroke;
    final phonePath = ui.Path()..moveTo(0, size.height * .75)..lineTo(size.width * .16, size.height * .55)..lineTo(size.width * .32, size.height * .48)..lineTo(size.width * .48, size.height * .68)..lineTo(size.width * .64, size.height * .2)..lineTo(size.width * .8, size.height * .3)..lineTo(size.width, size.height * .78);
    final viewPath = ui.Path()..moveTo(0, size.height * .88)..lineTo(size.width * .16, size.height * .7)..lineTo(size.width * .32, size.height * .6)..lineTo(size.width * .48, size.height * .72)..lineTo(size.width * .64, size.height * .48)..lineTo(size.width * .8, size.height * .5)..lineTo(size.width, size.height * .62);
    canvas.drawPath(phonePath, phones);
    canvas.drawPath(viewPath, views);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    const blueBorder = Color(0xFF3B6EDF);
    const purple = Color(0xFFB96EFF);
    const green = Color(0xFF2ED4B0);

    return ValueListenableBuilder<Campaign?>(
      valueListenable: activeCampaign,
      builder: (context, campaign, _) => Scaffold(
      backgroundColor: const Color(0xFF07163D),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 6),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Image(
                        image: AssetImage('assets/icon.png'),
                        width: 320,
                        height: 61,
                        fit: BoxFit.fill,
                        alignment: Alignment.centerLeft,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    style: IconButton.styleFrom(
                      backgroundColor: const Color(0xFF2B4BA8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      fixedSize: const Size(44, 44),
                    ),
                    icon: const Icon(
                      Icons.keyboard_arrow_left_rounded,
                      color: Colors.white,
                      size: 28,
                    ),
                    tooltip: 'Back',
                  ),
                ],
              ),
              const SizedBox(height: 26),
              Row(
                children: [
                  SizedBox(
                    width: 64,
                    height: 64,
                    child: Image.asset(
                      'assets/ankit_transparent.png',
                      fit: BoxFit.contain,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Dashboard',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              const Text(
                'Your Campaign Overview',
                style: TextStyle(
                  color: Color(0xFFB6C5F0),
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 18),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF1B2F74), Color(0xFF141F59)],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: blueBorder, width: 1.2),
                ),
                child: Row(
                  children: [
                    Expanded(
                      flex: 5,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 42,
                                height: 42,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(12),
                                  color: purple.withValues(alpha: .22),
                                ),
                                child: const Icon(Icons.storefront_rounded, color: Color(0xFFB96EFF), size: 24),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      campaign?.shopName ?? 'No Campaign Yet',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 17,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    SizedBox(height: 2),
                                    Text(
                                      campaign?.description ?? '—',
                                      style: TextStyle(
                                        color: Color(0xFFB6C5F0),
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: const Color(0xFF063F54),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: green.withValues(alpha: .7)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.circle, color: Color(0xFF00F09D), size: 9),
                                SizedBox(width: 6),
                                Text(
                                  campaign == null ? 'No Campaign' : 'Campaign Live',
                                  style: TextStyle(
                                    color: Color(0xFF00F09D),
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(width: 1, height: 68, color: const Color(0xFF30488B)),
                    Expanded(
                      child: _CompactMetric(
                        icon: Icons.location_on_rounded,
                        label: 'Radius',
                        value: campaign == null ? '—' : formatRadius(campaign.radiusKm),
                      ),
                    ),
                    Container(width: 1, height: 68, color: const Color(0xFF30488B)),
                    Expanded(
                      child: _CompactMetric(
                        icon: Icons.calendar_today_rounded,
                        label: 'Duration',
                        value: campaign == null ? '—' : '${campaign.durationDays} Days',
                      ),
                    ),
                    Container(width: 1, height: 68, color: const Color(0xFF30488B)),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 30,
                            height: 30,
                            decoration: BoxDecoration(
                              color: const Color(0xFF392C9A),
                              borderRadius: BorderRadius.circular(9),
                            ),
                            child: const Icon(Icons.groups_rounded, color: Color(0xFFB9A3FF), size: 19),
                          ),
                          const SizedBox(height: 3),
                          const Text('Platforms', style: TextStyle(color: Color(0xFFB6C5F0), fontSize: 10)),
                          const SizedBox(height: 4),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              if (campaign?.platforms.contains('YouTube') ?? false)
                                const _PlatformBadgeAsset(image: AssetImage('assets/youtube.png')),
                              if (campaign?.platforms.contains('Facebook') ?? false) ...[
                                const SizedBox(width: 3),
                                const _PlatformBadgeAsset(image: AssetImage('assets/facebook.png')),
                              ],
                              if (campaign?.platforms.contains('Instagram') ?? false) ...[
                                const SizedBox(width: 3),
                                const _PlatformBadgeAsset(image: AssetImage('assets/intagram.png')),
                              ],
                              if (campaign == null)
                                const Text('—', style: TextStyle(color: Colors.white, fontSize: 18)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: _DashboardStatCard(
                      icon: Icons.smartphone_rounded,
                      title: 'Total Phones in Selected Radius',
                      value: formatCount(campaign?.totalPhones),
                      subtitle: campaign == null ? 'Create a campaign to reach people' : 'People with your ad can see it',
                      color: const Color(0xFF111F4B),
                      iconBg: const Color(0xFF1D4ED8),
                      badgeText: null,
                      badgeColor: null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _DashboardStatCard(
                      icon: Icons.people_alt_rounded,
                      title: 'Active Devices Right Now',
                      value: formatCount(campaign?.activeDevices),
                      subtitle: campaign == null ? 'No active campaign yet' : 'Compared to last 7 days',
                      color: const Color(0xFF111F4B),
                      iconBg: const Color(0xFF14B8A6),
                      badgeText: campaign == null ? null : '+ 67%',
                      badgeColor: const Color(0xFF0F6B5B),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A3B77),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: blueBorder, width: 1.2),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.location_on_rounded, color: Color(0xFF8DB8FF), size: 28),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text(
                            'Selected Location & Radius',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (context) => const FullMapPage(),
                              ),
                            );
                          },
                          style: TextButton.styleFrom(
                            backgroundColor: const Color(0xFF2C4AA9),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          icon: const Icon(Icons.map_rounded, size: 16),
                          label: const Text(
                            'View Full Map',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Stack(
                      children: [
                        Container(
                          height: 256,
                          width: double.infinity,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(18),
                            gradient: const LinearGradient(
                              colors: [Color(0xFF091F46), Color(0xFF0E2B63)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(18),
                            child: _DashboardMapPreview(
                              radiusKm: campaign?.radiusKm ?? 0,
                            ),
                          ),
                        ),
                        Positioned(
                          left: 14,
                          top: 14,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                            decoration: BoxDecoration(
                              color: const Color(0xFFAF69FF),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              campaign == null ? 'Select a location to begin' : '${formatRadius(campaign.radiusKm)} Radius',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          right: 14,
                          bottom: 18,
                          child: Container(
                            width: 180,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFF163D8C),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: blueBorder, width: 1.2),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Phones in Radius',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                SizedBox(height: 12),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text('Android', style: TextStyle(color: Color(0xFFB6C5F0), fontSize: 12)),
                                    Text(formatCount(campaign?.androidPhones), style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
                                  ],
                                ),
                                SizedBox(height: 8),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text('iPhone', style: TextStyle(color: Color(0xFFB6C5F0), fontSize: 12)),
                                    Text(formatCount(campaign?.iphonePhones), style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
                decoration: BoxDecoration(
                  color: const Color(0xFF183B7E),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: blueBorder, width: 1.2),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.campaign_rounded, color: Color(0xFF8DB8FF), size: 28),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Campaign Information',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF102A5E),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: blueBorder, width: 1.2),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 110,
                      height: 90,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        gradient: const LinearGradient(
                          colors: [Color(0xFFB8721D), Color(0xFF5B2A00)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                      child: const Center(
                        child: Icon(Icons.play_arrow_rounded, color: Colors.white, size: 32),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            campaign?.shopName ?? 'No Campaign Yet',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 3),
                                    Text(
                                      campaign?.description ?? 'Create your first campaign to see it here',
                            style: TextStyle(
                              color: Color(0xFFB6C5F0),
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Icon(Icons.video_library_rounded, color: Colors.white, size: 16),
                              SizedBox(width: 6),
                              Text(
                                campaign == null ? 'No campaign video selected' : 'Video Length : ${campaign.videoLength}',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              if (campaign?.platforms.contains('Facebook') ?? false)
                              Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: Container(
                                  width: 24,
                                  height: 24,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF1F72F2),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Image(
                                    image: AssetImage('assets/facebook.png'),
                                    fit: BoxFit.cover,
                                  ),
                                ),
                              ),
                              if (campaign?.platforms.contains('YouTube') ?? false)
                              Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: Container(
                                  width: 24,
                                  height: 24,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFF1F4D),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Image(
                                    image: AssetImage('assets/youtube.png'),
                                    fit: BoxFit.cover,
                                  ),
                                ),
                              ),
                              if (campaign?.platforms.contains('Instagram') ?? false)
                              Container(
                                width: 24,
                                height: 24,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFE43BBF),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Image(
                                  image: AssetImage('assets/intagram.png'),
                                  fit: BoxFit.cover,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    InkWell(
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (context) => const CampaignDetailsPage(),
                        ),
                      ),
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF244DB0),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Row(
                          children: [
                            Text(
                              'View Details',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            SizedBox(width: 6),
                            Icon(Icons.arrow_forward_ios_rounded, color: Colors.white, size: 12),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  const Icon(Icons.bar_chart_rounded, color: Color(0xFF8DB8FF), size: 28),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Performance Overview',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1B3D7F),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Row(
                      children: [
                        Text(
                          'Last 7 Days',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white, size: 16),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: _PerformanceCard(
                      title: 'Total Views',
                      value: formatCount(campaign?.totalViews),
                      trend: campaign == null ? '—' : '+ 68%',
                      color: const Color(0xFF2559CF),
                      icon: Icons.remove_red_eye_rounded,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _PerformanceCard(
                      title: 'Reach',
                      value: formatCount(campaign?.reach),
                      trend: campaign == null ? '—' : '+ 54%',
                      color: const Color(0xFF8E42D8),
                      icon: Icons.groups_rounded,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _PerformanceCard(
                      title: 'Website Clicks',
                      value: formatCount(campaign?.websiteClicks),
                      trend: campaign == null ? '—' : '+ 72%',
                      color: const Color(0xFFB47014),
                      icon: Icons.touch_app_rounded,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _PerformanceCard(
                      title: 'Total Shares',
                      value: formatCount(campaign?.shares),
                      trend: campaign == null ? '—' : '+ 49%',
                      color: const Color(0xFF1FAF7D),
                      icon: Icons.share_rounded,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: Container(
        height: 90,
        padding: const EdgeInsets.fromLTRB(0, 8, 0, 8),
        decoration: const BoxDecoration(
          color: Color(0xFF081C47),
          border: Border(top: BorderSide(color: Color(0xFF2E4FAE))),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _BottomNavItem(icon: Icons.home_rounded, label: 'Home', selected: true),
            _BottomNavItem(icon: Icons.add_circle_rounded, label: 'Create', selected: false),
            _BottomNavItem(icon: Icons.person_rounded, label: 'Profile', selected: false),
          ],
        ),
      ),
    ),
    );
  }
}

class _CompactMetric extends StatelessWidget {
  const _CompactMetric({required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: const Color(0xFF392C9A),
          borderRadius: BorderRadius.circular(9),
        ),
        child: Icon(icon, color: const Color(0xFFB9A3FF), size: 19),
      ),
      const SizedBox(height: 3),
      Text(
        label,
        style: const TextStyle(color: Color(0xFFB6C5F0), fontSize: 10),
      ),
      const SizedBox(height: 2),
      Text(
        value,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 13,
          fontWeight: FontWeight.w800,
        ),
      ),
    ],
  );
}

class _PlatformBadgeAsset extends StatelessWidget {
  const _PlatformBadgeAsset({required this.image});

  final AssetImage image;

  @override
  Widget build(BuildContext context) => Container(
    width: 17,
    height: 17,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(5),
      color: Colors.white,
    ),
    child: Image(
      image: image,
      fit: BoxFit.cover,
      width: 17,
      height: 17,
    ),
  );
}

class _DashboardMapPreview extends StatefulWidget {
  const _DashboardMapPreview({required this.radiusKm});

  final double radiusKm;

  @override
  State<_DashboardMapPreview> createState() => _DashboardMapPreviewState();
}

class _DashboardMapPreviewState extends State<_DashboardMapPreview> {
  @override
  void initState() {
    super.initState();
    loadUserLocation();
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<LatLng?>(
    valueListenable: userLocation,
    builder: (context, location, _) {
      final center = location ?? fallbackLocation;
      return Stack(
        fit: StackFit.expand,
        children: [
          FlutterMap(
            options: MapOptions(initialCenter: center, initialZoom: 13),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.bolo_app',
              ),
              if (widget.radiusKm > 0)
                CircleLayer(
                  circles: [
                    CircleMarker(
                      point: center,
                      radius: widget.radiusKm * 1000,
                      useRadiusInMeter: true,
                      color: const Color(0xFF8D5EF4).withValues(alpha: .28),
                      borderColor: const Color(0xFFE6D9FF),
                      borderStrokeWidth: 2,
                    ),
                  ],
                ),
              MarkerLayer(
                markers: [
                  Marker(
                    point: center,
                    width: 38,
                    height: 38,
                    child: const Icon(
                      Icons.location_pin,
                      color: Color(0xFF8D5EF4),
                      size: 38,
                    ),
                  ),
                ],
              ),
            ],
          ),
          if (location == null)
            const Positioned(
              left: 12,
              bottom: 12,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Color(0xDD07163D),
                  borderRadius: BorderRadius.all(Radius.circular(8)),
                ),
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                  child: Text(
                    'Waiting for device location',
                    style: TextStyle(color: Colors.white, fontSize: 11),
                  ),
                ),
              ),
            ),
        ],
      );
    },
  );
}

class FullMapPage extends StatelessWidget {
  const FullMapPage({super.key});

  static const LatLng center = LatLng(28.6139, 77.2090);

  @override
  Widget build(BuildContext context) {
    final radiusKm = activeCampaign.value?.radiusKm ?? 0;
    final center = userLocation.value ?? fallbackLocation;
    return Scaffold(
    backgroundColor: const Color(0xFF07163D),
    appBar: AppBar(
      backgroundColor: const Color(0xFF07163D),
      foregroundColor: Colors.white,
      title: const Text('Selected Location & Radius'),
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_rounded),
        onPressed: () => Navigator.of(context).pop(),
      ),
    ),
    body: FlutterMap(
      options: MapOptions(initialCenter: center, initialZoom: 13.0),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.example.bolo_app',
        ),
        if (radiusKm > 0)
          CircleLayer(
            circles: [
              CircleMarker(
                point: center,
                radius: radiusKm * 1000,
                useRadiusInMeter: true,
                color: const Color(0xFF8D5EF4).withValues(alpha: 0.25),
                borderColor: const Color(0xFFE6D9FF),
                borderStrokeWidth: 2,
              ),
            ],
          ),
        MarkerLayer(
          markers: [
            Marker(
              point: center,
              width: 32,
              height: 32,
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Color(0xFFFFFFFF),
                      blurRadius: 16,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.location_on,
                  color: Color(0xFF1E3A8A),
                  size: 28,
                ),
              ),
            ),
          ],
        ),
      ],
    ),
    );
  }
}

class _DashboardStatCard extends StatelessWidget {
  const _DashboardStatCard({
    required this.icon,
    required this.title,
    required this.value,
    required this.subtitle,
    required this.color,
    required this.iconBg,
    this.badgeText,
    this.badgeColor,
  });

  final IconData icon;
  final String title;
  final String value;
  final String subtitle;
  final Color color;
  final Color iconBg;
  final String? badgeText;
  final Color? badgeColor;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: const Color(0xFF2C3E79), width: 1.2),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: Colors.white, size: 18),
            ),
            if (badgeText != null && badgeColor != null) ...[
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: badgeColor,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.arrow_upward_rounded, color: Colors.white, size: 12),
                    const SizedBox(width: 4),
                    Text(
                      badgeText!,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 18),
        Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w700,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 34,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.8,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          subtitle,
          style: const TextStyle(
            color: Color(0xFFBAC8F4),
            fontSize: 13,
            height: 1.3,
          ),
        ),
      ],
    ),
  );
}

class _PerformanceCard extends StatelessWidget {
  const _PerformanceCard({
    required this.title,
    required this.value,
    required this.trend,
    required this.color,
    required this.icon,
  });

  final String title;
  final String value;
  final String trend;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: Colors.white, size: 22),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 28,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          trend,
          style: const TextStyle(
            color: Color(0xFFE5E5FF),
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 2),
        const Text(
          'vs last 7 days',
          style: TextStyle(
            color: Color(0xFFE5E5FF),
            fontSize: 12,
          ),
        ),
      ],
    ),
  );
}

class _BottomNavItem extends StatelessWidget {
  const _BottomNavItem({required this.icon, required this.label, required this.selected});

  final IconData icon;
  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      Icon(
        icon,
        color: selected ? Colors.white : const Color(0xFFB5C5F3),
        size: 28,
      ),
      const SizedBox(height: 4),
      Text(
        label,
        style: TextStyle(
          color: selected ? Colors.white : const Color(0xFFB5C5F3),
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    ],
  );
}

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) => const Center(
    child: Text(
      'Your Profile',
      style: TextStyle(
        color: Colors.white,
        fontSize: 24,
        fontWeight: FontWeight.bold,
      ),
    ),
  );
}
