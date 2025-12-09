#!/usr/bin/env python3
"""
🚀 OneClip 增强版许可证管理器
支持邮箱绑定、MySQL数据库、完整的许可证生命周期管理

功能特点:
- 邮箱+激活码双重验证
- MySQL数据库支持
- 设备限制管理
- 完整的激活历史记录
- 许可证撤销和恢复
- 统计报表功能
"""

import argparse
import hashlib
import json
import os
import sys
import time
import uuid
from datetime import datetime, timedelta, timezone
from typing import Dict, Any, Optional, List, Union
import mysql.connector
from mysql.connector import Error

# 字符集：去掉容易混淆的字符 (0,O,1,I,L)
CHARSET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
CHARSET_LENGTH = len(CHARSET)

class EnhancedLicenseManager:
    """增强版许可证管理器"""
    
    def __init__(self, db_config: Dict[str, Any]):
        self.db_config = db_config
        self.connection = None
        self.test_connection()
    
    def test_connection(self):
        """测试数据库连接"""
        try:
            self.connection = mysql.connector.connect(**self.db_config)
            print("✅ 数据库连接成功")
        except Error as e:
            print(f"❌ 数据库连接失败: {e}")
            sys.exit(1)
    

    
    def get_connection(self):
        """获取数据库连接"""
        try:
            # 每次都创建新的连接，避免连接共享导致的问题
            return mysql.connector.connect(**self.db_config)
        except Error as e:
            print(f"❌ 数据库连接失败: {e}")
            raise e
    
    def generate_short_id(self) -> str:
        """生成短ID (11位)"""
        timestamp = int(time.time() * 1000) % (36 ** 6)  # 6位时间戳
        random_part = uuid.uuid4().int % (36 ** 5)  # 5位随机数
        
        combined = timestamp * (36 ** 5) + random_part
        
        result = ""
        for _ in range(11):
            result = CHARSET[combined % CHARSET_LENGTH] + result
            combined //= CHARSET_LENGTH
        
        return result
    
    def calculate_checksum(self, short_id: str) -> str:
        """计算校验码"""
        if len(short_id) != 11:
            return ""
        
        # 使用SHA256计算校验码
        hash_obj = hashlib.sha256(short_id.encode('utf-8'))
        hash_hex = hash_obj.hexdigest()
        
        # 取前4位作为校验码
        checksum = ""
        for i in range(4):
            start_index = i * 2
            end_index = start_index + 2
            hex_byte = hash_hex[start_index:end_index]
            
            int_value = int(hex_byte, 16)
            char_index = int_value % CHARSET_LENGTH
            checksum += CHARSET[char_index]
        
        return checksum
    
    def generate_activation_code(self) -> str:
        """生成激活码"""
        short_id = self.generate_short_id()
        checksum = self.calculate_checksum(short_id)
        
        # 格式化为 XXXXX-XXXXX-XXXXX
        activation_code = f"{short_id[:5]}-{short_id[5:10]}-{short_id[10:11]}{checksum}"
        return activation_code
    
    def generate_license_with_email(self, plan: str, email: str, device_cap: int = 5, 
                                   days: Optional[int] = None, user_hint: Optional[str] = None) -> Dict[str, Any]:
        """生成带邮箱绑定的许可证"""
        try:
            # 验证邮箱格式
            if not self.is_valid_email(email):
                return {"error": "邮箱格式无效"}
            
            # 移除邮箱唯一性限制，允许同一邮箱生成多个激活码
            # 这样用户可以购买多个许可证，或者为不同设备购买许可证
            
            # 规范化套餐与时长
            normalized_plan = (plan or '').strip().lower()
            if normalized_plan not in ('monthly', 'yearly', 'lifetime'):
                return {"error": "未知的套餐类型"}

            # 兼容不同类型的days参数
            if days is not None:
                try:
                    days = int(days)  # 可能来自数据库为Decimal/str
                except Exception:
                    days = None

            # 按套餐给默认时长，避免NULL被误判为终身
            if normalized_plan == 'monthly' and not days:
                days = 31
            if normalized_plan == 'yearly' and not days:
                days = 365

            # 生成激活码
            activation_code = self.generate_activation_code()
            license_id = f"LIC-{uuid.uuid4().hex[:8].upper()}"
            
            # 计算过期时间
            valid_until = None
            if days and normalized_plan != 'lifetime':
                valid_until = datetime.now(timezone.utc) + timedelta(days=days)
            
            # 保存到数据库 - 使用兼容的SQL语句
            conn = self.get_connection()
            cursor = conn.cursor()
            
            # 使用兼容的INSERT语句，不依赖新列
            cursor.execute('''
                INSERT INTO licenses (license_id, activation_code, email, plan, device_limit, 
                                    issued_at, valid_until, user_hint)
                VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
            ''', (license_id, activation_code, email, normalized_plan, device_cap, 
                  datetime.now(timezone.utc), valid_until, user_hint))
            
            conn.commit()
            cursor.close()
            
            print(f"✅ 许可证生成成功:")
            print(f"   许可证ID: {license_id}")
            print(f"   激活码: {activation_code}")
            print(f"   邮箱: {email}")
            print(f"   类型: {normalized_plan}")
            print(f"   设备限制: {device_cap}台")
            if valid_until:
                print(f"   过期时间: {valid_until.strftime('%Y-%m-%d %H:%M:%S')}")
            
            return {
                "license_id": license_id,
                "activation_code": activation_code,
                "email": email,
                "plan": normalized_plan,
                "device_cap": device_cap,
                "valid_until": valid_until.isoformat() if valid_until else None
            }
            
        except Error as e:
            return {"error": f"数据库操作失败: {str(e)}"}
        except Exception as e:
            return {"error": f"生成失败: {str(e)}"}
    
    def verify_license_with_email(self, activation_code: str, email: str, device_id: Optional[str] = None, 
                                 device_name: Optional[str] = None, ip_address: Optional[str] = None) -> Dict[str, Any]:
        """验证邮箱+激活码组合"""
        try:
            conn = self.get_connection()
            cursor = conn.cursor(dictionary=True)
            
            # 查询许可证信息
            cursor.execute('''
                SELECT license_id, plan, device_limit, issued_at, valid_until, 
                       user_hint, status, email
                FROM licenses
                WHERE activation_code = %s AND status = 'active'
            ''', (activation_code,))
            
            result = cursor.fetchone()
            if not result:
                return {"valid": False, "error": "激活码不存在或已停用"}
            
            # 验证邮箱匹配
            if result['email'].lower() != email.lower():
                return {"valid": False, "error": "邮箱与激活码不匹配"}
            
            # 检查有效期
            if result['valid_until']:
                # 确保比较的时间都是带时区的
                now_utc = datetime.now(timezone.utc)
                valid_until = result['valid_until']
                
                # 如果数据库时间没有时区信息，假设为UTC
                if valid_until.tzinfo is None:
                    valid_until = valid_until.replace(tzinfo=timezone.utc)
                
                if now_utc > valid_until:
                    return {"valid": False, "error": "激活码已过期"}
            
            # 处理设备激活
            if device_id:
                # 首先检查设备是否已存在
                cursor.execute('''
                    SELECT is_active FROM device_activations 
                    WHERE license_id = %s AND device_id = %s
                ''', (result['license_id'], device_id))
                
                existing_device = cursor.fetchone()
                
                if existing_device:
                    if existing_device['is_active'] == 1:
                        # 设备已激活，更新最后活跃时间
                        cursor.execute('''
                            UPDATE device_activations 
                            SET last_seen_at = %s, device_name = %s, ip_address = %s
                            WHERE license_id = %s AND device_id = %s
                        ''', (datetime.now(timezone.utc), device_name, ip_address, result['license_id'], device_id))
                        
                        # 记录心跳
                        cursor.execute('''
                            INSERT INTO activation_history (license_id, action, device_id, ip_address, details)
                            VALUES (%s, 'heartbeat', %s, %s, %s)
                        ''', (result['license_id'], device_id, ip_address, json.dumps({"device_name": device_name})))
                        
                        conn.commit()
                        cursor.close()
                        
                        return {
                            "valid": True,
                            "license_id": result['license_id'],
                            "plan": result['plan'],
                            "device_cap": result['device_limit'],
                            "issued_at": result['issued_at'].isoformat() if result['issued_at'] else None,
                            "valid_until": result['valid_until'].isoformat() if result['valid_until'] else None,
                            "user_hint": result['user_hint'],
                            "message": "设备已激活"
                        }
                    else:
                        # 设备被停用
                        return {"valid": False, "error": "设备已被停用，请联系管理员恢复"}
                else:
                    # 新设备，检查槽位是否可用
                    cursor.execute('''
                        SELECT COUNT(*) as count FROM device_activations 
                        WHERE license_id = %s AND is_active = 1
                    ''', (result['license_id'],))
                    current_devices = cursor.fetchone()['count']
                    
                    if current_devices >= result['device_limit']:
                        return {"valid": False, "error": f"设备数量已达上限({result['device_limit']}台)"}
                    
                    # 激活新设备
                    cursor.execute('''
                        INSERT INTO device_activations 
                        (license_id, device_id, device_name, ip_address, last_seen_at, is_active) 
                        VALUES (%s, %s, %s, %s, %s, 1)
                    ''', (result['license_id'], device_id, device_name, ip_address, datetime.now(timezone.utc)))
                    
                    # 记录激活历史
                    cursor.execute('''
                        INSERT INTO activation_history (license_id, action, device_id, ip_address, details)
                        VALUES (%s, 'activate', %s, %s, %s)
                    ''', (result['license_id'], device_id, ip_address, json.dumps({"device_name": device_name})))
                    
                    conn.commit()
                    cursor.close()
            
            cursor.close()
            
            return {
                "valid": True,
                "license_id": result['license_id'],
                "plan": result['plan'],
                "device_cap": result['device_limit'],
                "issued_at": result['issued_at'].isoformat() if result['issued_at'] else None,
                "valid_until": result['valid_until'].isoformat() if result['valid_until'] else None,
                "user_hint": result['user_hint']
            }
            
        except Error as e:
            return {"valid": False, "error": f"数据库操作失败: {str(e)}"}
        except Exception as e:
            return {"valid": False, "error": f"验证失败: {str(e)}"}
    
    def revoke_license(self, license_id: str, reason: str, revoked_by: Optional[str] = None) -> bool:
        """撤销许可证"""
        try:
            conn = self.get_connection()
            cursor = conn.cursor()
            
            # 检查许可证是否存在
            cursor.execute('SELECT 1 FROM licenses WHERE license_id = %s', (license_id,))
            if not cursor.fetchone():
                return False
            
            # 添加到撤销列表
            cursor.execute('''
                INSERT INTO revoked_licenses (license_id, reason, revoked_by)
                VALUES (%s, %s, %s)
                ON DUPLICATE KEY UPDATE reason = VALUES(reason), revoked_by = VALUES(revoked_by)
            ''', (license_id, reason, revoked_by))
            
            # 停用许可证
            cursor.execute('UPDATE licenses SET status = "revoked" WHERE license_id = %s', (license_id,))
            
            # 记录撤销历史
            cursor.execute('''
                INSERT INTO activation_history (license_id, action, details)
                VALUES (%s, 'revoke', %s)
            ''', (license_id, json.dumps({"reason": reason, "revoked_by": revoked_by})))
            
            conn.commit()
            cursor.close()
            
            print(f"✅ 许可证 {license_id} 已撤销，原因: {reason}")
            return True
            
        except Error as e:
            print(f"❌ 撤销许可证失败: {e}")
            return False

    def deactivate_device(self, license_id: str, device_id: str, reason: str = "管理员停用") -> bool:
        """停用设备"""
        try:
            conn = self.get_connection()
            cursor = conn.cursor()
            
            # 检查设备是否存在
            cursor.execute('''
                SELECT 1 FROM device_activations 
                WHERE license_id = %s AND device_id = %s
            ''', (license_id, device_id))
            
            if not cursor.fetchone():
                print(f"❌ 设备不存在: {license_id} - {device_id}")
                return False
            
            # 停用设备
            cursor.execute('''
                UPDATE device_activations 
                SET is_active = 0 
                WHERE license_id = %s AND device_id = %s
            ''', (license_id, device_id))
            
            # 记录停用历史
            cursor.execute('''
                INSERT INTO activation_history (license_id, action, device_id, details)
                VALUES (%s, 'deactivate', %s, %s)
            ''', (license_id, device_id, json.dumps({"reason": reason, "deactivated_by": "admin"})))
            
            conn.commit()
            cursor.close()
            
            print(f"✅ 设备已停用: {license_id} - {device_id}")
            return True
            
        except Error as e:
            print(f"❌ 停用设备失败: {e}")
            return False

    def activate_device(self, license_id: str, device_id: str, reason: str = "管理员恢复") -> bool:
        """恢复设备"""
        try:
            conn = self.get_connection()
            cursor = conn.cursor()
            
            # 检查设备是否存在
            cursor.execute('''
                SELECT 1 FROM device_activations 
                WHERE license_id = %s AND device_id = %s
            ''', (license_id, device_id))
            
            if not cursor.fetchone():
                print(f"❌ 设备不存在: {license_id} - {device_id}")
                return False
            
            # 恢复设备
            cursor.execute('''
                UPDATE device_activations 
                SET is_active = 1 
                WHERE license_id = %s AND device_id = %s
            ''', (license_id, device_id))
            
            # 记录恢复历史
            cursor.execute('''
                INSERT INTO activation_history (license_id, action, device_id, details)
                VALUES (%s, 'renew', %s, %s)
            ''', (license_id, device_id, json.dumps({"reason": reason, "activated_by": "admin"})))
            
            conn.commit()
            cursor.close()
            
            print(f"✅ 设备已恢复: {license_id} - {device_id}")
            return True
            
        except Error as e:
            print(f"❌ 恢复设备失败: {e}")
            return False

    def cancel_device_activation(self, license_id: str, device_id: str, reason: str = "用户取消激活") -> bool:
        """用户取消设备激活（释放设备槽位）"""
        try:
            conn = self.get_connection()
            cursor = conn.cursor()
            
            # 检查设备是否存在且处于激活状态
            cursor.execute('''
                SELECT 1 FROM device_activations 
                WHERE license_id = %s AND device_id = %s AND is_active = 1
            ''', (license_id, device_id))
            
            if not cursor.fetchone():
                print(f"❌ 设备不存在或未激活: {license_id} - {device_id}")
                return False
            
            # 取消激活（删除记录，释放槽位）
            cursor.execute('''
                DELETE FROM device_activations 
                WHERE license_id = %s AND device_id = %s
            ''', (license_id, device_id))
            
            # 记录取消激活历史
            cursor.execute('''
                INSERT INTO activation_history (license_id, action, device_id, details)
                VALUES (%s, 'cancel', %s, %s)
            ''', (license_id, device_id, json.dumps({"reason": reason, "canceled_by": "user"})))
            
            conn.commit()
            cursor.close()
            
            print(f"✅ 设备激活已取消: {license_id} - {device_id}")
            return True
            
        except Error as e:
            print(f"❌ 取消设备激活失败: {e}")
            return False

    def get_device_activation_status(self, license_id: str, device_id: str) -> Dict[str, Any]:
        """获取设备激活状态"""
        try:
            conn = self.get_connection()
            cursor = conn.cursor(dictionary=True)
            
            cursor.execute('''
                SELECT da.*, l.activation_code, l.email, l.device_limit
                FROM device_activations da
                JOIN licenses l ON da.license_id = l.license_id
                WHERE da.license_id = %s AND da.device_id = %s
            ''', (license_id, device_id))
            
            result = cursor.fetchone()
            cursor.close()
            
            if result:
                return {
                    'exists': True,
                    'is_active': bool(result['is_active']),
                    'device_name': result['device_name'],
                    'ip_address': result['ip_address'],
                    'last_seen_at': result['last_seen_at'].isoformat() if result['last_seen_at'] else None,
                    'activation_code': result['activation_code'],
                    'email': result['email'],
                    'device_limit': result['device_limit']
                }
            else:
                return {'exists': False}
                
        except Error as e:
            print(f"❌ 获取设备状态失败: {e}")
            return {'exists': False, 'error': str(e)}
    
    def get_license_statistics(self) -> Dict[str, Any]:
        """获取许可证统计信息"""
        conn = None
        cursor = None
        try:
            conn = self.get_connection()
            cursor = conn.cursor(dictionary=True)
            
            # 总许可证数
            cursor.execute('SELECT COUNT(*) as count FROM licenses')
            total_licenses = cursor.fetchone()['count']
            
            # 活跃许可证数
            cursor.execute('SELECT COUNT(*) as count FROM licenses WHERE status = "active"')
            active_licenses = cursor.fetchone()['count']
            
            # 按类型统计
            cursor.execute('''
                SELECT plan, COUNT(*) as count FROM licenses 
                WHERE status = "active" GROUP BY plan
            ''')
            plan_stats = {row['plan']: row['count'] for row in cursor.fetchall()}
            
            # 设备激活统计
            cursor.execute('SELECT COUNT(*) as count FROM device_activations WHERE is_active = 1')
            active_devices = cursor.fetchone()['count']
            
            # 最近激活统计
            cursor.execute('''
                SELECT DATE(created_at) as date, COUNT(*) as count 
                FROM activation_history 
                WHERE action = 'activate' 
                AND created_at >= DATE_SUB(NOW(), INTERVAL 30 DAY)
                GROUP BY DATE(created_at)
                ORDER BY date DESC
            ''')
            recent_activations = cursor.fetchall()
            
            return {
                "total_licenses": total_licenses,
                "active_licenses": active_licenses,
                "plan_statistics": plan_stats,
                "active_devices": active_devices,
                "recent_activations": recent_activations
            }
            
        except Error as e:
            return {"error": f"获取统计失败: {str(e)}"}
        finally:
            if cursor:
                cursor.close()
            if conn:
                conn.close()
    
    def list_licenses(self, status: Optional[str] = None, limit: int = 100) -> List[Dict[str, Any]]:
        """列出许可证"""
        try:
            conn = self.get_connection()
            cursor = conn.cursor(dictionary=True)
            
            query = '''
                SELECT l.*, 
                       COUNT(da.device_id) as active_devices,
                       CASE 
                           WHEN l.valid_until IS NULL THEN '永久有效'
                           WHEN l.valid_until > NOW() THEN CONCAT('剩余 ', DATEDIFF(l.valid_until, NOW()), ' 天')
                           ELSE '已过期'
                       END as validity_status
                FROM licenses l
                LEFT JOIN device_activations da ON l.license_id = da.license_id AND da.is_active = 1
            '''
            
            params = []
            if status:
                query += ' WHERE l.status = %s'
                params.append(status)
            
            query += ' GROUP BY l.license_id ORDER BY l.created_at DESC LIMIT %s'
            params.append(limit)
            
            cursor.execute(query, params)
            licenses = cursor.fetchall()
            cursor.close()
            
            return licenses
            
        except Error as e:
            return [{"error": f"查询失败: {str(e)}"}]
    
    def is_valid_email(self, email: str) -> bool:
        """验证邮箱格式"""
        import re
        pattern = r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$'
        return re.match(pattern, email) is not None
    
    def is_email_already_used(self, email: str) -> bool:
        """检查邮箱是否已被使用（已废弃，保留兼容性）"""
        # 移除邮箱唯一性限制，允许同一邮箱生成多个激活码
        return False
    
    def batch_generate(self, plan: str, count: int, emails: List[str], device_cap: int = 5,
                       days: Optional[int] = None, user_hint: Optional[str] = None) -> List[Dict[str, Any]]:
        """批量生成许可证"""
        if len(emails) != count:
            return [{"error": f"邮箱数量({len(emails)})与许可证数量({count})不匹配"}]
        
        licenses = []
        print(f"🚀 开始批量生成 {count} 个{plan}许可证...")
        
        for i, email in enumerate(emails, 1):
            print(f"📧 正在生成第 {i}/{count} 个许可证，邮箱: {email}")
            
            try:
                license_data = self.generate_license_with_email(plan, email, device_cap, days, user_hint)
                if "error" not in license_data:
                    licenses.append(license_data)
                    print(f"✅ 第 {i} 个许可证生成成功")
                else:
                    print(f"❌ 第 {i} 个许可证生成失败: {license_data['error']}")
            except Exception as e:
                print(f"❌ 第 {i} 个许可证生成异常: {str(e)}")
        
        print(f"🎉 批量生成完成！成功: {len(licenses)}/{count}")
        return licenses

def main():
    parser = argparse.ArgumentParser(description='OneClip 增强版许可证管理器')
    parser.add_argument('--action', required=True, choices=['generate', 'verify', 'revoke', 'stats', 'list', 'batch'],
                       help='操作类型')
    parser.add_argument('--plan', choices=['monthly', 'yearly', 'lifetime'], help='许可证类型')
    parser.add_argument('--email', help='绑定邮箱')
    parser.add_argument('--activation-code', help='激活码')
    parser.add_argument('--device-cap', type=int, default=5, help='设备数量限制')
    parser.add_argument('--days', type=int, help='有效期天数')
    parser.add_argument('--user-hint', help='用户备注')
    parser.add_argument('--license-id', help='许可证ID')
    parser.add_argument('--reason', help='撤销原因')
    parser.add_argument('--count', type=int, help='批量生成数量')
    parser.add_argument('--emails-file', help='邮箱列表文件路径')
    parser.add_argument('--status', choices=['active', 'suspended', 'revoked'], help='许可证状态')
    
    args = parser.parse_args()
    
    # 数据库配置
    db_config = {
        'host': '118.25.195.204',
        'port': 3306,
        'user': 'oneclip_licensepro',
        'password': 'Wkw2003120@',
        'database': 'oneclip_licensepro',
        'charset': 'utf8mb4'
    }
    
    manager = EnhancedLicenseManager(db_config)
    
    try:
        if args.action == 'generate':
            if not args.plan or not args.email:
                print("❌ 生成许可证需要指定 --plan 和 --email")
                return
            
            result = manager.generate_license_with_email(
                args.plan, args.email, args.device_cap, args.days, args.user_hint
            )
            if "error" in result:
                print(f"❌ 生成失败: {result['error']}")
            else:
                print("✅ 许可证生成成功")
        
        elif args.action == 'verify':
            if not args.activation_code or not args.email:
                print("❌ 验证许可证需要指定 --activation-code 和 --email")
                return
            
            result = manager.verify_license_with_email(args.activation_code, args.email)
            if result["valid"]:
                print("✅ 许可证验证成功")
                print(f"   许可证ID: {result['license_id']}")
                print(f"   类型: {result['plan']}")
                print(f"   设备限制: {result['device_cap']}台")
            else:
                print(f"❌ 许可证验证失败: {result['error']}")
        
        elif args.action == 'revoke':
            if not args.license_id or not args.reason:
                print("❌ 撤销许可证需要指定 --license-id 和 --reason")
                return
            
            if manager.revoke_license(args.license_id, args.reason):
                print("✅ 许可证撤销成功")
            else:
                print("❌ 许可证撤销失败")
        
        elif args.action == 'stats':
            stats = manager.get_license_statistics()
            if "error" in stats:
                print(f"❌ 获取统计失败: {stats['error']}")
            else:
                print("📊 许可证统计信息:")
                print(f"   总许可证数: {stats['total_licenses']}")
                print(f"   活跃许可证数: {stats['active_licenses']}")
                print(f"   活跃设备数: {stats['active_devices']}")
                print(f"   按类型统计: {stats['plan_statistics']}")
        
        elif args.action == 'list':
            licenses = manager.list_licenses(args.status, 50)
            if licenses and "error" in licenses[0]:
                print(f"❌ 查询失败: {licenses[0]['error']}")
            else:
                print(f"📋 许可证列表 (共 {len(licenses)} 个):")
                for license in licenses:
                    print(f"   {license['license_id']} | {license['email']} | {license['plan']} | {license['validity_status']}")
        
        elif args.action == 'batch':
            if not args.count or not args.emails_file:
                print("❌ 批量生成需要指定 --count 和 --emails-file")
                return
            
            # 读取邮箱列表
            try:
                with open(args.emails_file, 'r', encoding='utf-8') as f:
                    emails = [line.strip() for line in f if line.strip()]
                
                if len(emails) < args.count:
                    print(f"❌ 邮箱文件中的邮箱数量({len(emails)})少于指定数量({args.count})")
                    return
                
                result = manager.batch_generate(args.plan, args.count, emails[:args.count], 
                                             args.device_cap, args.days, args.user_hint)
                
            except FileNotFoundError:
                print(f"❌ 邮箱文件不存在: {args.emails_file}")
            except Exception as e:
                print(f"❌ 读取邮箱文件失败: {str(e)}")
    
    except KeyboardInterrupt:
        print("\n⚠️ 操作被用户中断")
    except Exception as e:
        print(f"❌ 操作失败: {str(e)}")
    finally:
        if manager.connection and manager.connection.is_connected():
            manager.connection.close()

if __name__ == "__main__":
    main()
