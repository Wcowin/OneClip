#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
OneClip 许可证服务器启动器 - 使用正确的账户信息
"""

import os
import sys

# 设置正确的环境变量
os.environ['ADMIN_SECRET_KEY'] = 'oneclip-super-secret-key-2024'
os.environ['ADMIN_USERNAME'] = 'Wcowin'  # 您的正确用户名
os.environ['ADMIN_PASSWORD'] = 'Wkw2003120@'  # 您的正确密码
os.environ['ONECLIP_API_KEY'] = 'oneclip-api-key-2024'

# 设置ZPAY支付配置
os.environ['ZPAY_PID'] = '2025090522454134'
os.environ['ZPAY_KEY'] = '3skhuHdNrNeubD5yDBzhKYL3awo2SC5t'
os.environ['ZPAY_NOTIFY_URL'] = 'https://oneclip.cloud/api/payment/notify'
os.environ['ZPAY_RETURN_URL'] = 'https://oneclip.cloud/api/payment/return'

print("✅ 环境变量已设置")
print(f"🔐 管理员用户名: {os.environ['ADMIN_USERNAME']}")
print("🚀 启动 OneClip 许可证服务器...")

# 执行原始服务器文件
if __name__ == '__main__':
    exec(open('license_api_server.py').read())

