//
// main.swift
// mvpnhelper
// setuid root 特权组件, 由 Mihomo VPN 安装到 /Library/PrivilegedHelperTools。
// 只接受固定命令: 以 root 启停 TUN 模式的 Mihomo, 以及在普通权限不足时设置系统代理。
//
//   mvpnhelper version
//   mvpnhelper start <config.json>
//   mvpnhelper stop
//   mvpnhelper status
//   mvpnhelper proxy on <port> | proxy off
//

import Foundation

let helperVersion = "2"
let corePath = "/Library/PrivilegedHelperTools/io.github.renpengkai.mihomovpn.core"
let workDir = "/Library/Application Support/MihomoVPN"
let pidPath = "/var/run/io.github.renpengkai.mihomovpn.pid"
let safeEnvironment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "HOME": "/var/root"]

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

@discardableResult
func run(_ path: String, _ args: [String]) -> String {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: path)
    p.arguments = args
    p.environment = safeEnvironment
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = FileHandle.nullDevice
    guard (try? p.run()) != nil else { return "" }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return String(decoding: data, as: UTF8.self)
}

func runningPID() -> pid_t? {
    guard let text = try? String(contentsOfFile: pidPath, encoding: .utf8),
          let pid = pid_t(text.trimmingCharacters(in: .whitespacesAndNewlines)), pid > 0,
          kill(pid, 0) == 0 else { return nil }
    var buf = [CChar](repeating: 0, count: 4096)
    guard proc_pidpath(pid, &buf, UInt32(buf.count)) > 0, String(cString: buf) == corePath else { return nil }
    return pid
}

func stopCore() {
    defer { try? FileManager.default.removeItem(atPath: pidPath) }
    guard let pid = runningPID() else { return }
    kill(pid, SIGTERM)
    for _ in 0..<30 where kill(pid, 0) == 0 {
        usleep(100_000)
    }
    if kill(pid, 0) == 0 { kill(pid, SIGKILL) }
}

func startCore(configPath: String) -> Never {
    stopCore()
    guard FileManager.default.fileExists(atPath: configPath) else {
        fail("无法读取配置文件")
    }

    let fm = FileManager.default
    try? fm.createDirectory(atPath: workDir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o755])

    let rootConfig = workDir + "/config.json"
    guard let data = fm.contents(atPath: configPath) else { fail("无法读取配置文件") }
    guard fm.createFile(atPath: rootConfig, contents: data, attributes: [.posixPermissions: 0o600]) else {
        fail("无法写入 \(rootConfig)")
    }

    let p = Process()
    p.executableURL = URL(fileURLWithPath: corePath)
    p.arguments = ["-f", rootConfig, "-d", workDir]
    p.environment = safeEnvironment
    p.standardInput = FileHandle.nullDevice
    p.standardOutput = FileHandle.nullDevice
    p.standardError = FileHandle.nullDevice
    do {
        try p.run()
    } catch {
        fail("内核启动失败：\(error.localizedDescription)")
    }
    try? "\(p.processIdentifier)".write(toFile: pidPath, atomically: true, encoding: .utf8)
    usleep(600_000)
    if !p.isRunning { fail("内核启动后立即退出") }
    exit(0)
}

func networkServices() -> [String] {
    run("/usr/sbin/networksetup", ["-listallnetworkservices"])
        .split(separator: "\n").dropFirst()
        .map(String.init)
        .filter { !$0.hasPrefix("*") && !$0.isEmpty }
}

func setProxy(port: Int?) {
    let tool = "/usr/sbin/networksetup"
    let bypass = ["127.0.0.1", "localhost", "*.local", "169.254/16", "10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16", "::1"]
    for s in networkServices() {
        if let port {
            run(tool, ["-setwebproxy", s, "127.0.0.1", "\(port)"])
            run(tool, ["-setsecurewebproxy", s, "127.0.0.1", "\(port)"])
            run(tool, ["-setsocksfirewallproxy", s, "127.0.0.1", "\(port)"])
            run(tool, ["-setproxybypassdomains", s] + bypass)
        } else {
            run(tool, ["-setwebproxystate", s, "off"])
            run(tool, ["-setsecurewebproxystate", s, "off"])
            run(tool, ["-setsocksfirewallproxystate", s, "off"])
        }
    }
}

let args = Array(CommandLine.arguments.dropFirst())
guard let command = args.first else {
    fail("usage: mvpnhelper version | start <config> | stop | status | proxy on <port> | proxy off")
}
if command == "version" {
    print(helperVersion)
    exit(0)
}
guard geteuid() == 0 else { fail("特权组件未以 root 身份运行，请在设置中重新安装") }
guard setgid(0) == 0, setuid(0) == 0 else { fail("切换到 root 失败") }

switch command {
case "start":
    guard args.count == 2 else { fail("usage: mvpnhelper start <config>") }
    startCore(configPath: args[1])
case "stop":
    stopCore()
case "status":
    print(runningPID() != nil ? "running" : "stopped")
case "proxy":
    if args.count == 3, args[1] == "on", let port = Int(args[2]), (1...65535).contains(port) {
        setProxy(port: port)
    } else if args.count == 2, args[1] == "off" {
        setProxy(port: nil)
    } else {
        fail("usage: mvpnhelper proxy on <port> | proxy off")
    }
default:
    fail("未知命令：\(command)")
}
