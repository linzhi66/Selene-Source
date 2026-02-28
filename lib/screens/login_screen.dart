import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:selene/components/animations/glass_card.dart';
import 'package:selene/components/animations/neon_button.dart';
import 'package:selene/design/design_system.dart';
import 'package:selene/screens/home_screen.dart';
import 'package:selene/services/local_mode_storage_service.dart';
import 'package:selene/services/subscription_service.dart';
import 'package:selene/services/theme_service.dart';
import 'package:selene/services/user_data_service.dart';
import 'package:selene/utils/device_utils.dart';
import 'package:selene/widgets/windows_title_bar.dart';

/// 现代化登录页面
///
/// 采用 2026 设计系统：
/// - 玻璃拟态卡片
/// - 霓虹渐变按钮
/// - 流畅的入场动画
/// - 现代化的输入框样式
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _urlController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _subscriptionUrlController = TextEditingController();

  bool _isPasswordVisible = false;
  bool _isLoading = false;
  bool _isFormValid = false;
  bool _isLocalMode = false;

  // 点击计数器（用于切换到本地模式）
  int _logoTapCount = 0;
  Timer? _tapTimer;

  // 动画控制器
  late AnimationController _animationController;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: AppAnimations.showcase,
    );
    _animationController.forward();

    _urlController.addListener(_validateForm);
    _usernameController.addListener(_validateForm);
    _passwordController.addListener(_validateForm);
    _subscriptionUrlController.addListener(_validateForm);
    _loadSavedUserData();
  }

  void _loadSavedUserData() async {
    final userData = await UserDataService.getAllUserData();
    bool hasData = false;

    if (userData['serverUrl'] != null) {
      _urlController.text = userData['serverUrl']!;
      hasData = true;
    }
    if (userData['username'] != null) {
      _usernameController.text = userData['username']!;
      hasData = true;
    }
    if (userData['password'] != null) {
      _passwordController.text = userData['password']!;
      hasData = true;
    }

    final subscriptionUrl = await LocalModeStorageService.getSubscriptionUrl();
    if (subscriptionUrl != null && subscriptionUrl.isNotEmpty) {
      _subscriptionUrlController.text = subscriptionUrl;
      hasData = true;
    }

    if (hasData && mounted) {
      setState(() => _validateForm());
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    _urlController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _subscriptionUrlController.dispose();
    _tapTimer?.cancel();
    super.dispose();
  }

  void _handleLogoTap() {
    _logoTapCount++;
    _tapTimer?.cancel();

    if (_logoTapCount >= 10) {
      setState(() {
        _isLocalMode = !_isLocalMode;
        _validateForm();
        _logoTapCount = 0;
      });
      _showToast(
        _isLocalMode ? '已切换到本地模式' : '已切换到服务器模式',
        AppColors.success,
      );
    } else {
      _tapTimer = Timer(const Duration(seconds: 1), () {
        setState(() => _logoTapCount = 0);
      });
    }
  }

  void _validateForm() {
    setState(() {
      if (_isLocalMode) {
        _isFormValid = _subscriptionUrlController.text.isNotEmpty;
      } else {
        _isFormValid = _urlController.text.isNotEmpty &&
            _usernameController.text.isNotEmpty &&
            _passwordController.text.isNotEmpty;
      }
    });
  }

  void _handleSubmit() {
    if (_isLocalMode) {
      _handleLocalModeLogin();
    } else {
      _handleLogin();
    }
  }

  void _showToast(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: AppTypography.bodyMediumStyle().copyWith(color: Colors.white),
        ),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  String _processUrl(String url) {
    String processedUrl = url.trim();
    if (processedUrl.endsWith('/')) {
      processedUrl = processedUrl.substring(0, processedUrl.length - 1);
    }
    return processedUrl;
  }

  String _parseCookies(http.Response response) {
    final List<String> cookies = [];
    final setCookieHeaders = response.headers['set-cookie'];
    if (setCookieHeaders != null) {
      final cookieParts = setCookieHeaders.split(';');
      if (cookieParts.isNotEmpty) {
        cookies.add(cookieParts[0].trim());
      }
    }
    return cookies.join('; ');
  }

  void _handleLogin() async {
    if (_formKey.currentState!.validate() && _isFormValid) {
      setState(() => _isLoading = true);

      try {
        final String baseUrl = _processUrl(_urlController.text);
        final String loginUrl = '$baseUrl/api/login';

        final response = await http.post(
          Uri.parse(loginUrl),
          headers: {'Content-Type': 'application/json'},
          body: json.encode({
            'username': _usernameController.text,
            'password': _passwordController.text,
          }),
        );

        setState(() => _isLoading = false);

        switch (response.statusCode) {
          case 200:
            final String cookies = _parseCookies(response);
            await UserDataService.saveUserData(
              serverUrl: baseUrl,
              username: _usernameController.text,
              password: _passwordController.text,
              cookies: cookies,
            );
            await UserDataService.saveIsLocalMode(isLocalMode: false);

            if (mounted) {
              await Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute<void>(
                  builder: (context) => const HomeScreen(),
                ),
                (route) => false,
              );
            }
            break;
          case 401:
            _showToast('用户名或密码错误', AppColors.error);
            break;
          case 500:
            _showToast('服务器错误', AppColors.error);
            break;
          default:
            _showToast('网络异常', AppColors.error);
        }
      } catch (e) {
        setState(() => _isLoading = false);
        _showToast('网络异常', AppColors.error);
      }
    }
  }

  void _handleLocalModeLogin() async {
    if (_formKey.currentState!.validate()) {
      setState(() => _isLoading = true);

      try {
        final newUrl = _subscriptionUrlController.text.trim();
        final response = await http.get(Uri.parse(newUrl));

        if (response.statusCode != 200) {
          setState(() => _isLoading = false);
          _showToast('获取订阅内容失败', AppColors.error);
          return;
        }

        final content =
            await SubscriptionService.parseSubscriptionContent(response.body);

        if (content == null ||
            (content.searchResources?.isEmpty ?? true) &&
                (content.liveSources?.isEmpty ?? true)) {
          setState(() => _isLoading = false);
          _showToast('解析订阅内容失败', AppColors.error);
          return;
        }

        final existingUrl = await LocalModeStorageService.getSubscriptionUrl();

        if (existingUrl != null &&
            existingUrl.isNotEmpty &&
            existingUrl != newUrl) {
          setState(() => _isLoading = false);

          if (!mounted) return;

          final shouldClear = await showDialog<bool>(
            context: context,
            builder: (context) => _buildClearDataDialog(),
          );

          if (shouldClear == true) {
            await LocalModeStorageService.clearAllLocalModeData();
          } else if (shouldClear == null) {
            return;
          }

          setState(() => _isLoading = true);
        }

        await LocalModeStorageService.saveSubscriptionUrl(newUrl);
        if (content.searchResources != null &&
            content.searchResources!.isNotEmpty) {
          await LocalModeStorageService.saveSearchSources(
              content.searchResources!);
        }
        if (content.liveSources != null && content.liveSources!.isNotEmpty) {
          await LocalModeStorageService.saveLiveSources(content.liveSources!);
        }

        await UserDataService.saveIsLocalMode(isLocalMode: true);
        setState(() => _isLoading = false);

        if (mounted) {
          await Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute<void>(builder: (context) => const HomeScreen()),
            (route) => false,
          );
        }
      } catch (e) {
        setState(() => _isLoading = false);
        _showToast('登录失败：${e.toString()}', AppColors.error);
      }
    }
  }

  Widget _buildClearDataDialog() {
    return GlassCard(
      isDark: false,
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '提示',
            style: AppTypography.headlineSmallStyle(),
          ),
          const SizedBox(height: 16),
          Text(
            '检测到已有本地模式内容且订阅链接不一致，是否清空全部本地模式存储？',
            style: AppTypography.bodyMediumStyle(),
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(
                  '否',
                  style: AppTypography.bodyMediumStyle().copyWith(
                    color: AppColors.lightTextSecondary,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              NeonButton(
                text: '是',
                onPressed: () => Navigator.of(context).pop(true),
                height: 40,
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeService = Provider.of<ThemeService>(context);
    final isDark = themeService.isDarkMode;
    final isTablet = DeviceUtils.isTablet(context);

    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: AppColors.backgroundGradient(isDark: isDark),
        ),
        child: Column(
          children: [
            if (Platform.isWindows)
              WindowsTitleBar(forceBlack: !themeService.isDarkMode),
            Expanded(
              child: SafeArea(
                child: Center(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.symmetric(
                      horizontal: isTablet ? 0 : 24.0,
                      vertical: 24.0,
                    ),
                    child: isTablet
                        ? _buildTabletLayout(isDark)
                        : _buildMobileLayout(isDark),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMobileLayout(bool isDark) {
    return AppAnimations.entrance(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Logo
          _buildLogo(isDark),
          const SizedBox(height: 48),
          // 登录表单
          _buildLoginForm(isDark),
        ],
      ),
    );
  }

  Widget _buildTabletLayout(bool isDark) {
    return AppAnimations.entrance(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 480),
        padding: const EdgeInsets.symmetric(horizontal: 32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildLogo(isDark),
            const SizedBox(height: 48),
            _buildLoginForm(isDark),
          ],
        ),
      ),
    );
  }

  Widget _buildLogo(bool isDark) {
    return GestureDetector(
      onTap: _handleLogoTap,
      child: Column(
        children: [
          // 图标
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              gradient: AppColors.primaryGradient,
              borderRadius: BorderRadius.circular(24),
              boxShadow: AppShadows.neonPrimary,
            ),
            child: const Icon(
              LucideIcons.play,
              color: Colors.white,
              size: 40,
            ),
          ),
          const SizedBox(height: 24),
          // 品牌名
          ShaderMask(
            shaderCallback: (bounds) =>
                AppColors.primaryGradient.createShader(bounds),
            child: Text(
              'Selene',
              style: AppTypography.brand(fontSize: 42)
                  .copyWith(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoginForm(bool isDark) {
    return GlassCard(
      isDark: isDark,
      borderRadius: 24,
      padding: const EdgeInsets.all(32),
      child: Form(
        key: _formKey,
        child: _isLocalMode
            ? _buildLocalModeForm(isDark)
            : _buildServerModeForm(isDark),
      ),
    );
  }

  Widget _buildServerModeForm(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildTextField(
          controller: _urlController,
          label: '服务器地址',
          hint: 'https://example.com',
          icon: LucideIcons.link,
          isDark: isDark,
          validator: (value) {
            if (value == null || value.isEmpty) {
              return '请输入服务器地址';
            }
            final uri = Uri.tryParse(value);
            if (uri == null || uri.scheme.isEmpty || uri.host.isEmpty) {
              return '请输入有效的URL地址';
            }
            return null;
          },
        ),
        const SizedBox(height: 20),
        _buildTextField(
          controller: _usernameController,
          label: '用户名',
          hint: '请输入用户名',
          icon: LucideIcons.user,
          isDark: isDark,
          validator: (value) {
            if (value == null || value.isEmpty) {
              return '请输入用户名';
            }
            return null;
          },
        ),
        const SizedBox(height: 20),
        _buildTextField(
          controller: _passwordController,
          label: '密码',
          hint: '请输入密码',
          icon: LucideIcons.lock,
          isDark: isDark,
          isPassword: true,
          validator: (value) {
            if (value == null || value.isEmpty) {
              return '请输入密码';
            }
            return null;
          },
        ),
        const SizedBox(height: 32),
        _buildLoginButton(isDark),
      ],
    );
  }

  Widget _buildLocalModeForm(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildTextField(
          controller: _subscriptionUrlController,
          label: '订阅链接',
          hint: '请输入订阅链接',
          icon: LucideIcons.link,
          isDark: isDark,
          validator: (value) {
            if (value == null || value.isEmpty) {
              return '请输入订阅链接';
            }
            return null;
          },
        ),
        const SizedBox(height: 32),
        _buildLoginButton(isDark),
      ],
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    required bool isDark,
    bool isPassword = false,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: isPassword && !_isPasswordVisible,
      style: AppTypography.bodyLargeStyle(isDark: isDark),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, color: AppColors.primary, size: 20),
        suffixIcon: isPassword
            ? IconButton(
                icon: Icon(
                  _isPasswordVisible ? LucideIcons.eye : LucideIcons.eyeOff,
                  color: AppColors.textTertiary(isDark: isDark),
                  size: 20,
                ),
                onPressed: () {
                  setState(() => _isPasswordVisible = !_isPasswordVisible);
                },
              )
            : null,
        filled: true,
        fillColor: isDark
            ? AppColors.darkElevated.withValues(alpha: 0.5)
            : AppColors.lightElevated.withValues(alpha: 0.5),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.error),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 18,
        ),
        labelStyle: AppTypography.bodyMediumStyle(isDark: isDark).copyWith(
          color: AppColors.textSecondary(isDark: isDark),
        ),
        hintStyle: AppTypography.bodyMediumStyle(isDark: isDark).copyWith(
          color: AppColors.textTertiary(isDark: isDark),
        ),
      ),
      validator: validator,
      onFieldSubmitted: (_) => _handleSubmit(),
    );
  }

  Widget _buildLoginButton(bool isDark) {
    return NeonButton(
      text: _isLoading ? '登录中...' : '登录',
      onPressed: (_isLoading || !_isFormValid) ? null : _handleSubmit,
      isLoading: _isLoading,
      isFullWidth: true,
      height: 56,
      gradient: _isFormValid && !_isLoading
          ? AppColors.primaryGradient
          : LinearGradient(
              colors: [
                AppColors.textTertiary(isDark: isDark),
                AppColors.textTertiary(isDark: isDark),
              ],
            ),
    );
  }
}
