#!/bin/bash
# 轻聊 2.0 本地 Swift 预检（无 Xcode 环境的替代验证）
# 用法: ./check_swift.sh   （在 ql_ipa2 目录下）
export LD_LIBRARY_PATH=/opt/data/swift-libs
SWIFT=/opt/data/swift-toolchain/swift-6.0.3-RELEASE-ubuntu24.04/usr/bin

echo "=== 1. 语法检查（全部 .swift） ==="
$SWIFT/swiftc -parse qingliao/QingliaoApp.swift qingliao/Core/*.swift qingliao/Features/*/*.swift 2>&1 | grep -v "^$" | head -10
if [ ${PIPESTATUS[0]} -eq 0 ]; then
    echo "✅ 语法通过"
else
    echo "❌ 语法错误（如上）"
    exit 1
fi

echo "=== 2. parseResponse 单元测试 ==="
$SWIFT/swiftc -o /tmp/test_parse scripts/test_parse.swift 2>&1 | head -3
/tmp/test_parse
exit $?
