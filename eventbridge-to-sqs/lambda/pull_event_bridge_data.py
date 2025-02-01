import json
import boto3

eventbridge = boto3.client('events')

def lambda_handler(event, context):
    for record in event['Records']:
        try:
            # Extract the EventBridge detail from SQS message
            message = json.loads(record['body'])
            detail = message.get('detail', {})
            
            # Validate the expected payload
            if detail.get('name') == 'test':
                # Process your payload here
                print("Received valid payload:", detail)
                
                # Forward to destination EventBus
                eventbridge.put_events(
                    Entries=[{
                        'Source': 'processed.events',
                        'DetailType': 'SuccessfulProcessing',
                        'Detail': json.dumps(detail),
                        'EventBusName': 'processed-events-bus'
                    }]
                )
            else:
                print("Unexpected payload format:", detail)
                raise ValueError("Invalid payload format")
                
        except Exception as e:
            print("Processing failed:", str(e))
            raise

    return {'statusCode': 200}