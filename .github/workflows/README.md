# Selene CI/CD 工作流文档

本目录包含 Selene Flutter 项目的 GitHub Actions 工作流配置。

## 工作流概览

### 1. `ci-cd.yml` - 主 CI/CD 流水线

**触发条件：**

- 推送到 `main`、`develop` 或 `release/*` 分支
- 提交到 `main` 或 `develop` 分支的 Pull Request
- 手动运行（可选择构建平台）

**阶段划分：**

#### 第一阶段：代码质量与验证

- **任务：** `analyze`
- **运行环境：** Ubuntu Latest
- **执行步骤：**
    - 使用 `flutter analyze` 进行代码分析
    - 使用 `dart format` 检查代码格式
    - 运行单元测试并生成覆盖率报告
    - 上传覆盖率到 Codecov
    - 从 pubspec.yaml 提取版本号

#### 第二阶段：安全审计

- **任务：** `security`
- **执行步骤：**
    - 使用 `flutter pub audit` 进行依赖漏洞扫描
    - 依赖树分析

#### 第三阶段：多平台并行构建

| 平台      | 运行环境           | 输出产物                    |
|---------|----------------|-------------------------|
| Android | Ubuntu Latest  | APK (arm64、armeabi)、AAB |
| iOS     | macOS Latest   | IPA（未签名）                |
| macOS   | macOS Latest   | DMG (arm64、x86_64)      |
| Windows | Windows Latest | ZIP (x64)               |
| Web     | Ubuntu Latest  | Tarball 压缩包             |
| Linux   | Ubuntu Latest  | Tarball 压缩包 (x64)       |

#### 第四阶段：发布

- **任务：** `release`
- **触发条件：** 推送 Tag (`v*`)
- 自动创建 GitHub Release 并附带所有构建产物

#### 第五阶段：汇总

- 输出所有平台的构建状态报告

### 2. `pr-check.yml` - Pull Request 验证

**触发条件：**

- 提交到 `main` 或 `develop` 分支的 Pull Request

**任务：**

- `pr_validation`：快速分析、格式检查和测试
- `smoke_build`：编译 Debug APK 确保项目可构建

## 功能特性

### 🚀 性能优化

1. **智能缓存**
    - 按平台隔离缓存 Pub 依赖
    - Android 构建使用 Gradle 缓存
    - iOS/macOS 构建使用 CocoaPods 缓存
    - Flutter SDK 缓存

2. **并行执行**
    - 所有平台构建并行运行
    - macOS 使用矩阵策略构建多架构版本
    - 基于阶段的依赖管理

3. **条件构建**
    - 手动运行可选择指定平台
    - 文档变更自动跳过构建
    - 根据 PR/Push/Tag 自动调整逻辑

4. **资源效率**
    - 每个任务设置超时限制
    - 并发控制自动取消过期运行
    - 制品保留策略（30天）

### 🔒 安全特性

- 依赖漏洞扫描
- 调试符号单独上传（90天保留）
- 日志中不输出敏感数据
- 安全的制品处理

### 📊 监控与报告

- 构建状态汇总
- 代码覆盖率报告
- 制品大小追踪
- 自动生成发布说明

## 配置说明

### 环境变量

| 变量名                | 值              | 说明             |
|--------------------|----------------|----------------|
| `FLUTTER_VERSION`  | `3.38.9`       | Flutter SDK 版本 |
| `FLUTTER_CHANNEL`  | `stable`       | Flutter 通道     |
| `PUB_CACHE_KEY`    | `pub-cache-v1` | Pub 缓存键名       |
| `GRADLE_CACHE_KEY` | `gradle-v1`    | Gradle 缓存键名    |

### 需要的密钥

| 密钥名             | 用途    | 说明                    |
|-----------------|-------|-----------------------|
| `CODECOV_TOKEN` | 覆盖率上传 | Codecov 集成令牌（可选）      |
| `GITHUB_TOKEN`  | 发布    | 由 GitHub Actions 自动提供 |

## 使用指南

### 手动触发

1. 进入 **Actions** 标签页
2. 选择 **Selene CI/CD**
3. 点击 **Run workflow**
4. 选择要构建的平台
5. 点击 **Run workflow**

### 标签发布

创建标签即可触发发布：

```bash
git tag -a v1.6.6 -m "发布 v1.6.6"
git push origin v1.6.6
```

工作流将自动：

1. 构建所有平台
2. 创建 GitHub Release
3. 附加所有构建产物
4. 生成发布说明

## 问题排查

### 构建失败

1. **Android 构建失败**
    - 检查 Java 版本（需要 Java 17）
    - 验证 Android SDK 配置
    - 检查 Gradle 守护进程状态

2. **iOS/macOS 构建失败**
    - 检查 Xcode 版本兼容性
    - 验证 CocoaPods 安装
    - 检查签名配置

3. **Windows 构建失败**
    - 验证 Visual Studio 安装
    - 检查 Windows SDK 版本

4. **Linux 构建失败**
    - 确保已安装依赖库
    - 检查 GTK3 开发库

### 缓存问题

如果构建因缓存损坏而失败：

1. 进入 **Actions** 标签页
2. 左侧选择 **Caches**
3. 删除相关缓存
4. 重新运行工作流

## 优化建议

1. **缩短构建时间**
    - 发布构建使用 `--obfuscate` 参数
    - 启用 `split-debug-info`
    - Android 使用 `--split-per-abi`

2. **制品管理**
    - 只保留必要的制品
    - Debug 构建使用较短的保留期
    - 归档旧版本发布

3. **运行器选择**
    - 重型构建使用更大的运行器
    - 考虑使用自托管运行器加快执行

## 参考资料

- [Flutter CI/CD 文档](https://docs.flutter.dev/deployment/cd)
- [GitHub Actions 文档](https://docs.github.com/en/actions)
- [subosito/flutter-action](https://github.com/subosito/flutter-action)
