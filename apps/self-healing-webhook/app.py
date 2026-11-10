from flask import Flask, request, jsonify
import os
import subprocess
import logging
import sys

logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
log = logging.getLogger(__name__)

app = Flask(__name__)

VALID_SERVICES = {
    'auth-service',
    'analytics-service',
    'evaluation-service',
    'flag-service',
    'targeting-service'
}

@app.route('/healthz', methods=['GET'])
def healthz():
    return jsonify({'status': 'ok'}), 200

@app.route('/webhook', methods=['POST'])
def webhook():
    try:
        payload = request.get_json(force=True, silent=True)
        if not payload:
            log.warning('Empty payload received')
            return jsonify({'error': 'empty payload'}), 400

        alerts = payload.get('alerts', [])
        for alert in alerts:
            labels = alert.get('labels', {})
            service = labels.get('service') or labels.get('job')
            if service in VALID_SERVICES:
                namespace = 'feature-flags'
                cmd = ['kubectl', 'rollout', 'restart', f'deployment/{service}', '-n', namespace]
                try:
                    result = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=120)
                    if result.returncode == 0:
                        log.info(f'Restarted deployment/{service} in {namespace}')
                    else:
                        log.error(f'Failed to restart {service}: {result.stderr.decode(errors="ignore")}')
                except Exception as e:
                    log.error(f'Error restarting {service}: {e}')
            else:
                log.info(f'No action for service/job: {service}')
        return jsonify({'status': 'processed'}), 200
    except Exception as e:
        log.error(f'Webhook error: {e}')
        return jsonify({'error': str(e)}), 500

if __name__ == '__main__':
    port = int(os.getenv('PORT', '8080'))
    app.run(host='0.0.0.0', port=port)
