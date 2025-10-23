import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/live_channel.dart';

class LiveChannelService {
  static const String _channelsKey = 'live_channels';
  static const String _sourceUrlKey = 'live_source_url';
  static const String _favoritesKey = 'live_favorites';

  // 获取频道列表
  static Future<List<LiveChannel>> getChannels() async {
    final prefs = await SharedPreferences.getInstance();
    final channelsJson = prefs.getString(_channelsKey);
    
    if (channelsJson == null || channelsJson.isEmpty) {
      return [];
    }

    try {
      final List<dynamic> decoded = json.decode(channelsJson);
      final channels = decoded.map((e) => LiveChannel.fromJson(e)).toList();
      
      // 加载收藏状态
      final favorites = await _getFavoriteIds();
      for (var channel in channels) {
        channel.isFavorite = favorites.contains(channel.id);
      }
      
      return channels;
    } catch (e) {
      print('解析频道列表失败: $e');
      return [];
    }
  }

  // 保存频道列表
  static Future<void> saveChannels(List<LiveChannel> channels) async {
    final prefs = await SharedPreferences.getInstance();
    final channelsJson = json.encode(channels.map((e) => e.toJson()).toList());
    await prefs.setString(_channelsKey, channelsJson);
  }

  // 获取频道源地址
  static Future<String?> getSourceUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_sourceUrlKey);
  }

  // 保存频道源地址
  static Future<void> saveSourceUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_sourceUrlKey, url);
  }

  // 从 MoonTV API 获取直播源
  static Future<List<LiveChannel>> fetchFromMoonTV(String baseUrl) async {
    try {
      final url = '$baseUrl/api/live/sources';
      
      // 获取认证 cookies
      final prefs = await SharedPreferences.getInstance();
      final cookies = prefs.getString('cookies');
      
      // 构建请求头
      final headers = <String, String>{
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      };
      
      if (cookies != null && cookies.isNotEmpty) {
        headers['Cookie'] = cookies;
      }
      
      final response = await http.get(Uri.parse(url), headers: headers);
      
      if (response.statusCode == 401) {
        throw Exception('未授权，请先登录');
      }
      
      if (response.statusCode != 200) {
        throw Exception('请求失败: ${response.statusCode}');
      }

      final data = json.decode(utf8.decode(response.bodyBytes));
      
      if (data['success'] != true || data['data'] == null) {
        throw Exception('API 返回数据格式错误');
      }

      final List<dynamic> sources = data['data'];
      final allChannels = <LiveChannel>[];
      int channelId = 0;
      
      // 遍历每个 M3U 源
      for (var source in sources) {
        if (source['disabled'] == true) continue;
        
        final m3uUrl = source['url'] as String?;
        if (m3uUrl == null || m3uUrl.isEmpty) continue;
        
        try {
          // 下载 M3U 文件
          final m3uHeaders = <String, String>{};
          final ua = source['ua'] as String?;
          if (ua != null && ua.isNotEmpty) {
            m3uHeaders['User-Agent'] = ua;
          }
          
          final m3uResponse = await http.get(
            Uri.parse(m3uUrl),
            headers: m3uHeaders,
          ).timeout(const Duration(seconds: 10));
          
          if (m3uResponse.statusCode != 200) continue;
          
          final m3uContent = utf8.decode(m3uResponse.bodyBytes);
          
          // 解析 M3U 内容
          final channels = _parseM3uContent(m3uContent, channelId);
          allChannels.addAll(channels);
          channelId += channels.length;
        } catch (e) {
          print('下载 M3U 源失败 [${source['name']}]: $e');
          continue;
        }
      }
      
      if (allChannels.isEmpty) {
        throw Exception('未找到有效频道');
      }

      await saveChannels(allChannels);
      await saveSourceUrl(baseUrl);
      
      return allChannels;
    } catch (e) {
      throw Exception('从 MoonTV 获取失败: $e');
    }
  }

  // 解析 M3U 内容
  static List<LiveChannel> _parseM3uContent(String content, int startId) {
    final channels = <LiveChannel>[];
    final lines = content.split('\n');
    final channelMap = <String, List<LiveChannel>>{};
    
    LiveChannel? currentChannel;
    int id = startId;

    for (var line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;

      if (trimmed.startsWith('#EXTINF')) {
        final nameMatch = RegExp(r'tvg-name="([^"]+)"').firstMatch(trimmed);
        final logoMatch = RegExp(r'tvg-logo="([^"]+)"').firstMatch(trimmed);
        final numMatch = RegExp(r'tvg-chno="([^"]+)"').firstMatch(trimmed);
        final groupMatch = RegExp(r'group-title="([^"]+)"').firstMatch(trimmed);
        
        final parts = trimmed.split(',');
        final title = parts.length > 1 ? parts.last.trim() : '';
        final name = nameMatch?.group(1)?.trim() ?? title;
        
        currentChannel = LiveChannel(
          id: id++,
          name: name,
          title: title,
          logo: logoMatch?.group(1)?.trim() ?? '',
          uris: [],
          group: groupMatch?.group(1)?.trim() ?? '未分组',
          number: int.tryParse(numMatch?.group(1)?.trim() ?? '') ?? -1,
        );
      } else if (!trimmed.startsWith('#') && currentChannel != null) {
        final key = '${currentChannel.group}_${currentChannel.name}';
        if (!channelMap.containsKey(key)) {
          channelMap[key] = [currentChannel];
        }
        channelMap[key]!.last.uris.add(trimmed);
      }
    }

    // 合并相同频道的多个源
    for (var entry in channelMap.entries) {
      final allUris = entry.value.expand((c) => c.uris).toList();
      final channel = entry.value.first.copyWith(uris: allUris);
      channels.add(channel);
    }

    return channels;
  }



  // 按分组获取频道
  static Future<List<LiveChannelGroup>> getChannelsByGroup() async {
    final channels = await getChannels();
    final groupMap = <String, List<LiveChannel>>{};

    for (var channel in channels) {
      if (!groupMap.containsKey(channel.group)) {
        groupMap[channel.group] = [];
      }
      groupMap[channel.group]!.add(channel);
    }

    return groupMap.entries
        .map((e) => LiveChannelGroup(name: e.key, channels: e.value))
        .toList();
  }

  // 获取收藏的频道ID列表
  static Future<Set<int>> _getFavoriteIds() async {
    final prefs = await SharedPreferences.getInstance();
    final favoritesJson = prefs.getString(_favoritesKey);
    
    if (favoritesJson == null || favoritesJson.isEmpty) {
      return {};
    }

    try {
      final List<dynamic> decoded = json.decode(favoritesJson);
      return decoded.map((e) => e as int).toSet();
    } catch (e) {
      return {};
    }
  }

  // 保存收藏的频道ID列表
  static Future<void> _saveFavoriteIds(Set<int> ids) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_favoritesKey, json.encode(ids.toList()));
  }

  // 切换收藏状态
  static Future<void> toggleFavorite(int channelId) async {
    final favorites = await _getFavoriteIds();
    
    if (favorites.contains(channelId)) {
      favorites.remove(channelId);
    } else {
      favorites.add(channelId);
    }
    
    await _saveFavoriteIds(favorites);
  }

  // 获取收藏的频道
  static Future<List<LiveChannel>> getFavoriteChannels() async {
    final channels = await getChannels();
    return channels.where((c) => c.isFavorite).toList();
  }


}
