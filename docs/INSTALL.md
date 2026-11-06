# 安装到自己 iPhone

这个仓库**不提供已签名的 ipa**。签名必须绑定安装者自己的 Apple ID，证书不能共享。
下面三种方式按门槛从低到高。

## 方式一：Xcode 直接跑（推荐）

需要一台 Mac + Xcode 16 以上。

```bash
git clone https://github.com/dingbei0218-pixel/dsh-pocket.git
cd dsh-pocket/App
xcodegen generate
open PocketDSH.xcodeproj
```

1. Xcode → Settings → Accounts，登录你的 Apple ID；
2. 选中 `PocketDSH` target → Signing & Capabilities；
3. Team 选你的 Personal Team；
4. Bundle Identifier 改成全球唯一，例如 `com.yourname.dshpocket`；
5. 选自己的 iPhone，Run。

免费 Apple ID 的证书 **7 天过期**，到期重新 Run 一次即可。App 的数据不会丢。

## 方式二：未签名 ipa + 自己签名

仓库提供脚本，产出**未签名**的 `PocketDSH-unsigned.ipa`：

```bash
./scripts/build-unsigned-ipa.sh
```

产物在 `build/PocketDSH-unsigned.ipa`。然后用你自己的 Apple ID 通过
[AltStore](https://altstore.io/)、[Sideloadly](https://sideloadly.io/) 等工具签名安装。
同样受 7 天免费证书限制，工具可以帮你自动续签。

签名全程在本机完成，Apple ID 密码不经过本项目。

## 方式三：TestFlight / App Store

需要付费的 Apple Developer Program（99 美元/年）：

- Ad Hoc：登记设备 UDID 后分发，最多 100 台；
- TestFlight：最多 1 万外部测试者，90 天一轮；
- App Store：公开上架。

这条路要求你用自己的账号归档、上传；仓库不包含任何证书或 provisioning profile。

## 隐私

- 没有遥测、没有账号系统、没有云端会话；API Key 只存在本机 Keychain；
- 会话、工作区、皮肤都在 App 沙箱内；
- 只有 DeepSeek API、你主动触发的网页抓取、皮肤 Git 源会产生网络请求；
- 仓库和 App 都不包含作者的个人信息、证书或密钥。
