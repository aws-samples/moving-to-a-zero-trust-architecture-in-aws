# Import Modules
import json

def lambda_handler(event, context):
    
    headers = event['headers']
    print(headers)
    
    if event['path'] == "/":
        
        body = json.loads(event['body'])

        data = {
            'app2message'       :   'Welcome to the mservice2 - this is a simple open API',
            'app2information'   :   'Meeoow - Make a connection to the secure endpoint for secrets',
            'app2headers'       :   headers
        }
    
        if body['portalidname'] == 'Anonymous':
            resp = 418
        else:
            resp = 200
        
        
        return {
            'statusCode': resp,
            'body': json.dumps(data)
        }
    
    else:
    
    ### Check for Connection Type
  
        if "x-amz-content-sha256" in headers:
            resp = 200
            data = {
                'app2secmessage'        :   'Welcome to the mservice2(secure) - this contains sensitive cat treat information',
                'app2secinformation'    :   'The cat treats are located in the upper kitchen cupboard',
                'app2secdetails'        :   'Folks are out - you have the run of the house',
                'app2secheaders'        :   headers
                }
        else:
            resp = 418
            data = {
                'app2secmessage'        :   'Welcome to the mservice2(secure) - this contains sensitive cat treat information',
                'app2secinformation'    :   '[For more info, sign your requests]',
                'app2secdetails'        :   '[For more info, sign your requests]',
                'app2secheaders'        :   headers
            }
    
        return {
            'statusCode': resp,
            'body': json.dumps(data)
        }