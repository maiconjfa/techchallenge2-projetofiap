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

from otel import init_otel

logging.basicConfig(level=logging.INFO)
log = logging.getLogger(__name__)

load_dotenv()
init_otel()

app = Flask(__name__)

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

def require_auth(f):
    @wraps(f)
    def decorated(*args, **kwargs):
        auth_header = request.headers.get('Authorization')
        if not auth_header:
            return jsonify({'error': 'Authorization header obrigatório'}), 401
        try:
            validate_url = f'{AUTH_SERVICE_URL}/validate'
            resp = requests.get(validate_url, headers={'Authorization': auth_header}, timeout=3)
            if resp.status_code != 200:
                return jsonify({'error': 'Chave de API inválida'}), 401
        except Exception as e:
            log.error(f'Erro auth: {e}')
            return jsonify({'error': 'Serviço de autenticação indisponível'}), 503
        return f(*args, **kwargs)
    return decorated

@app.route('/health')
def health():
    return jsonify({'status': 'ok'})
