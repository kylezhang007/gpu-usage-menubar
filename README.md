<div align="center">

# GPU Usage Menubar

**Your rented GPUs, at a glance, in Liquid Glass.**

A native macOS menu bar app that watches the GPU servers you rent on AutoDL, RunPod,
Vast.ai or anywhere you can SSH into: how busy each GPU is, how long it's been on,
and how much balance you have left. It also tells you when a machine has been sitting
idle so you can stop paying for it.

SwiftUI · macOS 14+ · Liquid Glass on macOS 26 · Universal (Apple Silicon + Intel)

Companion to [AI Usage Menubar](https://github.com/kylezhang007/ai-usage-menubar), same design language.

[中文介绍](#中文介绍)

</div>

---

## What it shows

**Per machine**
- **GPU use and VRAM** as two activity-style rings, averaged across all GPUs on the machine
- **Temperature and power draw**
- **Uptime**: how long the instance has been on
- **Fullest disk**: system or data disk, turning amber at 90% before a full disk kills your run
- **The last hour of GPU use** as a sparkline, so a stalled job is obvious
- **Idle warning**: a machine whose GPU has been below 5% for a while turns amber and says "shut it down?"

**Per account**
- **Balance**, plus AutoDL vouchers
- **Today's, this week's and total spend** on AutoDL, with a 7-day chart of daily spend
- **Spend per hour** and roughly **how long the balance lasts**. RunPod and Vast.ai report the rate;
  for AutoDL it's worked out from how fast total spend grows.

**Notifications**
- A machine has been idle for 15, 30 or 60 minutes (you choose)
- A balance will run out in under 3 hours

**Menu bar**: one small ring per running machine with its GPU use, in the provider's color; amber when idle.

## Design

- **Liquid Glass, Control Center style.** No backing sheet; every machine is its own piece of glass.
- **One color family per provider.** AutoDL violet, RunPod pink, Vast.ai teal, other servers green, balances blue.
- **Amber means "look at this".** Idle machines, nearly full disks and low balances all use the same warm
  amber, and nothing else does.
- **Aligned type.** Tabular figures for percentages, a monospaced fixed-width uptime (`3h12m`, `1d04h`).
- **English and Chinese**, light and dark mode, Standard or Clear glass.

## Where the data comes from

| Source | What you add | What it gives |
|---|---|---|
| Any server over SSH (AutoDL, Lambda, your own box) | The SSH command from the console, with key login set up | GPUs, VRAM, temperature, power, uptime, disks |
| AutoDL developer API | Developer token (Console → Settings → Developer Token) | Balance and vouchers |
| RunPod API | API key | Balance, spend per hour, every pod's GPU use and uptime, no SSH needed |
| Vast.ai API | API key | Balance, every instance's GPU use, cost and uptime, no SSH needed |

Over SSH the app runs one read-only command per refresh (`nvidia-smi`, `ps`, `df`) through the system
`ssh` in batch mode. It never asks for or stores a server password; key login must already work.

## Install

1. Download `GPUUsage.zip` from [Releases](../../releases), unzip it, and drag `GPUUsage.app` into Applications.
2. The app isn't notarized, so the first time, right-click it and choose **Open**.
3. Click the ring in the menu bar → **Settings**:
   - **Servers**: add a name, pick the provider, paste the SSH command (for example
     `ssh -p 12345 root@connect.westb.seetacloud.com`), and press **Test**.
   - **Accounts**: paste your AutoDL token and/or RunPod / Vast.ai API keys.

### SSH key login on AutoDL

If `ssh -p <port> root@<host>` from Terminal still asks for a password, add your Mac's public key
(`cat ~/.ssh/id_ed25519.pub`) in AutoDL under Console → Settings → SSH Public Key, then try again.

## Privacy

Tokens and API keys stay in the macOS Keychain on your Mac, stored through Apple's `security` tool so
updates don't ask for your password (other programs running as you can read them the same way). Server
addresses are kept in the app's preferences. The app only talks to your servers and to the AutoDL,
RunPod and Vast.ai APIs.

## Build

```bash
./build.sh
```

Needs Xcode or the Command Line Tools. Produces a universal `build/GPUUsage.app` and `build/GPUUsage.zip`.
`GPUUsage --demo` fills the panel with made-up machines, handy for screenshots;
`GPUUsage --snapshot out.png` renders the panel to an image and exits.

## Disclaimer

Unofficial and not affiliated with AutoDL, RunPod or Vast.ai.

## License

[MIT](LICENSE)

---

## 中文介绍

一个原生的 macOS 状态栏小工具，用来盯你在 AutoDL、RunPod、Vast.ai 等平台租的 GPU 服务器：GPU 忙不忙、开机多久了、余额还剩多少，机器空闲时还会提醒你关机省钱。

**每台机器**
- GPU 利用率和显存占用，用两层圆环显示；多卡机器显示平均值
- 温度和功率
- 开机时长
- 最满的那块硬盘（系统盘或数据盘），超过 90% 变成琥珀色提醒
- 最近一小时的 GPU 利用率曲线，训练卡住了一眼就能看出来
- 空闲提醒：GPU 一段时间几乎没在用，卡片会变成琥珀色，提示「记得关机」

**每个账户**
- 余额（AutoDL 还显示代金券）
- AutoDL 的今日花费、本周累计和累计消费，以及近 7 天每日花费的折线图
- 每小时花费，以及余额大约还能撑多久。RunPod 和 Vast.ai 由接口直接给出；AutoDL 根据累计消费增长的速度估算

**系统通知**：机器空闲超过设定时间，或者余额撑不过 3 小时。

**数据来源**
- **SSH**：AutoDL 或任何能 SSH 登录的服务器，粘贴控制台给的 SSH 登录命令即可。需要先配好免密登录，程序不保存服务器密码。
- **AutoDL**：开发者 Token，用来查余额。
- **RunPod / Vast.ai**：填 API Key，机器会自动出现，不用配 SSH。

安装方法同上：从 Releases 下载 zip，解压后拖进「应用程序」，第一次打开要右键选「打开」。
