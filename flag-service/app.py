# flag-service with OTel
import os
import sys
import psycopg2
import requests
from psycopg2.extras import RealDictCursor
from psycopg2.pool import SimpleConnectionPool
from flask import Flask, request, jsonify
from dotenv import load_dotenv
from functools import wraps
import logging

from otel import init_otel, instrument_app

logging.basicConfig(level=logging.INFO)
log = logging.getLogger(__name__)

load_dotenv()

init_otel()

app = Flask(__name__)
app.logger.setLevel(logging.INFO)
instrument_app(app)

DATABASE_URL = os.getenv('DATABASE_URL')
AUTH_SERVICE_URL = os.getenv('AUTH_SERVICE_URL')

if not DATABASE_URL or not AUTH_SERVICE_URL:
    log.critical('Erro: DATABASE_URL e AUTH_SERVICE_URL devem ser definidos.')
    sys.exit(1)

try:
    pool = SimpleConnectionPool(1, 5, dsn=DATABASE_URL)
    log.info('Pool de conexões com o PostgreSQL inicializado.')
except psycopg2.OperationalError as e:
    log.critical(f'Erro fatal ao conectar ao PostgreSQL: {e}')
    sys.exit(1)

def require_auth(f):
    @wraps(f)
    def decorated(*args, **kwargs):
        auth_header = request.headers.get('Authorization')
        if not auth_header:
            return jsonify({'error': 'Authorization header obrigatório'}), 401
        try:
            validate_url = f'{AUTH_SERVICE_URL}/validate'
            response = requests.get(validate_url, headers={'Authorization': auth_header}, timeout=3)
            if response.status_code != 200:
                return jsonify({'error': 'Chave de API inválida'}), 401
        except Exception as e:
            log.error(f'Erro auth: {e}')
            return jsonify({'error': 'Serviço de autenticação indisponível'}), 503
        return f(*args, **kwargs)
    return decorated

@app.route('/health')
def health():
    return jsonify({'status': 'ok'})

@app.route('/flags', methods=['POST'])
@require_auth
def create_flag():
    data = request.get_json() or {}
    if 'name' not in data:
        return jsonify({'error': "'name' é obrigatório"}), 400
    name = data['name']
    description = data.get('description', '')
    is_enabled = data.get('is_enabled', False)
    conn = cur = None
    try:
        conn = pool.getconn()
        cur = conn.cursor(cursor_factory=RealDictCursor)
        cur.execute(
            'INSERT INTO flags (name, description, is_enabled, created_at, updated_at) VALUES (%s, %s, %s, NOW(), NOW()) RETURNING *',
            (name, description, is_enabled)
        )
        new_flag = cur.fetchone()
        conn.commit()
        return jsonify(new_flag), 201
    except psycopg2.IntegrityError:
        if conn: conn.rollback()
        return jsonify({'error': f"Flag '{name}' já existe"}), 409
    except Exception as e:
        if conn: conn.rollback()
        return jsonify({'error': 'Erro interno do servidor'}), 500
    finally:
        if cur: cur.close()
        if conn: pool.putconn(conn)


@app.route('/flags/<flag_name>', methods=['GET'])
@require_auth
def get_flag(flag_name):
    conn = cur = None
    try:
        conn = pool.getconn(); cur = conn.cursor(cursor_factory=RealDictCursor)
        cur.execute('SELECT * FROM flags WHERE name = %s', (flag_name,))
        row = cur.fetchone()
        if not row: return jsonify({'error':'not found'}), 404
        return jsonify(row), 200
    except Exception as e:
        log.error(f'get_flag: {e}'); return jsonify({'error':'internal'}), 500
    finally:
        if cur: cur.close()
        if conn: pool.putconn(conn)
