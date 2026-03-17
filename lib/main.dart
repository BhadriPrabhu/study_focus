// ignore_for_file: unnecessary_null_comparison
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:sensors_plus/sensors_plus.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'dart:math' as math;
import 'splash_screen.dart';

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();
const platform = MethodChannel('com.example.stackit/blocklist');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const AndroidInitializationSettings initSettingsAndroid =
      AndroidInitializationSettings('@mipmap/ic_launcher');
  await flutterLocalNotificationsPlugin.initialize(
    const InitializationSettings(android: initSettingsAndroid),
  );
  runApp(const MyApp());
}

Future<Database> _getDatabase() async {
  final dbPath = await getDatabasesPath();
  final path = p.join(dbPath, 'stackit_vault.db');
  return await openDatabase(
    path,
    version: 2,
    onCreate: (db, version) async {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS notifications (
          id INTEGER PRIMARY KEY AUTOINCREMENT, 
          pkg TEXT, 
          title TEXT, 
          content TEXT, 
          timestamp INTEGER,
          subject TEXT
        )
      '''); // Added comma here
    },
    onUpgrade: (db, oldV, newV) async {
      if (oldV < 2) {
        await db.execute(
          "ALTER TABLE notifications ADD COLUMN subject TEXT DEFAULT 'General'",
        );
      }
    },
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.teal,
        textTheme: GoogleFonts.poppinsTextTheme(),
      ),
      // In main.dart MyApp class
      home: const SplashScreen(),
    );
  }
}

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});
  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _currentIndex = 0;
  final List<Widget> _pages = [
    const ExamSchedulerScreen(),
    const NotificationVaultScreen(),
    const AnalyticsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _pages[_currentIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (i) => setState(() => _currentIndex = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.timer), label: 'Zones'),
          NavigationDestination(icon: Icon(Icons.inventory_2), label: 'Vault'),
          NavigationDestination(icon: Icon(Icons.bar_chart), label: 'Heatmap'),
        ],
      ),
    );
  }
}

// --- ZONES SCREEN ---
class ExamSchedulerScreen extends StatefulWidget {
  const ExamSchedulerScreen({super.key});
  @override
  State<ExamSchedulerScreen> createState() => _ExamSchedulerScreenState();
}

class _ExamSchedulerScreenState extends State<ExamSchedulerScreen> {
  final TextEditingController _subjectController = TextEditingController();
  final TextEditingController _keywordController = TextEditingController();
  TimeOfDay _startTime = const TimeOfDay(hour: 9, minute: 0);
  TimeOfDay _endTime = const TimeOfDay(hour: 17, minute: 0);
  final Set<String> _selectedApps = {};
  final List<String> _priorityKeywords = [
    'emergency',
    'urgent',
    'exam',
    'hospital',
  ];
  List<Map<String, dynamic>> scheduleList = [];
  bool _isLoading = true;
  bool _isReleased = false;

  final Map<String, String> _appPackages = {
    'Instagram': 'com.instagram.android',
    'WhatsApp': 'com.whatsapp',
    'Facebook': 'com.facebook.katana',
    'Twitter/X': 'com.twitter.android',
    'Discord': 'com.discord',
    'Snapchat': 'com.snapchat.android',
    'YouTube': 'com.google.android.youtube',
    'TikTok': 'com.zhiliaoapp.musically',
    'LinkedIn': 'com.linkedin.android',
    'Telegram': 'org.telegram.messenger',
  };

  @override
  void initState() {
    super.initState();
    _loadSchedules();
    _setupShakeDetection();
  }

  void _setupShakeDetection() {
    accelerometerEventStream().listen((AccelerometerEvent event) {
      double val = math.sqrt(
        event.x * event.x + event.y * event.y + event.z * event.z,
      );
      if (val > 30 && !_isReleased) {
        _triggerRelease();
      }
    });
  }

  void _triggerRelease() {
    if (!mounted) return;
    setState(() => _isReleased = true);

    // Set bypass to true
    platform.invokeMethod('tempRelease', {'active': true});

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Quick Release Active (30s)"),
        backgroundColor: Colors.orange,
      ),
    );

    // Use a reliable timer that doesn't care if the widget is still mounted
    Timer(const Duration(seconds: 30), () async {
      // ALWAYS call the platform method to reset the background service
      await platform.invokeMethod('tempRelease', {'active': false});

      if (mounted) {
        setState(() => _isReleased = false);
      }
    });
  }

  List<Map<String, dynamic>> get activeSchedules =>
      scheduleList.where((item) => item['isActive'] == true).toList();

  Future<void> _loadSchedules() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString('schedules');
    if (data != null) {
      setState(
        () => scheduleList = List<Map<String, dynamic>>.from(json.decode(data)),
      );
    }
    await _syncWithAndroid();
    setState(() => _isLoading = false);
  }

  Future<void> _saveSchedules() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('schedules', json.encode(scheduleList));
    await _syncWithAndroid();
  }

  Future<void> _showSessionSummary(String subject, int count) async {
    const AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
          'session_summary_channel',
          'Focus Summaries',
          importance: Importance.high,
          priority: Priority.high,
          color: Colors.teal,
          playSound: true,
        );

    const NotificationDetails platformChannelSpecifics = NotificationDetails(
      android: androidPlatformChannelSpecifics,
    );

    await flutterLocalNotificationsPlugin.show(
      0,
      'Focus Session Complete!',
      'Subject: $subject | $count notifications siloed.',
      platformChannelSpecifics,
    );
  }

  // In _ExamSchedulerScreenState

  Future<void> _syncWithAndroid() async {
    try {
      var active = activeSchedules;

      if (active.isEmpty) {
        await platform.invokeMethod('updateBlockList', {
          'apps': [],
          'keywords': _priorityKeywords,
          'startHour': 0, 'startMinute': 0,
          'endHour': 0, 'endMinute': 0, // Effectively disables blocking
        });
        return;
      }

      // CRITICAL: Get the time from the ACTUAL active session
      final currentSession = active.first;
      final startParts = currentSession['startTime'].split(':');
      final endParts = currentSession['endTime'].split(':');

      List<String> pkgs = [];
      for (var s in active) {
        for (var a in s['appsToDisable']) {
          pkgs.add(_appPackages[a] ?? a);
        }
      }

      await platform.invokeMethod('updateBlockList', {
        'apps': pkgs.toSet().toList(),
        'keywords': _priorityKeywords,
        'startHour': int.parse(startParts[0]),
        'startMinute': int.parse(startParts[1]),
        'endHour': int.parse(endParts[0]),
        'endMinute': int.parse(endParts[1]),
      });

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString("active_subject_name", currentSession['subject']);

      debugPrint(
        "Syncing Session: ${currentSession['subject']} (${currentSession['startTime']} to ${currentSession['endTime']})",
      );
    } catch (e) {
      debugPrint(e.toString());
    }
  }

  void _addSchedule() {
    _subjectController.clear();
    _keywordController.clear();
    _selectedApps.clear();
    _startTime = const TimeOfDay(hour: 9, minute: 0);
    _endTime = const TimeOfDay(hour: 17, minute: 0);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder:
          (ctx) => StatefulBuilder(
            builder:
                (context, setModalState) => Container(
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(30),
                    ),
                  ),
                  padding: EdgeInsets.only(
                    bottom: MediaQuery.of(ctx).viewInsets.bottom,
                    top: 25,
                    left: 25,
                    right: 25,
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'New Focus Session',
                          style: GoogleFonts.poppins(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 15),
                        TextField(
                          controller: _subjectController,
                          decoration: InputDecoration(
                            labelText: 'Subject',
                            filled: true,
                            fillColor: Colors.blueGrey[50],
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(15),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                        const SizedBox(height: 15),
                        Row(
                          children: [
                            Expanded(
                              child: _buildTimeTile(
                                "Start",
                                _startTime,
                                (t) => setModalState(() => _startTime = t),
                              ),
                            ),
                            const SizedBox(width: 15),
                            Expanded(
                              child: _buildTimeTile(
                                "End",
                                _endTime,
                                (t) => setModalState(() => _endTime = t),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        Text(
                          'Emergency Keywords',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                        Wrap(
                          spacing: 8,
                          children:
                              _priorityKeywords
                                  .map(
                                    (w) => Chip(
                                      label: Text(
                                        w,
                                        style: const TextStyle(fontSize: 11),
                                      ),
                                      onDeleted:
                                          () => setModalState(
                                            () => _priorityKeywords.remove(w),
                                          ),
                                    ),
                                  )
                                  .toList(),
                        ),
                        TextField(
                          controller: _keywordController,
                          decoration: InputDecoration(
                            hintText: 'Add word...',
                            suffixIcon: IconButton(
                              icon: const Icon(Icons.add),
                              onPressed: () {
                                if (_keywordController.text.isNotEmpty) {
                                  setModalState(
                                    () => _priorityKeywords.add(
                                      _keywordController.text
                                          .trim()
                                          .toLowerCase(),
                                    ),
                                  );
                                  _keywordController.clear();
                                }
                              },
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          'Block Apps',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Wrap(
                          spacing: 8,
                          children:
                              _appPackages.keys
                                  .map(
                                    (app) => FilterChip(
                                      label: Text(app),
                                      selected: _selectedApps.contains(app),
                                      onSelected:
                                          (v) => setModalState(
                                            () =>
                                                v
                                                    ? _selectedApps.add(app)
                                                    : _selectedApps.remove(app),
                                          ),
                                    ),
                                  )
                                  .toList(),
                        ),
                        const SizedBox(height: 25),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            minimumSize: const Size(double.infinity, 55),
                            backgroundColor: Colors.teal[800],
                            foregroundColor: Colors.white,
                          ),
                          onPressed: () {
                            if (_subjectController.text.isNotEmpty) {
                              final newSchedule = {
                                'subject': _subjectController.text,
                                'appsToDisable': _selectedApps.toList(),
                                'isActive': true,
                                'startTime':
                                    '${_startTime.hour}:${_startTime.minute}',
                                'endTime':
                                    '${_endTime.hour}:${_endTime.minute}',
                                'date': DateFormat.yMMMd().format(
                                  DateTime.now(),
                                ),
                              };

                              setState(() {
                                scheduleList.add(newSchedule);
                              });

                              _saveSchedules();

                              SharedPreferences.getInstance().then((prefs) {
                                prefs.setString(
                                  "active_subject_name",
                                  _subjectController.text,
                                );
                              });

                              Navigator.pop(context);
                            }
                          },
                          child: const Text('Start Session'),
                        ),
                        const SizedBox(height: 20),
                      ],
                    ),
                  ),
                ),
          ),
    );
  }

  Widget _buildTimeTile(String l, TimeOfDay t, Function(TimeOfDay) onPick) {
    return InkWell(
      onTap: () async {
        final time = await showTimePicker(context: context, initialTime: t);
        if (time != null) onPick(time);
      },
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.blueGrey[50],
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l, style: const TextStyle(fontSize: 11)),
            Text(
              t.format(context),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }

  void _showSessionDetails(BuildContext context, Map<String, dynamic> item) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(25),
            ),
            title: Row(
              children: [
                const Icon(Icons.bolt, color: Colors.teal),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    item['subject'],
                    style: GoogleFonts.poppins(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildDetailRow(
                  Icons.timer_outlined,
                  "Focus Window",
                  "${item['startTime']} to ${item['endTime']}",
                ),
                const SizedBox(height: 15),
                _buildDetailRow(
                  Icons.calendar_today_outlined,
                  "Created on",
                  item['date'] ?? "N/A",
                ),
                const SizedBox(height: 15),
                const Text(
                  "Siloed Applications:",
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children:
                      (item['appsToDisable'] as List).map((app) {
                        return Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            // ignore: deprecated_member_use
                            color: Colors.teal.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            app,
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.teal,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        );
                      }).toList(),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text(
                  "Close",
                  style: TextStyle(color: Colors.blueGrey),
                ),
              ),
            ],
          ),
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Colors.blueGrey[400]),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(fontSize: 10, color: Colors.blueGrey[300]),
            ),
            Text(
              value,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final activeItems = activeSchedules;
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text(
          "StackIt Focus",
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
        centerTitle: true,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          _buildPermissionBanner(),
          Expanded(
            child:
                _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : activeItems.isEmpty
                    ? _buildEmptyState()
                    : ListView.builder(
                      padding: const EdgeInsets.all(20),
                      itemCount: activeItems.length,
                      itemBuilder: (context, index) {
                        final item = activeItems[index];
                        return GlassCard(
                          child: ListTile(
                            onTap: () => _showSessionDetails(context, item),
                            title: Text(
                              item['subject'],
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            subtitle: Text(
                              "Window: ${item['startTime']} - ${item['endTime']}",
                            ),
                            trailing: IconButton(
                              icon: const Icon(
                                Icons.delete_outline,
                                color: Colors.redAccent,
                              ),
                              onPressed: () async {
                                final db = await _getDatabase();
                                // Use 'item' instead of 'active[i]'
                                final result = await db.rawQuery(
                                  'SELECT COUNT(*) as count FROM notifications WHERE subject = ?',
                                  [item['subject']],
                                );
                                int siloedCount =
                                    Sqflite.firstIntValue(result) ?? 0;

                                setState(() {
                                  // Logic to find the correct item in the master list
                                  int masterIndex = scheduleList.indexOf(item);
                                  if (masterIndex != -1) {
                                    scheduleList[masterIndex]['isActive'] =
                                        false;
                                  }
                                });

                                _saveSchedules();
                                _showSessionSummary(
                                  item['subject'],
                                  siloedCount,
                                );
                              },
                            ),
                          ),
                        );
                      },
                    ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addSchedule,
        backgroundColor: const Color(0xFF0F172A),
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text("New Zone", style: TextStyle(color: Colors.white)),
      ),
    );
  }

  Widget _buildPermissionBanner() {
    return Container(
      width: double.infinity,
      color: Colors.teal[50],
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          const Icon(Icons.info_outline, color: Colors.teal, size: 20),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              "Ensure Notification Access is ON.",
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
            ),
          ),
          TextButton(
            style: TextButton.styleFrom(
              backgroundColor: Colors.teal,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed:
                () => platform.invokeMethod('openNotificationListenerSettings'),
            child: const Text("SETTINGS", style: TextStyle(fontSize: 11)),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() => Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // ignore: deprecated_member_use
        Icon(Icons.shield_moon, size: 80, color: Colors.teal.withOpacity(0.1)),
        const Text(
          "No active zones",
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey),
        ),
      ],
    ),
  );
}

// --- VAULT SCREEN ---
class NotificationVaultScreen extends StatefulWidget {
  const NotificationVaultScreen({super.key});

  @override
  State<NotificationVaultScreen> createState() =>
      _NotificationVaultScreenState();
}

class _NotificationVaultScreenState extends State<NotificationVaultScreen> {
  Future<Map<String, List<Map<String, dynamic>>>> _getGroupedVault() async {
    final db = await _getDatabase();
    final List<Map<String, dynamic>> maps = await db.query(
      'notifications',
      orderBy: 'timestamp DESC',
    );
    Map<String, List<Map<String, dynamic>>> grouped = {};
    for (var row in maps) {
      String subject = row['subject'] ?? "General";
      if (!grouped.containsKey(subject)) grouped[subject] = [];
      grouped[subject]!.add(row);
    }
    return grouped;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          "Siloed History",
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        centerTitle: true,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
            ),
          ),
        ),
      ),
      body: FutureBuilder<Map<String, List<Map<String, dynamic>>>>(
        future: _getGroupedVault(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.data!.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Using an inventory/vault-related icon
                  Icon(
                    Icons.inventory_2_outlined,
                    size: 80,
                    color: Colors.blueGrey[100],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    "Your vault is empty",
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      color: Colors.blueGrey[300],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "Notifications siloed during focus\nsessions will appear here.",
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      color: Colors.blueGrey[200],
                    ),
                  ),
                ],
              ),
            );
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children:
                snapshot.data!.keys
                    .map((s) => _buildGroup(s, snapshot.data![s]!))
                    .toList(),
          );
        },
      ),
    );
  }

  Widget _buildGroup(String s, List<Map<String, dynamic>> msgs) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ExpansionTile(
        title: Text(s, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text("${msgs.length} stacked"),
        children:
            msgs
                .map(
                  (m) => ListTile(
                    title: Text(m['title'] ?? ""),
                    subtitle: Text(m['content'] ?? ""),
                    trailing: IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () async {
                        final db = await _getDatabase();
                        await db.delete(
                          'notifications',
                          where: 'id = ?',
                          whereArgs: [m['id']],
                        );
                        setState(() {});
                      },
                    ),
                  ),
                )
                .toList(),
      ),
    );
  }
}

// --- ANALYTICS SCREEN ---
class AnalyticsScreen extends StatelessWidget {
  const AnalyticsScreen({super.key});

  Future<Map<String, dynamic>> _getAllAnalyticsData() async {
    final db = await _getDatabase();
    final List<Map<String, dynamic>> appStats = await db.rawQuery(
      'SELECT pkg, COUNT(*) as count FROM notifications GROUP BY pkg ORDER BY count DESC',
    );
    final List<Map<String, dynamic>> hourlyStats = await db.rawQuery('''
      SELECT strftime('%H',CAST(timestamp AS INTEGER) / 1000, 'unixepoch', 'localtime') as hour, 
      COUNT(*) as count 
      FROM notifications 
      GROUP BY hour 
      ORDER BY hour ASC
    ''');
    return {'apps': appStats, 'hours': hourlyStats};
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text(
          "Focus Analytics",
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        centerTitle: true,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
            ),
          ),
        ),
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _getAllAnalyticsData(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(
              child: CircularProgressIndicator(color: Colors.teal),
            );
          }

          final apps = snapshot.data!['apps'] as List<Map<String, dynamic>>;
          final hours = snapshot.data!['hours'] as List<Map<String, dynamic>>;

          if (apps.isEmpty) return _buildEmptyAnalytics();

          int totalBlocked = apps.fold(
            0,
            (sum, item) => sum + (item['count'] as int),
          );
          int maxCount = apps
              .map((e) => e['count'] as int)
              .reduce((a, b) => a > b ? a : b);

          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              _buildSummaryDashboard(
                totalBlocked,
                totalBlocked,
              ), // 1 min saved per msg
              const SizedBox(height: 25),
              _buildTemporalHeatmap(hours), // ACTUALLY CALLING THE HEATMAP HERE
              const SizedBox(height: 25),
              Text(
                "Noise Density per App",
                style: GoogleFonts.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.blueGrey[800],
                ),
              ),
              const SizedBox(height: 15),
              ...apps
                  .map((item) => _buildAnalyticsCard(item, maxCount))
                  // ignore: unnecessary_to_list_in_spreads
                  .toList(),
            ],
          );
        },
      ),
    );
  }

  // Use your preferred version of _buildTemporalHeatmap here...
  Widget _buildTemporalHeatmap(List<Map<String, dynamic>> hourlyData) {
    return GlassCard(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Peak Distraction Times",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(height: 15),
            SizedBox(
              height: 80,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: List.generate(24, (index) {
                  var hourData = hourlyData.firstWhere(
                    (element) => int.parse(element['hour']) == index,
                    orElse: () => {'count': 0},
                  );
                  int count = hourData['count'] as int;
                  return Container(
                    width: 6,
                    height: (count * 8.0 + 4.0).clamp(4.0, 70.0),
                    decoration: BoxDecoration(
                      color:
                          count > 5
                              ? Colors.orange
                              // ignore: deprecated_member_use
                              : Colors.teal.withOpacity(0.4),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  );
                }),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryDashboard(int total, int saved) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Colors.teal, Color(0xFF0D9488)],
        ),
        borderRadius: BorderRadius.circular(25),
        boxShadow: [
          BoxShadow(
            // ignore: deprecated_member_use
            color: Colors.teal.withOpacity(0.3),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildStatItem("Stacked", total.toString(), Icons.layers),
          Container(width: 1, height: 40, color: Colors.white24),
          _buildStatItem("Focus Time", "${saved}m", Icons.timer),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: Colors.white70, size: 20),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 10),
        ),
      ],
    );
  }

  Widget _buildAnalyticsCard(Map<String, dynamic> item, int max) {
    String pkgName = item['pkg'].toString().split('.').last.toUpperCase();
    int count = item['count'] as int;
    double progress = count / (max == 0 ? 1 : max);

    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          // ignore: deprecated_member_use
          BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                pkgName,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: Color(0xFF1E293B),
                ),
              ),
              Text(
                "$count stacked",
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Colors.teal[700],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 10,
              // ignore: deprecated_member_use
              backgroundColor: Colors.teal.withOpacity(0.05),
              valueColor: AlwaysStoppedAnimation<Color>(
                progress > 0.7 ? Colors.orangeAccent : Colors.teal,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyAnalytics() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.bar_chart_rounded, size: 80, color: Colors.blueGrey[100]),
          const SizedBox(height: 16),
          Text(
            "No focus data captured",
            style: GoogleFonts.poppins(
              fontSize: 16,
              color: Colors.blueGrey[300],
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }
}

class GlassCard extends StatelessWidget {
  final Widget child;
  const GlassCard({super.key, required this.child});
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            // ignore: deprecated_member_use
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: child,
    );
  }
}
