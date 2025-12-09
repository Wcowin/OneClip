-- OneClip 许可证管理系统数据库初始化脚本
-- 数据库名: oneclip_licensepro
-- 请在MySQL中执行此脚本

USE oneclip_licensepro;

-- 1. 许可证表
CREATE TABLE IF NOT EXISTS licenses (
    id INT AUTO_INCREMENT PRIMARY KEY,
    license_id VARCHAR(50) UNIQUE NOT NULL COMMENT '许可证唯一ID',
    activation_code VARCHAR(20) UNIQUE NOT NULL COMMENT '激活码 (XXXXX-XXXXX-XXXXX)',
    email VARCHAR(100) NOT NULL COMMENT '绑定邮箱',
    plan ENUM('monthly', 'yearly', 'lifetime') NOT NULL COMMENT '许可证类型',
    device_limit INT DEFAULT 5 COMMENT '设备数量限制',
    issued_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP COMMENT '发放时间',
    valid_until TIMESTAMP NULL COMMENT '过期时间 (lifetime为NULL)',
    status ENUM('active', 'suspended', 'revoked') DEFAULT 'active' COMMENT '状态',
    user_hint VARCHAR(200) NULL COMMENT '用户备注',
    source ENUM('manual', 'purchase', 'batch') DEFAULT 'manual' COMMENT '来源：manual=手动生成，purchase=购买生成，batch=批量生成',
    order_id VARCHAR(100) NULL COMMENT '关联订单号（购买生成时）',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_activation_code (activation_code),
    INDEX idx_email (email),
    INDEX idx_status (status),
    INDEX idx_license_id (license_id),
    INDEX idx_source (source),
    INDEX idx_order_id (order_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='许可证信息表';

-- 2. 设备激活记录表
CREATE TABLE IF NOT EXISTS device_activations (
    id INT AUTO_INCREMENT PRIMARY KEY,
    license_id VARCHAR(50) NOT NULL COMMENT '许可证ID',
    device_id VARCHAR(100) NOT NULL COMMENT '设备唯一标识',
    device_name VARCHAR(200) NULL COMMENT '设备名称',
    device_info TEXT NULL COMMENT '设备详细信息(JSON)',
    ip_address VARCHAR(45) NULL COMMENT '激活IP地址',
    activated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP COMMENT '激活时间',
    last_seen_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP COMMENT '最后在线时间',
    is_active BOOLEAN DEFAULT 1 COMMENT '是否激活',
    FOREIGN KEY (license_id) REFERENCES licenses(license_id) ON DELETE CASCADE,
    INDEX idx_license_device (license_id, device_id),
    INDEX idx_device_id (device_id),
    INDEX idx_is_active (is_active)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='设备激活记录表';

-- 3. 激活历史记录表
CREATE TABLE IF NOT EXISTS activation_history (
    id INT AUTO_INCREMENT PRIMARY KEY,
    license_id VARCHAR(50) NOT NULL COMMENT '许可证ID',
    action ENUM('activate', 'deactivate', 'renew', 'revoke') NOT NULL COMMENT '操作类型',
    device_id VARCHAR(100) NULL COMMENT '设备ID',
    ip_address VARCHAR(45) NULL COMMENT '操作IP',
    user_agent TEXT NULL COMMENT '用户代理',
    details TEXT NULL COMMENT '操作详情(JSON)',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (license_id) REFERENCES licenses(license_id) ON DELETE CASCADE,
    INDEX idx_license_id (license_id),
    INDEX idx_action (action),
    INDEX idx_created_at (created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='激活历史记录表';

-- 4. 撤销记录表
CREATE TABLE IF NOT EXISTS revoked_licenses (
    id INT AUTO_INCREMENT PRIMARY KEY,
    license_id VARCHAR(50) UNIQUE NOT NULL COMMENT '许可证ID',
    reason TEXT NOT NULL COMMENT '撤销原因',
    revoked_by VARCHAR(100) NULL COMMENT '撤销操作者',
    revoked_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (license_id) REFERENCES licenses(license_id) ON DELETE CASCADE,
    INDEX idx_license_id (license_id),
    INDEX idx_revoked_at (revoked_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='撤销记录表';

-- 5. 许可证模板表
CREATE TABLE IF NOT EXISTS license_templates (
    id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(100) NOT NULL COMMENT '模板名称',
    plan ENUM('monthly', 'yearly', 'lifetime') NOT NULL COMMENT '许可证类型',
    duration_days INT NULL COMMENT '有效期天数(lifetime为NULL)',
    device_limit INT DEFAULT 5 COMMENT '设备数量限制',
    price DECIMAL(10,2) NULL COMMENT '价格',
    description TEXT NULL COMMENT '描述',
    is_active BOOLEAN DEFAULT 1 COMMENT '是否启用',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_plan (plan),
    INDEX idx_is_active (is_active)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='许可证模板表';

-- 6. 系统配置表
CREATE TABLE IF NOT EXISTS system_config (
    id INT AUTO_INCREMENT PRIMARY KEY,
    config_key VARCHAR(100) UNIQUE NOT NULL COMMENT '配置键',
    config_value TEXT NULL COMMENT '配置值',
    description VARCHAR(200) NULL COMMENT '配置描述',
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_config_key (config_key)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='系统配置表';

-- 插入默认许可证模板 - 统一为前端显示的价格
INSERT INTO license_templates (name, plan, duration_days, device_limit, price, description) VALUES
('月度版', 'monthly', 30, 5, 5.00, '月度订阅，支持5台设备'),
('年度版', 'yearly', 365, 5, 50.00, '年度订阅，支持5台设备，享受8.3折优惠'),
('终身版', 'lifetime', NULL, 5, 29.90, '终身使用，支持5台设备，享受超值优惠');

-- 插入系统配置
INSERT INTO system_config (config_key, config_value, description) VALUES
('max_devices_per_license', '5', '每个许可证最大设备数量'),
('license_expiry_grace_days', '7', '许可证过期宽限期(天)'),
('offline_verification_enabled', 'false', '是否启用离线验证'),
('api_rate_limit', '100', 'API请求频率限制(每分钟)');

-- 创建视图：许可证状态概览
CREATE OR REPLACE VIEW license_overview AS
SELECT 
    l.license_id,
    l.activation_code,
    l.email,
    l.plan,
    l.device_limit,
    l.status,
    l.issued_at,
    l.valid_until,
    COUNT(da.device_id) as active_devices,
    CASE 
        WHEN l.valid_until IS NULL THEN '永久有效'
        WHEN l.valid_until > NOW() THEN CONCAT('剩余 ', DATEDIFF(l.valid_until, NOW()), ' 天')
        ELSE '已过期'
    END as validity_status
FROM licenses l
LEFT JOIN device_activations da ON l.license_id = da.license_id AND da.is_active = 1
GROUP BY l.license_id;

-- 7. 支付订单表
CREATE TABLE IF NOT EXISTS payment_orders (
    id INT AUTO_INCREMENT PRIMARY KEY,
    order_id VARCHAR(100) UNIQUE NOT NULL COMMENT '订单号',
    email VARCHAR(255) NOT NULL COMMENT '用户邮箱',
    plan ENUM('lifetime', 'monthly', 'yearly') NOT NULL COMMENT '许可证类型',
    device_cap INT DEFAULT 5 COMMENT '设备数量限制',
    days INT NULL COMMENT '有效天数(月/年卡)',
    amount DECIMAL(10,2) NOT NULL COMMENT '支付金额',
    status ENUM('pending', 'paid', 'failed', 'cancelled') DEFAULT 'pending' COMMENT '订单状态',
    trade_no VARCHAR(100) NULL COMMENT '易支付交易号',
    license_id VARCHAR(50) NULL COMMENT '生成的许可证ID',
    activation_code VARCHAR(50) NULL COMMENT '生成的激活码',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    paid_at TIMESTAMP NULL COMMENT '支付时间',
    INDEX idx_order_id (order_id),
    INDEX idx_email (email),
    INDEX idx_status (status),
    INDEX idx_created_at (created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='支付订单表';

-- 显示创建结果
SHOW TABLES;
SELECT '数据库表创建完成！' as message;
