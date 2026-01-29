import 'package:hive/hive.dart';

class UserDataService {
  static const String _boxName = 'user_data';
  static const String _serverUrlKey = 'server_url';
  static const String _usernameKey = 'username';
  static const String _passwordKey = 'password';
  static const String _cookiesKey = 'cookies';
  static const String _doubanDataSourceKey = 'douban_data_source';
  static const String _doubanImageSourceKey = 'douban_image_source';
  static const String _m3u8ProxyUrlKey = 'm3u8_proxy_url';
  static const String _preferSpeedTestKey = 'prefer_speed_test';
  static const String _localSearchKey = 'local_search';
  static const String _isLocalModeKey = 'is_local_mode';

  // 内存缓存
  static bool? _isLocalModeCache;

  // 保存用户登录信息
  static Future<void> saveUserData({
    required String serverUrl,
    required String username,
    required String password,
    required String cookies,
  }) async {
    final box = Hive.box<String>(_boxName);
    await box.put(_serverUrlKey, serverUrl);
    await box.put(_usernameKey, username);
    await box.put(_passwordKey, password);
    await box.put(_cookiesKey, cookies);
  }

  // 获取服务器地址
  static Future<String?> getServerUrl() async {
    final box = Hive.box<String>(_boxName);
    return box.get(_serverUrlKey);
  }

  // 获取用户名
  static Future<String?> getUsername() async {
    final box = Hive.box<String>(_boxName);
    return box.get(_usernameKey);
  }

  // 获取密码
  static Future<String?> getPassword() async {
    final box = Hive.box<String>(_boxName);
    return box.get(_passwordKey);
  }

  // 获取cookies
  static Future<String?> getCookies() async {
    final box = Hive.box<String>(_boxName);
    return box.get(_cookiesKey);
  }

  // 检查是否已登录
  static Future<bool> isLoggedIn() async {
    final cookies = await getCookies();
    return cookies != null && cookies.isNotEmpty;
  }

  // 清除用户数据
  static Future<void> clearUserData() async {
    final box = Hive.box<String>(_boxName);
    await box.delete(_serverUrlKey);
    await box.delete(_usernameKey);
    await box.delete(_passwordKey);
    await box.delete(_cookiesKey);
  }

  // 只清除密码和cookies，保留服务器地址和用户名
  static Future<void> clearPasswordAndCookies() async {
    final box = Hive.box<String>(_boxName);
    await box.delete(_passwordKey);
    await box.delete(_cookiesKey);
  }

  // 获取所有用户数据
  static Future<Map<String, String?>> getAllUserData() async {
    final box = Hive.box<String>(_boxName);
    return {
      'serverUrl': box.get(_serverUrlKey),
      'username': box.get(_usernameKey),
      'password': box.get(_passwordKey),
      'cookies': box.get(_cookiesKey),
    };
  }

  // 检查是否具有自动登录所需的所有字段
  static Future<bool> hasAutoLoginData() async {
    final serverUrl = await getServerUrl();
    final username = await getUsername();
    final password = await getPassword();

    return serverUrl != null &&
        serverUrl.isNotEmpty &&
        username != null &&
        username.isNotEmpty &&
        password != null &&
        password.isNotEmpty;
  }

  // 保存豆瓣数据源设置（存储key值）
  static Future<void> saveDoubanDataSource(String dataSourceDisplayName) async {
    final box = Hive.box<String>(_boxName);
    final key = _getDoubanDataSourceKeyFromDisplayName(dataSourceDisplayName);
    await box.put(_doubanDataSourceKey, key);
  }

  // 获取豆瓣数据源设置（返回key值）
  static Future<String> getDoubanDataSourceKey() async {
    final box = Hive.box<String>(_boxName);
    return box.get(_doubanDataSourceKey) ?? 'direct';
  }

  // 获取豆瓣数据源显示名称
  static Future<String> getDoubanDataSourceDisplayName() async {
    final key = await getDoubanDataSourceKey();
    return _getDoubanDataSourceDisplayNameFromKey(key);
  }

  // 保存豆瓣图片源设置（存储key值）
  static Future<void> saveDoubanImageSource(
      String imageSourceDisplayName) async {
    final box = Hive.box<String>(_boxName);
    final key = _getDoubanImageSourceKeyFromDisplayName(imageSourceDisplayName);
    await box.put(_doubanImageSourceKey, key);
  }

  // 获取豆瓣图片源设置（返回key值）
  static Future<String> getDoubanImageSourceKey() async {
    final box = Hive.box<String>(_boxName);
    return box.get(_doubanImageSourceKey) ?? 'direct';
  }

  // 获取豆瓣图片源显示名称
  static Future<String> getDoubanImageSourceDisplayName() async {
    final key = await getDoubanImageSourceKey();
    return _getDoubanImageSourceDisplayNameFromKey(key);
  }

  // 根据显示名称获取豆瓣数据源的key值（私有方法）
  static String _getDoubanDataSourceKeyFromDisplayName(String dataSource) {
    switch (dataSource) {
      case '直连':
        return 'direct';
      case 'Cors Proxy By Zwei':
        return 'cors_proxy';
      case '豆瓣 CDN By CMLiussss（腾讯云）':
        return 'cdn_tencent';
      case '豆瓣 CDN By CMLiussss（阿里云）':
        return 'cdn_aliyun';
      default:
        return 'direct';
    }
  }

  // 根据显示名称获取豆瓣图片源的key值（私有方法）
  static String _getDoubanImageSourceKeyFromDisplayName(String imageSource) {
    switch (imageSource) {
      case '直连':
        return 'direct';
      case '豆瓣官方精品 CDN':
        return 'official_cdn';
      case '豆瓣 CDN By CMLiussss（腾讯云）':
        return 'cdn_tencent';
      case '豆瓣 CDN By CMLiussss（阿里云）':
        return 'cdn_aliyun';
      default:
        return 'direct';
    }
  }

  // 根据key值获取豆瓣数据源显示名称（私有方法）
  static String _getDoubanDataSourceDisplayNameFromKey(String key) {
    switch (key) {
      case 'direct':
        return '直连';
      case 'cors_proxy':
        return 'Cors Proxy By Zwei';
      case 'cdn_tencent':
        return '豆瓣 CDN By CMLiussss（腾讯云）';
      case 'cdn_aliyun':
        return '豆瓣 CDN By CMLiussss（阿里云）';
      default:
        return '直连';
    }
  }

  // 根据key值获取豆瓣图片源显示名称（私有方法）
  static String _getDoubanImageSourceDisplayNameFromKey(String key) {
    switch (key) {
      case 'direct':
        return '直连';
      case 'official_cdn':
        return '豆瓣官方精品 CDN';
      case 'cdn_tencent':
        return '豆瓣 CDN By CMLiussss（腾讯云）';
      case 'cdn_aliyun':
        return '豆瓣 CDN By CMLiussss（阿里云）';
      default:
        return '直连';
    }
  }

  // 保存 M3U8 代理 URL
  static Future<void> saveM3u8ProxyUrl(String url) async {
    final box = Hive.box<String>(_boxName);
    await box.put(_m3u8ProxyUrlKey, url);
  }

  // 获取 M3U8 代理 URL
  static Future<String> getM3u8ProxyUrl() async {
    final box = Hive.box<String>(_boxName);
    return box.get(_m3u8ProxyUrlKey) ?? '';
  }

  // 保存优选测速设置
  static Future<void> savePreferSpeedTest(bool enabled) async {
    final box = Hive.box<bool>(_boxName);
    await box.put(_preferSpeedTestKey, enabled);
  }

  // 获取优选测速设置（默认为 true）
  static Future<bool> getPreferSpeedTest() async {
    final box = Hive.box<bool>(_boxName);
    return box.get(_preferSpeedTestKey) ?? true;
  }

  // 保存本地搜索设置
  static Future<void> saveLocalSearch(bool enabled) async {
    final box = Hive.box<bool>(_boxName);
    await box.put(_localSearchKey, enabled);
  }

  // 获取本地搜索设置（默认为 false）
  static Future<bool> getLocalSearch() async {
    final box = Hive.box<bool>(_boxName);
    return box.get(_localSearchKey) ?? false;
  }

  // 保存本地模式设置
  static Future<void> saveIsLocalMode(bool isLocalMode) async {
    final box = Hive.box<bool>(_boxName);
    await box.put(_isLocalModeKey, isLocalMode);
    _isLocalModeCache = isLocalMode; // 同步更新内存缓存
  }

  // 获取本地模式设置（默认为 false）
  static Future<bool> getIsLocalMode() async {
    final box = Hive.box<bool>(_boxName);
    final value = box.get(_isLocalModeKey) ?? false;
    _isLocalModeCache = value; // 缓存到内存
    return value;
  }

  // 同步获取本地模式设置（从内存缓存读取）
  static bool getIsLocalModeSync() {
    return _isLocalModeCache ?? false;
  }
}
