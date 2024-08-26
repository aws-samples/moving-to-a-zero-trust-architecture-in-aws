#import modules

import os
from flask import Flask, render_template, request, redirect, url_for
import requests
from botocore.awsrequest import AWSRequest
from botocore.credentials import Credentials
from botocore.auth import SigV4Auth
import botocore.session
import json
import base64
import jwt
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

#define variables

img = os.path.join('static','images')
global portal
render = {}

mservice1 = 'http://' + os.environ['DNSBackEnd1']
mservice1sec = 'http://' + os.environ['DNSBackEnd1'] + '/secure'

avaurl = 'https://public-keys.prod.verified-access.{REGION}.amazonaws.com/'

# Secure signer function
def signer(endpoint):
  session = botocore.session.Session()
  signer = SigV4Auth(session.get_credentials(), 'vpc-lattice-svcs', '{REGION}')
  endpoint = endpoint
  data = "null"
  headers = {}
  request = AWSRequest(method='GET', url=endpoint, data=data, headers=headers)
  request.context["payload_signing_enabled"] = False # payload signing is not supported
  signer.add_auth(request)
  prepped = request.prepare()
  return prepped

# AVA depacker function
def depacker(portal):
  
  if "X-Amzn-Ava-User-Context" in portal:

    #Decode the headers
    encoded_jwt = portal['X-Amzn-Ava-User-Context']
    jwt_headers = encoded_jwt.split('.')[0]
    decoded_jwt_headers = base64.b64decode(jwt_headers)
    decoded_jwt_headers = decoded_jwt_headers.decode("utf-8")
    decoded_json = json.loads(decoded_jwt_headers)
    kid = decoded_json['kid']
    
    #Get the public key
    url = avaurl + kid
    req = requests.get(url)
    pub_key = req.text
    
    #Get the payload
    payload = jwt.decode(encoded_jwt, pub_key, algorithms=['ES384'])
  
    ptype   = os.path.join(img,'verifiedaccess.png')
    pid     = os.path.join(img, payload['user']['user_name'] + '.png')
    pidname = payload['user']['user_name']

  else:
    ptype = os.path.join(img, 'clientvpn.png')
    pid   = os.path.join(img, 'mrx.png')
    pidname = "Anonymous"

  response = {
    "portaltype"    : ptype,
    "portalid"      : pid,
    "portalidname"  : pidname
  }
  return response

# Portal Application
app = Flask(__name__)

@app.route('/', methods=['GET'])
def getBaselinePictures():
  
  portal = depacker(dict(request.headers))

  render = {
    "app1img"               : os.path.join(img,'wait.jpg'),
    "app1secimg"            : os.path.join(img,'wait.jpg'),
    "app2img"               : os.path.join(img,'wait.jpg'),
    "app2secimg"            : os.path.join(img,'wait.jpg'),
    'portalmessage'         : "Welcome to the Feline microservice portal",
    'portalinformation'     : "Build a zero-trust layer to reveal feline imagery" if portal['portalidname'] == 'Anonymous' else "Welcome " + portal['portalidname'] + " - check the cat pictures (if you can) !",
    'portalheaders'         : dict(request.headers),
    "portaltype"            : portal['portaltype'],
    "portalid"              : portal['portalid'],
    "portalidname"          : portal['portalidname'],
    'app1headers'           : '',
    'app1url'               : '',
    'app1status'            : '',
    'app1message'           : '',
    'app1information'       : '',
    'app2headers'           : '',
    'app2url'               : '',
    'app2message'           : '',
    'app2information'       : '',
    'app2status'            : '',
    'app1secstatus'         : '',
    'app1secmessage'        : '',
    'app1secinformation'    : '',
    'app1secdetails'        : '',
    'app1secheaders'        : '',
    'app1securl'            : '',
    'app2secmessage'        : '',
    'app2secinformation'    : '',
    'app2secdetails'        : '',
    'app2secheaders'        : '',
    'app2securl'            : '',
    'app2secstatus'         : ''
  }

  return render_template('index.html', render=render)

@app.route('/run', methods=['GET','POST'])
def runapp():

  portal = depacker(dict(request.headers))
  
  portaldata = {
      'portalmessage'         : "Welcome to the Feline microservice portal",
      'portalinformation'     : "Build a zero-trust layer to reveal feline imagery" if portal['portalidname'] == 'Anonymous' else "Welcome " + portal['portalidname'] + " - check the cat pictures (if you can) !",
      'portalheaders'         : dict(request.headers),
      'portaltype'            : portal['portaltype'],
      'portalid'              : portal['portalid'],
      'portalidname'          : portal['portalidname'],
  }

  try:
    logger.info("Attempting connection to mservice1 unsecured endpoint")
    m1aresp = requests.get(mservice1,json=portal)
    payload = json.loads(m1aresp.content)

    render1 = {
      'app1img'               : os.path.join(img,'mservice1_open.png') if m1aresp.status_code == 200 else os.path.join(img,'teapot.png') if m1aresp.status_code == 418 else os.path.join(img,'wait.png'),
      'app2img'               : os.path.join(img,'mservice2_open.png') if payload['app2status'] == 200 else os.path.join(img,'teapot.png') if payload['app2status'] == 418 else os.path.join(img,'wait.png'),
      'app1headers'           : payload['app1headers'],
      'app1url'               : payload['app1url'],
      'app1status'            : m1aresp.status_code,
      'app1message'           : payload['app1message'],
      'app1information'       : payload['app1information'],
      'app2headers'           : payload['app2headers'],
      'app2url'               : payload['app2url'],
      'app2message'           : payload['app2message'],
      'app2information'       : payload['app2information'],
      'app2status'            : payload['app2status']
    }
    render.update(render1)

  except Exception as e:
    logger.info("There was an issue connecting to mservice1 unsecured endpoint - error deatils: " + str(e))

    render1 = {
      'app1img'               : os.path.join(img,'wait.jpg'),
      'app2img'               : os.path.join(img,'wait.jpg'),
      'app1headers'           : "Communication Error",
      'app1url'               : "Communication Error",
      'app1status'            : "Communication Error",
      'app1message'           : "Communication Error",
      'app1information'       : "Communication Error",
      'app2headers'           : "Communication Error",
      'app2url'               : "Communication Error",
      'app2message'           : "Communication Error",
      'app2information'       : "Communication Error",
      'app2status'            : "Communication Error"
    }
    render.update(render1)

  try:
    logger.info("Attempting connection to mservice1 secured endpoint")
  ## Comment out the below line when switching to signed requests
    m1bresp = requests.get(mservice1sec)
  ## Uncomment the below two lines when switching to signed requests
# prepped = signer(mservice1sec)
# m1bresp = requests.get(prepped.url,headers=prepped.headers,json=portal)

    payload2 = json.loads(m1bresp.content)
    render2 = {
      'app1secimg'            : os.path.join(img,'mservice1_secure.png') if m1bresp.status_code == 200 else os.path.join(img,'teapot.png') if m1bresp.status_code == 418 else os.path.join(img,'wait.png'),
      'app2secimg'            : os.path.join(img,'mservice2_secure.png') if payload2['app2secstatus'] == 200 else os.path.join(img,'teapot.png') if payload2['app2secstatus'] == 418 else os.path.join(img,'wait.png'),
      'app1secstatus'         : m1bresp.status_code,
      'app1secmessage'        : payload2['app1secmessage'],
      'app1secinformation'    : payload2['app1secinformation'],
      'app1secdetails'        : payload2['app1secdetails'],
      'app1secheaders'        : payload2['app1secheaders'],
      'app1securl'            : payload2['app1securl'],
      'app2secmessage'        : payload2['app2secmessage'],
      'app2secinformation'    : payload2['app2secinformation'],
      'app2secdetails'        : payload2['app2secdetails'],
      'app2secheaders'        : payload2['app2secheaders'],
      'app2securl'            : payload2['app2securl'],
      'app2secstatus'         : payload2['app2secstatus']
    }

    render.update(render2)

  except Exception as e:
    logger.info("There was an issue connecting to mservice1 secured endpoint - error deatils: " + str(e))

    render2 = {
      'app1secimg'            : os.path.join(img,'wait.jpg'),
      'app2secimg'            : os.path.join(img,'wait.jpg'),
      'app1secstatus'         : "Communication Error",
      'app1secmessage'        : "Communication Error",
      'app1secinformation'    : "Communication Error",
      'app1secdetails'        : "Communication Error",
      'app1secheaders'        : "Communication Error",
      'app1securl'            : "Communication Error",
      'app2secmessage'        : "Communication Error",
      'app2secinformation'    : "Communication Error",
      'app2secdetails'        : "Communication Error",
      'app2secheaders'        : "Communication Error",
      'app2securl'            : "Communication Error",
      'app2secstatus'         : "Communication Error"
    }

    render.update(render2)

  render.update(portaldata)
  return render_template('index.html', render=render)

@app.route("/health",  methods=['GET'])
def hc():
    response = app.response_class(
        status=200,
        mimetype='application/json'
    )
    return response

if __name__ == '__main__':
  app.run(debug=True,host="0.0.0.0",port=8080)