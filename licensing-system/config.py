# OneClip 许可证系统配置文件

# 数据库配置
DB_CONFIG = {
    'host': '118.25.195.204',
    'port': 3306,
    'user': 'oneclip_licensepro',
    'password': 'Wkw2003120@',
    'database': 'oneclip_licensepro',
    'charset': 'utf8mb4'
}

# ZPAY支付配置
ZPAY_CONFIG = {
    'api_url': 'https://zpayz.cn/',
    'pid': '2025090522454134',  # 商户ID
    'key': '3skhuHdNrNeubD5yDBzhKYL3awo2SC5t',  # 商户密钥
    'notify_url': 'https://oneclip.cloud/api/payment/notify',
    'return_url': 'https://oneclip.cloud/api/payment/return'
}

# 易支付配置（保留作为备份）
YIPAY_CONFIG = {
    'api_url': 'https://pay.myzfw.com/',
    'merchant_id': '15632',
    'md5_key': 'E1a4hAGICpa61gpIlP6ppyPplfyYhAlh',
    'notify_url': 'https://oneclip.cloud/api/payment/notify',
    'return_url': 'https://oneclip.cloud/api/payment/return'
}

# 邮件配置
EMAIL_CONFIG = {
    'smtp_server': 'smtp.exmail.qq.com',  # 腾讯企业邮箱SMTP
    'smtp_port': 465,
    'smtp_user': 'vip@oneclip.cloud',  # 企业邮箱
    'smtp_password': 'DFEB7DWQaPdTEwcv',  # 腾讯企业邮箱密码
    'from_email': 'vip@oneclip.cloud',
    'from_name': 'OneClip 许可证系统'
}

# 许可证价格配置 - 统一为前端显示的价格
LICENSE_PRICES = {
    'monthly': {
        'base_price': 5.00,  # ¥5.00 /月
        'device_price': 2.00,  # 每台额外设备的价格
        'duration_days': 31,
        'display_name': '月度版',
        'description': '月度订阅，支持5台设备'
    },
    'yearly': {
        'base_price': 50.00,  # ¥50.00 /年
        'device_price': 3.00,
        'duration_days': 365,
        'display_name': '年度版',
        'description': '年度订阅，支持5台设备，享受8.3折优惠'
    },
    'lifetime': {
        'base_price': 29.90,  # ¥29.90 /终身
        'device_price': 5.00,
        'duration_days': None,
        'display_name': '终身版',
        'description': '终身使用，支持5台设备，享受超值优惠'
    }
}

# 系统配置
SYSTEM_CONFIG = {
    'max_devices_per_license': 20,
    'default_device_limit': 5,
    'order_expiry_hours': 24,  # 订单过期时间（小时）
    'max_orders_per_email_per_day': 5  # 每个邮箱每天最大订单数
}
