// Notifications on the phone: a daily practice reminder (keeps the streak) and Mockfy's own news
// (friend requests, results, Mock Day...) shown as phone notifications when the app opens or comes back.
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'api.dart';

class Notify {
  Notify._();
  static final Notify I = Notify._();
  final _plugin = FlutterLocalNotificationsPlugin();
  final unread = ValueNotifier<int>(0);
  bool _ready = false;

  static const _channel = AndroidNotificationDetails('mockfy', 'Mockfy',
      channelDescription: 'Reminders and news from Mockfy', importance: Importance.defaultImportance, priority: Priority.defaultPriority);

  Future<void> init() async {
    if (_ready) return;
    tzdata.initializeTimeZones();
    await _plugin.initialize(const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')));
    _ready = true;
  }

  Future<bool> askPermission() async {
    await init();
    final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    return await android?.requestNotificationsPermission() ?? true;
  }

  /// The daily reminder at [hour]:[minute] on this phone's clock; off when [on] is false.
  Future<void> setReminder(bool on, {int hour = 20, int minute = 0}) async {
    await init();
    await _plugin.cancel(1);
    final p = await SharedPreferences.getInstance();
    await p.setBool('reminder', on);
    await p.setInt('reminderHour', hour);
    await p.setInt('reminderMinute', minute);
    if (!on) return;
    await askPermission();
    final now = DateTime.now();
    var at = DateTime(now.year, now.month, now.day, hour, minute);
    if (!at.isAfter(now)) at = at.add(const Duration(days: 1));
    await _plugin.zonedSchedule(
      1,
      'Keep your streak going',
      'A few minutes of Daily English today keeps your streak alive.',
      tz.TZDateTime.from(at, tz.UTC),
      const NotificationDetails(android: _channel),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  Future<({bool on, int hour, int minute})> reminder() async {
    final p = await SharedPreferences.getInstance();
    return (on: p.getBool('reminder') ?? false, hour: p.getInt('reminderHour') ?? 20, minute: p.getInt('reminderMinute') ?? 0);
  }

  /// Mockfy's notifications: the unread count for the badge, and the new ones as phone notifications.
  Future<void> sync() async {
    try {
      await init();
      final r = await Api.I.get('/api/notifications');
      final items = (r['items'] as List? ?? []).cast<Map>();
      final unseen = items.where((n) => n['unread'] == true).toList();
      unread.value = unseen.length;
      final p = await SharedPreferences.getInstance();
      final shown = (p.getStringList('shownNotifications') ?? []).toSet();
      for (final n in unseen.take(3)) {
        final id = '${n['id']}';
        if (shown.contains(id)) continue;
        shown.add(id);
        await _plugin.show(1000 + (int.tryParse(id) ?? id.hashCode) % 100000, '${n['title'] ?? 'Mockfy'}', '${n['body'] ?? ''}',
            const NotificationDetails(android: _channel));
      }
      await p.setStringList('shownNotifications', shown.toList().reversed.take(200).toList());
    } catch (_) { /* offline: the next sync shows them */ }
  }
}
