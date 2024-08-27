# Import Modules

import os
from flask import Flask, request
import requests
from botocore.awsrequest import AWSRequest
from botocore.credentials import Credentials
from botocore.auth import SigV4Auth
import botocore.session
import json
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Define Variables
mservice2 = 'http://' + os.environ['DNSBackEnd2']
mservice2sec = 'http://' + os.environ['DNSBackEnd2'] + '/secure'
logger.info(mservice2)
logger.info(mservice2sec)

# Secure signer function

def signer(endpoint):
  session = botocore.session.Session()
  signer = SigV4Auth(session.get_credentials(), 'vpc-lattice-svcs', os.environ['Region'])
  endpoint = endpoint
  data = "null"
  headers = {}
  request = AWSRequest(method='GET', url=endpoint, data=data, headers=headers)
  request.context["payload_signing_enabled"] = False # payload signing is not supported
  signer.add_auth(request)
  prepped = request.prepare()
  return prepped

app = Flask(__name__)

@app.route("/",  methods=['GET'])
def app1resp():

    try:    
        requestdata = request.json
        m2aresp = requests.get(mservice2,json=requestdata)
        m2payload = json.loads(m2aresp.content)

        data = {
            'app1headers'       :   dict(request.headers),
            'app1url'           :   request.url,
            'app1message'       :   "Welcome to mservice1 - this is a simple open API - it calls mservice2",
            'app1information'   :   "Make a connection to the secure endpoint for secrets",
            'app2headers'       :   m2payload['app2headers'],
            'app2url'           :   m2aresp.url,
            'app2message'       :   m2payload['app2message'],
            'app2information'   :   m2payload['app2information'],
            'app2status'        :   m2aresp.status_code
        }

        if requestdata['portalidname'] == 'Anonymous':
            resp = 418
        else:
            resp = 200
        
        response = app.response_class(
            response=json.dumps(data),
            status=resp,
            mimetype='application/json'
        )
        return response
    
    except Exception as e:
        logger.info(e)

        data = {
            'app1headers'       :   '',
            'app1url'           :   '',
            'app1message'       :   '',
            'app1information'   :   '',
            'app2headers'       :   '',
            'app2url'           :   '',
            'app2message'       :   '',
            'app2information'   :   '',
            'app2status'        :   ''
        }

        response = app.response_class(
            response=json.dumps(data),
            status=500,
            mimetype='application/json'
        )
        return response

@app.route("/secure", methods=['GET','POST'])
def app1respsec():
    
    try:
        requestdata = request.json   
        headers = dict(request.headers)

    ## Comment out the below line when switching to signed requests
        m2asecresp = requests.get(mservice2sec,json=requestdata)
    ## Uncomment the below line when switching to signed requests
        #prepped = signer(mservice2sec)
        #m2asecresp = requests.get(prepped.url, headers=prepped.headers,json=requestdata)
            
        m2secpayload = json.loads(m2asecresp.content)
    
        if "X-Amz-Content-Sha256" in headers:
            resp = 200
            data = {
                'app1secmessage'        :   'Welcome to mservice1 (secure) - this contains sensitive cat treat information',
                'app1secinformation'    :   'Cats > that Dogs, it is a fact :-D ',
                'app1secdetails'        :   'House cats share 95.6 percent of their genetic makeup with tigers.',
                'app1secheaders'        :   dict(request.headers),
                'app1securl'            :   request.url,
                'app2secmessage'        :   m2secpayload['app2secmessage'],
                'app2secinformation'    :   m2secpayload['app2secinformation'],
                'app2secdetails'        :   m2secpayload['app2secdetails'],
                'app2secheaders'        :   m2secpayload['app2secheaders'],
                'app2securl'            :   m2asecresp.url,
                'app2secstatus'         :   m2asecresp.status_code
                }
        else:
            resp = 418
            data = {
                'app1secmessage'        :   'Welcome to mservice1 (secure) - this contains sensitive cat treat information',
                'app1secinformation'    :   '[For more info, sign your requests]',
                'app1secdetails'        :   '[For more info, sign your requests]',
                'app1secheaders'        :   dict(request.headers),
                'app1securl'            :   request.url,
                'app2secmessage'        :   m2secpayload['app2secmessage'],
                'app2secinformation'    :   m2secpayload['app2secinformation'],
                'app2secdetails'        :   m2secpayload['app2secdetails'],
                'app2secheaders'        :   m2secpayload['app2secheaders'],
                'app2securl'            :   m2asecresp.url,
                'app2secstatus'         :   m2asecresp.status_code
                }
        
        response = app.response_class(
            response=json.dumps(data),
            status=resp,
            mimetype='application/json'
        )

        return response
    
    except Exception as e:
        logger.info(e)

        data = {
            'app1secmessage'        :   '',
            'app1secinformation'    :   '',
            'app1secdetails'        :   '',
            'app1secheaders'        :   '',
            'app1securl'            :   '',
            'app2secmessage'        :   '',
            'app2secinformation'    :   '',
            'app2secdetails'        :   '',
            'app2secheaders'        :   '',
            'app2securl'            :   '',
            'app2secstatus'         :   ''
            }
        
        response = app.response_class(
            response=json.dumps(data),
            status=500,
            mimetype='application/json'
        )
        
        return response

@app.route("/health",  methods=['GET'])
def hc():
    response = app.response_class(
        status=200,
        mimetype='application/json'
    )
    return response

if __name__ == '__main__':
  app.run(debug=True,host="0.0.0.0",port=8081)