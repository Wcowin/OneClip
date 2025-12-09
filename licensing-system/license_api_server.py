#!/usr/bin/env python3
"""
🌐 OneClip 许可证验证 Web API 服务器
接收应用的HTTP请求，验证许可证并返回结果
"""

from flask import Flask, request, jsonify, session, redirect, send_from_directory, Response
from flask_cors import CORS
import json
import os
import sys
from datetime import datetime, timezone, timedelta
import logging
import time
import uuid

# 添加当前目录到Python路径
sys.path.append(os.path.dirname(os.path.abspath(__file__)))

from enhanced_license_manager import EnhancedLicenseManager

# 配置日志
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = Flask(__name__)
# 为会话设置密钥（请在生产环境通过环境变量设置）
SECRET_KEY = os.getenv('ADMIN_SECRET_KEY')
if not SECRET_KEY:
    raise ValueError("ADMIN_SECRET_KEY 环境变量未设置")
app.secret_key = SECRET_KEY
# 允许跨域，同时支持凭据（用于同源下的会话 Cookie）
CORS(app, supports_credentials=True)

# 数据库配置
DB_CONFIG = {
    'host': os.getenv('DB_HOST', '118.25.195.204'),
    'port': int(os.getenv('DB_PORT', '3306')),
    'user': os.getenv('DB_USER', 'oneclip_licensepro'),
    'password': os.getenv('DB_PASSWORD'),  # ✅ 从环境变量读取，安全
    'database': os.getenv('DB_NAME', 'oneclip_licensepro'),
    'charset': 'utf8mb4'
}

# 🔒 安全检查：确保关键环境变量已设置
if not DB_CONFIG['password']:
    raise ValueError("❌ DB_PASSWORD 环境变量未设置！请先设置: export DB_PASSWORD='your_password'")

# 初始化许可证管理器
license_manager = EnhancedLicenseManager(DB_CONFIG)

# 管理后台配置（用户名和密码从环境变量读取）
ADMIN_USERNAME = os.getenv('ADMIN_USERNAME', os.getenv('ONECLIP_ADMIN_USERNAME'))
ADMIN_PASSWORD = os.getenv('ADMIN_PASSWORD', os.getenv('ONECLIP_ADMIN_PASSWORD'))

# API 密钥配置（用于客户端验证）
API_KEY = os.getenv('ONECLIP_API_KEY')

# 安全检查：确保关键配置已设置
if not ADMIN_USERNAME:
    raise ValueError("ADMIN_USERNAME 环境变量未设置")
if not ADMIN_PASSWORD:
    raise ValueError("ADMIN_PASSWORD 环境变量未设置")
if not API_KEY:
    raise ValueError("ONECLIP_API_KEY 环境变量未设置")

# 安全配置
import time
from functools import wraps

# 登录失败记录
login_attempts = {}
MAX_LOGIN_ATTEMPTS = 5
LOGIN_LOCKOUT_TIME = 3600  # 1小时
SESSION_TIMEOUT = 3600  # 1小时

def require_api_key(f):
    """API 密钥验证装饰器"""
    @wraps(f)
    def decorated_function(*args, **kwargs):
        api_key = request.headers.get('X-API-Key')
        if not api_key or api_key != API_KEY:
            logger.warning(f"❌ API密钥验证失败: {request.remote_addr}")
            return jsonify({
                'success': False,
                'message': 'API密钥无效',
                'code': 'INVALID_API_KEY'
            }), 401
        return f(*args, **kwargs)
    return decorated_function

def check_login_attempts(ip):
    """检查登录尝试次数"""
    now = time.time()
    if ip not in login_attempts:
        login_attempts[ip] = []
    
    # 清理1小时前的记录
    login_attempts[ip] = [t for t in login_attempts[ip] if now - t < LOGIN_LOCKOUT_TIME]
    
    # 检查是否超过5次失败
    if len(login_attempts[ip]) >= MAX_LOGIN_ATTEMPTS:
        return False
    
    return True

def record_login_attempt(ip, success):
    """记录登录尝试"""
    if not success:
        login_attempts[ip] = login_attempts.get(ip, []) + [time.time()]

def log_admin_operation(operation, details=None):
    """记录管理员操作"""
    try:
        conn = license_manager.get_connection()
        cur = conn.cursor()
        
        # 创建操作日志表（如果不存在）
        cur.execute('''
            CREATE TABLE IF NOT EXISTS admin_operation_logs (
                id INT AUTO_INCREMENT PRIMARY KEY,
                operation VARCHAR(100) NOT NULL,
                details TEXT,
                admin_ip VARCHAR(45),
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                INDEX idx_operation (operation),
                INDEX idx_admin_ip (admin_ip),
                INDEX idx_created_at (created_at)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
        ''')
        
        cur.execute('''
            INSERT INTO admin_operation_logs 
            (operation, details, admin_ip, created_at)
            VALUES (%s, %s, %s, %s)
        ''', (
            operation,
            json.dumps(details) if details else None,
            request.remote_addr,
            datetime.now(timezone.utc)
        ))
        
        conn.commit()
        cur.close()
        
    except Exception as e:
        logger.error(f"记录操作日志失败: {str(e)}")

def is_admin_logged_in() -> bool:
    """检查管理员是否已登录且会话未超时"""
    if not session.get('admin_logged_in'):
        return False
    
    # 检查会话超时
    login_time = session.get('login_time', 0)
    if time.time() - login_time > SESSION_TIMEOUT:
        session.clear()
        return False
    
    return True

def require_admin():
    """要求管理员登录装饰器"""
    if not is_admin_logged_in():
        return jsonify({'success': False, 'message': '未登录或会话已超时', 'code': 'UNAUTHORIZED'}), 401
    return None

@app.before_request
def check_session_timeout():
    """检查会话超时"""
    # 仅对后台页面路由 (/admin...) 做重定向；API (/api/...) 不在此处重定向，未登录时由各 API 返回 401
    if request.path.startswith('/admin') and request.endpoint and request.endpoint.startswith('admin'):
        # 允许的无需登录端点：后台登录页面与登录提交接口
        allowed_endpoints = {'admin_login_page', 'admin_login'}
        if 'admin_logged_in' in session:
            login_time = session.get('login_time', 0)
            if time.time() - login_time > SESSION_TIMEOUT:
                session.clear()
                if request.endpoint not in allowed_endpoints:
                    return redirect('/admin/login')
        elif request.endpoint not in allowed_endpoints:
            return redirect('/admin/login')

# -------------------------
# 静态文件目录配置
# -------------------------
# 获取当前脚本所在目录
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
ADMIN_DIR = os.path.join(BASE_DIR, 'admin')
STATIC_DIR = BASE_DIR  # 静态文件目录

# 打印调试信息
logger.info(f"🔧 Flask应用启动信息:")
logger.info(f"   当前工作目录: {os.getcwd()}")
logger.info(f"   脚本所在目录: {BASE_DIR}")
logger.info(f"   管理后台目录: {ADMIN_DIR}")
logger.info(f"   静态文件目录: {STATIC_DIR}")
logger.info(f"   静态文件列表: {[f for f in os.listdir(STATIC_DIR) if f.endswith('.html')]}")

@app.route('/admin/login', methods=['GET'])
def admin_login_page():
    # 提供登录页面
    return send_from_directory(ADMIN_DIR, 'login.html')

@app.route('/admin', methods=['GET'])
def admin_index_page():
    # 未登录则跳转到登录页
    if not is_admin_logged_in():
        return redirect('/admin/login')
    return send_from_directory(ADMIN_DIR, 'index.html')

@app.route('/admin/<path:filename>', methods=['GET'])
def admin_static_file(filename):
    # 提供静态资源（js/css等）
    return send_from_directory(ADMIN_DIR, filename)

@app.route('/')
def index_page():
    """首页"""
    try:
        logger.info(f"🔍 访问首页: {STATIC_DIR}/index.html")
        return send_from_directory(STATIC_DIR, 'index.html')
    except Exception as e:
        logger.error(f"❌ 首页加载失败: {str(e)}")
        return jsonify({
            'code': 'FILE_NOT_FOUND',
            'message': f'首页文件未找到: {str(e)}',
            'success': False
        }), 404

@app.route('/purchase')
def purchase_page():
    try:
        logger.info(f"🔍 访问购买页面: {STATIC_DIR}/purchase.html")
        return send_from_directory(STATIC_DIR, 'purchase.html')
    except Exception as e:
        logger.error(f"❌ 购买页面加载失败: {str(e)}")
        return jsonify({
            'code': 'FILE_NOT_FOUND',
            'message': f'购买页面文件未找到: {str(e)}',
            'success': False
        }), 404

@app.route('/purchase/monthly')
def purchase_monthly():
    """月度版购买页面"""
    try:
        logger.info(f"🔍 访问月度版页面: {STATIC_DIR}/purchase_monthly.html")
        return send_from_directory(STATIC_DIR, 'purchase_monthly.html')
    except Exception as e:
        logger.error(f"❌ 月度版页面加载失败: {str(e)}")
        return jsonify({
            'code': 'FILE_NOT_FOUND',
            'message': f'月度版页面文件未找到: {str(e)}',
            'success': False
        }), 404

@app.route('/purchase/yearly')
def purchase_yearly():
    """年度版购买页面"""
    try:
        logger.info(f"🔍 访问年度版页面: {STATIC_DIR}/purchase_yearly.html")
        return send_from_directory(STATIC_DIR, 'purchase_yearly.html')
    except Exception as e:
        logger.error(f"❌ 年度版页面加载失败: {str(e)}")
        return jsonify({
            'code': 'FILE_NOT_FOUND',
            'message': f'年度版页面文件未找到: {str(e)}',
            'success': False
        }), 404

@app.route('/purchase/lifetime')
def purchase_lifetime():
    """终身版购买页面"""
    try:
        logger.info(f"🔍 访问终身版页面: {STATIC_DIR}/purchase_lifetime.html")
        return send_from_directory(STATIC_DIR, 'purchase_lifetime.html')
    except Exception as e:
        logger.error(f"❌ 终身版页面加载失败: {str(e)}")
        return jsonify({
            'code': 'FILE_NOT_FOUND',
            'message': f'终身版页面文件未找到: {str(e)}',
            'success': False
        }), 404

@app.route('/robots.txt')
def robots_txt():
    """提供 robots.txt 文件"""
    try:
        logger.info(f"🔍 访问 robots.txt: {STATIC_DIR}/robots.txt")
        return send_from_directory(STATIC_DIR, 'robots.txt', mimetype='text/plain')
    except Exception as e:
        logger.error(f"❌ robots.txt 文件加载失败: {str(e)}")
        return jsonify({
            'code': 'FILE_NOT_FOUND',
            'message': f'robots.txt 文件未找到: {str(e)}',
            'success': False
        }), 404

@app.route('/sitemap.xml', methods=['GET'])
def sitemap():
    """提供 sitemap.xml 文件"""
    try:
        logger.info(f"🔍 访问 sitemap.xml: {STATIC_DIR}/sitemap.xml")
        return send_from_directory(STATIC_DIR, 'sitemap.xml', mimetype='application/xml')
    except Exception as e:
        logger.error(f"❌ sitemap.xml 文件加载失败: {str(e)}")
        return jsonify({
            'code': 'NOT_FOUND',
            'message': 'sitemap.xml 文件未找到',
            'success': False
        }), 404

@app.route('/favicon.ico', methods=['GET'])
def favicon():
    """提供网站图标"""
    try:
        logger.info(f"🔍 访问 favicon.ico: {STATIC_DIR}/favicon.png")
        return send_from_directory(STATIC_DIR, 'favicon.png', mimetype='image/png')
    except Exception as e:
        logger.error(f"❌ favicon 加载失败: {str(e)}")
        return '', 404

@app.route('/apple-touch-icon.png', methods=['GET'])
def apple_touch_icon():
    """提供 Apple 设备图标"""
    try:
        return send_from_directory(STATIC_DIR, 'apple-touch-icon.png', mimetype='image/png')
    except Exception as e:
        logger.error(f"❌ Apple touch icon 加载失败: {str(e)}")
        return '', 404

# ==================== 腾讯云站长验证文件服务 ====================
@app.route('/tencent<verification_code>.txt')
def tencent_verification(verification_code):
    """处理腾讯云站长验证文件请求"""
    try:
        # 构建文件名
        filename = f"tencent{verification_code}.txt"
        logger.info(f"🔍 访问腾讯云验证文件: {STATIC_DIR}/{filename}")
        
        # 直接使用send_from_directory服务静态文件
        return send_from_directory(STATIC_DIR, filename, mimetype='text/plain')
        
    except Exception as e:
        logger.error(f"❌ 腾讯云验证文件加载失败: {str(e)}")
        return jsonify({
            'code': 'FILE_NOT_FOUND',
            'message': f'验证文件未找到: {str(e)}',
            'success': False
        }), 404

# ==================== PDF 和其他文档文件服务 ====================
@app.route('/<filename>', methods=['GET'])
def serve_pdf_and_docs(filename):
    """提供 PDF、文档等静态文件"""
    # 只处理特定的文件类型，拒绝 API 请求
    allowed_extensions = ('.pdf', '.txt', '.md', '.doc', '.docx')
    
    # 安全检查：拒绝 API 和其他特殊路径
    if filename.startswith('api') or filename.startswith('admin') or '/' in filename:
        return jsonify({'code': 'NOT_FOUND', 'message': 'API端点不存在', 'success': False}), 404
    
    if not filename.lower().endswith(allowed_extensions):
        return jsonify({'code': 'NOT_FOUND', 'message': 'API端点不存在', 'success': False}), 404
    
    try:
        file_path = os.path.join(STATIC_DIR, filename)
        
        # 安全检查：防止目录遍历
        if not os.path.abspath(file_path).startswith(os.path.abspath(STATIC_DIR)):
            logger.warning(f"⚠️ 非法文件访问尝试: {filename}")
            return jsonify({'code': 'FORBIDDEN', 'message': '禁止访问', 'success': False}), 403
        
        if os.path.isfile(file_path):
            logger.info(f"📄 提供文件: {filename}")
            
            # 根据文件类型设置正确的 MIME 类型
            if filename.lower().endswith('.pdf'):
                mimetype = 'application/pdf'
            elif filename.lower().endswith('.txt'):
                mimetype = 'text/plain'
            elif filename.lower().endswith('.md'):
                mimetype = 'text/markdown'
            else:
                mimetype = 'application/octet-stream'
            
            return send_from_directory(STATIC_DIR, filename, mimetype=mimetype)
        else:
            logger.warning(f"⚠️ 文件未找到: {filename}")
            return jsonify({'code': 'NOT_FOUND', 'message': '文件未找到', 'success': False}), 404
    except Exception as e:
        logger.error(f"❌ 文件服务失败: {filename}, 错误: {str(e)}")
        return jsonify({'code': 'ERROR', 'message': f'文件访问失败', 'success': False}), 500

@app.route('/complete_order_page.html', methods=['GET'])
def complete_order_page():
    """订单完成页面"""
    try:
        logger.info(f"🔍 访问订单完成页面: {STATIC_DIR}/complete_order_page.html")
        return send_from_directory(STATIC_DIR, 'complete_order_page.html')
    except Exception as e:
        logger.error(f"❌ 订单完成页面加载失败: {str(e)}")
        return jsonify({
            'code': 'FILE_NOT_FOUND',
            'message': f'订单完成页面文件未找到: {str(e)}',
            'success': False
        }), 404

# -------------------------
# 文档页面路由
# -------------------------
@app.route('/docs.html', methods=['GET'])
def docs_index():
    """文档首页"""
    try:
        logger.info(f"🔍 访问文档首页: {STATIC_DIR}/docs.html")
        return send_from_directory(STATIC_DIR, 'docs.html')
    except Exception as e:
        logger.error(f"❌ 文档首页加载失败: {str(e)}")
        return jsonify({
            'code': 'FILE_NOT_FOUND',
            'message': f'文档页面未找到: {str(e)}',
            'success': False
        }), 404

@app.route('/docs-getting-started.html', methods=['GET'])
def docs_getting_started():
    """快速开始文档"""
    try:
        return send_from_directory(STATIC_DIR, 'docs-getting-started.html')
    except Exception as e:
        logger.error(f"❌ 文档加载失败: {str(e)}")
        return jsonify({'code': 'FILE_NOT_FOUND', 'message': '页面未找到', 'success': False}), 404

@app.route('/docs-features.html', methods=['GET'])
def docs_features():
    """功能指南文档"""
    try:
        return send_from_directory(STATIC_DIR, 'docs-features.html')
    except Exception as e:
        logger.error(f"❌ 文档加载失败: {str(e)}")
        return jsonify({'code': 'FILE_NOT_FOUND', 'message': '页面未找到', 'success': False}), 404

@app.route('/docs-ai.html', methods=['GET'])
def docs_ai():
    """AI功能文档"""
    try:
        return send_from_directory(STATIC_DIR, 'docs-ai.html')
    except Exception as e:
        logger.error(f"❌ 文档加载失败: {str(e)}")
        return jsonify({'code': 'FILE_NOT_FOUND', 'message': '页面未找到', 'success': False}), 404

@app.route('/docs-faq.html', methods=['GET'])
def docs_faq():
    """常见问题文档"""
    try:
        return send_from_directory(STATIC_DIR, 'docs-faq.html')
    except Exception as e:
        logger.error(f"❌ 文档加载失败: {str(e)}")
        return jsonify({'code': 'FILE_NOT_FOUND', 'message': '页面未找到', 'success': False}), 404

# -------------------------
# 博客页面路由
# -------------------------
@app.route('/blog.html', methods=['GET'])
def blog_index():
    """博客首页"""
    try:
        logger.info(f"🔍 访问博客首页: {STATIC_DIR}/blog.html")
        return send_from_directory(STATIC_DIR, 'blog.html')
    except Exception as e:
        logger.error(f"❌ 博客首页加载失败: {str(e)}")
        return jsonify({'code': 'FILE_NOT_FOUND', 'message': '页面未找到', 'success': False}), 404

@app.route('/blog-<path:article_name>.html', methods=['GET'])
def blog_article(article_name):
    """博客文章页面（通用路由）"""
    try:
        filename = f'blog-{article_name}.html'
        logger.info(f"🔍 访问博客文章: {STATIC_DIR}/{filename}")
        return send_from_directory(STATIC_DIR, filename)
    except Exception as e:
        logger.error(f"❌ 博客文章加载失败: {str(e)}")
        return jsonify({'code': 'FILE_NOT_FOUND', 'message': '页面未找到', 'success': False}), 404

@app.route('/api/verify-license-3', methods=['POST'])
@require_api_key
def verify_license():
    """验证许可证API端点"""
    try:
        # 获取请求数据
        data = request.get_json()
        if not data:
            return jsonify({
                'success': False,
                'message': '请求数据为空',
                'code': 'INVALID_REQUEST'
            }), 400
        
        # 提取参数
        license_code = data.get('license', '').strip()
        email = data.get('email', '').strip()
        app_version = data.get('appVersion', '1.0.0')
        platform = data.get('platform', 'macOS')
        device_name = data.get('device_name', f"{platform} {app_version}")  # 使用客户端发送的设备名称
        device_id = data.get('device_id', '').strip()  # 客户端发送的设备ID（基于硬件UUID）
        client_ip = data.get('ip_address') or request.remote_addr  # 优先使用客户端上传的IP,否则使用请求IP
        
        logger.info(f"🔍 收到验证请求: 邮箱={email}, 激活码={license_code[:8]}..., 版本={app_version}, 平台={platform}, IP={client_ip}, 设备ID={device_id}")
        
        # 验证必要参数
        if not license_code:
            return jsonify({
                'success': False,
                'message': '激活码不能为空',
                'code': 'MISSING_LICENSE'
            }), 400
        
        if not email:
            return jsonify({
                'success': False,
                'message': '邮箱不能为空',
                'code': 'MISSING_EMAIL'
            }), 400
        
        # 验证设备ID（必须由客户端提供）
        if not device_id:
            logger.error(f"❌ 客户端未发送设备ID，拒绝请求")
            return jsonify({
                'success': False,
                'message': '设备ID不能为空，请更新到最新版本',
                'code': 'MISSING_DEVICE_ID'
            }), 400
        
        # 验证许可证
        result = license_manager.verify_license_with_email(
            license_code, 
            email, 
            device_id=device_id,
            device_name=device_name,  # 使用客户端发送的真实设备名称
            ip_address=client_ip  # 使用客户端上传的IP地址
        )
        
        if result['valid']:
            logger.info(f"✅ 许可证验证成功: 许可证ID={result['license_id']}, 类型={result['plan']}, 设备ID={device_id}")
            return jsonify({
                'success': True,
                'message': '许可证验证成功',
                'code': 'SUCCESS',
                'license': {
                    'key': result['license_id'],
                    'type': result['plan'],
                    'expiresAt': result['valid_until']
                },
                'isValid': True,
                'licenseType': result['plan'],
                'expiresAt': result['valid_until'],
                'timestamp': datetime.now(timezone.utc).isoformat()
            })
        else:
            logger.warning(f"❌ 许可证验证失败: 激活码={license_code[:8]}..., 邮箱={email}, 错误={result.get('error', '未知错误')}")
            return jsonify({
                'success': False,
                'message': result.get('error', '许可证验证失败'),
                'code': 'INVALID_LICENSE',
                'isValid': False,
                'timestamp': datetime.now(timezone.utc).isoformat()
            }), 400
            
    except Exception as e:
        logger.error(f"❌ 验证过程中发生错误: {str(e)}")
        return jsonify({
            'success': False,
            'message': f'服务器内部错误: {str(e)}',
            'code': 'INTERNAL_ERROR',
            'timestamp': datetime.now().isoformat()
        }), 500

@app.route('/api/admin/login', methods=['POST'])
def admin_login():
    """管理员登录 - 用户名+密码验证版"""
    try:
        data = request.get_json(silent=True) or request.form
        username = (data.get('username') if data else '') or ''
        password = (data.get('password') if data else '') or ''
        client_ip = request.remote_addr
        
        # 检查登录尝试次数
        if not check_login_attempts(client_ip):
            logger.warning(f"管理员登录被阻止: {client_ip} - 失败次数过多")
            return jsonify({
                'success': False,
                'message': f'登录失败次数过多，请{LOGIN_LOCKOUT_TIME//60}分钟后再试',
                'code': 'TOO_MANY_ATTEMPTS'
            }), 429
        
        # 验证用户名和密码
        if not username:
            record_login_attempt(client_ip, False)
            return jsonify({
                'success': False,
                'message': '用户名不能为空',
                'code': 'MISSING_USERNAME'
            }), 400
        
        if not password:
            record_login_attempt(client_ip, False)
            return jsonify({
                'success': False,
                'message': '密码不能为空',
                'code': 'MISSING_PASSWORD'
            }), 400
        
        if username != ADMIN_USERNAME or password != ADMIN_PASSWORD:
            record_login_attempt(client_ip, False)
            logger.warning(f"管理员登录失败: {client_ip} - 用户名: {username}")
            return jsonify({
                'success': False,
                'message': '用户名或密码错误',
                'code': 'INVALID_CREDENTIALS'
            }), 401
        
        # 登录成功
        session['admin_logged_in'] = True
        session['login_time'] = time.time()
        session['login_at'] = datetime.now(timezone.utc).isoformat()
        session['admin_ip'] = client_ip
        session['admin_username'] = username
        
        record_login_attempt(client_ip, True)
        log_admin_operation('admin_login', {'username': username, 'ip': client_ip})
        
        logger.info(f"管理员登录成功: {username} @ {client_ip}")
        return jsonify({'success': True})
        
    except Exception as e:
        logger.error(f"❌ 管理登录失败: {str(e)}")
        return jsonify({'success': False, 'message': '服务器错误'}), 500

@app.route('/api/admin/logout', methods=['POST'])
def admin_logout():
    """管理员退出登录"""
    try:
        log_admin_operation('admin_logout', {'ip': request.remote_addr})
        session.clear()
        logger.info(f"管理员退出登录: {request.remote_addr}")
        return jsonify({'success': True})
    except Exception as e:
        logger.error(f"退出登录失败: {str(e)}")
        session.clear()  # 即使记录失败也要清除会话
        return jsonify({'success': True})

@app.route('/api/admin/licenses', methods=['GET'])
def admin_list_licenses():
    auth = require_admin()
    if auth is not None:
        return auth
    try:
        status = request.args.get('status', None)
        plan = request.args.get('plan', None)
        source = request.args.get('source', None)
        page = max(int(request.args.get('page', 1)), 1)
        page_size = min(max(int(request.args.get('page_size', 10)), 1), 100)
        query = (request.args.get('q') or '').strip()

        # 基于原有 list_licenses 进行分页/搜索
        all_rows = license_manager.list_licenses(status, 10000)
        
        # 应用筛选条件
        if plan:
            all_rows = [r for r in all_rows if r.get('plan') == plan]
        # 暂时跳过 source 筛选，因为当前数据库架构中没有 source 列
        # if source:
        #     all_rows = [r for r in all_rows if r.get('source') == source]
        if query:
            ql = query.lower()
            all_rows = [r for r in all_rows if (
                (r.get('email') or '').lower().find(ql) >= 0 or
                (r.get('license_id') or '').lower().find(ql) >= 0 or
                (r.get('activation_code') or '').lower().find(ql) >= 0
            )]

        total = len(all_rows)
        start = (page - 1) * page_size
        end = start + page_size
        data = all_rows[start:end]
        
        # 转换时区：将 UTC 时间转换为 CST (UTC+8) 用于前端显示
        for license_data in data:
            if license_data.get('valid_until'):
                # 如果是 datetime 对象，转换为中国时区字符串
                if isinstance(license_data['valid_until'], datetime):
                    cst_time = license_data['valid_until'] + timedelta(hours=8)
                    license_data['valid_until'] = cst_time.strftime('%a, %d %b %Y %H:%M:%S CST')
            if license_data.get('created_at'):
                # 同样转换创建时间
                if isinstance(license_data['created_at'], datetime):
                    cst_time = license_data['created_at'] + timedelta(hours=8)
                    license_data['created_at'] = cst_time.strftime('%Y-%m-%d %H:%M:%S')
            if license_data.get('issued_at'):
                # 转换签发时间
                if isinstance(license_data['issued_at'], datetime):
                    cst_time = license_data['issued_at'] + timedelta(hours=8)
                    license_data['issued_at'] = cst_time.strftime('%Y-%m-%d %H:%M:%S')

        return jsonify({'success': True, 'licenses': data, 'total': total, 'page': page, 'page_size': page_size})
    except Exception as e:
        logger.error(f"❌ 管理查询许可证失败: {str(e)}")
        return jsonify({'success': False, 'message': '查询失败'}), 500

@app.route('/api/admin/generate', methods=['POST'])
def admin_generate_license():
    auth = require_admin()
    if auth is not None:
        return auth
    try:
        data = request.get_json(force=True)
        plan = data.get('plan')
        email = data.get('email')
        device_cap = int(data.get('device_cap', 5))
        days = data.get('days')
        user_hint = data.get('user_hint')
        if days is not None:
            try:
                days = int(days)
            except Exception:
                days = None
        
        result = license_manager.generate_license_with_email(plan, email, device_cap, days, user_hint)
        if 'error' in result:
            log_admin_operation('generate_license_failed', {
                'plan': plan,
                'email': email,
                'device_cap': device_cap,
                'days': days,
                'error': result['error']
            })
            return jsonify({'success': False, 'message': result['error']}), 400
        
        # 记录成功操作
        log_admin_operation('generate_license', {
            'plan': plan,
            'email': email,
            'device_cap': device_cap,
            'days': days,
            'license_id': result.get('license_id'),
            'activation_code': result.get('activation_code')
        })
        
        return jsonify({'success': True, 'license': result})
    except Exception as e:
        logger.error(f"❌ 管理生成许可证失败: {str(e)}")
        return jsonify({'success': False, 'message': '生成失败'}), 500

@app.route('/api/admin/revoke', methods=['POST'])
def admin_revoke_license():
    auth = require_admin()
    if auth is not None:
        return auth
    try:
        data = request.get_json(force=True)
        license_id = data.get('license_id')
        reason = data.get('reason', 'no reason provided')
        if not license_id:
            return jsonify({'success': False, 'message': '缺少 license_id'}), 400
        
        ok = license_manager.revoke_license(license_id, reason, revoked_by='admin')
        if not ok:
            log_admin_operation('revoke_license_failed', {
                'license_id': license_id,
                'reason': reason
            })
            return jsonify({'success': False, 'message': '撤销失败或许可证不存在'}), 400
        
        # 记录成功操作
        log_admin_operation('revoke_license', {
            'license_id': license_id,
            'reason': reason
        })
        
        return jsonify({'success': True})
    except Exception as e:
        logger.error(f"❌ 管理撤销许可证失败: {str(e)}")
        return jsonify({'success': False, 'message': '撤销失败'}), 500

@app.route('/api/admin/update-device-cap', methods=['POST'])
def admin_update_device_cap():
    auth = require_admin()
    if auth is not None:
        return auth
    try:
        data = request.get_json(force=True)
        license_id = data.get('license_id')
        device_cap = int(data.get('device_cap', 5))
        if not license_id:
            return jsonify({'success': False, 'message': '缺少 license_id'}), 400
        conn = license_manager.get_connection()
        if not conn:
            return jsonify({'success': False, 'message': '数据库连接失败'}), 500
        cur = conn.cursor()
        cur.execute('UPDATE licenses SET device_limit = %s WHERE license_id = %s', (device_cap, license_id))
        conn.commit()
        cur.close()
        return jsonify({'success': True})
    except Exception as e:
        logger.error(f"❌ 更新设备上限失败: {str(e)}")
        return jsonify({'success': False, 'message': '更新失败'}), 500

@app.route('/api/admin/extend-validity', methods=['POST'])
def admin_extend_validity():
    auth = require_admin()
    if auth is not None:
        return auth
    try:
        data = request.get_json(force=True)
        license_id = data.get('license_id')
        days = int(data.get('days', 30))
        if not license_id:
            return jsonify({'success': False, 'message': '缺少 license_id'}), 400
        conn = license_manager.get_connection()
        if not conn:
            return jsonify({'success': False, 'message': '数据库连接失败'}), 500
        cur = conn.cursor()
        # 如果当前为 NULL，则从现在起算；否则在原基础上增加
        cur.execute('''
            UPDATE licenses 
            SET valid_until = IFNULL(DATE_ADD(UTC_TIMESTAMP(), INTERVAL %s DAY), DATE_ADD(valid_until, INTERVAL %s DAY))
            WHERE license_id = %s
        ''', (days, days, license_id))
        conn.commit()
        cur.close()
        return jsonify({'success': True})
    except Exception as e:
        logger.error(f"❌ 延长有效期失败: {str(e)}")
        return jsonify({'success': False, 'message': '更新失败'}), 500

@app.route('/api/admin/batch-generate', methods=['POST'])
def admin_batch_generate():
    auth = require_admin()
    if auth is not None:
        return auth
    try:
        data = request.get_json(force=True)
        plan = data.get('plan')
        emails = data.get('emails', [])
        device_cap = int(data.get('device_cap', 5))
        days = data.get('days')
        user_hint = data.get('user_hint')
        
        if days is not None:
            try:
                days = int(days)
            except Exception:
                days = None
        
        if not emails or not isinstance(emails, list):
            return jsonify({'success': False, 'message': '邮箱列表不能为空'}), 400
            
        results = license_manager.batch_generate(plan, len(emails), emails, device_cap, days, user_hint)
        success_count = len([r for r in results if 'error' not in r])
        
        return jsonify({
            'success': True, 
            'results': results,
            'success_count': success_count,
            'total_count': len(emails)
        })
    except Exception as e:
        logger.error(f"❌ 批量生成许可证失败: {str(e)}")
        return jsonify({'success': False, 'message': '批量生成失败'}), 500

@app.route('/api/admin/batch-revoke', methods=['POST'])
def admin_batch_revoke():
    auth = require_admin()
    if auth is not None:
        return auth
    try:
        data = request.get_json(force=True)
        license_ids = data.get('license_ids', [])
        reason = data.get('reason', 'batch revoke')
        
        if not license_ids or not isinstance(license_ids, list):
            return jsonify({'success': False, 'message': '许可证ID列表不能为空'}), 400
            
        success_count = 0
        for license_id in license_ids:
            if license_manager.revoke_license(license_id, reason, revoked_by='admin'):
                success_count += 1
                
        return jsonify({
            'success': True,
            'success_count': success_count,
            'total_count': len(license_ids)
        })
    except Exception as e:
        logger.error(f"❌ 批量撤销许可证失败: {str(e)}")
        return jsonify({'success': False, 'message': '批量撤销失败'}), 500

@app.route('/api/admin/restore', methods=['POST'])
def admin_restore_license():
    auth = require_admin()
    if auth is not None:
        return auth
    try:
        data = request.get_json(force=True)
        license_id = data.get('license_id')
        if not license_id:
            return jsonify({'success': False, 'message': '缺少 license_id'}), 400
            
        conn = license_manager.get_connection()
        if not conn:
            return jsonify({'success': False, 'message': '数据库连接失败'}), 500
        cur = conn.cursor()
        # 恢复许可证状态
        cur.execute('UPDATE licenses SET status = "active" WHERE license_id = %s', (license_id,))
        # 从撤销列表中移除
        cur.execute('DELETE FROM revoked_licenses WHERE license_id = %s', (license_id,))
        conn.commit()
        cur.close()
        
        return jsonify({'success': True})
    except Exception as e:
        logger.error(f"❌ 恢复许可证失败: {str(e)}")
        return jsonify({'success': False, 'message': '恢复失败'}), 500

@app.route('/api/admin/delete', methods=['POST'])
def admin_delete_license():
    auth = require_admin()
    if auth is not None:
        return auth
    try:
        data = request.get_json(force=True)
        license_id = data.get('license_id')
        if not license_id:
            return jsonify({'success': False, 'message': '缺少 license_id'}), 400
        
        # 删除许可证（物理删除）
        conn = license_manager.get_connection()
        if not conn:
            return jsonify({'success': False, 'message': '数据库连接失败'}), 500
        cur = conn.cursor()
        
        # 先删除相关的设备激活记录
        cur.execute('DELETE FROM device_activations WHERE license_id = %s', (license_id,))
        
        # 删除激活历史记录
        cur.execute('DELETE FROM activation_history WHERE license_id = %s', (license_id,))
        
        # 删除撤销记录
        cur.execute('DELETE FROM revoked_licenses WHERE license_id = %s', (license_id,))
        
        # 最后删除许可证本身
        cur.execute('DELETE FROM licenses WHERE license_id = %s', (license_id,))
        
        conn.commit()
        cur.close()
        
        return jsonify({'success': True})
    except Exception as e:
        logger.error(f"❌ 删除许可证失败: {str(e)}")
        return jsonify({'success': False, 'message': '删除失败'}), 500

@app.route('/api/admin/deactivate-device', methods=['POST'])
def admin_deactivate_device():
    """停用设备"""
    auth = require_admin()
    if auth is not None:
        return auth
    try:
        data = request.get_json(force=True)
        license_id = data.get('license_id')
        device_id = data.get('device_id')
        reason = data.get('reason', '管理员停用')
        
        if not license_id or not device_id:
            return jsonify({'success': False, 'message': '缺少 license_id 或 device_id'}), 400
        
        conn = license_manager.get_connection()
        if not conn:
            return jsonify({'success': False, 'message': '数据库连接失败'}), 500
        cur = conn.cursor()
        
        # 停用设备
        cur.execute('''
            UPDATE device_activations 
            SET is_active = 0 
            WHERE license_id = %s AND device_id = %s
        ''', (license_id, device_id))
        
        if cur.rowcount == 0:
            return jsonify({'success': False, 'message': '设备不存在'}), 404
        
        # 记录停用历史
        cur.execute('''
            INSERT INTO activation_history (license_id, action, device_id, details)
            VALUES (%s, 'deactivate', %s, %s)
        ''', (license_id, device_id, json.dumps({"reason": reason, "deactivated_by": "admin"})))
        
        conn.commit()
        cur.close()
        
        return jsonify({'success': True})
    except Exception as e:
        logger.error(f"❌ 停用设备失败: {str(e)}")
        return jsonify({'success': False, 'message': '停用失败'}), 500

@app.route('/api/admin/activate-device', methods=['POST'])
def admin_activate_device():
    """恢复设备"""
    auth = require_admin()
    if auth is not None:
        return auth
    try:
        data = request.get_json(force=True)
        license_id = data.get('license_id')
        device_id = data.get('device_id')
        reason = data.get('reason', '管理员恢复')
        
        if not license_id or not device_id:
            return jsonify({'success': False, 'message': '缺少 license_id 或 device_id'}), 400
        
        conn = license_manager.get_connection()
        if not conn:
            return jsonify({'success': False, 'message': '数据库连接失败'}), 500
        cur = conn.cursor()
        
        # 检查设备是否存在
        cur.execute('''
            SELECT 1 FROM device_activations 
            WHERE license_id = %s AND device_id = %s
        ''', (license_id, device_id))
        
        if not cur.fetchone():
            return jsonify({'success': False, 'message': '设备不存在'}), 404
        
        # 恢复设备
        cur.execute('''
            UPDATE device_activations 
            SET is_active = 1 
            WHERE license_id = %s AND device_id = %s
        ''', (license_id, device_id))
        
        # 记录恢复历史
        cur.execute('''
            INSERT INTO activation_history (license_id, action, device_id, details)
            VALUES (%s, 'renew', %s, %s)
        ''', (license_id, device_id, json.dumps({"reason": reason, "activated_by": "admin"})))
        
        conn.commit()
        cur.close()
        
        return jsonify({'success': True})
    except Exception as e:
        logger.error(f"❌ 恢复设备失败: {str(e)}")
        return jsonify({'success': False, 'message': '恢复失败'}), 500

@app.route('/api/admin/delete-device', methods=['POST'])
def admin_delete_device():
    """管理员删除设备"""
    auth = require_admin()
    if auth is not None:
        return auth
    try:
        data = request.get_json(force=True)
        license_id = data.get('license_id')
        device_id = data.get('device_id')
        reason = data.get('reason', '管理员删除')
        
        if not license_id or not device_id:
            return jsonify({'success': False, 'message': '缺少 license_id 或 device_id'}), 400
        
        logger.info(f"🔍 管理员删除设备: license_id={license_id}, device_id={device_id}")
        
        conn = license_manager.get_connection()
        if not conn:
            return jsonify({'success': False, 'message': '数据库连接失败'}), 500
        cur = conn.cursor()
        
        # 检查设备是否存在
        cur.execute('''
            SELECT 1 FROM device_activations 
            WHERE license_id = %s AND device_id = %s
        ''', (license_id, device_id))
        
        if not cur.fetchone():
            logger.warning(f"❌ 设备不存在: license_id={license_id}, device_id={device_id}")
            return jsonify({'success': False, 'message': '设备不存在'}), 404
        
        # 删除设备激活记录
        cur.execute('''
            DELETE FROM device_activations 
            WHERE license_id = %s AND device_id = %s
        ''', (license_id, device_id))
        
        if cur.rowcount == 0:
            logger.warning(f"❌ 设备删除失败，没有行被删除: license_id={license_id}, device_id={device_id}")
            return jsonify({'success': False, 'message': '设备删除失败'}), 500
        
        # 记录删除历史
        cur.execute('''
            INSERT INTO activation_history (license_id, action, device_id, details)
            VALUES (%s, 'delete', %s, %s)
        ''', (license_id, device_id, json.dumps({"reason": reason, "deleted_by": "admin"})))
        
        conn.commit()
        cur.close()
        
        logger.info(f"✅ 管理员删除设备成功: {device_id}")
        return jsonify({'success': True, 'message': '设备已删除'})
        
    except Exception as e:
        logger.error(f"❌ 管理员删除设备失败: {str(e)}")
        return jsonify({'success': False, 'message': '删除失败'}), 500

@app.route('/api/cancel-activation', methods=['POST'])
def cancel_device_activation():
    """用户取消设备激活"""
    try:
        data = request.get_json(force=True)
        activation_code = data.get('activation_code')
        email = data.get('email')
        device_id = data.get('device_id')
        reason = data.get('reason', '用户取消激活')
        
        if not activation_code or not email or not device_id:
            return jsonify({'success': False, 'message': '缺少必要参数'}), 400
        
        # 验证许可证
        result = license_manager.verify_license_with_email(activation_code, email)
        if not result['valid']:
            return jsonify({'success': False, 'message': result['error']}), 400
        
        license_id = result['license_id']
        
        # 取消设备激活
        if license_manager.cancel_device_activation(license_id, device_id, reason):
            return jsonify({'success': True, 'message': '设备激活已取消'})
        else:
            return jsonify({'success': False, 'message': '取消激活失败'}), 400
            
    except Exception as e:
        logger.error(f"❌ 取消设备激活失败: {str(e)}")
        return jsonify({'success': False, 'message': '操作失败'}), 500

@app.route('/api/device-status', methods=['POST'])
def get_device_status():
    """获取设备激活状态"""
    try:
        data = request.get_json(force=True)
        activation_code = data.get('activation_code')
        email = data.get('email')
        device_id = data.get('device_id')
        
        if not activation_code or not email or not device_id:
            return jsonify({'success': False, 'message': '缺少必要参数'}), 400
        
        # 验证许可证
        result = license_manager.verify_license_with_email(activation_code, email)
        if not result['valid']:
            return jsonify({'success': False, 'message': result['error']}), 400
        
        license_id = result['license_id']
        
        # 获取设备状态
        status = license_manager.get_device_activation_status(license_id, device_id)
        
        if 'error' in status:
            return jsonify({'success': False, 'message': status['error']}), 500
        
        return jsonify({
            'success': True, 
            'device_status': status
        })
            
    except Exception as e:
        logger.error(f"❌ 获取设备状态失败: {str(e)}")
        return jsonify({'success': False, 'message': '获取状态失败'}), 500

@app.route('/api/admin/license-details/<license_id>', methods=['GET'])
def admin_license_details(license_id):
    auth = require_admin()
    if auth is not None:
        return auth
    try:
        conn = license_manager.get_connection()
        if not conn:
            return jsonify({'success': False, 'message': '数据库连接失败'}), 500
        cur = conn.cursor(dictionary=True)
        
        # 获取许可证详情
        cur.execute('''
            SELECT l.*, COUNT(da.device_id) as active_devices
            FROM licenses l
            LEFT JOIN device_activations da ON l.license_id = da.license_id AND da.is_active = 1
            WHERE l.license_id = %s
            GROUP BY l.license_id
        ''', (license_id,))
        license_info = cur.fetchone()
        
        if not license_info:
            return jsonify({'success': False, 'message': '许可证不存在'}), 404
            
        # 获取设备激活记录
        cur.execute('''
            SELECT device_id, device_name, ip_address, last_seen_at, is_active
            FROM device_activations 
            WHERE license_id = %s 
            ORDER BY last_seen_at DESC
        ''', (license_id,))
        devices = cur.fetchall()
        
        # 获取激活历史
        cur.execute('''
            SELECT action, device_id, ip_address, details, created_at
            FROM activation_history 
            WHERE license_id = %s 
            ORDER BY created_at DESC 
            LIMIT 50
        ''', (license_id,))
        history = cur.fetchall()
        
        cur.close()
        
        # 转换时区：将 UTC 时间转换为 CST (UTC+8)
        if license_info.get('valid_until') and isinstance(license_info['valid_until'], datetime):
            cst_time = license_info['valid_until'] + timedelta(hours=8)
            license_info['valid_until'] = cst_time.strftime('%Y-%m-%d %H:%M:%S CST')
        if license_info.get('created_at') and isinstance(license_info['created_at'], datetime):
            cst_time = license_info['created_at'] + timedelta(hours=8)
            license_info['created_at'] = cst_time.strftime('%Y-%m-%d %H:%M:%S')
        if license_info.get('issued_at') and isinstance(license_info['issued_at'], datetime):
            cst_time = license_info['issued_at'] + timedelta(hours=8)
            license_info['issued_at'] = cst_time.strftime('%Y-%m-%d %H:%M:%S')
        
        # 转换设备列表的时间
        for device in devices:
            if device.get('last_seen_at') and isinstance(device['last_seen_at'], datetime):
                cst_time = device['last_seen_at'] + timedelta(hours=8)
                device['last_seen_at'] = cst_time.strftime('%Y-%m-%d %H:%M:%S')
        
        # 转换历史记录的时间
        for record in history:
            if record.get('created_at') and isinstance(record['created_at'], datetime):
                cst_time = record['created_at'] + timedelta(hours=8)
                record['created_at'] = cst_time.strftime('%Y-%m-%d %H:%M:%S')
        
        return jsonify({
            'success': True,
            'license': license_info,
            'devices': devices,
            'history': history
        })
    except Exception as e:
        logger.error(f"❌ 获取许可证详情失败: {str(e)}")
        return jsonify({'success': False, 'message': '获取详情失败'}), 500

# ==================== 优惠码管理 ====================

@app.route('/api/admin/coupons', methods=['GET'])
def admin_get_coupons():
    """获取优惠码列表"""
    auth = require_admin()
    if auth is not None:
        return auth
    try:
        conn = license_manager.get_connection()
        if not conn:
            return jsonify({'success': False, 'message': '数据库连接失败'}), 500
        cur = conn.cursor(dictionary=True)
        cur.execute('''
            SELECT id, code, type, value, min_amount, plans, usage_limit, user_limit, 
                   start_date, end_date, is_active, usage_count, created_at
            FROM coupons 
            ORDER BY created_at DESC
        ''')
        rows = cur.fetchall()
        cur.close()
        
        coupons = []
        for row in rows:
            coupons.append({
                'id': row['id'],
                'code': row['code'],
                'type': row['type'],
                'value': float(row['value']) if row['value'] is not None else 0.0,
                'min_amount': float(row['min_amount']) if row['min_amount'] is not None else 0.0,
                'plans': json.loads(row['plans']) if row['plans'] else [],
                'usage_limit': row['usage_limit'],
                'user_limit': row['user_limit'],
                'start_date': row['start_date'].isoformat() if row['start_date'] else None,
                'end_date': row['end_date'].isoformat() if row['end_date'] else None,
                'is_active': bool(row['is_active']),
                'usage_count': row['usage_count'],
                'created_at': row['created_at'].isoformat() if row['created_at'] else None
            })
        
        return jsonify({'success': True, 'coupons': coupons})
    except Exception as e:
        logger.error(f"❌ 获取优惠码列表失败: {str(e)}")
        return jsonify({'success': False, 'message': '获取优惠码列表失败'}), 500

@app.route('/api/admin/coupons', methods=['POST'])
def admin_create_coupon():
    """创建优惠码"""
    auth = require_admin()
    if auth is not None:
        return auth
    try:
        data = request.get_json(force=True)
        code = data.get('code', '').strip()
        coupon_type = data.get('type', 'fixed')
        value = data.get('value', 0)
        min_amount = data.get('min_amount', 0)
        plans = data.get('plans', [])
        usage_limit = data.get('usage_limit', 999999)
        user_limit = data.get('user_limit', 1)
        start_date = data.get('start_date')
        end_date = data.get('end_date')
        
        if not code or not value or not plans:
            return jsonify({'success': False, 'message': '缺少必要参数'}), 400
        
        conn = license_manager.get_connection()
        if not conn:
            return jsonify({'success': False, 'message': '数据库连接失败'}), 500
        cur = conn.cursor()
        
        # 检查优惠码是否已存在
        cur.execute('SELECT id FROM coupons WHERE code = %s', (code,))
        if cur.fetchone():
            return jsonify({'success': False, 'message': '优惠码已存在'}), 400
        
        # 插入新优惠码
        cur.execute('''
            INSERT INTO coupons (code, type, value, min_amount, plans, usage_limit, user_limit, start_date, end_date)
            VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s)
        ''', (code, coupon_type, value, min_amount, json.dumps(plans), usage_limit, user_limit, start_date, end_date))
        
        conn.commit()
        cur.close()
        
        logger.info(f"✅ 创建优惠码成功: {code}")
        return jsonify({'success': True, 'message': '优惠码创建成功'})
    except Exception as e:
        logger.error(f"❌ 创建优惠码失败: {str(e)}")
        return jsonify({'success': False, 'message': '创建优惠码失败'}), 500

@app.route('/api/admin/coupons/<int:coupon_id>', methods=['DELETE'])
def admin_delete_coupon(coupon_id):
    """删除优惠码"""
    auth = require_admin()
    if auth is not None:
        return auth
    try:
        conn = license_manager.get_connection()
        if not conn:
            return jsonify({'success': False, 'message': '数据库连接失败'}), 500
        cur = conn.cursor()
        cur.execute('DELETE FROM coupons WHERE id = %s', (coupon_id,))
        if cur.rowcount == 0:
            return jsonify({'success': False, 'message': '优惠码不存在'}), 404
        
        conn.commit()
        cur.close()
        
        logger.info(f"✅ 删除优惠码成功: ID={coupon_id}")
        return jsonify({'success': True, 'message': '优惠码删除成功'})
    except Exception as e:
        logger.error(f"❌ 删除优惠码失败: {str(e)}")
        return jsonify({'success': False, 'message': '删除优惠码失败'}), 500

@app.route('/api/admin/coupons/<int:coupon_id>/toggle', methods=['POST'])
def admin_toggle_coupon(coupon_id):
    """启用/停用优惠码"""
    auth = require_admin()
    if auth is not None:
        return auth
    try:
        data = request.get_json(force=True)
        is_active = data.get('is_active', True)
        
        conn = license_manager.get_connection()
        if not conn:
            return jsonify({'success': False, 'message': '数据库连接失败'}), 500
        cur = conn.cursor()
        cur.execute('UPDATE coupons SET is_active = %s WHERE id = %s', (is_active, coupon_id))
        if cur.rowcount == 0:
            return jsonify({'success': False, 'message': '优惠码不存在'}), 404
        
        conn.commit()
        cur.close()
        
        status = '启用' if is_active else '停用'
        logger.info(f"✅ {status}优惠码成功: ID={coupon_id}")
        return jsonify({'success': True, 'message': f'优惠码{status}成功'})
    except Exception as e:
        logger.error(f"❌ 切换优惠码状态失败: {str(e)}")
        return jsonify({'success': False, 'message': '操作失败'}), 500

# ==================== 支付系统集成 ====================

# ZPAY支付配置
ZPAY_CONFIG = {
    'pid': os.getenv('ZPAY_PID', '2025090522454134'),
    'key': os.getenv('ZPAY_KEY', '3skhuHdNrNeubD5yDBzhKYL3awo2SC5t'),
    'api_url': 'https://zpayz.cn/',
    'notify_url': os.getenv('ZPAY_NOTIFY_URL', 'https://oneclip.cloud/api/payment/notify'),
    'return_url': os.getenv('ZPAY_RETURN_URL', 'https://oneclip.cloud/api/payment/return')
}

# 导入ZPAY适配器
try:
    from zpay_adapter import ZPayAdapterFixed as ZPayAdapter
    # 初始化ZPAY适配器
    zpay_adapter = ZPayAdapter(ZPAY_CONFIG)
except ImportError:
    # 如果ZPAY适配器不存在，创建一个简单的模拟类
    class ZPayAdapter:
        def __init__(self, config):
            self.config = config
        
        def create_order(self, order_data):
            return {
                'success': True,
                'pay_url': f"https://zpayz.cn/pay?order_id={order_data['order_id']}",
                'qr_code': f"https://zpayz.cn/qr?order_id={order_data['order_id']}",
                'img': f"https://zpayz.cn/qr?order_id={order_data['order_id']}"
            }
        
        def handle_notify(self, notify_data):
            return {
                'success': True,
                'order_id': notify_data.get('out_trade_no', ''),
                'trade_no': notify_data.get('trade_no', '')
            }
    
    zpay_adapter = ZPayAdapter(ZPAY_CONFIG)

# 邮件服务配置（按优先级排序，失败自动切换）
EMAIL_CONFIGS = [
    {
        'name': 'OneClip 企业邮箱',
        'smtp_server': 'smtp.exmail.qq.com',
        'smtp_port': 465,
        'smtp_user': 'vip@oneclip.cloud',
        'smtp_password': 'DFEB7DWQaPdTEwcv',
        'from_email': 'vip@oneclip.cloud',
        'use_ssl': True
    },
    {
        'name': '腾讯企业邮箱备用',
        'smtp_server': 'smtp.exmail.qq.com',
        'smtp_port': 587,
        'smtp_user': 'wangkewen@ctbu.edu.cn',
        'smtp_password': 'ExbKNQWEF5H3JuQc',
        'from_email': 'wangkewen@ctbu.edu.cn',
        'use_ssl': False
    }
]

import hashlib
import urllib.parse
import smtplib
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart

def generate_yipay_sign(params, key):
    """生成易支付签名"""
    # 过滤空值和签名参数
    filtered_params = {k: v for k, v in params.items() if v and k != 'sign'}
    # 按键名排序
    sorted_params = sorted(filtered_params.items())
    # 拼接字符串
    sign_string = '&'.join([f"{k}={v}" for k, v in sorted_params])
    # 加上密钥
    sign_string += key
    # MD5加密
    return hashlib.md5(sign_string.encode('utf-8')).hexdigest()

def verify_yipay_sign(params, key):
    """验证易支付签名"""
    received_sign = params.get('sign', '')
    calculated_sign = generate_yipay_sign(params, key)
    return received_sign == calculated_sign

def generate_zpay_sign(params, key):
    """生成ZPAY签名 - 按照ZPAY官方文档的签名算法"""
    # 移除空值、sign和sign_type参数
    filtered_params = {k: v for k, v in params.items() if v and k not in ['sign', 'sign_type']}
    
    # 按照参数名ASCII码从小到大排序（a-z）
    sorted_params = sorted(filtered_params.items())
    
    # 拼接成URL键值对格式，参数值不进行url编码
    sign_parts = []
    for k, v in sorted_params:
        sign_parts.append(f'{k}={v}')
    
    sign_str = '&'.join(sign_parts)
    sign_str += key  # 直接拼接KEY，不加&符号
    
    # MD5加密，结果为小写
    sign = hashlib.md5(sign_str.encode('utf-8')).hexdigest().lower()
    logger.info(f"🔍 ZPAY签名字符串: {sign_str}")
    logger.info(f"🔍 ZPAY生成签名: {sign}")
    return sign

def send_activation_email(email, license_info, user_choice='send'):
    """发送激活码邮件（支持多邮件服务商自动切换）"""
    if user_choice != 'send':
        logger.info(f"用户选择不发送邮件: {email}")
        return True
    
    # 尝试多个邮件服务商
    for config in EMAIL_CONFIGS:
        try:
            logger.info(f"尝试使用 {config['name']} 发送邮件到 {email}")
            
            # 邮件内容 - 优化主题避免被过滤
            subject = f"OneClip License Activation Code - {license_info['plan'].title()}"
            
            # 获取许可证类型的中文名称
            plan_names = {
                'monthly': '月度版',
                'yearly': '年度版', 
                'lifetime': '终身版'
            }
            plan_display = plan_names.get(license_info['plan'], license_info['plan'])
            
            html_content = f"""
            <html>
            <head>
                <meta charset="utf-8">
                <meta name="viewport" content="width=device-width, initial-scale=1.0">
                <style>
                    body {{ 
                        font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif; 
                        line-height: 1.6; 
                        color: #1e293b; 
                        background: #f1f5f9;
                        margin: 0;
                        padding: 20px;
                    }}
                    .container {{ 
                        max-width: 680px; 
                        margin: 0 auto; 
                        background: white;
                        border-radius: 20px;
                        overflow: hidden;
                        box-shadow: 0 10px 40px rgba(0, 0, 0, 0.1);
                    }}
                    .header {{ 
                        background: linear-gradient(135deg, #3b82f6 0%, #1d4ed8 100%); 
                        color: white; 
                        padding: 40px 30px; 
                        text-align: center; 
                    }}
                    .header h1 {{
                        font-size: 28px;
                        margin: 0 0 10px 0;
                        font-weight: 700;
                    }}
                    .header p {{
                        font-size: 16px;
                        opacity: 0.9;
                        margin: 0;
                    }}
                    .content {{ 
                        padding: 40px 30px; 
                    }}
                    .activation-section {{
                        background: linear-gradient(135deg, #f0f9ff 0%, #e0f2fe 100%);
                        border: 2px solid #3b82f6;
                        border-radius: 16px;
                        padding: 30px;
                        margin: 0 0 30px 0;
                        text-align: center;
                    }}
                    .activation-section h2 {{
                        color: #1e40af;
                        font-size: 18px;
                        margin: 0 0 15px 0;
                    }}
                    .activation-code {{ 
                        font-family: 'SF Mono', 'Monaco', 'Courier New', monospace; 
                        font-size: 24px; 
                        font-weight: 700; 
                        color: #1d4ed8; 
                        background: white;
                        padding: 15px 25px; 
                        border-radius: 10px;
                        letter-spacing: 2px;
                        display: inline-block;
                        border: 2px dashed #93c5fd;
                        margin: 10px 0;
                    }}
                    .activation-tip {{
                        color: #64748b;
                        font-size: 14px;
                        margin-top: 15px;
                    }}
                    .info-card {{
                        background: #f8fafc;
                        border-radius: 12px;
                        padding: 25px;
                        margin-bottom: 25px;
                    }}
                    .info-card h3 {{
                        color: #1e293b;
                        font-size: 18px;
                        margin: 0 0 20px 0;
                        padding-bottom: 10px;
                        border-bottom: 2px solid #e2e8f0;
                    }}
                    .info-row {{ 
                        display: table;
                        width: 100%;
                        padding: 12px 0; 
                        border-bottom: 1px solid #e2e8f0; 
                    }}
                    .info-row:last-child {{
                        border-bottom: none;
                    }}
                    .info-label {{ 
                        display: table-cell;
                        font-weight: 600; 
                        color: #64748b;
                        width: 40%;
                    }}
                    .info-value {{ 
                        display: table-cell;
                        color: #1e293b;
                        text-align: right;
                        font-weight: 500;
                    }}
                    .steps-section {{
                        background: #f0fdf4;
                        border-left: 4px solid #22c55e;
                        border-radius: 0 12px 12px 0;
                        padding: 25px;
                        margin-bottom: 25px;
                    }}
                    .steps-section h3 {{
                        color: #166534;
                        font-size: 18px;
                        margin: 0 0 15px 0;
                    }}
                    .steps-section ol {{
                        margin: 0;
                        padding-left: 20px;
                        color: #15803d;
                    }}
                    .steps-section li {{
                        margin: 10px 0;
                        padding-left: 5px;
                    }}
                    .tips-section {{
                        background: #fefce8;
                        border-left: 4px solid #eab308;
                        border-radius: 0 12px 12px 0;
                        padding: 25px;
                        margin-bottom: 25px;
                    }}
                    .tips-section h3 {{
                        color: #a16207;
                        font-size: 18px;
                        margin: 0 0 15px 0;
                    }}
                    .tips-section ul {{
                        margin: 0;
                        padding-left: 20px;
                        color: #854d0e;
                    }}
                    .tips-section li {{
                        margin: 8px 0;
                    }}
                    .support-section {{
                        background: #eff6ff;
                        border-radius: 12px;
                        padding: 25px;
                        text-align: center;
                        margin-bottom: 20px;
                    }}
                    .support-section h3 {{
                        color: #1e40af;
                        font-size: 16px;
                        margin: 0 0 10px 0;
                    }}
                    .support-section p {{
                        color: #3b82f6;
                        margin: 0;
                    }}
                    .support-section a {{
                        color: #1d4ed8;
                        text-decoration: none;
                        font-weight: 600;
                    }}
                    .footer {{ 
                        text-align: center; 
                        padding: 25px;
                        background: #f8fafc;
                        border-top: 1px solid #e2e8f0;
                    }}
                    .footer p {{
                        color: #94a3b8; 
                        font-size: 12px;
                        margin: 5px 0;
                    }}
                </style>
            </head>
            <body>
                <div class="container">
                    <div class="header">
                        <h1>🎉 OneClip 订单完成</h1>
                        <p>感谢您的购买，您的许可证已准备就绪</p>
                    </div>
                    
                    <div class="content">
                        <!-- 激活码区域 -->
                        <div class="activation-section">
                            <h2>🔑 您的激活码</h2>
                            <div class="activation-code">{license_info['activation_code']}</div>
                            <p class="activation-tip">请复制此激活码到 OneClip 应用中激活</p>
                        </div>
                        
                        <!-- 购买信息（精简版） -->
                        <div class="info-card">
                            <h3>📋 订单信息</h3>
                            <div class="info-row">
                                <span class="info-label">邮箱</span>
                                <span class="info-value">{email}</span>
                            </div>
                            <div class="info-row">
                                <span class="info-label">类型</span>
                                <span class="info-value">{plan_display} · {license_info['device_cap']}台设备 · {license_info['valid_until'] or '永久有效'}</span>
                            </div>
                            <div class="info-row">
                                <span class="info-label">订单号</span>
                                <span class="info-value">{license_info.get('order_id', 'N/A')}</span>
                            </div>
                        </div>
                        
                        <!-- 激活步骤 -->
                        <div class="steps-section">
                            <h3>💻 激活步骤</h3>
                            <ol>
                                <li>下载并安装 OneClip 应用</li>
                                <li>打开设置 → 高级功能</li>
                                <li>输入邮箱和激活码，点击激活</li>
                            </ol>
                            <p style="margin-top: 15px; color: #166534; font-size: 13px;">💡 请妥善保管此邮件，建议标记为重要或收藏</p>
                        </div>
                        
                        <!-- 客服支持 -->
                        <div class="support-section">
                            <h3>📞 需要帮助？</h3>
                            <p>技术支持：<a href="mailto:vip@oneclip.cloud">vip@oneclip.cloud</a></p>
                        </div>
                    </div>
                    
                    <div class="footer">
                        <p>此邮件由系统自动发送，请勿直接回复</p>
                        <p>© 2025 OneClip · <a href="https://oneclip.cloud" style="color: #3b82f6;">oneclip.cloud</a></p>
                    </div>
                </div>
            </body>
            </html>
            """
            
            # 创建邮件
            msg = MIMEMultipart('alternative')
            # 简化From头格式，避免Gmail解析问题
            msg['From'] = config['from_email']
            msg['To'] = email
            msg['Subject'] = subject
            
            # 添加HTML内容
            msg.attach(MIMEText(html_content, 'html', 'utf-8'))
            
            # 发送邮件
            if config['use_ssl']:
                # 使用SSL连接（163邮箱）
                with smtplib.SMTP_SSL(config['smtp_server'], config['smtp_port']) as server:
                    server.login(config['smtp_user'], config['smtp_password'])
                    server.send_message(msg)
            else:
                # 使用TLS连接（QQ邮箱）
                with smtplib.SMTP(config['smtp_server'], config['smtp_port']) as server:
                    server.starttls()
                    server.login(config['smtp_user'], config['smtp_password'])
                    server.send_message(msg)
            
            logger.info(f"✅ 激活码邮件发送成功: {email} (使用 {config['name']})")
            return True
            
        except Exception as e:
            logger.error(f"❌ 使用 {config['name']} 发送激活码邮件失败: {str(e)}")
            continue
    
    logger.error(f"❌ 所有邮件服务商都发送失败: {email}")
    return False

@app.route('/api/payment/send-email', methods=['POST'])
def send_email_by_choice():
    """根据用户选择发送邮件"""
    try:
        data = request.get_json(force=True)
        order_id = data.get('order_id')
        email = data.get('email')
        user_choice = data.get('choice', 'send')  # 'send' 或 'dont_send'
        
        if not order_id or not email:
            return jsonify({'success': False, 'message': '缺少必要参数'}), 400
        
        # 查询订单信息
        conn = license_manager.get_connection()
        if not conn:
            return jsonify({'success': False, 'message': '数据库连接失败'}), 500
        
        cur = conn.cursor()
        cur.execute('''
            SELECT po.order_id, po.email, po.plan, po.device_cap, po.activation_code, po.license_id,
                   l.valid_until, po.email_sent
            FROM payment_orders po
            LEFT JOIN licenses l ON po.license_id = l.license_id
            WHERE po.order_id = %s AND po.email = %s
        ''', (order_id, email))
        
        order_data = cur.fetchone()
        cur.close()
        
        if not order_data:
            return jsonify({'success': False, 'message': '订单不存在'}), 404
        
        order_id, email, plan, device_cap, activation_code, license_id, valid_until, email_sent = order_data
        
        if not activation_code:
            return jsonify({'success': False, 'message': '订单未生成激活码'}), 400
        
        # 检查是否已经发送过邮件（防止重复发送），除非用户明确要求重新发送
        if email_sent and user_choice == 'send':
            logger.info(f"📧 订单 {order_id} 的邮件已经发送过，跳过重复发送")
            return jsonify({
                'success': True,
                'message': '邮件已经发送过了，如需重新发送请点击"重新发送邮件"',
                'email_sent': True,
                'duplicate_prevented': True,
                'license_info': {
                    'order_id': order_id,
                    'license_id': license_id,
                    'activation_code': activation_code,
                    'plan': plan,
                    'device_cap': device_cap,
                    'valid_until': (valid_until + timedelta(hours=8)).strftime('%Y-%m-%d %H:%M:%S') if valid_until and hasattr(valid_until, 'strftime') else (str(valid_until) if valid_until else '永久')
                }
            })
        
        # 构建许可证信息（转换为北京时间）
        license_info = {
            'order_id': order_id,
            'license_id': license_id,
            'activation_code': activation_code,
            'plan': plan,
            'device_cap': device_cap,
            'valid_until': (valid_until + timedelta(hours=8)).strftime('%Y-%m-%d %H:%M:%S') if valid_until and hasattr(valid_until, 'strftime') else (str(valid_until) if valid_until else '永久')
        }
        
        # 发送邮件
        email_sent_result = send_activation_email(email, license_info, user_choice)
        
        if email_sent_result:
            # 更新邮件发送状态
            if user_choice == 'send':
                conn = license_manager.get_connection()
                if conn:
                    cur = conn.cursor()
                    cur.execute('''
                        UPDATE payment_orders SET email_sent = 1 WHERE order_id = %s
                    ''', (order_id,))
                    conn.commit()
                    cur.close()
                
                return jsonify({
                    'success': True,
                    'message': '激活码邮件发送成功！请检查您的邮箱（包括垃圾邮件文件夹）',
                    'email_sent': True,
                    'license_info': license_info
                })
            else:
                return jsonify({
                    'success': True,
                    'message': '已选择不发送邮件',
                    'email_sent': False,
                    'license_info': license_info
                })
        else:
            return jsonify({
                'success': False,
                'message': '邮件发送失败',
                'email_sent': False,
                'license_info': license_info
            }), 500
            
    except Exception as e:
        logger.error(f"❌ 邮件发送选择处理失败: {str(e)}")
        return jsonify({'success': False, 'message': '处理失败'}), 500

@app.route('/api/payment/verify-coupon', methods=['POST'])
def verify_coupon():
    """验证优惠码"""
    try:
        data = request.get_json(force=True)
        code = data.get('code', '').strip()
        plan = data.get('plan')
        device_cap = int(data.get('device_cap', 5))
        base_price = float(data.get('base_price', 0))
        days = data.get('days')
        
        if not code or not plan or not base_price:
            return jsonify({'valid': False, 'message': '缺少必要参数'}), 400
        
        # 查询优惠码
        conn = license_manager.get_connection()
        if not conn:
            return jsonify({'success': False, 'message': '数据库连接失败'}), 500
        cur = conn.cursor(dictionary=True)
        cur.execute('''
            SELECT id, type, value, min_amount, plans, usage_limit, user_limit, 
                   start_date, end_date, is_active, usage_count
            FROM coupons 
            WHERE code = %s
        ''', (code,))
        row = cur.fetchone()
        cur.close()
        
        if not row:
            return jsonify({'valid': False, 'message': '优惠码不存在'})
        
        coupon_id = row['id']
        coupon_type = row['type']
        value = float(row['value']) if row['value'] is not None else 0.0
        min_amount = float(row['min_amount']) if row['min_amount'] is not None else 0.0
        plans_json = row['plans']
        usage_limit = row['usage_limit']
        user_limit = row['user_limit']
        start_date = row['start_date']
        end_date = row['end_date']
        is_active = row['is_active']
        usage_count = row['usage_count']
        
        try:
            base_price = float(base_price)
        except Exception:
            base_price = 0.0
        
        # 检查优惠码是否启用
        if not is_active:
            return jsonify({'valid': False, 'message': '优惠码已停用'})
        
        # 检查有效期
        now = datetime.now(timezone.utc)
        # 将数据库中的naive datetime转换为timezone-aware datetime进行比较
        if start_date and isinstance(start_date, datetime):
            if start_date.tzinfo is None:
                start_date = start_date.replace(tzinfo=timezone.utc)
            if now < start_date:
                return jsonify({'valid': False, 'message': '优惠码尚未生效'})
        if end_date and isinstance(end_date, datetime):
            if end_date.tzinfo is None:
                end_date = end_date.replace(tzinfo=timezone.utc)
            if now > end_date:
                return jsonify({'valid': False, 'message': '优惠码已过期'})
        
        # 检查使用次数限制
        if usage_count >= usage_limit:
            return jsonify({'valid': False, 'message': '优惠码使用次数已达上限'})
        
        # 检查适用计划
        plans = json.loads(str(plans_json)) if plans_json else []
        if plan not in plans:
            return jsonify({'valid': False, 'message': '优惠码不适用于此计划'})
        
        # 检查最低消费
        if min_amount > 0 and base_price < min_amount:
            return jsonify({'valid': False, 'message': f'最低消费金额为¥{min_amount}'})
        
        # 计算折扣
        if coupon_type == 'fixed':
            discount = min(value, base_price)  # 固定金额减免，不超过原价
            final_price = max(0, base_price - discount)
        else:  # percentage
            discount = base_price * (value / 100)  # 百分比折扣
            final_price = max(0, base_price - discount)
        
        # 检查用户使用次数限制
        if user_limit > 1:
            cur = conn.cursor()
            cur.execute('''
                SELECT COUNT(*) FROM coupon_usage_logs 
                WHERE coupon_id = %s AND user_email = %s
            ''', (coupon_id, data.get('email', '')))
            result = cur.fetchone()
            user_usage_count = result[0] if result else 0
            cur.close()
            
            if user_usage_count >= user_limit:
                return jsonify({'valid': False, 'message': '您已达到此优惠码的使用次数限制'})
        
        return jsonify({
            'valid': True,
            'message': f'优惠码有效，减免¥{discount:.2f}',
            'discount': discount,
            'final_price': final_price,
            'coupon_id': coupon_id
        })
        
    except Exception as e:
        logger.error(f"❌ 验证优惠码失败: {str(e)}")
        return jsonify({'valid': False, 'message': '验证优惠码失败'}), 500

def verify_coupon_internal(data):
    """内部优惠码验证函数（供其他API调用）"""
    try:
        code = data.get('code', '').strip()
        plan = data.get('plan')
        device_cap = int(data.get('device_cap', 5))
        base_price = float(data.get('base_price', 0))
        days = data.get('days')
        email = data.get('email', '')
        
        if not code or not plan or not base_price:
            return {'valid': False, 'message': '缺少必要参数'}
        
        # 查询优惠码
        conn = license_manager.get_connection()
        if not conn:
            return {'valid': False, 'message': '数据库连接失败'}
        cur = conn.cursor(dictionary=True)
        cur.execute('''
            SELECT id, type, value, min_amount, plans, usage_limit, user_limit, 
                   start_date, end_date, is_active, usage_count
            FROM coupons 
            WHERE code = %s
        ''', (code,))
        row = cur.fetchone()
        cur.close()
        
        if not row:
            return {'valid': False, 'message': '优惠码不存在'}
        
        coupon_id = row['id']
        coupon_type = row['type']
        value = float(row['value']) if row['value'] is not None else 0.0
        min_amount = float(row['min_amount']) if row['min_amount'] is not None else 0.0
        plans_json = row['plans']
        usage_limit = row['usage_limit']
        user_limit = row['user_limit']
        start_date = row['start_date']
        end_date = row['end_date']
        is_active = row['is_active']
        usage_count = row['usage_count']
        
        # 检查优惠码是否启用
        if not is_active:
            return {'valid': False, 'message': '优惠码已停用'}
        
        # 检查有效期
        now = datetime.now(timezone.utc)
        # 将数据库中的naive datetime转换为timezone-aware datetime进行比较
        if start_date and isinstance(start_date, datetime):
            if start_date.tzinfo is None:
                start_date = start_date.replace(tzinfo=timezone.utc)
            if now < start_date:
                return {'valid': False, 'message': '优惠码尚未生效'}
        if end_date and isinstance(end_date, datetime):
            if end_date.tzinfo is None:
                end_date = end_date.replace(tzinfo=timezone.utc)
            if now > end_date:
                return {'valid': False, 'message': '优惠码已过期'}
        
        # 检查使用次数限制
        if usage_count >= usage_limit:
            return {'valid': False, 'message': '优惠码使用次数已达上限'}
        
        # 检查适用计划
        plans = json.loads(str(plans_json)) if plans_json else []
        if plan not in plans:
            return {'valid': False, 'message': '优惠码不适用于此计划'}
        
        # 检查最低消费
        if min_amount > 0 and base_price < min_amount:
            return {'valid': False, 'message': f'最低消费金额为¥{min_amount}'}
        
        # 计算折扣
        if coupon_type == 'fixed':
            discount = min(value, base_price)  # 固定金额减免，不超过原价
            final_price = max(0, base_price - discount)
        else:  # percentage
            discount = base_price * (value / 100)  # 百分比折扣
            final_price = max(0, base_price - discount)
        
        # 检查用户使用次数限制
        if user_limit > 1 and email:
            cur = conn.cursor()
            cur.execute('''
                SELECT COUNT(*) FROM coupon_usage_logs 
                WHERE coupon_id = %s AND user_email = %s
            ''', (coupon_id, email))
            result = cur.fetchone()
            user_usage_count = result[0] if result else 0
            cur.close()
            
            if user_usage_count >= user_limit:
                return {'valid': False, 'message': '您已达到此优惠码的使用次数限制'}
        
        return {
            'valid': True,
            'message': f'优惠码有效，减免¥{discount:.2f}',
            'discount': discount,
            'final_price': final_price,
            'coupon_id': coupon_id
        }
        
    except Exception as e:
        logger.error(f"❌ 内部优惠码验证失败: {str(e)}")
        return {'valid': False, 'message': '验证优惠码失败'}

@app.route('/api/payment/create', methods=['POST'])
def create_payment():
    """创建支付订单"""
    try:
        data = request.get_json(force=True)
        email = data.get('email')
        plan = data.get('plan')
        device_cap = int(data.get('device_cap', 5))
        days = data.get('days')
        coupon_code = data.get('coupon_code')
        
        if not email or not plan:
            return jsonify({'success': False, 'message': '缺少必要参数'}), 400
            
        # 规范 plan 并补全 days，避免后续生成许可证时 valid_until 为 NULL
        plan = (plan or '').strip().lower()
        if plan not in ('monthly', 'yearly', 'lifetime'):
            return jsonify({'success': False, 'message': '不支持的套餐类型'}), 400
        if days is None:
            if plan == 'monthly':
                days = 31
            elif plan == 'yearly':
                days = 365
        
        # 生成订单号
        order_id = f"ORDER-{int(time.time())}-{uuid.uuid4().hex[:8].upper()}"
        
        # 计算基础价格（使用配置文件中的价格）
        prices = {
            'lifetime': 29.90,
            'monthly': 5.00,
            'yearly': 50.00
        }
        base_amount = prices.get(plan, 29.90)
        
        # 计算最终价格（考虑设备数量和优惠码）
        final_amount = base_amount
        discount_amount = 0
        coupon_id = None
        
        # 根据设备数量调整价格
        if device_cap > 5:
            final_amount = base_amount + (device_cap - 5) * 10
        
        # 应用优惠码
        if coupon_code:
            try:
                logger.info(f"🔍 开始验证优惠码: {coupon_code}, 基础价格: ¥{final_amount}")
                # 验证优惠码
                coupon_response = verify_coupon_internal({
                    'code': coupon_code,
                    'plan': plan,
                    'device_cap': device_cap,
                    'base_price': final_amount,
                    'days': days,
                    'email': email
                })
                
                logger.info(f"🔍 优惠码验证结果: {coupon_response}")
                
                if coupon_response.get('valid'):
                    discount_amount = coupon_response.get('discount', 0)
                    original_amount = final_amount
                    final_amount = max(0, final_amount - discount_amount)
                    coupon_id = coupon_response.get('coupon_id')
                    logger.info(f"✅ 优惠码应用成功: {coupon_code}, 原价: ¥{original_amount}, 减免: ¥{discount_amount}, 最终价格: ¥{final_amount}")
                else:
                    logger.warning(f"⚠️ 优惠码验证失败: {coupon_code}, 原因: {coupon_response.get('message')}")
            except Exception as e:
                logger.error(f"❌ 优惠码验证异常: {str(e)}")
                import traceback
                logger.error(f"❌ 异常堆栈: {traceback.format_exc()}")
        
        # 保存订单到数据库（包含优惠码信息）
        conn = license_manager.get_connection()
        if not conn:
            return jsonify({'success': False, 'message': '数据库连接失败'}), 500
        cur = conn.cursor()
        cur.execute('''
            INSERT INTO payment_orders (order_id, email, plan, device_cap, days, amount, 
                                      coupon_code, coupon_id, discount_amount, status, created_at)
            VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, 'pending', %s)
        ''', (order_id, email, plan, device_cap, days, final_amount, 
              coupon_code, coupon_id, discount_amount, datetime.now(timezone.utc)))
        conn.commit()
        cur.close()
        
        # 如果最终金额为0，仍然通过ZPAY创建订单（确保在ZPAY中可见）
        if final_amount <= 0:
            logger.info(f"🎉 免费订单，通过ZPAY创建: {order_id}")
            
            # 构建ZPAY订单数据（0元订单）
            order_data = {
                'order_id': order_id,
                'payment_type': 'alipay',
                'notify_url': ZPAY_CONFIG['notify_url'],
                'return_url': ZPAY_CONFIG['return_url'],
                'product_name': f'OneClip {plan}许可证 (免费)',
                'amount': final_amount,
                'client_ip': request.remote_addr,
                'device': 'pc',
                'param': json.dumps({
                    'email': email,
                    'plan': plan,
                    'device_cap': device_cap,
                    'coupon_code': coupon_code,
                    'is_free': True
                })
            }
            
            # 临时方案：直接完成0元订单，不通过ZPAY
            logger.info(f"🎉 免费订单，直接完成: {order_id}")
            
            # 更新订单状态为已支付（0元订单直接完成）
            cur = conn.cursor()
            cur.execute('''
                UPDATE payment_orders 
                SET status = 'paid', paid_at = %s, trade_no = %s
                WHERE order_id = %s
            ''', (datetime.now(timezone.utc), f"FREE-{order_id}", order_id))
            
            # 更新优惠码使用次数（免费订单也需要记录使用）
            # 🔧 修复：如果coupon_id为None，从数据库重新查询
            if coupon_code and not coupon_id:
                cur.execute('SELECT id FROM coupons WHERE code = %s', (coupon_code,))
                result = cur.fetchone()
                if result:
                    coupon_id = result[0]
                    logger.info(f"🔍 从数据库重新获取coupon_id: {coupon_id}")
            
            if coupon_code and coupon_id:
                cur.execute('''
                    UPDATE coupons SET usage_count = usage_count + 1 WHERE id = %s
                ''', (coupon_id,))
                
                # 计算金额信息
                original_amount = 5.0 if plan == 'monthly' else (50.0 if plan == 'yearly' else 200.0)
                discount_amount = original_amount  # 100%折扣
                final_amount = 0.0  # 最终金额
                
                cur.execute('''
                    INSERT INTO coupon_usage_logs 
                    (coupon_id, coupon_code, user_email, order_id, 
                     original_amount, discount_amount, final_amount, used_at)
                    VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
                ''', (coupon_id, coupon_code, email, order_id, 
                      original_amount, discount_amount, final_amount, 
                      datetime.now(timezone.utc)))
            
            # 🔧 修复：不要提前commit，等许可证生成成功后再一起提交
            # conn.commit()  # ❌ 移除提前commit
            # cur.close()    # ❌ cursor还要继续使用
            
            # 生成许可证
            try:
                # 0元订单也为月付/年付补充默认时长
                default_days = days
                if default_days is None:
                    if plan == 'monthly':
                        default_days = 31
                    elif plan == 'yearly':
                        default_days = 365
                license_result = license_manager.generate_license_with_email(
                    plan=plan,
                    email=email,
                    device_cap=device_cap,
                    days=default_days,
                    user_hint=f"免费订单: {order_id}"
                )
                
                if 'error' in license_result:
                    logger.error(f"❌ 免费订单许可证生成失败: {license_result['error']}")
                    # 🔧 修复：许可证生成失败时回滚事务
                    conn.rollback()
                    cur.close()
                    return jsonify({'success': False, 'message': '许可证生成失败'}), 500
                
                # 调试日志
                logger.info(f"🔍 许可证生成结果: {license_result}")
                
                # 更新订单的许可证信息
                cur.execute('''
                    UPDATE payment_orders 
                    SET license_id = %s, activation_code = %s 
                    WHERE order_id = %s
                ''', (license_result['license_id'], license_result['activation_code'], order_id))
                
                # 🔧 修复：所有操作成功后统一commit
                conn.commit()
                cur.close()
                
                # 构建许可证信息（不自动发送邮件，让用户选择）
                license_info = {
                    'license_id': license_result['license_id'],
                    'activation_code': license_result['activation_code'],
                    'plan': license_result['plan'],
                    'device_cap': license_result['device_cap'],
                    'valid_until': license_result['valid_until']
                }
                
                logger.info(f"✅ 免费订单完成，许可证已生成: {order_id}")
                
                # 从数据库查询激活码（确保获取最新数据）
                cur = conn.cursor()
                cur.execute('''
                    SELECT activation_code, license_id FROM payment_orders 
                    WHERE order_id = %s
                ''', (order_id,))
                order_data = cur.fetchone()
                cur.close()
                
                activation_code = order_data[0] if order_data else ''
                license_id = order_data[1] if order_data else ''
                
                logger.info(f"🔍 从数据库查询的激活码: {activation_code}")
                
                return jsonify({
                    'success': True,
                    'order_id': order_id,
                    'amount': final_amount,
                    'message': '免费订单已完成，请选择是否发送激活码到邮箱',
                    'license_key': license_result.get('license_key', ''),
                    'is_free': True,
                    'trade_no': f"FREE-{order_id}",
                    'pay_url': '',
                    'qr_code': '',
                    'activation_code': activation_code,
                    'redirect_url': f"/complete_order_page.html?order_id={order_id}&email={email}&plan={plan}&activation_code={activation_code}&device_cap={device_cap}&valid_until={license_result.get('valid_until', '')}&license_id={license_result.get('license_id', '')}&amount={final_amount}"
                })
                    
            except Exception as e:
                logger.error(f"❌ 免费订单处理失败: {str(e)}")
                import traceback
                logger.error(f"❌ 免费订单处理异常详情: {traceback.format_exc()}")
                # 🔧 修复：异常时回滚事务
                try:
                    conn.rollback()
                    cur.close()
                except:
                    pass
                return jsonify({'success': False, 'message': f'免费订单处理失败: {str(e)}'}), 500
        
        # 构建ZPAY订单数据
        logger.info(f"🔍 构建ZPAY订单数据: 订单ID={order_id}, 最终金额=¥{final_amount}, 优惠码={coupon_code}")
        order_data = {
            'order_id': order_id,
            'payment_type': 'alipay',  # 支付方式：alipay, wxpay
            'notify_url': ZPAY_CONFIG['notify_url'],
            'return_url': ZPAY_CONFIG['return_url'],
            'product_name': f'OneClip {plan}许可证',
            'amount': final_amount,
            'client_ip': request.remote_addr,
            'device': 'pc',
            'param': json.dumps({
                'email': email,
                'plan': plan,
                'device_cap': device_cap,
                'coupon_code': coupon_code
            })
        }
        logger.info(f"🔍 ZPAY订单数据详情: {json.dumps(order_data, indent=2, ensure_ascii=False)}")
        
        # 创建ZPAY支付订单
        print(f"🔍 调试：开始调用ZPAY适配器")
        result = zpay_adapter.create_order(order_data)
        print(f"🔍 调试：ZPAY适配器返回结果: {result}")
        
        # 添加调试日志
        logger.info(f"🔍 ZPAY适配器返回结果: {result}")
        logger.info(f"🔍 ZPAY适配器返回的img字段: {result.get('img', 'N/A')}")
        logger.info(f"🔍 ZPAY适配器返回的qr_code字段: {result.get('qr_code', 'N/A')}")
        
        if result['success']:
            response_data = {
                'success': True,
                'order_id': order_id,
                'pay_url': result.get('pay_url', ''),
                'qrcode': result.get('qr_code', ''),
                'img': result.get('img', ''),  # 使用ZPAY返回的img字段
                'amount': final_amount,
                'is_free': final_amount <= 0,  # 添加is_free字段
                'message': '订单创建成功'
            }
            logger.info(f"🔍 最终返回数据: {response_data}")
            return jsonify(response_data)
        else:
            return jsonify({
                'success': False,
                'message': result['message']
            }), 400
            
    except Exception as e:
        logger.error(f"❌ 创建支付订单失败: {str(e)}")
        return jsonify({'success': False, 'message': '创建订单失败'}), 500

@app.route('/api/payment/notify', methods=['POST', 'GET'])
def payment_notify():
    """ZPAY支付异步通知 - 修复版"""
    try:
        # 获取通知参数 - 支持POST和GET
        if request.method == 'POST':
            notify_data = request.form.to_dict()
        else:
            notify_data = request.args.to_dict()
        
        logger.info(f"🔔 收到ZPAY支付通知 ({request.method}): {notify_data}")
        
        # 验证必要参数
        required_fields = ['pid', 'out_trade_no', 'trade_no', 'trade_status', 'sign']
        missing_fields = [field for field in required_fields if field not in notify_data]
        if missing_fields:
            logger.error(f"❌ 缺少必要参数: {missing_fields}")
            return 'fail'
        
        # 验证商户ID
        if notify_data.get('pid') != ZPAY_CONFIG['pid']:
            logger.error(f"❌ 商户ID不匹配: {notify_data.get('pid')} != {ZPAY_CONFIG['pid']}")
            return 'fail'
        
        # 验证支付状态
        if notify_data.get('trade_status') != 'TRADE_SUCCESS':
            logger.warning(f"⚠️ 支付状态不是成功: {notify_data.get('trade_status')}")
            return 'fail'
        
        # 验证签名
        received_sign = notify_data.get('sign', '')
        calculated_sign = generate_zpay_sign(notify_data, ZPAY_CONFIG['key'])
        
        if received_sign.lower() != calculated_sign.lower():
            logger.error(f"❌ 签名验证失败: 接收={received_sign}, 计算={calculated_sign}")
            return 'fail'
        
        order_id = notify_data.get('out_trade_no')
        trade_no = notify_data.get('trade_no')
        
        logger.info(f"✅ ZPAY支付回调验证成功: 订单={order_id}")
        
        # 查询订单
        conn = license_manager.get_connection()
        if not conn:
            logger.error("❌ 数据库连接失败")
            return 'fail'
        
        # 🔧 修复：使用dictionary=True避免字段映射错误
        cur = conn.cursor(dictionary=True)
        cur.execute('SELECT * FROM payment_orders WHERE order_id = %s AND status = "pending"', (order_id,))
        order = cur.fetchone()
        
        if not order:
            logger.warning(f"⚠️ 订单不存在或已处理: {order_id}")
            cur.close()
            return 'success'  # 即使订单不存在也返回success，避免重复通知
        
        logger.info(f"🔍 找到订单: {order}")
        
        # 🔧 更新订单状态（添加幂等性检查，防止重复处理）
        cur.execute('''
            UPDATE payment_orders 
            SET status = "paid", trade_no = %s, paid_at = %s 
            WHERE order_id = %s AND status = "pending"
        ''', (trade_no, datetime.now(timezone.utc), order_id))
        
        # 🔒 幂等性保护：如果没有更新任何行，说明订单已处理
        if cur.rowcount == 0:
            logger.warning(f"⚠️ 订单{order_id}已处理，跳过（幂等性保护，防止重复生成许可证）")
            cur.close()
            return 'success'
        
        # 生成许可证
        plan = (order['plan'] or '').lower()
        # 为不同套餐提供默认天数，避免NULL导致被当作终身
        order_days = order['days']
        if order_days is None:
            if plan == 'monthly':
                order_days = 31
            elif plan == 'yearly':
                order_days = 365
        logger.info(f"🔧 开始生成许可证: plan={plan}, email={order['email']}, device_cap={order['device_cap']}, days={order_days}")
        license_result = license_manager.generate_license_with_email(
            plan=plan,
            email=order['email'],
            device_cap=order['device_cap'],
            days=order_days,
            user_hint=f"购买订单: {order_id}"
        )
        
        logger.info(f"🔍 许可证生成结果: {license_result}")
        
        if 'error' in license_result:
            logger.error(f"❌ 许可证生成失败: {license_result['error']}")
            cur.close()
            return 'fail'
        
        # 更新订单的许可证信息，标记邮件已发送
        cur.execute('''
            UPDATE payment_orders 
            SET license_id = %s, activation_code = %s, email_sent = 1 
            WHERE order_id = %s
        ''', (license_result['license_id'], license_result['activation_code'], order_id))
        
        # 记录优惠码使用
        # 🔧 修复：如果coupon_id为None，从数据库重新查询
        if order['coupon_code']:
            coupon_id_from_order = order['coupon_id']
            if not coupon_id_from_order:
                cur.execute('SELECT id FROM coupons WHERE code = %s', (order['coupon_code'],))
                result = cur.fetchone()
                if result:
                    coupon_id_from_order = result[0]
                    logger.info(f"🔍 [支付回调] 从数据库重新获取coupon_id: {coupon_id_from_order}")
            
            if coupon_id_from_order:
                cur.execute('''
                    UPDATE coupons SET usage_count = usage_count + 1 WHERE id = %s
                ''', (coupon_id_from_order,))
            else:
                logger.error(f"❌ 无法找到优惠码ID: {order['coupon_code']}")
            
            # 计算优惠信息用于记录
            # 🔧 修复：使用订单中保存的真实优惠金额，而不是硬编码
            if coupon_id_from_order:
                final_amount = float(order['amount'])
                discount_amount = float(order.get('discount_amount', 0))  # 从订单中读取真实优惠金额
                original_amount = final_amount + discount_amount  # 原价 = 最终价 + 优惠金额
                
                cur.execute('''
                    INSERT INTO coupon_usage_logs 
                    (coupon_id, user_email, order_id, used_at, coupon_code, original_amount, discount_amount, final_amount)
                    VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
                ''', (coupon_id_from_order, order['email'], order_id, datetime.now(timezone.utc), order['coupon_code'], 
                      original_amount, discount_amount, final_amount))
        
        conn.commit()
        cur.close()
        
        # 发送激活码邮件
        license_info = {
            'order_id': order_id,
            'license_id': license_result['license_id'],
            'activation_code': license_result['activation_code'],
            'plan': license_result['plan'],
            'device_cap': license_result['device_cap'],
            'valid_until': license_result['valid_until']
        }
        
        if send_activation_email(order['email'], license_info):
            logger.info(f"✅ ZPAY支付成功，许可证生成并邮件发送成功: {order_id}")
        else:
            logger.warning(f"⚠️ ZPAY支付成功，许可证生成成功但邮件发送失败: {order_id}")
        
        return 'success'  # 返回纯字符串success
        
    except Exception as e:
        logger.error(f"❌ 处理支付通知失败: {str(e)}")
        import traceback
        logger.error(f"❌ 错误详情: {traceback.format_exc()}")
        return 'fail'

@app.route('/api/payment/return', methods=['GET'])
def payment_return():
    """支付完成后的跳转页面"""
    try:
        order_id = request.args.get('out_trade_no')
        trade_status = request.args.get('trade_status')
        
        if not order_id:
            return jsonify({'success': False, 'message': '订单号缺失'}), 400
        
        # 查询订单状态
        conn = license_manager.get_connection()
        if not conn:
            return jsonify({'success': False, 'message': '数据库连接失败'}), 500
        cur = conn.cursor(dictionary=True)
        cur.execute('SELECT * FROM payment_orders WHERE order_id = %s', (order_id,))
        order = cur.fetchone()
        cur.close()
        
        if not order:
            return jsonify({'success': False, 'message': '订单不存在'}), 404
        
        if order['status'] == 'paid':
            # 跳转到订单完成页面
            return redirect(f'/complete_order_page.html?order_id={order_id}&email={order["email"]}')
        else:
            # 支付未完成，跳转到购买页面
            return redirect('/purchase')
            
    except Exception as e:
        logger.error(f"❌ 查询支付状态失败: {str(e)}")
        return redirect('/purchase')

@app.route('/api/payment/orders', methods=['GET'])
def get_payment_orders():
    """获取支付订单列表（管理员）"""
    auth = require_admin()
    if auth is not None:
        return auth
    
    try:
        conn = license_manager.get_connection()
        if not conn:
            return jsonify({'success': False, 'message': '数据库连接失败'}), 500
        cur = conn.cursor(dictionary=True)
        cur.execute('''
            SELECT * FROM payment_orders 
            ORDER BY created_at DESC 
            LIMIT 100
        ''')
        orders = cur.fetchall()
        cur.close()
        
        return jsonify({'success': True, 'orders': orders})
        
    except Exception as e:
        logger.error(f"❌ 获取支付订单失败: {str(e)}")
        return jsonify({'success': False, 'message': '查询失败'}), 500

# 🔒 订单查询频率限制（防止暴力枚举）
order_query_attempts = {}
ORDER_QUERY_LIMIT = 10  # 每分钟最多10次查询
ORDER_QUERY_WINDOW = 60  # 60秒窗口

def check_order_query_rate_limit(ip):
    """检查订单查询频率限制"""
    now = time.time()
    if ip not in order_query_attempts:
        order_query_attempts[ip] = []
    
    # 清理过期记录
    order_query_attempts[ip] = [t for t in order_query_attempts[ip] if now - t < ORDER_QUERY_WINDOW]
    
    if len(order_query_attempts[ip]) >= ORDER_QUERY_LIMIT:
        return False
    
    order_query_attempts[ip].append(now)
    return True

@app.route('/api/payment/query-order', methods=['POST'])
def query_order():
    """
    🔒 安全的订单查询接口
    要求：必须同时提供订单号和邮箱，两者必须匹配
    限制：频率限制，防止暴力枚举
    返回：不返回完整激活码，只返回脱敏信息
    """
    try:
        # 🔒 频率限制检查
        client_ip = request.remote_addr
        if not check_order_query_rate_limit(client_ip):
            logger.warning(f"⚠️ 订单查询频率超限: {client_ip}")
            return jsonify({
                'success': False,
                'message': '查询过于频繁，请稍后再试'
            }), 429
        
        data = request.get_json()
        if not data:
            return jsonify({
                'success': False,
                'message': '请求数据为空'
            }), 400
        
        order_id = data.get('order_id', '').strip()
        email = data.get('email', '').strip()
        
        # 🔒 安全要求：必须同时提供订单号和邮箱
        if not order_id or not email:
            return jsonify({
                'success': False,
                'message': '请同时提供订单号和邮箱地址'
            }), 400
        
        # 🔒 验证邮箱格式
        import re
        if not re.match(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$', email):
            return jsonify({
                'success': False,
                'message': '邮箱格式不正确'
            }), 400
        
        conn = license_manager.get_connection()
        if not conn:
            return jsonify({'success': False, 'message': '数据库连接失败'}), 500
        cur = conn.cursor(dictionary=True)
        
        # 🔒 安全查询：订单号和邮箱必须同时匹配（AND 而非 OR）
        query = '''
            SELECT 
                order_id, email, plan, device_cap, days, amount, 
                status, trade_no, license_id, activation_code,
                created_at, paid_at
            FROM payment_orders 
            WHERE order_id = %s AND email = %s
            LIMIT 1
        '''
        
        cur.execute(query, (order_id, email))
        order = cur.fetchone()
        cur.close()
        
        if not order:
            # 🔒 模糊错误信息，不透露是订单号错误还是邮箱错误
            logger.info(f"订单查询未匹配: order_id={order_id[:8]}***, email={email[:3]}***")
            return jsonify({
                'success': False,
                'message': '订单信息不匹配，请检查订单号和邮箱'
            }), 404
        
        # 🔒 脱敏处理激活码：只显示前4位和后4位
        activation_code = order['activation_code']
        if activation_code and len(activation_code) > 8:
            masked_code = activation_code[:4] + '****' + activation_code[-4:]
        else:
            masked_code = '****'
        
        # 🔒 脱敏处理邮箱
        email_parts = order['email'].split('@')
        if len(email_parts) == 2:
            masked_email = email_parts[0][:2] + '***@' + email_parts[1]
        else:
            masked_email = '***'
        
        formatted_order = {
            'order_id': order['order_id'],
            'email': masked_email,  # 🔒 脱敏邮箱
            'plan': order['plan'],
            'device_cap': order['device_cap'],
            'days': order['days'],
            'amount': float(order['amount']),
            'status': order['status'],
            'status_text': get_status_text(order['status']),
            'license_id': order['license_id'],
            'activation_code_masked': masked_code,  # 🔒 脱敏激活码
            # 🔒 只有已支付订单才返回完整激活码
            'activation_code': order['activation_code'] if order['status'] == 'paid' else None,
            'created_at': order['created_at'].isoformat() if order['created_at'] else None,
            'paid_at': order['paid_at'].isoformat() if order['paid_at'] else None
        }
        
        logger.info(f"✅ 订单查询成功: {order_id[:8]}***")
        return jsonify({
            'success': True,
            'order': formatted_order
        })
        
    except Exception as e:
        logger.error(f"❌ 查询订单失败: {str(e)}")
        return jsonify({'success': False, 'message': '查询失败'}), 500

def get_status_text(status):
    """获取订单状态的中文描述"""
    status_map = {
        'pending': '待支付',
        'paid': '已支付',
        'failed': '支付失败',
        'cancelled': '已取消'
    }
    return status_map.get(status, status)

@app.route('/api/admin/export', methods=['GET'])
def admin_export_csv():
    auth = require_admin()
    if auth is not None:
        return auth
    try:
        import csv
        from io import StringIO
        status = request.args.get('status', None)
        query = (request.args.get('q') or '').strip()
        rows = license_manager.list_licenses(status, 10000)
        if query:
            ql = query.lower()
            rows = [r for r in rows if (
                (r.get('email') or '').lower().find(ql) >= 0 or
                (r.get('license_id') or '').lower().find(ql) >= 0 or
                (r.get('activation_code') or '').lower().find(ql) >= 0
            )]

        output = StringIO()
        writer = csv.writer(output)
        writer.writerow(['license_id','email','plan','device_limit','active_devices','valid_until','status','activation_code','created_at'])
        for r in rows:
            writer.writerow([
                r.get('license_id'), r.get('email'), r.get('plan'), r.get('device_limit'),
                r.get('active_devices'), r.get('valid_until'), r.get('status'), r.get('activation_code'),
                r.get('created_at')
            ])
        csv_data = output.getvalue()
        return app.response_class(
            csv_data,
            mimetype='text/csv; charset=utf-8',
            headers={'Content-Disposition': 'attachment; filename=oneclip_licenses.csv'}
        )
    except Exception as e:
        logger.error(f"❌ 导出CSV失败: {str(e)}")
        return jsonify({'success': False, 'message': '导出失败'}), 500

@app.route('/api/user/devices', methods=['POST'])
def get_user_devices():
    """获取用户的设备列表"""
    try:
        data = request.get_json(force=True)
        activation_code = data.get('activation_code')
        email = data.get('email')
        
        if not activation_code or not email:
            return jsonify({'success': False, 'message': '缺少必要参数'}), 400
        
        # 验证许可证
        result = license_manager.verify_license_with_email(activation_code, email)
        if not result['valid']:
            return jsonify({'success': False, 'message': result['error']}), 400
        
        license_id = result['license_id']
        
        # 获取用户的设备列表
        conn = license_manager.get_connection()
        if not conn:
            return jsonify({'success': False, 'message': '数据库连接失败'}), 500
        cur = conn.cursor(dictionary=True)
        
        cur.execute('''
            SELECT device_id, device_name, ip_address, last_seen_at, is_active
            FROM device_activations 
            WHERE license_id = %s 
            ORDER BY last_seen_at DESC
        ''', (license_id,))
        
        devices = cur.fetchall()
        cur.close()
        
        # 格式化设备信息
        device_list = []
        for device in devices:
            device_list.append({
                'device_id': device['device_id'],
                'device_name': device['device_name'],
                'ip_address': device['ip_address'],
                'last_seen_at': device['last_seen_at'].isoformat() if device['last_seen_at'] else None,
                'is_active': bool(device['is_active'])
            })
        
        return jsonify({
            'success': True,
            'devices': device_list
        })
            
    except Exception as e:
        logger.error(f"❌ 获取用户设备列表失败: {str(e)}")
        return jsonify({'success': False, 'message': '获取设备列表失败'}), 500

@app.route('/api/check-revoke-status', methods=['POST'])
@require_api_key
def check_revoke_status():
    """检查激活码是否被撤销"""
    try:
        data = request.get_json(force=True)
        license_id = data.get('license_id', '').strip()
        email = data.get('email', '').strip()
        
        if not license_id or not email:
            return jsonify({
                'success': False,
                'message': '缺少必要参数',
                'code': 'MISSING_PARAMS'
            }), 400
        
        logger.info(f"🔍 检查撤销状态: license_id={license_id}, email={email}")
        
        # 查询撤销列表
        conn = license_manager.get_connection()
        if not conn:
            return jsonify({'success': False, 'message': '数据库连接失败'}), 500
        cur = conn.cursor(dictionary=True)
        
        # 检查激活码是否在撤销列表中
        cur.execute('''
            SELECT rl.*, l.email as license_email
            FROM revoked_licenses rl
            JOIN licenses l ON rl.license_id = l.license_id
            WHERE rl.license_id = %s AND l.email = %s
        ''', (license_id, email))
        
        revoked_record = cur.fetchone()
        cur.close()
        
        if revoked_record:
            logger.warning(f"❌ 激活码已被撤销: {license_id}")
            return jsonify({
                'success': True,
                'isRevoked': True,
                'reason': revoked_record.get('reason', '未知原因'),
                'revoked_at': revoked_record.get('revoked_at', '').isoformat() if revoked_record.get('revoked_at') else None,
                'revoked_by': revoked_record.get('revoked_by', '未知'),
                'message': '激活码已被撤销'
            })
        else:
            logger.info(f"✅ 激活码状态正常: {license_id}")
            return jsonify({
                'success': True,
                'isRevoked': False,
                'message': '激活码状态正常'
            })
            
    except Exception as e:
        logger.error(f"❌ 检查撤销状态失败: {str(e)}")
        return jsonify({
            'success': False,
            'message': f'检查失败: {str(e)}',
            'code': 'INTERNAL_ERROR'
        }), 500

@app.route('/api/suspend-device', methods=['POST'])
def suspend_device():
    """停用设备"""
    try:
        data = request.get_json(force=True)
        activation_code = data.get('activation_code')
        email = data.get('email')
        device_id = data.get('device_id')
        reason = data.get('reason', '用户停用')
        
        if not activation_code or not email or not device_id:
            return jsonify({'success': False, 'message': '缺少必要参数'}), 400
        
        logger.info(f"🔍 收到停用设备请求: activation_code={activation_code}, email={email}, device_id={device_id}")
        
        # 验证许可证
        result = license_manager.verify_license_with_email(activation_code, email)
        if not result['valid']:
            logger.warning(f"❌ 许可证验证失败: {result.get('error', '未知错误')}")
            return jsonify({'success': False, 'message': result['error']}), 400
        
        license_id = result['license_id']
        logger.info(f"✅ 许可证验证成功: {license_id}")
        
        # 获取数据库连接
        conn = license_manager.get_connection()
        if not conn:
            logger.error("❌ 无法获取数据库连接")
            return jsonify({'success': False, 'message': '数据库连接失败'}), 500
        
        try:
            cur = conn.cursor()
            
            # 检查设备是否存在
            cur.execute('''
                SELECT 1 FROM device_activations 
                WHERE license_id = %s AND device_id = %s
            ''', (license_id, device_id))
            
            if not cur.fetchone():
                logger.warning(f"❌ 设备不存在: license_id={license_id}, device_id={device_id}")
                return jsonify({'success': False, 'message': '设备不存在'}), 404
            
            # 停用设备
            cur.execute('''
                UPDATE device_activations 
                SET is_active = 0 
                WHERE license_id = %s AND device_id = %s
            ''', (license_id, device_id))
            
            if cur.rowcount == 0:
                logger.warning(f"❌ 设备停用失败，没有行被更新: license_id={license_id}, device_id={device_id}")
                return jsonify({'success': False, 'message': '设备停用失败'}), 500
            
            # 记录停用历史
            cur.execute('''
                INSERT INTO activation_history (license_id, action, device_id, details)
                VALUES (%s, 'suspend', %s, %s)
            ''', (license_id, device_id, json.dumps({"reason": reason, "suspended_by": "user"})))
            
            conn.commit()
            cur.close()
            
            logger.info(f"✅ 设备停用成功: {device_id}")
            return jsonify({'success': True, 'message': '设备已停用'})
            
        except Exception as db_error:
            logger.error(f"❌ 数据库操作失败: {str(db_error)}")
            if conn:
                conn.rollback()
            return jsonify({'success': False, 'message': f'数据库操作失败: {str(db_error)}'}), 500
        finally:
            if cur:
                cur.close()
        
    except Exception as e:
        logger.error(f"❌ 停用设备失败: {str(e)}")
        return jsonify({'success': False, 'message': f'停用失败: {str(e)}'}), 500

@app.route('/api/restore-device', methods=['POST'])
def restore_device():
    """恢复设备"""
    try:
        data = request.get_json(force=True)
        activation_code = data.get('activation_code')
        email = data.get('email')
        device_id = data.get('device_id')
        reason = data.get('reason', '用户恢复')
        
        if not activation_code or not email or not device_id:
            return jsonify({'success': False, 'message': '缺少必要参数'}), 400
        
        logger.info(f"🔍 收到恢复设备请求: activation_code={activation_code}, email={email}, device_id={device_id}")
        
        # 验证许可证
        result = license_manager.verify_license_with_email(activation_code, email)
        if not result['valid']:
            logger.warning(f"❌ 许可证验证失败: {result.get('error', '未知错误')}")
            return jsonify({'success': False, 'message': result['error']}), 400
        
        license_id = result['license_id']
        logger.info(f"✅ 许可证验证成功: {license_id}")
        
        # 获取数据库连接
        conn = license_manager.get_connection()
        if not conn:
            logger.error("❌ 无法获取数据库连接")
            return jsonify({'success': False, 'message': '数据库连接失败'}), 500
        
        try:
            cur = conn.cursor()
            
            # 检查设备是否存在
            cur.execute('''
                SELECT 1 FROM device_activations 
                WHERE license_id = %s AND device_id = %s
            ''', (license_id, device_id))
            
            if not cur.fetchone():
                logger.warning(f"❌ 设备不存在: license_id={license_id}, device_id={device_id}")
                return jsonify({'success': False, 'message': '设备不存在'}), 404
            
            # 恢复设备
            cur.execute('''
                UPDATE device_activations 
                SET is_active = 1 
                WHERE license_id = %s AND device_id = %s
            ''', (license_id, device_id))
            
            if cur.rowcount == 0:
                logger.warning(f"❌ 设备恢复失败，没有行被更新: license_id={license_id}, device_id={device_id}")
                return jsonify({'success': False, 'message': '设备恢复失败'}), 500
            
            # 记录恢复历史
            cur.execute('''
                INSERT INTO activation_history (license_id, action, device_id, details)
                VALUES (%s, 'restore', %s, %s)
            ''', (license_id, device_id, json.dumps({"reason": reason, "restored_by": "user"})))
            
            conn.commit()
            cur.close()
            
            logger.info(f"✅ 设备恢复成功: {device_id}")
            return jsonify({'success': True, 'message': '设备已恢复'})
            
        except Exception as db_error:
            logger.error(f"❌ 数据库操作失败: {str(db_error)}")
            if conn:
                conn.rollback()
            return jsonify({'success': False, 'message': f'数据库操作失败: {str(db_error)}'}), 500
        finally:
            if cur:
                cur.close()
        
    except Exception as e:
        logger.error(f"❌ 恢复设备失败: {str(e)}")
        return jsonify({'success': False, 'message': f'恢复失败: {str(e)}'}), 500

@app.route('/api/delete-device', methods=['POST'])
def delete_device():
    """删除设备"""
    try:
        data = request.get_json(force=True)
        activation_code = data.get('activation_code')
        email = data.get('email')
        device_id = data.get('device_id')
        reason = data.get('reason', '用户删除')
        
        if not activation_code or not email or not device_id:
            return jsonify({'success': False, 'message': '缺少必要参数'}), 400
        
        logger.info(f"🔍 收到删除设备请求: activation_code={activation_code}, email={email}, device_id={device_id}")
        
        # 验证许可证
        result = license_manager.verify_license_with_email(activation_code, email)
        if not result['valid']:
            logger.warning(f"❌ 许可证验证失败: {result.get('error', '未知错误')}")
            return jsonify({'success': False, 'message': result['error']}), 400
        
        license_id = result['license_id']
        logger.info(f"✅ 许可证验证成功: {license_id}")
        
        # 获取数据库连接
        conn = license_manager.get_connection()
        if not conn:
            logger.error("❌ 无法获取数据库连接")
            return jsonify({'success': False, 'message': '数据库连接失败'}), 500
        
        try:
            cur = conn.cursor()
            
            # 检查设备是否存在
            cur.execute('''
                SELECT 1 FROM device_activations 
                WHERE license_id = %s AND device_id = %s
            ''', (license_id, device_id))
            
            if not cur.fetchone():
                logger.warning(f"❌ 设备不存在: license_id={license_id}, device_id={device_id}")
                return jsonify({'success': False, 'message': '设备不存在'}), 404
            
            # 删除设备激活记录
            cur.execute('''
                DELETE FROM device_activations 
                WHERE license_id = %s AND device_id = %s
            ''', (license_id, device_id))
            
            if cur.rowcount == 0:
                logger.warning(f"❌ 设备删除失败，没有行被删除: license_id={license_id}, device_id={device_id}")
                return jsonify({'success': False, 'message': '设备删除失败'}), 500
            
            # 记录删除历史
            cur.execute('''
                INSERT INTO activation_history (license_id, action, device_id, details)
                VALUES (%s, 'delete', %s, %s)
            ''', (license_id, device_id, json.dumps({"reason": reason, "deleted_by": "user"})))
            
            conn.commit()
            cur.close()
            
            logger.info(f"✅ 设备删除成功: {device_id}")
            return jsonify({'success': True, 'message': '设备已删除'})
            
        except Exception as db_error:
            logger.error(f"❌ 数据库操作失败: {str(db_error)}")
            if conn:
                conn.rollback()
            return jsonify({'success': False, 'message': f'数据库操作失败: {str(db_error)}'}), 500
        finally:
            if cur:
                cur.close()
        
    except Exception as e:
        logger.error(f"❌ 删除设备失败: {str(e)}")
        return jsonify({'success': False, 'message': f'删除失败: {str(e)}'}), 500

@app.route('/api/verify-trial', methods=['POST'])
def verify_trial():
    """验证试用期API端点"""
    try:
        data = request.get_json()
        if not data:
            return jsonify({
                'success': False,
                'message': '请求数据为空'
            }), 400
        
        app_version = data.get('appVersion', '1.0.0')
        platform = data.get('platform', 'macOS')
        
        logger.info(f"🔍 收到试用期验证请求: 版本={app_version}, 平台={platform}")
        
        # 返回试用期信息（可以根据需要实现）
        return jsonify({
            'hasUsedTrial': False,
            'trialStartDate': None,
            'trialEndDate': None,
            'isActive': True,
            'remainingDays': 7
        })
        
    except Exception as e:
        logger.error(f"❌ 试用期验证过程中发生错误: {str(e)}")
        return jsonify({
            'success': False,
            'message': f'服务器内部错误: {str(e)}'
        }), 500

@app.route('/api/health', methods=['GET'])
def health_check():
    """健康检查端点"""
    return jsonify({
        'status': 'healthy',
        'timestamp': datetime.now().isoformat(),
        'version': '1.0.0'
    })

@app.route('/indexnow', methods=['POST'])
def indexnow():
    """
    IndexNow API 端点
    用于通知搜索引擎网站内容已更新
    支持 Microsoft IndexNow 和 Yandex IndexNow 协议
    """
    try:
        # 解析 JSON 请求体
        data = request.get_json()
        
        if not data:
            return jsonify({'error': 'Invalid request'}), 400
        
        # IndexNow 协议要求：host, key, urlList
        host = data.get('host', 'oneclip.cloud')
        key = data.get('key', '')  # API key (可选，用于验证)
        url_list = data.get('urlList', [])
        
        if not url_list:
            return jsonify({'error': 'urlList is required'}), 400
        
        # 记录索引请求（可选，用于日志）
        logger.info(f"📢 IndexNow 请求: {len(url_list)} 个URL需要索引")
        logger.info(f"   主机: {host}, Key: {key[:10] if key else 'N/A'}...")
        
        # IndexNow 协议只需要返回 200 OK
        # 搜索引擎会自行处理 URL 列表
        return jsonify({
            'status': 'ok',
            'message': f'已接收 {len(url_list)} 个URL的索引请求'
        }), 200
        
    except Exception as e:
        logger.error(f"❌ IndexNow 处理失败: {str(e)}")
        return jsonify({'error': 'Internal server error'}), 500

@app.route('/api/stats', methods=['GET'])
def get_stats():
    """获取统计信息端点"""
    try:
        stats = license_manager.get_license_statistics()
        return jsonify(stats)
    except Exception as e:
        logger.error(f"❌ 获取统计信息失败: {str(e)}")
        return jsonify({
            'error': f'获取统计信息失败: {str(e)}'
        }), 500

@app.route('/api/licenses', methods=['GET'])
def list_licenses():
    """列出许可证端点"""
    try:
        status = request.args.get('status', None)
        limit = int(request.args.get('limit', 50))
        
        licenses = license_manager.list_licenses(status, limit)
        return jsonify({
            'licenses': licenses,
            'count': len(licenses)
        })
    except Exception as e:
        logger.error(f"❌ 列出许可证失败: {str(e)}")
        return jsonify({
            'error': f'列出许可证失败: {str(e)}'
        }), 500

@app.route('/api/order/complete', methods=['GET'])
def get_complete_order_info():
    """
    🔒 安全的订单完成页面信息接口
    要求：必须同时提供订单号和邮箱，两者必须匹配
    限制：频率限制，防止暴力枚举
    """
    try:
        # 🔒 频率限制检查
        client_ip = request.remote_addr
        if not check_order_query_rate_limit(client_ip):
            logger.warning(f"⚠️ 订单完成页查询频率超限: {client_ip}")
            return jsonify({
                'success': False,
                'message': '查询过于频繁，请稍后再试'
            }), 429
        
        order_id = request.args.get('order_id', '').strip()
        email = request.args.get('email', '').strip()
        
        # 🔒 安全要求：必须同时提供订单号和邮箱
        if not order_id or not email:
            return jsonify({'success': False, 'message': '请同时提供订单号和邮箱地址'}), 400
        
        # 🔒 验证邮箱格式
        import re
        if not re.match(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$', email):
            return jsonify({
                'success': False,
                'message': '邮箱格式不正确'
            }), 400
        
        conn = license_manager.get_connection()
        if not conn:
            return jsonify({'success': False, 'message': '数据库连接失败'}), 500
        
        cur = conn.cursor(dictionary=True)
        
        # 🔒 安全查询：订单号和邮箱必须同时匹配（AND）
        cur.execute('''
            SELECT 
                po.order_id,
                po.email,
                po.plan,
                po.device_cap,
                po.activation_code,
                po.license_id,
                po.amount,
                po.status,
                po.created_at as purchase_time,
                l.valid_until,
                l.status as license_status
            FROM payment_orders po
            LEFT JOIN licenses l ON po.license_id = l.license_id
            WHERE po.order_id = %s AND po.email = %s
            ORDER BY po.created_at DESC
            LIMIT 1
        ''', (order_id, email))
        
        order = cur.fetchone()
        cur.close()
        
        if not order:
            # 🔒 模糊错误信息
            logger.info(f"订单完成页查询未匹配: order_id={order_id[:8]}***, email={email[:3]}***")
            return jsonify({'success': False, 'message': '订单信息不匹配，请检查订单号和邮箱'}), 404
        
        # 格式化数据
        plan_names = {
            'monthly': '月度版',
            'yearly': '年度版',
            'lifetime': '终身版'
        }
        
        # 🔒 只有已支付订单才返回完整激活码
        activation_code = order['activation_code'] if order['status'] == 'paid' else None
        
        result = {
            'success': True,
            'order': {
                'order_id': order['order_id'],
                'email': order['email'],
                'plan': order['plan'],
                'plan_name': plan_names.get(order['plan'], order['plan']),
                'device_cap': order['device_cap'],
                'activation_code': activation_code,
                'license_id': order['license_id'],
                'amount': float(order['amount']) if order['amount'] else 0,
                'status': order['status'],
                'purchase_time': (order['purchase_time'] + timedelta(hours=8)).strftime('%Y-%m-%d %H:%M:%S') if order['purchase_time'] else None,
                'valid_until': (order['valid_until'] + timedelta(hours=8)).strftime('%Y-%m-%d %H:%M:%S') if order['valid_until'] else None,
                'license_status': order['license_status'],
                'is_subscription': order['plan'] in ['monthly', 'yearly']
            }
        }
        
        logger.info(f"✅ 订单完成页查询成功: {order_id[:8]}***")
        return jsonify(result)
        
    except Exception as e:
        logger.error(f"❌ 获取订单信息失败: {str(e)}")
        return jsonify({'success': False, 'message': '获取订单信息失败'}), 500

@app.errorhandler(404)
def not_found(error):
    return jsonify({
        'success': False,
        'message': 'API端点不存在',
        'code': 'NOT_FOUND'
    }), 404

@app.errorhandler(405)
def method_not_allowed(error):
    return jsonify({
        'success': False,
        'message': 'HTTP方法不允许',
        'code': 'METHOD_NOT_ALLOWED'
    }), 405

# ==================== 管理工具：修复历史数据 ====================
@app.route('/api/admin/backfill-valid-until', methods=['POST'])
def admin_backfill_valid_until():
    auth = require_admin()
    if auth is not None:
        return auth
    try:
        conn = license_manager.get_connection()
        if not conn:
            return jsonify({'success': False, 'message': '数据库连接失败'}), 500
        cur = conn.cursor()
        # 月卡补 30 天
        cur.execute('''
            UPDATE licenses SET valid_until = DATE_ADD(issued_at, INTERVAL 30 DAY)
            WHERE plan='monthly' AND valid_until IS NULL
        ''')
        monthly_fixed = cur.rowcount
        # 年卡补 365 天
        cur.execute('''
            UPDATE licenses SET valid_until = DATE_ADD(issued_at, INTERVAL 365 DAY)
            WHERE plan='yearly' AND valid_until IS NULL
        ''')
        yearly_fixed = cur.rowcount
        conn.commit()
        cur.close()
        return jsonify({'success': True, 'monthly_fixed': monthly_fixed, 'yearly_fixed': yearly_fixed})
    except Exception as e:
        logger.error(f"❌ 修复历史数据失败: {str(e)}")
        return jsonify({'success': False, 'message': '修复失败'}), 500

# -------------------------
# 通用静态HTML文件路由（自动处理所有 .html 文件）
# 注意：此路由必须在所有特定路由之后，以避免拦截特定路由
# -------------------------
@app.route('/<path:filename>.html', methods=['GET'])
def serve_html(filename):
    """通用 HTML 文件服务路由 - 自动处理所有 .html 文件"""
    try:
        html_file = f'{filename}.html'
        logger.info(f"🔍 访问页面: {STATIC_DIR}/{html_file}")
        return send_from_directory(STATIC_DIR, html_file)
    except Exception as e:
        logger.error(f"❌ 页面加载失败: {html_file}, 错误: {str(e)}")
        return jsonify({'code': 'NOT_FOUND', 'message': 'API端点不存在', 'success': False}), 404

if __name__ == '__main__':
    print("🚀 启动 OneClip 许可证验证 API 服务器...")
    print("📡 服务器地址: http://0.0.0.0:3000")
    print("🔗 API端点: /api/verify-license-3")
    print("💡 健康检查: /api/health")
    print("📊 统计信息: /api/stats")
    print("📋 许可证列表: /api/licenses")
    print("=" * 50)
    
    # 启动服务器
    app.run(
        host='0.0.0.0',  # 监听所有IP
        port=3000,       # 端口3000
        debug=False,     # 生产环境关闭调试
        threaded=True    # 启用多线程
    )