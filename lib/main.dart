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
    version: 1,
    onCreate: (db, version) async {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS notifications (
          id INTEGER PRIMARY KEY AUTOINCREMENT, 
          pkg TEXT, 
          title TEXT, 
          content TEXT, 
          timestamp INTEGER
        )
      ''');
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
      home: const MainNavigationScreen(),
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
  List<String> _priorityKeywords = ['emergency', 'urgent', 'exam', 'hospital'];
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
      double val = math.sqrt(event.x * event.x + event.y * event.y + event.z * event.z);
      if (val > 35 && !_isReleased) {
        _triggerRelease();
      }
    });
  }

  void _triggerRelease() {
    if (!mounted) return;
    setState(() => _isReleased = true);
    platform.invokeMethod('tempRelease', {'active': true});
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Quick Release Active (30s)"),
        backgroundColor: Colors.orange,
      ),
    );
    Timer(const Duration(seconds: 30), () {
      if (mounted) {
        setState(() => _isReleased = false);
        platform.invokeMethod('tempRelease', {'active': false});
      }
    });
  }

  List<Map<String, dynamic>> get activeSchedules =>
      scheduleList.where((item) => item['isActive'] == true).toList();

  Future<void> _loadSchedules() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString('schedules');
    if (data != null)
      setState(
        () => scheduleList = List<Map<String, dynamic>>.from(json.decode(data)),
      );
    _syncWithAndroid();
    setState(() => _isLoading = false);
  }

  Future<void> _saveSchedules() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('schedules', json.encode(scheduleList));
    await _syncWithAndroid();
  }

  // In _ExamSchedulerScreenState

  Future<void> _syncWithAndroid() async {
    try {
      List<String> pkgs = [];
      var active = activeSchedules;

      if (active.isEmpty) {
        await platform.invokeMethod('updateBlockList', {
          'apps': [], 'keywords': _priorityKeywords,
          'startHour': 0,
          'startMinute': 0,
          'endHour': 23,
          'endMinute': 59, // Reset to full range
        });
        return;
      }

      for (var s in active) {
        for (var a in s['appsToDisable']) pkgs.add(_appPackages[a] ?? a);
      }

      // CRITICAL FIX: Ensure we use the latest selected times
      await platform.invokeMethod('updateBlockList', {
        'apps': pkgs.toSet().toList(),
        'keywords': _priorityKeywords,
        'startHour': _startTime.hour,
        'startMinute': _startTime.minute,
        'endHour': _endTime.hour,
        'endMinute': _endTime.minute,
      });

      debugPrint(
        "Syncing: ${_startTime.hour}:${_startTime.minute} to ${_endTime.hour}:${_endTime.minute}",
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
                              setState(
                                () => scheduleList.add({
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
                                }),
                              );
                              _saveSchedules();
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
                              onPressed: () {
                                setState(() {
                                  scheduleList[scheduleList.indexOf(
                                        item,
                                      )]['isActive'] =
                                      false;
                                });
                                _saveSchedules();
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
class NotificationVaultScreen extends StatelessWidget {
  const NotificationVaultScreen({super.key});
  Future<List<Map<String, dynamic>>> _getVault() async {
    final db = await _getDatabase();
    return await db.query('notifications', orderBy: 'timestamp DESC');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Notification Vault")),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _getVault(),
        builder: (context, snapshot) {
          if (!snapshot.hasData)
            return const Center(child: CircularProgressIndicator());
          if (snapshot.data!.isEmpty)
            return const Center(child: Text("Vault is empty."));
          return ListView.builder(
            itemCount: snapshot.data!.length,
            itemBuilder:
                (c, i) => GlassCard(
                  child: ListTile(
                    leading: const CircleAvatar(
                      child: Icon(Icons.notifications_paused),
                    ),
                    title: Text(
                      snapshot.data![i]['title'],
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(snapshot.data![i]['content']),
                    trailing: Text(
                      DateFormat.jm().format(
                        DateTime.fromMillisecondsSinceEpoch(
                          snapshot.data![i]['timestamp'],
                        ),
                      ),
                      style: const TextStyle(fontSize: 10),
                    ),
                  ),
                ),
          );
        },
      ),
    );
  }
}

// --- ANALYTICS SCREEN ---
class AnalyticsScreen extends StatelessWidget {
  const AnalyticsScreen({super.key});
  Future<List<Map<String, dynamic>>> _getStats() async {
    final db = await _getDatabase();
    return await db.rawQuery(
      'SELECT pkg, COUNT(*) as count FROM notifications GROUP BY pkg ORDER BY count DESC',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Focus Heatmap")),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _getStats(),
        builder: (context, snapshot) {
          if (!snapshot.hasData || snapshot.data!.isEmpty)
            return const Center(child: Text("No data yet."));
          int max = snapshot.data!
              .map((e) => e['count'] as int)
              .reduce((a, b) => a > b ? a : b);
          return ListView.builder(
            padding: const EdgeInsets.all(20),
            itemCount: snapshot.data!.length,
            itemBuilder:
                (c, i) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "${snapshot.data![i]['pkg'].split('.').last.toUpperCase()} (${snapshot.data![i]['count']})",
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 5),
                    LinearProgressIndicator(
                      value:
                          (snapshot.data![i]['count'] as int) /
                          (max == 0 ? 1 : max),
                      color: Colors.teal,
                      minHeight: 8,
                      borderRadius: BorderRadius.circular(5),
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
          );
        },
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
