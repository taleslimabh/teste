from flask import Flask
import os

app = Flask(__name__)

@app.route('/')
def hello():
    with open('/var/log/app_access.log', 'a') as f:
        f.write("Acesso recebido\n")
    return "Hello, Infrastructure Team!"

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
