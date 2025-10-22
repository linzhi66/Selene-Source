import 'dart:convert';
import 'package:bs58check/bs58check.dart' as bs58;
import '../models/search_resource.dart';

/// 订阅服务
/// 用于解析订阅内容
class SubscriptionService {
  /// 解析订阅内容
  /// 
  /// 参数:
  /// - content: Base58 编码的订阅内容
  /// 
  /// 返回:
  /// - 成功: 返回 SearchResource 列表
  /// - 失败: 返回 null
  static Future<List<SearchResource>?> parseSubscriptionContent(
      String content) async {
    try {
      // Base58 解码
      final decoded = bs58.base58.decode(content);
      final jsonString = utf8.decode(decoded);

      // 解析 JSON
      final jsonData = jsonDecode(jsonString) as Map<String, dynamic>;
      final apiSite = jsonData['api_site'] as Map<String, dynamic>?;

      if (apiSite == null) {
        return null;
      }

      // 保持 map 中的顺序，转换为 List<SearchResource>
      final resources = <SearchResource>[];
      apiSite.forEach((key, value) {
        final site = value as Map<String, dynamic>;
        resources.add(SearchResource(
          key: site['key'] as String? ?? key,
          name: site['name'] as String? ?? '',
          api: site['api'] as String? ?? '',
          detail: site['detail'] as String? ?? '',
          from: site['from'] as String? ?? '',
          disabled: false,
        ));
      });

      return resources;
    } catch (e) {
      return null;
    }
  }
}
