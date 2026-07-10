import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ApiService {
  static const String host = 'https://smarthrm.gpstrackerbd.com';
  static const String _baseUrl = '$host/api/mobile/v1';

  /// Builds a full URL for an employee photo (API returns just the filename).
  static String photoUrl(String? file) {
    if (file == null || file.trim().isEmpty) return '';
    if (file.startsWith('http')) return file;
    return '$host/storage/employee/$file';
  }
  static const String _tokenKey = 'smarthr_token';
  static const String _userIdKey = 'smarthr_user_id';
  static const String _roleKey = 'smarthr_role';

  static Future<String> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_tokenKey) ?? '';
  }

  static Future<void> setToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
  }

  static Future<String> getUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_userIdKey) ?? '';
  }

  static Future<void> setUserId(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_userIdKey, id);
  }

  static Future<String> getRole() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_roleKey) ?? 'employee';
  }

  static Future<void> setRole(String role) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_roleKey, role);
  }

  static Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_userIdKey);
    await prefs.remove(_roleKey);
  }

  static Future<Map<String, dynamic>> _req(
    String method,
    String path, {
    Map<String, String>? fields,
    bool auth = true,
  }) async {
    final uri = Uri.parse('$_baseUrl$path');
    final headers = <String, String>{};
    if (auth) {
      final token = await getToken();
      if (token.isNotEmpty) headers['Authorization'] = 'Bearer $token';
    }

    http.Response res;
    if (method == 'POST' && fields != null) {
      final req = http.MultipartRequest('POST', uri);
      req.headers.addAll(headers);
      req.fields.addAll(fields);
      final streamed = await req.send().timeout(const Duration(seconds: 15));
      res = await http.Response.fromStream(streamed);
    } else if (method == 'POST') {
      res = await http.post(uri, headers: headers).timeout(const Duration(seconds: 15));
    } else {
      res = await http.get(uri, headers: headers).timeout(const Duration(seconds: 15));
    }

    final data = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode >= 400) {
      final msg = data['message'] ?? data['error'] ?? 'Server error ${res.statusCode}';
      throw Exception(msg.toString());
    }
    return data;
  }

  // Auth
  static Future<Map<String, dynamic>> checkUser(String email) =>
      _req('POST', '/checkUser', fields: {'email': email}, auth: false);

  static Future<Map<String, dynamic>> login(String email, String password) =>
      _req('POST', '/login', fields: {'email': email, 'password': password}, auth: false);

  static Future<Map<String, dynamic>> verifyOtp(String userId, String otp) =>
      _req('POST', '/otp-verify?user_id=$userId&otp=$otp', auth: false);

  static Future<Map<String, dynamic>> logout() => _req('GET', '/logout');

  static Future<Map<String, dynamic>> changePassword(String oldPass, String newPass, String confirm) =>
      _req('POST', '/change-password', fields: {
        'old_password': oldPass,
        'password': newPass,
        'password_confirmation': confirm,
      });

  // Office clock
  static Future<Map<String, dynamic>> todaySchedule() => _req('GET', '/today-schedule');
  static Future<Map<String, dynamic>> clockIn(Map<String, String> params) {
    final qs = params.entries.map((e) => '${e.key}=${Uri.encodeComponent(e.value)}').join('&');
    return _req('GET', '/time_in?$qs');
  }
  static Future<Map<String, dynamic>> clockOut() => _req('GET', '/time_out');

  // Location
  static Future<Map<String, dynamic>> locationCreate(String batch, String lat, String lon) =>
      _req('POST', '/location_create?batch_no=$batch&lat=$lat&lon=$lon');
  static Future<Map<String, dynamic>> locationHistory(String uid, {String start = '', String end = ''}) =>
      _req('GET', '/map_history/$uid?startDate=$start&endDate=$end');
  static Future<Map<String, dynamic>> lastLocation(String uid) =>
      _req('GET', '/userLastLocation/$uid');

  // Super Admin
  static Future<Map<String, dynamic>> myTeam() => _req('GET', '/my_team');
  static Future<Map<String, dynamic>> teamLastLocation(String uid) =>
      _req('GET', '/team_last_location/$uid');
  static Future<Map<String, dynamic>> teamMapHistory(String uid, {String start = '', String end = ''}) =>
      _req('GET', '/team_map_history/$uid?startDate=$start&endDate=$end');

  // Employee
  static Future<Map<String, dynamic>> myInfo() => _req('GET', '/my_info');
  static Future<Map<String, dynamic>> holidays() => _req('GET', '/holiday');
  static Future<Map<String, dynamic>> rules() => _req('GET', '/rules');
  static Future<Map<String, dynamic>> document() => _req('GET', '/document');
  static Future<Map<String, dynamic>> tutorial() => _req('GET', '/tutorial');
  static Future<Map<String, dynamic>> advanceSalary() => _req('GET', '/advance_salary');
  static Future<Map<String, dynamic>> notices() => _req('GET', '/notice');
  static Future<Map<String, dynamic>> noticeDetail(int id) => _req('GET', '/notice/$id');
  static Future<Map<String, dynamic>> payrollList({String status = 'all'}) =>
      _req('GET', '/pay_roll?status=$status');
  static Future<Map<String, dynamic>> payrollDetail(int id) => _req('GET', '/pay_roll/$id');

  // Attendance
  static Future<Map<String, dynamic>> attendanceList({String start = '', String end = ''}) =>
      _req('GET', '/my_attendance_list?startDate=$start&endDate=$end');
  static Future<Map<String, dynamic>> attendanceApps({String start = '', String end = '', String type = ''}) =>
      _req('GET', '/my_attendance_application_list?startDate=$start&endDate=$end${type.isNotEmpty ? '&type=${Uri.encodeComponent(type)}' : ''}');

  // Leaves
  static Future<Map<String, dynamic>> leaveBalance() => _req('GET', '/attendance_leave/list');
  static Future<Map<String, dynamic>> leaveApps({String start = '', String end = ''}) =>
      _req('GET', '/leave_applications?startDate=$start&endDate=$end');
  static Future<Map<String, dynamic>> applyLeave(String type, List<String> dates, String details) async {
    final req = http.MultipartRequest('POST', Uri.parse('$_baseUrl/leave_application'));
    final token = await getToken();
    if (token.isNotEmpty) req.headers['Authorization'] = 'Bearer $token';
    req.fields['type'] = type;
    req.fields['details'] = details;
    for (int i = 0; i < dates.length; i++) {
      req.fields['date_list[$i][date]'] = dates[i];
    }
    final streamed = await req.send().timeout(const Duration(seconds: 15));
    final res = await http.Response.fromStream(streamed);
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode >= 400) throw Exception(data['message'] ?? 'Failed');
    return data;
  }

  // Overtime
  static Future<Map<String, dynamic>> otBalance({String start = '', String end = ''}) =>
      _req('GET', '/attendance_ot_list/list?startDate=$start&endDate=$end');
  static Future<Map<String, dynamic>> otApps({String start = '', String end = '', String type = ''}) =>
      _req('GET', '/ot_applications?startDate=$start&endDate=$end${type.isNotEmpty ? '&type=${Uri.encodeComponent(type)}' : ''}');
  static Future<Map<String, dynamic>> applyOt(String attId, Map<String, String> fields) =>
      _req('POST', '/ot_applications/$attId', fields: fields);

  // Attendance correction requests (mirror website Action column).
  // In/Out Time Modify: type='In Time Modify' (sends time_in) or 'Out Time Modify' (sends time_out).
  static Future<Map<String, dynamic>> applyTimeModify(String attId, String type, String time, String details) {
    final fields = {'type': type, 'details': details, 'office_schedule': ''};
    if (type == 'In Time Modify') {
      fields['time_in'] = time;
    } else {
      fields['time_out'] = time;
    }
    return _req('POST', '/in_time_out_time_modify/$attId', fields: fields);
  }

  // Late In / Early Out excuse: type='Late In' or 'Early Out'.
  static Future<Map<String, dynamic>> applyLateInEarlyOut(String attId, String type, String details) =>
      _req('POST', '/late_in_early_out_apply/$attId', fields: {'type': type, 'details': details});

  // ── Field-sales CRM (mirrors website Client/Task modules) ────────────────
  static Future<Map<String, dynamic>> clients() => _req('GET', '/client');
  static Future<Map<String, dynamic>> clientCreate(Map<String, String> f) => _req('POST', '/client', fields: f);
  static Future<Map<String, dynamic>> clientUpdate(String id, Map<String, String> f) => _req('POST', '/client/update/$id', fields: f);
  static Future<Map<String, dynamic>> clientDelete(String id) => _req('GET', '/client/delete/$id');

  // filter: '', 'pending', 'complete', 'self_task'
  static Future<Map<String, dynamic>> tasks({String filter = ''}) =>
      _req('GET', '/task${filter.isNotEmpty ? '?filter=$filter' : ''}');
  static Future<Map<String, dynamic>> taskCreate(Map<String, String> f) => _req('POST', '/task', fields: f);
  static Future<Map<String, dynamic>> taskComplete(String id, String note) =>
      _req('POST', '/task/complete/$id', fields: {'note': note});
  static Future<Map<String, dynamic>> taskUncomplete(String id) => _req('GET', '/task/uncomplete/$id');
  static Future<Map<String, dynamic>> taskDelete(String id) => _req('GET', '/task/delete/$id');

  // Lookup tables for CRM forms
  static Future<Map<String, dynamic>> districts() => _req('GET', '/district');
  static Future<Map<String, dynamic>> zones() => _req('GET', '/zone');
  static Future<Map<String, dynamic>> areas() => _req('GET', '/area');
  static Future<Map<String, dynamic>> saleStatuses() => _req('GET', '/saleStatus');
  static Future<Map<String, dynamic>> taskTypes() => _req('GET', '/tasktype');
}
