# Import Modules
import json

def lambda_handler(event, context):
    
    # Obtaining headers and requestContent from event
    headers = event['headers']
    requestContext = event['requestContext']
    output = dict(**headers, **requestContext)

    if event['path'] == "/":
        
        body = json.loads(event['body'])

        data = {
            'app2message'       :   'Welcome to the mservice2 - this is a simple open API',
            'app2information'   :   'Make a connection to the secure endpoint for secrets',
            'app2headers'       :   output
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
                'app2secinformation'    :   'A word on feline capabilities',
                'app2secdetails'        :   'Cats can jump 5 times their own height',
                'app2secheaders'        :   output
                }
        else:
            resp = 418
            data = {
                'app2secmessage'        :   'Welcome to the mservice2(secure) - this contains sensitive cat treat information',
                'app2secinformation'    :   '[For more info, sign your requests]',
                'app2secdetails'        :   '[For more info, sign your requests]',
                'app2secheaders'        :   output
            }
    
        return {
            'statusCode': resp,
            'body': json.dumps(data)
        }