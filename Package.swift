// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Luma",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(
            name: "Luma",
            targets: ["Luma"]
        ),
    ],
    targets: [
        .executableTarget(
            name: "Luma",
            exclude: [
                // Info.plist 由 linker 通过 -sectcreate 嵌入可执行文件，不作为资源处理
                "App/Info.plist",
            ],
            resources: [
                .copy("Resources")
            ],
            swiftSettings: [
                // 减轻 Swift 6 strict concurrency 在闭包上注入的 runtime isolation 检查
                // （系统 SwiftUI 预编译产物理不到，本设置仍降低**应用自身**闭包/回调里的检查面）。
                .swiftLanguageMode(.v5),
                // macOS 26 / Swift 6.2 / arm64e：编译器在 SwiftUI view body 闭包等位置
                // 注入 actor isolation runtime check（swift_task_isCurrentExecutorWithFlagsImpl），
                // 但系统 libswift_Concurrency.dylib 在走 SerialExecutor.isMainExecutor
                // witness table 时拿到 null 函数指针 → SIGSEGV（pc=0x0）。
                // 这是 SDK 级 bug，逐个 callsite 修不完。
                // 该 flag 让编译器**不插入** runtime actor data-race checks，从根源消除崩溃。
                // 编译期 Sendable / actor isolation 静态检查仍然保留。
                // 详见 KNOWN_ISSUES.md。
                .unsafeFlags([
                    "-Xfrontend", "-disable-actor-data-race-checks",
                ]),
            ],
            linkerSettings: [
                // 把 Info.plist 嵌入 __TEXT,__info_plist，让 macOS 识别到 CFBundleIdentifier 与
                // NSPhotoLibrary* usage description；否则 TCC 权限无法稳定授予/持久化。
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Sources/Luma/App/Info.plist",
                ]),
            ]
        ),
        .testTarget(
            name: "LumaTests",
            dependencies: ["Luma"]
        ),
    ]
)
