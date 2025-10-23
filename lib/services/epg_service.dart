import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/epg_program.dart';

class EpgService {
  static const String _epgUrlsKey = 'epg_urls';
  static const String _epgCacheKey = 'epg_cache';
  static const String _epgCacheTimeKey = 'epg_cache_time';
  static const Duration _cacheExpiry = Duration(hours: 6);

  // 从 MoonTV API 获取 EPG URL 列表
  static Future<List<String>> fetchEpgUrls(String baseUrl) async {
    try {
      final url = '$baseUrl/api/live/sources';
      
      final prefs = await SharedPreferences.getInstance();
      final cookies = prefs.getString('cookies');
      
      final headers = <String, String>{
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      };
      
      if (cookies != null && cookies.isNotEmpty) {
        headers['Cookie'] = cookies;
      }
      
      final response = await http.get(Uri.parse(url), headers: headers);
      
      if (response.statusCode != 200) {
        throw Exception('请求失败: ${response.statusCode}');
      }

      final data = json.decode(utf8.decode(response.bodyBytes));
      
      if (data['success'] != true || data['data'] == null) {
        throw Exception('API 返回数据格式错误');
      }

      final List<dynamic> sources = data['data'];
      final epgUrls = <String>[];
      
      for (var source in sources) {
        if (source['disabled'] == true) continue;
        
        final epgUrl = source['epg'] as String?;
        if (epgUrl != null && epgUrl.isNotEmpty && !epgUrls.contains(epgUrl)) {
          epgUrls.add(epgUrl);
        }
      }
      
      // 保存 EPG URLs
      await prefs.setStringList(_epgUrlsKey, epgUrls);
      
      return epgUrls;
    } catch (e) {
      print('获取 EPG URLs 失败: $e');
      return [];
    }
  }

  // 获取频道的节目单
  static Future<List<EpgProgram>> getChannelPrograms(
    String channelName,
    String baseUrl,
  ) async {
    try {
      // 检查缓存
      final cachedPrograms = await _getCachedPrograms(channelName);
      if (cachedPrograms != null) {
        return cachedPrograms;
      }

      // 获取 EPG URLs
      var epgUrls = await _getStoredEpgUrls();
      if (epgUrls.isEmpty) {
        epgUrls = await fetchEpgUrls(baseUrl);
      }

      if (epgUrls.isEmpty) {
        return [];
      }

      // 尝试从每个 EPG URL 获取节目单
      for (var epgUrl in epgUrls) {
        try {
          final programs = await _fetchProgramsFromUrl(epgUrl, channelName);
          if (programs.isNotEmpty) {
            await _cachePrograms(channelName, programs);
            return programs;
          }
        } catch (e) {
          print('从 $epgUrl 获取节目单失败: $e');
          continue;
        }
      }

      return [];
    } catch (e) {
      print('获取节目单失败: $e');
      return [];
    }
  }

  // 从 URL 获取节目单
  static Future<List<EpgProgram>> _fetchProgramsFromUrl(
    String epgUrl,
    String channelName,
  ) async {
    final response = await http.get(Uri.parse(epgUrl)).timeout(
      const Duration(seconds: 30),
    );

    if (response.statusCode != 200) {
      throw Exception('请求失败: ${response.statusCode}');
    }

    final xmlContent = utf8.decode(response.bodyBytes);
    return _parseEpgXml(xmlContent, channelName);
  }

  // 解析 EPG XML
  static List<EpgProgram> _parseEpgXml(String xmlContent, String channelName) {
    try {
      final document = XmlDocument.parse(xmlContent);
      final programs = <EpgProgram>[];
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final tomorrow = today.add(const Duration(days: 1));

      // 查找匹配的频道
      for (var channel in document.findAllElements('channel')) {
        final displayName = channel.findElements('display-name').firstOrNull?.innerText ?? '';
        
        // 模糊匹配频道名称
        if (!_isChannelMatch(displayName, channelName)) {
          continue;
        }

        final channelId = channel.getAttribute('id');
        if (channelId == null) continue;

        // 获取该频道的所有节目
        for (var programme in document.findAllElements('programme')) {
          if (programme.getAttribute('channel') != channelId) continue;

          final startStr = programme.getAttribute('start');
          final stopStr = programme.getAttribute('stop');
          if (startStr == null || stopStr == null) continue;

          final startTime = _parseEpgTime(startStr);
          final endTime = _parseEpgTime(stopStr);

          // 只获取今天和明天的节目
          if (endTime.isBefore(today) || startTime.isAfter(tomorrow)) {
            continue;
          }

          final title = programme.findElements('title').firstOrNull?.innerText ?? '';
          final desc = programme.findElements('desc').firstOrNull?.innerText;

          programs.add(EpgProgram(
            channelId: channelId,
            title: title,
            startTime: startTime,
            endTime: endTime,
            description: desc,
          ));
        }

        // 找到匹配的频道后就返回
        if (programs.isNotEmpty) {
          programs.sort((a, b) => a.startTime.compareTo(b.startTime));
          return programs;
        }
      }

      return [];
    } catch (e) {
      print('解析 EPG XML 失败: $e');
      return [];
    }
  }

  // 解析 EPG 时间格式 (例如: 20231225120000 +0800)
  static DateTime _parseEpgTime(String timeStr) {
    try {
      // 移除时区信息
      final cleanTime = timeStr.split(' ')[0];
      
      final year = int.parse(cleanTime.substring(0, 4));
      final month = int.parse(cleanTime.substring(4, 6));
      final day = int.parse(cleanTime.substring(6, 8));
      final hour = int.parse(cleanTime.substring(8, 10));
      final minute = int.parse(cleanTime.substring(10, 12));
      final second = int.parse(cleanTime.substring(12, 14));

      return DateTime(year, month, day, hour, minute, second);
    } catch (e) {
      print('解析时间失败: $timeStr, $e');
      return DateTime.now();
    }
  }

  // 频道名称模糊匹配
  static bool _isChannelMatch(String epgName, String channelName) {
    final normalizedEpg = epgName.toLowerCase().replaceAll(RegExp(r'[\s\-_]'), '');
    final normalizedChannel = channelName.toLowerCase().replaceAll(RegExp(r'[\s\-_]'), '');
    
    return normalizedEpg.contains(normalizedChannel) || 
           normalizedChannel.contains(normalizedEpg);
  }

  // 获取存储的 EPG URLs
  static Future<List<String>> _getStoredEpgUrls() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_epgUrlsKey) ?? [];
  }

  // 缓存节目单
  static Future<void> _cachePrograms(
    String channelName,
    List<EpgProgram> programs,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheData = {
        'channelName': channelName,
        'programs': programs.map((p) => {
          'channelId': p.channelId,
          'title': p.title,
          'startTime': p.startTime.toIso8601String(),
          'endTime': p.endTime.toIso8601String(),
          'description': p.description,
        }).toList(),
      };
      
      await prefs.setString('${_epgCacheKey}_$channelName', json.encode(cacheData));
      await prefs.setString(
        '${_epgCacheTimeKey}_$channelName',
        DateTime.now().toIso8601String(),
      );
    } catch (e) {
      print('缓存节目单失败: $e');
    }
  }

  // 获取缓存的节目单
  static Future<List<EpgProgram>?> _getCachedPrograms(String channelName) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheTimeStr = prefs.getString('${_epgCacheTimeKey}_$channelName');
      
      if (cacheTimeStr == null) return null;
      
      final cacheTime = DateTime.parse(cacheTimeStr);
      if (DateTime.now().difference(cacheTime) > _cacheExpiry) {
        return null;
      }

      final cacheDataStr = prefs.getString('${_epgCacheKey}_$channelName');
      if (cacheDataStr == null) return null;

      final cacheData = json.decode(cacheDataStr);
      final programsData = cacheData['programs'] as List<dynamic>;
      
      return programsData.map((p) => EpgProgram(
        channelId: p['channelId'],
        title: p['title'],
        startTime: DateTime.parse(p['startTime']),
        endTime: DateTime.parse(p['endTime']),
        description: p['description'],
      )).toList();
    } catch (e) {
      print('读取缓存失败: $e');
      return null;
    }
  }
}
