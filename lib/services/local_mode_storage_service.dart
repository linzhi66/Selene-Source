import 'dart:convert';

import 'package:hive/hive.dart';
import 'package:selene/models/favorite_item.dart';
import 'package:selene/models/live_source.dart';
import 'package:selene/models/play_record.dart';
import 'package:selene/models/search_resource.dart';

/// 本地模式存储服务
/// 用于持久化存储本地模式下的订阅信息、播放记录、收藏夹和搜索记录
class LocalModeStorageService {
  static const String _boxName = 'local_mode_data';
  static const String _subscriptionUrlKey = 'local_mode_subscription_url';
  static const String _searchSourcesKey = 'local_mode_search_sources';
  static const String _liveSourcesKey = 'local_mode_live_sources';
  static const String _playRecordsKey = 'local_mode_play_records';
  static const String _favoritesKey = 'local_mode_favorites';
  static const String _searchHistoryKey = 'local_mode_search_history';

  // 内存缓存
  static List<FavoriteItem>? _favoritesCache;

  // ==================== 订阅 URL ====================

  /// 保存订阅 URL
  static Future<void> saveSubscriptionUrl(String url) async {
    await Hive.box<String>(_boxName).put(_subscriptionUrlKey, url);
  }

  /// 获取订阅 URL
  static Future<String?> getSubscriptionUrl() async {
    return Hive.box<String>(_boxName).get(_subscriptionUrlKey);
  }

  /// 清除订阅 URL
  static Future<void> clearSubscriptionUrl() async {
    await Hive.box<String>(_boxName).delete(_subscriptionUrlKey);
  }

  // ==================== 搜索源列表 ====================

  /// 保存搜索源列表
  static Future<void> saveSearchSources(List<SearchResource> resources) async {
    await Hive.box<String>(_boxName).put(_searchSourcesKey,
        jsonEncode(resources.map((r) => r.toJson()).toList()));
  }

  /// 获取搜索源列表
  static Future<List<SearchResource>> getSearchSources() async {
    final jsonString = Hive.box<String>(_boxName).get(_searchSourcesKey);
    if (jsonString == null || jsonString.isEmpty) {
      return [];
    }
    try {
      final jsonList = jsonDecode(jsonString) as List;
      return jsonList.map((json) => SearchResource.fromJson(json)).toList();
    } catch (e) {
      return [];
    }
  }

  /// 清除搜索源列表
  static Future<void> clearSearchSources() async {
    await Hive.box<String>(_boxName).delete(_searchSourcesKey);
  }

  // ==================== 直播源 ====================

  /// 保存直播源列表
  static Future<void> saveLiveSources(List<LiveSource> sources) async {
    await Hive.box<String>(_boxName).put(
        _liveSourcesKey, jsonEncode(sources.map((s) => s.toJson()).toList()));
  }

  /// 获取直播源列表
  static Future<List<LiveSource>> getLiveSources() async {
    final jsonString = Hive.box<String>(_boxName).get(_liveSourcesKey);
    if (jsonString == null || jsonString.isEmpty) {
      return [];
    }
    try {
      final jsonList = jsonDecode(jsonString) as List;
      return jsonList.map((json) => LiveSource.fromJson(json)).toList();
    } catch (e) {
      return [];
    }
  }

  /// 清除直播源
  static Future<void> clearLiveSources() async {
    await Hive.box<String>(_boxName).delete(_liveSourcesKey);
  }

  // ==================== 播放记录 ====================

  /// 保存播放记录列表
  static Future<void> savePlayRecords(List<PlayRecord> records) async {
    final Map<String, dynamic> recordsMap = {};
    for (var record in records) {
      recordsMap['${record.source}+${record.id}'] = record.toJson();
    }
    await Hive.box<String>(_boxName)
        .put(_playRecordsKey, jsonEncode(recordsMap));
  }

  /// 获取播放记录列表
  static Future<List<PlayRecord>> getPlayRecords() async {
    final jsonString = Hive.box<String>(_boxName).get(_playRecordsKey);
    if (jsonString == null || jsonString.isEmpty) {
      return [];
    }
    try {
      final records = <PlayRecord>[];
      jsonDecode(jsonString).forEach((String key, dynamic value) {
        records.add(PlayRecord.fromJson(key, value));
      });
      // 按保存时间降序排序
      records.sort((a, b) => b.saveTime.compareTo(a.saveTime));
      return records;
    } catch (e) {
      return [];
    }
  }

  /// 添加或更新单条播放记录
  static Future<void> savePlayRecord(PlayRecord record) async {
    final records = await getPlayRecords();
    // 移除相同的记录（如果存在）
    records.removeWhere((r) => r.source == record.source && r.id == record.id);
    // 添加新记录到列表开头
    records.insert(0, record);
    // 保存更新后的列表
    await savePlayRecords(records);
  }

  /// 删除单条播放记录
  static Future<void> deletePlayRecord(String source, String id) async {
    final records = await getPlayRecords();
    records.removeWhere((r) => r.source == source && r.id == id);
    await savePlayRecords(records);
  }

  /// 清除所有播放记录
  static Future<void> clearPlayRecords() async {
    await Hive.box<String>(_boxName).delete(_playRecordsKey);
  }

  // ==================== 收藏夹 ====================

  /// 保存收藏夹列表
  static Future<void> saveFavorites(List<FavoriteItem> favorites) async {
    final Map<String, dynamic> favoritesMap = {};
    for (var favorite in favorites) {
      final key = '${favorite.source}+${favorite.id}';
      favoritesMap[key] = favorite.toJson();
    }
    await Hive.box<String>(_boxName)
        .put(_favoritesKey, jsonEncode(favoritesMap));
    _favoritesCache = List.from(favorites);
  }

  /// 获取收藏夹列表
  static Future<List<FavoriteItem>> getFavorites() async {
    final jsonString = Hive.box<String>(_boxName).get(_favoritesKey);
    if (jsonString == null || jsonString.isEmpty) {
      _favoritesCache = [];
      return [];
    }
    try {
      final favorites = <FavoriteItem>[];
      jsonDecode(jsonString).forEach((String key, dynamic value) {
        favorites.add(FavoriteItem.fromJson(key, value));
      });
      // 按保存时间降序排序
      favorites.sort((a, b) => b.saveTime.compareTo(a.saveTime));
      _favoritesCache = favorites;
      return favorites;
    } catch (e) {
      _favoritesCache = [];
      return [];
    }
  }

  /// 添加或更新单个收藏项
  static Future<void> saveFavorite(FavoriteItem favorite) async {
    final favorites = await getFavorites();
    // 移除相同的收藏项（如果存在）
    favorites
        .removeWhere((f) => f.source == favorite.source && f.id == favorite.id);
    // 添加新收藏项到列表开头
    favorites.insert(0, favorite);
    // 保存更新后的列表
    await saveFavorites(favorites);
  }

  /// 删除单个收藏项
  static Future<void> deleteFavorite(String source, String id) async {
    final favorites = await getFavorites();
    favorites.removeWhere((f) => f.source == source && f.id == id);
    await saveFavorites(favorites);
  }

  /// 检查是否已收藏（异步）
  static Future<bool> isFavorite(String source, String id) async {
    final favorites = await getFavorites();
    return favorites.any((f) => f.source == source && f.id == id);
  }

  /// 同步检查是否已收藏（从内存缓存读取）
  static bool isFavoriteSync(String source, String id) {
    if (_favoritesCache == null) {
      getFavorites();
      return false;
    }
    return _favoritesCache!.any((f) => f.source == source && f.id == id);
  }

  /// 清除所有收藏
  static Future<void> clearFavorites() async {
    await Hive.box<String>(_boxName).delete(_favoritesKey);
    _favoritesCache = [];
  }

  // ==================== 搜索记录 ====================

  /// 保存搜索记录列表
  static Future<void> saveSearchHistory(List<String> history) async {
    await Hive.box<String>(_boxName)
        .put(_searchHistoryKey, jsonEncode(history));
  }

  /// 获取搜索记录列表
  static Future<List<String>> getSearchHistory() async {
    final jsonString = Hive.box<String>(_boxName).get(_searchHistoryKey);
    if (jsonString == null || jsonString.isEmpty) {
      return [];
    }
    try {
      final List<dynamic> jsonList = jsonDecode(jsonString);
      return jsonList.map((e) => e.toString()).toList();
    } catch (e) {
      return [];
    }
  }

  /// 添加搜索记录
  static Future<void> addSearchHistory(String keyword) async {
    if (keyword.trim().isEmpty) return;
    final history = await getSearchHistory();
    // 移除重复的关键词
    history.remove(keyword);
    // 添加到列表开头
    history.insert(0, keyword);
    // 限制最多保存 50 条记录
    if (history.length > 20) {
      history.removeRange(20, history.length);
    }
    await saveSearchHistory(history);
  }

  /// 删除单条搜索记录
  static Future<void> deleteSearchHistory(String keyword) async {
    final history = await getSearchHistory();
    history.remove(keyword);
    await saveSearchHistory(history);
  }

  /// 清除所有搜索记录
  static Future<void> clearSearchHistory() async {
    await Hive.box<String>(_boxName).delete(_searchHistoryKey);
  }

  // ==================== 清除所有本地模式数据 ====================

  /// 清除所有本地模式数据
  static Future<void> clearAllLocalModeData() async {
    await clearSubscriptionUrl();
    await clearSearchSources();
    await clearLiveSources();
    await clearPlayRecords();
    await clearFavorites();
    await clearSearchHistory();
  }
}
