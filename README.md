# Mihomo VPN

轻量的 macOS 代理客户端。原生 SwiftUI，适配 macOS 26/27 **Liquid Glass**；内核使用 [MetaCubeX/mihomo](https://github.com/MetaCubeX/mihomo)（Clash Meta）。

- **尽量小**：默认不内置内核，界面 + 特权组件约数百 KB；需要时在设置里一键下载官方 Mihomo，或打包时 `BUNDLE_CORE=1` 内置。
- **订阅**：Clash / Clash.Meta YAML、分享链接、Base64、SIP008、常见 V2ray / sing-box JSON、GitHub 配置文件。
- **接管**：系统代理（mixed 端口）或 TUN（需安装特权组件）。
- **界面**：菜单栏弹窗 + 主窗口（概览 / 节点 / 订阅 / 日志 / 设置），macOS 26+ 使用 `glassEffect`。

## 构建

需要 Xcode（液态玻璃 API 来自 macOS 26 SDK；旧版 Xcode 可编译，无玻璃效果）。

```bash
chmod +x scripts/package-app.sh
./scripts/package-app.sh                        # 精简包，不内置内核
BUNDLE_CORE=1 ./scripts/package-app.sh          # 内置最新 Mihomo
MIHOMO_VERSION=1.19.32 BUNDLE_CORE=1 ./scripts/package-app.sh
ARCH=x86_64 ./scripts/package-app.sh
```

产物：`dist/MihomoVPN.app` 与 zip。

## 使用

1. 打开应用 →「设置」下载 Mihomo 内核（精简包）或使用内置内核。
2. 「订阅」添加 Clash 订阅 / 分享链接 / 本地文件。
3. 连接。默认规则模式：国内直连，其余走代理。
4. TUN：先在设置安装特权组件，再打开 TUN 开关。

运行数据：`~/Library/Application Support/MihomoVPN`。

## 体积说明

| 包 | 内容 | 大约体积 |
| --- | --- | --- |
| 精简包 `BUNDLE_CORE=0` | App + helper | &lt; 1 MB |
| 完整包 `BUNDLE_CORE=1` | + mihomo 官方二进制 | ~20–40 MB（由内核主导） |
