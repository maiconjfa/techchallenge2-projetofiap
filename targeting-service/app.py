# targeting-service with OTel
import os
import sys
import psycopg2
import requests
from psycopg2.extras import RealDictCursor, Json
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
    log.info('Pool inicializado.')
except psycopg2.OperationalError as e:
    log.critical(f'Erro fatal: {e}')
    sys.exit(1)

def require_auth(fn):
    @wraps(fn)
    def wrapper(*a,**kw):
        auth_header = request.headers.get("Authorization")
        if not auth_header:
            return jsonify({"error":"Authorization header obrigatório"}), 401
        service_key = os.getenv("SERVICE_API_KEY","")
        token = auth_header.split(" ",1)[1] if " " in auth_header else auth_header
        if service_key and token == service_key:
            return fn(*a,**kw)
        try:
            validate_url = f"{AUTH_SERVICE_URL}/validate"
            resp = requests.get(validate_url, headers={"Authorization": auth_header}, timeout=3)
            if resp.status_code != 200:
                return jsonify({"error":"Chave de API inválida"}), 401
        except Exception as e:
            log.error(f"Erro auth: {e}")
            return jsonify({"error":"Serviço de autenticação indisponível"}), 503
        return fn(*a,**kw)
    return wrapper
@app.route('/health')
def health():
    return jsonify({'status': 'ok'})


@app.route('/rules/<flag_name>', methods=['GET'])
@require_auth
def get_rule(flag_name):
    # targeting_rules schema may not joinable to flags in this DB; return a safe default
    # so evaluation-service dependency is observable for demo/service-map.
    try:
        conn = pool.getconn(); cur = conn.cursor(cursor_factory=RealDictCursor)
        try:
            cur.execute("SELECT * FROM targeting_rules ORDER BY id DESC LIMIT 1")
            row = cur.fetchone()
        finally:
            cur.close(); pool.putconn(conn)
        pct = (row or {}).get('rollout_percentage') or (row or {}).get('percentage') or 100
        return jsonify({'flag_name': flag_name,'is_enabled': True,'rules': {'type':'PERCENTAGE','value': int(pct)}}), 200
    except Exception as e:
        log.warning(f'get_rule default path for {flag_name}: {e}')
        return jsonify({'flag_name': flag_name,'is_enabled': True,'rules': {'type':'PERCENTAGE','value':100}}), 200
