// ignore_for_file: unnecessary_null_comparison
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

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

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'StackIt Focus',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        textTheme: GoogleFonts.poppinsTextTheme(),
      ),
      home: const ExamSchedulerScreen(),
    );
  }
}

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

  final Map<String, String> _appPackages = {
    // Global & General Social Media
    'Instagram': 'com.instagram.android',
    'WhatsApp': 'com.whatsapp',
    'Facebook': 'com.facebook.katana',
    'Twitter/X': 'com.twitter.android',
    'Discord': 'com.discord',
    'Snapchat': 'com.snapchat.android',
    'Reddit': 'com.reddit.frontpage',
    'Threads': 'com.instagram.barcelona',
    'Pinterest': 'com.pinterest',

    // Video & Entertainment (High Distraction)
    'YouTube': 'com.google.android.youtube',
    'TikTok': 'com.zhiliaoapp.musically',
    'Netflix': 'com.netflix.mediaclient',
    'Prime Video': 'com.amazon.avod.thirdpartyclient',
    'Hotstar': 'in.startv.hotstar',

    // Professional & Communication
    'LinkedIn': 'com.linkedin.android',
    'Telegram': 'org.telegram.messenger',
    'Slack': 'com.Slack',
    'Microsoft Teams': 'com.microsoft.teams',

    // Indian Popular Apps (2026 Trends)
    'ShareChat': 'com.dolphin.browser.sharechat',
    'Moj': 'in.mohalla.video',
    'Josh': 'com.eterno.shortvideos',
  };

  @override
  void initState() {
    super.initState();
    _loadSchedules();
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

  // Helper to keep the dialog UI consistent
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

  // FIX: Helper to get only active items
  List<Map<String, dynamic>> get activeSchedules =>
      scheduleList.where((item) => item['isActive'] == true).toList();

  Future<void> _loadSchedules() async {
    final prefs = await SharedPreferences.getInstance();
    final String? data = prefs.getString('schedules');
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
    _syncWithAndroid();
  }

  Future<void> _syncWithAndroid() async {
    try {
      List<String> packagesToBlock = [];
      for (var schedule in activeSchedules) {
        // Use filtered list
        List<String> apps = List<String>.from(schedule['appsToDisable'] ?? []);
        for (var app in apps) {
          packagesToBlock.add(_appPackages[app] ?? app);
        }
      }
      await platform.invokeMethod('updateBlockList', {
        'apps': packagesToBlock.toSet().toList(),
        'keywords': _priorityKeywords,
        'startHour': _startTime.hour,
        'startMinute': _startTime.minute,
        'endHour': _endTime.hour,
        'endMinute': _endTime.minute,
      });
    } on PlatformException catch (e) {
      debugPrint("Sync Error: ${e.message}");
    }
  }

  void _addSchedule() {
    // BUG FIX: Reset all inputs BEFORE opening the modal
    _subjectController.clear();
    _keywordController.clear();
    _selectedApps.clear();
    _startTime = const TimeOfDay(hour: 9, minute: 0);
    _endTime = const TimeOfDay(hour: 17, minute: 0);

    showModalBottomSheet(
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      context: context,
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
                            labelText: 'Subject Name',
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
                          style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                        Wrap(
                          spacing: 8,
                          children:
                              _priorityKeywords
                                  .map(
                                    (word) => Chip(
                                      label: Text(
                                        word,
                                        style: const TextStyle(fontSize: 11),
                                      ),
                                      onDeleted:
                                          () => setModalState(
                                            () =>
                                                _priorityKeywords.remove(word),
                                          ),
                                      deleteIconColor: Colors.redAccent,
                                    ),
                                  )
                                  .toList(),
                        ),
                        TextField(
                          controller: _keywordController,
                          decoration: InputDecoration(
                            hintText: 'Add urgent word...',
                            suffixIcon: IconButton(
                              icon: const Icon(Icons.add_circle),
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
                          'Block Distractions',
                          style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Wrap(
                          spacing: 8,
                          children:
                              _appPackages.keys.map((app) {
                                final isSelected = _selectedApps.contains(app);
                                return FilterChip(
                                  label: Text(app),
                                  selected: isSelected,
                                  onSelected:
                                      (val) => setModalState(
                                        () =>
                                            val
                                                ? _selectedApps.add(app)
                                                : _selectedApps.remove(app),
                                      ),
                                );
                              }).toList(),
                        ),
                        const SizedBox(height: 25),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            minimumSize: const Size(double.infinity, 55),
                            backgroundColor: Colors.teal[800],
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(15),
                            ),
                          ),
                          onPressed: () {
                            if (_subjectController.text.isNotEmpty) {
                              setState(() {
                                scheduleList.add({
                                  'subject': _subjectController.text,
                                  'appsToDisable': _selectedApps.toList(),
                                  'isActive': true,
                                  'startTime':
                                      '${_startTime.hour}:${_startTime.minute}', // Save specific time for this session
                                  'endTime':
                                      '${_endTime.hour}:${_endTime.minute}',
                                });
                              });
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

  Widget _buildTimeTile(
    String label,
    TimeOfDay time,
    Function(TimeOfDay) onPick,
  ) {
    return InkWell(
      onTap: () async {
        final t = await showTimePicker(context: context, initialTime: time);
        if (t != null) onPick(t);
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
            Text(
              label,
              style: const TextStyle(fontSize: 11, color: Colors.blueGrey),
            ),
            Text(
              time.format(context),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final activeItems = activeSchedules; // FIX: Calculate once per build

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
        actions: [
          IconButton(
            icon: const Icon(Icons.settings, color: Colors.white),
            onPressed:
                () => platform.invokeMethod('openNotificationListenerSettings'),
          ),
        ],
      ),
      // BUG FIX: Checking activeItems.isEmpty ensures the empty state appears after deletion
      body:
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
                      // Makes the entire card clickable
                      onTap: () => _showSessionDetails(context, item),
                      title: Text(
                        item['subject'],
                        style: const TextStyle(fontWeight: FontWeight.bold),
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
                            int originalIndex = scheduleList.indexOf(item);
                            scheduleList[originalIndex]['isActive'] = false;
                          });
                          _saveSchedules();
                        },
                      ),
                    ),
                  );
                },
              ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addSchedule,
        backgroundColor: const Color(0xFF0F172A),
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text("New Zone", style: TextStyle(color: Colors.white)),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      width: double.infinity,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(30),
            decoration: BoxDecoration(
              color: Colors.teal.withOpacity(0.05),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.notifications_paused_rounded,
              size: 80,
              color: Colors.teal.withOpacity(0.3),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            "No Active Focus Zones",
            style: GoogleFonts.poppins(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              "Notifications are flowing normally. Reclaim your time by creating a focus session.",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.blueGrey[400]),
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
